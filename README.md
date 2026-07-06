# Valheim Game Server Module

A Nix flake providing a Valheim dedicated game server NixOS module.

## Flake Outputs

- `packages.x86_64-linux.valheim-server` - Server tools package
- `nixosModules.default` - NixOS module for deploying the server

## Usage

Add the flake as an input to your NixOS configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    valheim.url = "github:yourusername/valheim";
  };

  outputs = { self, nixpkgs, valheim, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        valheim.nixosModules.default
        {
          services.valheim = {
            enable = true;
            serverName = "My Valheim Server";
            worldName = "MyWorld";
            password = "your_secure_password";
            port = 2456;
            public = false;
            openFirewall = true;
            maxPlayers = 10;
          };
        }
      ];
    };
  };
}
```

## Configuration Options

- `services.valheim.enable` - Enable the Valheim server (default: false)
- `services.valheim.serverName` - Name of the Valheim server (default: "NixOS Valheim Server")
- `services.valheim.port` - Port for the Valheim server (default: 2456)
- `services.valheim.worldName` - Name of the world (default: "World")
- `services.valheim.password` - Password for the server (default: "changeme")
- `services.valheim.public` - Whether the server is public (default: false)
- `services.valheim.enableSaveDebug` - Enable save debugging (default: false)
- `services.valheim.enableDebug` - Enable debug mode (default: false)
- `services.valheim.maxPlayers` - Maximum number of players (default: 10)
- `services.valheim.openFirewall` - Open ports in the firewall (default: false)
- `services.valheim.steamCmdPackage` - SteamCMD package to use (default: pkgs.steamcmd)

## Ports

The Valheim server uses the following ports:
- Main game port (configurable, default 2456)
- Additional UDP ports (port+1, port+2, port+3)

Make sure these ports are open in your firewall and router if hosting publicly.

## Data Storage

Server data is stored in `/var/lib/valheim/` with proper ownership for the `valheim` user.
