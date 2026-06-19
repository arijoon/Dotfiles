{
  config,
  lib,
  pkgs,
  pkgs-latest,
  ...
}:
{
  home.username = "arlp";
  home.homeDirectory = "/home/arlp";

  programs.git = {
    # No signing key yet — generate one and fill this in if you want signed
    # commits (mirror users/dsk.nix's `signing` block).
    settings.user = {
      email = "ayaraee1@gmail.com";
      name = "arijoon";
    };
  };

  # rofi (solarized) and flameshot are configured system-wide in the NixOS
  # config (modules/desktop.nix), not here.

  # Laptop apps (extend as you like — see users/dsk.nix for ideas).
  home.packages =
    (with pkgs; [
      duf
      lazydocker
      mtr
    ])
    ++ (with pkgs-latest; [
      btop
      keepassxc
      (librewolf.override {
        nativeMessagingHosts = [ pkgs-latest.keepassxc ];
      })
    ]);
}
