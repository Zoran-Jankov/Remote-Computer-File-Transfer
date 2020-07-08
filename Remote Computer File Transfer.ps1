<#
.SYNOPSIS
This script transfers files to remote computers.

.DESCRIPTION
This script transfers files to remote computers. In '.\Files Paths.txt' file user can write full paths to files for transfer, and
in '.\Remote Computers.txt' user can write list of remote computers to which files are transferred, ether by hostname or IP address.
Script generates detailed log file, '.\File Transfer Log.log', and report that is sent via email to system administrators.

.NOTES
	Version:        1.3
	Author:         Zoran Jankov
	Creation Date:  06.07.2020.
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
$ErrorActionPreference = "SilentlyContinue"

#Clears the contents of the DNS client cache
Clear-DnsClientCache

#Defining network drive thru which files will be to transferred
$networkDrive = "T"

#Defining folder for file transfer in which files will be to transferred
$transferFolder = "\Transfer Folder"

#Defining log files
$logfile = '.\File Transfer Log.log'
New-Item -Path '.\Report.log' -ItemType File
$report = '.\Report.log'

#Defining log title
$logTitle = "======================= Remote Computer File Transfer PowerShell Script Log ========================"

#Defining log separator
$logSeparator = "===================================================================================================="

#Loading file paths and remote computers
$filesPaths = Get-Content -Path '.\Files Paths.txt'
$remoteComputers = Get-Content -Path '.\Remote Computers.txt'

#Mail settings (enter your on mail settings)
$smtp = "smtp.mail.com"
$port = 25
$receiverEmail = "system.administrators@company.com"
$senderEmail = "powershell@company.com"
$subject = "File Deletion Report"
$body = "This is an automated message sent from PowerShell script. Remote Computer File Transfer script has finished executing."

#-----------------------------------------------------------[Functions]------------------------------------------------------------

<#
.SYNOPSIS
Writes a log entry

.DESCRIPTION
Creates a log entry with timestamp and message passed thru a parameter $Message, and saves the log entry to log file
".\File Transfer Log.txt" Timestamp is not written if $Message parameter is defined $logSeparator.

.PARAMETER Message
String value to be writen in the log file alongside timestamp

.EXAMPLE
Write-Log -Message "Successfully transferred"

.NOTES
Format of the timestamp in "yyyy.MM.dd. HH:mm:ss:fff" and this function adds " - " after timestamp and before the main message.
#>
function Write-Log
{
    param([String]$Message)

	if(($Message -eq $logSeparator) -or ($Message -eq $logTitle))
	{
		Add-content -Path $logfile -Value $Message
		Add-content -Path $report -Value $Message
		Write-Output - $Message
	}
	else
	{
		$timestamp = Get-Date -Format "yyyy.MM.dd. HH:mm:ss:fff"
    	$logEntry = $timestamp + " - " + $Message
		Add-content -Path $logfile -Value $logEntry
		Add-content -Path $report -Value $logEntry
		Write-Output - $logEntry
	}
}

<#
.SYNOPSIS
Sends a Report.log file to defined email address

.DESCRIPTION
This function sends a Report.log file as an attachment to defined email address
#>
function Send-Report
{
    Send-MailMessage -SmtpServer $smtp `
                     -Port $port `
                     -To $receiverEmail `
                     -From $senderEmail `
                     -Subject $subject `
                     -Body $body `
                     -Attachments $report

	Remove-Item -Path $report
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

	$message = "Attempting to access " + $networkDrive + $transferFolder + " folder"
	Write-Log -Message $message

    if((Test-Path $Path) -eq $false)
    {
		$message = "Failed to access " + $networkDrive + $transferFolder + " folder - does not exist"
		Write-Log -Message $message

		$message = "Attempting to create " + $networkDrive + $transferFolder + " folder"
		Write-Log -Message $message

		New-Item -Path $Path -ItemType "Directory"

		$message = "Successfully created " + $networkDrive + $transferFolder + " folder"
		Write-Log -Message $message
	}
	else
	{
		$message = "Successfully accessed " + $networkDrive + $transferFolder + " folder"
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
		#File name extraction from file full path
		$fileName = Split-Path $file -leaf

		$message = "Attempting to transfer " + $fileName + " file to " + $Computer + " remote computer"
		Write-Log -Message $message
		
		try
		{
			Copy-Item -Path $file -Destination $DestinationPath
			$message = "Successfully transferred " + $fileName + " file to " + $Computer + " remote computer"
			Write-Log -Message $message
		}
		catch
		{
			$message = "Failed to transfer " + $fileName + " file to " + $Computer + " remote computer"
			Write-Log -Message $message
			Write-Log -Message $_.Exception
		}
	}

	$message = "Successfully transferred files to " + $Computer + " remote computer"
	Write-Log -Message $message
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-Log -Message $logTitle
Write-Log -Message $logSeparator

#Get username and password from prompt
$user = Read-Host -Prompt "Enter username"
$password = Read-Host -Prompt "Enter password" -AsSecureString
$message = "User " + $user + " entered credentials"
Write-Log -Message $message

#Create credentials
$credentials = New-Object -TypeName System.Management.Automation.PSCredential($user, $password)

Write-Log -Message "Attempting to access files for transfer"

foreach($file in $filesPaths)
{
	if((Test-Path -Path $filesPaths) -eq $false)
	{
		$message = "Failed to access " + $file + " file. It does not exist."
		Write-Log -Message $message
		Write-Log -Message "Script stopped - MISSING FILE ERROR"
		Write-Log -Message $logSeparator
		Send-Report
		Exit
	}
	else
	{
		$message = "Successfully accessed " + $file + " file - ready for transfer."
		Write-Log -Message $message
	}
}

Write-Log -Message "Successfully accessed all files - ready for transfer."

#Start file transfer
Write-Log -Message "Started file transfer"
foreach($computer in $remoteComputers)
{
	$message = "Attempting to access " + $computer + " remote computer"
	Write-Log -Message $message

	if(Test-Connection $computer -Quiet -Count 1)
	{
		$message = "Successfully accessed " + $computer + " remote computer"
		Write-Log -Message $message

		#Transfer network drive full path creation
		$networkDrive = "\\" + $computer + "\D$"

		$message = "Attempting to map network drive to " + $computer + " remote computer"
		Write-Log -Message $message

		#Try to create network drive with given path
		try
		{
			New-PSDrive -Name "T" -PSProvider "FileSystem" -Root $networkDrive -Credential $credentials
		}
		catch
		{
			$message = "Failed to map network drive to " + $computer + " remote computer"
			Write-Log -Message $message
			Write-Log -Message $_.Exception
        	Break
		}

		$message = "Successfully mapped network drive to " + $computer + " remote computer"
		Write-Log -Message $message

		#Transfer fodler full path creation
		$destinationPath = "T:" + $transferFolder
		Deploy-TransferFolder -Path $destinationPath
		
		#Start transfering files to remote computer
		Start-FileTransfer -DestinationPath $destinationPath -Computer $computer

		#Network drive removal
		Remove-PSDrive -Name $networkDrive
		$message = "Successfully removed network drive from " + $computer + " remote computer"
		Write-Log -Message $message
	}
    else
    {
		$message = "Failed to access " + $computer + " remote computer"
		Write-Log -Message $message
    }
}

Write-Log -Message "Successfully finished file transfer"
Write-Log -Message $logSeparator

#Sends email with detailed report and deletes temporary ".\Report.txt" file
Send-Report