{
  nixgl,
  pkgs,
  lib,
  ...
}:
let
  nvidiaEnv = pkgs.writeShellScript "nvidia-driver-libs" ''
    __nixgl_nvidia_setup() {
      [ -e /usr/lib/libcuda.so.1 ] || return 0

      local base key nvdir tmp lib
      base="''${XDG_CACHE_HOME:-$HOME/.cache}/nixgl-nvidia-libs"
      key="$(readlink -f /usr/lib/libcuda.so.1)" || return 0
      key="''${key##*/}"
      [ -n "$key" ] || return 0
      nvdir="$base/$key"

      if [ ! -e "$nvdir/libGLX_nvidia.so.0" ]; then
        mkdir -p "$base" 2>/dev/null || return 0
        tmp="$(mktemp -d "$base/.tmp.XXXXXX" 2>/dev/null)" || return 0
        for lib in /usr/lib/libcuda.so* /usr/lib/libnvcuvid.so* \
                   /usr/lib/libnvidia-*.so* /usr/lib/libGLX_nvidia.so* \
                   /usr/lib/libEGL_nvidia.so*; do
          if [ -e "$lib" ]; then
            ln -sf "$lib" "$tmp/''${lib##*/}"
          fi
        done
        mv -T "$tmp" "$nvdir" 2>/dev/null || rm -rf "$tmp"
      fi

      [ -e "$nvdir/libGLX_nvidia.so.0" ] || return 0
      export LD_LIBRARY_PATH="$nvdir''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
    }

    __nixgl_nvidia_setup || true
  '';

  withHostNvidia =
    ps:
    ps
    // {
      nixGLIntel = pkgs.writeShellScriptBin "nixGLIntel" ''
        . ${nvidiaEnv}
        exec ${ps.nixGLIntel}/bin/nixGLIntel "$@"
      '';
    };
in
{
  targets.genericLinux.nixGL = {
    packages = lib.mapAttrs (_: withHostNvidia) nixgl.packages;
    defaultWrapper = "mesa";
    installScripts = [
      "mesa"
    ];
  };
}
