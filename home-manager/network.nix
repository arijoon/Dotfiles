{ pkgs, pkgs-latest, ... }:
let
  vopono = "${pkgs-latest.vopono}/bin/vopono";
  ip = "${pkgs.iproute2}/bin/ip";
  awk = "${pkgs.gawk}/bin/awk";
  cat = "${pkgs.coreutils}/bin/cat";
  fuser = "${pkgs.psmisc}/bin/fuser";
  ps = "${pkgs.procps}/bin/ps";
  grep = "${pkgs.gnugrep}/bin/grep";
  sleep = "${pkgs.coreutils}/bin/sleep";
  mktemp = "${pkgs.coreutils}/bin/mktemp";
  rm = "${pkgs.coreutils}/bin/rm";
  ss = "${pkgs.iproute2}/bin/ss";
  socat = "${pkgs.socat}/bin/socat";

  host-handshake = pkgs.writeShellScript "with-vpn-host-handshake" ''
    host_ip="''${VOPONO_HOST_IP:-}"
    if [ -z "$host_ip" ]; then
      host_ip="$(${pkgs.getent}/bin/getent hosts vopono.host | ${awk} '{ print $1; exit }')"
    fi
    printf '%s\n' "$host_ip" >"$1"
    i=0
    while [ ! -e "$2" ] && [ "$i" -lt 300 ]; do
      ${sleep} 0.1
      i=$((i + 1))
    done
    shift 2
    exec "$@"
  '';

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
      -f, --forward <port>     Forward a port from the namespace to the host.
                               Repeat for multiple ports.
      -H, --allow-host-access  Let the command reach services on the host, as
                               vopono.host or $VOPONO_HOST_IP.
      -P, --host-port <port>   Relay a host service that listens on 127.0.0.1
                               only to vopono.host:<port> while the command
                               runs. Implies -H. Repeat for multiple ports.
      -w, --wireguard          Use WireGuard instead of OpenVPN (default: OpenVPN).
      -k, --keep-alive         Don't tear down namespace after command exits.
          --check-xtables      Abort if /run/xtables.lock is held by another
                               process (dockerd, libvirtd, etc.). Off by default.
          --no-tune            Don't append MTU/replay tuning to the provider's
                               .ovpn files (see "OpenVPN tuning" below).
      -h, --help               Show this help.

    OpenVPN tuning (on by default, provider configs only):
      PIA's shipped .ovpn files leave tun-mtu at 1500 and replay-window at the
      64-packet default. On a path with MTU 1480 that blackholes full-size
      packets (openvpn logs "EMSGSIZE Path-MTU=1480"), and high-throughput
      streams overrun the replay window ("AEAD Decrypt error: bad packet ID").
      Both silently drop packets, which truncates HTTP range responses and
      breaks video playback in Firefox (NS_ERROR_DOM_MEDIA_RANGE_ERR).

      So before exec, any provider .ovpn missing the marker gets appended:
      tun-mtu 1400, mssfix 1360, replay-window 2048 30, mute-replay-warnings.
      Idempotent, and re-applied after a 'vopono sync' rewrites the configs.
      Custom configs passed with -c are never touched. WireGuard (-w) doesn't
      need this: vopono generates those with MTU 1280 already.

    Examples:
      with-vpn -- curl -s ifconfig.me            # defaults to switzerland
      with-vpn 'us-*' -- firefox
      with-vpn -c ~/secrets/work.ovpn -- bash
      with-vpn -i wlan0 japan -- speedtest-cli
      with-vpn -w brazil -- firefox            # WireGuard instead of OpenVPN
      with-vpn -f 8080 -f 9090 -- some-server  # forward ports 8080 and 9090
      with-vpn -H -- curl http://vopono.host:5001  # reach a host service
      with-vpn -P 7000 -- curl http://vopono.host:7000  # a 127.0.0.1-only one
    EOF
    }

    iface=""
    dns="1.1.1.1"
    keep=0
    check_xtables=0
    custom_cfg=""
    protocol="openvpn"
    tune=1
    forward_args=()
    host_args=()
    host_ports=()

    tune_openvpn_configs() {
      local dir="$1" f
      [[ -d "$dir" ]] || return 0
      for f in "$dir"/*.ovpn; do
        [[ -f "$f" ]] || continue
        ${grep} -qx '# with-vpn-tuned' "$f" && continue
        ${cat} >> "$f" <<'TUNEEOF'

    # with-vpn-tuned
    tun-mtu 1400
    mssfix 1360
    replay-window 2048 30
    mute-replay-warnings
    TUNEEOF
      done
    }

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -i|--interface) iface="$2"; shift 2 ;;
        -D|--dns)       dns="$2"; shift 2 ;;
        -c|--config)    custom_cfg="$2"; shift 2 ;;
        -f|--forward)   forward_args+=(--forward "$2"); shift 2 ;;
        -H|--allow-host-access) host_args=(--allow-host-access); shift ;;
        -P|--host-port) host_ports+=("$2"); host_args=(--allow-host-access); shift 2 ;;
        -w|--wireguard) protocol="wireguard"; shift ;;
        -k|--keep-alive) keep=1; shift ;;
        --check-xtables) check_xtables=1; shift ;;
        --no-tune)      tune=0; shift ;;
        -h|--help)      usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "with-vpn: unknown option: $1" >&2; exit 2 ;;
        *)  break ;;
      esac
    done

    if [[ -n "$custom_cfg" ]]; then
      [[ -f "$custom_cfg" ]] || { echo "with-vpn: config not found: $custom_cfg" >&2; exit 2; }
      provider_args=(--custom "$custom_cfg" --protocol "$protocol")
    else
      # First positional is the server glob; if it looks like a command (path-y
      # or matches a binary on $PATH) or is missing, default to switzerland.
      server="switzerland"
      if [[ $# -ge 1 && "$1" != "--" ]]; then
        if [[ "$1" != */* ]] && ! command -v "$1" >/dev/null 2>&1; then
          server="$1"; shift
        fi
      fi
      provider_args=(--provider PrivateInternetAccess --protocol "$protocol" --server "''${server}")
      if [[ $tune -eq 1 && "$protocol" == "openvpn" ]]; then
        tune_openvpn_configs "''${XDG_CONFIG_HOME:-$HOME/.config}/vopono/pia/openvpn"
      fi
    fi

    [[ "''${1:-}" == "--" ]] && shift
    [[ $# -ge 1 ]] || { echo "with-vpn: no command specified" >&2; exit 2; }

    for port in "''${host_ports[@]}"; do
      [[ "$port" =~ ^[0-9]+$ ]] || { echo "with-vpn: --host-port needs a port number, not '$port'" >&2; exit 2; }
    done

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

    if [[ ''${#host_ports[@]} -gt 0 ]]; then
      relay_dir="$(${mktemp} -d)"
      quoted="${host-handshake} $(printf '%q' "$relay_dir/ip") $(printf '%q' "$relay_dir/ready") ''${quoted}"
    fi

    vopono_args=(exec -i "$iface" --dns "$dns" "''${forward_args[@]}" "''${host_args[@]}" "''${provider_args[@]}" "''${quoted}")
    [[ $keep -eq 1 ]] && vopono_args=(exec --keep-alive -i "$iface" --dns "$dns" "''${forward_args[@]}" "''${host_args[@]}" "''${provider_args[@]}" "''${quoted}")

    if [[ ''${#host_ports[@]} -eq 0 ]]; then
      exec ${vopono} "''${vopono_args[@]}"
    fi

    relay() {
      local host_ip port i
      trap 'kill $(jobs -p) 2>/dev/null; exit 0' TERM
      until [[ -s "$relay_dir/ip" ]]; do
        ${sleep} 0.2
      done
      host_ip="$(<"$relay_dir/ip")"
      if [[ -z "$host_ip" ]]; then
        echo "with-vpn: the namespace has neither VOPONO_HOST_IP nor vopono.host, so nothing is relayed" >&2
        : >"$relay_dir/ready"
        wait
        return 0
      fi
      for port in "''${host_ports[@]}"; do
        ${socat} -d0 "TCP-LISTEN:$port,bind=$host_ip,fork,reuseaddr" "TCP:127.0.0.1:$port" &
      done
      for port in "''${host_ports[@]}"; do
        for ((i = 0; i < 50; i++)); do
          ${ss} -ltnH | ${awk} -v a="$host_ip:$port" '$4 == a { found = 1 } END { exit !found }' && break
          ${sleep} 0.1
        done
        if (( i < 50 )); then
          echo "with-vpn: relaying vopono.host:$port to 127.0.0.1:$port" >&2
        else
          echo "with-vpn: could not listen on $host_ip:$port, so vopono.host:$port is not relayed" >&2
        fi
      done
      : >"$relay_dir/ready"
      wait
    }

    relay &
    relay_pid=$!
    cleanup() {
      kill "$relay_pid" 2>/dev/null
      wait "$relay_pid" 2>/dev/null
      ${rm} -rf "$relay_dir"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    status=0
    ${vopono} "''${vopono_args[@]}" || status=$?
    exit "$status"
  '';
in
{
  home.packages = [
    pkgs-latest.vopono
    pkgs.wireguard-tools
    with-vpn
  ];
}
