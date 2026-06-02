#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
#   PvZ2 Gardendless — one-line installer for macOS & Linux
#
#     curl -fsSL https://raw.githubusercontent.com/Ic0u/pvge_tauri/main/install.sh | bash
#
#   Env overrides:
#     PVZGE_VERSION=v0.8.2   pin a specific release (default: latest)
#     PVZGE_ARCH=universal   force a macOS variant: universal | x86_64 | arm64
#     NO_COLOR=1             disable colored output
# ──────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────────────
REPO="Ic0u/pvge_tauri"
APP_NAME="PvZ2 Gardendless"
APP_ID="com.pvzge.desktop"
MIN_FREE_MB=2600                      # download (~1G) + extracted app (~1.1G) + slack

# ── PvZ2 green palette (256-color) ─────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]; then
  R=$'\033[0m';  G1=$'\033[38;5;154m'; G2=$'\033[38;5;76m'
  G3=$'\033[38;5;34m'; G4=$'\033[38;5;28m'; WH=$'\033[1;37m'
  RD=$'\033[1;31m'; YL=$'\033[38;5;220m'; DIM=$'\033[2m'
  TTY=1
else
  R=''; G1=''; G2=''; G3=''; G4=''; WH=''; RD=''; YL=''; DIM=''
  TTY=0
fi

# ── Output helpers ─────────────────────────────────────────────────────────
info() { printf '%s  ▸%s %s%s%s\n'  "$G2" "$R" "$WH" "$*" "$R"; }
ok()   { printf '%s  ✓%s %s%s%s\n'  "$G3" "$R" "$WH" "$*" "$R"; }
warn() { printf '%s  !%s %s%s%s\n'  "$YL" "$R" "$WH" "$*" "$R"; }
step() { printf '\n%s  ══ %s ══%s\n\n' "$G1" "$*" "$R"; }
die()  { printf '\n%s  ✗ %s%s\n\n' "$RD" "$*" "$R" >&2; exit 1; }

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

# ── Spinner (wraps a slow command; degrades to plain wait on non-tty) ───────
spin() {
  local msg="$1"; shift
  if [ "$TTY" = "0" ]; then
    "$@"; return $?
  fi
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 rc
  "$@" &
  local pid=$!
  printf '\033[?25l'                                   # hide cursor
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % ${#frames} ))
    printf '\r%s  %s%s %s%s%s' "$G2" "${frames:$i:1}" "$R" "$WH" "$msg" "$R"
    sleep 0.08
  done
  if wait "$pid"; then rc=0; else rc=$?; fi
  printf '\r\033[K\033[?25h'                           # clear line, show cursor
  return "$rc"
}

# ── Cleanup: always runs (temp dir, mounted DMG, cursor) ────────────────────
TMP=""; MOUNTED_DMG=""
cleanup() {
  [ "$TTY" = "1" ] && printf '\033[?25h' 2>/dev/null || true
  if [ -n "$MOUNTED_DMG" ] && [ -d "$MOUNTED_DMG" ]; then
    hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null \
      || hdiutil detach "$MOUNTED_DMG" -force -quiet 2>/dev/null || true
  fi
  [ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT
trap 'die "Interrupted."' INT TERM

# ── Preflight: required tools ───────────────────────────────────────────────
require() { command -v "$1" >/dev/null 2>&1 || die "Missing required tool: $1"; }

# ── Resolve the right release asset URL from the GitHub API ─────────────────
json_assets() { printf '%s' "$RELEASE_JSON" | grep -o '"browser_download_url"[^,]*' | sed 's/.*: *"//;s/".*//'; }
pick()        { json_assets | grep -F "$1" | grep -i "${2}\$" | head -1; }

resolve_release() {
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

# ── Disk-space guard ────────────────────────────────────────────────────────
check_space() {
  local target="$1" free_mb
  free_mb="$(df -Pm "$target" 2>/dev/null | awk 'NR==2 {print $4}')" || free_mb=""
  if [ -n "$free_mb" ] && [ "$free_mb" -lt "$MIN_FREE_MB" ]; then
    die "Not enough free space on $target (${free_mb}MB free, need ~${MIN_FREE_MB}MB)."
  fi
}

# ── Download with resume + retry, then sanity-check the file ────────────────
download() {
  local url="$1" out="$2" name
  name="$(basename "$url")"
  step "Downloading  ·  ${VERSION}"
  printf '%s    %s%s  %s(%s)%s\n\n' "$DIM" "$name" "$R" "$DIM" "$(human_size "$url")" "$R"
  # --retry-all-errors so transient TCP resets (curl error 56) auto-retry;
  # -C - resumes the partial file across those retries.
  curl -fSL --retry 5 --retry-delay 2 --retry-all-errors --retry-connrefused -C - \
       --progress-bar "$url" -o "$out" \
    || die "Download failed after multiple attempts. Re-run the installer to try again."
  [ -s "$out" ] || die "Downloaded file is empty."
  echo ""
  ok "Download complete"
}

human_size() {
  local name; name="\"$(basename "$1")\""
  printf '%s' "$RELEASE_JSON" | awk -v n="$name" '
    index($0, n) { found = 1 }
    found && /"size":/ { gsub(/[^0-9]/, ""); print; exit }
  ' | awk '{ if ($1 > 1073741824) printf "%.1f GB", $1/1073741824; else printf "%.0f MB", $1/1048576 }'
}

# ── Quit a running instance so we can replace it cleanly ────────────────────
quit_if_running() {
  if pgrep -f "$APP_NAME" >/dev/null 2>&1; then
    info "Closing running instance..."
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
    sleep 1
    pkill -f "$APP_NAME.app" 2>/dev/null || true
  fi
}

# ═══════════════════════════ macOS install ═════════════════════════════════
install_macos() {
  require hdiutil; require ditto; require curl

  # Rosetta-aware arch detection
  local arch="$ARCH"
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ] && arch="arm64"

  # Universal first (runs on everything, dodges Rosetta edge cases), then native.
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
      fi
      ;;
  esac
  [ -n "$url" ] || die "No macOS build found in ${VERSION}."
  ok "Selected $(basename "$url")"

  # Auto-update: skip if the installed version already matches latest
  local dest="/Applications/${APP_NAME}.app"
  if [ -z "${PVZGE_FORCE:-}" ] && [ -d "$dest" ]; then
    local cur
    cur="$(defaults read "${dest}/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
    if [ -n "$cur" ] && [ "v${cur}" = "${VERSION}" ]; then
      ok "Already on the latest version (v${cur})"
      info "Set PVZGE_FORCE=1 to reinstall anyway."
      DONE_HINT="open -a \"${APP_NAME}\""
      return 0
    fi
    [ -n "$cur" ] && info "Updating  v${cur}  →  ${VERSION}"
  fi

  check_space "/Applications"

  TMP="$(mktemp -d)"
  local dmg="${TMP}/pvzge.dmg"
  download "$url" "$dmg"

  step "Installing"

  # Mount read-only, no GUI, no autoplay
  local out
  out="$(hdiutil attach -nobrowse -noverify -noautoopen -readonly "$dmg" 2>/dev/null)" \
    || die "Could not mount disk image (download may be corrupt — re-run to retry)."
  MOUNTED_DMG="$(printf '%s' "$out" | grep -Eo '/Volumes/[^[:cntrl:]]*' | tail -1)"
  [ -n "$MOUNTED_DMG" ] && [ -d "$MOUNTED_DMG" ] || die "Mounted image but found no volume."

  local app_src
  app_src="$(find "$MOUNTED_DMG" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
  [ -n "$app_src" ] || die "No .app inside the disk image."

  # Privilege only if /Applications isn't writable by us
  local SUDO=""
  if [ ! -w /Applications ]; then
    SUDO="sudo"
    info "Administrator access needed to write to /Applications"
    sudo -v || die "Could not obtain administrator access."
  fi

  quit_if_running
  if [ -d "$dest" ]; then
    info "Removing previous installation..."
    $SUDO rm -rf "$dest"
  fi

  spin "Copying ${APP_NAME} to /Applications" $SUDO ditto "$app_src" "$dest" \
    || die "Copy failed."

  hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null || true
  MOUNTED_DMG=""

  [ -d "$dest/Contents/MacOS" ] || die "Install verification failed — bundle looks incomplete."
  ok "Installed to ${dest}"

  # Bypass Gatekeeper for the unsigned bundle
  info "Clearing Gatekeeper quarantine..."
  $SUDO xattr -dr com.apple.quarantine "$dest" 2>/dev/null \
    || warn "Could not strip quarantine — if blocked: right-click ▸ Open, or System Settings ▸ Privacy & Security ▸ Open Anyway"

  # Refresh icon cache (best-effort, never blocks on a password)
  sudo -n rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
  killall Finder Dock 2>/dev/null || true

  DONE_HINT="open -a \"${APP_NAME}\""
}

# ═══════════════════════════ Linux install ═════════════════════════════════
install_linux() {
  require curl
  [ "$ARCH" = "x86_64" ] || die "Only x86_64 Linux builds are available (yours: ${ARCH})."

  local appimage deb url kind
  appimage="$(pick 'Linux-x86_64' '.AppImage' || true)"
  deb="$(pick 'Linux-x86_64' '.deb' || true)"

  # Prefer .deb on Debian/Ubuntu (desktop entry + menu integration), else AppImage
  if [ -n "$deb" ] && command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    url="$deb"; kind="deb"
  elif [ -n "$appimage" ]; then
    url="$appimage"; kind="appimage"
  elif [ -n "$deb" ]; then
    url="$deb"; kind="deb"
  else
    die "No Linux build found in ${VERSION}."
  fi
  ok "Selected $(basename "$url")"

  # Auto-update: skip if already on latest (tracked via version marker)
  local marker="${HOME}/.local/share/pvzge/version"
  if [ -z "${PVZGE_FORCE:-}" ] && [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "${VERSION}" ]; then
    ok "Already on the latest version (${VERSION})"
    info "Set PVZGE_FORCE=1 to reinstall anyway."
    DONE_HINT="PvZ2 Gardendless  (from your application menu)"
    return 0
  fi
  [ -f "$marker" ] && info "Updating  $(cat "$marker" 2>/dev/null)  →  ${VERSION}"

  TMP="$(mktemp -d)"
  check_space "$TMP"
  local file="${TMP}/$(basename "$url")"
  download "$url" "$file"

  step "Installing"
  if [ "$kind" = "deb" ]; then
    require sudo
    spin "Installing package (dpkg)" sudo dpkg -i "$file" \
      || { info "Resolving dependencies..."; sudo apt-get -y -f install; }
    ok "Installed via dpkg"
    DONE_HINT="pvzge   # or launch 'PvZ2 Gardendless' from your app menu"
    LAUNCH_BIN="$(command -v pvzge 2>/dev/null || echo pvzge)"
  else
    local bindir="${HOME}/.local/bin"
    local apps="${HOME}/.local/share/applications"
    mkdir -p "$bindir" "$apps"
    local target="${bindir}/PvZ2-Gardendless.AppImage"
    mv "$file" "$target"
    chmod +x "$target"
    ok "Installed to ${target}"

    # Desktop entry so it shows up in the launcher
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

    case ":$PATH:" in
      *":$bindir:"*) : ;;
      *) warn "Add ~/.local/bin to your PATH to launch by name." ;;
    esac
    DONE_HINT="$target"
    LAUNCH_BIN="$target"
  fi

  # Record installed version for future update checks
  mkdir -p "$(dirname "$marker")"
  printf '%s' "${VERSION}" > "$marker" 2>/dev/null || true
}

# ── Final flourish ──────────────────────────────────────────────────────────
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
  printf '%s  %s port by Marcus Nguyen ❤️%s\n\n' "$DIM" "$PLATFORM" "$R"
}

# Auto-open the game once it's installed (set PVZGE_NO_LAUNCH=1 to skip).
launch_app() {
  [ -n "${PVZGE_NO_LAUNCH:-}" ] && return 0
  info "Opening ${APP_NAME}..."
  if [ "$OS" = "Darwin" ]; then
    open -a "${APP_NAME}" 2>/dev/null \
      || open "/Applications/${APP_NAME}.app" 2>/dev/null || true
  elif [ -n "${LAUNCH_BIN:-}" ]; then
    ( setsid "${LAUNCH_BIN}" >/dev/null 2>&1 & ) 2>/dev/null \
      || ( "${LAUNCH_BIN}" >/dev/null 2>&1 & ) 2>/dev/null || true
  fi
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

  step "Resolving release"
  resolve_release
  info "Release: ${VERSION}"

  if [ "$OS" = "Darwin" ]; then install_macos; else install_linux; fi
  finish
  launch_app
}

main "$@"
