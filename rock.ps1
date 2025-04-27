$credential = New-Object System.Management.Automation.PSCredential ("sugandha", (ConvertTo-SecureString "su12ga34ND56#" -AsPlainText -Force))
$session = New-SSHSession -ComputerName 192.168.0.17 -Credential $credential -ErrorAction Stop 
$sessionId = $session.SessionId
Write-Host $sessionId
$command = "find /home/sugandha/test -type f -exec sha256sum {} + | sort | sha256sum | cut -d ' ' -f1"
#$command = "ls -lha --time-style=long-iso"
$result = Invoke-SSHCommand -Session $sessionId -Command $command
$result
#$result.Output

# Store the output in an ArrayList
$outputArrayList = [System.Collections.ArrayList]@()
$outputArrayList.AddRange($result.Output)
# Print the ArrayList to verify
$outputArrayList | ForEach-Object {
    # Split the line into parts
    $parts = $_ -split '\s+'
    Write-Output $parts
    if ($parts.Length -ge 8) {
        # Extract the date parts (assuming standard `ls -ltr` output)
        Write-Host  $($parts[0]), $($parts[1]), $($parts[3])
       # Write-Host $_
    } else {
        Write-Host $_
    }
}
#End-SSHSession -SessionId $sessionId

Get-ChildItem -Path "C:\Path\To\Folder" -Recurse -File |
Sort-Object FullName |
Get-FileHash -Algorithm SHA256 |
ForEach-Object { $_.Hash } | Out-String |
Get-FileHash -Algorithm SHA256