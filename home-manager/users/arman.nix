{ config, pkgs, ... }:
{
  home.username = "arman";
  home.homeDirectory = "/home/arman";

  programs.git = {
    signing = {
      format = "openpgp";
      signByDefault = true;
      key = "10DD4601042012F6";
      # Use system one
      signer = "/usr/bin/gpg";
    };

    settings.user = {
      email = "arman.yaraee@deversifi.com";
      name = "arijoon";
    };
  };

  # Additional packages only on this machine
  home.packages = with pkgs; [
    yq
    mongosh
    alacritty
  ];
}
