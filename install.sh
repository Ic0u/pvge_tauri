#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  PvZ2 Gardendless — macOS Installer
#  curl -fsSL https://raw.githubusercontent.com/Ic0u/pvge_tauri/main/install.sh | bash
# ──────────────────────────────────────────────────────────────
set -euo pipefail

REPO="Ic0u/pvge_tauri"
APP_NAME="PvZ2 Gardendless"
VERSION=""
ASSET_URL=""

# ── PvZ2 green palette (256-color) ────────────────────────────
#  G1  lime glow   #afff00  color 154   — banner / highlights
#  G2  vivid green #5fd700  color 76    — step headers
#  G3  mid green   #00af00  color 34    — ok checkmarks
#  G4  dark green  #005f00  color 22    — dim labels / credits
#  WH  white bold            —          — values
#  RD  red                   —          — errors
#  YL  yellow                —          — warnings
R='\033[0m'
G1='\033[38;5;154m'   # lime glow
G2='\033[38;5;76m'    # vivid green
G3='\033[38;5;34m'    # mid green
G4='\033[38;5;22m'    # dark green
WH='\033[1;37m'
RD='\033[1;31m'
YL='\033[1;33m'

banner() {
  printf "\n${G1}"
  cat << 'BANNER'
           ▄██▄
          ██▀▀██       ██████╗ ██╗   ██╗███████╗██████╗
         ██ ●  █      ██╔══██╗██║   ██║╚══███╔╝╚════██╗
         █▄ ▿ ▄█      ██████╔╝██║   ██║  ███╔╝  █████╔╝
          █▄▄▄█       ██╔═══╝ ╚██╗ ██╔╝ ███╔╝  ██╔═══╝
         ▄█▓▓▓█▄      ██║      ╚████╔╝ ███████╗███████╗
        ▀▀▀▀▀▀▀▀▀     ╚═╝       ╚═══╝  ╚══════╝╚══════╝
BANNER
  printf "${G3}        Gardendless ${G4}— macOS port by Marcus Nguyen${R}\n"
  printf "${G4}        github.com/Ic0u/pvge_tauri${R}\n\n"
}

info() { printf "${G2}  ▸${R} ${WH}%s${R}\n" "$*"; }
ok()   { printf "${G3}  ✓${R} ${WH}%s${R}\n" "$*"; }
warn() { printf "${YL}  !${R} ${WH}%s${R}\n" "$*"; }
err()  { printf "${RD}  ✗ %s${R}\n" "$*" >&2; exit 1; }
step() { printf "\n${G1}  ══ %s ══${R}\n\n" "$*"; }

banner

# ── Detect OS ─────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin)
    case "$ARCH" in
      x86_64) ASSET_ARCH="x86_64"  ;;
      arm64)  ASSET_ARCH="aarch64" ;;
      *)      err "Unsupported Mac architecture: $ARCH" ;;
    esac
    PLATFORM="macOS"
    ;;
  Linux)
    case "$ARCH" in
      x86_64)  ASSET_ARCH="amd64" ;;
      aarch64) ASSET_ARCH="arm64" ;;
      *)       err "Unsupported Linux architecture: $ARCH" ;;
    esac
    PLATFORM="Linux"
    ;;
  *)
    err "Unsupported OS: $OS. This installer supports macOS and Linux."
    ;;
esac

info "Platform: ${PLATFORM} (${ARCH})"

# ── Fetch latest release ──────────────────────────────────────
step "Resolving latest release"

API="https://api.github.com/repos/${REPO}/releases/latest"
RELEASE_JSON="$(curl -fsSL "$API" 2>/dev/null)" \
  || err "Could not reach GitHub. Check your connection."

VERSION="$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*: "//;s/".*//')"
[[ -n "$VERSION" ]] || err "No releases found at github.com/${REPO}"

info "Latest release: ${VERSION}"

if [[ "$OS" == "Darwin" ]]; then
  ASSET_URL="$(echo "$RELEASE_JSON" \
    | grep '"browser_download_url"' \
    | grep "${ASSET_ARCH}" \
    | grep -i "tar.gz" \
    | head -1 \
    | sed 's/.*: "//;s/".*//')"
else
  ASSET_URL="$(echo "$RELEASE_JSON" \
    | grep '"browser_download_url"' \
    | grep -iE "\.AppImage\"" \
    | grep -i "${ASSET_ARCH}" \
    | head -1 \
    | sed 's/.*: "//;s/".*//')" || true

  if [[ -z "$ASSET_URL" ]]; then
    ASSET_URL="$(echo "$RELEASE_JSON" \
      | grep '"browser_download_url"' \
      | grep -iE "\.deb\"" \
      | grep -i "${ASSET_ARCH}" \
      | head -1 \
      | sed 's/.*: "//;s/".*//')" || true
  fi
fi

[[ -n "$ASSET_URL" ]] || err "No ${PLATFORM} (${ARCH}) build found in ${VERSION}."
ok "Found ${PLATFORM} ${ARCH} build"

# ── Download ──────────────────────────────────────────────────
step "Downloading ${APP_NAME} ${VERSION}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FILENAME="$(basename "$ASSET_URL")"
curl -fSL --progress-bar "$ASSET_URL" -o "${TMP}/${FILENAME}"
echo ""
ok "Download complete"

# ── Install ───────────────────────────────────────────────────
step "Installing"

if [[ "$OS" == "Darwin" ]]; then
  INSTALL_DIR="/Applications"

  if [[ -d "${INSTALL_DIR}/${APP_NAME}.app" ]]; then
    warn "Removing previous installation..."
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
  fi

  info "Extracting to ${INSTALL_DIR}..."
  tar -xzf "${TMP}/${FILENAME}" -C "$INSTALL_DIR"

  info "Clearing Gatekeeper quarantine..."
  sudo xattr -rd com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}.app" 2>/dev/null || {
    warn "Could not remove quarantine automatically."
    warn "Go to System Settings → Privacy & Security → Open Anyway"
  }

  sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
  killall Finder 2>/dev/null || true

  ok "Installed to ${INSTALL_DIR}/${APP_NAME}.app"

else
  if [[ "$FILENAME" == *.AppImage ]]; then
    INSTALL_DIR="${HOME}/.local/bin"
    mkdir -p "$INSTALL_DIR"
    mv "${TMP}/${FILENAME}" "${INSTALL_DIR}/${FILENAME}"
    chmod +x "${INSTALL_DIR}/${FILENAME}"
    ok "Installed to ${INSTALL_DIR}/${FILENAME}"
    info "Make sure ~/.local/bin is in your PATH"
  elif [[ "$FILENAME" == *.deb ]]; then
    info "Installing .deb package..."
    sudo dpkg -i "${TMP}/${FILENAME}" || sudo apt-get install -f -y
    ok "Installed via dpkg"
  fi
fi

# ── Done ──────────────────────────────────────────────────────
printf "\n${G1}"
cat << 'DONE'
  ╔═════════════════════════════════════════╗
  ║                                         ║
  ║        Installation complete!  🌱       ║
  ║                                         ║
  ╚═════════════════════════════════════════╝
DONE
printf "${R}\n"

if [[ "$OS" == "Darwin" ]]; then
  info "Open from Launchpad, Spotlight, or run:"
  printf "\n    ${G4}open \"/Applications/${APP_NAME}.app\"${R}\n"
else
  info "Run from terminal:"
  printf "\n    ${G4}${FILENAME}${R}\n"
fi

printf "\n${G4}  Game by Gaozih & the PvZ2 Gardendless Team${R}\n"
printf "${G4}  macOS port by Marcus Nguyen ❤️${R}\n\n"
