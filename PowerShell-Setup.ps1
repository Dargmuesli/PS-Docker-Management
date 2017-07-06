Set-StrictMode -Version Latest

<#
    .SYNOPSIS
    Installs PS modules.

    .DESCRIPTION
    Checks if a module is installed and installs it if not.

    .PARAMETER DependencyNames
    A list of module names to install.

    .EXAMPLE
    Install-Dependencies -DependencyNames @("PSYaml")
#>
Function Install-Dependencies {
    Param (
        [Parameter(Mandatory = $True)] [String[]] $DependencyNames
    )
    
    Foreach ($DependencyName In $DependencyNames) {
        If (-Not (Test-ModuleInstalled -ModuleName $DependencyName)) {
            Invoke-Expression "Install-$DependencyName"
        }
    }
}

<#
    .SYNOPSIS
    Install the Docker module "PSYaml".

    .DESCRIPTION
    Downloads PSYaml-master from GitHub, extracts and removes the zip file.

    .EXAMPLE
    Invoke-Expression "Install-$DependencyName"
#>
Function Install-PSYaml {
    Add-Type -Assembly "System.IO.Compression.FileSystem"

    $YAMLDotNetLocation = "$Env:UserProfile\Documents\WindowsPowerShell\Modules\PSYaml"

    If (-Not (Test-Path "$YAMLDotNetLocation\YAMLdotNet")) {
        New-Item -ItemType "Directory" -Force -Path "$YAMLDotNetLocation\YAMLdotNet" | Out-Null
    }

    $Client = New-Object Net.WebClient
    $Client.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    $Client.DownloadFile("https://github.com/Dargmuesli/PSYaml/archive/master.zip", "$YAMLDotNetLocation\PSYaml.zip")

    If (Test-Path "$YAMLDotNetLocation\PSYaml-master") {
        Remove-Item "$YAMLDotNetLocation\PSYaml-master" -Recurse -Force
    }
    
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$YAMLDotNetLocation\PSYaml.zip", $YAMLDotNetLocation)

    Copy-Item "$YAMLDotNetLocation\PSYaml-master\*.*" $YAMLDotNetLocation
    Remove-Item @("$YAMLDotNetLocation\PSYaml-master", "$YAMLDotNetLocation\PSYaml.zip") -Recurse -Force
}

<#
    .SYNOPSIS
    Check if a PS module is installed.

    .DESCRIPTION
    Tries to get the module and returns true on success.

    .PARAMETER ModuleName
    The name of the module to check.

    .EXAMPLE
    If (-Not (Test-ModuleInstalled -ModuleName $DependencyName)) {
        Invoke-Expression "Install-$DependencyName"
    }
#>
Function Test-ModuleInstalled {
    Param (
        [Parameter(Mandatory = $True)] [String] $ModuleName
    )

    If (Get-Module -ListAvailable -Name $ModuleName) {
        Return $True
    } Else {
        Return $False
    }
}
