# Import common functions if needed
. "./CommonFunctions.ps1"

$underlineOn = "$([char]27)[4m"
$underlineOff = "$([char]27)[24m"
$boldOn = "$([char]27)[1m"
$boldOff = "$([char]27)[22m"
$italicOn = "$([char]27)[3m"
$italicOff = "$([char]27)[23m"

# Load list of applications for the menu filetoJSON
$appList = "./config/Application.json"
$apps = filetoJSON $appList "Stop"

# Show menu
Write-Host "$underlineOn === Select an Application ==== $underlineOff"
foreach ($property in $apps.PSObject.Properties) {
    Write-Host "$($property.Name) : $italicOn $($property.Value) $italicOff"
}

# Get user's selection
$appNum = Read-Host "Select App. Enter Number"
$appNum = [int]$appNum

$accept = Read-Host "You have selected $boldOn $($apps.PSObject.Properties[$appNum]) $boldOff. Confirm (yes/no): "
while ($accept -inotmatch "yes" -or $accept -inotmatch "y") {
    Write-Host "$italicOn Choose one of below application $italicOff"
    foreach ($property in $apps.PSObject.Properties) {
        Write-Host "$($property.Name) : $italicOn $($property.Value) $italicOff"
    }
    $appNum = Read-Host "Select App. Enter Number"
    $appNum = [int]$appNum
    $accept = Read-Host "You have selected $boldOn $($apps.PSObject.Properties[$appNum]) $boldOff. Confirm (yes/no): "
}

$configName = ".\config\{0}.json" -f $apps.PSObject.Properties[$appNum].Value

try {
    $config = fileToJson $configName "Stop"    
    
    try {
        Write-Host "Validating configuration..."
        checkConfigIsValid $config   
    }
    catch {
        Write-Host "Invalid configuration: $_"
        Exit 1
    }
    
    foreach ($configItem in $config.PSObject.Properties) {
        if ($configItem.Value.enabled) {
            switch ($configItem.Name) {
                1 { comparePath $configItem.Value }
                default { Write-Host "No action mapped for $($configItem.Name)." }
            }
        }
    }
}
catch {
    getWrite-Error "Failed to load configuration: $_"
    Exit 1}


