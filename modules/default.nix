{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.valheim;
  valheimUser = "valheim";
  valheimGroup = "valheim";
  stateDir = "/var/lib/${valheimUser}";

  # The launcher is built by packages/valheim-server/start-script.nix; this module
  # is the adapter that feeds the services.valheim option values into it and
  # wires the result into systemd/users/firewall.
  startScript = import ../packages/valheim-server/start-script.nix { inherit pkgs; } {
    inherit (cfg)
      serverName
      port
      worldName
      maxPlayers
      public
      enableSaveDebug
      enableDebug
      autoUpdate
      steamCmdPackage
      ;
    # Bake the password only when it comes from config; with passwordFile the
    # secret stays out of the Nix store and is passed as a systemd credential.
    password = if cfg.passwordFile == null then cfg.password else "";
    inherit stateDir;
  };
in
{
  options.services.valheim = {
    enable = mkEnableOption "Valheim game server";

    serverName = mkOption {
      type = types.str;
      default = "NixOS Valheim Server";
      description = "Name of the Valheim server";
    };

    port = mkOption {
      type = types.int;
      default = 2456;
      description = "Port for the Valheim server";
    };

    worldName = mkOption {
      type = types.str;
      default = "World";
      description = "Name of the world";
    };

    password = mkOption {
      type = types.str;
      default = "changeme";
      description = "Password for the server";
    };

    passwordFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to a file containing the server password. Mutually exclusive with password. Use a string path (as produced by sops) so the secret is not copied into the Nix store.";
    };

    public = mkOption {
      type = types.bool;
      default = false;
      description = "Whether the server is public (1) or private (0)";
    };

    enableSaveDebug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable save debugging";
    };

    enableDebug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug mode";
    };

    maxPlayers = mkOption {
      type = types.int;
      default = 10;
      description = "Maximum number of players";
    };

    autoUpdate = mkOption {
      type = types.bool;
      default = false;
      description = "Run a SteamCMD update check (app_update 896660 validate) on every server start instead of only downloading when missing.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open ports in the firewall for the Valheim server";
    };

    steamCmdPackage = mkOption {
      type = types.package;
      default = pkgs.steamcmd;
      description = "SteamCMD package to use for downloading the server";
    };
  };

  config = mkIf cfg.enable {
    # Input validation: the server silently refuses to boot on bad passwords
    assertions = [
      {
        assertion = cfg.passwordFile == null || cfg.password == "changeme";
        message = "services.valheim: `password` and `passwordFile` are mutually exclusive; leave `password` at its default when using `passwordFile`.";
      }
      {
        assertion = cfg.passwordFile != null || lib.stringLength cfg.password >= 5;
        message = "services.valheim: the server password must be at least 5 characters long.";
      }
      {
        assertion = cfg.passwordFile != null || !lib.hasInfix cfg.password cfg.worldName;
        message = "services.valheim: the server password must not appear inside the world name.";
      }
    ];

    # Create valheim user and group
    users.users.${valheimUser} = {
      isNormalUser = true;
      group = valheimGroup;
      home = stateDir;
      createHome = true;
      description = "Valheim Server User";
      uid = config.ids.uids.${valheimUser} or null;
    };

    users.groups.${valheimGroup} = {
      gid = config.ids.gids.${valheimUser} or null;
    };

    # Open firewall ports if requested (Valheim only uses port and port+1)
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
    networking.firewall.allowedUDPPorts = mkIf cfg.openFirewall [
      cfg.port
      (cfg.port + 1)
    ];

    # Systemd service
    systemd.services.valheim = {
      description = "Valheim Server";
      wantedBy = [ "multi-user.target" ];
      # The first start downloads the server via SteamCMD, so wait for a real network
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "exec";
        User = valheimUser;
        Group = valheimGroup;
        # No WorkingDirectory: it may not exist yet on a fresh install, and the
        # start script cd's into it itself after (re)creating it.
        ExecStart = "${startScript}/bin/valheim-start";
        Restart = "always";
        RestartSec = 10;

        # Directory creation and permissions ("valheim" mirrors stateDir above)
        StateDirectory = "valheim";
        StateDirectoryMode = "0755";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ stateDir ];
      }
      # Make a root-only passwordFile (e.g. sops 0400) readable as a systemd credential
      // optionalAttrs (cfg.passwordFile != null) {
        LoadCredential = "valheim-password:${cfg.passwordFile}";
      };
    };

    # Install required packages
    environment.systemPackages = [
      startScript
      cfg.steamCmdPackage
    ];
  };
}
