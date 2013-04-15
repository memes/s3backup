#!/bin/sh
#
# s3backup.sh: script to backup to Amazon S3 via Duplicity and GPG
# Copyright (C) 2010 Matthew Emes <memes@matthewemes.com>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program.  If not, see <http://www.gnu.org/licenses/>.
#

# Which directory should have the ACL, dpkg/debconf and/or yum backups
PREP_BACKUP_DIR=${PREP_BACKUP_DIR:-"/var/local/backups"}

# How many full backups to maintain on S3; full backups and all related
# incremental backups associated with the obsolete backups will be removed.
# Defaults to 2, which means 2 full backups and up to
# ($BACKUP_FULL_TIMESPEC - 1) x 2 incremental backups will be maintained in s3.
# Older backups will be removed.
BACKUP_FULL_COPIES=${BACKUP_FULL_COPIES:-2}

# How often to perform a full backup instead of an incremental backup; defaults
# to 30 days.
BACKUP_FULL_TIMESPEC=${BACKUP_FULL_TIMESPEC:-"30D"}

# Location of the include list; defaults to include.list in the location
# specified by $PREP_BACKUP_DIR above
BACKUP_INCLUDE_LIST=${BACKUP_INCLUDE_LIST:-"${PREP_BACKUP_DIR}/include.list"}

# Set to non-empty string to verify after backup; defaults to not performing a
# verify because I cannot spare the time!
VERIFY_AFTER_BACKUP=${VERIFY_AFTER_BACKUP:-""}

# Location to env executable; used to set environment variables for a
# sub-process without changing current environment
ENV_EXEC=${ENV_EXEC:-$(which env)}

# Compression program to use; may be any command line compressor that can take a
# single source file argument to compress
COMPRESS_EXEC=${COMPRESS_EXEC:-$(which bzip2)}

# Volume of duplicity files in Mb; defaults to 250Mb
DUPLICITY_VOLSIZE=${DUPLICITY_VOLSIZE:-250}

# Find executable to use
FIND=${FIND:-$(which find)}

# Default backup file spec if there is not a specified include list; defaults to
# backup all files in /home
DEFAULT_BACKUP_GLOB=${DEFAULT_BACKUP_GLOB:-"/home/**"}

# Readlink executable
READLINK=${READLINK:-$(which readlink)}

# Basename executable
BASENAME=${BASENAME:-$(which basename)}

# Dirname executable
DIRNAME=${DIRNAME:-$(which dirname)}

# Hostname executable
HOSTNM=${HOSTNM:-$(which hostname)}

# Grep executable
GREP=${GREP:-$(which grep)}

# getfacl executable; if invalid or not found then a backup of file ACL will not
# be generated
GETFACL=${GETFACL:-$(which getfacl)}

# Dpkg executable; if invalid or not found then a list of installed .deb files
# will not be generated
DPKG=${DPKG:-$(which dpkg)}

# Debconf backup executable; defaults to debconf-get-selections if installed.
# If missing or not found then the debconf database will not be backed up to a
# plain file; note the debconf database binaries will still be backed up if
# /var/cache/debconf is included in backup set.
DEBCONF_BACKUP=${DEBCONF_BACKUP:-$(which debconf-get-selections)}

# Yum executable; if invalid or not found then a list of installed .rpm files
# will not be generated
YUM=${YUM:-$(which yum)}

# Number of days of ACL, dpkg/debconf and/or yum lists to keep locally before
# deleting
ACL_PKG_DAYS_TO_KEEP=${ACL_PKG_DAYS_TO_KEEP:-7}

# Duplicity executable to use
DUPLICITY=${DUPLICITY:-$(which duplicity)}

# Duplicity options to use; see duplicity manual for options
DUPLICITY_OPTS=${DUPLICITY_OPTS:-"--s3-use-new-style -vERROR --name=$(${HOSTNM} -s)"}

# Temporary directory for duplicity files; defaults to $PREP_BACKUP_DIR
DUPLICITY_TEMP_DIR=${DUPLICITY_TEMP_DIR:-${PREP_BACKUP_DIR}}

# Location of duplicity local cache files; defaults to $PREP_BACKUP_DIR
DUPLICITY_ARCHIVE_DIR=${DUPLICITY_ARCHIVE_DIR:-${PREP_BACKUP_DIR}}

# Function to record an error message
error()
{
    echo "$0: Error: $*" >&2
    exit 0
}

# Function to issue a warning message
warn()
{
    echo "$0: Warning: $*" >&2
    return 0
}

# Function to make sure environment is setup
check()
{
    local missing_env=
    [ -z "${AWS_ACCESS_KEY_ID}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$AWS_ACCESS_KEY_ID"
    [ -z "${AWS_SECRET_ACCESS_KEY}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$AWS_SECRET_ACCESS_KEY"
    [ -z "${S3_BUCKET_PREFIX}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$S3_BUCKET_PREFIX"
    [ -z "${ENV_EXEC}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$ENV_EXEC"
    [ -z "${COMPRESS_EXEC}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$COMPRESS_EXEC"
    [ -z "${DUPLICITY}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$DUPLICITY"
    [ -z "${FIND}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$FIND"
    [ -z "${READLINK}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$READLINK"
    [ -z "${BASENAME}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$BASENAME"
    [ -z "${DIRNAME}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$DIRNAME"
    [ -z "${HOSTNM}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$HOSTNM"
    [ -z "${GREP}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$GREP"
    [ -z "${PREP_BACKUP_DIR}" ] && \
	missing_env="${missing_env}${missing_env:+, }\$PREP_BACKUP_DIR"
    [ -n "${missing_env}" ] && \
	error "check: the following environment variables are unset: ${missing_env}"
    [ -z "${BACKUP_INCLUDE_LIST}" ] && \
	warn "check: \$BACKUP_INCLUDE_LIST is unset, only files matching ${DEFAULT_BACKUP_GLOB} will be backed up"
    [ -n "${BACKUP_INCLUDE_LIST}" -a ! -r "${BACKUP_INCLUDE_LIST}" ] && \
	warn "check: \$BACKUP_INCLUDE_LIST is unreadable, only files matching ${DEFAULT_BACKUP_GLOB} will be backed up"

    local missing_exec=
    [ -x "${ENV_EXEC}" ] || \
	missing_exec="${missing_exec}${missing_exec:+, }${ENV_EXEC}"
    [ -x "${COMPRESS_EXEC}" ] || \
	missing_exec="${missing_exec}${missing_exec:+, }${COMPRESS_EXEC}"
    [ -x "${DUPLICITY}" ] || \
	missing_exec="${missing_exec}${missing_exec:+, }${DUPLICITY}"
    [ -x "${FIND}" ] || \
	missing_exec="${missing_exec}${missing_exec:+, }${FIND}"
    [ -x "${READLINK}" ] || \
	missing_exec="${missing_exec}${missing_exec:+, }${READLINK}"
    [ -x "${BASENAME}" ] || \
	missing_exec="${missing_exec}${missing_exec:+, }${BASENAME}"
    [ -x "${DIRNAME}" ] || \
	missing_exec="${missing_exec}${missing_exec:+, }${DIRNAME}"
    [ -x "${HOSTNM}" ] || \
	missing_exec="${missing_exec}${missing_exec:+, }${HOSTNM}"
    [ -x "${GREP}" ] || \
	missing_exec="${missing_exec}${missing_exec:+, }${GREP}"
    [ -n "${missing_exec}" ] && \
	error "check: the following executables are missing: ${missing_exec}"

    # Make sure that the number of full days is specified and is a number; if
    # not lets blank it out
    [ -n "${BACKUP_FULL_COPIES}" -a \
	${BACKUP_FULL_COPIES} -ge 1 >/dev/null 2>/dev/null ] || \
	BACKUP_FULL_COPIES=""

    # If GNUPGHOME is specified, make sure it is in the environment
    [ -n "${GNUPGHOME}" ] && export GNUPGHOME
    return 0
}

# Function to prepare for backup; make copies of currently installed packages,
# debconf settings, etc.
prep()
{
    local backupdir=$(${READLINK} -f ${PREP_BACKUP_DIR})
    [ -d "${backupdir}" ] && mkdir -p "${backupdir}"
    [ -d "${backupdir}" ] || \
	error "prep: ${backupdir} does not exist"
    local suffix="$(date '+%Y%m%d%H%M%S').$(${BASENAME} $0).backup"
    # Backup pkg, debconf and acl definitions
    if [ -n "${DPKG}" -a -x "${DPKG}" ]; then
	${DPKG} --get-selections > ${backupdir}/dpkg.${suffix}
	[ -s "${backupdir}/dpkg.${suffix}" ] && \
            ${COMPRESS_EXEC} ${backupdir}/dpkg.${suffix}
    fi
    if [ -n "${DEBCONF_BACKUP}" -a -x "${DEBCONF_BACKUP}" ]; then
	${DEBCONF_BACKUP} > ${backupdir}/debconf.${suffix}
	[ -s "${backupdir}/debconf.${suffix}" ] && \
            ${COMPRESS_EXEC} ${backupdir}/debconf.${suffix}
    fi
    if [ -n "${YUM}" -a -x "${YUM}" ]; then
	${YUM} list installed > ${backupdir}/yum.${suffix}
	[ -s "${backupdir}/dpkg.${suffix}" ] && \
            ${COMPRESS_EXEC} ${backupdir}/yum.${suffix}
    fi
    if [ -n "${GETFACL}" -a -x "${GETFACL}" ]; then
	[ -s "${backupdir}/acl.${suffix}" ] && \
	    rm -f "${backupdir}/acl.${suffix}"
	${FIND} -H / | ${GREP} -Ev '^/(dev|media|mnt|proc|run|sys|tmp)/' | \
	    ${GETFACL} -pn - > ${backupdir}/acl.${suffix} 2>/dev/null
	[ -s "${backupdir}/acl.${suffix}" ] && \
	    ${COMPRESS_EXEC} ${backupdir}/acl.${suffix}
    else
	warn "prep: cannot make backup of ACLs: install acl package to get this functionality in future"
    fi
    # Delete older copies of the acl and package lists
    [ -n "${ACL_PKG_DAYS_TO_KEEP}" ] && \
	${FIND} ${backupdir} -ctime +${ACL_PKG_DAYS_TO_KEEP} \
	     -regextype posix-extended \
             -regex ".*\.[0-9]{14}.$(${BASENAME} $0)\.backup(\.(gz|bz2|Z))?$" \
             -exec rm -f {} \;
}

# Run duplicity with supplied arguments
do_duplicity()
{
    local include_glob_arg=
    [ -n "${BACKUP_INCLUDE_LIST}" -a -r "${BACKUP_INCLUDE_LIST}" ] && \
	include_glob_arg="--include-globbing-filelist=${BACKUP_INCLUDE_LIST}"
    ${ENV_EXEC} AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
        AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
        GNUPGHOME="${GNUPGHOME}" \
        PASSPHRASE="${PASSPHRASE}" \
        SIGN_PASSPHRASE="${SIGN_PASSPHRASE}" \
        ${DUPLICITY} ${DEBUG:+"--dry-run"} \
        ${DUPLICITY_OPTS} \
        ${DUPLICITY_TEMP_DIR:+"--tempdir=${DUPLICITY_TEMP_DIR}"} \
        ${DUPLICITY_ARCHIVE_DIR:+"--archive-dir=${DUPLICITY_ARCHIVE_DIR}"} \
        ${DUPLICITY_VOLSIZE:+"--volsize=${DUPLICITY_VOLSIZE}"} \
	${SIGN_KEY:+"--sign-key=${SIGN_KEY}"} \
	${ENCRYPT_KEY:+"--encrypt-key=${ENCRYPT_KEY}"} \
	${GPG_OPTIONS:+"--gpg-options=\"${GPG_OPTIONS}\""} \
	${include_glob_arg:-"--include=\"${DEFAULT_BACKUP_GLOB}\""} \
	--exclude="**" \
        $*
}

# Pre-backup clean; remove files from incomplete backups from s3
pre_backup_clean()
{
    # Cleanup any incomplete backups
    do_duplicity cleanup --force ${S3_BUCKET_PREFIX}/$(${HOSTNM} -s)
    local retval=$?
    [ ${retval} -eq 0 ] || \
	warn "pre_backup_clean: duplicity returned error code: $?"
    return ${retval}
}

# Post-backup clean; remove all but the required number of complete backup
# sets
post_backup_clean()
{
    [ -n "${BACKUP_FULL_COPIES}" ] && \
	do_duplicity remove-all-but-n-full ${BACKUP_FULL_COPIES} --force \
            ${S3_BUCKET_PREFIX}/$(${HOSTNM} -s)
    local retval=$?
    [ ${retval} -eq 0 ] || \
	warn "post_backup_clean: duplicity returned error code: $?"
    return ${retval}
}

# Perform the backup steps
backup()
{   
    pre_backup_clean
    prep

    # Do the backup
    do_duplicity incremental \
	${BACKUP_FULL_TIMESPEC:+"--full-if-older-than=${BACKUP_FULL_TIMESPEC}"} \
        / ${S3_BUCKET_PREFIX}/$(${HOSTNM} -s) $*
    [ $? -eq 0 ] || error "backup: duplicity returned error code: $?"
    post_backup_clean
}

# Verify the backup; Note -v4 argument to make sure differences are
# listed even if rest of duplicity calls use a lower verbosity
verify()
{
    do_duplicity verify -v4 ${S3_BUCKET_PREFIX}/$(${HOSTNM} -s) / $*
    local retval=$?
    [ ${retval} -eq 0 ] || \
	warn "verify: duplicity returned error code: $?"
    return ${retval}
}

# Restore the file/folder from remote backup using supplied arguments.
# No sanity checking is performed by the script but there are limited sanity
# checks in duplicity itself.
#
# Note: since the backup starts at root, it is necessary to omit the leading /
# from the path of the file or directory to restore.
#
# Note: to restore the contents of a folder, end the file path with a trailing
# / and duplicity will restore the files and folders within the directory to
# the specified restore folder, but note that the folder itself will not be
# created. 
#
# Example restore home/memes/projects/ /home/memes/from_backup 
#  restores the latest files in /home/memes/projects and sub-dirs to
#  /home/memes/from_backup but does not create the projects folder, just the
#  contents of it 
#
# Example restore -t 3D home/memes/foo/bar /home/memes/from_backup
#  restores the file /home/memes/foo/bar to /home/memes/from_backup/bar as it
#  was 3 days ago
restore()
{
    local args=
    local paths=
    while [ -n "$1" ]; do
	case "$1" in
	    -*)
		args="${args} $1 $2"
		shift
		shift
		;;
	    *)
		if [ -z "${paths}" ]; then
		    paths="--file-to-restore $1"
		else
		    paths="${paths} $1"
		fi
		shift
	esac
    done
    do_duplicity restore ${args} ${S3_BUCKET_PREFIX}/$(${HOSTNM} -s) ${paths}
    local retval=$?
    [ ${retval} -eq 0 ] || \
	warn "restore: duplicity returned error code: $?"
    return ${retval}
}
    
# Exit if there is another copy of this script running
[ -r /var/run/$(${BASENAME} $0) ] && \
    error "another backup is running: /var/run/$(${BASENAME} $0) is present"
trap "rm -f /var/run/$(${BASENAME} $0)" 0 1 2 3 15
echo $$ > /var/run/$(${BASENAME} $0)

# Make sure the environment is ready to for use and load overrides from file
RC_FILE=${RC_FILE:-$(${DIRNAME} `${READLINK} -f $0`)/s3backup.rc}
[ -s ${RC_FILE} ] && . ${RC_FILE}
check

case "$1" in
    restore)
	shift
	restore $*
	;;
    verify)
	shift
	verify $*
	;;
    backup)
	shift
	backup $*
	# Disabled by default; set to a non-empty value to verify all files
	# in globbing set after a backup. Note this is a full verify and
	# requires access to the encryption key so if using dual keys for
	# signing and encryption there could be issues
	[ -n "${VERIFY_AFTER_BACKUP}" ] && verify $*
	;;
    *)
	backup $*
	;;
esac

# Reset environment
[ -n "${PASSPHRASE}" ] && PASSPHRASE=
[ -n "${SIGN_PASSPHRASE}" ] && SIGN_PASSPHRASE=
[ -n "${GNUPGHOME}" ] && GNUPGHOME=
[ -n "${AWS_ACCESS_KEY_ID}" ] && AWS_ACCESS_KEY_ID=
[ -n "${AWS_SECRET_ACCESS_KEY}" ] && AWS_SECRET_ACCESS_KEY=
exit 0
