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
  home.packages = with pkgs; [
    keepassxc
    pkgs-latest.btop
    pkgs-latest.veracrypt
  ] ++ scripts;
}
