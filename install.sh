#!/usr/bin/env bash
# Ubuntu KakaoTalk one-click installer.
#
# Installs Wine (WineHQ stable, 32-bit), Korean fonts, VC++ runtime, extracts and
# installs the 32-bit KakaoTalk NSIS package into a dedicated Wine prefix, and
# wires up a launcher, a GNOME .desktop entry, and (optionally) a top-bar toggle
# via the Argos extension.
#
# Usage:
#   ./install.sh /path/to/KakaoTalk_Setup.exe              # GUI install
#   ./install.sh /path/to/KakaoTalk_Setup.exe --silent     # unattended
#   ./install.sh /path/to/KakaoTalk_Setup.exe --clean      # reset prefix first
#
# The installer MUST be the 32-bit variant. The default download from
# kakao.com/talk/download is now 64-bit; pick "32비트" on the page to get the
# older build. File size is ~83MB vs ~93MB for 64-bit. This script verifies.

set -euo pipefail

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

usage() {
    cat <<'USAGE'
Usage: ./install.sh /path/to/KakaoTalk_Setup.exe [--silent] [--clean]

Download the 32-bit KakaoTalk installer from https://www.kakao.com/talk/download
(explicitly pick "32비트" — the default is now 64-bit and won't work under
a 32-bit Wine prefix). Expected size: ~83MB.

Options:
  --silent  Run the installer unattended, then use extraction fallback if needed.
  --clean   Delete ~/.wine_kakao before installing. This removes KakaoTalk login
            data and all files in that Wine prefix.
USAGE
}

INSTALLER=""
MODE="gui"
CLEAN_PREFIX=0

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

INSTALLER="${1:-}"
[ -n "$INSTALLER" ] || { usage >&2; exit 1; }
shift || true

while [ "$#" -gt 0 ]; do
    case "$1" in
        --silent|silent)
            MODE="silent"
            ;;
        --clean)
            CLEAN_PREFIX=1
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
    shift
done

need_cmd() {
    command -v "$1" >/dev/null 2>&1
}

ensure_bootstrap_tools() {
    need_cmd sudo || die "Missing required command 'sudo'. Install sudo or run from a sudo-capable user."
    need_cmd apt-get || die "Missing required command 'apt-get'. This installer targets apt-based Ubuntu."
    need_cmd dpkg || die "Missing required command 'dpkg'. This installer targets Ubuntu."

    local packages=()
    need_cmd file || packages+=(file)
    need_cmd wget || packages+=(wget)
    need_cmd gpg || packages+=(gnupg)
    dpkg -s ca-certificates >/dev/null 2>&1 || packages+=(ca-certificates)

    if [ "${#packages[@]}" -gt 0 ]; then
        log "Installing bootstrap tools: ${packages[*]}."
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
    fi
}

install_winehq_key() {
    local tmp_key
    tmp_key="$(mktemp)"
    if ! wget -q -O- https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor >"$tmp_key"; then
        rm -f "$tmp_key"
        die "Failed to download or dearmor the WineHQ signing key."
    fi
    sudo mkdir -pm755 /etc/apt/keyrings
    sudo install -m 0644 "$tmp_key" /etc/apt/keyrings/winehq-archive.key
    rm -f "$tmp_key"
}

install_winehq_source() {
    local codename="$1"
    local source_url="https://dl.winehq.org/wine-builds/ubuntu/dists/${codename}/winehq-${codename}.sources"
    local tmp_source arch_line

    tmp_source="$(mktemp)"
    if ! wget -q -O "$tmp_source" "$source_url"; then
        rm -f "$tmp_source"
        die "WineHQ does not publish a repository file for Ubuntu codename '$codename': $source_url"
    fi

    arch_line="$(awk -F': ' '/^Architectures:/ {print $2; exit}' "$tmp_source")"
    if ! printf ' %s ' "$arch_line" | grep -q ' i386 '; then
        rm -f "$tmp_source"
        die "WineHQ source for '$codename' does not advertise i386 packages (Architectures: ${arch_line:-missing}). This script needs 32-bit Wine; use a supported Ubuntu release or add a tested WoW64 flow first."
    fi

    sudo install -m 0644 "$tmp_source" "/etc/apt/sources.list.d/winehq-${codename}.sources"
    rm -f "$tmp_source"
}

verify_or_create_prefix() {
    if [ "$CLEAN_PREFIX" -eq 1 ] && [ -d "$PREFIX" ]; then
        log "Removing existing Wine prefix at $PREFIX because --clean was requested."
        rm -rf "$PREFIX"
    fi

    if [ -d "$PREFIX" ]; then
        if [ ! -f "$PREFIX/system.reg" ]; then
            die "Existing prefix at $PREFIX is incomplete. Re-run with --clean to recreate it."
        fi
        if ! grep -q '^#arch=win32' "$PREFIX/system.reg"; then
            die "Existing prefix at $PREFIX is not a 32-bit Wine prefix. Re-run with --clean after backing up any needed data."
        fi
        warn "Existing 32-bit prefix at $PREFIX will be reused. Use --clean to wipe it."
    else
        log "Creating fresh 32-bit Wine prefix at $PREFIX."
        wineboot -i >/dev/null 2>&1
    fi
}

install_icons() {
    local ico="$PREFIX/drive_c/Program Files/Kakao/KakaoTalk/resource/icon/icon_kakaotalk_idle.ico"
    mkdir -p "$(dirname "$ICON_DST_256")" "$(dirname "$ICON_DST_22")"

    if [ -f "$ico" ] &&
        convert "${ico}[0]" -resize 256x256 "$ICON_DST_256" &&
        convert "${ico}[0]" -resize 22x22 "$ICON_DST_22"; then
        return
    fi

    warn "Could not convert KakaoTalk's bundled icon; installing a simple fallback icon."
    if ! convert -size 256x256 'xc:#fee500' "$ICON_DST_256" ||
        ! convert -size 22x22 'xc:#fee500' "$ICON_DST_22"; then
        warn "Fallback icon generation failed; continuing with the desktop entry but no custom icon."
        rm -f "$ICON_DST_256" "$ICON_DST_22"
    fi
}

append_gnome_favorite() {
    local current new
    current="$(dconf read /org/gnome/shell/favorite-apps 2>/dev/null || true)"
    [ -n "$current" ] || return 0
    [[ "$current" != *"kakaotalk.desktop"* ]] || return 0

    log "Appending kakaotalk.desktop to GNOME dock favorites."
    case "$current" in
        "[]"|"@as []")
            new="['kakaotalk.desktop']"
            ;;
        \[*\])
            new="${current%]}, 'kakaotalk.desktop']"
            ;;
        *)
            warn "Unexpected GNOME favorites value; skipping dock favorite update: $current"
            return 0
            ;;
    esac

    if ! dconf write /org/gnome/shell/favorite-apps "$new"; then
        warn "Could not update GNOME dock favorites; continuing."
    fi
}

# -- preflight ---------------------------------------------------------------

[ "$EUID" -ne 0 ] || die "Run as a normal user; the script will sudo when needed."
[ -f /etc/os-release ] || die "/etc/os-release missing — this script targets Ubuntu."
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] || warn "Detected ID=$ID — tested on Ubuntu only; continuing."

[ -f "$INSTALLER" ] || die "Installer not found: $INSTALLER"

ensure_bootstrap_tools

if ! file "$INSTALLER" | grep -q "PE32 .*Intel 80386.*Nullsoft"; then
    file "$INSTALLER" >&2
    die "Installer is not a 32-bit NSIS PE. Use the '32비트' build (~83MB)."
fi

# -- system packages ---------------------------------------------------------

CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
[ -n "$CODENAME" ] || die "Cannot determine Ubuntu codename from /etc/os-release."

HOST_ARCH="$(dpkg --print-architecture)"
[ "$HOST_ARCH" = "amd64" ] || die "Unsupported host architecture '$HOST_ARCH'. This installer needs amd64 Ubuntu with i386 Wine packages."

log "Checking WineHQ repository support for Ubuntu $CODENAME."
install_winehq_source "$CODENAME"
install_winehq_key

log "Adding i386 architecture."
sudo dpkg --add-architecture i386

# Ubuntu 20.04 ships without focal-updates in some images; Wine i386 depends
# on the newer libasound2-data that only lives there.
if [ "$CODENAME" = "focal" ] && ! grep -Rqs "focal-updates" /etc/apt/sources.list /etc/apt/sources.list.d; then
    log "Adding focal-updates (missing from /etc/apt/sources.list)."
    sudo tee -a /etc/apt/sources.list >/dev/null <<EOF

deb http://archive.ubuntu.com/ubuntu/ focal-updates main restricted
deb http://archive.ubuntu.com/ubuntu/ focal-updates universe
deb http://archive.ubuntu.com/ubuntu/ focal-updates multiverse
EOF
fi

log "Running apt update and installing Wine + helpers."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --install-recommends \
    winehq-stable winetricks \
    xdotool x11-utils wmctrl imagemagick p7zip-full coreutils procps \
    wget file ca-certificates gnupg

# Bring winetricks up to date — the Ubuntu-packaged copy is years old and
# fails sha256 checks on modern VC++ redistributable downloads.
log "Updating winetricks to the upstream release."
if ! printf 'Y\n' | sudo winetricks --self-update >/dev/null; then
    warn "winetricks self-update failed; continuing with the packaged winetricks."
fi

# -- wine prefix -------------------------------------------------------------

export WINEARCH=win32
export WINEPREFIX="$PREFIX"
export WINEDLLOVERRIDES="mscoree=;mshtml="
export WINEDEBUG=-all

verify_or_create_prefix

log "Installing Korean fonts and the VC++ 2019 runtime (takes a few minutes)."
winetricks -q win10 cjkfonts vcrun2019 corefonts >/dev/null

# -- KakaoTalk install -------------------------------------------------------

if [ "$MODE" = "silent" ]; then
    log "Running KakaoTalk installer in silent mode."
    wine "$INSTALLER" /S || true
else
    log "Launching KakaoTalk installer (click through the wizard)."
    wine "$INSTALLER" || warn "KakaoTalk installer exited non-zero; checking for installed files and fallback extraction."
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
    cp -a "$TMP"/. "$TARGET/"
    rm -rf "$TARGET/\$PLUGINSDIR"
    rm -rf "$TMP"
fi
[ -f "$KAKAO_EXE" ] || die "KakaoTalk.exe still missing at $KAKAO_EXE after extraction."

# -- launcher, icon, desktop entry -------------------------------------------

log "Installing launcher to $LAUNCHER_DST."
mkdir -p "$(dirname "$LAUNCHER_DST")"
install -m 0755 "$LAUNCHER_SRC" "$LAUNCHER_DST"

log "Converting icon."
install_icons

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
    append_gnome_favorite
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
