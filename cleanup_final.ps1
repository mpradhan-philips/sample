<#
.SYNOPSIS
    A PowerShell script to monitor directory size, stop services, clean up files, and restart services when certain thresholds are exceeded.

.DESCRIPTION
    This script is designed to automate the cleanup of a specific directory (`datastoreLocation`) that may accumulate large amounts of data over time. 
    It takes input from the user for the directory location, a threshold size in GB, and a log file location. 
    When the directory exceeds the threshold size, it will:
    
    - Stop the specified service (`ncover` by default, or any other service).
    - Clean up files from subdirectories based on the specified conditions.
    - Log all activities, including service stops, cleanup details, and errors.
    - Restart the service after the cleanup is complete.

    This helps in maintaining optimal disk usage and ensuring that the service associated with the data directory runs efficiently.

.AUTHOR
    Your Name
    Contact: your.email@domain.com

.PARAMETER datastoreLocation
    The path to the datastore location to monitor. Example: `C:\ProgramData\ncoverdata`.

.PARAMETER directoryThresholdGB
    The threshold size in gigabytes. If the directory exceeds this size, cleanup will be triggered.

.PARAMETER logFile
    The path where the log file will be created. This file will store all the activity logs of the script.

.EXAMPLE
    .\cleanup.ps1
    
    This will run the script and prompt the user for the directory threshold in GB. If the directory size exceeds the threshold, 
    it will stop the service, clean up files, and restart the service, logging all actions in the provided log file.

.EXAMPLE
    .\cleanup.ps1 -datastoreLocation "C:\ProgramData\ncoverdata" -directoryThresholdGB 1.5 -logFile "C:\Users\youruser\cleanup_log.txt"
    
    This will run the script with predefined values for the datastore location, directory threshold, and log file path, without further prompts.
#>

# Define the service name
$serviceName = "ncover"  # Replace with the actual service name if different

# Prompt for the datastore location, directory threshold, and log file path.
$datastoreLocation = "C:\ProgramData\ncoverdata"
$directoryThresholdGB = [decimal](Read-Host "Enter the directory threshold in GB (e.g., 1.5)")
$logFile = "C:\Users\ing07471\cleanup_log.txt"

# Display all the inputs before proceeding in table format
$separator = "+" + ("-" * 30) + "+" + ("-" * 40) + "+"
$header = "| {0,-30} | {1,-40} |"
$row = "| {0,-30} | {1,-40} |"

Write-Host $separator -ForegroundColor Cyan
Write-Host ($header -f "Input Parameter", "Value") -ForegroundColor Magenta
Write-Host $separator -ForegroundColor Cyan
Write-Host ($row -f "Datastore Location", $datastoreLocation)
Write-Host ($row -f "Directory Threshold (in GB)", $directoryThresholdGB)
Write-Host ($row -f "Log File Location", $logFile)
Write-Host $separator -ForegroundColor Cyan


$confirmation = Read-Host "Are you sure you want to proceed (y/n):"
if ($confirmation -eq 'y') {
    Write-Host "################### Checking if cleanup is needed ###################" -ForegroundColor Green

    # Convert threshold to bytes
    $directoryThresholdBytes = $directoryThresholdGB * 1GB

    # Function to get the size of a directory
    function Get-DirectorySize {
        param (
            [string]$path
        )

        $size = 0
        if (Test-Path -Path $path) {
            $files = Get-ChildItem -Path $path -Recurse -File
            foreach ($file in $files) {
                $size += $file.Length
            }
        }
        return $size
    }

    # Function to format the size in human-readable format
    function Get-HRSize {
        param (
            [int]$dSize
        )

        if ($dSize -lt 1MB) {
            return [string]$([math]::floor($dSize / 1KB)) + ' KB'
        } elseif ($dSize -lt 1GB) {
            return [string]$([math]::floor($dSize / 1MB)) + ' MB'
        } else {
            return [string]$([math]::floor($dSize / 1GB)) + ' GB'
        }
    }

    # Log service status
    function Log-Status {
        param (
            [string]$message
        )
        Add-Content -Path $logFile -Value ("[" + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "] " + $message)
    }

    # Check if the datastore location exists
    if (Test-Path -Path $datastoreLocation) {
        # Get the size of the datastore directory
        $datastoreSize = Get-DirectorySize -Path $datastoreLocation
        $actualSize = Get-HRSize -dSize $datastoreSize
        Log-Status -message "Datastore size before cleanup: $actualSize"

        # Check if datastore size exceeds the threshold
        if ($datastoreSize -gt $directoryThresholdBytes) {
            Write-Host "Size has crossed the threshold. Starting cleanup activity..."
            Log-Status -message "Size has crossed the threshold limit of $directoryThresholdGB GB."
            Log-Status -message "Starting cleanup activity..."

            # Manage the service
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                Log-Status -message "Stopping $serviceName service..."
                Stop-Service -Name $serviceName -Force
                $service.WaitForStatus('Stopped', '00:00:30')
                Log-Status -message "$serviceName service stopped."
            } else {
                Log-Status -message "$serviceName service is not running or not found."
            }

            # Cleanup Coverage Files
            $coverageFilesDir = Join-Path -Path $datastoreLocation -ChildPath "Coverage Files"
            if (Test-Path -Path $coverageFilesDir) {
                Log-Status -message "Cleaning up files in 'Coverage Files'..."
                Remove-Item -Path $coverageFilesDir\* -Recurse -Force
            } else {
                Log-Status -message "'Coverage Files' does not exist."
            }

            # Cleanup Logs sub-directories
            $logsDirs = @("NcoverApiClient", "Profiling", "Service")
            foreach ($logsDir in $logsDirs) {
                $fullLogsDir = Join-Path -Path $datastoreLocation -ChildPath ("Logs\" + $logsDir)
                if (Test-Path -Path $fullLogsDir) {
                    Log-Status -message "Cleaning up logs in '$logsDir'..."
                    Remove-Item -Path $fullLogsDir\* -Recurse -Force
                } else {
                    Log-Status -message "'$logsDir' logs directory does not exist."
                }
            }

            # Cleanup NCover directory
            $ncoverDir = Join-Path -Path $datastoreLocation -ChildPath "NCover"
            $projectFolder = "Projects"
            if (Test-Path -Path $ncoverDir) {
                Set-Location -Path $ncoverDir
                Log-Status -message "Cleaning up items in 'NCover', excluding 'Projects'."
                $items = Get-ChildItem -Exclude $projectFolder
                if ($items.Count -gt 0) {
                    Remove-Item -Path $items.FullName -Recurse -Force
                } else {
                    Log-Status -message "No items to clean up in 'NCover', excluding 'Projects'."
                }
            } else {
                Log-Status -message "'NCover' directory does not exist."
            }

            # Get the size of the datastore directory after cleanup
            $datastoreSizeAfterCleanup = Get-DirectorySize -Path $datastoreLocation
            $dSizeAC = Get-HRSize -dSize $datastoreSizeAfterCleanup
            Log-Status -message "Datastore size after cleanup: $dSizeAC"
            Log-Status -message "Completed cleanup activity."

            # Restart the service
            if ($service -and $service.Status -ne 'Running') {
                Log-Status -message "Starting $serviceName service..."
                Start-Service -Name $serviceName
                $service.WaitForStatus('Running', '00:00:30')
                Log-Status -message "$serviceName service started."
            } else {
                Log-Status -message "$serviceName service is already running or not found."
            }
        } else {
            Write-Host "Cleanup not needed. Current size: $actualSize."
            Log-Status -message "Datastore size ($actualSize) does not exceed the threshold. No cleanup performed."
        }
    } else {
        Log-Status -message "$datastoreLocation does not exist."
    }

} else {
    Write-Host "Cleanup activity cancelled." -ForegroundColor Green
}
