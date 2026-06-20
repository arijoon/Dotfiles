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

  # Declaring `panels` makes plasma-manager own the panel: every switch wipes
  # the appletsrc and rebuilds from here, so GUI panel tweaks won't persist.
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

    panels = [
      {
        location = "top";
        height = 44;
        widgets = [
          "org.kde.plasma.kickoff"
          "org.kde.plasma.icontasks"
          "org.kde.plasma.pager"
          "org.kde.plasma.marginsseparator"
          {
            systemMonitor = {
              title = "System";
              showTitle = false;
              displayStyle = "org.kde.ksysguard.barchart";
              # If the disk bar is empty, the root mount's id differs: check the
              # widget's sensor browser under Disks (`disk/<name>/usedPercent`).
              sensors = [
                {
                  name = "cpu/all/usage";
                  label = "CPU";
                  color = "243,139,168"; # red
                }
                {
                  name = "memory/physical/usedPercent";
                  label = "RAM";
                  color = "166,227,161"; # green
                }
                {
                  name = "disk/root/usedPercent";
                  label = "Disk";
                  color = "137,180,250"; # blue
                }
              ];
              range = {
                from = 0;
                to = 100;
              };
            };
          }
          "org.kde.plasma.systemtray"
          "org.kde.plasma.digitalclock"
          "org.kde.plasma.showdesktop"
        ];
      }
    ];
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
