{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.armanConfig.hostNvidia;

  stateDir = "/var/lib/nix-host-gpu";

  mesaEnv = pkgs.buildEnv {
    name = "nix-host-gpu-mesa";
    paths = with pkgs; [
      mesa
      libvdpau-va-gl
      nvidia-vaapi-driver
    ];
  };

  builder = pkgs.writeShellApplication {
    name = "nix-host-gpu-build";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      gnused
      patchelf
    ];
    text = ''
      state="${stateDir}"
      mesa="${mesaEnv}"
      nvdir=""

      if [ -e /usr/lib/libcuda.so.1 ]; then
        real="$(readlink -f /usr/lib/libcuda.so.1)"
        ver="''${real##*/libcuda.so.}"
        nvdir="$state/nvidia-$ver"

        if [ ! -e "$nvdir/.stamp" ]; then
          rm -rf "$nvdir.tmp"
          mkdir -p "$nvdir.tmp/lib"

          for l in /usr/lib/libcuda.so* /usr/lib/libnvcuvid.so* \
                   /usr/lib/libnvidia-*.so* /usr/lib/libGLX_nvidia.so* \
                   /usr/lib/libEGL_nvidia.so*; do
            [ -e "$l" ] || continue
            b="''${l##*/}"
            if [ -L "$l" ]; then
              t="$(readlink "$l")"
              ln -sfn "''${t##*/}" "$nvdir.tmp/lib/$b"
            else
              cp -f "$l" "$nvdir.tmp/lib/$b"
              chmod u+w "$nvdir.tmp/lib/$b"
            fi
          done

          for f in "$nvdir.tmp"/lib/*; do
            [ -L "$f" ] && continue
            patchelf --set-rpath /run/opengl-driver/lib "$f" 2>/dev/null || true
          done

          touch "$nvdir.tmp/.stamp"
          rm -rf "$nvdir"
          mv -T "$nvdir.tmp" "$nvdir"
        fi
      fi

      merged="$state/merged"
      rm -rf "$merged.tmp"
      mkdir -p "$merged.tmp"
      cp -rsL "$mesa"/. "$merged.tmp"/
      chmod -R u+w "$merged.tmp"

      if [ -n "$nvdir" ] && [ -e "$nvdir/.stamp" ]; then
        mkdir -p "$merged.tmp/lib" \
                 "$merged.tmp/share/glvnd/egl_vendor.d" \
                 "$merged.tmp/share/vulkan/icd.d"

        for f in "$nvdir"/lib/*; do
          ln -sfn "$f" "$merged.tmp/lib/''${f##*/}"
        done

        printf '{"file_format_version":"1.0.0","ICD":{"library_path":"/run/opengl-driver/lib/libEGL_nvidia.so.0"}}\n' \
          > "$merged.tmp/share/glvnd/egl_vendor.d/10_nvidia.json"

        if [ -e /usr/share/vulkan/icd.d/nvidia_icd.json ]; then
          api="$(sed -n 's/.*"api_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                 /usr/share/vulkan/icd.d/nvidia_icd.json | head -1)"
          printf '{"file_format_version":"1.0.0","ICD":{"library_path":"/run/opengl-driver/lib/libGLX_nvidia.so.0","api_version":"%s"}}\n' \
            "''${api:-1.4.0}" > "$merged.tmp/share/vulkan/icd.d/nvidia_icd.json"
        fi

        if [ -d /usr/share/egl/egl_external_platform.d ]; then
          mkdir -p "$merged.tmp/share/egl/egl_external_platform.d"
          for j in /usr/share/egl/egl_external_platform.d/*.json; do
            [ -e "$j" ] || continue
            sed 's|"library_path"[[:space:]]*:[[:space:]]*"\([^"/]*\)"|"library_path": "/run/opengl-driver/lib/\1"|' \
              "$j" > "$merged.tmp/share/egl/egl_external_platform.d/''${j##*/}"
          done
        fi
      fi

      rm -rf "$merged"
      mv -T "$merged.tmp" "$merged"

      ln -sfn "$merged" /run/opengl-driver.tmp
      mv -T /run/opengl-driver.tmp /run/opengl-driver

      if [ -n "$nvdir" ]; then
        find "$state" -maxdepth 1 -name 'nvidia-*' ! -name "''${nvdir##*/}" -exec rm -rf {} +
      fi
    '';
  };

  unit = pkgs.writeText "nix-host-gpu.service" ''
    [Unit]
    Description=Provide host GPU drivers to Nix packages at /run/opengl-driver
    After=local-fs.target
    Before=display-manager.service graphical.target

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=${lib.getExe builder}

    [Install]
    WantedBy=multi-user.target
  '';

  setup = pkgs.writeShellApplication {
    name = "nix-host-gpu-setup";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      if [ -e /etc/tmpfiles.d/non-nixos-gpu.conf ]; then
        rm -f /etc/tmpfiles.d/non-nixos-gpu.conf
        rm -f ${config.targets.genericLinux.gpu.nixStateDirectory}/gcroots/non-nixos-gpu.conf
      fi

      ln -sfn ${unit} /etc/systemd/system/nix-host-gpu.service
      ln -sfn /etc/systemd/system/nix-host-gpu.service \
        ${config.targets.genericLinux.gpu.nixStateDirectory}/gcroots/nix-host-gpu.service

      systemctl daemon-reload
      systemctl enable --now nix-host-gpu.service
      systemctl restart nix-host-gpu.service
    '';
  };
in
{
  options.armanConfig.hostNvidia = {
    enable = lib.mkEnableOption "host GPU drivers at /run/opengl-driver for all Nix packages";
  };

  config = lib.mkMerge [
    {
      targets.genericLinux.gpu.enable = !cfg.enable;
    }

    (lib.mkIf cfg.enable {
      home.packages = [ setup ];

      home.activation.checkHostGpuDrivers = lib.hm.dag.entryAnywhere ''
        expected=${lib.getExe builder}
        current=$(sed -n 's/^ExecStart=//p' /etc/systemd/system/nix-host-gpu.service 2>/dev/null || true)
        if [ "''${current}" != "''${expected}" ]; then
          warnEcho "Host GPU drivers are not set up for Nix packages, or need an update. Run"
          warnEcho "  sudo ${lib.getExe setup}"
        fi
      '';
    })
  ];
}
