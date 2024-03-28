{ lib, pkgs, config, ... }:
with lib;                      
let
  cfg = config.services.armanwsl;
in {
  options.services.armanwsl = {
    enable = mkEnableOption "WSL arman";
  };

  config = mkIf cfg.enable {
    # TODO merge with any other config on this file
    home.file.".gnupg/gpg-agent.conf".text = ''
      pinentry-program ${pkgs.pinentry-gtk2}/bin/pinentry-gtk-2
    '';
  };
}