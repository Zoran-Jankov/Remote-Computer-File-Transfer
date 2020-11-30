<#
.SYNOPSIS
This script transfers files to remote computers.

.DESCRIPTION
This script transfers files to remote computers. In '.\Files Paths.txt' file user can write full paths to files for transfer, and
in '.\Remote Computers.txt' user can write list of remote computers to which files are transferred, ether by hostname or IP address.
Script generates detailed log file, '.\File Transfer Log.log', and report that is sent via email to system administrators.

.NOTES
Version:        1.6
Author:         Zoran Jankov
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Clears the contents of the DNS client cache
Clear-DnsClientCache

#Loading script configuration
$Settings = Get-Content "$PSScriptRoot\Settings.cfg" | ConvertFrom-StringData
$PSScriptRoot

#Defining network drive thru which files will be to transferred
$NetworkDrive = "T"

[System.Object[]]$FileList = Get-Content -Path $Settings.FileList
[System.Object[]]$ComputerList = Get-Content -Path $Settings.ComputerList

$SuccessfulTransfers = 0
$FailedTransfers = 0
#-----------------------------------------------------------[Functions]------------------------------------------------------------

Import-Module "$PSScriptRoot\Modules\Write-Log.psm1"
Import-Module "$PSScriptRoot\Modules\Start-FileTransfer.psm1"
Import-Module "$PSScriptRoot\Modules\Send-EmailReport.psm1"

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-Log -Message $Settings.LogTitle -NoTimestamp
Write-Log -Message $Settings.LogSeparator -NoTimestamp

#Get credential from user input
Write-Log -Message "Enter username and password"
$Credential = Get-Credential
Write-Log -Message ("User " + $Credential.UserName + " has entered credentials")

foreach($File in $FileList) {
	if (Test-Path -Path $File) {
		Write-Log -Message "Successfully checked $File file - ready for transfer"
	}
	else {
        $Message = "Failed to access $File file - it does not exist.`nScript stopped - MISSING FILE ERROR"
		Write-Log -Message $Message
		Write-Log -Message $Settings.LogSeparator -NoTimestamp
		Send-EmailReport -Settings $Settings -FinalMessage $Message
		Exit
	}
}
Write-Log -Message "Successfully accessed all files - ready for transfer"

#Start file transfer
foreach ($Computer in $ComputerList) {
    if (Test-Connection -TargetName $Computer -Quiet -Count 1) {
        Write-Log -Message "Successfully connected to $Computer remote computer"
        $Partition = $Settings.Partition
        $NetworkPath = "\\$Computer\$Partition$"
        if (New-PSDrive -Name $NetworkDrive -Persist -PSProvider "FileSystem" -Root $NetworkPath -Credential $Credential) {
            Write-Log -Message "Successfully mapped network drive to $Partition partition on the $Computer remote computer"
            Start-FileTransfer -FileList $FileList -Destination ($NetworkDrive + ":\" + $Settings.TransferFolder) | `
            ForEach-Object {
                $SuccessfulTransfers += $_.Successful
                $FailedTransfers += $_.Failed
            }
            Remove-PSDrive -Name $NetworkDrive
        }
        else {
            Write-Log -Message "Failed to map network drive to C partition on the $Computer remote computer"
            $FailedTransfers += $FileList.Length
	        Write-Log -Message "Canceld file transfer to $Computer remote computer"
        }
	}
    else {
        Write-Log -Message "Failed to connected to $Computer remote computer"
        $FailedTransfers += $FileList.Length
	    Write-Log -Message "Canceld file transfer to $Computer remote computer"
    }
}

if($SuccessfulTransfers -gt 0) {
    Write-Log -Message "Successfully transferred $SuccessfulTransfers files"
}

if ($FailedTransfers -gt 0) {
    Write-Log -Message "Failed to transfer $FailedTransfers files"
}

if(($SuccessfulTransfers -gt 0 ) -and ($FailedTransfers -eq 0)) {
    $Message = "Successfully transferred all files"
}
elseif (($SuccessfulTransfers -gt 0 ) -and ($FailedTransfers -gt 0)) {
    $Message = "Successfully transferred some files with some failed"
}
elseif (($SuccessfulTransfers -eq 0 ) -and ($FailedTransfers -gt 0)) {
    $Message = "Failed to transfer any file"
}
Write-Log -Message $Message
Write-Log -Message $Settings.LogSeparator -NoTimestamp

#Sends email with detailed report and deletes temporary report log file
Send-EmailReport -Settings $Settings -FinalMessage $Message