# Target Ivanti machines groups
$targetMachinesDNS = "DNS-DNS Critical Servers Phase 1"

# Define Template variables
$PatchScanTemplate = "Windows Server Scan Template"
$PatchDeployTemplate = "Windows Server Deployment Template"

$deploymentDate = Get-Date -Format yyyy-MM-dd_HHmmss

#Start patch scan for DNS
Start-PatchScan -MachineGroups $targetMachinesDNS -TemplateName $PatchScanTemplate -Name "$deploymentDate`_$targetMachinesDNS" | Out-Null

Write-Host "4. Pending patch scan creation." -ForegroundColor Green

#Patch Scan results for DNS
$scanUidDNS = Get-PatchScan -Name "$deploymentDate`_$targetMachinesDNS"
while ($scanUidDNS -eq $null) {
    Start-Sleep -Seconds 5
    $scanUidDNS = Get-PatchScan -Name "$deploymentDate`_$targetMachinesDNS"
}

Write-Host "5. Patch scan created.  Pending scan results." -ForegroundColor Green

#Patch scan results for DNS
$scanResultsDNS = Get-PatchScan -Uid $scanUidDNS.Uid
while ($scanResultsDNS.IsComplete -notlike "True*") {
    Start-Sleep -Seconds 5
    $scanResultsDNS = Get-PatchScan -Uid $scanUidDNS.Uid
}

Write-Host "5. Patch scan complete.  Beginning deployment." -ForegroundColor Green

#Start deployment
$executeDeploymentDNS = Start-PatchDeploy -ScanUid $scanUidDNS.Uid -TemplateName $PatchDeployTemplate

Write-Host "6. Patch deployment now in progress.  Please view progress in the Console.`n" -ForegroundColor Green

#Display patch deployment jobs on screen
Get-PatchDeploy -Uid $executeDeploymentDNS.Uid | ft -AutoSize

Write-Host "Patch deployment has been initiated. Exiting script." -ForegroundColor Green

# Exit the script
exit
