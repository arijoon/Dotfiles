{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.armanConfig.ai.ralph;

  tools = with pkgs; [
    coreutils
    findutils
    gawk
    git
    gnugrep
    gnused
    gnutar
    jq
    util-linux
  ];

  ralph = pkgs.writeShellApplication {
    name = "ralph";
    text = ''
      ralph_user_path="$PATH"
      PATH=${lib.makeBinPath tools}:$PATH
      RALPH_SHARE=${./templates}
    ''
    + builtins.readFile ./ralph.sh;
    excludeShellChecks = [
      "SC2016"
      "SC2329"
    ];
  };
in
{
  options.armanConfig.ai.ralph = {
    enable = lib.mkEnableOption "the Ralph loop: the ralph command and its Claude Code skill";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ ralph ];
    home.file.".claude/skills/ralph".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/home-manager/ai/ralph/skill";
  };
}
