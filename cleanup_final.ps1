<#
.SYNOPSIS
    This script performs cleanup activity for Ncover.

.DESCRIPTION
    This script takes input from user for the "datastoreLocation", "directoryThresholdGB" & "logFile" path
    Then checks if the "datastoreLocation" has crossed the "directoryThresholdGB" value. 
    If yes,
        then stop the service, perform cleanup activity and then start the service. All the logs
    activity is tracked in "logFile" path provided.
    If no, 
        then just update the logfile with message "No cleanup performed." 

.EXAMPLE
    .\\cleanup.ps1

    Runs the script
#>


# Define the service name
$serviceName = "ncover"  # Replace with the actual service name if different

# Prompt for the datastore location, directory threshold and Log file path  currently hardcoded the values.
$datastoreLocation = "C:\ProgramData\ncoverdata"
#$datastoreLocation = Read-Host "Enter the datastore location (e.g., C:\ProgramData\ncoverdata)"

#$directoryThresholdGB = 1.5
$directoryThresholdGB = [decimal](Read-Host "Enter the directory threshold in GB (e.g., 1.5)")

$logFile = "C:\Users\ing07471\cleanup_log.txt"
#$logFile = Read-Host "Enter the logfile location (e.g., C:\Users\ing07471\cleanup_log.txt)"

# Display all the inputs before proceeding
Write-Host "Verify the Inputs provided:" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------------" -ForegroundColor Magenta
Write-Host "| datastore location          | $datastoreLocation                "
Write-Host "| directory threshold (in GB) | $directoryThresholdGB             "
Write-Host "| logfile location            | $logFile                          "
Write-Host "------------------------------------------------------------------" -ForegroundColor Magenta

$confirmation = Read-Host "Are you sure You Want To Proceed(y/n):"
if ($confirmation -eq 'y') {
    Write-Host "################### Checking if cleanup needed ###################" -ForegroundColor Green

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

    # Function to format the size in human readable format
    function Get-HRSize {
        param (
            [int]$dSize
        )

        if ($dSize -lt 1000000) {
            $Size = [string]$([math]::floor(($dSize / 1KB))) + 'KB'
        } elseif (($dSize -gt 1000000) -and ($dSize -lt 1000000000)) {
             $Size = [string]$([math]::floor(($dSize / 1MB))) + 'MB'
        } else {
            $Size = [string]$([math]::floor(($dSize / 1GB))) + 'GB'
        }
        return $Size
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
        $datastoreSize = Get-DirectorySize -path $datastoreLocation

        $actualSize = Get-HRSize -dSize $datastoreSize
        Log-Status -message "Datastore size before cleanup: $actualSize"
    
        # Check if datastore size crossed threshold
        if ($datastoreSize -gt $directoryThresholdBytes) {
            Write-Host "Size has crossed threshold limit. Starting cleanup activity................"
            Log-Status -message "Size has crossed threshold limit of $directoryThresholdGB GB"
            Log-Status -message "Starting cleanup activity................"
    
            # Stop the service and log
           
            if ($serviceName.Status -eq 'Running') {
                Log-Status -message "Stopping $serviceName service..."
                Stop-Service -Name $serviceName -Force
                $serviceName.WaitForStatus('Stopped','00:00:30') # Wait for 30 seconds for the service to stop
                if ($serviceName.Status -eq 'Stopped'){
                    Log-Status -message "$serviceName service stopped."
                } else {
                    Log-Status -message "$serviceName service still not stopped. Stop it manually"
                }
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
    
            # Cleanup Logs sub-directories (NcoverApiClient, Profiling, Service)
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
    
            # Cleanup Ncover directory
            $ncoverDir = Join-Path -Path $datastoreLocation -ChildPath "NCover"

            $projectFolder = "Projects"
    
            if (Test-Path -Path $ncoverDir) {
                Set-Location -Path $ncoverDir
                Log-Status -message "Cleaning up items in 'NCover', excluding 'Projects'."
    
                # List all items except for the Project folder
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
            $datastoreSizeAfterCleanup = Get-DirectorySize -path $datastoreLocation
            $dSizeAC = Get-HRSize -dSize $datastoreSizeAfterCleanup
    
            # Log the datastore size after cleanup
            Log-Status -message "Datastore size after cleanup: $dSizeAC"
            Log-Status -message "Completed cleanup activity................"
            Write-Host "Size is now below threshold limit. Completed cleanup activity................"
    
            # Start the service and log
            if ($serviceName.Status -ne 'Running') {
                Log-Status -message "Starting $serviceName service..."
                Start-Service -Name $serviceName
                $serviceName.WaitForStatus('Running','00:00:30') # Wait for 30 seconds for the service to start
                if ($serviceName.Status -ne 'Running'){
                    Log-Status -message "$serviceName service not started. Start it manually "
                } else {
                    Log-Status -message "$serviceName service started."
                }
            } else {
                Log-Status -message "$serviceName service is already running or not found."
            }
        } else {
            Write-Host "################### Cleanup not needed because current size is $actualSize ###################" -ForegroundColor Green
            Log-Status -message "Datastore size ($actualSize) does not exceed the threshold ($directoryThresholdGB GB). No cleanup performed."
        }
    } else {
        Log-Status -message "$datastoreLocation does not exist."
    }
    
} else {
    Write-Host "################### Cancelled the Cleanup activity ###################" -ForegroundColor Green
}
