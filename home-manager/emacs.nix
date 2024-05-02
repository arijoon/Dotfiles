{ lib, pkgs, config, ... }:
with lib;
let
  cfg = config.editors.emacs;
in
{
  options.editors.emacs = {
    enable = mkEnableOption "Emacs editor";
  };

  config = mkIf cfg.enable (let 
    emacs = ((pkgs.emacsPackagesFor pkgs.emacsNativeComp).emacsWithPackages
        (epkgs: [ epkgs.vterm ]));

    emacDeps = with pkgs; [
      binutils
      fd
      gnutls
      imagemagick
      pinentry-emacs
      ripgrep
      sqlite
      texlive.combined.scheme-medium
    ];

    wrapped = pkgs.stdenv.mkDerivation {
      name = "emacs-wrapped";
      nativeBuildInputs = [ pkgs.makeWrapper ];
      phases = [ "installPhase" ];

      installPhase = ''
        mkdir -p "$out/bin"
        makeWrapper "${emacs}/bin/emacs" "$out/bin/emacs" \
          --prefix PATH : ${pkgs.lib.makeBinPath emacDeps}

        makeWrapper "${emacs}/bin/emacsclient" "$out/bin/emacsclient" \
          --prefix PATH : ${pkgs.lib.makeBinPath emacDeps}
      '';
    };
  in {
    home.packages = with pkgs; [
      # Only add emacs wrapped
      wrapped
    ];

    home.activation = {
      installDoomEmacs = ''
        if [ ! -d "${config.xdg.configHome}/emacs" ]; then
          git=${pkgs.git}/bin/git
          $git clone --depth=1 --single-branch "https://github.com/doomemacs/doomemacs" "${config.xdg.configHome}/emacs"
        fi
      '';
    };
  });
}
