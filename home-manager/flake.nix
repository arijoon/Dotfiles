{
  description = "Home Manager configuration of arman";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/24.11";
    nixpkg.url = "https://flakehub.com/f/NixOS/nix/=2.26.1";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkg, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { 
        inherit system;
         config.allowUnfree = true;
      };
      nixPkg = nixpkg.packages."${system}"; 
    in
    {
      homeConfigurations."arman" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [
          ./home.nix
          ./wsl.nix
          ./shell.nix
          ./xmonad.nix
          ./emacs.nix
          ./local.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
        extraSpecialArgs = {
          inherit nixpkgs;
          inherit nixPkg;
        };
      };

      packages."${system}" = {
        home-manager =  home-manager.defaultPackage."${system}";
        nix = nixPkg.nix;
      };
    };
}
