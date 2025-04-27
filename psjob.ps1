$scriptBlock = {
    param(
        [string]$Computer,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$Command
    )
    $SessionId = New-SSHSession -ComputerName $Computer -Credential $Credential -ErrorAction Stop -AcceptKey -AcceptKey: $true
    Write-Host $SessionId
    if ($SessionId -ne $null) {
        # Execute command
        $Result = Invoke-SSHCommand -SSHSession $SessionId -Command $Command
        Write-Host "Output from $Computer : $($Result.Output)"        
        # Close session
        Remove-SSHSession -SessionId $Session.SessionId
    } else {
        Write-Warning "Could not create SSH session for $Computer"
    }
}

$computers = Get-Content -Path ".\ips" # Replace with your file path
$hashTableOfJobs = @{}
$Username = Read-Host -Prompt "Enter username"
$Password = Read-Host -AsSecureString "Enter password for $username"
foreach ($computer in $computers) {
    Write-Host "Creating job for $computer"
    $Credential = New-Object System.Management.Automation.PSCredential ($Username, $Password)
    $hashTableOfJobs[$computer] = Start-Job -Name $computer -ScriptBlock $scriptBlock -ArgumentList $computer, $Credential, $Command #-ErrorAction SilentlyContinue  
}

$finishedJobs = $hashTableOfJobs.Values | Wait-Job -Timeout 10
Write-Host $hashTableOfJobs.Values.Count
if ($finishedJobs.Count -ne $hashTableOfJobs.Count) {
   Write-Warning "$($finishedJobs.Count)  of $($hashTableOfJobs.Count) jobs finished"
}

#remove job in loop
foreach ($job in Get-Job | Where-Object {$_.State -eq "completed"}){ Remove-job $($job.ID)} 
