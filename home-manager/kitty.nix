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
    fonts.fontconfig.enable = true;

    home.packages = [
      (config.lib.nixGL.wrap pkgs-latest.kitty)
      pkgs.nerd-fonts.ubuntu-mono
      pkgs.nerd-fonts.symbols-only
      (pkgs.writeShellApplication {
        name = "kitty-scrollback-pager";
        runtimeInputs = with pkgs; [ perl ];
        text = builtins.readFile ./scripts/kitty-scrollback-pager;
      })
    ];

    # Out-of-store symlink, not a /nix/store symlink: kitty's __watch_conf__
    # kitten recursively watches the directory holding the resolved config file.
    home.file.".config/kitty/kitty.conf".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/home-manager/home-files/kitty.conf";
  };
}
