<#
.SYNOPSIS
This script transfers files to remote computers.

.DESCRIPTION
This script transfers files to remote computers. In '.\Files Paths.txt' file user can write full paths to files for transfer, and
in '.\Remote Computers.txt' user can write list of remote computers to which files are transferred, ether by hostname or IP address.
Script generate detailed log file and report that is sent via email to administrators.

.NOTES
	Version:        1.2
	Author:         Zoran Jankov
	Creation Date:  06.07.2020.
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
$ErrorActionPreference = "SilentlyContinue"

#Clears the contents of the DNS client cache.
Clear-DnsClientCache

#Defining network drive thru which files will be to transferred
$networkDrive = "T"

#Defining folder for file transfer in which files will be to transferred
$transferFolder = "\Transfer Folder"

#Defining log files
$logfile = '.\File Transfer Log.txt'
New-Item -Path '.\Report.txt' -ItemType File
$report = '.\Report.txt'

#Defining log separator
$logSeparator = "===================================================================================================="

#Loading file paths and remote computers
$filesPaths = Get-Content -Path '.\Files Paths.txt'
$remoteComputers = Get-Content -Path '.\Remote Computers.txt'

#Mail settings (enter your on mail settings)
$receiverEmail = "itadministrator@company.com"
$senderEmail = "powershell@company.com"
$subject = "File Transfer Report"
$smpt = "smpt.mail.com"
$port = 25

#-----------------------------------------------------------[Functions]------------------------------------------------------------

<#
.SYNOPSIS
Writes a log entry

.DESCRIPTION
Creates a log entry with timestamp and message passed thru a parameter $Massage, and saves the log entry to log file
".\File Transfer Log.txt"

.PARAMETER Message
String value to be writen in the log file alongside timestamp

.EXAMPLE
Write-Log -Message "File sorting started"

.NOTES
Format of the timestamp in "yyyy.MM.dd. HH:mm:ss" and this function adds " - " after timestamp and before the main massage.
#>
function Write-Log
{
    param([String]$Message)

	if($Message -eq $logSeparator)
	{
		Add-content -Path $logfile -Value $logSeparator
		Add-content -Path $report -Value $logSeparator
		Write-Output - $logSeparator
	}
	else
	{
		$timestamp = Get-Date -Format "yyyy.MM.dd. HH:mm:ss"
    	$logEntry = $timestamp + " - " + $Message
		Add-content -Path $logfile -Value $logEntry
		Add-content -Path $report -Value $logEntry
		Write-Output - $logEntry
	}
}

function Send-Report
{
	$body = Get-Content -Path $report -Raw
	Send-MailMessage -To $receiverEmail -From $senderEmail -Subject $subject -Body $body -SmtpServer $smpt -Port $port
}

<#
.SYNOPSIS
Creates transfer folder if it does not already exists

.DESCRIPTION
This function check if defined transfer folder exists and if not it creates it on remote computer

.PARAMETER Path
Full path of the folder.

.EXAMPLE
Deploy-TransferFolder -Path "\\RemoteComputer\D$\Transfer Folder"

#>
function Deploy-TransferFolder
{
    param([String]$Path)

    if((Test-Path $Path) -eq $false)
    {
		$message = $networkDrive + $transferFolder + " does not exists"
		Write-Log -Message $message

		New-Item -Path $Path -ItemType "Directory"

		$message = $networkDrive + $transferFolder + " folder created"
		Write-Log -Message $message
	}
	else
	{
		$message = $networkDrive + $transferFolder + " folder checked and present"
		Write-Log -Message $message
	}
}

<#
.SYNOPSIS
Transfers files from '.\Files Paths.txt' list to remote computer.

.DESCRIPTION
Transfers files from '.\Files Paths.txt' list to remote computer. Log errors while file transfering.

.PARAMETER DestinationPath
Full path to file transfer folder.

.PARAMETER Computer
Name of the remote computer to which files are being transferred.

#>
function Start-FileTransfer
{
	param([string]$DestinationPath, [string]$Computer)

	foreach($file in $filesPaths)
	{
		try
		{
			#File name extraction from file full path
			$fileName = Split-Path $file -leaf

			$massage = "Transferring file " + $fileName + " file to " + $Computer + "..."
			Write-Log -Message $massage
			Copy-Item -Path $file -Destination $DestinationPath
			$massage = "File " + $fileName + " transferred to " + $Computer
			Write-Log -Message $massage
		}
		catch
		{
			$massage = "ERROR - Fail to transfer " + $fileName + " file to " + $Computer
			Write-Log -Message $massage
			Write-Log -Message $_.Exception
        	Break
		}
	}
	$massage = "All files transferred to " + $Computer
		Write-Log -Message $massage
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Welcome message
Write-Log -Message $logSeparator
Write-Output "Remote Computer File Transfer"

#Get username and password from prompt
$user = Read-Host -Prompt "Enter username"
$password = Read-Host -Prompt "Enter password" -AsSecureString
$massage = "User " + $user + " entered credentials"
Write-Log -Message $massage

#Create credentials
$credentials = New-Object -TypeName System.Management.Automation.PSCredential($user, $password)

Write-Log -Message "Checking files for transfer..."

foreach($file in $filesPaths)
{
	if((Test-Path -Path $filesPaths) -eq $false)
	{
		$massage = "ERROR - " + $file + " file is missing"
		Write-Log -Message $massage
		Write-Log -Message "Script stopped because of MISSING FILE ERROR"
		Write-Log -Message $logSeparator
		Send-Report
		Exit
	}
	else
	{
		$massage = $file + " file is is ready for transfer"
		Write-Log -Message $massage
	}
}

Write-Log -Message "All files are checked and present"

#Start file transfer
Write-Log -Message "File transfer started..."
foreach($computer in $remoteComputers)
{
	if(Test-Connection $computer -Quiet -Count 1)
	{
		#Transfer network drive full path creation
		$networkDrive = "\\" + $computer + "\D$"

		$massage = "Trying to map network drive to " + $computer + "..."
		Write-Log -Message $massage

		#Try to create network drive with given path
		try
		{
			New-PSDrive -Name "T" -PSProvider "FileSystem" -Root $networkDrive -Credential $credentials
		}
		catch
		{
			$massage = "ERROR - Fail to map network drive to " + $computer
			Write-Log -Message $massage
			Write-Log -Message $_.Exception
        	Break
		}

		$massage = "Network drive mapped to " + $computer
		Write-Log -Message $massage
		
		#Transfer fodler full path creation
		$destinationPath = "T:" + $transferFolder
		Deploy-TransferFolder -Path $destinationPath
		
		#Start transfering files to remote computer
		Start-FileTransfer -DestinationPath $destinationPath -Computer $computer

		#Network drive removal
		Remove-PSDrive -Name $networkDrive
		$massage = "Network drive removed from " + $computer
		Write-Log -Message $massage
	}
    else
    {
		$message = "ERROR - " + $computer + "not reachable"
		Write-Log -Message $massage
    }
}

Write-Log -Message "File transfer finished successfully"
Write-Log -Message $logSeparator

#Sends email with detailed report and deletes temporary ".\Report.txt" file
Send-Report
Remove-Item -Path $report