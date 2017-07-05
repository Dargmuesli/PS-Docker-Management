Set-StrictMode -Version Latest

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
