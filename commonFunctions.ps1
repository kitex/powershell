function filetoJSON($filename, $errorAction) {
    return Get-Content $filename -Raw -Encoding UTF8 -ErrorAction $errorAction | ConvertFrom-Json
}

function createSSHSession($adent, $tokenPin, $computername) {
    $token = Read-Host -Prompt "Enter Token (wait for it to change)"
    $passcode = $tokenPin + $token
    Write-Host "Creating session for $adent to $computername using $passcode"
    $credential = New-Object System.Management.Automation.PSCredential($adent, (ConvertTo-SecureString $passcode -AsPlainText -Force))
    $session = New-SSHSession -ComputerName $computername -Credential $credential -AcceptKey -ErrorAction Stop 
    return $session
}

function invokeSSHCommand($command, $sessionId) {
    $result = Invoke-SSHCommand -SessionId $sessionId -Command $command
    return $result
}

function readPassWord() {
    $securestring = Read-Host -Prompt "Enter Token Pin" -AsSecureString
    $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securestring))
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securestring)) #securly clear the securestring from memory
    return $plainText
}

function createSSHSessions($adent, $tokenPin, $serverList) {
    $sessionArray = @()   
    foreach ($server in $serverList) {
        Write-Host "Creating session for $adent to $server"
        $session = createSSHSession $adent $tokenPin $server
        $tuple = [Tuple]::Create($session, $server)
        $sessionArray += $tuple
    }
    return $sessionArray
}

function closeAllSessions() {
    Get-SSHSession | Remove-SSHSession | Out-Null
}


function IdentifyCommandToCompareHash($path, $sessionId) {
    $typeCommand = "stat --format '%F' $path"
    $pathType = invokeSSHCommand $typeCommand $sessionId


    if (($pathType.Output[0]) -eq "directory") {
        #if path type is directory
        return "find $path -type f -exec sha256sum {} + | sort | sha256sum | cut -d ' ' -f1"
    }
    elseif (($pathType.Output[0] -eq "regular file") -or ($pathType.Output[0] -eq "regular empty file")) {
        #if path type is file
        return "sha256sum $path | cut -d ' ' -f1"
    }
    else {
        Write-Host "Please check path as file type is not valid. (IdentifyCommandToCompareHash)"
        throw "Invalid path $path"
    }
}


#check edge cases for config file
function checkConfigIsValid($config) {
    $prodServers = $config.prod_servers -split ";"
    $bcpServers = $config.bcp_servers -split ";"
    $prodPaths = $config.prod_dir -split ";"
    $bcpPaths = $config.bcp_dir -split ";"

    Write-Host "$prodPaths vs $bcpPaths"
    if ($prodPaths.Length -ne $bcpPaths.Length) {
        throw "Number of prod paths and bcp paths do not match."
    }

    if ($prodServers.Length -lt 1 -or $bcpServers.Length -lt 1) {
        throw "At least one prod and one bcp server must be specified."
    }
}

function addToCSV($row, $csvPath) {
    # Check if file exists
    if (Test-Path $csvPath) {
        # File exists, just append
        $row | Export-Csv -Path $csvPath -Append -NoTypeInformation
    }
    else {
        # File doesn't exist, create new with headers
        $row | Export-Csv -Path $csvPath -NoTypeInformation
    }
}
   


function comparePath($config) {


    Write-Host "Cleaning all SSH Sessions..."
    closeAllSessions
    Write-Host "All SSH sessions closed."


    # Read source and destination hosts and paths to be compared
    $prodServers = $config.prod_servers -split ";"
    $bcpServers = $config.bcp_servers -split ";"
    $prodPaths = $config.prod_dir -split ";"
    $bcpPaths = $config.bcp_dir -split ";"
    $csvPath = "./output.csv"

    #check if config is good for selected option
    try {
        Write-Host "Validating configuration... $config"
        checkConfigIsValid $config   
    }
    catch {
        Write-Host "Invalid configuration: $_"
        Exit 1
    }

    
    $adent = Read-Host -Prompt "Enter your AD-ENT ID"
    $tokenPin = readPassWord
    Write-Host "Note: Please enter only token from RSA SecurID."
    Start-Sleep -Seconds 3
    $checksumResults = @()


    $prodSessions = $null
    $referenceSession = $null
    $referenceServer = $prodServers[0]

    #get reference server session and all prod sessions
    if ($prodServers.Length -gt 1) {
        $referenceSession = createSSHSession $adent $tokenPin $referenceServer
        $prodSessions = createSSHSessions $adent $tokenPin $prodServers[1..($prodServers.Length - 1)]
    }
    else {
        $referenceSession = createSSHSession $adent $tokenPin $prodServers[0]
    }

    #get session for bcp servers
    $bcpSessions = createSSHSessions $adent $tokenPin $bcpServers
    
    Clear-Host
    Write-Host "Completed Creating SSH session to all prod and bcp servers---------------"

    $i = 0
    foreach ($bcpPath in $bcpPaths) {
        Write-Host "-------------------For Each BCP Path $bcpPath--------------------------------"
        # Get first path hash from reference prod server for each bcp path        
        try {            
            $prodPath = $prodPaths[$i]        
            $referenceCommand = IdentifyCommandToCompareHash $prodPath $referenceSession.SessionId
            Write-Host "Getting checksum for reference server $($referenceServer) $($prodPaths[$i])  using $referenceCommand "
            $referenceCheckSum = Invoke-SSHCommand -Session $referenceSession.SessionId -Command $referenceCommand            
            Write-Host "Got checksum for reference server $($referenceCheckSum.Output[0]) $($referenceServer)"
        }
        catch {
            Write-Host "Error executing $referenceCommand for reference server $($referenceServer) $($prodPath).Check path and server name"
            Write-Host "Error: $($_.Exception.Message)"   
            $row = [PSCustomObject]@{
                ReferenceServer = $referenceServer
                CheckedServer   = $referenceServer
                Result          = "Not Ok"
                Remarks         = "Error Checking checksum for reference server $($referenceServer) $($prodPath). Check path and server name"
            }
            addToCSV $row $csvPath         
            i++
            continue
        }
        
        if ($prodServers.Length -gt 1) { 
            foreach ($prodSession in $prodSessions) {
                $row = $null
                try {
                    Write-Host "Getting checksum for Prod $($prodSession.Item2) $($prodPaths[$i])"      
                    $command = IdentifyCommandToCompareHash $($prodPaths[$i]) $prodSession.Item1.SessionId
                    Write-Host "Command to be executed: $command at $($prodSession.Item2)"
                    $checksumProd = Invoke-SSHCommand -SessionId $prodSession.Item1.SessionId -Command $command
                    Write-Host "Command executed: $command at $($prodSession.Item2)"
                }
                catch {
                    Write-Host "Error executing for Prod $($prodSession.Item2) $($prodPaths[$i]) vs $($referenceServer) $($prodPath)"
                    Write-Host "Error: $($_.Exception.Message)"
                    $row = [PSCustomObject]@{
                        ReferenceServer = $referenceServer
                        CheckedServer   = $prodSession.Item2
                        Result          = "Not Ok"
                        Remarks         = "Checksum not equal for Prod $($prodSession.Item2) $($prodPaths[$i]) vs $($referenceServer) $($prodPath)"
                    }
                    addToCSV $row $csvPath
                    continue
                }
               
               
                if ($checksumProd.Output[0] -eq $referenceCheckSum.Output[0]) {
                    Write-Host "Checksum equal for Prod $($prodSession.Item2) $($prodPaths[$i]) vs $($referenceServer) $($prodPath)"
                    $row = [PSCustomObject]@{
                        ReferenceServer = $referenceServer
                        CheckedServer   = $prodSession.Item2
                        Result          = "Ok"
                        Remarks         = "Checksum equal for Prod $($prodSession.Item2) $($prodPaths[$i]) vs $($referenceServer) $($prodPath)"
                    }
                }
                else {
                    Write-Host "Checksum not equal for Prod $($prodSession.Item2) $($prodPaths[$i]) vs $($referenceServer) $($prodPath)"
                    $row = [PSCustomObject]@{
                        ReferenceServer = $referenceServer
                        CheckedServer   = $prodSession.Item2
                        Result          = "Not Ok"
                        Remarks         = "Checksum not equal for Prod $($prodSession.Item2) $($prodPaths[$i]) vs $($referenceServer) $($prodPath)"
                    }
                }
                
                addToCSV $row $csvPath
                Write-Host "---------------Prod Check complete------------------------------------"
            }
        }

        foreach ($bcpSession in $bcpSessions) {
            $row = $null
            $checksumBCP = $null
            try {
                $command = IdentifyCommandToCompareHash $bcpPath $bcpSessions.Item1.SessionId
                Write-Host "Command to be executed: $($command) at $($bcpSession.Item2)"
                $checksumBCP = Invoke-SSHCommand -SessionId $bcpSession.Item1.SessionId -Command $command
                Write-Host "Command executed: $($command) at $($bcpSession.Item2)"
            }
            catch {
                Write-Host "Error executing for BCP $($bcpSession.Item2) $($bcpPaths[$i]) vs $($referenceServer) $($prodPath)"
                Write-Host "Error: $($_.Exception.Message)"
                $row = [PSCustomObject]@{
                    ReferenceServer = $referenceServer
                    CheckedServer   = $bcpSession.Item2
                    Result          = "Not Ok"
                    Remarks         = "Error executing for BCP $($bcpSession.Item2) $($bcpPaths[$i]) vs $($referenceServer) $($prodPath)"
                }
                addToCSV $row $csvPath
                continue
            }
            
            if ($checksumBCP.Output[0] -eq $referenceCheckSum.Output[0]) {
                Write-Host "Checksum equal for BCP $($bcpSession.Item2) $($bcpPaths[$i]) vs $($referenceServer) $($prodPath)"
                $row = [PSCustomObject]@{
                    ReferenceServer = $referenceServer
                    CheckedServer   = $bcpSession.Item2
                    Result          = "Ok"
                    Remarks         = "Checksum equal for BCP $($bcpSession.Item2) $($bcpPaths[$i]) vs $($referenceServer) $($prodPath)"
                }
            }
            else {
                Write-Host "Checksum not equal for BCP $($bcpSession.Item2) $($bcpPaths[$i]) vs $($referenceServer) $($prodPath)"
                $row = [PSCustomObject]@{
                    ReferenceServer = $referenceServer
                    CheckedServer   = $bcpSession.Item2
                    Result          = "Not Ok"
                    Remarks         = "Checksum not equal for BCP $($bcpSession.Item2) $($bcpPaths[$i]) vs $($referenceServer) $($prodPath)"
                }
            }
            # Check if file exists
            addToCSV $row $csvPath

            Write-Host "-----------------BCP Check Complete----------------------------------"
        }
        $i++
    }

    closeAllSessions
    Write-Host "All sessions closed."
}
