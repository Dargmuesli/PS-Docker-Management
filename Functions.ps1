Set-StrictMode -Version Latest

<#
    .SYNOPSIS
    Removes newlines from string.

    .DESCRIPTION
    Every line feed and carriage return characters are replaced with nothing.

    .PARAMETER String
    The input string containing the unneeded newlines.

    .EXAMPLE
    $DockerInspectConfigHostname = docker inspect -f "{{.Config.Hostname}}" $Name | Out-String | ForEach-Object {
        If ($PSItem) {
            Clear-Linebreaks -String $PSItem
        }
    }
#>
Function Clear-Linebreaks {
    Param (
        [Parameter(Mandatory = $True)] [String] $String
    )

    $String -Replace "`r", "" -Replace "`n", ""
}

<#
    .SYNOPSIS
    Installs Docker.

    .DESCRIPTION
    Downloads and starts the docker installer.

    .PARAMETER DownloadMethod
    Indicates which type of download function is to be used.

    .EXAMPLE
    Install-Docker

    .NOTES
    Download method "WebRequest" can display its progress, but is very slow.
    Download method "WebClient" cannot display its progress.
    Download method "BITS" can display its progress, but can also be delayed by other downloads.
#>
Function Install-Docker {
    Param (
        [Parameter(Mandatory = $False)] [String] $DownloadMethod = "BITS"
    )

    $Url = "https://download.docker.com/win/stable/InstallDocker.msi"
    $Path = "$Env:Temp\InstallDocker.msi"

    If (-Not (Test-Path $Path)) {
        Switch ($DownloadMethod) {
            "WebRequest" {
                Invoke-WebRequestWithProgress -Uri $Url -OutFile $Path -Overwrite
                break;
            }
            "WebClient" {
                $WebClient = New-Object Net.WebClient
                $WebClient.DownloadFile($Url, $Path)
                break;
            }
            "BITS" {
                Import-Module BitsTransfer
                Start-BitsTransfer -Source $Url -Destination $Path
                break;
            }
        }
    }

    Start-Process msiexec.exe -Wait -ArgumentList "/I $Path"
    Remove-Item -Path $Path
}

<#
    .SYNOPSIS
    Invokes an expression without causing crashes.

    .DESCRIPTION
    Invokes the given command redirecting errors into a temporary file and other output into a variable.
    If the WithError parameter is given, the temporary file's output is appended to stdout.
    If the Graceful parameter is given and an error occurs, no exception is be thrown.

    .PARAMETER Command
    The expression to invoke savely.

    .PARAMETER WithError
    Wether to return the error message in stdout.

    .PARAMETER Graceful
    Prevents that an error is thrown.

    .EXAMPLE
    $DockerSwarmInit = Invoke-ExpressionSave -Command "docker swarm init" -WithError -Graceful
#>
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

<#
    .SYNOPSIS
    Download a file and displays a progressbar.

    .DESCRIPTION
    Verifies that an existing file is managed as requested.
    Then creates a HttpWebRequest whose response stream is directed to a file.
    Every 10KB a progressbar showing the current download progress is displayed/updated.

    .PARAMETER Uri
    The Uri of the file that is to be downloaded

    .PARAMETER Outfile
    The path to where the file is to be saved.

    .EXAMPLE
    Invoke-WebRequestWithProgress -Uri "https://download.docker.com/win/stable/InstallDocker.msi" -OutFile $Path -Overwrite
#>
Function Invoke-WebRequestWithProgress {
    Param (
        [Parameter(Mandatory = $True)] [Uri] $Uri,
        [Parameter(Mandatory = $True)] [String] $OutFile,
        [Parameter(Mandatory = $False)] [Switch] $Overwrite,
        [Parameter(Mandatory = $False)] [Int] $Timeout = 15000
    )

    If (Test-Path $OutFile) {
        If ($Overwrite) {
            Remove-Item -Path $OutFile
        } Else {
            Throw "The file that is to be downloaded already exists at the indicated location and the parameter `"Overwrite`" is not passed."
        }
    }

    $Request = [Net.HttpWebRequest]::Create($Uri)
    $Request.Set_Timeout($Timeout)
    $Response = $Request.GetResponse()
    $TotalLength = [Math]::Floor($Response.Get_ContentLength() / 1024)
    $ResponseStream = $Response.GetResponseStream()
    $TargetStream = New-Object -TypeName IO.FileStream -ArgumentList $OutFile, Create
    $Buffer = New-Object Byte[] 10KB
    $Count = $ResponseStream.Read($Buffer, 0, $Buffer.Length)
    $DownloadedBytes = $Count

    While ($Count -Gt 0) {
        $test = [Convert]::ToInt32([Math]::Floor((($DownloadedBytes / 1024) / $TotalLength) * 100))
        Write-Progressbar -PercentComplete $test `
            -Activity "Downloading $([Math]::Floor($DownloadedBytes / 1024))K of ${TotalLength}K"
        $TargetStream.Write($Buffer, 0, $Count)
        $Count = $ResponseStream.Read($Buffer, 0, $Buffer.Length)
        $DownloadedBytes = $DownloadedBytes + $Count
    }

    Write-Progress -Completed $True

    $TargetStream.Flush()
    $TargetStream.Close()
    $TargetStream.Dispose()
    $ResponseStream.Dispose()
} 

<#
    .SYNOPSIS
    Merges two objects into one.

    .DESCRIPTION
    Adds all properties of the first and then the second object to a third one and returns the latter.

    .PARAMETER Object1
    The first source object.

    .PARAMETER Object2
    The second source object.

    .EXAMPLE
    $Settings = Merge-Objects -Object1 $Settings -Object2 (Get-Content -Path $SourcesPath | ConvertFrom-Json)
#>
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

<#
    .SYNOPSIS
    Sets environment variable from an .env file.

    .DESCRIPTION
    Reads and parses each valid line from an .env file and sets the corresponding Windows environment variable.

    .PARAMETER EnvFilePath
    Path to the .env file that is to be mounted

    .EXAMPLE
    Mount-EnvFile -EnvFilePath "$ProjectPath\.env"
#>
Function Mount-EnvFile {
    Param (
        [Parameter(Mandatory = $True)] [String] $EnvFilePath
    )

    Get-Content $EnvFilePath | Select-String -Pattern "^[A-Z_]+=.+$" | ForEach-Object {
        $PSItem = $PSItem -Split "="
        Set-Item -Force -Path "env:$($PSItem[0])" -Value $PSItem[1]
    }
}

<#
    .SYNOPSIS
    Displays a yes/no prompt.

    .DESCRIPTION
    Displays a yes/no prompt and waits for the user's choice.

    .PARAMETER Message
    A description of the state that requires a user's choice.

    .PARAMETER Question
    A possible solution to the problem.

    .PARAMETER Default
    The preselected answer.

    .EXAMPLE
    If (Read-PromptYesNo -Message "Docker is not installed." -Question "Do you want to install it automatically?" -Default 0) {
        Install-Docker
    } Else {
        Read-Host "Please install Docker manually. Press enter to continue ..."
    }
#>
Function Read-PromptYesNo {
    Param (
        [Parameter(Mandatory = $True)] [String] $Message,
        [Parameter(Mandatory = $False)] [String] $Question = 'Proceed?',
        [Parameter(Mandatory = $False)] [String] $Default = 1
    )

    $Choices = [Management.Automation.Host.ChoiceDescription[]] (
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

<#
    .SYNOPSIS
    Reads settings fields in the JSON format and returns a PSCustomObject.

    .DESCRIPTION
    Merges each source file's settings on top of the others.

    .PARAMETER SourcesPaths
    An array of settings files.

    .EXAMPLE
    $Settings = Read-Settings -SourcesPaths @("${ProjectPath}\package.json", "${ProjectPath}\docker-management.json")
#>
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

<#
    .SYNOPSIS
    Displays an indeterminate progressbar while a test is successful.

    .DESCRIPTION
    Increases the progressbar's value in steps from 0 to 100 infinitly to provide visual feedback about a running task to the user.

    .PARAMETER Test
    The task check which needs to pass.

    .PARAMETER Milliseconds
    The time to wait between test checks.

    .PARAMETER WithProgressbar
    Wether to display a progressbar.

    .PARAMETER Activity
    A description of the running task.

    .EXAMPLE
    Wait-Test -Test {-Not (Test-DockerIsRunning)} -$WithProgressbar -Activity "Waiting for Docker to initialize"
#>
Function Wait-Test {
    Param (
        [Parameter(Mandatory = $True)] [String] $Test,
        [Parameter(Mandatory = $False)] [Int] $Milliseconds = 1000,
        [Parameter(Mandatory = $False)] [Switch] $WithProgressbar,
        [Parameter(Mandatory = $False)] [String] $Activity = "Processing"
    )

    $I = 0

    While (Invoke-Expression -Command $Test) {
        $I++

        If ($I -Eq 100) {
            $I = 0
        }

        If ($WithProgressbar) {
            Write-Progressbar -Activity "$Activity ..." -PercentComplete $I
        }

        Start-Sleep -Milliseconds $Milliseconds
    }

    If ($WithProgressbar) {
        Write-Progress -Completed $True
    }
}

<#
    .SYNOPSIS
    Starts Docker for Windows.

    .DESCRIPTION
    Checks if Docker is installed and running. If not it offers to install and start Docker automatically.

    .EXAMPLE
    Start-Docker
#>
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

            Wait-Test -Test {-Not (Test-DockerIsRunning)} -WithProgressbar -Activity "Waiting for Docker to initialize"

            Break
        } Else {
            Read-Host "Please start Docker manually. Press enter to continue ..."
        }
    }
}

<#
    .SYNOPSIS
    Starts a registry container in Docker.

    .DESCRIPTION
    Tries to start the Docker registry image and offers to install it in case it is not.

    .PARAMETER Name
    The container's name

    .PARAMETER Hostname
    The hostname on which the registry should be available.

    .PARAMETER Port
    The port on which the registry should be available.

    .EXAMPLE
    Start-DockerRegistry -Name $RegistryAddressName -Host $RegistryAddressHostname -Port $RegistryAddressPort
#>
Function Start-DockerRegistry {
    Param (
        [Parameter(Mandatory = $True)] [String] $Name,
        [Parameter(Mandatory = $True)] [String] $Hostname,
        [Parameter(Mandatory = $True)] [String] $Port
    )

    While (-Not (Test-DockerRegistryIsRunning -Hostname $Hostname -Port $Port)) {
        $DockerInspectConfigHostname = docker inspect -f "{{.Config.Hostname}}" $Name | Out-String | ForEach-Object {
            If ($PSItem) {
                Clear-Linebreaks -String $PSItem
            }
        }

        If ($DockerInspectConfigHostname -And ($DockerInspectConfigHostname -Match "^[a-z0-9] {12}$")) {
            docker start $DockerInspectConfigHostname
        } Else {
            If (Read-PromptYesNo -Message "Docker registry does not exist." -Question "Do you want to initialize it automatically?" -Default 0) {
                docker run -d -p "${Port}:5000" --name $Name "registry:2"

                Wait-Test -Test {-Not (Test-DockerRegistryIsRunning  -Hostname $Hostname -Port $Port)} -WithProgressbar -Activity "Waiting for Docker registry to initialize"
            } Else {
                Read-Host "Please initialize the Docker registry manually. Press enter to continue ..."
            }
        }
    }
}

<#
    .SYNOPSIS
    Stops a Docker stack.

    .DESCRIPTION
    Stops a Docker stack, waiting for all included containers to stop.

    .PARAMETER StackName
    The name of the stack to is to be stopped.

    .EXAMPLE
    Stop-DockerStack -StackName $NameDns
#>
Function Stop-DockerStack {
    Param (
        [Parameter(Mandatory = $True)] [String] $StackName
    )

    docker stack rm ${StackName}
    Wait-Test -Test {Test-DockerStackIsRunning -StackNamespace $StackName} -WithProgressbar -Activity "Waiting for Docker stack to quit"
}

<#
    .SYNOPSIS
    Checks if Docker is in swarm-mode.

    .DESCRIPTION
    Tries to create a swarm and returns false if successful, leaving the just created swarm.

    .EXAMPLE
    If (-Not (Test-DockerInSwarm)) {
        Write-Output "Initializing swarm ..."
        docker swarm init
    }
#>
Function Test-DockerInSwarm {
    $DockerSwarmInit = Invoke-ExpressionSave -Command "docker swarm init" -Graceful -WithError

    If ($DockerSwarmInit -Like "Swarm initialized*") {
        docker swarm leave -f > $Null

        Return $False
    } Else {
        Return $True
    }
}

<#
    .SYNOPSIS
    Checks if Docker is installed.

    .DESCRIPTION
    Tries to access the command "docker" and returns true on success.

    .EXAMPLE
    While (-Not (Test-DockerIsInstalled)) {
        If (Read-PromptYesNo -Message "Docker is not installed." -Question "Do you want to install it automatically?" -Default 0) {
            Install-Docker
        } Else {
            Read-Host "Please install Docker manually. Press enter to continue ..."
        }
    }
#>
Function Test-DockerIsInstalled {
    If (Get-Command -Name "docker" -ErrorAction SilentlyContinue) {
        Return $True
    } Else {
        Return $False
    }
}

<#
    .SYNOPSIS
    Checks if Docker is running.

    .DESCRIPTION
    Tries to find the Docker process and verifies the availability of the "docker ps" command.

    .EXAMPLE
    Wait-Test -Test {-Not (Test-DockerIsRunning)} -$WithProgressbar -Activity "Waiting for Docker to initialize"
#>
Function Test-DockerIsRunning {
    $DockerActive = Get-Process "Docker for Windows" -ErrorAction SilentlyContinue | Out-String

    If (-Not $DockerActive) {
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

<#
    .SYNOPSIS
    Checks if Docker runs a registry container.

    .DESCRIPTION
    Tries to invoke a web request to the registry's catalog and returns true on success.

    .PARAMETER Hostname
    The hostname the registry is supposed to run on.

    .PARAMETER Port
    The port the registry is supposed to run on.

    .EXAMPLE
    While (-Not (Test-DockerRegistryIsRunning -Hostname $Hostname -Port $Port)) {
        # Start/Install registry
    }
#>
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

<#
    .SYNOPSIS
    Checks if a Docker stack runs.

    .DESCRIPTION
    Looks for running container with a matching "stack.namespace".

    .PARAMETER StackNamespace
    The stack's name that is checked.

    .EXAMPLE
    Wait-Test -Test {Test-DockerStackIsRunning -StackNamespace $StackName} -WithProgressbar -Activity "Waiting for Docker stack to quit"
#>
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

<#
    .SYNOPSIS
    Create a Docker compose file.

    .DESCRIPTION
    Converts the data in a PSCustomObject to the YAML format and writes to file, removing unneccessary linebreaks.

    .PARAMETER ComposeFile
    An object containing the compose file's properties.

    .PARAMETER Path
    Path of the output file.

    .EXAMPLE
    Write-DockerComposeFile -ComposeFile $ComposeFile -Path $ProjectPath
#>
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

Function Write-Progressbar {
    Param (
        [Parameter(Mandatory = $True)] [Int] $PercentComplete,
        [Parameter(Mandatory = $False)] [String] $Activity = "Processing"
    )

    Write-Progress -Activity "$Activity" -PercentComplete $PercentComplete
}
