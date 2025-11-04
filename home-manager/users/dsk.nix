{ config, pkgs, pkgs-latest, ... }:
let
  inherit (builtins) readFile;
  scripts = map
    (name:
      pkgs.writeShellScriptBin name (readFile "${../scripts}/${name}"))
    [
      "cputemp"
      "gputemp"
      "diskusage"
      "wifi"
      # For general terminal use
      "volume"
    ];
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
    latest = with pkgs-latest; [
      btop
      magic-wormhole
      rclone
      veracrypt
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
  ] ++ scripts ++ latest;
}
