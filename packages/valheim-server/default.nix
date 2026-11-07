# The standalone package: the same launcher the NixOS module installs, built with
# default settings. Point it at a state dir and a password and it will download
# and run a full dedicated server outside of NixOS:
#
#   nix build .#valheim-server
#   VALHEIM_STATE_DIR=./state VALHEIM_PASSWORD=s3cret ./result/bin/valheim-server
{ pkgs }:

{
  valheim-server = import ./start-script.nix { inherit pkgs; } {
    name = "valheim-server";
  };
}
