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
        try {
            if (Test-Path -Path $path) {
                $files = Get-ChildItem -Path $path -Recurse -File
                foreach ($file in $files) {
                    $size += $file.Length
                }
            }
        } catch {
            Log-Status -message "Error retrieving directory size for $path: $_"
            throw $_  # Rethrow error if you want to halt execution
        }
        return $size
    }

    # Function to format the size in a human-readable format, using Int64 for large values
    function Get-HRSize {
        param (
            [long]$dSize  # Use 'long' (Int64) to handle large file sizes
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
            Write-Host "Error logging to file: $logFile. Message: $_"
            throw $_  # Rethrow error if you want to halt execution
        }
    }

    try {
        # Check if the datastore location exists
        if (Test-Path -Path $datastoreLocation) {
            # Get the size of the datastore directory
            $datastoreSize = Get-DirectorySize -path $datastoreLocation

            $actualSize = Get-HRSize -dSize $datastoreSize
            Log-Status -message "Datastore size before cleanup: $actualSize"

            # Check if datastore size crossed the threshold
            if ($datastoreSize -gt $directoryThresholdBytes) {
                Write-Host "Size has crossed threshold limit. Starting cleanup activity..."
                Log-Status -message "Size has crossed the threshold limit of $directoryThresholdGB GB"
                Log-Status -message "Starting cleanup activity..."

                # Stop the service and log
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
                    Log-Status -message "Error stopping service $serviceName: $_"
                }

                # Perform the cleanup (coverage files, logs, etc.)
                try {
                    # Example: Clean up coverage files
                    $coverageFilesDir = Join-Path -Path $datastoreLocation -ChildPath "Coverage Files"
                    if (Test-Path -Path $coverageFilesDir) {
                        Log-Status -message "Cleaning up 'Coverage Files' directory."
                        Remove-Item -Path $coverageFilesDir\* -Recurse -Force -ErrorAction Stop
                    }
                } catch {
                    Log-Status -message "Error during cleanup: $_"
                }

                # Log the datastore size after cleanup
                $datastoreSizeAfterCleanup = Get-DirectorySize -path $datastoreLocation
                $dSizeAC = Get-HRSize -dSize $datastoreSizeAfterCleanup
                Log-Status -message "Datastore size after cleanup: $dSizeAC"
                Log-Status -message "Completed cleanup activity."
                Write-Host "Cleanup activity completed."

                # Restart the service
                try {
                    $service = Get-Service -Name $serviceName -ErrorAction Stop
                    if ($service.Status -ne 'Running') {
                        Log-Status -message "Starting $serviceName service..."
                        Start-Service -Name $serviceName -ErrorAction Stop
                        $service.WaitForStatus('Running', '00:00:30')
                        Log-Status -message "$serviceName service started."
                    } else {
                        Log-Status -message "$serviceName service is already running."
                    }
                } catch {
                    Log-Status -message "Error starting service $serviceName: $_"
                }
            } else {
                Write-Host "Cleanup not needed as current size is $actualSize."
                Log-Status -message "No cleanup performed as datastore size ($actualSize) does not exceed threshold ($directoryThresholdGB GB)."
            }
        } else {
            Log-Status -message "Datastore location $datastoreLocation does not exist."
            throw "Datastore location $datastoreLocation does not exist."
        }
    } catch {
        Log-Status -message "Error: $_"
        Write-Host "An error occurred: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Cleanup activity cancelled."
}
