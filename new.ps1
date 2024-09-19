
<#
.SYNOPSIS
    A PowerShell script to monitor directory size, stop services, clean up files, and restart services when certain thresholds are exceeded.

.DESCRIPTION
    This script is designed to automate the cleanup of a specific directory (`datastoreLocation`) that may accumulate large amounts of data over time. 
    It takes input from the user for the directory location and  a threshold size in GB 
    When the directory exceeds the threshold size, it will:
    
    - Stop the specified service (`ncover`).
    - Clean up files from subdirectories based on the specified conditions.
    - Show all activities, including service stops, cleanup details, and errors over the console
    - Start the service after the cleanup is complete.

    This helps in maintaining optimal disk usage and ensuring that the service associated with the data directory runs efficiently.

.AUTHOR

.PARAMETER datastoreLocation
    The path to the datastore location to monitor. Example: `C:\ProgramData\ncoverdata`.

.PARAMETER directoryThresholdGB
    The threshold size in gigabytes. If the directory exceeds this size, cleanup will be triggered.

.EXAMPLE
    .\cleanup.ps1 -datastoreLocation "C:\ProgramData\ncoverdata" -directoryThresholdGB 1.5
    
    This will run the script with predefined values for the datastore location and  directory threshold 
#>

param (
    [Parameter(Mandatory=$false)]
    [string]$datastoreLocation = "C:\ProgramData\ncoverdata",

    [Parameter(Mandatory=$false)]
    [ValidateScript({ $_ -is [decimal] -or $_ -is [int] })]
    [decimal]$directoryThresholdGB = 1.5
)

Write-Host "############### Script Execution Started  ##################"

# Define the service name
$serviceName = "ncover"

Write-Host "Datastore Location: $datastoreLocation"
Write-Host "Directory Threshold (in GB): $directoryThresholdGB"

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
        Write-Host "Error retrieving directory size for $path : $($Error[0].Exception.Message)"
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

try {
    # Log user and machine info for traceability
    Write-Host "Script initiated by user: $env:USERNAME on machine: $env:COMPUTERNAME"

    # Check if the datastore location exists
    if (Test-Path -Path $datastoreLocation) {
        # Get the size of the datastore directory
        $datastoreSize = Get-DirectorySize -path $datastoreLocation
        $actualSize = Get-HRSize -dSize $datastoreSize
        Write-Host "Datastore size before cleanup: $actualSize"

        # Check if datastore size crossed the threshold
        if ($datastoreSize -gt $directoryThresholdBytes) {
            Write-Host "Size has crossed the threshold limit of $directoryThresholdGB GB"
            Write-Host "Starting cleanup activity..."

            # Stop the service
            try {
                $service = Get-Service -Name $serviceName -ErrorAction Stop
                if ($service.Status -eq 'Running') {
                    Write-Host "Stopping $serviceName service..."
                    Stop-Service -Name $serviceName -Force -ErrorAction Stop
                    $service.WaitForStatus('Stopped', '00:00:30')
                    Write-Host "$serviceName service stopped."
                } else {
                    Write-Host "$serviceName service is not running."
                }
            } catch {
                Write-Host "Error stopping service $serviceName : $($Error[0].Exception.Message)"
                exit 1
            }

            # Cleanup Coverage Files
            try {
                $coverageFilesDir = Join-Path -Path $datastoreLocation -ChildPath "Coverage Files"
                if (Test-Path -Path $coverageFilesDir) {
                    Write-Host "Cleaning up 'Coverage Files' directory."
                    Remove-Item -Path $coverageFilesDir\* -Recurse -Force -ErrorAction Stop
                }
            } catch {
                Write-Host "Error during cleanup of Coverage Files: $($Error[0].Exception.Message)"
            }

            # Cleanup Logs sub-directories
            try {
                $logsDirs = @("NcoverApiClient", "Profiling", "Service")
                foreach ($logsDir in $logsDirs) {
                    $fullLogsDir = Join-Path -Path $datastoreLocation -ChildPath ("Logs\" + $logsDir)
                    if (Test-Path -Path $fullLogsDir) {
                        Write-Host "Cleaning up logs in '$logsDir'..."
                        Remove-Item -Path $fullLogsDir\* -Recurse -Force -ErrorAction Stop
                    } else {
                        Write-Host "'$logsDir' logs directory does not exist."
                    }
                }
            } catch {
                Write-Host "Error during cleanup of Logs sub-directories: $($Error[0].Exception.Message)"
            }

            # Cleanup NCover directory
            try {
                $ncoverDir = Join-Path -Path $datastoreLocation -ChildPath "NCover"
                $projectFolder = "Projects"
                if (Test-Path -Path $ncoverDir) {
                    Set-Location -Path $ncoverDir
                    Write-Host "Cleaning up items in 'NCover', excluding 'Projects'."
                    $items = Get-ChildItem -Exclude $projectFolder
                    if ($items.Count -gt 0) {
                        Remove-Item -Path $items.FullName -Recurse -Force -ErrorAction Stop
                    } else {
                        Write-Host "No items to clean up in 'NCover', excluding 'Projects'."
                    }
                } else {
                    Write-Host "'NCover' directory does not exist."
                }
            } catch {
                Write-Host "Error during cleanup of NCover directory: $($Error[0].Exception.Message)"
            }

            # Log the datastore size after cleanup
            $datastoreSizeAfterCleanup = Get-DirectorySize -path $datastoreLocation
            $dSizeAC = Get-HRSize -dSize $datastoreSizeAfterCleanup
            Write-Host "Datastore size after cleanup: $dSizeAC"
            Write-Host "Completed cleanup activity."

            # Start the service
            try {
                $service = Get-Service -Name $serviceName -ErrorAction Stop
                if ($service.Status -ne 'Running') {
                    Write-Host "Starting $serviceName service..."
                    Start-Service -Name $serviceName -ErrorAction Stop
                    $service.WaitForStatus('Running', '00:00:30')
                    Write-Host "$serviceName service started."
                }
            } catch {
                Write-Host "Error starting service $serviceName : $($Error[0].Exception.Message)"
            }

        } else {
            Write-Host "Cleanup not needed." 
        }
    } else {
        Write-Host "Datastore location does not exist."
    }
} catch {
    Write-Host "Error during the cleanup process: $($Error[0].Exception.Message)"
}


Write-Host "############### Script Execution completed ##################"
