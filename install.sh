#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#   PvZ2 Gardendless — installer / updater / uninstaller for macOS & Linux
#
#     curl -fsSL https://raw.githubusercontent.com/Ic0u/pvge_tauri/main/install.sh | bash
#
#   Runs as an interactive menu when launched from a terminal; falls back to a
#   plain install when piped without a TTY (CI). Environment overrides:
#
#     PVZGE_ACTION=install|update|reinstall|uninstall|build|menu
#     PVZGE_VERSION=v0.8.2      pin a release (default: latest)
#     PVZGE_ARCH=universal      macOS variant: universal | x86_64 | arm64
#     PVZGE_FORCE=1             reinstall even if already up to date
#     PVZGE_NO_LAUNCH=1         don't auto-open after install
#     PVZGE_YES=1               assume defaults, never prompt
#     NO_COLOR=1                disable colored output
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="Ic0u/pvge_tauri"
APP_NAME="PvZ2 Gardendless"
APP_ID="com.pvzge.desktop"
MIN_FREE_MB=2600                       # download (~1G) + extracted app (~1.1G) + slack
MARKER="${HOME}/.local/share/pvzge/version"

# ── PvZ2 green palette ──────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]; then
  R=$'\033[0m';  G1=$'\033[38;5;154m'; G2=$'\033[38;5;76m'
  G3=$'\033[38;5;34m'; G4=$'\033[38;5;28m'; WH=$'\033[1;37m'
  RD=$'\033[1;31m'; YL=$'\033[38;5;220m'; DIM=$'\033[2m'; TTY=1
else
  R=''; G1=''; G2=''; G3=''; G4=''; WH=''; RD=''; YL=''; DIM=''; TTY=0
fi

# ── Output helpers ──────────────────────────────────────────────────────────
info() { printf '%s  ▸%s %s%s%s\n'  "$G2" "$R" "$WH" "$*" "$R"; }
ok()   { printf '%s  ✓%s %s%s%s\n'  "$G3" "$R" "$WH" "$*" "$R"; }
warn() { printf '%s  !%s %s%s%s\n'  "$YL" "$R" "$WH" "$*" "$R"; }
step() { printf '\n%s  ══ %s ══%s\n\n' "$G1" "$*" "$R"; }
die()  { printf '\n%s  ✗ %s%s\n\n' "$RD" "$*" "$R" >&2; exit 1; }

# ── Interactive input (works under `curl | bash` by reading /dev/tty) ────────
INTERACTIVE=0
if [ -z "${PVZGE_YES:-}" ] && [ -r /dev/tty ] && [ -t 1 ]; then INTERACTIVE=1; fi

ask() { # ask "prompt" "default" -> echoes the answer (or default)
  local prompt="$1" def="${2:-}" ans=""
  if [ "$INTERACTIVE" = "1" ]; then
    printf '%s%s%s' "$G2" "$prompt" "$R" > /dev/tty
    IFS= read -r ans < /dev/tty || ans=""
  fi
  printf '%s' "${ans:-$def}"
}

confirm() { # confirm "prompt" "Y|N default" -> 0 if yes
  local def="${2:-N}" ans
  ans="$(ask "$1 " "$def")"
  case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

banner() {
  printf '\n%s' "$G1"
  cat <<'PEA'
⠀⠀⠀⠀⠀⣀⣀⣀⡀⠀⠀⠀⠀⠀⠀⠀⢀⣀⡤⠴⠖⠒⠒⠒⢒⠒⠶⠤⣤⣀
⠀⠀⢀⣴⠻⣉⢏⣽⣿⣗⣦⠀⠀⢀⡶⠞⠋⠅⠐⠀⢀⠐⠠⠈⠄⠌⠠⢡⢀⠊⠝⡲⣄
⠀⢠⡿⣼⣣⣼⣿⣿⣿⣿⢳⣝⡷⢋⠄⠈⢀⠄⠈⡀⠂⠌⠠⣑⣈⣄⠃⠢⢌⢸⡶⣥⣊⠽⣦⡀⠀⠀⣀⣠⣤⣀⡀
⠀⣸⣳⢹⣿⣿⣿⡿⡿⠓⣠⠏⡀⠁⠀⡀⠡⢀⠂⠄⡡⢈⡾⠙⢿⣿⣮⡵⣈⢹⣀⣿⣿⡖⣌⢻⡄⡠⢖⠋⠣⢈⣀⢈⡩⢓⢄
⠀⢻⡬⣿⣿⣿⠟⠁⠀⢰⠃⠌⠀⠀⠌⡀⢁⠂⢌⠂⡅⢂⣧⣀⣸⣿⣿⣿⡠⢍⡝⡿⢿⣉⠖⡬⠋⠔⢉⣴⢚⣭⣬⣧⣽⡣⣍⢷
⠀⠸⣗⣿⡿⠀⠀⠀⠀⡏⠰⠀⠀⠰⢀⠐⠠⠊⢄⢊⠰⣁⠚⢿⣿⣿⣿⢟⡋⢖⡸⣐⢣⡜⡘⢁⠐⡲⢏⣶⣿⣿⣿⣿⣽⣻⣆⠧⡇
⠀⠀⠹⣿⣷⠀⠀⠀⣸⡟⠠⡀⠀⠠⢀⢊⠐⡁⢎⠠⢃⠦⣉⠦⣅⠻⣃⢧⡙⢆⡳⣌⢣⠼⢁⠢⣱⡙⣾⣿⣿⣿⣿⣿⣿⣳⢿⡘⡅
⠀⠀⠀⠀⠀⠀⠀⠀⠸⡇⠀⡈⠄⠄⠌⡄⢊⠰⣈⢌⢣⢒⡡⠲⣌⢣⡓⢦⡙⣎⠶⣡⢏⡒⠌⢆⢧⣹⣿⣿⣿⣿⣿⣿⣿⢯⣿⡐⡇
⠀⠀⠀⠀⠀⠀⠀⠀⠀⣧⠈⣄⠐⡈⠔⣀⢃⠒⡌⠆⢎⢢⡑⠳⣌⢳⡘⣣⢝⣢⢛⡴⢣⢍⡚⡜⣢⢽⣿⣿⣿⣿⣿⣿⣿⣻⠆⣱⠃
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣧⠘⡷⢦⣂⠰⣈⠒⣌⠸⢌⠦⣙⡱⢜⡢⡝⢦⢫⡔⣣⢜⡣⢎⡵⣸⢡⠞⣿⣿⣿⣿⣿⣟⡾⢣⣸⠃
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢘⣧⡈⢳⣭⢻⣴⢡⣦⣃⣮⣜⣤⢳⣡⢳⡙⣎⣵⣘⣦⣋⣶⣩⣽⣇⡞⣜⢲⣙⢻⠙⡞⡁⣔⣷⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣶⣙⠿⣯⣿⡾⣽⢷⢯⣿⣯⢿⢯⣿⣝⣷⣟⣾⣻⣶⡿⠛⠙⠻⣿⣷⣛⣮⣿⣶⠿⠋
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣋⢿⣿⣎⣙⠻⡟⢏⡟⡾⣏⡟⡞⢷⢋⢷⣹⣶⠿⠋
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢿⣿⣿⣿⣾⣶⣾⣴⢬⠮⠽⠖⠛⠋⠉
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣟⡻⠿⣿⠿⠿⠋
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡇⠉⣓⡏⡆
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡀⠀⢧⡏⡅
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠸⡇⠀⡧⣧⠇
⠀⠀⠀⠀⠀⠀⠀⠀⣴⣿⣿⡿⣿⣿⣷⣦⣷⠁⢹⣹⣴⣾⣿⣿⣿⣿⣷
⠀⠀⠀⠀⠀⠀⠀⠀⢼⣿⣯⣿⣿⣾⣟⣿⣿⣇⡊⠵⢿⣿⣳⣿⣾⣟⣿⣇
⠀⠀⠀⠀⠀⠀⠀⢀⡼⢫⢍⣰⣠⢬⠭⢿⣿⣿⣎⡉⡞⢿⣿⣷⡿⠿⠭⡭⣍⣫⢙⡛⣢⣄
⠀⠀⠀⠀⠀⠀⢀⡿⣌⠣⢆⡇⡓⣎⡱⢃⢦⡙⢿⣶⣽⡿⢫⡔⢎⡵⢣⡑⣎⢒⠧⡱⢆⡭⢧
⠀⠀⠀⠀⠀⠀⢸⡳⣌⣛⢦⢳⡹⢤⠳⣍⠶⣙⣾⡟⠹⣷⣧⢚⡵⣊⢧⡹⣌⢏⡞⣱⢋⡖⣻
⠀⠀⠀⠀⠀⠀⠘⢷⡜⡜⣎⠳⣜⢣⡛⣬⢳⣽⠞⠀⠀⠈⠛⠿⣶⣭⣖⣣⢝⠮⡜⣥⠯⠞⠋
PEA
  printf '%s        P v Z 2   G a r d e n l e s s%s\n'   "$G2" "$R"
  printf '%s      macOS / Linux port · Marcus Nguyen%s\n' "$G4" "$R"
  printf '%s      github.com/%s%s\n\n'                  "$DIM" "$REPO" "$R"
}

# ── Spinner (degrades to a plain wait on non-tty) ───────────────────────────
spin() {
  local msg="$1"; shift
  if [ "$TTY" = "0" ]; then "$@"; return $?; fi
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 rc
  "$@" & local pid=$!
  printf '\033[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % ${#frames} ))
    printf '\r%s  %s%s %s%s%s' "$G2" "${frames:$i:1}" "$R" "$WH" "$msg" "$R"
    sleep 0.08
  done
  if wait "$pid"; then rc=0; else rc=$?; fi
  printf '\r\033[K\033[?25h'
  return "$rc"
}

# ── Cleanup: temp dir, mounted DMG, cursor — always runs ────────────────────
TMP=""; MOUNTED_DMG=""
detach_dmg() {
  [ -n "$MOUNTED_DMG" ] && [ -d "$MOUNTED_DMG" ] || { MOUNTED_DMG=""; return 0; }
  hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null \
    || hdiutil detach "$MOUNTED_DMG" -force -quiet 2>/dev/null || true
  MOUNTED_DMG=""
}
cleanup() {
  [ "$TTY" = "1" ] && printf '\033[?25h' 2>/dev/null || true
  detach_dmg
  [ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT
trap 'die "Interrupted."' INT TERM

require() { command -v "$1" >/dev/null 2>&1 || die "Missing required tool: $1"; }

# ── GitHub release helpers ──────────────────────────────────────────────────
json_assets() { printf '%s' "$RELEASE_JSON" | grep -o '"browser_download_url"[^,]*' | sed 's/.*: *"//;s/".*//'; }
pick()        { json_assets | grep -F "$1" | grep -i "${2}\$" | head -1; }

human_size() {
  local name; name="\"$(basename "$1")\""
  printf '%s' "$RELEASE_JSON" | awk -v n="$name" '
    index($0, n) { found = 1 }
    found && /"size":/ { gsub(/[^0-9]/, ""); print; exit }
  ' | awk '{ if ($1 > 1073741824) printf "%.1f GB", $1/1073741824; else printf "%.0f MB", $1/1048576 }'
}

resolve_release() {
  [ -n "${VERSION:-}" ] && return 0
  local api
  if [ -n "${PVZGE_VERSION:-}" ]; then
    api="https://api.github.com/repos/${REPO}/releases/tags/${PVZGE_VERSION}"
  else
    api="https://api.github.com/repos/${REPO}/releases/latest"
  fi
  RELEASE_JSON="$(curl -fsSL --retry 3 --retry-delay 2 "$api" 2>/dev/null)" \
    || die "Could not reach GitHub. Check your connection and try again."
  VERSION="$(printf '%s' "$RELEASE_JSON" | grep '"tag_name"' | head -1 | sed 's/.*: *"//;s/".*//')"
  [ -n "$VERSION" ] || die "No release found (${PVZGE_VERSION:-latest}) at github.com/${REPO}"
}

check_space() {
  local free_mb; free_mb="$(df -Pm "$1" 2>/dev/null | awk 'NR==2 {print $4}')" || free_mb=""
  if [ -n "$free_mb" ] && [ "$free_mb" -lt "$MIN_FREE_MB" ]; then
    warn "Low disk space on $1 (${free_mb}MB free, ~${MIN_FREE_MB}MB recommended)."
  fi
}

# Download with resume + retry (incl. transient TCP resets). Returns non-zero on failure.
download() {
  local url="$1" out="$2"
  step "Downloading  ·  ${VERSION}"
  printf '%s    %s%s  %s(%s)%s\n\n' "$DIM" "$(basename "$url")" "$R" "$DIM" "$(human_size "$url")" "$R"
  curl -fSL --retry 5 --retry-delay 2 --retry-all-errors --retry-connrefused -C - \
       --progress-bar "$url" -o "$out" || return 1
  [ -s "$out" ] || return 1
  echo ""; ok "Download complete"
}

installed_version() {
  if [ "$OS" = "Darwin" ]; then
    defaults read "/Applications/${APP_NAME}.app/Contents/Info" CFBundleShortVersionString 2>/dev/null \
      | sed 's/^/v/' || true
  elif [ -f "$MARKER" ]; then
    cat "$MARKER" 2>/dev/null || true
  fi
}

is_installed() {
  [ "$OS" = "Darwin" ] && [ -d "/Applications/${APP_NAME}.app" ] && return 0
  [ "$OS" = "Linux" ] && { [ -f "$MARKER" ] || [ -x "${HOME}/.local/bin/PvZ2-Gardendless.AppImage" ]; } && return 0
  return 1
}

quit_if_running() {
  pgrep -f "$APP_NAME" >/dev/null 2>&1 || return 0
  info "Closing running instance..."
  osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
  sleep 1
  pkill -f "$APP_NAME.app" 2>/dev/null || true
}

# ═══════════════════════════ INSTALL (macOS) ═══════════════════════════════
# Returns non-zero on recoverable failure so the caller can offer build-from-source.
install_macos() {
  require hdiutil; require ditto; require curl
  local arch="$ARCH"
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ] && arch="arm64"

  local url=""
  case "${PVZGE_ARCH:-auto}" in
    universal) url="$(pick 'macOS-Universal' '.dmg' || true)" ;;
    x86_64)    url="$(pick 'macOS-x86_64' '.dmg' || true)" ;;
    arm64)     url="$(pick 'macOS-Apple-Silicon' '.dmg' || true)" ;;
    *)
      url="$(pick 'macOS-Universal' '.dmg' || true)"
      if [ -z "$url" ]; then
        case "$arch" in
          arm64)  url="$(pick 'macOS-Apple-Silicon' '.dmg' || true)" ;;
          x86_64) url="$(pick 'macOS-x86_64' '.dmg' || true)" ;;
        esac
      fi ;;
  esac
  [ -n "$url" ] || { warn "No macOS build in ${VERSION}."; return 1; }
  ok "Selected $(basename "$url")"

  local dest="/Applications/${APP_NAME}.app"
  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION}" != "reinstall" ] && [ -d "$dest" ]; then
    local cur; cur="$(installed_version)"
    if [ -n "$cur" ] && [ "$cur" = "${VERSION}" ]; then
      ok "Already on the latest version (${cur})"
      DONE_HINT="open -a \"${APP_NAME}\""
      return 0
    fi
    [ -n "$cur" ] && info "Updating  ${cur}  →  ${VERSION}"
  fi

  check_space "/Applications"
  TMP="$(mktemp -d)"
  download "$url" "${TMP}/pvzge.dmg" || { warn "Download failed."; return 1; }

  step "Installing"
  local out
  out="$(hdiutil attach -nobrowse -noverify -noautoopen -readonly "${TMP}/pvzge.dmg" 2>/dev/null)" \
    || { warn "Could not mount disk image."; return 1; }
  MOUNTED_DMG="$(printf '%s' "$out" | grep -Eo '/Volumes/[^[:cntrl:]]*' | tail -1)"
  [ -n "$MOUNTED_DMG" ] && [ -d "$MOUNTED_DMG" ] || { warn "No volume mounted."; return 1; }

  local app_src
  app_src="$(find "$MOUNTED_DMG" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
  [ -n "$app_src" ] || { warn "No .app inside the image."; detach_dmg; return 1; }

  local SUDO=""
  if [ ! -w /Applications ]; then SUDO="sudo"; info "Administrator access needed for /Applications"; sudo -v || { warn "No admin access."; detach_dmg; return 1; }; fi

  quit_if_running
  [ -d "$dest" ] && { info "Removing previous installation..."; $SUDO rm -rf "$dest"; }
  spin "Copying ${APP_NAME} to /Applications" $SUDO ditto "$app_src" "$dest" || { warn "Copy failed."; detach_dmg; return 1; }
  detach_dmg

  [ -d "$dest/Contents/MacOS" ] || { warn "Bundle looks incomplete."; return 1; }
  ok "Installed to ${dest}"

  info "Clearing Gatekeeper quarantine..."
  $SUDO xattr -dr com.apple.quarantine "$dest" 2>/dev/null \
    || warn "Couldn't strip quarantine — right-click ▸ Open if blocked."
  sudo -n rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
  killall Finder Dock 2>/dev/null || true
  DONE_HINT="open -a \"${APP_NAME}\""
}

# ═══════════════════════════ INSTALL (Linux) ═══════════════════════════════
install_linux() {
  require curl
  [ "$ARCH" = "x86_64" ] || { warn "Only x86_64 Linux builds exist (yours: ${ARCH})."; return 1; }

  local appimage deb url kind
  appimage="$(pick 'Linux-x86_64' '.AppImage' || true)"
  deb="$(pick 'Linux-x86_64' '.deb' || true)"
  if [ -n "$deb" ] && command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    url="$deb"; kind="deb"
  elif [ -n "$appimage" ]; then url="$appimage"; kind="appimage"
  elif [ -n "$deb" ];      then url="$deb"; kind="deb"
  else warn "No Linux build in ${VERSION}."; return 1; fi
  ok "Selected $(basename "$url")"

  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION}" != "reinstall" ] \
     && [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "${VERSION}" ]; then
    ok "Already on the latest version (${VERSION})"
    DONE_HINT="PvZ2 Gardendless  (from your application menu)"
    return 0
  fi
  [ -f "$MARKER" ] && info "Updating  $(cat "$MARKER" 2>/dev/null)  →  ${VERSION}"

  TMP="$(mktemp -d)"; check_space "$TMP"
  local file="${TMP}/$(basename "$url")"
  download "$url" "$file" || { warn "Download failed."; return 1; }

  step "Installing"
  if [ "$kind" = "deb" ]; then
    require sudo
    spin "Installing package (dpkg)" sudo dpkg -i "$file" || { info "Resolving dependencies..."; sudo apt-get -y -f install || return 1; }
    ok "Installed via dpkg"
    DONE_HINT="pvzge"; LAUNCH_BIN="$(command -v pvzge 2>/dev/null || echo pvzge)"
  else
    local bindir="${HOME}/.local/bin" apps="${HOME}/.local/share/applications"
    mkdir -p "$bindir" "$apps"
    local target="${bindir}/PvZ2-Gardendless.AppImage"
    mv "$file" "$target"; chmod +x "$target"
    ok "Installed to ${target}"
    cat > "${apps}/${APP_ID}.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Exec=${target}
Icon=pvzge
Categories=Game;
Terminal=false
DESKTOP
    update-desktop-database "$apps" 2>/dev/null || true
    case ":$PATH:" in *":$bindir:"*) : ;; *) warn "Add ~/.local/bin to your PATH to launch by name." ;; esac
    DONE_HINT="$target"; LAUNCH_BIN="$target"
  fi
  mkdir -p "$(dirname "$MARKER")"; printf '%s' "${VERSION}" > "$MARKER" 2>/dev/null || true
}

# ═══════════════════════════ UNINSTALL ═════════════════════════════════════
uninstall() {
  step "Uninstall"
  if ! is_installed; then warn "${APP_NAME} is not installed — nothing to remove."; return 0; fi
  if [ "$INTERACTIVE" = "1" ]; then confirm "Remove ${APP_NAME} and its data?" "N" || { info "Cancelled."; return 0; }; fi

  if [ "$OS" = "Darwin" ]; then
    quit_if_running
    local dest="/Applications/${APP_NAME}.app" SUDO=""
    [ -w /Applications ] || { SUDO="sudo"; sudo -v 2>/dev/null || true; }
    [ -d "$dest" ] && { info "Removing app..."; $SUDO rm -rf "$dest"; }
    info "Removing app data & caches..."
    rm -rf "${HOME}/Library/Application Support/${APP_ID}" \
           "${HOME}/Library/Caches/${APP_ID}" \
           "${HOME}/Library/Saved Application State/${APP_ID}.savedState" \
           "${HOME}/Library/WebKit/${APP_ID}" 2>/dev/null || true
    rm -f "${HOME}/Library/Application Support/${APP_ID}/.seen-"* 2>/dev/null || true
    sudo -n rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
    killall Finder Dock 2>/dev/null || true
  else
    if command -v dpkg >/dev/null 2>&1 && dpkg -s pvzge >/dev/null 2>&1; then
      info "Removing package..."; sudo apt-get -y remove pvzge 2>/dev/null || sudo dpkg -r pvzge || true
    fi
    rm -f "${HOME}/.local/bin/PvZ2-Gardendless.AppImage" \
          "${HOME}/.local/share/applications/${APP_ID}.desktop" 2>/dev/null || true
    update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
    rm -rf "$(dirname "$MARKER")" "${HOME}/.config/${APP_ID}" "${HOME}/.local/share/${APP_ID}" 2>/dev/null || true
  fi
  ok "${APP_NAME} removed."
}

# ═══════════════════════ BUILD FROM SOURCE (backup) ════════════════════════
build_from_source() {
  step "Build from source"
  warn "This clones the full repo (game assets are ~1 GB) and compiles with Tauri."
  if [ "$INTERACTIVE" = "1" ]; then confirm "Continue building from source?" "Y" || { info "Cancelled."; return 1; }; fi

  local missing=()
  command -v git   >/dev/null 2>&1 || missing+=("git")
  command -v cargo >/dev/null 2>&1 || missing+=("rust (cargo)")
  command -v node  >/dev/null 2>&1 || missing+=("node")
  if [ "${#missing[@]}" -gt 0 ]; then
    warn "Missing build tools: ${missing[*]}"
    if [ "$OS" = "Darwin" ]; then
      info "Install with Homebrew, then re-run:"
      printf '      %sbrew install rust node git%s\n' "$DIM" "$R"
    else
      info "Install with apt + rustup, then re-run:"
      printf '      %ssudo apt install -y git nodejs npm build-essential libwebkit2gtk-4.1-dev librsvg2-dev%s\n' "$DIM" "$R"
      printf '      %scurl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh%s\n' "$DIM" "$R"
    fi
    return 1
  fi

  local tauri_cmd=""
  if command -v tauri >/dev/null 2>&1; then tauri_cmd="tauri"
  elif cargo tauri --version >/dev/null 2>&1; then tauri_cmd="cargo tauri"
  else
    info "Installing Tauri CLI..."
    if cargo install tauri-cli --version "^2" >/dev/null 2>&1; then tauri_cmd="cargo tauri"
    elif command -v npm >/dev/null 2>&1 && npm install -g @tauri-apps/cli@2 >/dev/null 2>&1; then tauri_cmd="tauri"
    else warn "Could not install the Tauri CLI."; return 1; fi
  fi

  TMP="${TMP:-$(mktemp -d)}"; local src="${TMP}/pvge_tauri"
  spin "Cloning ${REPO}" git clone --depth 1 "https://github.com/${REPO}.git" "$src" \
    || { warn "Clone failed."; return 1; }
  info "Compiling (this can take several minutes)..."
  ( cd "$src/src-tauri" && $tauri_cmd build --bundles app ) || { warn "Build failed."; return 1; }

  if [ "$OS" = "Darwin" ]; then
    local built; built="$(find "$src/src-tauri/target" -maxdepth 5 -name '*.app' -path '*/release/bundle/macos/*' -print -quit)"
    [ -n "$built" ] || { warn "Built app not found."; return 1; }
    local dest="/Applications/${APP_NAME}.app" SUDO=""
    [ -w /Applications ] || { SUDO="sudo"; sudo -v || return 1; }
    quit_if_running; $SUDO rm -rf "$dest"
    spin "Installing built app" $SUDO ditto "$built" "$dest" || return 1
    $SUDO xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
    ok "Built & installed to ${dest}"; DONE_HINT="open -a \"${APP_NAME}\""
  else
    local appimage; appimage="$(find "$src/src-tauri/target" -name '*.AppImage' -print -quit)"
    [ -n "$appimage" ] || { warn "Built AppImage not found."; return 1; }
    local target="${HOME}/.local/bin/PvZ2-Gardendless.AppImage"; mkdir -p "$(dirname "$target")"
    cp "$appimage" "$target"; chmod +x "$target"
    ok "Built & installed to ${target}"; DONE_HINT="$target"; LAUNCH_BIN="$target"
  fi
}

# ── Run an install, and on failure offer the build-from-source backup plan ──
install_with_fallback() {
  local fn="install_${1}"
  if "$fn"; then return 0; fi
  warn "The download/install method didn't succeed."
  if [ "$INTERACTIVE" = "1" ]; then
    if confirm "Try building from source instead?" "Y"; then build_from_source && return 0; fi
    die "Installation did not complete."
  else
    die "Installation failed. Re-run interactively to try building from source."
  fi
}

show_help() {
  step "Help"
  cat <<HELP
  ${APP_NAME} — desktop port of PvZ2 Gardendless (Tauri + WebKit).

  ${WH}Menu options${R}
    Install / Update    Download the latest release and install it
    Reinstall           Force a clean re-download even if up to date
    Uninstall           Remove the app, its data, caches and launchers
    Build from source   Backup plan — clone the repo and compile locally
    Help                This screen
    Quit                Exit

  ${WH}One-liner${R}
    curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash

  ${WH}Non-interactive / scripting${R}
    PVZGE_ACTION=install|update|reinstall|uninstall|build
    PVZGE_VERSION=v0.8.2     pin a release          PVZGE_FORCE=1     reinstall anyway
    PVZGE_ARCH=universal     macOS variant          PVZGE_NO_LAUNCH=1 don't auto-open
    PVZGE_YES=1              assume defaults         NO_COLOR=1        no colors

  ${WH}Locations${R}
    macOS   /Applications/${APP_NAME}.app
    Linux   ~/.local/bin/PvZ2-Gardendless.AppImage  (or apt package 'pvzge')

  Game by Gaozih & the PvZ2 Gardendless Team · port by Marcus Nguyen
  Releases:  github.com/${REPO}/releases
HELP
  echo ""
}

finish() {
  printf '\n%s' "$G1"
  cat <<'DONE'
   ╔══════════════════════════════════════════════╗
   ║          🌱  Installed & ready!  🧟           ║
   ╚══════════════════════════════════════════════╝
DONE
  printf '%s\n' "$R"
  info "Relaunch any time with:"
  printf '\n      %s%s%s\n\n' "$G2" "${DONE_HINT:-}" "$R"
  printf '%s  Game by Gaozih & the PvZ2 Gardendless Team%s\n' "$DIM" "$R"
  printf '%s  %s port by Marcus Nguyen ❤️%s\n\n' "$DIM" "${PLATFORM:-}" "$R"
}

launch_app() {
  [ -n "${PVZGE_NO_LAUNCH:-}" ] && return 0
  info "Opening ${APP_NAME}..."
  if [ "$OS" = "Darwin" ]; then
    open -a "${APP_NAME}" 2>/dev/null || open "/Applications/${APP_NAME}.app" 2>/dev/null || true
  elif [ -n "${LAUNCH_BIN:-}" ]; then
    ( setsid "${LAUNCH_BIN}" >/dev/null 2>&1 & ) 2>/dev/null || ( "${LAUNCH_BIN}" >/dev/null 2>&1 & ) 2>/dev/null || true
  fi
}

# ── Interactive menu (only when a TTY is available) ─────────────────────────
menu() {
  local cur; cur="$(installed_version)"
  if [ -n "$cur" ]; then
    printf '%s  Installed:%s %s%s%s   %s·%s   %sLatest:%s %s%s%s\n\n' \
      "$DIM" "$R" "$G3" "$cur" "$R" "$DIM" "$R" "$DIM" "$R" "$G1" "${VERSION:-?}" "$R"
  else
    printf '%s  Not installed%s   %s·%s   %sLatest:%s %s%s%s\n\n' \
      "$YL" "$R" "$DIM" "$R" "$DIM" "$R" "$G1" "${VERSION:-?}" "$R"
  fi
  local one="Install"; [ -n "$cur" ] && one="Update"
  printf '   %s[1]%s %s\n'  "$G1" "$R" "$one"
  printf '   %s[2]%s Reinstall (force re-download)\n' "$G1" "$R"
  printf '   %s[3]%s Uninstall\n' "$G1" "$R"
  printf '   %s[4]%s Build from source\n' "$G1" "$R"
  printf '   %s[5]%s Help\n' "$G1" "$R"
  printf '   %s[6]%s Quit\n\n' "$G1" "$R"
  local c; c="$(ask "  Choose [1]: " "1")"
  case "$c" in
    1) ACTION="update" ;;
    2) ACTION="reinstall"; PVZGE_FORCE=1 ;;
    3) ACTION="uninstall" ;;
    4) ACTION="build" ;;
    5) show_help; menu; return ;;
    6|q|Q) info "Bye!"; exit 0 ;;
    *) warn "Unknown choice — defaulting to ${one}."; ACTION="update" ;;
  esac
}

# ── main ────────────────────────────────────────────────────────────────────
main() {
  require uname; require curl; require grep; require sed; require awk
  banner

  OS="$(uname -s)"; ARCH="$(uname -m)"
  case "$OS" in
    Darwin) PLATFORM="macOS" ;;
    Linux)  PLATFORM="Linux" ;;
    *)      die "Unsupported OS: $OS (macOS and Linux only)." ;;
  esac
  info "Detected ${PLATFORM} · ${ARCH}"

  ACTION="${PVZGE_ACTION:-}"

  # Resolve the latest release up front (needed for menu/version compare).
  # Uninstall doesn't need the network.
  if [ "$ACTION" != "uninstall" ]; then
    step "Resolving release"; resolve_release; info "Release: ${VERSION}"
  fi

  # No explicit action? Show the menu when interactive, else default to update/install.
  if [ -z "$ACTION" ]; then
    if [ "$INTERACTIVE" = "1" ]; then
      step "Menu"; menu
    else
      ACTION="update"
    fi
  fi

  case "$ACTION" in
    uninstall) uninstall ;;
    build)     build_from_source && { finish; launch_app; } ;;
    install|update|reinstall|*)
      if [ "$OS" = "Darwin" ]; then install_with_fallback macos; else install_with_fallback linux; fi
      finish; launch_app ;;
  esac
}

main "$@"
