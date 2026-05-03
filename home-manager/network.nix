{ pkgs, pkgs-latest, ... }:
let
  vopono = "${pkgs-latest.vopono}/bin/vopono";
  ip = "${pkgs.iproute2}/bin/ip";
  awk = "${pkgs.gawk}/bin/awk";
  cat = "${pkgs.coreutils}/bin/cat";
  fuser = "${pkgs.psmisc}/bin/fuser";
  ps = "${pkgs.procps}/bin/ps";

  with-vpn = pkgs.writeShellScriptBin "with-vpn" ''
    # with-vpn — run a command through a VPN namespace via vopono.
    #
    # Defaults to PrivateInternetAccess + OpenVPN, switzerland server.
    # Bootstrap DNS forced to 1.1.1.1 (PIA's pushed DNS still wins after
    # the tunnel is up). Default host interface is auto-detected from the
    # host's default route. The command + args are bash-quoted into the
    # single string vopono expects.
    #
    # Optional pre-flight (--check-xtables): aborts if /run/xtables.lock
    # is held by another process (dockerd, libvirtd, etc.) since vopono's
    # iptables calls will race and leave the host half-configured.

    usage() {
      ${cat} >&2 <<'EOF'
    with-vpn — run a command through a VPN namespace via vopono.

    Usage:
      with-vpn [opts] [server-glob] -- <cmd> [args...]
      with-vpn [opts] -c <path.ovpn>  -- <cmd> [args...]

    If no server is given, defaults to 'switzerland'.

    Options:
      -i, --interface <name>   Override host interface (default: auto-detected).
      -D, --dns <ip>           Override bootstrap DNS (default: 1.1.1.1).
      -c, --config <path>      Use a custom .ovpn instead of the PIA provider.
      -k, --keep-alive         Don't tear down namespace after command exits.
          --check-xtables      Abort if /run/xtables.lock is held by another
                               process (dockerd, libvirtd, etc.). Off by default.
      -h, --help               Show this help.

    Examples:
      with-vpn -- curl -s ifconfig.me            # defaults to switzerland
      with-vpn 'us-*' -- firefox
      with-vpn -c ~/secrets/work.ovpn -- bash
      with-vpn -i wlan0 japan -- speedtest-cli
    EOF
    }

    iface=""
    dns="1.1.1.1"
    keep=0
    check_xtables=0
    custom_cfg=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -i|--interface) iface="$2"; shift 2 ;;
        -D|--dns)       dns="$2"; shift 2 ;;
        -c|--config)    custom_cfg="$2"; shift 2 ;;
        -k|--keep-alive) keep=1; shift ;;
        --check-xtables) check_xtables=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "with-vpn: unknown option: $1" >&2; exit 2 ;;
        *)  break ;;
      esac
    done

    if [[ -n "$custom_cfg" ]]; then
      [[ -f "$custom_cfg" ]] || { echo "with-vpn: config not found: $custom_cfg" >&2; exit 2; }
      provider_args=(--custom "$custom_cfg" --protocol openvpn)
    else
      # First positional is the server glob; if it looks like a command (path-y
      # or matches a binary on $PATH) or is missing, default to switzerland.
      server="switzerland"
      if [[ $# -ge 1 && "$1" != "--" ]]; then
        if [[ "$1" != */* ]] && ! command -v "$1" >/dev/null 2>&1; then
          server="$1"; shift
        fi
      fi
      provider_args=(--provider PrivateInternetAccess --protocol openvpn --server "''${server}")
    fi

    [[ "''${1:-}" == "--" ]] && shift
    [[ $# -ge 1 ]] || { echo "with-vpn: no command specified" >&2; exit 2; }

    if [[ -z "$iface" ]]; then
      iface="$(${ip} route show default 2>/dev/null | ${awk} '/default/ {print $5; exit}')"
      [[ -n "$iface" ]] || { echo "with-vpn: could not auto-detect default interface" >&2; exit 2; }
    fi

    if [[ $check_xtables -eq 1 ]]; then
      holders="$(sudo -n ${fuser} /run/xtables.lock 2>/dev/null || sudo ${fuser} /run/xtables.lock 2>/dev/null || true)"
      if [[ -n "''${holders// }" ]]; then
        echo "with-vpn: /run/xtables.lock is held by PID(s):''${holders}" >&2
        # shellcheck disable=SC2086
        ${ps} -o pid=,comm= -p ''${holders} 2>/dev/null >&2 || true
        echo "with-vpn: refusing to start — vopono's iptables calls will race." >&2
        echo "with-vpn:   stop the holder (e.g. 'sudo systemctl stop docker.socket docker.service')" >&2
        echo "with-vpn:   or drop --check-xtables to proceed anyway." >&2
        exit 3
      fi
    fi

    quoted="$(printf '%q ' "$@")"
    quoted="''${quoted% }"
    # Preserve PATH so apps inside the namespace can find home-manager binaries
    # (vopono uses sudo which resets PATH via secure_path)
    quoted="env PATH=$PATH ''${quoted}"

    vopono_args=(exec -i "$iface" --dns "$dns" "''${provider_args[@]}" "''${quoted}")
    [[ $keep -eq 1 ]] && vopono_args=(exec --keep-alive -i "$iface" --dns "$dns" "''${provider_args[@]}" "''${quoted}")

    exec ${vopono} "''${vopono_args[@]}"
  '';
in
{
  home.packages = [
    pkgs-latest.vopono
    with-vpn
  ];
}
