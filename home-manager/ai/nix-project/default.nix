{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.armanConfig.ai.nixProject;

  nix-project-init = pkgs.writeShellApplication {
    name = "nix-project-init";
    runtimeInputs = with pkgs; [
      age
      coreutils
      findutils
      git
      gnugrep
      gnused
    ];
    text = ''
      NIX_PROJECT_TEMPLATES=${./templates}
    ''
    + builtins.readFile ./init.sh;
  };
in
{
  options.armanConfig.ai.nixProject = {
    enable = lib.mkEnableOption "the nix-project-init command and its Claude Code skill";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ nix-project-init ];
    home.file.".claude/skills/nix-project".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.dotfiles/home-manager/ai/nix-project/skill";
  };
}
