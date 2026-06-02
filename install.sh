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
MIN_FREE_MB=2600
MARKER="${HOME}/.local/share/pvzge/version"

# ── PvZ2 green palette (256-color with graceful fallback) ────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]; then
  R=$'\033[0m';  G1=$'\033[38;5;154m'; G2=$'\033[38;5;76m'
  G3=$'\033[38;5;34m'; G4=$'\033[38;5;28m'; WH=$'\033[1;37m'
  RD=$'\033[1;31m'; YL=$'\033[38;5;220m'; DIM=$'\033[2m'
  OG=$'\033[38;5;208m'; GY=$'\033[38;5;245m'
  Y2=$'\033[38;5;214m'; Y3=$'\033[38;5;208m'
  BD=$'\033[1m'; UL=$'\033[4m'
  # Box-drawing border color
  BX=$'\033[38;5;240m'
  TTY=1
else
  R=''; G1=''; G2=''; G3=''; G4=''; WH=''; RD=''; YL=''; DIM=''
  OG=''; GY=''; Y2=''; Y3=''; BD=''; UL=''; BX=''; TTY=0
fi

# ── TUI primitives ──────────────────────────────────────────────────────
ln()    { printf '%s' "$R"; }                          # reset inline
nl()    { echo ""; }
pad()   { printf '  '; }                               # left gutter
line()  { pad; printf '%s%s%s\n' "$BX" "$1" "$R"; }   # draw a full-width box line
divider() {
  pad; printf '%s──────────────────────────────────────────%s\n' "$BX" "$R"
}

info() { pad; printf '%s▸%s %s%s%s\n'   "$G2" "$R" "$WH" "$*" "$R"; }
ok()   { pad; printf '%s✓%s %s%s%s\n'   "$G3" "$R" "$WH" "$*" "$R"; }
warn() { pad; printf '%s!%s %s%s%s\n'   "$YL" "$R" "$WH" "$*" "$R"; }
hint() { pad; printf '%s%s%s\n'          "$DIM" "$*" "$R"; }
die()  { nl; pad; printf '%s✗ %s%s\n\n' "$RD" "$*" "$R" >&2; exit 1; }
step() { nl; pad; printf '%s━━ %s%s %s━━%s\n\n' "$G1" "$WH" "$*" "$G1" "$R"; }

# ── Interactive input (reads /dev/tty so curl|bash works) ────────────────
INTERACTIVE=0
if [ -z "${PVZGE_YES:-}" ] && [ -r /dev/tty ] && [ -t 1 ]; then INTERACTIVE=1; fi

ask() {
  local prompt="$1" def="${2:-}" ans=""
  if [ "$INTERACTIVE" = "1" ]; then
    printf '%s%s%s' "$G2" "$prompt" "$R" > /dev/tty
    IFS= read -r ans < /dev/tty || ans=""
  fi
  printf '%s' "${ans:-$def}"
}

confirm() {
  local def="${2:-N}" ans
  ans="$(ask "$1 " "$def")"
  case "$ans" in [yY]*) return 0 ;; *) return 1 ;; esac
}

# ── Banner (peashooter + colored game title) ─────────────────────────────
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
  printf '%s%s' "$R" "$BD"
  printf '%s█████▄ ▄▄     ▄▄▄  ▄▄  ▄▄ ▄▄▄▄▄▄%s ' "$G1" "$R"
  printf '%s%s▄▄▄▄   ▄▄ ▄▄  ▄▄▄▄%s    '           "$BD" "$YL" "$R"
  printf '%s██████  ▄▄▄  ▄▄   ▄▄ ▄▄▄▄  ▄▄ ▄▄▄▄▄  ▄▄▄▄%s   '  "$GY" "$R"
  printf '%s████▄%s\n'                               "$OG" "$R"
  printf '%s██▄▄█▀ ██    ██▀██ ███▄██   ██  ███▄▄%s ' "$G1" "$R"
  printf '%s%s██▄██ ███▄▄%s      '                     "$BD" "$YL" "$R"
  printf '%s▄▄▀▀  ██▀██ ██▀▄▀██ ██▄██ ██ ██▄▄  ███▄▄%s    '  "$GY" "$R"
  printf '%s▄██▀%s\n'                                 "$OG" "$R"
  printf '%s██     ██▄▄▄ ██▀██ ██ ▀██   ██  ▄▄██▀%s ' "$G1" "$R"
  printf '%s%s ▀█▀  ▄▄██▀ ▄%s   '                      "$BD" "$YL" "$R"
  printf '%s██████ ▀███▀ ██   ██ ██▄█▀ ██ ██▄▄▄ ▄▄██▀%s   '  "$GY" "$R"
  printf '%s███▄▄%s\n'                                "$OG" "$R"
  nl
  printf '           %s▄████   ▄▄▄  ▄▄▄▄%s'          "$YL" "$R"
  printf '%s  ▄▄▄▄  ▄▄▄▄▄%s'                         "$Y2" "$R"
  printf '%s ▄▄  ▄▄ ▄▄    ▄▄▄▄▄  ▄▄▄▄  ▄▄▄▄%s\n'   "$Y3" "$R"
  printf '          %s██  ▄▄▄ ██▀██ ██▄█▄%s'         "$YL" "$R"
  printf '%s ██▀██ ██▄▄%s'                             "$Y2" "$R"
  printf '%s  ███▄██ ██    ██▄▄  ███▄▄ ███▄▄%s\n'    "$Y3" "$R"
  printf '           %s▀███▀  ██▀██ ██ ██%s'          "$YL" "$R"
  printf '%s ████▀ ██▄▄▄%s'                            "$Y2" "$R"
  printf '%s ██ ▀██ ██▄▄▄ ██▄▄▄ ▄▄██▀ ▄▄██▀%s\n'    "$Y3" "$R"
  nl
}

# ── System info card (shown after banner) ────────────────────────────────
sysinfo() {
  local cur; cur="$(installed_version)"
  local free_mb; free_mb="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}')" || free_mb="?"
  local free_h
  if [ "$free_mb" != "?" ] && [ "$free_mb" -ge 1024 ] 2>/dev/null; then
    free_h="$(awk "BEGIN{printf \"%.1f GB\", $free_mb/1024}")"
  else
    free_h="${free_mb} MB"
  fi

  line "╭──────────────────────────────────────────╮"
  pad; printf '%s│%s  %sSystem%s %-34s%s│%s\n'      "$BX" "$R" "$BD$WH" "$R" "" "$BX" "$R"
  line "│                                          │"
  pad; printf '%s│%s  %sOS         %s%-29s %s│%s\n' "$BX" "$R" "$DIM" "$WH" "${PLATFORM} (${ARCH})" "$BX" "$R"
  if [ -n "$cur" ]; then
    pad; printf '%s│%s  %sInstalled  %s%-29s %s│%s\n' "$BX" "$R" "$DIM" "$G3" "$cur" "$BX" "$R"
  else
    pad; printf '%s│%s  %sInstalled  %s%-29s %s│%s\n' "$BX" "$R" "$DIM" "$YL" "not found" "$BX" "$R"
  fi
  pad; printf '%s│%s  %sLatest     %s%-29s %s│%s\n' "$BX" "$R" "$DIM" "$G1" "${VERSION:-…}" "$BX" "$R"
  pad; printf '%s│%s  %sDisk free  %s%-29s %s│%s\n' "$BX" "$R" "$DIM" "$WH" "$free_h" "$BX" "$R"
  line "│                                          │"
  line "╰──────────────────────────────────────────╯"
  nl
}

# ── Spinner ──────────────────────────────────────────────────────────────
spin() {
  local msg="$1"; shift
  if [ "$TTY" = "0" ]; then "$@"; return $?; fi
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 rc
  "$@" & local pid=$!
  printf '\033[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % ${#frames} ))
    printf '\r  %s%s%s %s%s%s' "$G2" "${frames:$i:1}" "$R" "$WH" "$msg" "$R"
    sleep 0.08
  done
  if wait "$pid"; then rc=0; else rc=$?; fi
  printf '\r\033[K\033[?25h'
  return "$rc"
}

# ── Cleanup trap ─────────────────────────────────────────────────────────
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

# ── GitHub release helpers ───────────────────────────────────────────────
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
    warn "Low disk space on $1 (${free_mb}MB free, ~${MIN_FREE_MB}MB needed)."
    if [ "$INTERACTIVE" = "1" ]; then
      confirm "  Continue anyway? [y/N]" "N" || die "Aborted — free up disk space and re-run."
    fi
  fi
}

download() {
  local url="$1" out="$2" sz
  sz="$(human_size "$url")"
  step "Downloading"
  nl
  line "╭──────────────────────────────────────────╮"
  pad; printf '%s│%s  %sFile%s   %-34s%s│%s\n'     "$BX" "$R" "$DIM" "$WH" "$(basename "$url")" "$BX" "$R"
  pad; printf '%s│%s  %sSize%s   %-34s%s│%s\n'     "$BX" "$R" "$DIM" "$WH" "$sz" "$BX" "$R"
  pad; printf '%s│%s  %sFrom%s   %-34s%s│%s\n'     "$BX" "$R" "$DIM" "$DIM" "GitHub Releases" "$BX" "$R"
  line "╰──────────────────────────────────────────╯"
  nl
  curl -fSL --retry 5 --retry-delay 2 --retry-all-errors --retry-connrefused -C - \
       --progress-bar "$url" -o "$out" || return 1
  [ -s "$out" ] || return 1
  nl; ok "Download complete"
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
  sleep 1; pkill -f "$APP_NAME.app" 2>/dev/null || true
}

# ═══════════════════════════ INSTALL macOS ════════════════════════════════
install_macos() {
  require hdiutil; require ditto; require curl
  local arch="$ARCH"
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = "1" ] && arch="arm64"

  step "Resolving build"
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
  [ -n "$url" ] || { warn "No macOS build found in ${VERSION}."; return 1; }
  ok "$(basename "$url")"

  local dest="/Applications/${APP_NAME}.app"
  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION}" != "reinstall" ] && [ -d "$dest" ]; then
    local cur; cur="$(installed_version)"
    if [ -n "$cur" ] && [ "$cur" = "${VERSION}" ]; then
      nl; ok "You're already on the latest version (${cur})."
      hint "  Run with PVZGE_FORCE=1 or choose Reinstall to re-download."
      DONE_HINT="open -a \"${APP_NAME}\""; return 0
    fi
    [ -n "$cur" ] && info "Updating  ${cur}  →  ${VERSION}"
  fi

  check_space "/Applications"
  TMP="$(mktemp -d)"
  download "$url" "${TMP}/pvzge.dmg" || { warn "Download failed."; return 1; }

  step "Installing"
  info "Mounting disk image..."
  local out
  out="$(hdiutil attach -nobrowse -noverify -noautoopen -readonly "${TMP}/pvzge.dmg" 2>/dev/null)" \
    || { warn "Could not mount disk image (corrupt download?)."; return 1; }
  MOUNTED_DMG="$(printf '%s' "$out" | grep -Eo '/Volumes/[^[:cntrl:]]*' | tail -1)"
  [ -n "$MOUNTED_DMG" ] && [ -d "$MOUNTED_DMG" ] || { warn "No volume found."; return 1; }
  ok "Mounted"

  local app_src
  app_src="$(find "$MOUNTED_DMG" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
  [ -n "$app_src" ] || { warn "No .app inside the image."; detach_dmg; return 1; }

  local SUDO=""
  if [ ! -w /Applications ]; then
    SUDO="sudo"
    info "Administrator access needed for /Applications"
    sudo -v || { warn "Could not get admin access."; detach_dmg; return 1; }
  fi

  quit_if_running
  [ -d "$dest" ] && { info "Removing previous version..."; $SUDO rm -rf "$dest"; }
  spin "Copying to /Applications" $SUDO ditto "$app_src" "$dest" || { warn "Copy failed."; detach_dmg; return 1; }
  ok "App installed"
  detach_dmg

  [ -d "$dest/Contents/MacOS" ] || { warn "Bundle looks incomplete."; return 1; }

  info "Bypassing Gatekeeper..."
  $SUDO xattr -dr com.apple.quarantine "$dest" 2>/dev/null \
    || warn "Couldn't strip quarantine. Right-click the app ▸ Open to bypass."
  ok "Quarantine cleared"
  sudo -n rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
  killall Finder Dock 2>/dev/null || true

  info "Cleaning up temporary files..."
  rm -rf "$TMP" 2>/dev/null || true; TMP=""
  ok "Done"

  DONE_HINT="open -a \"${APP_NAME}\""
}

# ═══════════════════════════ INSTALL Linux ════════════════════════════════
install_linux() {
  require curl
  [ "$ARCH" = "x86_64" ] || { warn "Only x86_64 Linux builds are available (yours: ${ARCH})."; return 1; }

  step "Resolving build"
  local appimage deb url kind
  appimage="$(pick 'Linux-x86_64' '.AppImage' || true)"
  deb="$(pick 'Linux-x86_64' '.deb' || true)"
  if [ -n "$deb" ] && command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    url="$deb"; kind="deb"
  elif [ -n "$appimage" ]; then url="$appimage"; kind="appimage"
  elif [ -n "$deb" ];      then url="$deb"; kind="deb"
  else warn "No Linux build in ${VERSION}."; return 1; fi
  ok "$(basename "$url")"

  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION}" != "reinstall" ] \
     && [ -f "$MARKER" ] && [ "$(cat "$MARKER" 2>/dev/null)" = "${VERSION}" ]; then
    nl; ok "You're already on the latest version (${VERSION})."
    hint "  Run with PVZGE_FORCE=1 or choose Reinstall to re-download."
    DONE_HINT="${APP_NAME}  (from your app menu)"; return 0
  fi
  [ -f "$MARKER" ] && info "Updating  $(cat "$MARKER" 2>/dev/null)  →  ${VERSION}"

  TMP="$(mktemp -d)"; check_space "$TMP"
  local file="${TMP}/$(basename "$url")"
  download "$url" "$file" || { warn "Download failed."; return 1; }

  step "Installing"
  if [ "$kind" = "deb" ]; then
    require sudo
    spin "Installing package" sudo dpkg -i "$file" \
      || { info "Resolving dependencies..."; sudo apt-get -y -f install || return 1; }
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

  info "Cleaning up temporary files..."
  rm -rf "$TMP" 2>/dev/null || true; TMP=""
  ok "Done"
  mkdir -p "$(dirname "$MARKER")"; printf '%s' "${VERSION}" > "$MARKER" 2>/dev/null || true
}

# ═══════════════════════════ UNINSTALL ════════════════════════════════════
uninstall() {
  step "Uninstall"
  if ! is_installed; then
    warn "${APP_NAME} doesn't seem to be installed."
    hint "  Nothing to remove."; return 0
  fi

  local cur; cur="$(installed_version)"
  nl
  line "╭──────────────────────────────────────────╮"
  pad; printf '%s│%s  %sThis will remove:%s                        %s│%s\n' "$BX" "$R" "$RD" "$R" "$BX" "$R"
  pad; printf '%s│%s    %-39s%s│%s\n' "$BX" "$R" "• ${APP_NAME} app ${cur}" "$BX" "$R"
  pad; printf '%s│%s    %-39s%s│%s\n' "$BX" "$R" "• App data, caches & preferences" "$BX" "$R"
  if [ "$OS" = "Linux" ]; then
    pad; printf '%s│%s    %-39s%s│%s\n' "$BX" "$R" "• Desktop launcher entry" "$BX" "$R"
  fi
  line "╰──────────────────────────────────────────╯"
  nl
  if [ "$INTERACTIVE" = "1" ]; then
    confirm "  Are you sure? [y/N]" "N" || { info "Cancelled."; return 0; }
  fi
  nl

  if [ "$OS" = "Darwin" ]; then
    quit_if_running
    local dest="/Applications/${APP_NAME}.app" SUDO=""
    [ -w /Applications ] || { SUDO="sudo"; sudo -v 2>/dev/null || true; }
    [ -d "$dest" ] && { info "Removing app..."; $SUDO rm -rf "$dest"; ok "App removed"; }
    info "Removing app data & caches..."
    rm -rf "${HOME}/Library/Application Support/${APP_ID}" \
           "${HOME}/Library/Caches/${APP_ID}" \
           "${HOME}/Library/Saved Application State/${APP_ID}.savedState" \
           "${HOME}/Library/WebKit/${APP_ID}" 2>/dev/null || true
    rm -f "${HOME}/Library/Application Support/${APP_ID}/.seen-"* 2>/dev/null || true
    sudo -n rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
    killall Finder Dock 2>/dev/null || true
    ok "Data cleaned"
  else
    if command -v dpkg >/dev/null 2>&1 && dpkg -s pvzge >/dev/null 2>&1; then
      info "Removing package..."; sudo apt-get -y remove pvzge 2>/dev/null || sudo dpkg -r pvzge || true
    fi
    rm -f "${HOME}/.local/bin/PvZ2-Gardendless.AppImage" \
          "${HOME}/.local/share/applications/${APP_ID}.desktop" 2>/dev/null || true
    update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
    rm -rf "$(dirname "$MARKER")" "${HOME}/.config/${APP_ID}" "${HOME}/.local/share/${APP_ID}" 2>/dev/null || true
    ok "Data cleaned"
  fi
  nl; ok "${APP_NAME} has been completely removed."
  hint "  Re-run this script any time to install it again."
}

# ═══════════════════════ BUILD FROM SOURCE ════════════════════════════════
build_from_source() {
  step "Build from source"
  nl
  line "╭──────────────────────────────────────────╮"
  pad; printf '%s│%s  %sThis will:%s                               %s│%s\n' "$BX" "$R" "$WH" "$R" "$BX" "$R"
  pad; printf '%s│%s    %-39s%s│%s\n' "$BX" "$R" "• Clone the repository (~1 GB)" "$BX" "$R"
  pad; printf '%s│%s    %-39s%s│%s\n' "$BX" "$R" "• Compile with Rust + Tauri" "$BX" "$R"
  pad; printf '%s│%s    %-39s%s│%s\n' "$BX" "$R" "• Install the built app" "$BX" "$R"
  line "╰──────────────────────────────────────────╯"
  nl
  if [ "$INTERACTIVE" = "1" ]; then confirm "  Continue? [Y/n]" "Y" || { info "Cancelled."; return 1; }; fi

  local missing=()
  command -v git   >/dev/null 2>&1 || missing+=("git")
  command -v cargo >/dev/null 2>&1 || missing+=("rust (cargo)")
  command -v node  >/dev/null 2>&1 || missing+=("node")
  if [ "${#missing[@]}" -gt 0 ]; then
    warn "Missing build tools: ${missing[*]}"
    nl
    if [ "$OS" = "Darwin" ]; then
      info "Install with Homebrew first:"
      hint "  brew install rust node git"
    else
      info "Install build dependencies first:"
      hint "  sudo apt install -y git nodejs npm build-essential libwebkit2gtk-4.1-dev librsvg2-dev"
      hint "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
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
    ok "Tauri CLI ready"
  fi

  TMP="${TMP:-$(mktemp -d)}"; local src="${TMP}/pvge_tauri"
  spin "Cloning repository" git clone --depth 1 "https://github.com/${REPO}.git" "$src" \
    || { warn "Clone failed."; return 1; }
  ok "Cloned"
  info "Compiling — this can take several minutes..."
  ( cd "$src/src-tauri" && $tauri_cmd build --bundles app ) || { warn "Build failed."; return 1; }
  ok "Build complete"

  if [ "$OS" = "Darwin" ]; then
    local built; built="$(find "$src/src-tauri/target" -maxdepth 5 -name '*.app' -path '*/release/bundle/macos/*' -print -quit)"
    [ -n "$built" ] || { warn "Built app not found."; return 1; }
    local dest="/Applications/${APP_NAME}.app" SUDO=""
    [ -w /Applications ] || { SUDO="sudo"; sudo -v || return 1; }
    quit_if_running; $SUDO rm -rf "$dest"
    spin "Installing" $SUDO ditto "$built" "$dest" || return 1
    $SUDO xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
    ok "Installed to ${dest}"; DONE_HINT="open -a \"${APP_NAME}\""
  else
    local appimage; appimage="$(find "$src/src-tauri/target" -name '*.AppImage' -print -quit)"
    [ -n "$appimage" ] || { warn "Built AppImage not found."; return 1; }
    local target="${HOME}/.local/bin/PvZ2-Gardendless.AppImage"; mkdir -p "$(dirname "$target")"
    cp "$appimage" "$target"; chmod +x "$target"
    ok "Installed to ${target}"; DONE_HINT="$target"; LAUNCH_BIN="$target"
  fi
}

install_with_fallback() {
  local fn="install_${1}"
  if "$fn"; then return 0; fi
  nl; warn "The pre-built install method didn't succeed."
  if [ "$INTERACTIVE" = "1" ]; then
    hint "  You can try building from source as a backup plan."
    nl
    if confirm "  Build from source instead? [Y/n]" "Y"; then build_from_source && return 0; fi
    die "Installation did not complete. Re-run to try again."
  else
    die "Install failed. Re-run interactively or set PVZGE_ACTION=build."
  fi
}

show_help() {
  step "Help"
  nl
  line "╭──────────────────────────────────────────╮"
  pad; printf '%s│%s  %s%sPvZ2 Gardendless%s   desktop port          %s│%s\n' "$BX" "$R" "$BD" "$G1" "$R" "$BX" "$R"
  line "│──────────────────────────────────────────│"
  pad; printf '%s│%s  %s1%s  %-37s%s│%s\n' "$BX" "$R" "$G1" "$R" "Install or update to latest" "$BX" "$R"
  pad; printf '%s│%s  %s2%s  %-37s%s│%s\n' "$BX" "$R" "$G1" "$R" "Reinstall (force re-download)" "$BX" "$R"
  pad; printf '%s│%s  %s3%s  %-37s%s│%s\n' "$BX" "$R" "$RD" "$R" "Uninstall (removes all data)" "$BX" "$R"
  pad; printf '%s│%s  %s4%s  %-37s%s│%s\n' "$BX" "$R" "$YL" "$R" "Build from source (backup)" "$BX" "$R"
  line "│──────────────────────────────────────────│"
  pad; printf '%s│%s  %sOne-liner:%s                              %s│%s\n' "$BX" "$R" "$DIM" "$R" "$BX" "$R"
  pad; printf '%s│%s  %scurl -fsSL https://raw.github%s           %s│%s\n' "$BX" "$R" "$G2" "$R" "$BX" "$R"
  pad; printf '%s│%s  %susercontent.com/%s/%s  %s│%s\n' "$BX" "$R" "$G2" "$REPO" "main/install.sh | bash" "$BX" "$R"
  line "│──────────────────────────────────────────│"
  pad; printf '%s│%s  %sEnv overrides:%s                          %s│%s\n' "$BX" "$R" "$DIM" "$R" "$BX" "$R"
  pad; printf '%s│%s  %sPVZGE_ACTION%s    install|build|uninstall %s│%s\n' "$BX" "$R" "$WH" "$R" "$BX" "$R"
  pad; printf '%s│%s  %sPVZGE_VERSION%s   pin a specific release  %s│%s\n' "$BX" "$R" "$WH" "$R" "$BX" "$R"
  pad; printf '%s│%s  %sPVZGE_FORCE%s     reinstall even if same  %s│%s\n' "$BX" "$R" "$WH" "$R" "$BX" "$R"
  pad; printf '%s│%s  %sNO_COLOR%s        disable colors          %s│%s\n' "$BX" "$R" "$WH" "$R" "$BX" "$R"
  line "│──────────────────────────────────────────│"
  pad; printf '%s│%s  %sGame by%s Gaozih & the PvZ2GE Team        %s│%s\n' "$BX" "$R" "$DIM" "$R" "$BX" "$R"
  pad; printf '%s│%s  %sPort by%s Marcus Nguyen                   %s│%s\n' "$BX" "$R" "$DIM" "$R" "$BX" "$R"
  line "╰──────────────────────────────────────────╯"
  nl
}

finish() {
  nl
  printf '%s' "$G1"
  cat <<'DONE'
   ╭──────────────────────────────────────────────╮
   │                                              │
   │          🌱  Installed & ready!  🧟           │
   │                                              │
   ╰──────────────────────────────────────────────╯
DONE
  printf '%s\n' "$R"
  info "Launch any time with:"
  nl
  printf '      %s$ %s%s%s\n' "$DIM" "$G2" "${DONE_HINT:-}" "$R"
  nl
  divider
  hint "  Game by Gaozih & the PvZ2 Gardendless Team"
  hint "  ${PLATFORM} port by Marcus Nguyen"
  nl
}

launch_app() {
  [ -n "${PVZGE_NO_LAUNCH:-}" ] && return 0
  info "Launching ${APP_NAME}..."
  if [ "$OS" = "Darwin" ]; then
    open -a "${APP_NAME}" 2>/dev/null || open "/Applications/${APP_NAME}.app" 2>/dev/null || true
  elif [ -n "${LAUNCH_BIN:-}" ]; then
    ( setsid "${LAUNCH_BIN}" >/dev/null 2>&1 & ) 2>/dev/null \
      || ( "${LAUNCH_BIN}" >/dev/null 2>&1 & ) 2>/dev/null || true
  fi
}

# ── Interactive menu ─────────────────────────────────────────────────────
menu() {
  local cur; cur="$(installed_version)"
  local one="Install"; [ -n "$cur" ] && one="Update"
  nl
  line "╭──────────────────────────────────────────╮"
  pad; printf '%s│%s  %sWhat would you like to do?%s               %s│%s\n' "$BX" "$R" "$BD$WH" "$R" "$BX" "$R"
  line "│                                          │"
  pad; printf '%s│%s  %s  1 %s● %s%-33s%s│%s\n' "$BX" "$R" "$G1" "$G3" "$WH" "$one" "$BX" "$R"
  pad; printf '%s│%s  %s  2 %s● %s%-33s%s│%s\n' "$BX" "$R" "$G1" "$G2" "$WH" "Reinstall (force clean)" "$BX" "$R"
  pad; printf '%s│%s  %s  3 %s● %s%-33s%s│%s\n' "$BX" "$R" "$RD" "$RD" "$WH" "Uninstall" "$BX" "$R"
  pad; printf '%s│%s  %s  4 %s● %s%-33s%s│%s\n' "$BX" "$R" "$YL" "$YL" "$WH" "Build from source" "$BX" "$R"
  pad; printf '%s│%s  %s  5 %s● %s%-33s%s│%s\n' "$BX" "$R" "$DIM" "$DIM" "$R" "Help & docs" "$BX" "$R"
  pad; printf '%s│%s  %s  6 %s● %s%-33s%s│%s\n' "$BX" "$R" "$DIM" "$DIM" "$R" "Quit" "$BX" "$R"
  line "│                                          │"
  line "╰──────────────────────────────────────────╯"
  nl
  local c; c="$(ask "  Enter choice [1]: " "1")"
  case "$c" in
    1) ACTION="update" ;;
    2) ACTION="reinstall"; PVZGE_FORCE=1 ;;
    3) ACTION="uninstall" ;;
    4) ACTION="build" ;;
    5) show_help; menu; return ;;
    6|q|Q) nl; info "See you later!"; nl; exit 0 ;;
    *) warn "Invalid choice. Defaulting to ${one}."; ACTION="update" ;;
  esac
}

# ── main ─────────────────────────────────────────────────────────────────
main() {
  require uname; require curl; require grep; require sed; require awk
  banner

  OS="$(uname -s)"; ARCH="$(uname -m)"
  case "$OS" in
    Darwin) PLATFORM="macOS" ;;
    Linux)  PLATFORM="Linux" ;;
    *)      die "Unsupported OS: $OS (macOS and Linux only)." ;;
  esac

  ACTION="${PVZGE_ACTION:-}"

  if [ "$ACTION" != "uninstall" ]; then
    step "Connecting to GitHub"
    resolve_release
    ok "Release ${VERSION} found"
  fi

  # Show the system info card
  sysinfo

  if [ -z "$ACTION" ]; then
    if [ "$INTERACTIVE" = "1" ]; then
      menu
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
