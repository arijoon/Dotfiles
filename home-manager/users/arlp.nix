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
              # Text Only face: compact numbers (CPU %, RAM used/total GiB, Disk
              # used GiB) instead of cramped bars.
              displayStyle = "org.kde.ksysguard.textonly";
              # Labels are Nerd Font glyphs (via fromJSON so the source stays ASCII):
              #   uf4bc oct-cpu (chip) · uefc5 fa-memory (RAM stick) · uf0a0 fa-hdd
              # They fall back to "Symbols Nerd Font Mono"; stick to BMP PUA
              # (U+E000–U+F8FF) — Material-Design icons (U+F0000+) don't render here.
              # The compact (panel) view only renders highPrioritySensorIds, so RAM
              # total is added as its own `memory/physical/total` sensor with a "/"
              # label; its swatch colour is the panel background (32,35,38) so it
              # disappears and RAM reads as one group: " 4.9 GiB / 62.5 GiB".
              # Sensor ids come from ksystemstats; list them with:
              #   busctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1 \
              #     org.kde.ksystemstats1 allSensors
              # `disk/all` aggregates all mounts (root has no stable `disk/root` id
              # here — it's a btrfs/cryptroot UUID).
              sensors = [
                {
                  name = "cpu/all/usage";
                  label = builtins.fromJSON ''"\uf4bc"'';
                  color = "243,139,168"; # red
                }
                {
                  name = "memory/physical/used";
                  label = builtins.fromJSON ''"\uefc5"'';
                  color = "166,227,161"; # green
                }
                {
                  name = "memory/physical/total";
                  label = "/";
                  color = "32,35,38"; # panel background \u2192 swatch hidden
                }
                {
                  name = "disk/all/used";
                  label = builtins.fromJSON ''"\uf0a0"'';
                  color = "137,180,250"; # blue
                }
              ];
              # plasma-manager's `sensors` helper double-escapes the id list
              # (`toEscapedList` adds `\"` then writeConfig JSON-encodes it again),
              # so the widget stores `[\"cpu/all/usage\",...]` — invalid JSON and
              # nothing renders. `settings` is merged last, so override the key with
              # a plain JSON string (toJSON turns it into the correct `["..."]`).
              settings.Sensors.highPrioritySensorIds = ''["cpu/all/usage","memory/physical/used","memory/physical/total","disk/all/used"]'';
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
