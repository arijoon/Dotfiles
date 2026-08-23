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
      libgbm
      libvdpau-va-gl
      nvidia-vaapi-driver
    ];
  };

  depLibs = lib.makeLibraryPath (
    with pkgs;
    [
      libX11
      libXext
      libxcb
      libdrm
      libgbm
      wayland
      openssl
    ]
  );

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
      deps="${depLibs}"

      list_nvidia_libs() {
        local l
        for l in /usr/lib/libcuda.so* /usr/lib/libcudadebugger.so* \
                 /usr/lib/libnvcuvid.so* /usr/lib/libnvoptix.so* \
                 /usr/lib/libnvidia-*.so* /usr/lib/libGLX_nvidia.so* \
                 /usr/lib/libEGL_nvidia.so* /usr/lib/vdpau/libvdpau_nvidia.so*; do
          [ -e "$l" ] && printf '%s\n' "$l"
        done
        return 0
      }

      install_lib() {
        local src="$1" dst="$2" target
        if [ -L "$src" ]; then
          target="$(readlink "$src")"
          ln -sfn "''${target##*/}" "$dst"
        else
          cp -f "$src" "$dst"
          chmod u+w "$dst"
          patchelf --set-rpath "/run/opengl-driver/lib:$deps" "$dst" 2>/dev/null || true
        fi
      }

      nvdir=""
      if [ -e /usr/lib/libcuda.so.1 ]; then
        real="$(readlink -f /usr/lib/libcuda.so.1)"
        ver="''${real##*/libcuda.so.}"
        sig="$(list_nvidia_libs | xargs -r stat -Lc '%n %s %Y' | sha256sum | cut -c1-12)"
        nvdir="$state/nvidia-$ver-$sig"

        if [ ! -e "$nvdir/.stamp" ]; then
          rm -rf "$nvdir.tmp"
          mkdir -p "$nvdir.tmp/lib/vdpau"

          while read -r l; do
            case "$l" in
              /usr/lib/vdpau/*) install_lib "$l" "$nvdir.tmp/lib/vdpau/''${l##*/}" ;;
              *) install_lib "$l" "$nvdir.tmp/lib/''${l##*/}" ;;
            esac
          done < <(list_nvidia_libs)

          touch "$nvdir.tmp/.stamp"
          rm -rf "$nvdir"
          mv -T "$nvdir.tmp" "$nvdir"
        fi
      fi

      new="$(mktemp -d "$state/merged.XXXXXX")"
      chmod 755 "$new"
      cp -rsL "$mesa"/. "$new"/
      chmod -R u+w "$new"

      if [ -n "$nvdir" ] && [ -e "$nvdir/.stamp" ]; then
        mkdir -p "$new/lib/vdpau" \
                 "$new/share/glvnd/egl_vendor.d" \
                 "$new/share/vulkan/icd.d"

        for f in "$nvdir"/lib/*; do
          [ -d "$f" ] && continue
          ln -sfn "$f" "$new/lib/''${f##*/}"
        done

        for f in "$nvdir"/lib/vdpau/*; do
          [ -e "$f" ] || continue
          ln -sfn "$f" "$new/lib/vdpau/''${f##*/}"
        done

        printf '{"file_format_version":"1.0.0","ICD":{"library_path":"/run/opengl-driver/lib/libEGL_nvidia.so.0"}}\n' \
          > "$new/share/glvnd/egl_vendor.d/10_nvidia.json"

        if [ -e /usr/share/vulkan/icd.d/nvidia_icd.json ]; then
          api="$(sed -n 's/.*"api_version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
                 /usr/share/vulkan/icd.d/nvidia_icd.json | head -1)"
          if [ -n "$api" ]; then
            printf '{"file_format_version":"1.0.0","ICD":{"library_path":"/run/opengl-driver/lib/libGLX_nvidia.so.0","api_version":"%s"}}\n' \
              "$api" > "$new/share/vulkan/icd.d/nvidia_icd.json"
          else
            printf '{"file_format_version":"1.0.0","ICD":{"library_path":"/run/opengl-driver/lib/libGLX_nvidia.so.0"}}\n' \
              > "$new/share/vulkan/icd.d/nvidia_icd.json"
          fi
        fi
      fi

      ln -sfn "$new" /run/opengl-driver.tmp
      mv -T /run/opengl-driver.tmp /run/opengl-driver

      find "$state" -maxdepth 1 \( -name 'merged.*' -o -name merged \) \
        ! -name "''${new##*/}" -exec rm -rf {} +

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
