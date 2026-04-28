{
  lib,
  pkgs,
  pkgs-latest,
  config,
  ...
}:
with lib;
let
  cfg = config.armanConfig.kitty;
in
{
  options.armanConfig.kitty = {
    enable = mkEnableOption "Enable kitty terminal" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      (config.lib.nixGL.wrap pkgs-latest.kitty)
      (pkgs.writeShellApplication {
        name = "kitty-scrollback-pager";
        runtimeInputs = with pkgs; [ perl ];
        text = builtins.readFile ./scripts/kitty-scrollback-pager;
      })
    ];

    home.file.".config/kitty/kitty.conf".source = ./home-files/kitty.conf;
  };
}
