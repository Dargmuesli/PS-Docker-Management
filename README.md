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
