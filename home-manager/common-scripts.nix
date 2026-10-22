{
  config,
  lib,
  pkgs,
  nix,
  ...
}:
let
  cfg = config.armanConfig.rootNix;
in
{
  options.armanConfig.rootNix.flavour = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.enum [
        "determinate"
        "upstream"
      ]
    );
    default = null;
    description = "Nix flavour `upgrade-root-nix` installs into root's profile for the nix-daemon: /nix/var/nix/profiles/per-user/root/profile for determinate, /nix/var/nix/profiles/default for upstream. null leaves the daemon unmanaged.";
  };

  config.home.packages = [
    (pkgs.writeShellApplication {
      name = "update-ai";
      text = builtins.readFile ./scripts/update-ai;
    })
    (import ./scripts/backup-if-changed.nix { inherit pkgs; })
  ]
  ++ lib.optional (cfg.flavour != null) (
    pkgs.writeShellApplication {
      name = "upgrade-root-nix";
      runtimeInputs = [
        pkgs.jq
        pkgs.gnused
      ];
      runtimeEnv = {
        NIX_BIN = "${nix}/bin/nix";
        ROOT_NIX_FLAVOUR = cfg.flavour;
      };
      text = builtins.readFile ./scripts/upgrade-root-nix;
    }
  );
}
