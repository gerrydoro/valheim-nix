# Verification surface for this flake's two modules:
#
#   module-interface         evaluates the NixOS module against fixture
#                            configurations and asserts the resulting
#                            systemd/user/firewall wiring (and greps the baked
#                            script the module actually ships).
#   start-script-*           run scripts/valheim-start.sh hermetically with stub
#                            steamcmd/steam-run binaries (injected as
#                            dependencies through the constructor) and assert
#                            the whole start-up sequence.
{ pkgs }:

let
  lib = pkgs.lib;

  mkStartScript = import ../packages/valheim-server/start-script.nix { inherit pkgs; };
  valheimModule = import ../modules;

  # ---------------------------------------------------------------------------
  # Module interface
  # ---------------------------------------------------------------------------

  mkSystem =
    settings:
    pkgs.nixos {
      system.stateVersion = "26.11";
      imports = [ valheimModule ];
      services.valheim = settings // {
        enable = true;
      };
    };

  # Only this module's assertions are reported: a minimal NixOS eval has other
  # assertions that are false (root file system, boot loader, ...).
  valheimAssertionFailures =
    system:
    let
      failed = lib.filter (a: !a.assertion) system.config.assertions;
      messages = map (
        a:
        let
          m = builtins.tryEval a.message;
        in
        if m.success then m.value else "<message unavailable>"
      ) failed;
    in
    lib.filter (m: lib.hasPrefix "services.valheim:" m) messages;

  expect =
    label: actual: expected:
    if actual == expected then
      true
    else
      throw "valheim check '${label}': expected ${builtins.toJSON expected}, got ${builtins.toJSON actual}";

  defaultSystem = mkSystem { };
  secretSystem = mkSystem {
    serverName = "Ashlands";
    port = 3000;
    worldName = "Valhalla";
    maxPlayers = 4;
    public = true;
    openFirewall = true;
    autoUpdate = true;
    enableDebug = true;
    enableSaveDebug = true;
    passwordFile = "/run/secrets/valheim-password";
    # A recognizably different package: proves the option reaches the launcher.
    steamCmdPackage = pkgs.hello;
  };

  defaultSvc = defaultSystem.config.systemd.services.valheim.serviceConfig;
  secretSvc = secretSystem.config.systemd.services.valheim.serviceConfig;

  moduleFindings = {
    "default: assertion failures" =
      expect "default: no valheim assertion failures" (valheimAssertionFailures defaultSystem)
        [ ];
    "default: exec start" =
      expect "default: ExecStart runs the launcher" (lib.hasInfix "valheim-start" defaultSvc.ExecStart)
        true;
    "default: no credential without passwordFile" =
      expect "default: LoadCredential" (defaultSvc.LoadCredential or null)
        null;
    "default: user home" =
      expect "default: users.users.valheim.home" defaultSystem.config.users.users.valheim.home
        "/var/lib/valheim";
    "default: firewall closed" =
      expect "default: allowedTCPPorts" defaultSystem.config.networking.firewall.allowedTCPPorts
        [ ];
    "default: state directory" = expect "default: StateDirectory" defaultSvc.StateDirectory "valheim";
    "default: hardening" = expect "default: ProtectSystem" defaultSvc.ProtectSystem "strict";

    "secret: assertion failures" =
      expect "secret: no valheim assertion failures" (valheimAssertionFailures secretSystem)
        [ ];
    "secret: LoadCredential" =
      expect "secret: LoadCredential"
        # NixOS may hand the value back as a string or a singleton list.
        (
          if lib.isList secretSvc.LoadCredential then
            secretSvc.LoadCredential
          else
            [ secretSvc.LoadCredential ]
        )
        [ "valheim-password:/run/secrets/valheim-password" ];
    "secret: firewall ports" =
      expect "secret: allowedUDPPorts" secretSystem.config.networking.firewall.allowedUDPPorts
        [
          3000
          3001
        ];
    "secret: custom steamcmd package" = expect "secret: custom steamCmdPackage" (lib.any (
      p: p == pkgs.hello
    ) secretSystem.config.environment.systemPackages) true;
  };

  module-interface =
    pkgs.runCommand "valheim-module-interface"
      {
        findings = builtins.toJSON moduleFindings;
        # The exact script file the module installs: building it forces shellcheck
        # and the placeholder baking, and lets us assert on its contents.
        startScript = secretSvc.ExecStart;
      }
      ''
        echo "services.valheim module interface:"
        echo "$findings"

        # Option values must reach the shipped script, not just eval. escapeShellArg
        # only quotes a value when it needs it, so accept either form.
        grep -qE -- "bakedServerName='?Ashlands'?" "$startScript"
        grep -qE -- "bakedPort='?3000'?" "$startScript"
        grep -qE -- "bakedWorldName='?Valhalla'?" "$startScript"
        grep -qE -- "bakedMaxPlayers='?4'?" "$startScript"
        grep -qE -- "bakedPublic='?1'?" "$startScript"
        grep -qE -- "bakedAutoUpdate='?1'?" "$startScript"
        # passwordFile must NOT be baked into the Nix store
        ! grep -qF -- "changeme" "$startScript"

        touch $out
      '';

  # ---------------------------------------------------------------------------
  # Start script behaviour
  # ---------------------------------------------------------------------------

  # Stubs record their invocation and "install" the server tree; the launcher
  # reaches them through its runtimeInputs, no PATH tricks required.
  stubSteamCmd = pkgs.writeShellScriptBin "steamcmd" ''
    echo "steamcmd $*" >> "$VALHEIM_TEST_LOG_DIR/steamcmd.log"
    serverDir="$VALHEIM_STATE_DIR/.local/share/Steam/Steamapps/common/Valheim dedicated server"
    mkdir -p "$serverDir/linux64"
    printf 'binary' > "$serverDir/valheim_server.x86_64"
    printf 'lib' > "$serverDir/linux64/steamclient.so"
  '';

  stubSteamRun = pkgs.writeShellScriptBin "steam-run" ''
    echo "steam-run $*" >> "$VALHEIM_TEST_LOG_DIR/steam-run.log"
  '';

  fixture =
    extraSettings:
    mkStartScript (
      {
        serverName = "Fixture Server";
        port = 6000;
        worldName = "Midgard";
        maxPlayers = 3;
        public = true;
        enableDebug = true;
        enableSaveDebug = false;
        autoUpdate = true;
        password = "fixturePass";
        steamCmdPackage = stubSteamCmd;
        steamRunPackage = stubSteamRun;
      }
      // extraSettings
    );

  freshInstall = pkgs.runCommand "valheim-start-script-fresh-install" { } ''
    export VALHEIM_STATE_DIR="$PWD/state"
    export VALHEIM_TEST_LOG_DIR="$PWD/logs"
    export HOME="$PWD/home"
    mkdir -p "$VALHEIM_TEST_LOG_DIR" "$HOME"

    ${fixture { }}/bin/valheim-start

    # First start downloads the dedicated server app (896660), not the client app
    grep -qF -- "+app_update 896660 validate" "$VALHEIM_TEST_LOG_DIR/steamcmd.log"
    grep -qF -- "+force_install_dir" "$VALHEIM_TEST_LOG_DIR/steamcmd.log"
    grep -qF -- "+login anonymous" "$VALHEIM_TEST_LOG_DIR/steamcmd.log"

    # steamclient.so must be symlinked into $HOME/.steam/sdk64
    target=$(readlink "$HOME/.steam/sdk64/steamclient.so")
    case "$target" in
      */linux64/steamclient.so) ;;
      *) echo "unexpected symlink target: $target" >&2; exit 1 ;;
    esac

    # The exec line must carry every configured setting
    grep -qF -- "-name Fixture Server" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-port 6000" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-world Midgard" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-password fixturePass" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-public 1" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-maxplayers 3" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-nographics" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-batchmode" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-server" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-autostart" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    grep -qF -- "-debug" "$VALHEIM_TEST_LOG_DIR/steam-run.log"
    ! grep -qF -- "-savedebug" "$VALHEIM_TEST_LOG_DIR/steam-run.log"

    touch $out
  '';

  noUpdate = pkgs.runCommand "valheim-start-script-no-update" { } ''
    export VALHEIM_STATE_DIR="$PWD/state"
    export VALHEIM_TEST_LOG_DIR="$PWD/logs"
    export HOME="$PWD/home"
    mkdir -p "$VALHEIM_TEST_LOG_DIR" "$HOME"

    # Pretend the server is already installed, with autoUpdate = false: SteamCMD
    # must not run at all.
    serverDir="$VALHEIM_STATE_DIR/.local/share/Steam/Steamapps/common/Valheim dedicated server"
    mkdir -p "$serverDir/linux64"
    : > "$serverDir/valheim_server.x86_64"
    : > "$serverDir/linux64/steamclient.so"

    ${fixture { autoUpdate = false; }}/bin/valheim-start

    test ! -e "$VALHEIM_TEST_LOG_DIR/steamcmd.log"
    grep -qF -- "-name Fixture Server" "$VALHEIM_TEST_LOG_DIR/steam-run.log"

    touch $out
  '';

  passwordRules = pkgs.runCommand "valheim-start-script-password-rules" { } ''
    export VALHEIM_STATE_DIR="$PWD/state"
    export VALHEIM_TEST_LOG_DIR="$PWD/logs"
    export HOME="$PWD/home"
    mkdir -p "$VALHEIM_TEST_LOG_DIR" "$HOME"

    expectFailure() {
      local script="$1" needle="$2" output
      if ! output=$("$script" 2>&1); then
        echo "$output" | grep -qF -- "$needle" || {
          echo "unexpected error message: $output" >&2
          exit 1
        }
      else
        echo "script exited 0 but should have failed" >&2
        exit 1
      fi
    }

    expectFailure "${fixture { password = "abc"; }}/bin/valheim-start" "at least 5 characters"
    expectFailure "${
      fixture { password = "Midgard"; }
    }/bin/valheim-start" "must not contain the world name"
    expectFailure "${fixture { password = ""; }}/bin/valheim-start" "no server password configured"

    # A password file overrides both the environment and the baked password
    echo "fileSourced" > "$PWD/password-file"
    VALHEIM_PASSWORD="envSourced" VALHEIM_PASSWORD_FILE="$PWD/password-file" \
      ${fixture { }}/bin/valheim-start
    grep -qF -- "-password fileSourced" "$VALHEIM_TEST_LOG_DIR/steam-run.log"

    touch $out
  '';
in
{
  inherit
    module-interface
    freshInstall
    noUpdate
    passwordRules
    ;
}
