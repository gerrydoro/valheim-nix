# Builds the Valheim server launcher (scripts/valheim-start.sh): a small, named
# interface over the whole start-up sequence — download/update via SteamCMD, the
# steamclient.so symlink, password resolution and validation, and the exec line.
#
# Used by both the NixOS module (with the operator's services.valheim values) and
# the standalone package (all defaults). Dependencies are accepted as arguments
# so tests can inject stubs instead of the real steamcmd/steam-run (see checks/).
{ pkgs }:

{
  name ? "valheim-start",
  serverName ? "NixOS Valheim Server",
  port ? 2456,
  worldName ? "World",
  maxPlayers ? 10,
  public ? false,
  enableSaveDebug ? false,
  enableDebug ? false,
  autoUpdate ? false,
  # Empty means "no baked password": the run-time channels in the script
  # (systemd credential, VALHEIM_PASSWORD_FILE, VALHEIM_PASSWORD) apply instead.
  password ? "",
  stateDir ? "/var/lib/valheim",
  steamCmdPackage ? pkgs.steamcmd,
  steamRunPackage ? pkgs.steam-run,
}:

let
  # Settings become build-time defaults, substitutable at run time by the same
  # variable names without the leading VALHEIM_ prefix difference: see the script.
  placeholders = {
    VALHEIM_SERVER_NAME = serverName;
    VALHEIM_PORT = toString port;
    VALHEIM_WORLD = worldName;
    VALHEIM_MAX_PLAYERS = toString maxPlayers;
    VALHEIM_PUBLIC = if public then "1" else "0";
    VALHEIM_SAVE_DEBUG = if enableSaveDebug then "1" else "0";
    VALHEIM_DEBUG = if enableDebug then "1" else "0";
    VALHEIM_AUTO_UPDATE = if autoUpdate then "1" else "0";
    VALHEIM_STATE_DIR = stateDir;
    VALHEIM_PASSWORD = password;
  };

  # Every value is substituted as an escaped shell word, so names, worlds, or
  # passwords containing spaces, quotes, or $ cannot break out of their
  # assignments (a bare interpolation could corrupt or inject into the script).
  bakedScript =
    pkgs.lib.replaceStrings (map (placeholder: "@${placeholder}@") (builtins.attrNames placeholders))
      (map (value: pkgs.lib.escapeShellArg value) (builtins.attrValues placeholders))
      (builtins.readFile ../../scripts/valheim-start.sh);
in
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [
    steamCmdPackage
    steamRunPackage
  ];
  text = bakedScript;
  meta = {
    description = "Valheim dedicated game server launcher (steamcmd + steam-run)";
    license = pkgs.lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
