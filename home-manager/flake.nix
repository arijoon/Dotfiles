{
  description = "Home Manager configuration of arman";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/25.11";
    # Use this for users without determinate nix
    nix-src.url = "https://flakehub.com/f/NixOS/nix/=2.30.2";
    determinate-nix-src.url = "https://flakehub.com/f/DeterminateSystems/nix-src/=3.12.0";
    nixpkgs-latest.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zmx = {
      url = "github:neurosnap/zmx";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-latest,
      determinate-nix-src,
      nix-src,
      home-manager,
      nixgl,
      zmx,
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
        ./nixgl.nix
        ./kitty.nix
        ./common-scripts.nix
        ./sandbox.nix
        ./network.nix
      ];

      # On NixOS, GL works natively — drop nixGL (kitty.nix's
      # `config.lib.nixGL.wrap` falls back to an identity wrapper).
      commonModsNixOS = builtins.filter (m: m != ./nixgl.nix) commonMods;
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
          ./users/arlp.nix
        ];

        extraSpecialArgs = {
          inherit
            nixpkgs
            nixpkgs-latest
            pkgs-latest
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
            nixgl
            ;
          nix = determinate-nix.default;
          zmx = zmx.packages."${system}".default;
        };
      };

      packages."${system}" = {
        home-manager = home-manager.packages."${system}".default;
        determinate-nix = determinate-nix.default;
        upstream-nix = nix.default;
      };
    };
}
