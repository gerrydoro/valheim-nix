# AGENTS.md

## Repo structure
- `flake.nix` — single-system (x86_64-linux), sets `allowUnfree = true` for steamcmd
- `modules/default.nix` — NixOS module (`nixosModules.default`)
- `packages/valheim-server/default.nix` — package output (`packages.x86_64-linux.valheim-server`)

## Commands
- `nix build` — build the valheim-server package
- `nix flake show` — list all outputs
- `nix flake show --all-systems` — validate (will fail on non-x86_64 due to platform restrictions)

## Gotchas
- **x86_64-linux only** — `flake.nix` hardcodes `system = "x86_64-linux"` and the package `meta.platforms` restricts to x86_64. Do not add aarch64 without updating both places.
- **allowUnfree is required** — steamcmd is unfreeRedistributable. The flake sets this; do not remove it.
- **File ownership** — the repo was initially owned by root. If git commands fail with permission errors, run `sudo chown -R $USER:$USER /home/gerardo/MyStuff/valheim/`.
- **No test/lint pipeline** — this is a pure Nix flake. Verification is `nix flake show` + `nix build`.

## Adding a new package
Create `packages/<name>/default.nix` returning an attrset of derivations, then wire it into `flake.nix` outputs.

## Adding a new module
Create `modules/<name>.nix` following the pattern in `modules/default.nix`, then add it to `nixosModules` in `flake.nix`.
