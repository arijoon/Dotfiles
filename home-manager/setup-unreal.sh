#!/usr/bin/env bash
set -euo pipefail

STORE="/home/.unreal-engine"
BASE="/opt/unreal-engine"
GROUP="unreal"
BIN_LINK="/usr/local/bin/UnrealEditor"
APPS_DIR="/usr/local/share/applications"
ICONS_DIR="/usr/local/share/icons/hicolor/scalable/apps"
ICON_SRC="Engine/Content/Slate/Starship/Common/unreal-circle-thick.svg"
EDITOR_REL="Engine/Binaries/Linux/UnrealEditor"
BSDTAR="/usr/bin/bsdtar"
MIN_FREE_GB=85

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo $0 [path/to/Linux_Unreal_Engine_X.Y.Z.zip]" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo "Run via sudo from your normal user so it can be added to the '${GROUP}' group." >&2
    exit 1
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

ZIP="${1:-${TARGET_HOME}/Downloads/unreal/Linux_Unreal_Engine_5.8.4.zip}"
if [[ ! -f "$ZIP" ]]; then
    echo "Zip not found: $ZIP" >&2
    exit 1
fi

VERSION="${2:-}"
if [[ -z "$VERSION" ]]; then
    if [[ "$(basename "$ZIP")" =~ ^Linux_Unreal_Engine_([0-9][0-9.]*)\.zip$ ]]; then
        VERSION="${BASH_REMATCH[1]}"
    else
        echo "Cannot read the version from '$(basename "$ZIP")'; pass it as the second argument." >&2
        exit 1
    fi
fi

DEST="${STORE}/${VERSION}"
PARTIAL="${STORE}/.${VERSION}.partial"
EDITOR_PATH="${BASE}/${VERSION}/${EDITOR_REL}"
DESKTOP_FILE="${APPS_DIR}/unreal-editor-${VERSION}.desktop"
ICON_NAME="unreal-editor"

if [[ ! -x "$BSDTAR" ]]; then
    echo "$BSDTAR not found (pacman -S libarchive)." >&2
    exit 1
fi

if [[ -L "$BASE" ]]; then
    if [[ "$(readlink -f "$BASE")" != "$STORE" ]]; then
        echo "${BASE} is a symlink to $(readlink -f "$BASE"), expected ${STORE}." >&2
        exit 1
    fi
elif [[ -d "$BASE" ]]; then
    if rmdir "$BASE" 2>/dev/null; then
        echo "==> Removed empty ${BASE}"
    else
        echo "${BASE} exists and is not empty; move its contents into ${STORE} and remove it first." >&2
        exit 1
    fi
elif [[ -e "$BASE" ]]; then
    echo "${BASE} exists and is not a directory or symlink." >&2
    exit 1
fi

echo "==> Using ${STORE} (on /home, outside Timeshift's root snapshots)"
install -d -m 0755 "$STORE"
if [[ ! -L "$BASE" ]]; then
    echo "==> Linking ${BASE} -> ${STORE}"
    ln -s "$STORE" "$BASE"
fi

EXTRACT=1
if [[ -e "$DEST" ]]; then
    if [[ -x "${DEST}/${EDITOR_REL}" ]]; then
        echo "==> ${DEST} already extracted; skipping extraction"
        EXTRACT=0
    else
        echo "${DEST} exists but has no executable ${EDITOR_REL}; remove it first to reinstall." >&2
        exit 1
    fi
fi

if (( EXTRACT )); then
    FREE_GB=$(( $(df --output=avail -B1 "$STORE" | tail -1) / 1024 / 1024 / 1024 ))
    if (( FREE_GB < MIN_FREE_GB )); then
        echo "Only ${FREE_GB}G free under ${STORE}; need at least ${MIN_FREE_GB}G." >&2
        exit 1
    fi

    rm -rf "$PARTIAL"
    install -d -m 0755 "$PARTIAL"
    trap 'echo "Aborted; removing ${PARTIAL}" >&2; rm -rf "$PARTIAL"; exit 1' ERR INT TERM

    echo "==> Extracting $(basename "$ZIP") to ${DEST} (~77G, takes a while)"
    "$BSDTAR" -xf "$ZIP" -C "$PARTIAL"

    if [[ ! -x "${PARTIAL}/${EDITOR_REL}" ]]; then
        echo "${EDITOR_REL} missing or not executable after extraction." >&2
        false
    fi

    echo "==> Setting ownership root:root and removing group/other write"
    chown -R root:root "$PARTIAL"
    chmod -R go-w "$PARTIAL"

    mv "$PARTIAL" "$DEST"
    trap - ERR INT TERM
fi

echo "==> Group '${GROUP}' for writable engine plugin directory"
getent group "$GROUP" >/dev/null || groupadd -r "$GROUP"
usermod -aG "$GROUP" "$TARGET_USER"
install -d -o root -g "$GROUP" -m 2775 "${DEST}/Engine/Plugins/Marketplace"

echo "==> Linking ${BIN_LINK} -> ${EDITOR_PATH}"
install -d -m 0755 "$(dirname "$BIN_LINK")"
ln -sfn "$EDITOR_PATH" "$BIN_LINK"

echo "==> Installing icon ${ICONS_DIR}/${ICON_NAME}.svg"
install -D -m 0644 "${DEST}/${ICON_SRC}" "${ICONS_DIR}/${ICON_NAME}.svg"

echo "==> Writing ${DESKTOP_FILE}"
install -d -m 0755 "$APPS_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Unreal Editor ${VERSION}
GenericName=Game Engine
Comment=Unreal Engine ${VERSION} editor
Exec=${EDITOR_PATH} %f
Icon=${ICON_NAME}
Terminal=false
Categories=Development;IDE;
Keywords=unreal;ue5;engine;
StartupWMClass=UnrealEditor
EOF
chmod 0644 "$DESKTOP_FILE"

command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" || true

cat <<EOF

Unreal Engine ${VERSION} installed at ${BASE}/${VERSION} (stored in ${DEST}).

Log out and back in so '${TARGET_USER}' picks up the '${GROUP}' group.
Then refresh the KDE menu (as ${TARGET_USER}, not root):
  kbuildsycoca6

Launch:
  UnrealEditor
or "Unreal Editor ${VERSION}" from the app menu.

If the editor picks the AMD iGPU, launch with -graphicsadapter=0.
Once it runs, you can delete ${ZIP} to free ~40G.
EOF
