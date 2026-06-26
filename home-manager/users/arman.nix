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
    ] ++ latest;
}
