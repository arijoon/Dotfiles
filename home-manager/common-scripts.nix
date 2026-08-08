{ pkgs, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "update-ai";
      text = builtins.readFile ./scripts/update-ai;
    })
    (import ./scripts/backup-if-changed.nix { inherit pkgs; })
  ];
}
