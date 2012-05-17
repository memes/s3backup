Dual GPG key backup
=====================

For those that are paranoid, or just wish for greater security without
compromising secret key access, it is possible to use different keys
for signing and encryption of duplicity backups. Note that if you
choose to follow this strategy then backups can be automated but there
may be greater effort to restore files; see the wiki page on [dual key
strategy][1] for more details on what is involved.

This is the strategy I use when backing up my personal computers; an
automatic signing key is present in root's gnupg keyrings and a copy
of my personal encryption key is present in root's public
keyring. This way I do not need to give root or an automated script
the private key associated with my personal keypair.

Cron automatic backup
---------------------
1.  Download/clone s3backup.sh from [github][2] to a local directory

2.  Create/import a GPG key pair to use for backup signing; I prefer
    to create a key pair specifically for this purpose, but that is
    not essential. Import the public key to be used for encryption
    into the keyring.

    Verify that the signing key pair is present for the user account that will
    be performing the backup, and that the encryption key is present too.

        ganymede:~# gpg --list-keys
        /root/.gnupg/pubring.gpg
        ------------------------
        pub   1024D/9EC47665 2009-04-15
        uid                  Matthew Emes (automatic signing key) <autosign@matthewemes.com>
        
        pub   1024D/E1ADCDE1 2002-09-10
        uid                  Matthew Emes <memes@matthewemes.com>
        sub   4096g/4040BFA4 2011-03-24 [expires: 2013-03-23]
        
        ganymede:~# gpg --list-secret-keys
        /root/.gnupg/secring.gpg
        ------------------------
        sec   1024D/9EC47665 2009-04-15
        uid                  Matthew Emes (automatic signing key) <autosign@matthewemes.com>
       
3.  Modify s3backup.rc to specify which key to use for signing and
    encryption.

    See dual key example [configuration][3] for details.

4.  Create an include/exclude list to match the files to backup; if
    not present then the script will backup all files in /home. It is
    probably a good idea to make sure that the directory used to
    contain the duplicity local copies and temporary files are
    excluded from the backup.

    See example [include list][4] for details.

5.  Create a cron entry for the backup. For example, assuming the
    s3backup.sh is in /var/local/backups/, this snippet could be
    placed in `/etc/cron.d` to automatically backup daily.

        # Run a backup daily
        SHELL=/bin/sh
        MAILTO=memes@matthewemes.com
        13 23 * * * root test -x /var/local/backups/s3backup.sh && /var/local/backups/s3backup.sh 2>&1 | mail -s "Daily backup: $(hostname -s)" ${MAILTO}

[1]: http://github.com/memes/s3backup/wiki/Dual%20Key%20Strategy
[2]: http://github.com/memes/s3backup "s3backup git repository"
[3]: s3backup.rc
[4]: include.list
