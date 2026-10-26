{
  lib,
  pkgs-latest,
  config,
  ...
}:
with lib;
let
  cfg = config.armanConfig.opentrack;
in
{
  options.armanConfig.opentrack = {
    enable = mkEnableOption "opentrack head tracking";
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs-latest.opentrack ];
  };
}
