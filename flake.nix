{
  description = "Valheim dedicated game server NixOS module";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      packages = import ./packages/valheim-server {
        inherit pkgs;
      };
    in
    {
      packages.${system} = packages // {
        default = packages.valheim-server;
      };

      checks.${system} = packages;

      nixosModules.default = import ./modules;
    };
}
