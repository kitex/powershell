$credential = New-Object System.Management.Automation.PSCredential ("sugandha", (ConvertTo-SecureString "su12ga34ND56#" -AsPlainText -Force))
$session = New-SSHSession -ComputerName 192.168.0.17 -Credential $credential -ErrorAction Stop 
$sessionId = $session.SessionId
Write-Host $sessionId
$command = "find /home/sugandha/test -type f -exec sha256sum {} + | sort | sha256sum | cut -d ' ' -f1"

foreach($i in 1..){

}