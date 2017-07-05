Set-StrictMode -Version Latest

Import-Module BitsTransfer

Function Clear-Linebreaks {
    Param (
        [Parameter(Mandatory = $True)] [String] $String
    )

    $String -Replace "`r", "" -Replace "`n", ""
}

Function Install-Docker {
    $Path = "$Env:Temp\InstallDocker.msi"

    If (-Not (Test-Path $Path)) {
        Start-BitsTransfer -Source "https://download.docker.com/win/stable/InstallDocker.msi" -Destination $Path
    }

    Start-Process msiexec.exe -Wait -ArgumentList "/I $Path"
    Remove-Item -Path $Path
}

Function Invoke-ExpressionSave {
    Param (
        [Parameter(Mandatory = $True)] [String] $Command,
        [Parameter(Mandatory = $False)] [Switch] $WithError,
        [Parameter(Mandatory = $False)] [Switch] $Graceful
    )

    $TmpFile = New-TemporaryFile
    $Stdout = ""

    Try {
        Invoke-Expression -Command "$Command 2>$TmpFile" -OutVariable Stdout | Tee-Object -Variable Stdout
    } Catch {
        $PSItem > $TmpFile
    }

    $Stderr = Get-Content $TmpFile

    If ($WithError) {
        $Stdout = "${Stdout}${Stderr}"
    }

    $Stdout
    Remove-Item $TmpFile

    If ($Stderr -And (-Not $Graceful)) {
        Throw $Stderr
    }
}

Function Merge-Objects { 
    Param (
        [Parameter(Mandatory = $True)] $Object1,
        [Parameter(Mandatory = $True)] $Object2
    )
    
    $ReturnObject = [PSCustomObject] @{}

    Foreach ($Property In $Object1.PSObject.Properties) {
        $ReturnObject | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Property.Value -Force
    }

    Foreach ($Property In $Object2.PSObject.Properties) {
        $ReturnObject | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Property.Value -Force
    }
    
    return $ReturnObject
}

Function Read-PromptYesNo {
    Param (
        [Parameter(Mandatory = $True)] [String] $Message,
        [Parameter(Mandatory = $False)] [String] $Question = 'Proceed?',
        [Parameter(Mandatory = $False)] [String] $Default = 1
    )

    $Choices = [System.Management.Automation.Host.ChoiceDescription[]] (
        (New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'),
        (New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No')
    )
    $Decision = $Host.UI.PromptForChoice($Message, $Question, $Choices, $Default)
    
    If ($Decision -Eq 0) {
        Return $True
    } Else {
        Return $False
    }
}

Function Read-Settings {
    Param (
        [Parameter(Mandatory = $True)] [String[]] $SourcesPaths
    )

    $Settings = [PSCustomObject] @{}

    Foreach ($SourcesPath In $SourcesPaths) {
        If (Test-Path $SourcesPath) {
            $Settings = Merge-Objects -Object1 $Settings -Object2 (Get-Content -Path $SourcesPath | ConvertFrom-Json)
        }
    }

    Return $Settings
}

Function Show-Progress {
    Param (
        [Parameter(Mandatory = $True)] [String] $Test,
        [Parameter(Mandatory = $True)] [String] $Activity
    )

    $i = 0

    While (Invoke-Expression -Command $Test) {
        $i++

        If ($i -Eq 100) {
            $i = 0
        }

        Write-Progress -Activity "$Activity ..." -PercentComplete $i
        Start-Sleep -Seconds 1
    }

    Write-Progress -Completed $True
}

Function Start-Docker {
    While (-Not (Test-DockerIsRunning)) {
        While (-Not (Test-DockerIsInstalled)) {
            If (Read-PromptYesNo -Message "Docker is not installed." -Question "Do you want to install it automatically?" -Default 0) {
                Install-Docker
            } Else {
                Read-Host "Please install Docker manually. Press enter to continue ..."
            }
        }

        $DockerPath = (Get-Command docker).Path

        If ($DockerPath -And (Read-PromptYesNo -Message "Docker is not running." -Question "Do you want to start it automatically?" -Default 0)) {
            & "$((Get-Item (Get-Command docker).Path).Directory.Parent.Parent.FullName)\Docker for Windows.exe"

            Show-Progress -Test {-Not (Test-DockerIsRunning)} -Activity "Waiting for Docker to initialize"

            Break
        } Else {
            Read-Host "Please start Docker manually. Press enter to continue ..."
        }
    }
}

Function Start-DockerRegistry {
    Param (
        [Parameter(Mandatory = $True)] [String] $Name,
        [Parameter(Mandatory = $True)] [String] $Hostname,
        [Parameter(Mandatory = $True)] [String] $Port
    )

    While (-Not (Test-DockerRegistryIsRunning -Hostname $Hostname -Port $Port)) {
        $DockerInspectConfigHostname = docker inspect -f "{{.Config.Hostname}}" $Name | Out-String

        If ($DockerInspectConfigHostname -And ($DockerInspectConfigHostname[0] -Match "^[a-z0-9]{12}$")) {
            docker start $DockerInspectConfigHostname
        } Else {
            If (Read-PromptYesNo -Message "Docker registry does not exist." -Question "Do you want to initialize it automatically?" -Default 0) {
                docker run -d -p "${Port}:5000" --name $Name "registry:2"
            } Else {
                Read-Host "Please initialize the Docker registry manually. Press enter to continue ..."
            }
        }
    }
}

Function Stop-DockerStack {
    Param (
        [Parameter(Mandatory = $True)] [String] $StackName
    )

    docker stack rm ${StackName}
    Show-Progress -Test {Test-DockerStackIsRunning -StackNamespace $StackName} -Activity "Waiting for Docker stack to quit"
}

Function Test-DockerInSwarm {
    $DockerSwarmInit = Invoke-ExpressionSave -Command "docker swarm init" -Graceful -WithError

    If ($DockerSwarmInit -Like "Swarm initialized*") {
        docker swarm leave -f > $Null

        Return $False
    } Else {
        Return $True
    }
}

Function Test-DockerIsInstalled {
    If (Get-Command -Name "docker" -ErrorAction SilentlyContinue) {
        Return $True
    } Else {
        Return $False
    }
}

Function Test-DockerIsRunning {
    $DockerActive = Get-Process "Docker for Windows" -ErrorAction SilentlyContinue | Out-String

    If ($DockerActive -Eq $Null) {
        Return $false
    } Else {
        $DockerProcessesAll = Invoke-ExpressionSave "docker ps -a" -Graceful -WithError

        If (($DockerProcessesAll -Like "docker : error*") -Or (-Not $DockerProcessesAll)) {
            Return $False
        } Else {
            Return $True
        }
    }
}

Function Test-DockerRegistryIsRunning {
    Param (
        [Parameter(Mandatory = $True)] [String] $Hostname,
        [Parameter(Mandatory = $True)] [String] $Port
    )

    $WebRequest = Invoke-ExpressionSave -Command "Invoke-WebRequest -Method GET -Uri `"http://${Hostname}:${Port}/v2/_catalog`" -UseBasicParsing" -Graceful

    If ($WebRequest) {
        Return $True
    } Else {
        Return $False
    }
}

Function Test-DockerStackIsRunning {
    Param (
        [Parameter(Mandatory = $True)] [String] $StackNamespace
    )

    $ServiceList = docker ps --filter "label=com.docker.stack.namespace=$StackNamespace" -q | Out-String

    If ($ServiceList) {
        Return $True
    } Else {
        Return $False
    }
}

Function Write-DockerComposeFile {
    Param (
        [Parameter(Mandatory = $True)] [PSCustomObject] $ComposeFile,
        [Parameter(Mandatory = $False)] [String] $Path
    )

    $ComposeFileContent = $Null
    
    ConvertTo-YAML -InputObject $ComposeFile.Content | ForEach-Object {
        $Lines = $PSItem -Split "`r`n"
        $Index = 0

        ForEach ($Line In $Lines) {
            If (-Not ($Index -Eq 0)) {
                $ComposeFileContent += "`r`n"
            }

            $ComposeFileContent += $Line.TrimEnd()

            $Index++
        }
    }

    "$ComposeFileContent`r`n---" > "$Path\$($ComposeFile.Name)"
}
