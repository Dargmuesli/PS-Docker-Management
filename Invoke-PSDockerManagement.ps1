#Requires -Version 5

<#
    .SYNOPSIS
    A PowerShell script for Docker project management.

    .DESCRIPTION
    It writes a Docker compose file, stops a running stack, removes images of the Docker project, rebuilds them, publishes them to a registry and initializes a Docker swarm on which it deploys the new stack.

    .PARAMETER ProjectPath
    The path to the Docker project.

    .PARAMETER KeepYAML
    Whether to regenerate the docker "docker-compose.yml".

    .PARAMETER KeepImages
    Whether to rebuild the Docker image.

    .PARAMETER Offline
    Whether to install dependencies.

    .EXAMPLE
    .\Invoke-PSDockerManagement.ps1 -ProjectPath "..\docker-project-root\"
#>

Param (
    [Parameter(Mandatory = $True, Position = 0)]
    [ValidateScript({Test-Path -Path $PSItem})]
    [String] $ProjectPath,

    [Switch] $KeepYAML,

    [Switch] $KeepImages,

    [Switch] $Offline
)

# Enforce strict coding rules
Set-StrictMode -Version Latest

# Stop on errors
$ErrorActionPreference = "Stop"

# Unify path parameter
$ProjectPath = (Convert-Path -Path $ProjectPath).TrimEnd("/\")

# Check online status
If (-Not (Test-Connection -ComputerName "google.com" -Count 1 -Quiet)) {
    $Offline = $True
    Write-Host "Internet connection test failed. Operating in offline mode..." -ForegroundColor "Cyan"
}

# Install dependencies if connected to the internet
If (-Not $Offline) {
    Write-Host "Installing dependencies..." -ForegroundColor "Cyan"

    If (-Not (Get-Module -Name "PSDepend" -ListAvailable)) {
        Install-Module -Name "PSDepend" -Scope CurrentUser -Force
    }

    Invoke-PSDepend -Install -Force

    Install-PackageOnce -Name @("YamlDotNet") -Scope "CurrentUser" -Add
}

# Load project settings
$PackageJson = Join-Path -Path $ProjectPath -ChildPath "package.json"
$DockerManagementJson = Join-Path -Path $ProjectPath "docker-management.json"
$Settings = Read-Settings -SourcePath @($PackageJson, $DockerManagementJson)

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
    Write-Host "Writing compose file..." -ForegroundColor "Cyan"

    $ComposeFileHashtable = Convert-PSCustomObjectToHashtable -InputObject $ComposeFile.Content -YamlDotNet_DoubleQuoted
    [System.IO.File]::WriteAllLines((Join-Path -Path $ProjectPath -ChildPath $($ComposeFile.Name)), (New-Yaml -Value $ComposeFileHashtable))
}

# Assemble script variables
$Package = $Null

If ($Owner -And $Name) {
    $Package = "${Owner}/${Name}"
} ElseIf ($Name) {
    $Package = $Name
}

$StackGrep = $Null
$NameDns = $Name.replace(".", "-")

# Ensure Docker is installed
If (-Not (Test-DockerInstalled)) {
    Install-Docker -DownloadMethod $DownloadMethod -Ask
}

# Ensure Docker is started
If (-Not (Test-DockerRunning)) {
    If (Read-PromptYesNo -Caption "Docker is not running." -Message "Do you want to start it automatically?" -DefaultChoice 0) {
        Start-Docker
    } Else {
        While (-Not (Test-DockerRunning)) {
            Read-Host "Please start Docker manually. Press enter to continue..."
        }
    }
}

# Examine Docker's context
If (Test-DockerInSwarm) {
    $StackGrep = Invoke-Docker stack ls |
        Select-String $NameDns

    If (-Not $StackGrep) {
        Write-Host "Stack not found." -ForegroundColor "Cyan"
    }
} Else {
    Write-Host "Docker not in swarm." -ForegroundColor "Cyan"
}

$IdImgLocal = Invoke-Docker images -q $Package |
    Out-String |
    ForEach-Object {
    If ($PSItem) {
        Clear-Linebreaks -String $PSItem
    }
}

If (-Not $IdImgLocal) {
    Write-Host "Image not found as local image in image list." -ForegroundColor "Cyan"
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
        Write-Host "Image not found as registry image in image list." -ForegroundColor "Cyan"
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
        Write-Host "Initializing swarm..." -ForegroundColor "Cyan"
        Invoke-Docker swarm init --advertise-addr "eth0:2377"
    }
}

$EnvPath = Join-Path -Path $ProjectPath -ChildPath ".env"
$ComposeFilePath = Join-Path -Path $ProjectPath -ChildPath $ComposeFile.Name

Write-Host "Deploying `"$Package`" with `"$ComposeFilePath`"..."

If (Test-Path -Path $EnvPath) {
    Mount-EnvFile -EnvFilePath $EnvPath
}

Invoke-Docker stack deploy -c $ComposeFilePath $NameDns
