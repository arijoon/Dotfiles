{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.languages.nodejs;
in
{
  options.languages.nodejs = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs_24;
      description = "Pinned Node.js release.";
    };

    pnpm = lib.mkOption {
      type = lib.types.package;
      default = pkgs.pnpm_11;
      description = "Pinned pnpm release. Kept in step with the Node.js above.";
    };
  };

  config.devshell.packages = [
    cfg.package
    cfg.pnpm
  ];
}
