{
  config,
  lib,
  pkgs,
  pkgs-latest,
  zmx,
  ...
}:
let
  inherit (builtins) readFile;
in
{
  home.username = "dsk";
  home.homeDirectory = "/home/dsk";

  armanConfig.mpv.enable = true;

  services.flameshot = {
    enable = true;
    package = pkgs-latest.flameshot;
  };

  programs.git = {
    signing = {
      format = "openpgp";
      signByDefault = true;
      key = "91704E358EC0018E8AC9E5F312124962221E4036";
    };

    settings.user.email = "arman@yaraee.net";
  };

  # Additional packages only on this machine
  home.packages =
    let
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
        (librewolf.override {
          nativeMessagingHosts = [ keepassxc ];
        })
        keepassxc
        magic-wormhole
        rclone
        veracrypt
        vscode
      ];
    in
    with pkgs;
    [
      duf
      lazydocker
      lshw
      mtr
      ncdu
      termshark
      # zoxide
    ]
    ++ scriptswithDeps
    ++ latest
    ++ [ zmx ];

  programs.zsh.initContent = lib.mkOrder 1000 ''
    if command -v zmx &> /dev/null; then
      eval "$(zmx completions zsh)"
    fi
  '';
}
