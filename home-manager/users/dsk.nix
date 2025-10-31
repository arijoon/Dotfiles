{ config, pkgs, ... }:
{
  home.username = "dsk";
  home.homeDirectory = "/home/dsk";

  programs.git = {
    signing = {
      signByDefault = true;
      key = "91704E358EC0018E8AC9E5F312124962221E4036";
    };

    userEmail = "arman@yaraee.net";
  };

  # Additional packages only on this machine
  home.packages = with pkgs; [
    keepassxc
  ];
}
