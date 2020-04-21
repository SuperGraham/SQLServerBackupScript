# This PowerShell script does the following:

Creates a backup of a SQL Server DB.

Creates backup logfile for each backup.

Creates a master log file for each SQL Server instance to show when the script was run.

Compresses backup files using 7Zip.

Deletes obsolete backups.

Uses various command line parameters; all/none/some of which can be optional.

Can run in test mode so you don't waste time waiting for a backup to finish to test if the script is working.
