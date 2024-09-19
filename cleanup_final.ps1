<#
.SYNOPSIS
    A PowerShell script to monitor directory size, stop services, clean up files, and restart services when certain thresholds are exceeded.

.DESCRIPTION
    This script automates the cleanup of a specific directory when its size exceeds a threshold. It performs the following actions:
    - Stops a service (ncover by default).
    - Cleans up specific files and directories.
    - Restarts the service.
    - Logs all actions to a log file.
    The script supports error handling to ensure smooth execution even in case of failures.

.AUTHOR
    Your Name
    Contact: your.email@domain.com

.PARAMETER datastoreLocation
    The path to the datastore location to monitor. Example: `C:\ProgramData\ncoverdata`.

.PARAMETER directoryThresholdGB
    The threshold size in gigabytes. If the directory exceeds this size, cleanup will be triggered.

.PARAMETER logFile
    The path where the log file will be created.

.EXAMPLE
    .\cleanup.ps1
#>

# Define the service name
$serviceName = "ncover"  # Replace with the actual service name if different

# Prompt for the datastore location, directory threshold, and log file path. Currently hardcoded the values.
$datastoreLocation = "C:\ProgramData\ncoverdata"
$directoryThresholdGB = [decimal](Read-Host "Enter the directory threshold in GB (e.g., 1.5)")
$logFile = "C:\Users\ing07471\cleanup_log.txt"

# Validate if directory threshold is a valid number
if (-not [decimal]::TryParse($directoryThresholdGB, [ref]$null)) {
    Write-Host "Invalid directory threshold. Please enter a numeric value." -ForegroundColor Red
    exit 1
}

# Start transcript for logging
Start-Transcript -Path $logFile -Append

# Display all the inputs before proceeding
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

# Confirmation prompt
$confirmation = Read-Host "Are you sure you want to proceed (y/n):"
if ($confirmation -ne 'y') {
    Write-Host "Cleanup activity cancelled." -ForegroundColor Red
    Stop-Transcript
    exit 0
}

Write-Host "################### Checking if cleanup is needed ###################" -ForegroundColor Green

# Convert threshold to bytes
$directoryThresholdBytes = $directoryThresholdGB * 1GB

# Function to get the size of a directory (optimized)
function Get-DirectorySize {
    param (
        [string]$path
    )
    try {
        if (Test-Path -Path $path) {
            $size = (Get-ChildItem -Path $path -Recurse -File | Measure-Object -Property Length -Sum).Sum
            return $size
        } else {
            throw "Path $path not found."
        }
    } catch {
        Log-Status -message "Error retrieving directory size for $path: $($Error[0].Exception.Message)"
        throw $_
    }
}

# Function to format the size in a human-readable format
function Get-HRSize {
    param (
        [long]$dSize
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
    try {
        Add-Content -Path $logFile -Value ("[" + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "] " + $message)
    } catch {
        Write-Host "Error logging to file: $logFile. Message: $($Error[0].Exception.Message)"
        exit 1
    }
}

try {
    # Log user and machine info for traceability
    Log-Status -message "Script initiated by user: $env:USERNAME on machine: $env:COMPUTERNAME"

    # Check if the datastore location exists
    if (Test-Path -Path $datastoreLocation) {
        # Get the size of the datastore directory
        $datastoreSize = Get-DirectorySize -path $datastoreLocation
        $actualSize = Get-HRSize -dSize $datastoreSize
        Log-Status -message "Datastore size before cleanup: $actualSize"

        # Check if datastore size crossed the threshold
        if ($datastoreSize -gt $directoryThresholdBytes) {
            Write-Host "Current size: $actualSize"
            Write-Host "Size has crossed threshold limit. Starting cleanup activity..."
            Log-Status -message "Size has crossed the threshold limit of $directoryThresholdGB GB"
            Log-Status -message "Starting cleanup activity..."

            # Stop the service
            try {
                $service = Get-Service -Name $serviceName -ErrorAction Stop
                if ($service.Status -eq 'Running') {
                    Log-Status -message "Stopping $serviceName service..."
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    $service.WaitForStatus('Stopped', '00:00:30')
                    Log-Status -message "$serviceName service stopped."
                } else {
                    Log-Status -message "$serviceName service is not running."
                }
            } catch {
                Log-Status -message "Error stopping service $serviceName: $($Error[0].Exception.Message)"
                exit 1
            }

            # Cleanup Coverage Files (with -WhatIf for safety)
            try {
                $coverageFilesDir = Join-Path -Path $datastoreLocation -ChildPath "Coverage Files"
                if (Test-Path -Path $coverageFilesDir) {
                    Log-Status -message "Cleaning up 'Coverage Files' directory."
                    Remove-Item -Path $coverageFilesDir\* -Recurse -Force -ErrorAction Stop -WhatIf  # Remove -WhatIf after testing
                }
            } catch {
                Log-Status -message "Error during cleanup of Coverage Files: $($Error[0].Exception.Message)"
            }

            # Cleanup Logs sub-directories
            try {
                $logsDirs = @("NcoverApiClient", "Profiling", "Service")
                foreach ($logsDir in $logsDirs) {
                    $fullLogsDir = Join-Path -Path $datastoreLocation -ChildPath ("Logs\" + $logsDir)
                    if (Test-Path -Path $fullLogsDir) {
                        Log-Status -message "Cleaning up logs in '$logsDir'..."
                        Remove-Item -Path $fullLogsDir\* -Recurse -Force -WhatIf  # Remove -WhatIf after testing
                    } else {
                        Log-Status -message "'$logsDir' logs directory does not exist."
                    }
                }
            } catch {
                Log-Status -message "Error during cleanup of Logs sub-directories: $($Error[0].Exception.Message)"
            }

            # Cleanup NCover directory
            try {
                $ncoverDir = Join-Path -Path $datastoreLocation -ChildPath "NCover"
                $projectFolder = "Projects"
                if (Test-Path -Path $ncoverDir) {
                    Set-Location -Path $ncoverDir -Force
                    Log-Status -message "Cleaning up items in 'NCover', excluding 'Projects'."
                    $items = Get-ChildItem -Exclude $projectFolder
                    if ($items.Count -gt 0) {
                        Remove-Item -Path $items.FullName -Recurse -Force -WhatIf  # Remove -WhatIf after testing
                    } else {
                        Log-Status -message "No items to clean up in 'NCover', excluding 'Projects'."
                    }
                } else {
                    Log-Status -message "'NCover' directory does not exist."
                }
            } catch {
                Log-Status -message "Error during cleanup of NCover directory: $($Error[0].Exception.Message)"
            }

            # Log the datastore size after cleanup
            $datastoreSizeAfterCleanup = Get-DirectorySize -path $datastoreLocation
            $dSizeAC = Get-HRSize -dSize $datastoreSizeAfterCleanup
            Log-Status -message "Datastore size after cleanup: $dSizeAC"
            Log-Status -message "Completed cleanup activity."

            # Start the service
            try {
                $service = Get-Service -Name $serviceName -ErrorAction Stop
                if ($service.Status -ne 'Running') {
                    Log-Status -message "Starting $serviceName service..."
                    Start-Service -Name $serviceName -ErrorAction Stop
                    $service.WaitForStatus('Running', '00:00:30')
                    Log-Status -message "$serviceName service started."
                }
            } catch {
                Log-Status -message "Error starting service $serviceName: $($Error[0].Exception.Message)"
            }

        } else {
            Log-Status -message "Datastore size within limit: $actualSize"
            Write-Host "Datastore size is within the defined limit."
        }
    } else {
        Log-Status -message "Datastore location does not exist."
        Write-Host "Datastore location not found." -ForegroundColor Red
    }
} catch {
    Log-Status -message "Error during the cleanup process: $($Error[0].Exception.Message)"
}

# Stop transcript for logging
Stop-Transcript

Write-Host "Cleanup process completed."
