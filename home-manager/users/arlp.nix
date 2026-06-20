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
    signing = {
      format = "openpgp";
      signByDefault = true;
      key = "E50B51A6FEFB447247695A6C42836F5AEC17E1E5";
    };

    settings.user = {
      email = "arman.yaraee@rhino.fi";
      name = "arijoon";
    };
  };

  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-qt;
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
