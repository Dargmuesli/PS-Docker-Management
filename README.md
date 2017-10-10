# PS-Docker-Management
A PowerShell script for Docker project management.
It writes a Docker compose file, stops a running stack, removes images of the Docker project, rebuilds them, publishes them to a registry and initializes a Docker swarm on which it deploys the new stack.

## Requirements
This PowerShell script installs its requirements automatically. See `Requirements.psd1`.

There seems to be a bug with the nuget.org v3-API where the `Install-Package` command does not find matching packages to install automatically. One needs to unregister the v3-API and register the v2-API to solve this error.

``` PowerShell
> Get-PackageSource

Name       ProviderName   IsTrusted   Location
----       ------------   ---------   --------
nuget.org  NuGet          False       https://api.nuget.org/v3/index.json

> Unregister-PackageSource nuget.org
> Register-PackageSource nuget.org https://www.nuget.org/api/v2/ -ProviderName NuGet

Name        ProviderName   IsTrusted   Location
----        ------------   ---------   --------
nuget.org   NuGet          False       https://www.nuget.org/api/v2/
```

Settings are read from `package.json` and `docker-management.json` files in the Docker project's directory.

## Docker-Management

### Syntax
``` PowerShell
Docker-Management.ps1 [-ProjectPath] <string> [-MachineName <string>] [-DownloadMethod <string>] [-KeepYAML] [-KeepImages] [-Offline] [<CommonParameters>]
```

### Parameters

#### -ProjectPath
The path to the Docker project.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

#### -KeepYAML
Whether to regenerate the docker "docker-compose.yml".

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

#### -KeepImages
Whether to rebuild the Docker image.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

#### -Offline
Whether to install dependencies.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### EXAMPLES

#### -------------------------- EXAMPLE 1 --------------------------
``` PowerShell
.\Docker-Management.ps1 -ProjectPath "..\docker-project-root\"
```

## Configuration
The script needs to be able to read certain values from configuration files.
If they are not present in a `package.json` file they must be contained within the `docker-management.json` file.
This includes:

- **Name** [required]

    The project's name.

    Most probably included the `package.json`.
    Used for the generated image's and stack's name.

    Example:

    ``` JSON
    "Name": "project"
    ```

- **Owner** [optional]

    The project's owner.

    Used for the generated image's name and storage in a registry.

    Example:

    ``` JSON
    "Owner": "dargmuesli"
    ```

- **RegistryAddress** [optional]

    Information about the registry to be used.
    Contains:
    - Name
    - Hostname
    - Port

    Example:

    ``` JSON
    "RegistryAddress": {
        "Name": "registry",
        "Hostname": "localhost",
        "Port": "5000"
    }
    ```

- **ComposeFile** [required]

    Information about the Docker compose file that is created on execution.
    Contains:
    - Name
    - Content

    Where Content is the JSON representation of the compose file's YAML.

    Example:

    ``` JSON
    "ComposeFile": {
        "Name": "docker-compose.yml",
        "Content": {
            "version": "3",
            "services":
            ...
        }
    }
    ```

