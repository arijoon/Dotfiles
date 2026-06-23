{
  lib,
  pkgs,
  pkgs-latest,
  config,
  ...
}:
with lib;
let
  cfg = config.armanConfig.mpv;

  # Python env for the lua scripts. `autosub.lua` shells out to `subliminal`
  # to download subtitles.
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.subliminal ]);

  # mpv from nixpkgs-latest, nixGL-wrapped so GL works on non-NixOS (Manjaro).
  mpvGL = config.lib.nixGL.wrap pkgs-latest.mpv;

  # Re-wrap mpv so its script dependencies are scoped to the mpv process
  # instead of polluting the user profile:
  #   - PATH gets ffmpeg (slicing.lua / sub-cut.lua) and subliminal
  #     (autosub.lua); spawned subprocesses inherit it.
  #   - secrets (e.g. the OpenSubtitles login) are sourced from a file kept
  #     OUT of git and the Nix store. Optional — mpv launches fine without it,
  #     autosub just skips the logged-in provider.
  mpvWrapped = pkgs.symlinkJoin {
    name = "mpv-wrapped";
    paths = [ mpvGL ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/mpv \
        --prefix PATH : ${
          makeBinPath [
            pkgs.ffmpeg
            pythonEnv
          ]
        } \
        --run 'if [ -f "$HOME/.config/mpv/secrets.env" ]; then set -a; . "$HOME/.config/mpv/secrets.env"; set +a; fi'
    '';
  };
in
{
  options.armanConfig.mpv = {
    enable = mkEnableOption "Enable the mpv media player";
  };

  config = mkIf cfg.enable {
    home.packages = [ mpvWrapped ];

    # Config migrated from ~/.config/mpv. `recursive` symlinks each file
    # individually so mpv can still write its own state (e.g. watch_later).
    home.file.".config/mpv" = {
      source = ./home-files/mpv;
      recursive = true;
    };
  };
}
