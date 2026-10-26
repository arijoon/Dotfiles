{
  description = "Home Manager configuration of arman";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # Use this for users without determinate nix
    nix-src.url = "github:NixOS/nix/2.34.9";
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/=3.24.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate-nix-src.follows = "determinate/nix";
    nixpkgs-latest.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-vopono.url = "github:nixos/nixpkgs/391b592eb44808b3bd0cb80bb71b63a5a118b8bb";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zmx = {
      url = "github:neurosnap/zmx";
    };
    herdr = {
      url = "github:herdrdev/herdr/v0.9.5";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-latest,
      nixpkgs-vopono,
      determinate,
      determinate-nix-src,
      nix-src,
      home-manager,
      nixgl,
      zmx,
      herdr,
      plasma-manager,
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
      pkgs-vopono = nixpkgs-vopono.legacyPackages."${system}";
      determinate-nix = determinate-nix-src.packages."${system}";
      nix = nix-src.packages."${system}";

      commonMods = [
        ./home.nix
        ./shell.nix
        ./gpu.nix
        ./kitty.nix
        ./common-scripts.nix
        ./sandbox.nix
        ./network.nix
        ./mpv.nix
        ./opentrack.nix
        ./ai
      ];

      # On NixOS, GL works natively — drop the generic-Linux GPU setup
      # (kitty.nix's `config.lib.nixGL.wrap` falls back to an identity wrapper).
      commonModsNixOS = builtins.filter (m: m != ./gpu.nix) commonMods;
    in
    {
      homeConfigurations."arman" = home-manager.lib.homeManagerConfiguration {
        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = commonMods ++ [
          ./wsl.nix
          ./xmonad.nix
          ./emacs.nix
          ./users/arman.nix
        ];

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
        inherit pkgs;

        extraSpecialArgs = {
          inherit
            nixpkgs
            nixpkgs-latest
            pkgs-latest
            pkgs-vopono
            nixgl
            ;
          nix = nix.default;
        };
      };

      # Laptop profile (NixOS). Switch independently of nixos-rebuild:
      #   nix run .#home-manager -- switch --flake .#arlp
      homeConfigurations."arlp" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        modules = commonModsNixOS ++ [
          plasma-manager.homeModules.plasma-manager
          ./users/arlp.nix
        ];

        extraSpecialArgs = {
          inherit
            nixpkgs
            nixpkgs-latest
            pkgs-latest
            pkgs-vopono
            nixgl
            ;
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
          inherit
            nixpkgs
            nixpkgs-latest
            pkgs-latest
            pkgs-vopono
            nixgl
            ;
          nix = determinate-nix.default;
          zmx = zmx.packages."${system}".default;
          herdr = herdr.packages."${system}".default;
        };
      };

      packages."${system}" = {
        home-manager = home-manager.packages."${system}".default;
        determinate-nix = determinate-nix.default;
        upstream-nix = nix.default;
        root-nix-determinate = pkgs.buildEnv {
          name = "root-nix-determinate";
          paths = [
            determinate-nix.default
            determinate.packages."${system}".default
          ];
        };
        root-nix-upstream = nix.default;
      };
    };
}
