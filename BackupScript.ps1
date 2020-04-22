#   SQL SERVER BACKUP SCRIPT - GRAHAM WATKINS (graham_watkins@yahoo.com)
#   
#   This Powershell script does the following:
#   Creates a backup of a SQL Server DB
#   Creates backup logfile for each backup
#   Creates a master log file for each SQL Server instance to show when the script was run
#   Compresses backup files using 7Zip
#   Deletes obsolete backups
#   Uses various command line parameters; all/none/some of which can be optional
#   Can run in test mode so you don't waste time waiting for a backup to finish to test if the script is working
#   
#   When using this script you don't need to use any 3rd party software to run backups. I wrote this script because I had a server running SQL Server Express with a number of instances and databases, but free backup software only allows you to backup a limited number of instances/databases; you then have to pay for a licence.  This script will allow you to backup your databases without having to pay for any additional software.
#   
#   The account used when you run the script must have access to both the database being backed up and the backup destination backup folder; local or network share. The script uses the database server, instance and database names, backup schedule, backup type and backup file destination, plus you can decide to run the script in test mode.  Once the backup is complete, the backup file is compressed using 7Zip, and the original file deleted.
#   
#   This script needs both the SqlServer and 7Zip4PowerShell modules.  To install them, do the following.
#   Install-Module -Name SqlServer -Verbose
#   Install-Module -Name 7Zip4PowerShell -Verbose
#   
#   You can also define how many of each backup schedule should be retained by configuring the TransactionLogBackupRetain (2), DailyBackupRetain (5), WeeklyBackupRetain (4), MonthlyBackupRetain (3).  The detault values are shown in brackets.
#   
#   Command line examples
#   .\<scrpt-name> -dBServer "SQLSERVER" -dBInstance "WSUS" -dBName "SUSDB" -dBSchedule "Daily" -dBBackupAction "Database" -BackupFolderRoot "C:\SQLBackups" -TestMode  # If you set a default value in the script then you don't need to provide it in the command line.
#   .\<scrpt-name> -dBInstance "WSUS" -dBName "SUSDB" -dBSchedule "Weekly" -TestMode   # -TestMode runs the script in test mode
#   .\<scrpt-name> -dBInstance "WSUS" -dBName "SUSDB" -dBBackupAction "Log"   # Uses the default database set in the dBServer parameter above and performs a transaction log backup.
#   
#   If your SQL Server has multple instances/databases, dBServer and BackupFolderRoot will stay constant, so I suggesting configuring these in the script and passing dBInstance, dBName, dBSchedule and dBBackupAction.  For example;
#   .\<scrpt-name> -dBInstance "WSUS" -dBName "SUSDB" -dBSchedule "Daily" -dBBackupAction "Database"
#   
#   Folders are created based on $dBInstance\$dBName\$dBSchedule, in which the script creates backups. For log backups the Daily folder is used.  The script cleans up after itself, deleting backups and logs based on the provided parameters.  A log file is generated in a .\BackupLogs folder showing the results of all script steps. A master log file is generated in the $BackupFolderRoot\$dBInstance folder showing when the script was executed.
#   
#   You can schedule the backup to run using Task Scheduler
#   If you are using an account that has access to the databases and shared folder to run the scheduled task, that account must also have 'Log on as a batch job' rights
#   Task Action -> Start a program
#   Program/script: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe (
#   Add arguments: %PATH%\<scrpt-name> -dBServer <optional> -dBInstance <mandatory>  -dBName <mandatory>  -dBSchedule <mandatory> -dBBackupAction <optional> -TestMode <optional>
#   Start in: %PATH%

param(
    [Parameter(Mandatory=$false)][string]$dBServer = "localhost", # <dBServer> - Database server name. Change the default as required if you plan to use this script multiple times for multiple instances\DBs but you only have one database server
    [Parameter(Mandatory=$false)][string]$dBInstance = "InstanceName", # <dBInstance> - Named instance, used also in the backup folder location $dBInstance\$dBName\$dBSchedule
    [Parameter(Mandatory=$false)][string]$dBName = "DatabaseName", # <dBName> - Database name, also used in the backup folder location $dBInstance\$dBName\$dBSchedule
    [Parameter(Mandatory=$false)][string]$dBSchedule = "Daily", # <dBSchedule> - Daily, Weekly, Monthly, Log, used also in the backup folder location $dBInstance\$dBName\$dBSchedule
    [Parameter(Mandatory=$false)][string]$dBBackupAction = "Database", # <dBBackupAction> - Backup type: Database, Files, Log.  The option Files has not been tested.
    [Parameter(Mandatory=$false)][string]$BackupFolderRoot = "C:\SQLBackups", # <BackupFolderRoot> - SThe root folder for your backups. This can be a local path or shared folder
    [Parameter(Mandatory=$false)][switch]$TestMode # <TestMode> - If you wish to you can set test mode as a passed argument. If set, overides the $ScriptTestMode parameters in the script
)

[int]$TransactionLogBackupRetain = 2  # Any transaction log backups older than <TransactionLogBackupRetain> days will be deleted
[int]$DailyBackupRetain = 5  # Assuming you're running daily backup jobs on weekdays only, all other than the most recent <DailyBackupRetain> daily backups will be deleted
[int]$WeeklyBackupRetain = 4  # All other than the most recent <WeeklyBackupRetain> weekly backups will be deleted
[int]$MonthlyBackupRetain = 3  # All other than the most recent <MonthlyBackupRetain> monthly backups will be deleted

#   If $True, the script creates an empty backup file to speed up the testing process. This should be set to $False if not testing.
#   Test mode creates test files in the correct folders, but named differently; *.test.*.
#   Test mode cleans up the files created during testing
$ScriptTestMode = $False  #   $True or $False.  This is over ridden by the -TestMode parameter if used when calling the script.
if ($TestMode) { $ScriptTestMode = $True }

Function Format-FileSize() {
    Param ([int64]$size)
    If ($size -gt 1TB) {[string]::Format("{0:0.00} TB", $size / 1TB)}
    ElseIf ($size -gt 1GB) {[string]::Format("{0:0.00} GB", $size / 1GB)}
    ElseIf ($size -gt 1MB) {[string]::Format("{0:0.00} MB", $size / 1MB)}
    ElseIf ($size -gt 1KB) {[string]::Format("{0:0.00} kB", $size / 1KB)}
    ElseIf ($size -gt 0) {[string]::Format("{0:0.00} B", $size)}
    Else {""}
}

$SQLInstance = "$dBServer\$dBInstance"
$DateTime = Get-Date -format yyyyMMddHHmmss
if (!($ScriptTestMode)) { $FileName = $DBName + $DateTime } else { $FileName = $DBName + $DateTime + ".test" }

if (!($dBBackupAction -eq "Log")) {
    $BackupPath = "$dBInstance\$dBName\$dBSchedule"
    $LogPath = "$dBInstance\$dBName\$dBSchedule\BackupLogs"
    $FileName = $FileName + ".bak"
} else {
    $BackupPath = "$dBInstance\$dBName\Daily"
    $LogPath = "$dBInstance\$dBName\Daily\BackupLogs"
    $FileName = $FileName + ".trn"
    $dBSchedule = "Log"
}

#   Define log file name
$LogFile = "$BackupFolderRoot\$LogPath\$FileName.log"

#   Start transcipt using $LogFile
Start-Transcript $LogFile -IncludeInvocationHeader -Force | Out-Null
if ($ScriptTestMode) { Write-Output "`n****** SCRIPT IS IN TESTNG MODE ******" }

#   Define master log file
if (!($ScriptTestMode)) { $MasterLogFile = "$BackupFolderRoot\$dBInstance\master" + $dBInstance + ".log" } else { $MasterLogFile = "$BackupFolderRoot\$dBInstance\master" + $dBInstance + ".test.log" }

#   Add backup details and backup start time to log file
$stepTime = Get-Date -format "yyyy-MM-dd HHmm"
Write-Output "`nBackup Start Time: $stepTime"
Write-Output "Backup details - Instance: $SQLInstance, Database: $dBName, Schedule: $dBSchedule, Type: $dBBackupAction"
$MasterLogFileText = $MasterLogFileText + "$stepTime - Instance: $SQLInstance, Database: $dBName, Schedule: $dBSchedule, Type: $dBBackupAction"
if ($ScriptTestMode) { $MasterLogFileText = $MasterLogFileText + "  ** TEST RUN **" }
Add-Content -Path $MasterLogFile -Encoding unicode -Value $MasterLogFileText

#   Perform database backup
if (!($ScriptTestMode)) {
    Write-Output "`nBackup-SqlDatabase -ServerInstance $SQLInstance -Database $dBName -BackupFile $BackupFolderRoot\$BackupPath\$FileName -BackupAction $dBBackupAction -SkipTapeHeader -checksum -Verbose`n"
    Backup-SqlDatabase -ServerInstance $SQLInstance -Database $dBName -BackupFile "$BackupFolderRoot\$BackupPath\$FileName" -BackupAction $dBBackupAction -SkipTapeHeader -checksum -Verbose
#   SQL Server (not SQL Express) has a -CompressionOption option.  This can be used in the Backup-SqlDatabase command if you want to, but it probably uses Windows compression not 7Zip, so it won't be as quick nor as efficient as the Compress-7Zip command.
} else {
    Write-Output "`nCreating dummy file for testing"
    New-Item "$BackupFolderRoot\$BackupPath\$FileName" | Out-Null
    Set-Content "$BackupFolderRoot\$BackupPath\$FileName" "$FileName" | Out-Null
}

#   Add compression start time to log file
$stepTime = Get-Date -format "yyyy-MM-dd HHmm"
Write-Output "`nCompressing backup file: $stepTime"

#   Check if the backup file exists
if (Test-Path "$BackupFolderRoot\$BackupPath\$FileName" -PathType Leaf) {

#   Add initial backup file size to log file
    $size=Format-FileSize((Get-Item "$BackupFolderRoot\$BackupPath\$FileName").length)
    Write-Output "Pre-compression file size: $size"

#   Start compressing. Compress-7Zip has more options than the ones used - https://www.powershellgallery.com/packages/PS7Zip/, -CompressionLevel, -CompressionLevel and more.
    Compress-7Zip -Path "$BackupFolderRoot\$BackupPath\$FileName" -ArchiveFileName "$BackupFolderRoot\$BackupPath\$FileName.zip" -Format Zip -Verbose

#   Add compressed backup file size to log file
    $size=Format-FileSize((Get-Item "$BackupFolderRoot\$BackupPath\$FileName.zip").length)
    Write-Output "Post-compression file size: $size"

#   Remove uncompressed backup file
    Remove-Item "$BackupFolderRoot\$BackupPath\$FileName" -Verbose

} else {
    Write-Output "The backup file did not exist: $BackupFolderRoot\$BackupPath\$FileName"
}

#   Add time to log file
$stepTime = Get-Date -format "yyyy-MM-dd HHmm"
Write-Output "`nDeleting obsolete backups/logs: $stepTime"

#    Delete obsolete backup files
if (!($ScriptTestMode)) {
    Get-ChildItem -path "$BackupFolderRoot\$BackupPath\*.test.???.zip" | Remove-Item -Force -Verbose
    Get-ChildItem -path "$BackupFolderRoot\$LogPath\*.test.???.log" | Remove-Item -Force -Verbose
    Get-ChildItem -path "$BackupFolderRoot\$dBInstance\*.test.log" | Remove-Item -Force -Verbose
}

Switch ($dBSchedule)
{
  "Log"     { if (!($ScriptTestMode)) {
                Get-ChildItem -path "$BackupFolderRoot\$BackupPath\*.trn.zip" | where {$_.Lastwritetime -lt (date).adddays(-$TransactionLogBackupRetain)} | Remove-Item -Force -Verbose
                Get-ChildItem -path "$BackupFolderRoot\$LogPath\*.trn.log" | where {$_.Lastwritetime -lt (date).adddays(-$TransactionLogBackupRetain)} | Remove-Item -Force -Verbose
              }
              else
              {
                Write-Output "Get-ChildItem -path $BackupFolderRoot\$BackupPath\*.trn.zip | where {$_.Lastwritetime -lt (date).adddays(-$TransactionLogBackupRetain)} | Remove-Item -Force -Verbose"
                Get-ChildItem -path "$BackupFolderRoot\$BackupPath\*.test.trn.zip" | where {$_.Lastwritetime -lt (date).adddays(-$TransactionLogBackupRetain)} | Remove-Item -Force -Verbose
                Write-Output "Get-ChildItem -path $BackupFolderRoot\$LogPath\*.trn.log | where {$_.Lastwritetime -lt (date).adddays(-$TransactionLogBackupRetain)} | Remove-Item -Force -Verbose"
                Get-ChildItem -path "$BackupFolderRoot\$LogPath\*.test.trn.log" | where {$_.Lastwritetime -lt (date).adddays(-$TransactionLogBackupRetain)} | Remove-Item -Force -Verbose
              }
              Break
            }
  "Daily"   { if (!($ScriptTestMode)) {
                Get-ChildItem -path "$BackupFolderRoot\$BackupPath\*.bak.zip" | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $DailyBackupRetain | Remove-Item -Force -Verbose
                Get-ChildItem -path "$BackupFolderRoot\$LogPath\*.bak.log" | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $DailyBackupRetain | Remove-Item -Force -Verbose
              }
              else
              {
                Write-Output "Get-ChildItem -path $BackupFolderRoot\$BackupPath\*.bak.zip | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $DailyBackupRetain | Remove-Item -Force -Verbose"
                Get-ChildItem -path $BackupFolderRoot\$BackupPath\*.test.bak.zip | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $DailyBackupRetain | Remove-Item -Force -Verbose
                Write-Output "Get-ChildItem -path $BackupFolderRoot\$LogPath\*.bak.log | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $DailyBackupRetain | Remove-Item -Force -Verbose"
                Get-ChildItem -path $BackupFolderRoot\$LogPath\*.test.bak.log | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $DailyBackupRetain | Remove-Item -Force -Verbose
              }
              Break
            }
  "Weekly"  { if (!($ScriptTestMode)) {
                Get-ChildItem -path "$BackupFolderRoot\$BackupPath\*.bak.zip" | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $WeeklyBackupRetain | Remove-Item -Force -Verbose
                Get-ChildItem -path "$BackupFolderRoot\$LogPath\*.bak.log" | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $WeeklyBackupRetain | Remove-Item -Force -Verbose
              }
              else
              {
                Write-Output "Get-ChildItem -path $BackupFolderRoot\$BackupPath\*.bak.zip | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $WeeklyBackupRetain | Remove-Item -Force -Verbose"
                Get-ChildItem -path $BackupFolderRoot\$BackupPath\*.test.bak.zip | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $WeeklyBackupRetain | Remove-Item -Force -Verbose
                Write-Output "Get-ChildItem -path $BackupFolderRoot\$LogPath\*.bak.log | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $WeeklyBackupRetain | Remove-Item -Force -Verbose"
                Get-ChildItem -path $BackupFolderRoot\$LogPath\*.test.bak.log | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $WeeklyBackupRetain | Remove-Item -Force -Verbose
              }
              Break
            }
  "Monthly"   { if (!($ScriptTestMode)) {
                Get-ChildItem -path "$BackupFolderRoot\$BackupPath\*.bak.zip" | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $MonthlyBackupRetain | Remove-Item -Force -Verbose
                Get-ChildItem -path "$BackupFolderRoot\$LogPath\*.bak.log" | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $MonthlyBackupRetain | Remove-Item -Force -Verbose
              }
              else
              {
                Write-Output "Get-ChildItem -path $BackupFolderRoot\$BackupPath\*.bak.zip | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $MonthlyBackupRetain | Remove-Item -Force -Verbose"
                Get-ChildItem -path "$BackupFolderRoot\$BackupPath\*.test.bak.zip" | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $MonthlyBackupRetain | Remove-Item -Force -Verbose
                Write-Output "Get-ChildItem -path $BackupFolderRoot\$LogPath\*.bak.log | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $MonthlyBackupRetain | Remove-Item -Force -Verbose"
                Get-ChildItem -path "$BackupFolderRoot\$LogPath\*.test.bak.log" | where {-not $_.PsIsContainer} | sort CreationTime -desc | select -Skip $MonthlyBackupRetain | Remove-Item -Force -Verbose
              }
            }
}

#   Add script end time to log file
$stepTime = Get-Date -format "yyyy-MM-dd HHmm"
Write-Output "`nBackup End Time: $stepTime"

#   Stop transctpt and remove last 5 lines.
Stop-Transcript | Out-Null
$content = Get-Content $LogFile
$output = $content[0..($content.length-5)]
Set-Content -Path $LogFile -Value $output
