# AGENTS.md

## Project

Nix flake providing a Valheim dedicated game server NixOS module and a package bundling steamcmd + steam-run.

## Structure

- `flake.nix` — single flake input (`nixpkgs/nixos-unstable`), x86_64-linux only, `allowUnfree = true`
- `packages/valheim-server/default.nix` — package output: symlinkJoin of valheim-tools (steamcmd + steam-run)
- `modules/default.nix` — NixOS module: `services.valheim` option, systemd service, user/group, firewall rules, SteamCMD auto-download

## Commands

```
nix build .#          # builds default package (valheim-server)
nix build .#packages.x86_64-linux.valheim-server
nix flake show .
nix flake check       # build verification (checks = packages)
```

## Module usage

```nix
imports = [ (import /path/to/valheim { }).nixosModules.default ];
# or via flake input
imports = [ valheim.nixosModules.default ];
```

## Gotchas

- `allowUnfree = true` is required — Valheim is unfree software
- Server binaries are downloaded at runtime by SteamCMD (app ID 892660) into `/var/lib/valheim/.local/share/Steam/...`
- Default password is `"changeme"` — must be changed for production
- Firewall ports: UDP/TCP `port`, `port+1`, `port+2`, `port+3` (controlled by `openFirewall` option)
- Systemd service uses `StateDirectory = "valheim"` for persistence, with strict sandboxing (`ProtectSystem = "strict"`, `ReadOnlyPaths = [ "/" ]`, `ReadWritePaths = [ "/var/lib/valheim" "/tmp" "/var/tmp" ]`)
- Only x86_64-linux is supported (Valheim server is x86_64 only)
