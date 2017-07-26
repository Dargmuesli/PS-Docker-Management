#Requires -Version 5

# Get the path to the project this script is used on
Param (
    [Parameter(Mandatory = $True, Position = 0)]
    [ValidateScript({Test-Path -Path $PSItem})]
    [String] $ProjectPath,

    [Parameter(Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [String] $MachineName = "Docker",

    [Parameter(Mandatory = $False)]
    [ValidateSet('BITS', 'WebClient', 'WebRequest')]
    [String] $DownloadMethod = "BITS"
)

# Enforce desired coding rules
Set-StrictMode -Version Latest

# Stop on errors
$ErrorActionPreference = "Stop"

# Unify path parameter
$ProjectPath = (Convert-Path -Path $ProjectPath).TrimEnd("\")

# Install dependencies if connected to the internet
If (Test-Connection -ComputerName "google.com" -Count 1 -Quiet) {
    While (-Not (Get-Module -ListAvailable -Name "PSDepend")) {
        If ($PSVersionTable.PSVersion.Major -Ge 5) {
            Install-Module -Name "PSDepend" -Scope CurrentUser
        } ElseIf (($PSVersionTable.PSVersion.Major -Eq 3) -Or ($PSVersionTable.PSVersion.Major -Eq 4)) {
            Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://raw.github.com/ramblingcookiemonster/PSDepend/Examples/Install-PSDepend.ps1')
        }
    }

    Write-Output "Checking dependencies..."

    If (-Not (Invoke-PSDepend .\ -Test -Quiet)) {
        Write-Output "Installing dependencies..."
        Invoke-PSDepend -Force
    }
}

# Load project settings
$Settings = Read-Settings -SourcePath @("${ProjectPath}\package.json", "${ProjectPath}\docker-management.json")

# Ensure required project variables are set
If (-Not (Get-Member -InputObject $Settings -Name "Name" -Membertype Properties)) {
    Throw "Name not specified."
}

If (-Not (Get-Member -InputObject $Settings -Name "ComposeFile" -Membertype Properties)) {
    Throw "Compose file not specified."
}

# Project variables
$Name = [String] $Settings.Name
$Owner = [String] $Settings.Owner
$RegistryAddressName = [String] $Settings.RegistryAddress.Name
$RegistryAddressHostname = [String] $Settings.RegistryAddress.Hostname
$RegistryAddressPort = [String] $Settings.RegistryAddress.Port
$ComposeFile = [PSCustomObject] $Settings.ComposeFile

If (-Not $ComposeFile.Name) {
    Throw "Compose file name not specified."
}

Write-Output "Writing compose file..."
Write-DockerComposeFile -ComposeFile $ComposeFile -Path $ProjectPath -Force

# Ensure Docker is running
Start-Docker -MachineName $MachineName -DownloadMethod $DownloadMethod

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
    $StackGrep = docker stack ls |
        Select-String $NameDns
    
    If (-Not $StackGrep) {
        Write-Output "Stack not found."
    }
} Else {
    Write-Output "Docker not in swarm."
}

$IdImgLocal = docker images -q $Package |
    Out-String |
    ForEach-Object {
    If ($PSItem) {
        Clear-Linebreaks -String $PSItem
    }
}

If (-Not $IdImgLocal) {
    Write-Output "Image not found as local image in image list."
}

$RegistryAddress = "${RegistryAddressHostname}:${RegistryAddressPort}"
$IdImgRegistry = $Null

If ($RegistryAddress) {
    Start-DockerRegistry -RegistryName $RegistryAddressName -Hostname $RegistryAddressHostname -Port $RegistryAddressPort

    $IdImgRegistry = docker images -q "${RegistryAddress}/${Package}" |
        Out-String |
        ForEach-Object {
        If ($PSItem) {
            Clear-Linebreaks -String $PSItem
        }
    }

    If (-Not $IdImgRegistry) {
        Write-Output "Image not found as registry image in image list."
    }
}

### Main tasks

If ($StackGrep) {
    Write-Output "Stopping stack `"${NameDns}`"..."
    Stop-DockerStack -StackName $NameDns
}

If ($IdImgLocal) {
    Write-Output "Removing image `"${IdImgLocal}`" as local image..."
    docker rmi ${IdImgLocal} -f
}

If ($IdImgRegistry -And ($IdImgRegistry -Ne $IdImgLocal)) {
    Write-Output "Removing image `"${IdImgRegistry}`" as registry image..."
    docker rmi ${IdImgRegistry} -f
}

Write-Output "Building `"${Package}`"..."
docker build -t ${Package} $ProjectPath

If ($RegistryAddress) {
    Write-Output "Publishing `"${Package}`" on `"${RegistryAddress}`"..."
    docker tag ${Package} "${RegistryAddress}/${Package}"
    docker push "${RegistryAddress}/${Package}"
}

If (-Not (Test-DockerInSwarm)) {
    Write-Output "Initializing swarm..."
    docker swarm init --advertise-addr "eth0:2377"
}

Write-Output "Deploying `"${Package}`" with `"$ProjectPath\$($ComposeFile.Name)`"..."
Mount-EnvFile -EnvFilePath "$ProjectPath\.env"
docker stack deploy -c "$ProjectPath\$($ComposeFile.Name)" $NameDns
