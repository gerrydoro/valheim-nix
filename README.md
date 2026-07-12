# Valheim Dedicated Server

Nix flake providing a Valheim dedicated game server NixOS module and a package bundling steamcmd + steam-run.

## Features

- **NixOS Module** — Full systemd service with auto-download, user/group management, and firewall configuration
- **Package** — Bundles steamcmd and steam-run for manual server management
- **Runtime download** — SteamCMD automatically fetches server binaries on first start
- **Hardened** — Systemd sandboxing with strict protection, read-only root, and restricted write paths

## Quick Start

### As a NixOS module

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    valheim.url = "github:<user>/valheim";
  };

  services.valheim = {
    enable = true;
    serverName = "My Valheim Server";
    password = "s3cur3P@ssw0rd";  # Change from default!
    # Or use a file-based password for secrets management (recommended):
    # passwordFile = config.sops.secrets.valheim-password.path;
    port = 2456;
    worldName = "MyWorld";
    maxPlayers = 10;
    openFirewall = true;
  };
}
```

### As a package

```bash
nix build github:<user>/valheim
./result/bin/valheim-server
```

## Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable the Valheim server |
| `serverName` | string | `"NixOS Valheim Server"` | Server name displayed in game browser |
| `port` | int | `2456` | Server port |
| `worldName` | string | `"World"` | Default world name |
| `password` | string | `"changeme"` | Server password |
| `passwordFile` | str or null | `null` | Path to file containing the server password (alternative to `password`, recommended for secrets management) |
| `public` | bool | `false` | Whether the server is public |
| `maxPlayers` | int | `10` | Maximum number of players |
| `openFirewall` | bool | `false` | Open firewall ports |
| `enableDebug` | bool | `false` | Enable debug mode |
| `enableSaveDebug` | bool | `false` | Enable save debugging |
| `steamCmdPackage` | package | `pkgs.steamcmd` | Custom SteamCMD package |

## Firewall Ports

When `openFirewall = true`, the following ports are opened:

- TCP: `port`
- UDP: `port`, `port+1`, `port+2`, `port+3`

## How It Works

1. The systemd service starts the `valheim-start` script
2. If the server binaries don't exist, SteamCMD downloads them (app ID 896660)
3. The server runs via `steam-run` with the required library paths
4. World data and server files are stored in `/var/lib/valheim`

## Commands

```bash
nix build .#              # Build default package
nix build .#valheim-server # Build valheim-server package
nix flake show .           # Show flake outputs
nix flake check            # Build verification
```

## Gotchas

- **Unfree software** — `allowUnfree = true` is required in your nixpkgs config
- **Runtime download** — Server binaries are fetched by SteamCMD on first start, not at build time
- **Default password** — Change from `"changeme"` before deploying to production
- **x86_64 only** — Valheim server binaries are x86_64 Linux only
- **Steam account** — Server downloads use anonymous login; no Steam account required
- **Secrets management** — Use `passwordFile` with SOPS instead of hardcoding `password` in your NixOS configuration

## Development

```bash
nix flake check       # Verify flake builds
nix flake show .      # Inspect flake outputs
```

## License

MIT
