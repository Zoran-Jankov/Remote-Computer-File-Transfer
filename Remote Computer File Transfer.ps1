<#
.SYNOPSIS
This script transfers files to remote computers.

.DESCRIPTION
This script transfers files to remote computers. In '.\Files Paths.txt' file user can write full paths to files for transfer, and
in '.\Remote Computers.txt' user can write list of remote computers to which files are transferred, ether by hostname or IP address.
Script generates detailed log file, '.\File Transfer Log.log', and report that is sent via email to system administrators.

.NOTES
Version:        1.5
Author:         Zoran Jankov
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------
#Importing modules
Import-Module '.\Write-Log.psm1'
Import-Module '.\Deploy-Folder.psm1'
Import-Module '.\Start-FileTransfer.psm1'
Import-Module '.\Send-Report.psm1'

#Clears the contents of the DNS client cache
Clear-DnsClientCache

#Loading script configuration
$configuration = Get-Content '.\Configuration.cfg' | ConvertFrom-StringData

#Defining network drive thru which files will be to transferred
$networkDrive = "T"

#Initializing report file
New-Item -Path $configuration.ReportFile -ItemType File

$fileList = Get-Content -Path $configuration.FileList
$computerList = Get-Content -Path $configuration.ComputerList

$successfulTransfers = 0
$failedTransfers = 0

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-Log -Message $configuration.LogTitle
Write-Log -Message $configuration.LogSeparator

#Get credential from user input
$credential = Get-Credential

$message = "User " + $credential.UserName + " has entered credentials"
Write-Log -OperationResult Success -Message $message

foreach($file in $fileList)
{
	if((Test-Path -Path $file) -eq $true)
	{
		$message = "Successfully checked " + $file + " file - ready for transfer"
		Write-Log -OperationResult Success -Message $message
	}
	else
	{
        $message = "Failed to access " + $file + " file - it does not exist."
        Write-Log -OperationResult Fail -Message $message
        $message = "Script stopped - MISSING FILE ERROR"
		Write-Log -OperationResult Fail -Message $message
		Write-Log -Message $configuration.LogSeparator
		Send-Report -FinalMessage $message
		Exit
	}
}

Write-Log -OperationResult Success -Message "Successfully accessed all files - ready for transfer"

#Start file transfer
Write-Log -OperationResult Success -Message "Started file transfer"
foreach($computer in $computerList)
{
    if(Test-Connection -TargetName $computer -Quiet -Count 1)
	{
		$message = "Successfully connected to " + $computer + " remote computer"
		Write-Log -OperationResult Success -Message $message

        #Network path creation to D partition on the remote computer
        $partition = "\D$"
		$networkPath = "\\" + $computer + $partition

		#Try to create network drive to D partition on the remote computer
        if(New-PSDrive -Name $networkDrive -Persist -PSProvider "FileSystem" -Root $networkPath -Credential $Credential)
        {
            $message = "Successfully mapped network drive to D partition on the " + $computer + " remote computer"
            Write-Log -OperationResult Success -Message $message
            $operationResult = $true
        }
        else
        {
            $message = "Failed to map network drive to D partition on the " + $computer + " remote computer"
            Write-Log -OperationResult Fail -Message $message

            #Network path creation to C partition on the remote computer
            $partition = "\C$\"
		    $networkPath = "\\" + $computer + $partition
            
            #Try to create network drive to C partition on the remote computer
            if(New-PSDrive -Name $networkDrive -Persist -PSProvider "FileSystem" -Root $networkPath -Credential $Credential)
            {
                $message = "Successfully mapped network drive to C partition on the " + $computer + " remote computer"
                Write-Log -OperationResult Success -Message $message
                $operationResult = $true
            }
            else
            {
                $message = "Failed to map network drive to C partition on the " + $computer + " remote computer - Credential not valid"
                Write-Log -OperationResult Fail -Message $message
                $operationResult = $false
            }
        }
	}
    else
    {
		$message = "Failed to connected to " + $computer + " remote computer"
        Write-Log -OperationResult Fail -Message $message
        $operationResult = $false
    }

    if($operationResult)
    {
        $path = $networkDrive + ":\" + $configuration.TransferFolder

        if(Deploy-Folder -Path $path)
        {
            Start-FileTransfer -FileList $fileList -Destination $path | `
            ForEach-Object {$successfulTransfers += $_.Successful; $failedTransfers += $_.Failed}
        }
        else
        {
            $failedTransfers += $fileList.Length
            $message = "Canceld file transfer to " + $computer + " remote computer"
	        Write-Log -OperationResult Fail -Message $message
        }
        
        #Network drive removal
        if($operationResult)
        {
            Remove-PSDrive -Name $networkDrive
        }
    }
    else
    {
        $failedTransfers += $fileList.Length
        $message = "Canceld file transfer to " + $computer + " remote computer"
	    Write-Log -OperationResult Fail -Message $message
    }
}

if($successfulTransfers -gt 0)
{
    $message = "Successfully transferred " + $successfulTransfers + " files"
    Write-Log -OperationResult Success -Message $message
}

if($failedTransfers -gt 0)
{
    $message = "Failed to transfer " + $failedTransfers + " files"
    Write-Log -OperationResult Fail -Message $message
}

if(($successfulTransfers -gt 0 ) -and ($failedTransfers -eq 0))
{
    $message = "Successfully transferred all files"
    Write-Log -OperationResult Success -Message $message
}
elseif(($successfulTransfers -gt 0 ) -and ($failedTransfers -gt 0))
{
    $message = "Successfully transferred some files with some failed"
    Write-Log -OperationResult Partial -Message $message
}
elseif(($successfulTransfers -eq 0 ) -and ($failedTransfers -gt 0))
{
    $message = "Failed to transfer any file"
    Write-Log -OperationResult Fail -Message $message
}

Write-Log -Message $configuration.LogSeparator

#Sends email with detailed report and deletes temporary report log file
Send-Report -FinalMessage $message