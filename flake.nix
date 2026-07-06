{
  description = "Valheim dedicated game server NixOS module";

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
        in
        {
          valheim-server = import ./default.nix {
            inherit pkgs;
          };
          default = self.packages.${system}.valheim-server;
        }
      );

      nixosModules.default = import ./module.nix;
    };
}
