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
  RV=$'\033[7m' HI=$'\033[?25l' SH=$'\033[?25h' CL=$'\033[2J\033[H'
  TTY=1
else
  R='' B='' D='' C='' G='' W='' RD='' YL='' RV='' HI='' SH='' CL='' TTY=0
fi

# ── Helpers ──────────────────────────────────────────────────────────────
info() { printf ' %s▸%s %s\n'  "$C" "$R" "$*"; }
ok()   { printf ' %s✓%s %s\n'  "$G" "$R" "$*"; }
warn() { printf ' %s!%s %s\n'  "$YL" "$R" "$*"; }
die()  { printf '\n %s✗ %s%s\n' "$RD" "$*" "$R" >&2; exit 1; }
cls()  { [ "$TTY" = 1 ] && printf '%s' "$CL" || echo ""; }

INTERACTIVE=0
[ -z "${PVZGE_YES:-}" ] && [ -r /dev/tty ] && [ -t 1 ] && INTERACTIVE=1
confirm() {
  [ "$INTERACTIVE" = 0 ] && return 0
  printf ' %s%s%s ' "$C" "$1" "$R" >/dev/tty
  local a; IFS= read -r a </dev/tty || a=""
  case "${a:-$2}" in [yY]*) return 0;; *) return 1;; esac
}

# ── Arrow-key menu ───────────────────────────────────────────────────────
# Usage: choose <var> "label1" "desc1" "label2" "desc2" ...
choose() {
  local _var="$1"; shift
  local labels=() descs=() n=0
  while [ $# -ge 2 ]; do labels+=("$1"); descs+=("$2"); n=$((n+1)); shift 2; done
  [ "$INTERACTIVE" = 0 ] && { eval "$_var=0"; return; }

  local sel=0 key
  printf '%s' "$HI"
  while true; do
    # Draw options
    local i=0
    while [ $i -lt $n ]; do
      if [ $i -eq $sel ]; then
        printf '\r %s▸ %-14s %s%s\n' "$C" "${labels[$i]}" "${descs[$i]}" "$R"
      else
        printf '\r   %s%-14s %s%s%s\n' "$D" "${labels[$i]}" "${descs[$i]}" "$R" ""
      fi
      i=$((i+1))
    done
    printf '\n %s↑↓%s  Navigate   %sEnter%s  Select   %sq%s  Quit' "$D" "$R" "$D" "$R" "$D" "$R"
    # Read key
    IFS= read -rsn1 key </dev/tty
    if [ "$key" = $'\x1b' ]; then
      IFS= read -rsn2 key </dev/tty
      case "$key" in
        '[A') sel=$(( sel > 0 ? sel - 1 : n - 1 )) ;;
        '[B') sel=$(( sel < n - 1 ? sel + 1 : 0 )) ;;
      esac
    elif [ "$key" = "" ]; then
      break  # Enter
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      printf '%s\n' "$SH"; info "Bye!"; exit 0
    fi
    # Move cursor up to redraw
    printf '\033[%dA' "$((n + 1))"
  done
  printf '%s' "$SH"
  eval "$_var=$sel"
}

# ── Spinner ──────────────────────────────────────────────────────────────
spin() {
  local msg="$1"; shift
  [ "$TTY" = 0 ] && { "$@"; return $?; }
  "$@" &
  local pid=$! i=0 f='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  printf '%s' "$HI"
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r %s%s%s %s' "$C" "${f:$((i%10)):1}" "$R" "$msg"
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
    | awk '{if($1>1e9)printf"%.1fGB",$1/1e9;else printf"%dMB",$1/1e6}'
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

# ── Install macOS ────────────────────────────────────────────────────────
install_macos() {
  cls
  printf '\n %s%s · %s%s\n\n' "$B$W" "$APP" "$VERSION" "$R"

  local arch="$ARCH"
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ] && arch=arm64
  local url=""
  case "${PVZGE_ARCH:-auto}" in
    universal) url="$(pick macOS-Universal .dmg || true)" ;;
    x86_64)    url="$(pick macOS-x86_64 .dmg || true)" ;;
    arm64)     url="$(pick macOS-Apple-Silicon .dmg || true)" ;;
    *) url="$(pick macOS-Universal .dmg || true)"
       [ -z "$url" ] && { [ "$arch" = arm64 ] && url="$(pick macOS-Apple-Silicon .dmg || true)" || url="$(pick macOS-x86_64 .dmg || true)"; } ;;
  esac
  [ -n "$url" ] || { warn "No macOS build in $VERSION"; return 1; }

  local dest="/Applications/${APP}.app"
  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION:-}" != reinstall ] && [ -d "$dest" ]; then
    local cur; cur="$(installed_version)"
    [ -n "$cur" ] && [ "$cur" = "$VERSION" ] && { ok "Already up to date ($cur)"; DONE_HINT="open -a \"$APP\""; return 0; }
    [ -n "$cur" ] && info "Updating $cur → $VERSION"
  fi

  info "Downloading $(basename "$url")  ($(human_size "$url"))"
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
  printf '\n %s%s · %s%s\n\n' "$B$W" "$APP" "$VERSION" "$R"

  [ "$ARCH" = x86_64 ] || { warn "Only x86_64 Linux builds exist"; return 1; }
  local url kind
  if [ -n "$(pick Linux-x86_64 .deb || true)" ] && command -v dpkg >/dev/null; then
    url="$(pick Linux-x86_64 .deb)"; kind=deb
  elif [ -n "$(pick Linux-x86_64 .AppImage || true)" ]; then
    url="$(pick Linux-x86_64 .AppImage)"; kind=appimage
  else warn "No Linux build"; return 1; fi

  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION:-}" != reinstall ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$VERSION" ]; then
    ok "Already up to date ($VERSION)"; return 0
  fi

  info "Downloading $(basename "$url")  ($(human_size "$url"))"
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
  cls; printf '\n %s%sUninstall%s\n\n' "$B" "$RD" "$R"
  is_installed || { warn "Not installed."; return 0; }
  confirm "Remove ${APP} and all its data? [y/N]" "N" || { info "Cancelled."; return 0; }
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
  cls; printf '\n %s%sBuild from source%s\n\n' "$B" "$YL" "$R"
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
  cls
  printf '\n %s✓ %s%s is ready%s\n\n' "$G" "$B" "$APP" "$R"
  [ -n "${DONE_HINT:-}" ] && printf ' %s$ %s%s\n\n' "$D" "${DONE_HINT}" "$R"
  printf ' %sGame by Gaozih · Port by Marcus Nguyen%s\n\n' "$D" "$R"
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
  OS="$(uname -s)"; ARCH="$(uname -m)"
  case "$OS" in Darwin) PLATFORM=macOS;; Linux) PLATFORM=Linux;; *) die "Unsupported: $OS";; esac

  cls
  printf '\n %s%sPvZ2 Gardendless%s  %s%s · %s%s\n' "$B$G" "" "$R" "$D" "$PLATFORM" "$ARCH" "$R"
  local cur; cur="$(installed_version)"
  [ -n "$cur" ] && printf ' %sInstalled: %s%s%s\n' "$D" "$G" "$cur" "$R" || printf ' %sNot installed%s\n' "$D" "$R"

  ACTION="${PVZGE_ACTION:-}"
  if [ "$ACTION" != uninstall ]; then
    printf ' %sFetching latest release...%s' "$D" "$R"
    resolve_release
    printf '\r\033[K %sLatest:    %s%s%s\n' "$D" "$G" "$VERSION" "$R"
  fi
  echo ""

  if [ -z "$ACTION" ] && [ "$INTERACTIVE" = 1 ]; then
    local one="Install"; [ -n "$cur" ] && one="Update"
    local sel
    choose sel \
      "$one"      "Download latest release" \
      "Reinstall"  "Force clean re-download" \
      "Uninstall"  "Remove app and data" \
      "Build"      "Compile from source" \
      "Help"       "Show env overrides" \
      "Quit"       ""
    case $sel in
      0) ACTION=update ;;
      1) ACTION=reinstall; PVZGE_FORCE=1 ;;
      2) ACTION=uninstall ;;
      3) ACTION=build ;;
      4) cls; printf '\n %s%sEnvironment overrides%s\n\n' "$B" "$W" "$R"
         printf ' %sPVZGE_ACTION%s     install|build|uninstall\n' "$C" "$R"
         printf ' %sPVZGE_VERSION%s    pin release (e.g. v0.8.2)\n' "$C" "$R"
         printf ' %sPVZGE_FORCE%s      reinstall even if current\n' "$C" "$R"
         printf ' %sPVZGE_ARCH%s       universal|x86_64|arm64\n' "$C" "$R"
         printf ' %sPVZGE_NO_LAUNCH%s  skip auto-open\n' "$C" "$R"
         printf ' %sNO_COLOR%s         disable colors\n\n' "$C" "$R"
         printf ' %sGame by Gaozih & PvZ2GE Team · Port by Marcus Nguyen%s\n' "$D" "$R"
         printf ' %sgithub.com/%s%s\n\n' "$D" "$REPO" "$R"
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
