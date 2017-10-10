#Requires -Version 5

Param (
    [Parameter(Mandatory = $True, Position = 0)]
    [ValidateScript({Test-Path -Path $PSItem})]
    [String] $ProjectPath,

    [Parameter(Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String] $MachineName = "Docker",

    [Parameter(Mandatory = $False)]
    [ValidateSet('BITS', 'WebClient', 'WebRequest')]
    [String] $DownloadMethod = "BITS",

    [Switch] $KeepYAML,

    [Switch] $KeepImages,
    
    [Switch] $Offline
)

# Enforce strict coding rules
Set-StrictMode -Version Latest

# Stop on errors
$ErrorActionPreference = "Stop"

# Unify path parameter
$ProjectPath = (Convert-Path -Path $ProjectPath).TrimEnd("\")

# Check online status
If (-Not (Test-Connection -ComputerName "google.com" -Count 1 -Quiet)) {
    $Offline = $True
    Write-Information "Internet connection test failed. Operating in offline mode..."
}

# Install dependencies if connected to the internet
If (-Not $Offline) {
    Write-Host "Installing dependencies..."

    If (-Not (Get-Module -Name "PSDepend" -ListAvailable)) {
        Install-Module -Name "PSDepend" -Scope CurrentUser
    }

    Invoke-PSDepend -Install -Import -Force

    Install-PackageOnce -Name @("YamlDotNet") -Add
}

# Load project settings
$Settings = Read-Settings -SourcePath @("${ProjectPath}\package.json", "${ProjectPath}\docker-management.json") 

# Ensure required project variables are set
If (-Not (Test-PropertyExists -Object $Settings -PropertyName @("Name", "ComposeFile"))) {
    Throw "Not all required project variables are set."
}

# Project variables
$Name = [String] $Settings.Name
$Owner = [String] $Settings.Owner
$RegistryAddressName = [String] $Settings.RegistryAddress.Name
$RegistryAddressHostname = [String] $Settings.RegistryAddress.Hostname
$RegistryAddressPort = [String] $Settings.RegistryAddress.Port
$ComposeFile = [PSCustomObject] $Settings.ComposeFile

If (-Not (Test-PropertyExists -Object $ComposeFile -PropertyName "Name")) {
    Throw "Compose file name not specified."
}

If (-Not $KeepYAML) {
    Write-Host "Writing compose file..."
    
    $ComposeFileHashtable = Convert-PSCustomObjectToHashtable -InputObject $ComposeFile.Content -YamlDotNet_DoubleQuoted
    [System.IO.File]::WriteAllLines("$ProjectPath\$($ComposeFile.Name)", (New-Yaml -Value $ComposeFileHashtable))
}

# Assemble script variables and examine Docker's context
$Package = $Null

If ($Owner -And $Name) {
    $Package = "${Owner}/${Name}"
} ElseIf ($Name) {
    $Package = $Name
}

$StackGrep = $Null
$NameDns = $Name.replace(".", "-")

If (Test-DockerInSwarm) {
    $StackGrep = Invoke-Docker stack ls |
        Select-String $NameDns

    If (-Not $StackGrep) {
        Write-Host "Stack not found."
    }
} Else {
    Write-Host "Docker not in swarm."
}

$IdImgLocal = Invoke-Docker images -q $Package |
    Out-String |
    ForEach-Object {
    If ($PSItem) {
        Clear-Linebreaks -String $PSItem
    }
}

If (-Not $IdImgLocal) {
    Write-Host "Image not found as local image in image list."
}

$RegistryAddress = "${RegistryAddressHostname}:${RegistryAddressPort}"
$IdImgRegistry = $Null

If ($RegistryAddress) {
    Start-DockerRegistry -RegistryName $RegistryAddressName -Hostname $RegistryAddressHostname -Port $RegistryAddressPort

    $IdImgRegistry = Invoke-Docker images -q "${RegistryAddress}/${Package}" |
        Out-String |
        ForEach-Object {
        If ($PSItem) {
            Clear-Linebreaks -String $PSItem
        }
    }

    If (-Not $IdImgRegistry) {
        Write-Host "Image not found as registry image in image list."
    }
}

### Main tasks

If ($StackGrep) {
    Write-Host "Stopping stack `"${NameDns}`"..."
    Stop-DockerStack -StackName $NameDns
}

If (-Not $KeepImages) {
    If ($IdImgLocal) {
        Write-Host "Removing image `"${IdImgLocal}`" as local image..."
        Invoke-Docker rmi ${IdImgLocal} -f
    }

    If ($IdImgRegistry -And ($IdImgRegistry -Ne $IdImgLocal)) {
        Write-Host "Removing image `"${IdImgRegistry}`" as registry image..."
        Invoke-Docker rmi ${IdImgRegistry} -f
    }

    Write-Host "Building `"${Package}`"..."
    Invoke-Docker build -t ${Package} $ProjectPath

    If ($RegistryAddress) {
        Write-Host "Publishing `"${Package}`" on `"${RegistryAddress}`"..."
        Invoke-Docker tag ${Package} "${RegistryAddress}/${Package}"
        Invoke-Docker push "${RegistryAddress}/${Package}"
    }

    If (-Not (Test-DockerInSwarm)) {
        Write-Host "Initializing swarm..."
        Invoke-Docker swarm init --advertise-addr "eth0:2377"
    }
}

Write-Host "Deploying `"${Package}`" with `"$ProjectPath\$($ComposeFile.Name)`"..."
Mount-EnvFile -EnvFilePath "$ProjectPath\.env"
Invoke-Docker stack deploy -c "$ProjectPath\$($ComposeFile.Name)" $NameDns
