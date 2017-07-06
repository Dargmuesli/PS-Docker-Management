# PS-Docker-Management
A PowerShell script for Docker project management.
It writes a Docker compose file, stops a running stack, removes images of the Docker project, rebuilds them, publishes them to a registry and initializes a Docker swarm on which it deploys the new stack.

## Requirements
This PowerShell script installs the "PSYaml" PS module automatically.

Settings are read from `package.json` and `docker-management.json` files in the Docker project's directory.


## Usage
Just execute the PowerShell script using the path to your Docker project as first parameter.

``` PowerShell
.\Docker-Management.ps1 -ProjectPath "..\project-root\"
```

### Configuration
The script needs to be able to read certain values from configuration files.
If they are not present in a `package.json` file they must be contained within the `docker-management.json` file.
This includes:

- **Name**

    Required.

    The project's name.

    Most probably included the `package.json`.
    Used for the generated image's and stack's name.

    Example:

    ``` JSON
    "Name": "project"
    ```

- **Owner**

    Optional.

    The project's owner.

    Used for the generated image's name and storage in a registry.

    Example:

    ``` JSON
    "Owner": "dargmuesli"
    ```

- **RegistryAddress**

    Optional.

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

- **ComposeFile**

    Required.

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

