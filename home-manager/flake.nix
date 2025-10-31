{
  description = "Home Manager configuration of arman";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/24.11";
    # Use this for users without determinate nix
    # nixpkg.url = "https://flakehub.com/f/NixOS/nix/=2.29.1";
    nixpkg.url = "https://flakehub.com/f/DeterminateSystems/nix-src/=3.12.0";
    nixpkgs-latest.url = "github:nixos/nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-latest, nixpkg, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { 
        inherit system;
         config.allowUnfree = true;
      };
      nixPkg = nixpkg.packages."${system}"; 

      commonMods = [
        ./home.nix
        ./shell.nix
      ];

      extraSpecialArgs = {
        inherit nixpkgs nixpkgs-latest;
        nixPkg = {
          nix = nixPkg.default;
        };
      };
    in
    {
      homeConfigurations."arman" = home-manager.lib.homeManagerConfiguration {
        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = commonMods ++ [
          ./wsl.nix
          ./xmonad.nix
          ./emacs.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
        inherit extraSpecialArgs pkgs;
      };

      homeConfigurations."dsk" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = commonMods ++ [
          ./home.nix
          ./shell.nix
          # ./xmonad.nix
          # ./emacs.nix
          ./users/dsk.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
        extraSpecialArgs = {
          inherit nixpkgs nixpkgs-latest;
          inherit nixPkg;
        };
      };

      packages."${system}" = {
        home-manager =  home-manager.defaultPackage."${system}";
        nix = nixPkg.default;
      };
    };
}
