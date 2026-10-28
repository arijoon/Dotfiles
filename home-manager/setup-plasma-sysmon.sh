#!/usr/bin/env bash
set -euo pipefail

CONF="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

read -r -d '' JS <<'EOF' || true
var ps = panels();
var p = null;
for (var i = 0; i < ps.length; i++) {
    if (ps[i].location === "top") { p = ps[i]; break; }
}
if (p === null && ps.length > 0) { p = ps[0]; }
if (p === null) { throw "no panel found"; }

var w = null;
var ex = p.widgets("org.kde.plasma.systemmonitor");
for (var j = 0; j < ex.length; j++) {
    ex[j].currentConfigGroup = ["Appearance"];
    if (ex[j].readConfig("title") === "System") { w = ex[j]; break; }
}
if (w === null) { w = p.addWidget("org.kde.plasma.systemmonitor"); }

w.currentConfigGroup = ["Appearance"];
w.writeConfig("chartFace", "org.kde.ksysguard.textonly");
w.writeConfig("title", "System");
w.writeConfig("showTitle", false);

w.currentConfigGroup = ["SensorColors"];
w.writeConfig("cpu/all/usage", "243,139,168");
w.writeConfig("memory/physical/used", "166,227,161");
w.writeConfig("memory/physical/total", "32,35,38");
w.writeConfig("disk/all/used", "137,180,250");

w.currentConfigGroup = ["SensorLabels"];
w.writeConfig("cpu/all/usage", "");
w.writeConfig("memory/physical/used", "");
w.writeConfig("memory/physical/total", "/");
w.writeConfig("disk/all/used", "");

w.currentConfigGroup = ["Sensors"];
w.writeConfig("highPrioritySensorIds", '["cpu/all/usage","memory/physical/used","memory/physical/total","disk/all/used"]');

w.reloadConfig();
w.id;
EOF

NEWID="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$JS" | tr -dc '0-9')"
[ -n "$NEWID" ] || { echo "failed to add widget" >&2; exit 1; }
echo "widget id: $NEWID"

kquitapp6 plasmashell || true
for _ in $(seq 1 50); do pgrep -x plasmashell >/dev/null || break; sleep 0.2; done

PANEL="$(awk '
    /^\[Containments\]\[[0-9]+\]$/ { c=$0; gsub(/[^0-9]/,"",c); next }
    /^\[/ { next }
    $0=="plugin=org.kde.panel" { print c; exit }
' "$CONF")"
[ -n "$PANEL" ] || { echo "no panel containment found" >&2; exit 1; }

TRAY="$(awk -v cc="$PANEL" '
    $0 ~ "^\\[Containments\\]\\["cc"\\]\\[Applets\\]\\[[0-9]+\\]$" {
        a=$0; sub(/.*\[Applets\]\[/,"",a); sub(/\].*/,"",a); id=a; next
    }
    $0=="plugin=org.kde.plasma.systemtray" && id!="" { print id; exit }
' "$CONF")"

ORDER="$(awk -v hdr="[Containments][$PANEL][General]" '
    $0==hdr { ing=1; next }
    ing && /^\[/ { ing=0 }
    ing && /^AppletOrder=/ { sub(/^AppletOrder=/,""); print; exit }
' "$CONF")"

out=()
placed=
IFS=';' read -ra arr <<< "$ORDER"
for x in "${arr[@]}"; do
    [ "$x" = "$NEWID" ] && continue
    if [ -n "$TRAY" ] && [ "$x" = "$TRAY" ]; then out+=("$NEWID"); placed=1; fi
    out+=("$x")
done
[ -n "$placed" ] || out+=("$NEWID")
NEWORDER="$(IFS=';'; echo "${out[*]}")"

kwriteconfig6 \
    --file plasma-org.kde.plasma.desktop-appletsrc \
    --group Containments --group "$PANEL" --group General \
    --key AppletOrder "$NEWORDER"

if command -v kstart >/dev/null 2>&1; then
    kstart plasmashell >/dev/null 2>&1 &
else
    setsid plasmashell >/dev/null 2>&1 &
fi
disown || true

echo "panel $PANEL order: $NEWORDER (monitor before system tray ${TRAY:-<none, appended>})"
