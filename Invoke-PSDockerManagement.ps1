#Requires -Version 5

<#
    .SYNOPSIS
    A PowerShell script for Docker project management.

    .DESCRIPTION
    It writes a Docker compose file, stops a running stack, removes images of the Docker project, rebuilds them, publishes them to a registry and initializes a Docker swarm on which it deploys the new stack.

    .PARAMETER ProjectPath
    The path to the Docker project.

    .PARAMETER EnvPath
    The path to the environment variable file.

    .PARAMETER SecretPath
    The path to Docker secret files.

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

    [Parameter(Mandatory = $False)]
    [ValidateScript(
        {
            If (-Not [System.IO.Path]::IsPathRooted($PSItem)) {
                Test-Path -Path (Join-Path -Path $ProjectPath -ChildPath $PSItem)
            } Else {
                Test-Path -Path $PSItem
            }
        }
    )]
    [String] $EnvPath,

    [Parameter(Mandatory = $False)]
    [ValidateScript(
        {
            If (-Not [System.IO.Path]::IsPathRooted($PSItem)) {
                Test-Path -Path (Join-Path -Path $ProjectPath -ChildPath $PSItem)
            } Else {
                Test-Path -Path $PSItem
            }
        }
    )]
    [String] $SecretPath,

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
    Write-Warning -Message "Internet connection test failed. Operating in offline mode..."
}

# Install dependencies if connected to the internet
If (-Not $Offline) {
    Write-Host "Setting up dependencies..." -ForegroundColor "Cyan"

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
$ComposeFilePath = (Join-Path -Path $ProjectPath -ChildPath $ComposeFile.Name)

If (-Not (Test-PropertyExists -Object $ComposeFile -PropertyName "Name")) {
    Throw "Compose file name not specified."
}

If ((-Not (Test-Path $ComposeFilePath)) -Or (-Not $KeepYAML)) {
    Write-Host "Writing YAML compose file..." -ForegroundColor "Cyan"

    $ComposeFileHashtable = Convert-PSCustomObjectToHashtable -InputObject $ComposeFile.Content -YamlDotNet_DoubleQuoted
    [System.IO.File]::WriteAllLines($ComposeFilePath, (New-Yaml -Value $ComposeFileHashtable))
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

# Search image as local image
$IdImgLocal = Invoke-Docker images -q $Package |
    Out-String |
    ForEach-Object {
    If ($PSItem) {
        Clear-Linebreaks -String $PSItem
    }
}

If (-Not $IdImgLocal) {
    Write-Host "Image not found as local image." -ForegroundColor "Cyan"
}

# Start or use the local registry
$RegistryAddress = "${RegistryAddressHostname}:${RegistryAddressPort}"
$IdImgRegistry = $Null

If ($RegistryAddress) {
    Start-DockerRegistry -RegistryName $RegistryAddressName -Hostname $RegistryAddressHostname -Port $RegistryAddressPort

    # Search image as registry image
    $IdImgRegistry = Invoke-Docker images -q "${RegistryAddress}/${Package}" |
        Out-String |
        ForEach-Object {
        If ($PSItem) {
            Clear-Linebreaks -String $PSItem
        }
    }

    If (-Not $IdImgRegistry) {
        Write-Host "Image not found as registry image." -ForegroundColor "Cyan"
    }
}

# Stop stack
If ($StackGrep) {
    Write-MultiColor -Text @("Stopping stack ", $NameDns, "...") -Color Cyan, Yellow, Cyan
    Stop-DockerStack -StackName $NameDns
}

### Main tasks
If (((-Not $IdImgLocal) -And (-Not $IdImgRegistry)) -Or (-Not $KeepImages)) {

    # Delete local image
    If ($IdImgLocal) {
        Write-MultiColor -Text @("Removing image ", $IdImgLocal, " as local image...") -Color Cyan, Yellow, Cyan
        Invoke-Docker rmi ${IdImgLocal} -f
    }

    # Delete registry image
    If ($IdImgRegistry -And ($IdImgRegistry -Ne $IdImgLocal)) {
        Write-MultiColor -Text @("Removing image ", $IdImgRegistry, " as registry image...") -Color Cyan, Yellow, Cyan
        Invoke-Docker rmi ${IdImgRegistry} -f
    }

    # Build image
    Write-MultiColor -Text @("Building ", $Package, "...") -Color Cyan, Yellow, Cyan
    Invoke-Docker build -t ${Package} $ProjectPath

    # Publish local image on local registry
    If ($RegistryAddress) {
        Write-MultiColor -Text @("Publishing ", $Package, " on ", $RegistryAddress, "...") -Color Cyan, Yellow, Cyan, Yellow, Cyan
        Invoke-Docker tag ${Package} "${RegistryAddress}/${Package}"
        Invoke-Docker push "${RegistryAddress}/${Package}"
    }

    # Initialize the swarm
    If (-Not (Test-DockerInSwarm)) {
        Write-Host "Initializing swarm..." -ForegroundColor "Cyan"
        Invoke-Docker swarm init --advertise-addr "eth0:2377"
    }
}

# Mount .env file
If ($EnvPath) {
    If (-Not [System.IO.Path]::IsPathRooted($EnvPath)) {
        $EnvPath = Join-Path -Path $ProjectPath -ChildPath $EnvPath
    }

    If (Test-Path -Path $EnvPath) {
        Mount-EnvFile -EnvFilePath $EnvPath
    }
}

# Reload docker secrets
If ($SecretPath) {
    If (-Not [System.IO.Path]::IsPathRooted($SecretPath)) {
        $SecretPath = Join-Path -Path $ProjectPath -ChildPath $SecretPath
    }
} Else {
    $SecretPath = "$ProjectPath\docker\secrets"
}

If (Test-Path -Path $SecretPath) {
    Get-ChildItem -Path $SecretPath -File | ForEach-Object {
        Invoke-Docker secret rm $_.Name
        Invoke-Docker secret create $_.Name $_.FullName
    }
}

# Deploy the stack
Write-MultiColor -Text @("Deploying ", $Package, " with ", $ComposeFilePath, "...") -Color Cyan, Yellow, Cyan, Yellow, Cyan
Invoke-Docker stack deploy -c $ComposeFilePath $NameDns
