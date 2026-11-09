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
  armanConfig.rootNix.flavour = "upstream";

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
      # Use system one
      signer = "/usr/bin/gpg";
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
      ];
    in
    with pkgs;
    [
      yq
      mongosh
      alacritty
      # dwm-start runs `nitrogen --restore`; nitrogen left the Ubuntu archive in 26.04
      nitrogen
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

  # picom 12 (Ubuntu 26.04) refuses to start without a backend; xrender was the old default
  home.file.".config/picom/picom.conf".text = ''
    backend = "xrender";
  '';
}
