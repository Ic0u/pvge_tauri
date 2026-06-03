#!/usr/bin/env bash
# PvZ2 Gardendless — installer · updater · uninstaller
# curl -fsSL https://raw.githubusercontent.com/Ic0u/pvge_tauri/main/install.sh | bash
set -euo pipefail

REPO="Ic0u/pvge_tauri"
APP="PvZ2 Gardendless"
APP_ID="com.pvzge.desktop"
MARKER="${HOME}/.local/share/pvzge/version"

# ── Colors (PvZ2 green gradient) ─────────────────────────────────────────
ESC=$'\x1b'
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[0m' B=$'\033[1m' D=$'\033[2m'
  G1=$'\033[38;5;154m' G2=$'\033[38;5;118m' G3=$'\033[38;5;82m'
  G4=$'\033[38;5;76m'  G5=$'\033[38;5;34m'  G6=$'\033[38;5;28m' G7=$'\033[38;5;22m'
  C=$'\033[38;5;76m'   RD=$'\033[31m' YL=$'\033[33m'
  CIVIS=$'\033[?25l' CNORM=$'\033[?25h' EL=$'\033[2K'
  TTY=1
else
  R='' B='' D='' G1='' G2='' G3='' G4='' G5='' G6='' G7='' C='' RD='' YL=''
  CIVIS='' CNORM='' EL='' TTY=0
fi

INTERACTIVE=0
[ -z "${PVZGE_YES:-}" ] && [ -r /dev/tty ] && [ -t 1 ] && INTERACTIVE=1

# ── Terminal width (for centering only; never used for absolute layout) ──
term_cols() {
  local sz c
  sz="$(stty size </dev/tty 2>/dev/null || true)"
  c="${sz##* }"
  [ -n "$c" ] && [ "$c" -ge 1 ] 2>/dev/null || c="$(command tput cols 2>/dev/null || echo "${COLUMNS:-80}")"
  [ -n "$c" ] && [ "$c" -ge 1 ] 2>/dev/null || c=80
  printf '%s' "$c"
}
COLS="$(term_cols)"
# Left indent to center a ~58-wide content block (safe: flowing, never breaks)
PAD=""
_pad=$(( (COLS - 58) / 2 )); [ "$_pad" -gt 2 ] && PAD="$(printf "%${_pad}s" "")"
p() { printf '%s' "$PAD"; }

# ── Output helpers ───────────────────────────────────────────────────────
msg()  { p; printf '%s▸%s %s\n'  "$C"  "$R" "$*"; }
good() { p; printf '%s✓%s %s\n'  "$G1" "$R" "$*"; }
bad()  { p; printf '%s!%s %s\n'  "$YL" "$R" "$*"; }
dim()  { p; printf '%s%s%s\n'    "$D"  "$*" "$R"; }

# ── Cleanup ──────────────────────────────────────────────────────────────
TMP="" MOUNTED_DMG=""
cleanup() {
  printf '%s' "$CNORM" 2>/dev/null || true
  stty echo 2>/dev/null || true
  [ -n "$MOUNTED_DMG" ] && hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null || true
  [ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ── Peashooter banner (flowing — printed once, no absolute positioning) ──
banner() {
  local g=("$G7" "$G6" "$G6" "$G5" "$G5" "$G4" "$G4" "$G3" "$G3" "$G2" "$G2" "$G3" "$G4" "$G5")
  local art=(
    "      ░▒▓██▓▒░"
    "    ░▓██████████▓░"
    "  ░▓██  ██    ██  ██▓░"
    "  ▓██   ▓▓    ▓▓   ██▓"
    "  ▓██              ██▓"
    "   ▓███   ▀▀▀▀  ███▓"
    "    ░▓██████████████░"
    "       ▓████████▓"
    "     ░▓██████████▓▒"
    "    ▓████████████████▓"
    "   ▓██▓▒░      ░▒▓██▓"
    "    ██             ██"
    "     ▓░           ░▓"
    "      ░░░░░░░░░░░░░"
  )
  echo ""
  local i=0
  for line in "${art[@]}"; do
    p; printf '        %s%s%s\n' "${g[$i]}" "$line" "$R"
    i=$((i+1))
  done
  echo ""
  local os_icon=""; [ "$OS" = Darwin ] && os_icon="" || os_icon=""
  p; printf '   %s%s%s%s\n' "$B" "$G1" "$APP" "$R"
  p; printf '   %s%s %s · %s%s\n' "$G4" "$os_icon" "$PLATFORM" "$ARCH" "$R"
  echo ""
  local cur; cur="$(installed_version)"
  p; printf '   %sInstalled  %s' "$G4" "$R"; [ -n "$cur" ] && { printf '%s%s%s\n' "$G1" "$cur" "$R"; } || { printf '%s—%s\n' "$D" "$R"; }
  p; printf '   %sLatest     %s%s%s%s\n' "$G4" "$R" "$G1" "${VERSION:-…}" "$R"
  echo ""
}

# ── Arrow-key menu (flowing; redraws only its own lines, never a new screen)
SELECTED=0
menu() {
  local labels=() descs=() all=("$@") i=0
  while [ $i -lt ${#all[@]} ]; do labels+=("${all[$i]}"); descs+=("${all[$((i+1))]}"); i=$((i+2)); done
  local n=${#labels[@]}
  local icons=("󰏔" "󰑓" "󰩺" "󰙲" "" "")
  SELECTED=0

  if [ "$INTERACTIVE" = 0 ]; then SELECTED=0; return; fi

  printf '%s' "$CIVIS"; stty -echo 2>/dev/null || true
  while true; do
    i=0
    while [ $i -lt $n ]; do
      printf '\r%s' "$EL"   # CR to col 0, then clear the whole line
      if [ $i -eq $SELECTED ]; then
        p; printf ' %s▸ %s ' "$G1$B" "$R"
        printf '%s%-12s%s' "$G1$B" "${labels[$i]}" "$R"
        printf '  %s%s%s\n' "$G4" "${descs[$i]}" "$R"
      else
        p; printf '   %s%s %-12s%s  %s%s%s\n' "$D" "${icons[$i]:-}" "${labels[$i]}" "$R" "$D" "${descs[$i]}" "$R"
      fi
      i=$((i+1))
    done
    printf '\r%s\n' "$EL"
    printf '\r%s' "$EL"; p; printf '   %s↑↓%s nav  %s⏎%s select  %sq%s quit' "$G5" "$R" "$G5" "$R" "$G5" "$R"

    local key
    IFS= read -rsn1 key </dev/tty || { key=q; }
    if [ "$key" = "$ESC" ]; then
      IFS= read -rsn2 -t 0.05 key </dev/tty 2>/dev/null || key=""
      case "$key" in
        '[A') SELECTED=$(( SELECTED>0 ? SELECTED-1 : n-1 ));;
        '[B') SELECTED=$(( SELECTED<n-1 ? SELECTED+1 : 0 ));;
      esac
    elif [ -z "$key" ]; then break
    elif [ "$key" = q ] || [ "$key" = Q ]; then
      stty echo 2>/dev/null || true; printf '%s\n' "$CNORM"; exit 0
    elif [ "$key" = k ]; then SELECTED=$(( SELECTED>0 ? SELECTED-1 : n-1 ))
    elif [ "$key" = j ]; then SELECTED=$(( SELECTED<n-1 ? SELECTED+1 : 0 ))
    fi
    # Move cursor back up over the n options + blank + footer (n+1 rows up
    # from the footer row to land on the first option row)
    printf '\r\033[%dA' "$((n+1))"
  done
  stty echo 2>/dev/null || true; printf '%s' "$CNORM"
  echo ""
}

# ── Spinner ──────────────────────────────────────────────────────────────
spin() {
  local m="$1"; shift
  [ "$TTY" = 0 ] && { "$@"; return $?; }
  "$@" &
  local pid=$! i=0 f='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  printf '%s' "$CIVIS"
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r'; p; printf '%s%s%s %s' "$C" "${f:$((i%10)):1}" "$R" "$m"
    i=$((i+1)); sleep 0.08
  done
  local rc=0; wait "$pid" || rc=$?
  printf '\r%s' "$EL"; printf '%s' "$CNORM"
  return "$rc"
}

confirm() {
  [ "$INTERACTIVE" = 0 ] && return 0
  p; printf '%s%s%s ' "$C" "$1" "$R"
  local a; IFS= read -r a </dev/tty || a=""
  case "${a:-$2}" in [yY]*) return 0;; *) return 1;; esac
}

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
    case "$PVZGE_ARCH" in universal) pick macOS-Universal .dmg||true;; x86_64) pick macOS-x86_64 .dmg||true;; arm64) pick macOS-Apple-Silicon .dmg||true;; esac; return
  fi
  local url=""
  case "$arch" in
    arm64)  url="$(pick macOS-Apple-Silicon .dmg||true)"; [ -z "$url" ] && url="$(pick macOS-Universal .dmg||true)";;
    x86_64) url="$(pick macOS-x86_64 .dmg||true)"; [ -z "$url" ] && url="$(pick macOS-Universal .dmg||true)";;
  esac
  printf '%s' "$url"
}

# ── Install / Uninstall / Build ──────────────────────────────────────────
install_macos() {
  echo ""
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
  echo ""
  [ "$ARCH" = x86_64 ] || { bad "Only x86_64 Linux builds"; return 1; }
  local url kind
  if [ -n "$(pick Linux-x86_64 .deb||true)" ] && command -v dpkg >/dev/null; then url="$(pick Linux-x86_64 .deb)"; kind=deb
  elif [ -n "$(pick Linux-x86_64 .AppImage||true)" ]; then url="$(pick Linux-x86_64 .AppImage)"; kind=appimage
  else bad "No Linux build"; return 1; fi
  good "Build: $(basename "$url")"
  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION:-}" != reinstall ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$VERSION" ]; then good "Already up to date ($VERSION)"; return 0; fi
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
  echo ""
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
  echo ""
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
    chmod +x "${HOME}/.local/bin/PvZ2-Gardendless.AppImage"; DONE_HINT="${HOME}/.local/bin/PvZ2-Gardendless.AppImage"; LAUNCH_BIN="$DONE_HINT"; fi
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
  echo ""; p; printf '%s✓%s %s%s is ready%s\n\n' "$G1" "$R" "$B" "$APP" "$R"
  [ -n "${DONE_HINT:-}" ] && { p; printf '   %s%s %s%s\n\n' "$G4" "" "$DONE_HINT" "$R"; }
  dim "   Game by Gaozih · Port by Marcus Nguyen"; echo ""
}
show_help() {
  echo ""
  p; printf '   %s%sEnvironment overrides%s\n\n' "$B" "$G1" "$R"
  p; printf '   %sPVZGE_ACTION%s     install|build|uninstall\n' "$C" "$R"
  p; printf '   %sPVZGE_VERSION%s    pin release (v0.8.2)\n' "$C" "$R"
  p; printf '   %sPVZGE_FORCE%s      reinstall if current\n' "$C" "$R"
  p; printf '   %sPVZGE_ARCH%s       x86_64|arm64|universal\n' "$C" "$R"
  p; printf '   %sPVZGE_NO_LAUNCH%s  skip auto-open\n' "$C" "$R"
  p; printf '   %sNO_COLOR%s         disable colors\n\n' "$C" "$R"
  dim "   github.com/$REPO"; echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
  OS="$(uname -s)"; ARCH="$(uname -m)"
  case "$OS" in Darwin) PLATFORM=macOS;; Linux) PLATFORM=Linux;; *) echo "Unsupported: $OS" >&2; exit 1;; esac
  resolve_release

  ACTION="${PVZGE_ACTION:-}"

  if [ -z "$ACTION" ] && [ "$INTERACTIVE" = 1 ]; then
    [ "$TTY" = 1 ] && printf '\033[2J\033[H'  # clear screen + home (no alt buffer)
    banner
    local cur; cur="$(installed_version)"
    local one="Install"; [ -n "$cur" ] && one="Update"
    menu \
      "$one"       "Download latest release" \
      "Reinstall"  "Force clean re-download" \
      "Uninstall"  "Remove app and data" \
      "Build"      "Compile from source" \
      "Help"       "Environment overrides" \
      "Quit"       ""
    case $SELECTED in
      0) ACTION=update ;;
      1) ACTION=reinstall; PVZGE_FORCE=1 ;;
      2) ACTION=uninstall ;;
      3) ACTION=build ;;
      4) show_help; exit 0 ;;
      5) exit 0 ;;
    esac
  fi
  [ -z "$ACTION" ] && { ACTION=update; echo ""; p; printf ' %s%s · %s%s\n' "$B" "$APP" "$VERSION" "$R"; }

  case "$ACTION" in
    uninstall) uninstall ;;
    build) build_from_source && { finish; launch_app; } ;;
    *) install_with_fallback "$([ "$OS" = Darwin ] && echo macos || echo linux)" && { finish; launch_app; } ;;
  esac
}

main "$@"
