{
  description = "Home Manager configuration of arman";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/25.05";
    # Use this for users without determinate nix
    nix-src.url = "https://flakehub.com/f/NixOS/nix/=2.29.1";
    determinate-nix-src.url = "https://flakehub.com/f/DeterminateSystems/nix-src/=3.12.0";
    nixpkgs-latest.url = "github:nixos/nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-latest,
      determinate-nix-src,
      nix-src,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-latest = import nixpkgs-latest {
        inherit system;
        config.allowUnfree = true;
      };
      determinate-nix = determinate-nix-src.packages."${system}";
      nix = nix-src.packages."${system}";

      commonMods = [
        ./home.nix
        ./shell.nix
      ];
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
        inherit pkgs;

        extraSpecialArgs = {
          inherit nixpkgs nixpkgs-latest pkgs-latest;
          nix = nix.default;
        };
      };

      homeConfigurations."dsk" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = commonMods ++ [
          # ./xmonad.nix
          # ./emacs.nix
          ./users/dsk.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
        extraSpecialArgs = {
          inherit nixpkgs nixpkgs-latest pkgs-latest;
          nix = determinate-nix.default;
        };
      };

      packages."${system}" = {
        home-manager = home-manager.packages."${system}".default;
        determinate-nix = determinate-nix.default;
        upstream-nix = nix.default;
      };
    };
}
