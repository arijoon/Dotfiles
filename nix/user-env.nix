let 
  pkgs = import <nixpkgs> {};
in {
  inherit (pkgs) fzf bat direnv lorri ripgrep fd;
}

