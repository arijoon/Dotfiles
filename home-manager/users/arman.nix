{ config, pkgs, ... }:
{
  home.username = "arman";
  home.homeDirectory = "/home/arman";

  programs.git = {
    signing = {
      signByDefault = true;
      key = "10DD4601042012F6";
      # Use system one
      signer = "/usr/bin/gpg";
    };

    userEmail = "arman.yaraee@deversifi.com";
    userName = "arijoon";
  };

  fonts.fontconfig.enable = true;

  # Additional packages only on this machine
  home.packages = with pkgs; [
    yq
    mongosh
    alacritty
    nerd-fonts.ubuntu-mono
    nerd-fonts.symbols-only
  ];
}
