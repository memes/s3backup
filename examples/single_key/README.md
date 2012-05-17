Single GPG key backup
=====================

This is probably the most common backup option for duplicity; the backup files
are encrypted and signed by a single key. I use this option for backing up my
employer's laptop to S3 so I never have to surrender my personal GPG key if
circumstances change or another employee needs access to my backups.

Cron automatic backup
---------------------
1.  Download/clone s3backup.sh from [github][1] to a local directory

2.  Create/import a GPG key pair to use for backups. I prefer to create a key
    pair specifically for this purpose, but that is not essential.

    Verify that the key pair is present for the user account that will
    be performing the backup.

        blofeld:~# gpg --list-keys
        /root/.gnupg/pubring.gpg
        ------------------------
        pub   2048D/D69967E1 2011-03-17
        uid                  Matthew Emes (automatic backup key) <memes+backup@aaxisgroup.com>
        sub   2048g/879A3774 2011-03-17
        
        blofeld:~# gpg --list-secret-keys
        /root/.gnupg/secring.gpg
        ------------------------
        sec   2048D/D69967E1 2011-03-17
        uid                  Matthew Emes (automatic backup key) <memes+backup@aaxisgroup.com>
        ssb   2048g/879A3774 2011-03-17
        
3.  Modify s3backup.rc to specify the key pair to use for signing and
    encryption. Note that if this key pair is the only set available
    then it is not necessary to do this step but it will help if you
    manage multiple machines with different keys.

    See single key example configuration for details.

4.  Create an include/exclude list to match the files to backup; if
    not present then the script will backup all files in /home. It is
    probably a good idea to make sure that the directory used to
    contain the duplicity local copies and temporary files are
    excluded from the backup.

    See example include list for details.

5.  Create a cron entry for the backup. For example, assuming the
    s3backup.sh is in /var/local/backups/, this snippet could be
    placed in `/etc/cron.d` to automatically backup daily.

        # Run a backup daily
        SHELL=/bin/sh
        MAILTO=memes@aaxisgroup.com
        03 23 * * * root test -x /var/local/backups/s3backup.sh && /var/local/backups/s3backup.sh 2>&1 | mail -s "Daily backup: $(hostname -s)" ${MAILTO}

[1]: http://github.com/memes/s3backup "s3backup git repository"
