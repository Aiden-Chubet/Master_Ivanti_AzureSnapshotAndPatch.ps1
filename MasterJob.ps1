<#
PURPOSE:        This will create a snapshot (disk-only) of a VM in Azure
BACKGOUNRD:	    Required for automation of Ivanti patching
AUTHOR:		    Aiden Chubet
DATE CREATED:	20-Aug-2025
#>

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Begin [1]: Install Az Module  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# This section is to verify if the required Module is installed
# 

function funcInstallModule{
    
    $requiredModule = "Az"
    $moduleVersion = Get-InstalledModule | Where-Object {($_.Name -like "*$requiredModule*")} | Select-Object Name, Version
        
    if ($null -ne $moduleVersion) {
        #Write-Host "The '$requiredModule' module is already installed.  Do you wish to check for an upgrade to the latest version (Y/N)?" -ForegroundColor Cyan

        $responseLoop = 0
        while (($responseLoop -eq 0)) {
            #Clear-Host
            Write-Host "The '$requiredModule' module is already installed.  Do you wish to check for an upgrade to the latest version (Y/N)?" -ForegroundColor Cyan -NoNewline
            $response = Read-Host " "

            if ($response -eq "Y" -or $response -eq "Yes") {
                $responseLoop = 1
                # Write-Host "You said yes" -ForegroundColor Green
                Update-Module -Name "*$requiredModule*" -Force
            } elseif ($response -eq "N" -or $response -eq "No") {
                $responseLoop = 1
                Write-Host "You said no" -ForegroundColor Magenta
            }
        }

        return
    }

    Write-Host "Installing the '$requiredModule' module now.  This may take 2-3 minutes, do not exit prematurely...." -ForegroundColor Green
    Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
    
}
#>
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ End [1]: Install Az Module ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Begin [2]: Parameters  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# This section is to define the variables used in the script for execution
# 

$subscriptionID = "REDACTED"
$tenantID = "REDACTED"
$resourceGroup = 'TARGET-RG'
$location= 'North Central US'

# Create an array with the names of all the machine groups you want to target
$targetMachines = @("DNS-AZR Automatic Servers", "DNS-AZR Critical Servers Phase 1", "DNS-AZR Critical Servers Phase 2")

#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ End [2]: Parameters ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Begin [3]: Connect to Az  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# This section is to connect/check connection to Azure
#
$password = Get-Content "C:\Scripts\_DNS_svc_patching.encrypted" | ConvertTo-SecureString 
$credential = New-Object System.Management.Automation.PsCredential("svc_patching@domain.com",$password)

$AzConnectionTest = Get-AzAccessToken -ErrorAction SilentlyContinue
if ($null -eq $AzConnectionTest) {
    Write-Host "1. Not connected to Az, trying to connect now..." -ForegroundColor Magenta
    Connect-AzAccount -Credential $credential -Tenant $tenantID 
    
    $error.clear()
    try { Get-AzAccessToken }
    catch { Write-Host "Error occured" -ForegroundColor Magenta }
    if (!$error) { <#Write-Host "No Error Occured"#> }
} else { Write-Host "1. Already connected to Azure (Az)" -ForegroundColor Green}

Select-AzSubscription -Tenant $tenantID -Subscription $subscriptionID | Out-Null
#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ End [3]: Connect to Az ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Begin [4]: Execute Snapshot Script  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# This section is to execute script regarding parameters passed to PoSH
#

$error.Clear()
try {
    # Check for access to the Ivanti PSModule by getting a single machine group filter.
    (Get-MachineGroup | Select-Object -ExpandProperty Filters) | Out-Null
} catch {
    Write-Host "2. Error occurred. No access to Ivanti PSModule/API" -ForegroundColor Red
    Write-Host "Please ensure the Ivanti module (STProtect) is installed and you have the correct permissions." -ForegroundColor Yellow
    break
}

if ($error.Count -eq 0) {
    Write-Host "2. No error occurred accessing STProtect PS module." -ForegroundColor Green
}

# The Get-MachineGroup cmdlet cannot process an array of names directly.
# This loop processes each machine group name individually and combines the results.
Write-Host "Retrieving machine names from Ivanti machine groups..." -ForegroundColor Yellow
$allMachineGroups = @()
foreach ($targetGroup in $targetMachines) {
    $allMachineGroups += Get-MachineGroup -Name $targetGroup
}

# Now we can safely process the combined results to get all the machine names.
$machineGroup = ($allMachineGroups | Select-Object -ExpandProperty Filters) | Select-Object -ExpandProperty Name
Write-Host "Found $($machineGroup.Count) machines to process." -ForegroundColor Green

# Create an array to hold the jobs for monitoring.
$snapshotJobs = @()

# Loop through each machine name retrieved from Ivanti.
foreach ($machine in $machineGroup) {
    $vmName = $machine.Replace(".domain.com","")

    # Search for the Azure VM using the cleaned-up name.
    $vm = Get-AzVM | Where-Object Name -like "$vmName*"

    if ($null -ne $vm) {
        Write-Host "Found Azure VM: $($vm.Name). Starting snapshot creation..." -ForegroundColor Cyan
        
        # Define the snapshot name with the date and time.
        $date = Get-Date -Format yyyyMMdd
        $snapshotName = "IvantiPatchJob_$($vm.Name)_$date"
        
        # Create a new snapshot configuration.
        $snapshotConfig = New-AzSnapshotConfig -SourceUri $vm.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy
        
        # Start the snapshot creation as a background job.
        $job = New-AzSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $resourceGroup -AsJob
        
        # Add the job to our tracking array.
        $snapshotJobs += $job
    } else {
        Write-Host "Azure VM for machine '$machine' not found. Skipping..." -ForegroundColor Yellow
    }
}

#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ End [4]: Execute Snapshot Script ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Begin [5]: Execute Deployment Script  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# This section is to execute script regarding deployment of patches

$job1 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-AZRAutomaticServers.ps1"
$job2 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-DNSAutomaticServers.ps1"
$job3 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-DNSAutomaticServers.ps1"
$job4 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-DNSAutomaticServers.ps1"
Start-Sleep -Seconds 900
Remove-Job -Job $job1, $job2, $job3, $job4 -Force
$job5 = Start-Job -FilePath "C:\Scripts\DNS-Azure_SnapshotAndPatch_AZR-AZRADS005.ps1"
$job6 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-AZRCriticalPhase1Servers.ps1"
$job7 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-DNSCriticalPhase1Servers.ps1"
$job8 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-DNSCriticalPhase1Servers.ps1"
$job9 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-DNSCriticalPhase1Servers.ps1"
Start-Sleep -Seconds 900
Remove-Job -Job $job5, $job6, $job7, $job8, $job9 -Force
$job10 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-AZRCriticalPhase2Servers.ps1"
$job11 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-DNSCriticalPhase2Servers.ps1"
$job12 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-DNSCriticalPhase2Servers.ps1"
$job13 = Start-Job -FilePath "C:\Scripts\Secondary_Scripts\DNS-DNSCriticalPhase2Servers.ps1"
Remove-Job -Job $job10, $job11, $job12, $job13 -Force

#
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ End [4]: Execute Deployment Script ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# All jobs have been removed, now exit the script.
Write-Host "All secondary scripts started. Exiting script." -ForegroundColor Green
exit
