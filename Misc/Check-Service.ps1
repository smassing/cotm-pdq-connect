# Name: Test-Service.ps1 
# Author: Chris Harris 
# Version: 1.0 
# Updated: 10/26/2008 
# Description: Checks whether a service is running attempts to start it 
# sends email with results of start attempt 
# Requires: None 
# Usage: .\Test-service.ps1 -service:ServiceName 
# Todo: Make email optional 
# Make email more generic 
# Get Parameters 
param( [string] $service = $(Throw "Please specify the name of the Service [-service]."), [switch] $email ) 

function send-email($SmtpServer,$From,$To,$subject,$Body)
{ 
	$smtp = new-object system.net.mail.smtpClient($SmtpServer) 
	$mail = new-object System.Net.Mail.MailMessage 
	$mail.From = $From 
	$mail.To.Add($To) 
	$mail.Subject = $subject 
	$mail.Body = $Body 
	#$mail.IsBodyHtml = $true $smtp.Send($mail) 
} 

# If you're going to be checking for a specific service all the time, 
# just enable this block and set the variables appropriately so you 
# don't have to pass them at the commandline every time 
#$service = "smtp" 
#$email = $true 
#$smtpServer = "mailserver" 
#$from = "ServiceMonitor@domain.local" 
#$to = "myEmail@domain.local" 
#$subject = "$service Down Alert" 
if ((Get-Service $service).Status -ne "Running") 
{ 
	$Error.Clear() 
	# Attempt to start the service Start-Service 
	$service 
	if ($Error)
	{ 
		$Body = "The [$service] service could not be started. The error was:" 
		$Body += `n+$Error 
	} 
	else 
	{ 
		$Body = "The [$service] service was found to be stopped and has been started." 
	} 
	
	if ($email){
		Write-Host $body + `n Write-Host "Sending email..." 
		$Error.clear 
		send-email -smtpServer $smtpServer -from $from -to $to -subject $subject -body $body 
		if (!$Error){ 
			Write-Host "Email sent successfully." 
		} 
	} 
} 
else
{ 
	Write-Host "The [$service] service is running." 
} 
