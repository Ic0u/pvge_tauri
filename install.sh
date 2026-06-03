#!/usr/bin/env bash
# PvZ2 Gardendless — installer · updater · uninstaller
# curl -fsSL https://raw.githubusercontent.com/Ic0u/pvge_tauri/main/install.sh | bash
set -euo pipefail

REPO="Ic0u/pvge_tauri"
APP="PvZ2 Gardendless"
APP_ID="com.pvzge.desktop"
MARKER="${HOME}/.local/share/pvzge/version"

# ── Pure-bash tput (inspired by Nightfall by Dave Eddy) ──────────────────
ESC=$'\x1b'
_tput() {
  case "$1" in
    cup)    printf '%s[%d;%dH' "$ESC" "$(($2+1))" "$(($3+1))";;
    setaf)  printf '%s[38;5;%dm' "$ESC" "$2";;
    setab)  printf '%s[48;5;%dm' "$ESC" "$2";;
    sgr0)   printf '%s[0m' "$ESC";;
    bold)   printf '%s[1m' "$ESC";;
    dim)    printf '%s[2m' "$ESC";;
    civis)  printf '%s[?25l' "$ESC";;
    cnorm)  printf '%s[?25h' "$ESC";;
    smcup)  printf '%s[?1049h' "$ESC";;
    rmcup)  printf '%s[?1049l' "$ESC";;
    clear)  printf '%s[2J' "$ESC";;
    el)     printf '%s[2K' "$ESC";;
    *)      command tput "$@" 2>/dev/null;;
  esac
}

# ── State ────────────────────────────────────────────────────────────────
INTERACTIVE=0; TTY=0; COLS=80; ROWS=24
TMP=""; MOUNTED_DMG=""; VERSION=""; RELEASE_JSON=""
OS=""; ARCH=""; PLATFORM=""

# ── Terminal size — stty first (kernel tty size, ignores $TERM), then
#    tput, then $COLUMNS/$LINES, then 80x24. tput silently returns the
#    80x24 fallback when $TERM is unset (Finder/odd launchers), which is
#    what jammed the UI into a corner — stty avoids that entirely. ────────
read_size() {
  local sz=""
  sz="$(stty size </dev/tty 2>/dev/null || true)"
  if [ -n "$sz" ] && [ "${sz% *}" -ge 1 ] 2>/dev/null; then
    ROWS="${sz%% *}"; COLS="${sz##* }"
  else
    COLS="$(command tput cols 2>/dev/null || echo "${COLUMNS:-80}")"
    ROWS="$(command tput lines 2>/dev/null || echo "${LINES:-24}")"
  fi
  [ -n "$COLS" ] && [ "$COLS" -ge 1 ] 2>/dev/null || COLS=80
  [ -n "$ROWS" ] && [ "$ROWS" -ge 1 ] 2>/dev/null || ROWS=24
}

init_term() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then TTY=1; fi
  [ -z "${PVZGE_YES:-}" ] && [ -r /dev/tty ] && [ -t 1 ] && INTERACTIVE=1
  read_size
}

# ── Cleanup (Nightfall-style: restore terminal on any exit) ──────────────
cleanup() {
  _tput cnorm
  [ "$TTY" = 1 ] && [ "$INTERACTIVE" = 1 ] && _tput rmcup
  stty echo 2>/dev/null || true
  [ -n "$MOUNTED_DMG" ] && hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null || true
  [ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ── Drawing helpers ──────────────────────────────────────────────────────
at()   { _tput cup "$1" "$2"; }  # row col
clr()  { _tput el; }             # clear current line
color(){ _tput setaf "$1"; }
bg()   { _tput setab "$1"; }
bold() { _tput bold; }
dim()  { _tput dim; }
rst()  { _tput sgr0; }

# Print at position: pat row col "text"
pat() { at "$1" "$2"; shift 2; printf '%s' "$*"; }

# ── Gradient peashooter (CP437-style block shading) ──────────────────────
# Uses ░▒▓█ gradient in greens (28→34→40→46→82→118)
draw_peashooter() {
  local r=$1 c=$2
  local g1=22 g2=28 g3=34 g4=76 g5=154 g6=118
  local lines=(
    "        ░▒▓██▓▒░"
    "      ░▓██████████▓░"
    "    ░▓██  ██    ██  ██▓░"
    "    ▓██   ▓▓    ▓▓   ██▓"
    "    ▓██              ██▓"
    "     ▓███   ▀▀▀▀  ███▓"
    "      ░▓██████████████░"
    "         ▓████████▓"
    "       ░▓██████████▓▒"
    "      ▓████████████████▓"
    "     ▓██▓▒░      ░▒▓██▓"
    "      ██             ██"
    "       ▓░           ░▓"
    "        ░░░░░░░░░░░░░"
  )
  local colors=($g1 $g2 $g2 $g3 $g3 $g4 $g4 $g5 $g5 $g6 $g6 $g5 $g4 $g3)
  local i=0
  for line in "${lines[@]}"; do
    color "${colors[$i]}"
    pat "$((r + i))" "$c" "$line"
    i=$((i + 1))
  done
  rst
}

# ── Animated border (Nightfall-style) ────────────────────────────────────
draw_border() {
  local shade=("$@")  # array of color codes, outer→inner
  local i=0
  for clr_code in "${shade[@]}"; do
    bg "$clr_code"
    # Top
    at "$i" "$((i * 2))"
    printf '%*s' "$((COLS - i * 4))" ''
    # Bottom
    at "$((ROWS - i - 1))" "$((i * 2))"
    printf '%*s' "$((COLS - i * 4))" ''
    # Sides
    local row
    for ((row = i; row < ROWS - i; row++)); do
      at "$row" "$((i * 2))"; printf '  '
      at "$row" "$((COLS - i * 2 - 2))"; printf '  '
    done
    rst
    sleep 0.03 2>/dev/null || true
    i=$((i + 1))
  done
}

# ── Draw the full UI ─────────────────────────────────────────────────────
SELECTED=0
MENU_LABELS=() MENU_DESCS=()

draw_ui() {
  local cx=$((COLS / 2))
  # Vertically center the ~18-row content block within the real terminal
  local top=$(( (ROWS - 18) / 2 )); [ "$top" -lt 2 ] && top=2

  # ── Left: peashooter ──
  draw_peashooter "$((top + 2))" "$((cx - 42))"

  # ── Right: info panel ──
  local rx=$((cx - 10))
  # Nerd Font OS icon
  local os_icon=""; [ "$OS" = Darwin ] && os_icon="" || os_icon=""
  bold; color 154
  pat "$((top))" "$rx" "$APP"
  rst; color 76
  pat "$((top + 1))" "$rx" "$os_icon $PLATFORM · $ARCH"
  rst

  # Status
  local cur; cur="$(installed_version)"
  local y=$((top + 3))
  color 76; pat "$y" "$rx" "  Installed  "; rst
  if [ -n "$cur" ]; then color 154; printf '%s' "$cur"; else dim; printf '—'; fi
  rst

  y=$((y + 1))
  color 76; pat "$y" "$rx" "  Latest     "; rst
  color 154; printf '%s' "${VERSION:-…}"; rst

  # ── Menu (with Nerd Font icons) ──
  # Icons: 󰏔 download, 󰑓 reinstall, 󰩺 uninstall, 󰙲 build,  help,  quit
  local icons=("󰏔" "󰑓" "󰩺" "󰙲" "" "")
  y=$((top + 7))
  local n=${#MENU_LABELS[@]} i=0
  while [ $i -lt $n ]; do
    at "$y" 0; clr  # clear from col 0 to prevent smear
    at "$y" "$rx"
    if [ $i -eq $SELECTED ]; then
      color 154; bold; printf '▸ '; rst
      color 154; printf '%s ' "${icons[$i]:-}"; rst
      color 76; bold; printf '%-13s' "${MENU_LABELS[$i]}"; rst
      color 34; printf ' %s' "${MENU_DESCS[$i]}"; rst
    else
      dim; printf '  %s %-13s %s' "${icons[$i]:-}" "${MENU_LABELS[$i]}" "${MENU_DESCS[$i]}"; rst
    fi
    y=$((y + 1)); i=$((i + 1))
  done

  # Footer
  y=$((ROWS - 3))
  at "$y" 0; clr; at "$y" "$rx"
  color 28; printf '↑↓'; rst; dim; printf ' Navigate  '; rst
  color 28; printf '⏎'; rst; dim; printf ' Select  '; rst
  color 28; printf 'q'; rst; dim; printf ' Quit'; rst

  # Credits
  y=$((ROWS - 2))
  at "$y" "$((cx - 26))"
  dim; printf '  Game by Gaozih · macOS/Linux port by Marcus Nguyen'; rst
}

# ── Arrow-key event loop (Nightfall-style: read from tty) ────────────────
run_menu() {
  MENU_LABELS=("$@")
  # Split interleaved labels/descs
  local all=("$@") labels=() descs=() i=0
  while [ $i -lt ${#all[@]} ]; do
    labels+=("${all[$i]}")
    descs+=("${all[$((i+1))]}")
    i=$((i + 2))
  done
  MENU_LABELS=("${labels[@]}")
  MENU_DESCS=("${descs[@]}")
  local n=${#labels[@]}
  SELECTED=0

  _tput civis
  stty -echo 2>/dev/null || true

  draw_ui

  while true; do
    local key
    IFS= read -rsn1 key </dev/tty
    if [ "$key" = "$ESC" ]; then
      IFS= read -rsn2 key </dev/tty
      case "$key" in
        '[A'|'[D') SELECTED=$(( SELECTED > 0 ? SELECTED - 1 : n - 1 ));;
        '[B'|'[C') SELECTED=$(( SELECTED < n - 1 ? SELECTED + 1 : 0 ));;
      esac
    elif [ "$key" = "" ]; then
      break  # Enter
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      stty echo 2>/dev/null || true; _tput cnorm; exit 0
    elif [ "$key" = "k" ] || [ "$key" = "K" ]; then
      SELECTED=$(( SELECTED > 0 ? SELECTED - 1 : n - 1 ))
    elif [ "$key" = "j" ] || [ "$key" = "J" ]; then
      SELECTED=$(( SELECTED < n - 1 ? SELECTED + 1 : 0 ))
    fi
    draw_ui
  done

  stty echo 2>/dev/null || true
  _tput cnorm
}

# ── Spinner ──────────────────────────────────────────────────────────────
spin() {
  local msg="$1"; shift
  [ "$TTY" = 0 ] && { "$@"; return $?; }
  "$@" &
  local pid=$! i=0 f='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  _tput civis
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r'; color 6; printf ' %s' "${f:$((i%10)):1}"; rst; printf ' %s' "$msg"
    i=$((i+1)); sleep 0.08
  done
  local rc=0; wait "$pid" || rc=$?
  printf '\r'; clr; _tput cnorm
  return "$rc"
}

confirm() {
  [ "$INTERACTIVE" = 0 ] && return 0
  color 6; printf ' %s ' "$1"; rst
  stty echo 2>/dev/null || true
  local a; IFS= read -r a </dev/tty || a=""
  stty -echo 2>/dev/null || true
  case "${a:-$2}" in [yY]*) return 0;; *) return 1;; esac
}

msg()  { color 6; printf ' ▸'; rst; printf ' %s\n' "$*"; }
good() { color 34; printf ' ✓'; rst; printf ' %s\n' "$*"; }
bad()  { color 1; printf ' !'; rst; printf ' %s\n' "$*"; }

# ── GitHub API ───────────────────────────────────────────────────────────
json_assets() { printf '%s' "$RELEASE_JSON" | grep -o '"browser_download_url"[^,]*' | sed 's/.*"://;s/"//g;s/ //g'; }
pick() { json_assets | grep -F "$1" | grep -i "${2}\$" | head -1; }
human_size() {
  local n; n="\"$(basename "$1")\""
  printf '%s' "$RELEASE_JSON" | awk -v n="$n" 'index($0,n){f=1} f&&/"size":/{gsub(/[^0-9]/,"");print;exit}' \
    | awk '{if($1>1e9)printf"%.1f GB",$1/1e9;else printf"%d MB",$1/1e6}'
}
resolve_release() {
  [ -n "${VERSION:-}" ] && return
  local api="https://api.github.com/repos/${REPO}/releases/${PVZGE_VERSION:+tags/$PVZGE_VERSION}"
  [ -z "${PVZGE_VERSION:-}" ] && api="https://api.github.com/repos/${REPO}/releases/latest"
  RELEASE_JSON="$(curl -fsSL --retry 3 "$api" 2>/dev/null)" || { echo "Cannot reach GitHub." >&2; exit 1; }
  VERSION="$(printf '%s' "$RELEASE_JSON" | sed -n 's/.*"tag_name"[^"]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$VERSION" ] || { echo "No release found." >&2; exit 1; }
}
installed_version() {
  [ "$OS" = Darwin ] && { defaults read "/Applications/${APP}.app/Contents/Info" CFBundleShortVersionString 2>/dev/null | sed 's/^/v/' || true; return; }
  [ -f "$MARKER" ] && cat "$MARKER" 2>/dev/null || true
}
is_installed() {
  [ "$OS" = Darwin ] && [ -d "/Applications/${APP}.app" ] && return 0
  { [ -f "$MARKER" ] || [ -x "${HOME}/.local/bin/PvZ2-Gardendless.AppImage" ]; } && return 0
  return 1
}
quit_if_running() {
  pgrep -f "$APP" >/dev/null 2>&1 || return 0
  msg "Closing ${APP}..."
  [ "$OS" = Darwin ] && osascript -e "quit app \"$APP\"" 2>/dev/null || true
  sleep 1; pkill -f "${APP}" 2>/dev/null || true
}
pick_macos_dmg() {
  local arch="$ARCH"
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ] && arch=arm64
  if [ -n "${PVZGE_ARCH:-}" ] && [ "${PVZGE_ARCH}" != auto ]; then
    case "$PVZGE_ARCH" in
      universal) pick macOS-Universal .dmg || true;; x86_64) pick macOS-x86_64 .dmg || true;; arm64) pick macOS-Apple-Silicon .dmg || true;;
    esac; return
  fi
  local url=""
  case "$arch" in
    arm64)  url="$(pick macOS-Apple-Silicon .dmg || true)"; [ -z "$url" ] && url="$(pick macOS-Universal .dmg || true)";;
    x86_64) url="$(pick macOS-x86_64 .dmg || true)"; [ -z "$url" ] && url="$(pick macOS-Universal .dmg || true)";;
  esac
  printf '%s' "$url"
}

# ── Install / Uninstall / Build (same logic, exits alternate screen) ─────
leave_tui() {
  [ "$TTY" = 1 ] && [ "$INTERACTIVE" = 1 ] && { _tput cnorm; _tput rmcup; stty echo 2>/dev/null || true; }
}

install_macos() {
  leave_tui; echo ""
  local url; url="$(pick_macos_dmg)"
  [ -n "$url" ] || { bad "No macOS build in $VERSION"; return 1; }
  good "Build: $(basename "$url")"
  local dest="/Applications/${APP}.app"
  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION:-}" != reinstall ] && [ -d "$dest" ]; then
    local cur; cur="$(installed_version)"
    [ -n "$cur" ] && [ "$cur" = "$VERSION" ] && { good "Already up to date ($cur)"; DONE_HINT="open -a \"$APP\""; return 0; }
    [ -n "$cur" ] && msg "Updating $cur → $VERSION"
  fi
  msg "Downloading  $(human_size "$url")"
  TMP="$(mktemp -d)"
  curl -fSL --retry 5 --retry-all-errors -C - --progress-bar "$url" -o "$TMP/pvzge.dmg" || return 1
  good "Downloaded"
  msg "Mounting..."
  local out; out="$(hdiutil attach -nobrowse -noverify -noautoopen -readonly "$TMP/pvzge.dmg" 2>/dev/null)" || return 1
  MOUNTED_DMG="$(printf '%s' "$out" | grep -Eo '/Volumes/[^[:cntrl:]]*' | tail -1)"
  local app_src; app_src="$(find "$MOUNTED_DMG" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null)"
  [ -n "$app_src" ] || { bad "No .app in image"; return 1; }
  local S=""; [ ! -w /Applications ] && { S=sudo; sudo -v || return 1; }
  quit_if_running; [ -d "$dest" ] && $S rm -rf "$dest"
  spin "Installing" $S ditto "$app_src" "$dest" || return 1
  hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null; MOUNTED_DMG=""
  good "Installed"
  $S xattr -dr com.apple.quarantine "$dest" 2>/dev/null && good "Gatekeeper bypassed" || bad "Strip quarantine manually"
  rm -rf "$TMP" 2>/dev/null; TMP=""
  DONE_HINT="open -a \"$APP\""
}
install_linux() {
  leave_tui; echo ""
  [ "$ARCH" = x86_64 ] || { bad "Only x86_64 Linux builds"; return 1; }
  local url kind
  if [ -n "$(pick Linux-x86_64 .deb || true)" ] && command -v dpkg >/dev/null; then url="$(pick Linux-x86_64 .deb)"; kind=deb
  elif [ -n "$(pick Linux-x86_64 .AppImage || true)" ]; then url="$(pick Linux-x86_64 .AppImage)"; kind=appimage
  else bad "No Linux build"; return 1; fi
  good "Build: $(basename "$url")"
  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION:-}" != reinstall ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$VERSION" ]; then
    good "Already up to date ($VERSION)"; return 0; fi
  msg "Downloading  $(human_size "$url")"
  TMP="$(mktemp -d)"; curl -fSL --retry 5 --retry-all-errors -C - --progress-bar "$url" -o "$TMP/pkg" || return 1
  good "Downloaded"
  if [ "$kind" = deb ]; then spin "Installing" sudo dpkg -i "$TMP/pkg" || { sudo apt-get -yf install || return 1; }
    DONE_HINT=pvzge; LAUNCH_BIN="$(command -v pvzge 2>/dev/null || echo pvzge)"
  else mkdir -p "${HOME}/.local/bin"; local t="${HOME}/.local/bin/PvZ2-Gardendless.AppImage"
    mv "$TMP/pkg" "$t"; chmod +x "$t"; DONE_HINT="$t"; LAUNCH_BIN="$t"; fi
  good "Installed"; rm -rf "$TMP" 2>/dev/null; TMP=""
  mkdir -p "$(dirname "$MARKER")"; printf '%s' "$VERSION" >"$MARKER" 2>/dev/null || true
}
uninstall() {
  leave_tui; echo ""
  is_installed || { bad "Not installed."; return 0; }
  confirm "Remove ${APP} and all data? [y/N]" "N" || { msg "Cancelled."; return 0; }; echo ""
  if [ "$OS" = Darwin ]; then quit_if_running; local S=""; [ ! -w /Applications ] && { S=sudo; sudo -v 2>/dev/null || true; }
    $S rm -rf "/Applications/${APP}.app"
    rm -rf "${HOME}/Library/Application Support/${APP_ID}" "${HOME}/Library/Caches/${APP_ID}" "${HOME}/Library/WebKit/${APP_ID}" 2>/dev/null || true
  else command -v dpkg >/dev/null && dpkg -s pvzge >/dev/null 2>&1 && sudo apt-get -y remove pvzge 2>/dev/null || true
    rm -f "${HOME}/.local/bin/PvZ2-Gardendless.AppImage" "${HOME}/.local/share/applications/${APP_ID}.desktop" 2>/dev/null || true
    rm -rf "$(dirname "$MARKER")" 2>/dev/null || true; fi
  good "${APP} removed."
}
build_from_source() {
  leave_tui; echo ""
  for t in git cargo node; do command -v "$t" >/dev/null || { bad "Missing: $t"; return 1; }; done
  local tc=""; command -v tauri >/dev/null && tc=tauri || { cargo tauri --version >/dev/null 2>&1 && tc="cargo tauri"; } || {
    msg "Installing Tauri CLI..."; cargo install tauri-cli --version "^2" >/dev/null 2>&1 && tc="cargo tauri" || return 1; }
  TMP="${TMP:-$(mktemp -d)}"; local src="$TMP/pvge"
  spin "Cloning" git clone --depth 1 "https://github.com/${REPO}.git" "$src" || return 1; good "Cloned"
  msg "Compiling (may take several minutes)..."
  (cd "$src/src-tauri" && $tc build --bundles app) || return 1; good "Built"
  if [ "$OS" = Darwin ]; then local b; b="$(find "$src/src-tauri/target" -maxdepth 5 -name '*.app' -path '*/release/bundle/macos/*' -print -quit)"
    [ -n "$b" ] || return 1; local S=""; [ ! -w /Applications ] && { S=sudo; sudo -v || return 1; }
    quit_if_running; $S rm -rf "/Applications/${APP}.app"; $S ditto "$b" "/Applications/${APP}.app"
    $S xattr -dr com.apple.quarantine "/Applications/${APP}.app" 2>/dev/null || true; DONE_HINT="open -a \"$APP\""
  else local ai; ai="$(find "$src/src-tauri/target" -name '*.AppImage' -print -quit)"; [ -n "$ai" ] || return 1
    mkdir -p "${HOME}/.local/bin"; cp "$ai" "${HOME}/.local/bin/PvZ2-Gardendless.AppImage"
    chmod +x "${HOME}/.local/bin/PvZ2-Gardendless.AppImage"
    DONE_HINT="${HOME}/.local/bin/PvZ2-Gardendless.AppImage"; LAUNCH_BIN="$DONE_HINT"; fi
  good "Installed"
}
install_with_fallback() {
  if "install_$1"; then return 0; fi; bad "Install failed."
  [ "$INTERACTIVE" = 1 ] && confirm "Build from source instead? [Y/n]" "Y" && build_from_source && return 0
  return 1
}
launch_app() {
  [ -n "${PVZGE_NO_LAUNCH:-}" ] && return 0
  [ "$OS" = Darwin ] && { open -a "$APP" 2>/dev/null || true; return; }
  [ -n "${LAUNCH_BIN:-}" ] && { (setsid "$LAUNCH_BIN" >/dev/null 2>&1 &) 2>/dev/null || true; }
}
finish() {
  echo ""; color 154; printf ' ✓ '; bold; printf '%s is ready\n\n' "$APP"; rst
  [ -n "${DONE_HINT:-}" ] && { color 76; printf '  '; rst; dim; printf ' %s\n\n' "$DONE_HINT"; rst; }
  dim; printf '   Game by Gaozih · Port by Marcus Nguyen\n\n'; rst
}

# ── Simple flowing menu (small/odd terminals — no fullscreen chrome) ─────
simple_menu() {
  local labels=() descs=() all=("$@") i=0
  while [ $i -lt ${#all[@]} ]; do labels+=("${all[$i]}"); descs+=("${all[$((i+1))]}"); i=$((i+2)); done
  local n=${#labels[@]}
  local icons=("󰏔" "󰑓" "󰩺" "󰙲" "" "")
  local cur; cur="$(installed_version)"
  local os_icon=""; [ "$OS" = Darwin ] && os_icon="" || os_icon=""

  echo ""
  bold; color 154; printf ' %s\n' "$APP"; rst
  color 76;  printf ' %s %s · %s\n' "$os_icon" "$PLATFORM" "$ARCH"; rst
  echo ""
  color 76; printf ' Installed  '; rst; [ -n "$cur" ] && { color 154; printf '%s\n' "$cur"; } || { dim; printf '—\n'; }; rst
  color 76; printf ' Latest     '; rst; color 154; printf '%s\n' "${VERSION:-…}"; rst
  echo ""

  SELECTED=0
  _tput civis; stty -echo 2>/dev/null || true
  while true; do
    i=0
    while [ $i -lt $n ]; do
      _tput el
      if [ $i -eq $SELECTED ]; then
        color 154; bold; printf ' ▸ '; color 154; printf '%s ' "${icons[$i]:-}"
        color 76; printf '%-13s' "${labels[$i]}"; rst; color 34; printf ' %s\n' "${descs[$i]}"; rst
      else
        dim; printf '   %s %-13s %s\n' "${icons[$i]:-}" "${labels[$i]}" "${descs[$i]}"; rst
      fi
      i=$((i+1))
    done
    _tput el; echo ""
    _tput el; color 28; printf ' ↑↓'; rst; dim; printf ' Navigate  '; color 28; printf '⏎'; rst; dim; printf ' Select  '; color 28; printf 'q'; rst; dim; printf ' Quit'; rst
    local key
    IFS= read -rsn1 key </dev/tty
    if [ "$key" = "$ESC" ]; then IFS= read -rsn2 key </dev/tty
      case "$key" in '[A') SELECTED=$((SELECTED>0?SELECTED-1:n-1));; '[B') SELECTED=$((SELECTED<n-1?SELECTED+1:0));; esac
    elif [ "$key" = "" ]; then break
    elif [ "$key" = q ] || [ "$key" = Q ]; then stty echo 2>/dev/null||true; _tput cnorm; exit 0
    elif [ "$key" = k ]; then SELECTED=$((SELECTED>0?SELECTED-1:n-1))
    elif [ "$key" = j ]; then SELECTED=$((SELECTED<n-1?SELECTED+1:0))
    fi
    printf '\033[%dA' "$((n+2))"
  done
  stty echo 2>/dev/null || true; _tput cnorm; echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
  init_term
  OS="$(uname -s)"; ARCH="$(uname -m)"
  case "$OS" in Darwin) PLATFORM=macOS;; Linux) PLATFORM=Linux;; *) echo "Unsupported: $OS" >&2; exit 1;; esac

  # Resolve release before drawing (so we have VERSION for the UI)
  resolve_release

  ACTION="${PVZGE_ACTION:-}"

  # Interactive menu (size re-read in case the window changed since launch)
  if [ -z "$ACTION" ] && [ "$INTERACTIVE" = 1 ] && [ "$TTY" = 1 ]; then
    read_size
    local cur; cur="$(installed_version)"
    local one="Install"; [ -n "$cur" ] && one="Update"
    local items=(
      "$one"       "Download latest release"
      "Reinstall"  "Force clean re-download"
      "Uninstall"  "Remove app and data"
      "Build"      "Compile from source"
      "Help"       "Environment overrides"
      "Quit"       ""
    )

    # Fullscreen TUI only when there's room; else simple flowing menu.
    if [ "$COLS" -ge 92 ] && [ "$ROWS" -ge 26 ]; then
      _tput smcup; _tput clear; stty -echo 2>/dev/null || true
      draw_border 22 28 34 40
      run_menu "${items[@]}"
    else
      simple_menu "${items[@]}"
    fi

    case $SELECTED in
      0) ACTION=update ;;
      1) ACTION=reinstall; PVZGE_FORCE=1 ;;
      2) ACTION=uninstall ;;
      3) ACTION=build ;;
      4) leave_tui; echo ""
         bold; printf ' Environment overrides\n\n'; rst
         color 6; printf ' PVZGE_ACTION'; rst; printf '     install|build|uninstall\n'
         color 6; printf ' PVZGE_VERSION'; rst; printf '    pin release (v0.8.2)\n'
         color 6; printf ' PVZGE_FORCE'; rst; printf '      reinstall if current\n'
         color 6; printf ' PVZGE_ARCH'; rst; printf '       x86_64|arm64|universal\n'
         color 6; printf ' PVZGE_NO_LAUNCH'; rst; printf '  skip auto-open\n'
         color 6; printf ' NO_COLOR'; rst; printf '         disable colors\n\n'
         dim; printf ' github.com/%s\n\n' "$REPO"; rst
         exit 0 ;;
      5) exit 0 ;;
    esac
  fi

  # Non-interactive fallback
  if [ -z "$ACTION" ]; then
    ACTION=update
    echo ""; bold; printf ' %s · %s\n' "$APP" "$VERSION"; rst; echo ""
  fi

  case "$ACTION" in
    uninstall) uninstall ;;
    build) build_from_source && { finish; launch_app; } ;;
    *) install_with_fallback "$([ "$OS" = Darwin ] && echo macos || echo linux)" && { finish; launch_app; } ;;
  esac
}

main "$@"
