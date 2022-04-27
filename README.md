# This PowerShell script does the following:

Creates a backup of a SQL Server DB
Creates backup logfile for each backup
Creates a master log file for each SQL Server instance to show when the script was run
Compresses backup files using 7Zip
Deletes obsolete backups
Uses various command line parameters; all/none/some of which can be optional
Can run in test mode so you don't waste time waiting for a backup to finish to test if the script is working

When using this script you don't need to use any 3rd party software to run backups. I wrote this script because I had a server running SQL Server Express with a number of instances and databases, but free backup software only allows you to backup a limited number of instances/databases; you then have to pay for a licence.  This script will allow you to backup your databases without having to pay for any additional software.

The account used when you run the script must have access to both the database being backed up and the backup destination backup folder; local or network share. The script uses the database server, instance and database names, backup schedule, backup type and backup file destination, plus you can decide to run the script in test mode.  Once the backup is complete, the backup file is compressed using 7Zip, and the original file deleted.

This script needs both the SqlServer and 7Zip4PowerShell modules.  To install them, do the following.
Install-Module -Name SqlServer -Verbose
Install-Module -Name 7Zip4PowerShell -Verbose

You can also define how many of each backup schedule should be retained by configuring the TransactionLogBackupRetain (2), DailyBackupRetain (5), WeeklyBackupRetain (4), MonthlyBackupRetain (3).  The detault values are shown in brackets.

Command line examples
.\<scrpt-name> -dBServer "SQLSERVER" -dBInstance "WSUS" -dBName "SUSDB" -dBSchedule "Daily" -dBBackupAction "Database" -BackupFolderRoot "C:\SQLBackups" -TestMode  # If you set a default value in the script then you don't need to provide it in the command line.
.\<scrpt-name> -dBInstance "WSUS" -dBName "SUSDB" -dBSchedule "Weekly" -TestMode   # -TestMode runs the script in test mode
.\<scrpt-name> -dBInstance "WSUS" -dBName "SUSDB" -dBBackupAction "Log"   # Uses the default database set in the dBServer parameter above and performs a transaction log backup.

If your SQL Server has multple instances/databases, dBServer and BackupFolderRoot will stay constant, so I suggesting configuring these in the script and passing dBInstance, dBName, dBSchedule and dBBackupAction.  For example;
.\<scrpt-name> -dBInstance "WSUS" -dBName "SUSDB" -dBSchedule "Daily" -dBBackupAction "Database"

Folders are created based on $dBInstance\$dBName\$dBSchedule, in which the script creates backups. For log backups the Daily folder is used.  The script cleans up after itself, deleting backups and logs based on the provided parameters.  A log file is generated in a .\BackupLogs folder showing the results of all script steps. A master log file is generated in the $BackupFolderRoot\$dBInstance folder showing when the script was executed.

You can schedule the backup to run using Task Scheduler
If you are using an account that has access to the databases and shared folder to run the scheduled task, that account must also have 'Log on as a batch job' rights
Task Action -> Start a program
Program/script: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe (
Add arguments: %PATH%\<scrpt-name> -dBServer <optional> -dBInstance <mandatory>  -dBName <mandatory>  -dBSchedule <mandatory> -dBBackupAction <optional> -TestMode <optional>
Start in: %PATH%

## Check the script for for full usage instructions.