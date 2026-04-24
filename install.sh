#!/usr/bin/env bash
# Ubuntu KakaoTalk one-click installer.
#
# Installs Wine (WineHQ stable, 32-bit), Korean fonts, VC++ runtime, extracts and
# installs the 32-bit KakaoTalk NSIS package into a dedicated Wine prefix, and
# wires up a launcher, a GNOME .desktop entry, and (optionally) a top-bar toggle
# via the Argos extension.
#
# Usage:
#   ./install.sh /path/to/KakaoTalk_Setup.exe        # GUI install
#   ./install.sh /path/to/KakaoTalk_Setup.exe --silent   # unattended
#
# The installer MUST be the 32-bit variant. The default download from
# kakao.com/talk/download is now 64-bit; pick "32비트" on the page to get the
# older build. File size is ~83MB vs ~93MB for 64-bit. This script verifies.

set -euo pipefail

INSTALLER="${1:-}"
MODE="${2:-gui}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$HOME/.wine_kakao"
LAUNCHER_SRC="$SCRIPT_DIR/launcher/kakaotalk"
ARGOS_SRC="$SCRIPT_DIR/argos/kakaotalk.5s.sh"

LAUNCHER_DST="$HOME/.local/bin/kakaotalk"
DESKTOP_DST="$HOME/.local/share/applications/kakaotalk.desktop"
ICON_DST_256="$HOME/.local/share/icons/hicolor/256x256/apps/kakaotalk.png"
ICON_DST_22="$HOME/.local/share/icons/hicolor/22x22/apps/kakaotalk.png"
ARGOS_DST="$HOME/.config/argos/kakaotalk.5s.sh"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; exit 1; }

# -- preflight ---------------------------------------------------------------

[ "$EUID" -ne 0 ] || die "Run as a normal user; the script will sudo when needed."
[ -f /etc/os-release ] || die "/etc/os-release missing — this script targets Ubuntu."
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || warn "Detected ID=$ID — tested on Ubuntu only; continuing."

if [ -z "$INSTALLER" ]; then
    cat <<'USAGE' >&2
Usage: ./install.sh /path/to/KakaoTalk_Setup.exe [--silent]

Download the 32-bit KakaoTalk installer from https://www.kakao.com/talk/download
(explicitly pick "32비트" — the default is now 64-bit and won't work under
a 32-bit Wine prefix). Expected size: ~83MB.
USAGE
    exit 1
fi
[ -f "$INSTALLER" ] || die "Installer not found: $INSTALLER"

if ! file "$INSTALLER" | grep -q "PE32 .*Intel 80386.*Nullsoft"; then
    file "$INSTALLER" >&2
    die "Installer is not a 32-bit NSIS PE. Use the '32비트' build (~83MB)."
fi

# -- system packages ---------------------------------------------------------

log "Adding i386 architecture and WineHQ repository."
sudo dpkg --add-architecture i386

sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -q -O /etc/apt/keyrings/winehq-archive.key \
    https://dl.winehq.org/wine-builds/winehq.key

CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-focal}}"
if [ ! -f "/etc/apt/sources.list.d/winehq-${CODENAME}.sources" ]; then
    sudo wget -q -NP /etc/apt/sources.list.d/ \
        "https://dl.winehq.org/wine-builds/ubuntu/dists/${CODENAME}/winehq-${CODENAME}.sources"
fi

# Ubuntu 20.04 ships without focal-updates in some images; Wine i386 depends
# on the newer libasound2-data that only lives there.
if [ "$CODENAME" = "focal" ] && ! grep -q "focal-updates" /etc/apt/sources.list; then
    log "Adding focal-updates (missing from /etc/apt/sources.list)."
    sudo tee -a /etc/apt/sources.list >/dev/null <<EOF

deb http://archive.ubuntu.com/ubuntu/ focal-updates main restricted
deb http://archive.ubuntu.com/ubuntu/ focal-updates universe
deb http://archive.ubuntu.com/ubuntu/ focal-updates multiverse
EOF
fi

log "Running apt update and installing Wine + helpers."
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y --install-recommends \
    winehq-stable winetricks \
    xdotool wmctrl imagemagick p7zip-full coreutils wget

# Bring winetricks up to date — the Ubuntu-packaged copy is years old and
# fails sha256 checks on modern VC++ redistributable downloads.
log "Updating winetricks to the upstream release."
echo Y | sudo winetricks --self-update >/dev/null

# -- wine prefix -------------------------------------------------------------

export WINEARCH=win32
export WINEPREFIX="$PREFIX"
export WINEDLLOVERRIDES="mscoree=;mshtml="
export WINEDEBUG=-all

if [ -d "$PREFIX" ]; then
    warn "Existing prefix at $PREFIX will be reused. Use --clean to wipe (future flag)."
else
    log "Creating fresh 32-bit Wine prefix at $PREFIX."
    wineboot -i >/dev/null 2>&1
fi

log "Installing Korean fonts and the VC++ 2019 runtime (takes a few minutes)."
winetricks -q win10 cjkfonts vcrun2019 corefonts >/dev/null

# -- KakaoTalk install -------------------------------------------------------

if [ "$MODE" = "--silent" ] || [ "$MODE" = "silent" ]; then
    log "Running KakaoTalk installer in silent mode."
    wine "$INSTALLER" /S || true
else
    log "Launching KakaoTalk installer (click through the wizard)."
    wine "$INSTALLER"
fi

KAKAO_EXE="$PREFIX/drive_c/Program Files/Kakao/KakaoTalk/KakaoTalk.exe"

# Modern NSIS wizards sometimes exit silently under Wine after the OS check.
# If the installer produced nothing, extract the bundle manually — it's just a
# 7-zip-compatible NSIS archive wrapping a complete, unzipped install tree.
if [ ! -f "$KAKAO_EXE" ]; then
    warn "GUI installer did not place files; extracting directly as fallback."
    TARGET="$PREFIX/drive_c/Program Files/Kakao/KakaoTalk"
    TMP="$(mktemp -d)"
    7z x -y -o"$TMP" "$INSTALLER" >/dev/null
    mkdir -p "$TARGET"
    cp -r "$TMP"/* "$TARGET/"
    rm -rf "$TARGET/\$PLUGINSDIR"
    rm -rf "$TMP"
fi
[ -f "$KAKAO_EXE" ] || die "KakaoTalk.exe still missing at $KAKAO_EXE after extraction."

# -- launcher, icon, desktop entry -------------------------------------------

log "Installing launcher to $LAUNCHER_DST."
mkdir -p "$(dirname "$LAUNCHER_DST")"
install -m 0755 "$LAUNCHER_SRC" "$LAUNCHER_DST"

log "Converting icon."
ICO="$PREFIX/drive_c/Program Files/Kakao/KakaoTalk/resource/icon/icon_kakaotalk_idle.ico"
mkdir -p "$(dirname "$ICON_DST_256")" "$(dirname "$ICON_DST_22")"
convert "${ICO}[0]" -resize 256x256 "$ICON_DST_256"
convert "${ICO}[0]" -resize 22x22   "$ICON_DST_22"

log "Installing desktop entry."
mkdir -p "$(dirname "$DESKTOP_DST")"
cat > "$DESKTOP_DST" <<DESKTOP
[Desktop Entry]
Name=KakaoTalk
Name[ko]=카카오톡
Comment=KakaoTalk messenger (via Wine)
Exec=$LAUNCHER_DST
Icon=kakaotalk
Terminal=false
Type=Application
Categories=Network;InstantMessaging;
StartupWMClass=kakaotalk.exe
DESKTOP
chmod 0755 "$DESKTOP_DST"
update-desktop-database "$(dirname "$DESKTOP_DST")" 2>/dev/null || true
gtk-update-icon-cache "$HOME/.local/share/icons/hicolor/" 2>/dev/null || true

# -- GNOME dock favorite -----------------------------------------------------

if command -v dconf >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    CURRENT="$(dconf read /org/gnome/shell/favorite-apps 2>/dev/null || true)"
    if [ -n "$CURRENT" ] && [[ "$CURRENT" != *"kakaotalk.desktop"* ]]; then
        log "Appending kakaotalk.desktop to GNOME dock favorites."
        NEW="${CURRENT%]*}, 'kakaotalk.desktop']"
        dconf write /org/gnome/shell/favorite-apps "$NEW"
    fi
fi

# -- argos top-bar toggle (optional) -----------------------------------------

if [ -d "$HOME/.local/share/gnome-shell/extensions/argos@pew.worldwidemann.com" ]; then
    log "Argos extension detected — installing top-bar toggle script."
    mkdir -p "$(dirname "$ARGOS_DST")"
    install -m 0755 "$ARGOS_SRC" "$ARGOS_DST"
else
    warn "Argos extension not installed — skipping top-bar toggle."
    warn "Install it from https://extensions.gnome.org/extension/1176/argos/ to enable."
fi

cat <<'DONE'

==============================================================================
  KakaoTalk installed.

  Run:           kakaotalk
  Restart:       kakaotalk --restart   (fixes the occasional black window)
  Quit:          kakaotalk --quit
  From GUI:      Dock / Activities search / Argos top-bar icon (if enabled)

  Prefix:        ~/.wine_kakao
  Launcher:      ~/.local/bin/kakaotalk
==============================================================================
DONE
