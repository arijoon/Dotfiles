{
  config,
  pkgs,
  lib,
  pkgs-latest,
  ...
}:
{
  home.username = "arman";
  home.homeDirectory = "/home/arman";

  armanConfig.ai.opencode.enable = true;

  # start-ticket: create a Jira ticket -> wt worktree -> kitty tab title.
  # Sourced as a zsh function (after worktrunk's `wt` init in home.nix) so that
  # `wt switch` can cd the interactive shell into the new worktree.
  programs.zsh.initContent = lib.mkOrder 1500 ''
    source ${../scripts/start-ticket.zsh}
  '';

  programs.git = {
    signing = {
      format = "openpgp";
      signByDefault = true;
      key = "10DD4601042012F6";
    };

    settings.user = {
      email = "arman.yaraee@deversifi.com";
      name = "arijoon";
    };
  };

  # Additional packages only on this machine
  home.packages =
    let
      latest = with pkgs-latest; [
        (librewolf.override {
          nativeMessagingHosts = [ keepassxc ];
        })
        # fhs: extensions ship generic Linux binaries (rust-analyzer, C#, ...)
        vscode.fhs
      ];
    in
    with pkgs;
    [
      yq
      mongosh
      rclone
      # spice-vdagent itself stays the system one, matching the system spice-vdagentd
      (writeShellApplication {
        name = "vm-display-fix";
        runtimeInputs = [
          xrandr
          gawk
          procps
          util-linux
          nitrogen
        ];
        text = builtins.readFile ../scripts/vm-display-fix;
      })
    ]
    ++ latest;

  # Back up ~/drive (WorkDb.kdbx) to Google Drive every 5 minutes. Was a crontab
  # line on the Ubuntu VM, which failed unnoticed for months once the token
  # expired; here failures show in `systemctl --user --failed` and the journal
  # (`journalctl --user -u rclone-drive-sync`). Token: `rclone config reconnect gdrive:`.
  systemd.user.services.rclone-drive-sync = {
    Unit.Description = "Sync ~/drive to gdrive:/xub_pc/drive";
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe pkgs.rclone} sync %h/drive gdrive:/xub_pc/drive -v";
    };
  };
  systemd.user.timers.rclone-drive-sync = {
    Unit.Description = "Sync ~/drive to Google Drive every 5 minutes";
    Timer.OnCalendar = "*:0/5";
    Install.WantedBy = [ "timers.target" ];
  };

  programs.git.maintenance = {
    enable = true;
    repositories = [ "/code/rhino-core" ];
  };
}
