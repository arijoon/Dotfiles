{ lib, pkgs, config, ... }:
with lib;
let
  inherit (builtins) readFile;
  cfg = config.armanConfig.xmonad;
in
{
  options.armanConfig.xmonad = {
    enable = mkEnableOption "Enable XMonad";
  };

  config =
    let
      scripts = map
        (name:
          pkgs.writeShellScriptBin name (readFile "${./scripts}/${name}"))
        [
          "cputemp"
          "gputemp"
          "diskusage"
          "wifi"
          # For general terminal use
          "volume"
        ];
    in
    mkIf cfg.enable {
      home.packages = with pkgs; [
        nitrogen
        picom
        haskellPackages.xmobar
      ] ++ scripts;

      xsession.windowManager.xmonad = {
        enable = true;
        config = ./xmonad/.xmonad/xmonad.hs;
        extraPackages = hp: with hp; [
          xmonad-contrib
          xmobar
        ];
      };

      home.file.".xmobarrc.hs".source = ./xmonad/.xmobarrc.hs;
    };
}
