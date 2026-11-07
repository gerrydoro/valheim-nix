# AGENTS.md

## Project

Nix flake providing a Valheim dedicated game server NixOS module and a package bundling steamcmd + steam-run.

## Structure

- `flake.nix` — single flake input (`nixpkgs/nixos-unstable`), x86_64-linux only, `allowUnfree = true`
- `scripts/valheim-start.sh` — the launcher: the entire start-up sequence (SteamCMD download/update, `linux64/steamclient.so` symlink, password resolution + validation, exec line) as plain bash. Its interface is a documented env-var contract; build-time settings arrive as `@VALHEIM_*@` placeholders
- `packages/valheim-server/start-script.nix` — constructor for the launcher: named settings + `steamCmdPackage`/`steamRunPackage` in, `writeShellApplication` out. Substitutes the placeholders with `escapeShellArg` values, so `nix build` runs shellcheck on the result
- `packages/valheim-server/default.nix` — returns `{ valheim-server = ... }` (the launcher built with defaults, runnable standalone via `VALHEIM_*` env vars); the flake aliases it as `default`
- `modules/default.nix` — NixOS module: `services.valheim` options, assertions, user/group, firewall, systemd service. It is a thin adapter: it calls `start-script.nix` with its option values and wires the result into systemd (no shell generation lives here)
- `checks/` — flake checks: `module-interface` evals the NixOS module against fixture configs and asserts the resulting systemd/user/firewall wiring; `start-script-*` run the launcher hermetically with stub `steamcmd`/`steam-run` (injected via the constructor) and assert download, symlink, password-rule and exec behavior

## Commands

```
nix build .#               # builds default package (valheim-server)
nix build .#valheim-server # short attr alias, same derivation
nix flake show .
nix flake check            # builds packages AND module-interface / start-script checks
nix fmt                    # format .nix files (formatter.x86_64-linux = nixfmt-tree)
nix develop                # dev shell with nixfmt, steamcmd, steam-run
```

`nix flake check` now evaluates the NixOS module: `checks/default.nix` builds two fixture systems (default and `passwordFile`) with `pkgs.nixos`, so option regressions fail the check. To inspect a specific config by hand:

```
nix eval --impure --json --expr 'let
  flake = builtins.getFlake (toString ./.);
  pkgs = import flake.inputs.nixpkgs.outPath { system = "x86_64-linux"; config.allowUnfree = true; };
  n = pkgs.nixos { imports = [ flake.nixosModules.default ]; services.valheim.enable = true; };
in n.config.systemd.services.valheim.serviceConfig'
```

## Module usage

```nix
imports = [ (import /path/to/valheim { }).nixosModules.default ];
# or via flake input
imports = [ valheim.nixosModules.default ];
```

## Gotchas

- `allowUnfree = true` is required — Valheim is unfree software
- Server binaries are downloaded at runtime by SteamCMD (`app_update 896660`) into `/var/lib/valheim/.local/share/Steam/Steamapps/common/Valheim dedicated server`. The running server also sets `SteamAppId=892970` (the *client* app id) — the two IDs intentionally differ, don't "fix" them to match
- The start script symlinks `linux64/steamclient.so` into `$HOME/.steam/sdk64/` (SteamGameServer requires it) and needs the 64-bit lib path, which contains a space ("Valheim dedicated server"). Don't "simplify" these away — the server silently fails to start without them
- `passwordFile` is optional. When set, it's loaded as a systemd `LoadCredential`, so root-only secret files (e.g. sops `0400`) work without loosening permissions; the launcher resolves the password in this order: `$CREDENTIALS_DIRECTORY/valheim-password` → `$VALHEIM_PASSWORD_FILE` → `$VALHEIM_PASSWORD` → the baked (config) value
- `passwordFile` type is `types.str` — never `types.path`. A Nix `path` literal gets copied into the world-readable Nix store. sops produces a string path, which is safe
- The server refuses to boot with a password shorter than 5 characters or one that appears in the world name. The module asserts this at eval time for `password` and `scripts/valheim-start.sh` re-checks at runtime; both paths are covered by `nix flake check`
- The password is passed via `-password`, so it's visible in the process cmdline (`ps`, `systemctl status`) regardless of `passwordFile` — residual, unavoidable exposure on the host. A config `password` is additionally baked into the store script (that exposure predates this layout); `passwordFile` is the only channel that keeps the secret out of the Nix store
- The launcher's defaults mirror the `services.valheim` option defaults, and every setting can be overridden at runtime with the matching `VALHEIM_*` env var — that is what makes the standalone `valheim-server` package usable without a rebuild
- In `scripts/valheim-start.sh`, the `@VALHEIM_*@` tokens are substituted wherever they appear, including inside comments — never mention a token in a comment, and don't add a placeholder without extending the constructor's substitution list in `start-script.nix`
- `start-script.nix` substitutes each value via `escapeShellArg`, which only adds quotes when the value needs them (e.g. spaces) — grep patterns in checks must tolerate both forms
- Tests inject stub `steamcmd`/`steam-run` through the constructor's `steamCmdPackage`/`steamRunPackage` arguments. Don't try to shadow them with PATH tricks: `writeShellApplication` prepends `runtimeInputs` to `PATH` inside the script
- `autoUpdate = true` runs `+app_update 896660 validate` on every start instead of only when the binary is missing
- Default password is `"changeme"` — must be changed for production
- Firewall ports (only opened when `openFirewall = true`): TCP `port`; UDP `port`, `port+1` (Valheim doesn't use `port+2`/`port+3`)
- Systemd service uses `StateDirectory = "valheim"` for persistence, with strict sandboxing (`ProtectSystem = "strict"`, `Type = "exec"`, `ReadWritePaths = [ "/var/lib/valheim" ]`). There is deliberately no `WorkingDirectory` — it may not exist yet on a fresh install, and the start script `cd`'s into it itself
- Only x86_64-linux is supported (Valheim server is x86_64 only)
