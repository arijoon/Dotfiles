#!/usr/bin/env bash
set -euo pipefail

SHARE_PATH="/run/media/veracrypt2"
IFACE="enp13s0"
SMB_USER="dsk"
SHARE_NAME="videos"

NIX_BIN="/home/dsk/.nix-profile/bin"
SMBD="${NIX_BIN}/smbd"
SMBPASSWD="${NIX_BIN}/smbpasswd"
TESTPARM="${NIX_BIN}/testparm"
UNIT="/etc/systemd/system/smbd-nix.service"

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo $0" >&2
    exit 1
fi

if ! id "$SMB_USER" &>/dev/null; then
    echo "Unix user '$SMB_USER' does not exist." >&2
    exit 1
fi

if [[ ! -x "$SMBD" ]]; then
    echo "nix smbd not found at $SMBD -- run 'nix run .#home-manager -- switch --flake .#dsk' first." >&2
    exit 1
fi

echo "==> Creating samba state directories"
install -d -m 0755 /var/lib/samba /var/cache/samba /var/log/samba
install -d -m 0700 /var/lib/samba/private

echo "==> Writing /etc/samba/smb.conf"
install -d -m 0755 /etc/samba
if [[ -f /etc/samba/smb.conf ]]; then
    cp -a /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$(date +%s)"
fi

cat > /etc/samba/smb.conf <<EOF
[global]
   workgroup = WORKGROUP
   server string =
   disable netbios = yes
   smb ports = 445
   bind interfaces only = yes
   interfaces = lo ${IFACE}
   server min protocol = SMB3
   map to guest = never
   restrict anonymous = 2
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes

   private dir = /var/lib/samba/private
   state directory = /var/lib/samba
   lock directory = /var/lib/samba
   cache directory = /var/cache/samba
   pid directory = /run/samba
   ncalrpc dir = /run/samba/ncalrpc

   log file = /var/log/samba/%m.log
   max log size = 1000
   log level = 1

[${SHARE_NAME}]
   path = ${SHARE_PATH}
   valid users = ${SMB_USER}
   read only = yes
   browseable = no
EOF

echo "==> Validating config (nix testparm)"
"$TESTPARM" -s /etc/samba/smb.conf >/dev/null

echo "==> Writing systemd unit ${UNIT}"
cat > "$UNIT" <<EOF
[Unit]
Description=Samba SMB Daemon (nix)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SMBD} --foreground --no-process-group --configfile=/etc/samba/smb.conf
ExecReload=/bin/kill -HUP \$MAINPID
RuntimeDirectory=samba
RuntimeDirectoryMode=0755
LimitNOFILE=16384
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "==> Set the SMB password for '${SMB_USER}' (separate from your login password)"
"$SMBPASSWD" -c /etc/samba/smb.conf -a "$SMB_USER"
"$SMBPASSWD" -c /etc/samba/smb.conf -e "$SMB_USER"

systemctl daemon-reload

cat <<EOF

Setup complete. Nothing is running yet.

Before starting, make sure the veracrypt volume is mounted at ${SHARE_PATH}.

Enable + start the service:
  sudo systemctl enable --now smbd-nix.service

Check it:
  systemctl status smbd-nix.service

On your phone, connect to  \\\\192.168.0.237\\${SHARE_NAME}
  user: ${SMB_USER}   password: (what you just set)
EOF
