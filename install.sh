#!/usr/bin/env bash
# PvZ2 Gardendless — installer · updater · uninstaller
# curl -fsSL https://raw.githubusercontent.com/Ic0u/pvge_tauri/main/install.sh | bash
set -euo pipefail

REPO="Ic0u/pvge_tauri"
APP="PvZ2 Gardendless"
APP_ID="com.pvzge.desktop"
MARKER="${HOME}/.local/share/pvzge/version"

# ── Colors ───────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  R=$'\033[0m' B=$'\033[1m' D=$'\033[2m' C=$'\033[38;5;6m'
  G=$'\033[38;5;34m' W=$'\033[1;37m' RD=$'\033[31m' YL=$'\033[33m'
  HI=$'\033[?25l' SH=$'\033[?25h' CL=$'\033[2J\033[H'
  TTY=1
else
  R='' B='' D='' C='' G='' W='' RD='' YL='' HI='' SH='' CL='' TTY=0
fi

# ── Layout: center everything in the terminal ────────────────────────────
COLS="$(tput cols 2>/dev/null || echo 80)"
W_CONTENT=52  # inner content width
_m=""  # margin cache
margin() {
  if [ -z "$_m" ]; then
    local n=$(( (COLS - W_CONTENT) / 2 ))
    [ "$n" -gt 0 ] && _m="$(printf "%${n}s" "")" || _m=""
  fi
  printf '%s' "$_m"
}
m() { margin; }  # short alias

# ── TUI primitives (all centered) ───────────────────────────────────────
info() { m; printf '%s▸%s %s\n'   "$C" "$R" "$*"; }
ok()   { m; printf '%s✓%s %s\n'   "$G" "$R" "$*"; }
warn() { m; printf '%s!%s %s\n'   "$YL" "$R" "$*"; }
dim()  { m; printf '%s%s%s\n'     "$D" "$*" "$R"; }
die()  { echo ""; m; printf '%s✗ %s%s\n\n' "$RD" "$*" "$R" >&2; exit 1; }
cls()  { [ "$TTY" = 1 ] && printf '%s' "$CL" || echo ""; }
hr()   { m; printf '%s%s%s\n' "$D" "────────────────────────────────────────" "$R"; }

INTERACTIVE=0
[ -z "${PVZGE_YES:-}" ] && [ -r /dev/tty ] && [ -t 1 ] && INTERACTIVE=1
confirm() {
  [ "$INTERACTIVE" = 0 ] && return 0
  m; printf '%s%s%s ' "$C" "$1" "$R" >/dev/tty
  local a; IFS= read -r a </dev/tty || a=""
  case "${a:-$2}" in [yY]*) return 0;; *) return 1;; esac
}

# ── Arrow-key menu (centered) ───────────────────────────────────────────
choose() {
  local _var="$1"; shift
  local labels=() descs=() n=0
  while [ $# -ge 2 ]; do labels+=("$1"); descs+=("$2"); n=$((n+1)); shift 2; done
  [ "$INTERACTIVE" = 0 ] && { eval "$_var=0"; return; }

  local sel=0 key lines=$((n + 2))  # n options + blank + footer
  printf '%s' "$HI"
  while true; do
    # Draw each option, clearing the full line first
    local i=0
    while [ $i -lt $n ]; do
      printf '\033[2K'  # erase entire line
      if [ $i -eq $sel ]; then
        m; printf '%s▸ %-14s%s %s\n' "$C" "${labels[$i]}" "$R" "${descs[$i]}"
      else
        m; printf '  %s%-14s %s%s\n' "$D" "${labels[$i]}" "${descs[$i]}" "$R"
      fi
      i=$((i+1))
    done
    printf '\033[2K\n'  # blank line (cleared)
    printf '\033[2K'    # clear footer line
    m; printf '%s↑↓%s Navigate  %s⏎%s Select  %sq%s Quit' "$D" "$R" "$D" "$R" "$D" "$R"
    # Read key
    IFS= read -rsn1 key </dev/tty
    if [ "$key" = $'\x1b' ]; then
      IFS= read -rsn2 key </dev/tty
      case "$key" in
        '[A') sel=$(( sel > 0 ? sel - 1 : n - 1 )) ;;
        '[B') sel=$(( sel < n - 1 ? sel + 1 : 0 )) ;;
      esac
    elif [ "$key" = "" ]; then break
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      printf '%s\n' "$SH"; info "Bye!"; exit 0
    fi
    # Move cursor back up to redraw
    printf '\033[%dA' "$lines"
  done
  printf '\n%s' "$SH"
  eval "$_var=$sel"
}

# ── Spinner (centered) ──────────────────────────────────────────────────
spin() {
  local msg="$1"; shift
  [ "$TTY" = 0 ] && { "$@"; return $?; }
  "$@" &
  local pid=$! i=0 f='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' mg
  mg="$(margin)"
  printf '%s' "$HI"
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s%s%s%s %s' "$mg" "$C" "${f:$((i%10)):1}" "$R" "$msg"
    i=$((i+1)); sleep 0.08
  done
  local rc=0; wait "$pid" || rc=$?
  printf '\r\033[K%s' "$SH"
  return "$rc"
}

# ── Cleanup ──────────────────────────────────────────────────────────────
TMP="" MOUNTED_DMG=""
cleanup() {
  printf '%s' "$SH" 2>/dev/null || true
  [ -n "$MOUNTED_DMG" ] && hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null || true
  [ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT; trap 'die "Interrupted."' INT TERM

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
  RELEASE_JSON="$(curl -fsSL --retry 3 "$api" 2>/dev/null)" || die "Cannot reach GitHub."
  VERSION="$(printf '%s' "$RELEASE_JSON" | sed -n 's/.*"tag_name"[^"]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$VERSION" ] || die "No release found."
}

installed_version() {
  [ "$OS" = Darwin ] && { defaults read "/Applications/${APP}.app/Contents/Info" CFBundleShortVersionString 2>/dev/null | sed 's/^/v/' || true; return; }
  [ -f "$MARKER" ] && cat "$MARKER" 2>/dev/null || true
}
is_installed() {
  [ "$OS" = Darwin ] && [ -d "/Applications/${APP}.app" ] && return 0
  [ -f "$MARKER" ] || [ -x "${HOME}/.local/bin/PvZ2-Gardendless.AppImage" ] && return 0
  return 1
}
quit_if_running() {
  pgrep -f "$APP" >/dev/null 2>&1 || return 0
  info "Closing ${APP}..."
  [ "$OS" = Darwin ] && osascript -e "quit app \"$APP\"" 2>/dev/null || true
  sleep 1; pkill -f "${APP}" 2>/dev/null || true
}

# ── Detect correct macOS build for this machine ─────────────────────────
pick_macos_dmg() {
  local arch="$ARCH"
  # Detect Rosetta: if running under translation, real hardware is arm64
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ] && arch=arm64

  # If user forced an arch, respect it
  if [ -n "${PVZGE_ARCH:-}" ] && [ "${PVZGE_ARCH}" != "auto" ]; then
    case "$PVZGE_ARCH" in
      universal) pick macOS-Universal .dmg || true ;;
      x86_64)    pick macOS-x86_64 .dmg || true ;;
      arm64)     pick macOS-Apple-Silicon .dmg || true ;;
    esac
    return
  fi

  # Auto: pick the native build first, fall back to universal
  local url=""
  case "$arch" in
    arm64)
      url="$(pick macOS-Apple-Silicon .dmg || true)"
      [ -z "$url" ] && url="$(pick macOS-Universal .dmg || true)"
      ;;
    x86_64)
      url="$(pick macOS-x86_64 .dmg || true)"
      [ -z "$url" ] && url="$(pick macOS-Universal .dmg || true)"
      ;;
  esac
  printf '%s' "$url"
}

# ── Install macOS ────────────────────────────────────────────────────────
install_macos() {
  cls
  echo ""
  m; printf '%s%s%s  %s·  %s%s\n\n' "$B" "$W" "$APP" "$R" "$VERSION" "$R"

  local url; url="$(pick_macos_dmg)"
  [ -n "$url" ] || { warn "No macOS build in $VERSION"; return 1; }
  ok "Build: $(basename "$url")"

  local dest="/Applications/${APP}.app"
  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION:-}" != reinstall ] && [ -d "$dest" ]; then
    local cur; cur="$(installed_version)"
    if [ -n "$cur" ] && [ "$cur" = "$VERSION" ]; then
      ok "Already up to date ($cur)"
      DONE_HINT="open -a \"$APP\""; return 0
    fi
    [ -n "$cur" ] && info "Updating $cur → $VERSION"
  fi

  info "Downloading  $(human_size "$url")"
  TMP="$(mktemp -d)"
  curl -fSL --retry 5 --retry-all-errors -C - --progress-bar "$url" -o "$TMP/pvzge.dmg" || return 1
  ok "Downloaded"

  info "Mounting..."
  local out; out="$(hdiutil attach -nobrowse -noverify -noautoopen -readonly "$TMP/pvzge.dmg" 2>/dev/null)" || return 1
  MOUNTED_DMG="$(printf '%s' "$out" | grep -Eo '/Volumes/[^[:cntrl:]]*' | tail -1)"
  local app_src; app_src="$(find "$MOUNTED_DMG" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null)"
  [ -n "$app_src" ] || { warn "No .app in image"; return 1; }

  local S=""; [ ! -w /Applications ] && { S=sudo; sudo -v || return 1; }
  quit_if_running
  [ -d "$dest" ] && $S rm -rf "$dest"
  spin "Installing" $S ditto "$app_src" "$dest" || return 1
  hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null; MOUNTED_DMG=""
  ok "Installed"

  $S xattr -dr com.apple.quarantine "$dest" 2>/dev/null && ok "Gatekeeper bypassed" || warn "Strip quarantine manually"
  rm -rf "$TMP" 2>/dev/null; TMP=""
  DONE_HINT="open -a \"$APP\""
}

# ── Install Linux ────────────────────────────────────────────────────────
install_linux() {
  cls
  echo ""
  m; printf '%s%s%s  %s·  %s%s\n\n' "$B" "$W" "$APP" "$R" "$VERSION" "$R"

  [ "$ARCH" = x86_64 ] || { warn "Only x86_64 Linux builds available"; return 1; }
  local url kind
  if [ -n "$(pick Linux-x86_64 .deb || true)" ] && command -v dpkg >/dev/null; then
    url="$(pick Linux-x86_64 .deb)"; kind=deb
  elif [ -n "$(pick Linux-x86_64 .AppImage || true)" ]; then
    url="$(pick Linux-x86_64 .AppImage)"; kind=appimage
  else warn "No Linux build"; return 1; fi
  ok "Build: $(basename "$url")"

  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION:-}" != reinstall ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$VERSION" ]; then
    ok "Already up to date ($VERSION)"; return 0
  fi

  info "Downloading  $(human_size "$url")"
  TMP="$(mktemp -d)"
  curl -fSL --retry 5 --retry-all-errors -C - --progress-bar "$url" -o "$TMP/pkg" || return 1
  ok "Downloaded"

  if [ "$kind" = deb ]; then
    spin "Installing" sudo dpkg -i "$TMP/pkg" || { sudo apt-get -yf install || return 1; }
    DONE_HINT=pvzge; LAUNCH_BIN="$(command -v pvzge 2>/dev/null || echo pvzge)"
  else
    mkdir -p "${HOME}/.local/bin"
    local t="${HOME}/.local/bin/PvZ2-Gardendless.AppImage"
    mv "$TMP/pkg" "$t"; chmod +x "$t"
    DONE_HINT="$t"; LAUNCH_BIN="$t"
  fi
  ok "Installed"
  rm -rf "$TMP" 2>/dev/null; TMP=""
  mkdir -p "$(dirname "$MARKER")"; printf '%s' "$VERSION" >"$MARKER" 2>/dev/null || true
}

# ── Uninstall ────────────────────────────────────────────────────────────
uninstall() {
  cls; echo ""
  m; printf '%s%sUninstall%s\n\n' "$B" "$RD" "$R"
  is_installed || { warn "Not installed."; return 0; }
  confirm "Remove ${APP} and all data? [y/N]" "N" || { info "Cancelled."; return 0; }
  echo ""
  if [ "$OS" = Darwin ]; then
    quit_if_running
    local S=""; [ ! -w /Applications ] && { S=sudo; sudo -v 2>/dev/null || true; }
    $S rm -rf "/Applications/${APP}.app"
    rm -rf "${HOME}/Library/Application Support/${APP_ID}" "${HOME}/Library/Caches/${APP_ID}" \
           "${HOME}/Library/WebKit/${APP_ID}" 2>/dev/null || true
  else
    command -v dpkg >/dev/null && dpkg -s pvzge >/dev/null 2>&1 && sudo apt-get -y remove pvzge 2>/dev/null || true
    rm -f "${HOME}/.local/bin/PvZ2-Gardendless.AppImage" "${HOME}/.local/share/applications/${APP_ID}.desktop" 2>/dev/null || true
    rm -rf "$(dirname "$MARKER")" 2>/dev/null || true
  fi
  ok "${APP} removed."
}

# ── Build from source ────────────────────────────────────────────────────
build_from_source() {
  cls; echo ""
  m; printf '%s%sBuild from source%s\n\n' "$B" "$YL" "$R"
  for t in git cargo node; do command -v "$t" >/dev/null || { warn "Missing: $t"; return 1; }; done
  local tc=""
  command -v tauri >/dev/null && tc=tauri || { cargo tauri --version >/dev/null 2>&1 && tc="cargo tauri"; } || {
    info "Installing Tauri CLI..."; cargo install tauri-cli --version "^2" >/dev/null 2>&1 && tc="cargo tauri" || return 1
  }
  TMP="${TMP:-$(mktemp -d)}"; local src="$TMP/pvge"
  spin "Cloning" git clone --depth 1 "https://github.com/${REPO}.git" "$src" || return 1
  ok "Cloned"
  info "Compiling (may take several minutes)..."
  (cd "$src/src-tauri" && $tc build --bundles app) || return 1
  ok "Built"
  if [ "$OS" = Darwin ]; then
    local b; b="$(find "$src/src-tauri/target" -maxdepth 5 -name '*.app' -path '*/release/bundle/macos/*' -print -quit)"
    [ -n "$b" ] || return 1
    local S=""; [ ! -w /Applications ] && { S=sudo; sudo -v || return 1; }
    quit_if_running; $S rm -rf "/Applications/${APP}.app"
    $S ditto "$b" "/Applications/${APP}.app"
    $S xattr -dr com.apple.quarantine "/Applications/${APP}.app" 2>/dev/null || true
    DONE_HINT="open -a \"$APP\""
  else
    local ai; ai="$(find "$src/src-tauri/target" -name '*.AppImage' -print -quit)"
    [ -n "$ai" ] || return 1
    mkdir -p "${HOME}/.local/bin"
    cp "$ai" "${HOME}/.local/bin/PvZ2-Gardendless.AppImage"; chmod +x "${HOME}/.local/bin/PvZ2-Gardendless.AppImage"
    DONE_HINT="${HOME}/.local/bin/PvZ2-Gardendless.AppImage"; LAUNCH_BIN="$DONE_HINT"
  fi
  ok "Installed"
}

install_with_fallback() {
  if "install_$1"; then return 0; fi
  warn "Install failed."
  [ "$INTERACTIVE" = 1 ] && confirm "Build from source instead? [Y/n]" "Y" && build_from_source && return 0
  return 1
}

launch_app() {
  [ -n "${PVZGE_NO_LAUNCH:-}" ] && return 0
  [ "$OS" = Darwin ] && { open -a "$APP" 2>/dev/null || true; return; }
  [ -n "${LAUNCH_BIN:-}" ] && { (setsid "$LAUNCH_BIN" >/dev/null 2>&1 &) 2>/dev/null || true; }
}

finish() {
  cls; echo ""
  m; printf '%s✓ %s%s is ready%s\n\n' "$G" "$B" "$APP" "$R"
  [ -n "${DONE_HINT:-}" ] && { m; printf '%s$ %s%s\n\n' "$D" "${DONE_HINT}" "$R"; }
  hr
  dim "Game by Gaozih · Port by Marcus Nguyen"
  echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
  OS="$(uname -s)"; ARCH="$(uname -m)"
  case "$OS" in Darwin) PLATFORM=macOS;; Linux) PLATFORM=Linux;; *) die "Unsupported: $OS";; esac

  cls; echo ""
  m; printf '%s%sPvZ2 Gardendless%s\n' "$B$G" "" "$R"
  m; printf '%s%s · %s%s\n' "$D" "$PLATFORM" "$ARCH" "$R"
  echo ""
  local cur; cur="$(installed_version)"
  [ -n "$cur" ] && { m; printf 'Installed  %s%s%s\n' "$G" "$cur" "$R"; } || { m; printf 'Installed  %s—%s\n' "$D" "$R"; }

  ACTION="${PVZGE_ACTION:-}"
  if [ "$ACTION" != uninstall ]; then
    m; printf 'Latest     %sfetching...%s' "$D" "$R"
    resolve_release
    printf '\r'; m; printf 'Latest     %s%s%s\n' "$G" "$VERSION" "$R"
  fi
  echo ""
  hr
  echo ""

  if [ -z "$ACTION" ] && [ "$INTERACTIVE" = 1 ]; then
    local one="Install"; [ -n "$cur" ] && one="Update"
    local sel
    choose sel \
      "$one"       "Download latest release" \
      "Reinstall"  "Force clean re-download" \
      "Uninstall"  "Remove app and data" \
      "Build"      "Compile from source" \
      "Help"       "Environment overrides" \
      "Quit"       ""
    case $sel in
      0) ACTION=update ;;
      1) ACTION=reinstall; PVZGE_FORCE=1 ;;
      2) ACTION=uninstall ;;
      3) ACTION=build ;;
      4) cls; echo ""
         m; printf '%s%sEnvironment overrides%s\n\n' "$B" "$W" "$R"
         m; printf '%sPVZGE_ACTION%s     install|build|uninstall\n' "$C" "$R"
         m; printf '%sPVZGE_VERSION%s    pin release (v0.8.2)\n' "$C" "$R"
         m; printf '%sPVZGE_FORCE%s      reinstall if current\n' "$C" "$R"
         m; printf '%sPVZGE_ARCH%s       x86_64|arm64|universal\n' "$C" "$R"
         m; printf '%sPVZGE_NO_LAUNCH%s  skip auto-open\n' "$C" "$R"
         m; printf '%sNO_COLOR%s         disable colors\n' "$C" "$R"
         echo ""
         hr
         dim "Game by Gaozih · Port by Marcus Nguyen"
         dim "github.com/$REPO"
         echo ""
         exit 0 ;;
      5) exit 0 ;;
    esac
  fi
  [ -z "$ACTION" ] && ACTION=update

  case "$ACTION" in
    uninstall) uninstall ;;
    build) build_from_source && { finish; launch_app; } ;;
    *) install_with_fallback "$([ "$OS" = Darwin ] && echo macos || echo linux)" && { finish; launch_app; } ;;
  esac
}

main "$@"
