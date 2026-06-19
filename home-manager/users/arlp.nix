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

  # Declarative KDE Plasma config (plasma-manager). overrideConfig stays false
  # (default), so this only sets what's listed here and leaves the rest of your
  # Plasma settings (e.g. a manually-positioned panel) intact.
  programs.plasma = {
    enable = true;

    # Global dark theme.
    workspace.lookAndFeel = "org.kde.breezedark.desktop";

    # Alt+P -> rofi, matching the dwm binding.
    hotkeys.commands."launch-rofi" = {
      name = "Launch rofi";
      key = "Alt+P";
      command = "rofi -show drun";
    };
  };

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
      magic-wormhole
      rclone
      veracrypt
      vscode
      (librewolf.override {
        nativeMessagingHosts = [ pkgs-latest.keepassxc ];
      })
    ]);
}
