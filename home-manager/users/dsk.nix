{ config, pkgs, pkgs-latest, ... }:
let
  inherit (builtins) readFile;
in
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
  home.packages = let 
    scriptswithDeps = [
      (pkgs.writeShellApplication {
        name = "towebm";
        text = readFile "${../scripts}/towebm";
        runtimeInputs = [ pkgs.ffmpeg ];
      })
      (pkgs.writeShellApplication {
        name = "towebmnoaudio";
        text = readFile "${../scripts}/towebmnoaudio";
        runtimeInputs = [ pkgs.ffmpeg ];
      })
    ];
    latest = with pkgs-latest; [
      btop
      magic-wormhole
      rclone
      veracrypt
      vscode
    ];
  in
    with pkgs; [
      duf
      keepassxc
      lazydocker
      lshw
      mtr
      ncdu
      termshark
      # zoxide
  ] ++ scriptswithDeps ++ latest;
}
