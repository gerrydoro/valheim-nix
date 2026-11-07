# Valheim dedicated server launcher.
#
# This file is the implementation behind two interfaces:
#   * the NixOS module (services.valheim), which bakes its option values in via
#     the @VAR@ placeholders below, and
#   * the standalone package (nix build .#valheim-server), which ships the
#     defaults and is reconfigured per-run through the VALHEIM_* environment
#     variables.
#
# Build-time settings are substituted by packages/valheim-server/start-script.nix
# and default to the same values as the services.valheim module options. Every
# setting can still be overridden by an environment variable at run time.
#
# Password resolution order (first one that yields a value wins):
#   1. $CREDENTIALS_DIRECTORY/valheim-password  (systemd LoadCredential, used
#      when services.valheim.passwordFile is set)
#   2. $VALHEIM_PASSWORD_FILE                    (file path, for manual runs)
#   3. $VALHEIM_PASSWORD                         (environment)
#   4. the baked password            (services.valheim.password at build time)
#
# The Steam app ids intentionally differ and must not be unified: 896660 is the
# dedicated server we download with SteamCMD, 892970 is the client id the server
# binary requires at run time.

# --- baked defaults (substituted at build time; see start-script.nix) ---------
bakedServerName=@VALHEIM_SERVER_NAME@
bakedPort=@VALHEIM_PORT@
bakedWorldName=@VALHEIM_WORLD@
bakedMaxPlayers=@VALHEIM_MAX_PLAYERS@
bakedPublic=@VALHEIM_PUBLIC@
bakedSaveDebug=@VALHEIM_SAVE_DEBUG@
bakedDebug=@VALHEIM_DEBUG@
bakedAutoUpdate=@VALHEIM_AUTO_UPDATE@
bakedStateDir=@VALHEIM_STATE_DIR@
bakedPassword=@VALHEIM_PASSWORD@

# --- effective settings (environment overrides the baked defaults) -----------
serverName="${VALHEIM_SERVER_NAME:-$bakedServerName}"
port="${VALHEIM_PORT:-$bakedPort}"
worldName="${VALHEIM_WORLD:-$bakedWorldName}"
maxPlayers="${VALHEIM_MAX_PLAYERS:-$bakedMaxPlayers}"
publicFlag="${VALHEIM_PUBLIC:-$bakedPublic}"
saveDebug="${VALHEIM_SAVE_DEBUG:-$bakedSaveDebug}"
debugMode="${VALHEIM_DEBUG:-$bakedDebug}"
autoUpdate="${VALHEIM_AUTO_UPDATE:-$bakedAutoUpdate}"
stateDir="${VALHEIM_STATE_DIR:-$bakedStateDir}"

steamServerAppId=896660
export SteamAppId=892970

steamDir="$stateDir/.local/share/Steam"
# The install path contains a space ("Valheim dedicated server"); quoting the
# variables (not the literal) is what keeps every use of it correct.
serverDir="$steamDir/Steamapps/common/Valheim dedicated server"
homeDir="${HOME:-$stateDir}"

echo "Preparing Valheim server in $serverDir"
mkdir -p "$serverDir"

steamcmdUpdate() {
	echo "Updating Valheim server binaries via SteamCMD (app $steamServerAppId)..."
	steamcmd +login anonymous +force_install_dir "$serverDir" +app_update "$steamServerAppId" validate +quit
}

if [ ! -f "$serverDir/valheim_server.x86_64" ]; then
	# First start (or a wiped state dir): the download must succeed.
	steamcmdUpdate
elif [ "$autoUpdate" = "1" ]; then
	steamcmdUpdate
fi

# SteamGameServer looks for steamclient.so under $HOME/.steam/sdk64; without this
# symlink the server exits immediately (and silently, when run under systemd).
mkdir -p "$homeDir/.steam/sdk64"
if [ -f "$serverDir/linux64/steamclient.so" ]; then
	ln -sf "$serverDir/linux64/steamclient.so" "$homeDir/.steam/sdk64/steamclient.so"
fi

# The 64-bit libraries live next to the server binary.
export LD_LIBRARY_PATH="$serverDir/linux64:${LD_LIBRARY_PATH:-}"

# Password precedence: credential > passwordFile > environment > baked value.
password="${VALHEIM_PASSWORD:-$bakedPassword}"
if [ -n "${VALHEIM_PASSWORD_FILE:-}" ] && [ -f "$VALHEIM_PASSWORD_FILE" ]; then
	password=$(cat "$VALHEIM_PASSWORD_FILE")
fi
if [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -f "$CREDENTIALS_DIRECTORY/valheim-password" ]; then
	password=$(cat "$CREDENTIALS_DIRECTORY/valheim-password")
fi

# Valheim refuses to boot on a missing, too short, or world-name-containing
# password; fail loudly here instead of dying without a trace.
if [ -z "$password" ]; then
	echo "ERROR: no server password configured (set services.valheim.password, use passwordFile, or export VALHEIM_PASSWORD)" >&2
	exit 1
fi
if [ "${#password}" -lt 5 ]; then
	echo "ERROR: the server password must be at least 5 characters long" >&2
	exit 1
fi
case "$password" in
*"$worldName"*)
	echo "ERROR: the server password must not contain the world name" >&2
	exit 1
	;;
esac

cd "$serverDir" || exit 1

# The password is visible in the process cmdline (ps, systemctl status) no
# matter which channel it came from; Valheim only accepts it as an argument.
serverArgs=(
	-name "$serverName"
	-port "$port"
	-world "$worldName"
	-password "$password"
	-public "$publicFlag"
	-nographics -batchmode -server -autostart
	-maxplayers "$maxPlayers"
)
if [ "$saveDebug" = "1" ]; then
	serverArgs+=(-savedebug)
fi
if [ "$debugMode" = "1" ]; then
	serverArgs+=(-debug)
fi

echo "Starting Valheim server '$serverName' (world: $worldName, port: $port)"
exec steam-run ./valheim_server.x86_64 "${serverArgs[@]}"
