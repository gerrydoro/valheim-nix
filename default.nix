{ pkgs }:

pkgs.symlinkJoin {
  name = "valheim-server";
  paths = [
    pkgs.steamcmd
    pkgs.steam-run
  ];
  buildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    # Ensure steamcmd and steam-run are properly wrapped
    wrapProgram "$out/bin/steamcmd" --prefix LD_LIBRARY_PATH : "${pkgs.stdenv.cc.cc.lib}/lib"
  '';

  meta = with pkgs.lib; {
    description = "Valheim dedicated game server tools (steamcmd + steam-run)";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
