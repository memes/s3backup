Automated backup to Amazon S3 using duplicity
=============================================

s3backup is a simple shell script designed to do one thing; backup
your Linux computer to an Amazon S3 bucket with GPG encryption. All
the heavy lifting is done by duplicity, with the script automating
common options and making the process easier to use.

Requirements
------------
1.  duplicity

2.  env

3.  a compression utility (defaults to bzip2)

4.  find

5.  readlink, basename, dirname

6.  hostname

7.  grep

8.  Bourne-like shell (bash, dash, etc)

9.  gnupg

10. hostname

11. date

12. getfacl (optional)

13. dpkg/debconf and/or yum depending on distribution in use

Quick installation
------------------
1.  Download or clone s3backup.sh from [github][1]

2.  Install in a folder accessible by root; default assumption is that
    the folder /var/local/backups will be used

3.  Create an rc file to provide AWS credentials, GnuPG keys and other
    options in the same location as the `s3backup.sh`
    script. Optionally, create an include list to control exactly 
    what gets backed up in the same directory as the
    `s3backup.sh`. There are sample files in the `examples`
    folder.

    E.g. after configuration, assuming use of `/var/local/backups` as
    a base directory, there would be three files:-
    1. `/var/local/backups/s3backup.sh`: the backup script,
    2. `/var/local/backups/s3backup.rc`: the configuration parameters
    for backup, and
    3. `/var/local/backups/include.list`: the duplicity include list;
    see duplicity manual for format

4. Create a cron entry to execute the backup script; I prefer to make
   this send email so I see the results of a backup and get email if a
   backup is still running.

Advanced installation
---------------------

By default the script assumes that the configuration file is located
in the same directory as `s3backup.sh`, and that a single base
directory should be used for all temporary files, duplicity local
files, etc. This is fine, but there may be a need to separate out temp
files, or to use a separate directory for duplicity local cache. All
parameters in the script are expressed as environment variables, so
they can be overridden on an ad-hoc basis via command line or more
permanently using `s3backup.rc` file. As an example, my [configuration][2] I
override the default duplicity options (`$DUPLICITY_OPTS`) in
`s3backup.rc` to include duplicity's support for asynchronous upload
that is still experimental.

[1]: http://github.com/memes/s3backup "s3backup git repository"
[2]: http://github.com/memes/s3backup/wiki/Matthew's-configuration "Matthew's configuration"
