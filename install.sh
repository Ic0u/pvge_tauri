#!/usr/bin/env bash
# PvZ2 Gardendless — game installer · updater · uninstaller
# curl -fsSL https://raw.githubusercontent.com/Ic0u/pvge_tauri/main/install.sh | bash
set -euo pipefail

REPO="Ic0u/pvge_tauri"
APP="PvZ2 Gardendless"
APP_ID="com.pvzge.desktop"
MARKER="${HOME}/.local/share/pvzge/version"

# ── Terminal capabilities ────────────────────────────────────────────────
ESC=$'\x1b'
CAN_TTY=0
[ -t 1 ] && CAN_TTY=1
CAN_CLEAR="$CAN_TTY"
USE_COLOR=0
[ "$CAN_TTY" = 1 ] && [ -z "${NO_COLOR:-}" ] && USE_COLOR=1
USE_ICONS=0
case "${PVZGE_ICONS:-1}" in
  0|false|FALSE|no|NO|off|OFF) USE_ICONS=0 ;;
  *) [ "$CAN_TTY" = 1 ] && USE_ICONS=1 ;;
esac

if [ "$CAN_TTY" = 1 ]; then
  CIVIS=$'\033[?25l' CNORM=$'\033[?25h' EL=$'\033[2K'
else
  CIVIS='' CNORM='' EL=''
fi

if [ "$USE_COLOR" = 1 ]; then
  R=$'\033[0m' B=$'\033[1m' D=$'\033[2m'
  G1=$'\033[38;5;154m' G2=$'\033[38;5;118m' G3=$'\033[38;5;82m'
  G4=$'\033[38;5;76m'  G5=$'\033[38;5;34m'  G6=$'\033[38;5;28m' G7=$'\033[38;5;22m'
  C=$'\033[38;5;76m'   RD=$'\033[31m' YL=$'\033[33m'
else
  R='' B='' D='' G1='' G2='' G3='' G4='' G5='' G6='' G7='' C='' RD='' YL=''
fi

INTERACTIVE=0
[ -z "${PVZGE_YES:-}" ] && [ -r /dev/tty ] && [ -t 1 ] && INTERACTIVE=1

# ── Layout ───────────────────────────────────────────────────────────────
MARGIN="  "
p() { :; }

# ── Output helpers ───────────────────────────────────────────────────────
msg()  { p; printf '%s▸%s %s\n'  "$C"  "$R" "$*"; }
good() { p; printf '%s✓%s %s\n'  "$G1" "$R" "$*"; }
bad()  { p; printf '%s!%s %s\n'  "$YL" "$R" "$*"; }
dim()  { p; printf '%s%s%s\n'    "$D"  "$*" "$R"; }
cls()  { [ "$CAN_CLEAR" = 1 ] && printf '\033[2J\033[H' || true; }
start_phase() { cls; }

# ── Cleanup ──────────────────────────────────────────────────────────────
TMP="" MOUNTED_DMG="" DOWNLOAD_PID=""
cleanup() {
  printf '%s' "$CNORM" 2>/dev/null || true
  stty echo 2>/dev/null || true
  [ -n "$DOWNLOAD_PID" ] && kill "$DOWNLOAD_PID" 2>/dev/null || true
  [ -n "$MOUNTED_DMG" ] && hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null || true
  [ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ── Clean banner (flowing — printed once, no absolute positioning) ───────
banner() {
  echo ""
  printf '%s%s%s%s%s\n' "$MARGIN" "$B" "$G1" "$APP" "$R"
  printf '%s%s%s · %s%s\n' "$MARGIN" "$G4" "$PLATFORM" "$ARCH" "$R"
  local cur; cur="$(installed_version)"
  printf '%s%sInstalled  %s' "$MARGIN" "$G4" "$R"; [ -n "$cur" ] && { printf '%s%s%s\n' "$G1" "$cur" "$R"; } || { printf '%s—%s\n' "$D" "$R"; }
  printf '%s%sLatest     %s%s%s%s\n' "$MARGIN" "$G4" "$R" "$G1" "${VERSION:-…}" "$R"
  echo ""
  printf '%s%s────────────────────────────────────────%s\n' "$MARGIN" "$D" "$R"
  echo ""
}

intro_load() {
  [ "$INTERACTIVE" = 1 ] || return 0
  start_phase
  echo ""
  printf '%s%s%s%s%s\n' "$MARGIN" "$B" "$G1" "$APP" "$R"
  printf '%s%s%s · %s · game installer%s\n\n' "$MARGIN" "$G4" "$PLATFORM" "$ARCH" "$R"
  printf '%s' "$CIVIS"

  local step n=0 steps=("Reading latest release" "Checking local game" "Preparing menu")
  for step in "${steps[@]}"; do
    n=$((n+1))
    printf '\r%s' "$EL"
    printf '%s%s[%s/3]%s %s' "$MARGIN" "$G5" "$n" "$R" "$step"
    sleep 0.14
  done

  printf '\r%s' "$EL"
  printf '%s%sReady%s' "$MARGIN" "$G1" "$R"
  sleep 0.18
  printf '\r%s' "$EL"
  printf '%s' "$CNORM"
}

phase_header() {
  local title="$1" detail="${2:-}"
  local icon title_cell
  icon="$(menu_icon "$title")"
  title_cell="$title"; [ -n "$icon" ] && title_cell="$icon $title"
  echo ""
  p; printf '%s%s%s%s\n' "$MARGIN" "$B$G1" "$title_cell" "$R"
  [ -n "$detail" ] && { p; printf '%s%s%s\n' "$MARGIN" "$D$detail" "$R"; }
  p; printf '%s%s────────────────────────────────────────%s\n\n' "$MARGIN" "$D" "$R"
}

phase_detail() {
  p; printf '%s%s%-11s%s %s\n' "$MARGIN" "$G4" "$1" "$R" "$2"
}

phase_path() {
  p; printf '%s%s%-11s%s %s\n' "$MARGIN" "$G4" "$1" "$R" "$2"
}

phase_step() {
  p; printf '%s%s%-11s%s %s\n' "$MARGIN" "$G5" "$1" "$R" "$2"
}

phase_note() {
  p; printf '%s%s%s%s\n' "$MARGIN" "$D" "$1" "$R"
}

menu_icon() {
  [ "$USE_ICONS" = 1 ] || return 0
  case "$1" in
    Install|Update) printf '󰏔' ;;
    Reinstall) printf '󰑓' ;;
    Uninstall) printf '󰩺' ;;
    Build) printf '󰙲' ;;
    Help) printf '󰋖' ;;
    Menu) printf '󰍜' ;;
    Launch) printf '󰐊' ;;
    Finish) printf '󰄬' ;;
    Quit) printf '󰗼' ;;
    *) return 0 ;;
  esac
}

quit_screen() {
  start_phase
  phase_header "Quit" "Game installer closed"
  phase_detail "State" "No further actions"
  phase_note "Re-run the installer any time to update, repair, or remove the game."
  echo ""
}

# ── Arrow-key menu (flowing; redraws only its own lines, never a new screen)
SELECTED=0
menu() {
  local labels=() descs=() all=("$@") i=0
  while [ $i -lt ${#all[@]} ]; do labels+=("${all[$i]}"); descs+=("${all[$((i+1))]}"); i=$((i+2)); done
  local n=${#labels[@]}
  SELECTED=0

  if [ "$INTERACTIVE" = 0 ]; then SELECTED=0; return; fi

  printf '%s' "$CIVIS"; stty -echo 2>/dev/null || true
  while true; do
    i=0
    while [ $i -lt $n ]; do
      local label_cell="${labels[$i]}"
      [ "$USE_ICONS" = 1 ] && label_cell="$(menu_icon "${labels[$i]}") ${labels[$i]}"
      printf '\r%s' "$EL"   # CR to col 0, then clear the whole line
      if [ $i -eq $SELECTED ]; then
        printf '%s%s▸ %-13s%s' "$MARGIN" "$G1$B" "$label_cell" "$R"
        [ -n "${descs[$i]}" ] && printf '  %s%s%s' "$G4" "${descs[$i]}" "$R"
        printf '\n'
      else
        printf '%s  %s%-13s%s' "$MARGIN" "$D" "$label_cell" "$R"
        [ -n "${descs[$i]}" ] && printf '  %s%s%s' "$D" "${descs[$i]}" "$R"
        printf '\n'
      fi
      i=$((i+1))
    done
    printf '\r%s\n' "$EL"
    printf '\r%s' "$EL"; printf '%s%s↑↓%s Navigate  %s⏎%s Select  %sq%s Quit' "$MARGIN" "$G5" "$R" "$G5" "$R" "$G5" "$R"

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
      stty echo 2>/dev/null || true; printf '%s\n' "$CNORM"; quit_screen; exit 0
    elif [ "$key" = k ]; then SELECTED=$(( SELECTED>0 ? SELECTED-1 : n-1 ))
    elif [ "$key" = j ]; then SELECTED=$(( SELECTED<n-1 ? SELECTED+1 : 0 ))
    fi
    # Move cursor back up over the n options plus the helper gap.
    printf '\r\033[%dA' "$((n+1))"
  done
  stty echo 2>/dev/null || true; printf '%s' "$CNORM"
  echo ""
}

# ── Spinner ──────────────────────────────────────────────────────────────
spin() {
  local m="$1"; shift
  [ "$CAN_TTY" = 0 ] && { "$@"; return $?; }
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
confirm_destructive() {
  if [ "$INTERACTIVE" = 0 ]; then
    [ -n "${PVZGE_YES:-}" ] && return 0
    bad "Set PVZGE_YES=1 to remove the game."
    return 1
  fi
  confirm "$@"
}

# ── GitHub API ───────────────────────────────────────────────────────────
json_assets() { printf '%s' "$RELEASE_JSON" | grep -o '"browser_download_url"[^,]*' | sed 's/.*"://;s/"//g;s/ //g'; }
pick() { json_assets | grep -F "$1" | grep -i "${2}\$" | head -1; }
human_size() {
  local n; n="\"$(basename "$1")\""
  printf '%s' "$RELEASE_JSON" | awk -v n="$n" 'index($0,n){f=1} f&&/"size":/{gsub(/[^0-9]/,"");print;exit}' \
    | awk '{if($1>1e9)printf"%.1f GB",$1/1e9;else printf"%d MB",$1/1e6}'
}
asset_size_bytes() {
  local n; n="\"$(basename "$1")\""
  printf '%s' "$RELEASE_JSON" | awk -v n="$n" 'index($0,n){f=1} f&&/"size":/{gsub(/[^0-9]/,"");print;exit}'
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
path_exists() { [ -e "$1" ] || [ -L "$1" ]; }
remove_glob() {
  local item
  for item in "$@"; do
    path_exists "$item" || continue
    rm -rf "$item" 2>/dev/null || true
  done
}
has_macos_game_data() {
  path_exists "/Applications/${APP}.app" ||
  path_exists "${HOME}/Library/Application Support/${APP_ID}" ||
  path_exists "${HOME}/Library/Caches/${APP_ID}" ||
  path_exists "${HOME}/Library/WebKit/${APP_ID}" ||
  path_exists "${HOME}/Library/HTTPStorages/${APP_ID}" ||
  path_exists "${HOME}/Library/Preferences/${APP_ID}.plist" ||
  path_exists "${HOME}/Library/Saved Application State/${APP_ID}.savedState" ||
  path_exists "$(dirname "$MARKER")"
}
has_linux_game_data() {
  path_exists "$MARKER" ||
  path_exists "${HOME}/.local/bin/PvZ2-Gardendless.AppImage" ||
  path_exists "${HOME}/.local/share/applications/${APP_ID}.desktop" ||
  path_exists "${HOME}/.config/${APP_ID}" ||
  path_exists "${HOME}/.cache/${APP_ID}" ||
  path_exists "${HOME}/.local/share/${APP_ID}" ||
  path_exists "${HOME}/.config/pvzge" ||
  path_exists "${HOME}/.cache/pvzge" ||
  path_exists "${HOME}/.local/share/pvzge"
}
wipe_macos_game_data() {
  remove_glob \
    "${HOME}/Library/Application Support/${APP_ID}" \
    "${HOME}/Library/Application Support/${APP}" \
    "${HOME}/Library/Application Support/pvzge" \
    "${HOME}/Library/Caches/${APP_ID}" \
    "${HOME}/Library/Caches/${APP}" \
    "${HOME}/Library/Caches/pvzge" \
    "${HOME}/Library/WebKit/${APP_ID}" \
    "${HOME}/Library/WebKit/${APP}" \
    "${HOME}/Library/HTTPStorages/${APP_ID}" \
    "${HOME}/Library/HTTPStorages/${APP_ID}.binarycookies" \
    "${HOME}/Library/Cookies/${APP_ID}.binarycookies" \
    "${HOME}/Library/Preferences/${APP_ID}.plist" \
    "${HOME}/Library/Preferences/${APP}.plist" \
    "${HOME}/Library/Saved Application State/${APP_ID}.savedState" \
    "${HOME}/Library/Saved Application State/${APP}.savedState" \
    "${HOME}/Library/Containers/${APP_ID}" \
    "${HOME}/Library/Application Scripts/${APP_ID}" \
    "${HOME}/Library/Group Containers/${APP_ID}" \
    "${HOME}/Library/LaunchAgents/${APP_ID}.plist" \
    "${HOME}/Library/Logs/${APP_ID}" \
    "${HOME}/Library/Logs/${APP}" \
    "$(dirname "$MARKER")"
  remove_glob "${HOME}/Library/Preferences/ByHost/${APP_ID}."*.plist
  remove_glob "${HOME}/Library/Logs/DiagnosticReports/${APP}"_*.crash
  remove_glob "${HOME}/Library/Logs/DiagnosticReports/${APP}"_*.ips
  remove_glob "${HOME}/Library/Logs/DiagnosticReports/${APP}"_*.diag
}
wipe_linux_game_data() {
  remove_glob \
    "${HOME}/.local/bin/PvZ2-Gardendless.AppImage" \
    "${HOME}/.local/share/applications/${APP_ID}.desktop" \
    "${HOME}/.local/share/applications/PvZ2-Gardendless.desktop" \
    "${HOME}/.local/share/applications/pvzge.desktop" \
    "${HOME}/.config/${APP_ID}" \
    "${HOME}/.cache/${APP_ID}" \
    "${HOME}/.local/share/${APP_ID}" \
    "${HOME}/.config/${APP}" \
    "${HOME}/.cache/${APP}" \
    "${HOME}/.local/share/${APP}" \
    "${HOME}/.config/pvzge" \
    "${HOME}/.cache/pvzge" \
    "${HOME}/.local/share/pvzge" \
    "$(dirname "$MARKER")"
}
wipe_game_data() {
  [ "$OS" = Darwin ] && wipe_macos_game_data || wipe_linux_game_data
  good "Old game data removed"
}
show_removal_targets() {
  if [ "$OS" = Darwin ]; then
    phase_path "Bundle" "/Applications/${APP}.app"
    phase_path "Support" "${HOME}/Library/Application Support/${APP_ID}"
    phase_path "Support" "${HOME}/Library/Application Support/${APP}"
    phase_path "Support" "${HOME}/Library/Application Support/pvzge"
    phase_path "Cache" "${HOME}/Library/Caches/${APP_ID}"
    phase_path "Cache" "${HOME}/Library/Caches/${APP}"
    phase_path "Cache" "${HOME}/Library/Caches/pvzge"
    phase_path "WebKit" "${HOME}/Library/WebKit/${APP_ID}"
    phase_path "WebKit" "${HOME}/Library/WebKit/${APP}"
    phase_path "Storage" "${HOME}/Library/HTTPStorages/${APP_ID}"
    phase_path "Storage" "${HOME}/Library/HTTPStorages/${APP_ID}.binarycookies"
    phase_path "Cookies" "${HOME}/Library/Cookies/${APP_ID}.binarycookies"
    phase_path "Prefs" "${HOME}/Library/Preferences/${APP_ID}.plist"
    phase_path "Prefs" "${HOME}/Library/Preferences/${APP}.plist"
    phase_path "Prefs" "${HOME}/Library/Preferences/ByHost/${APP_ID}.*.plist"
    phase_path "State" "${HOME}/Library/Saved Application State/${APP_ID}.savedState"
    phase_path "State" "${HOME}/Library/Saved Application State/${APP}.savedState"
    phase_path "Container" "${HOME}/Library/Containers/${APP_ID}"
    phase_path "Scripts" "${HOME}/Library/Application Scripts/${APP_ID}"
    phase_path "Group" "${HOME}/Library/Group Containers/${APP_ID}"
    phase_path "Agent" "${HOME}/Library/LaunchAgents/${APP_ID}.plist"
    phase_path "Logs" "${HOME}/Library/Logs/${APP_ID}"
    phase_path "Logs" "${HOME}/Library/Logs/${APP}"
    phase_path "Crash" "${HOME}/Library/Logs/DiagnosticReports/${APP}_*.crash"
    phase_path "Crash" "${HOME}/Library/Logs/DiagnosticReports/${APP}_*.ips"
    phase_path "Crash" "${HOME}/Library/Logs/DiagnosticReports/${APP}_*.diag"
    phase_path "Marker" "$(dirname "$MARKER")"
  else
    phase_path "Game" "${HOME}/.local/bin/PvZ2-Gardendless.AppImage"
    phase_path "Desktop" "${HOME}/.local/share/applications/${APP_ID}.desktop"
    phase_path "Desktop" "${HOME}/.local/share/applications/PvZ2-Gardendless.desktop"
    phase_path "Desktop" "${HOME}/.local/share/applications/pvzge.desktop"
    phase_path "Config" "${HOME}/.config/${APP_ID}"
    phase_path "Config" "${HOME}/.config/${APP}"
    phase_path "Config" "${HOME}/.config/pvzge"
    phase_path "Cache" "${HOME}/.cache/${APP_ID}"
    phase_path "Cache" "${HOME}/.cache/${APP}"
    phase_path "Cache" "${HOME}/.cache/pvzge"
    phase_path "Data" "${HOME}/.local/share/${APP_ID}"
    phase_path "Data" "${HOME}/.local/share/${APP}"
    phase_path "Data" "${HOME}/.local/share/pvzge"
  fi
}
is_installed() {
  [ "$OS" = Darwin ] && has_macos_game_data && return 0
  [ "$OS" != Darwin ] && has_linux_game_data && return 0
  return 1
}
quit_if_running() {
  pgrep -f "$APP" >/dev/null 2>&1 || return 0
  msg "Closing game..."
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
download_backend() {
  local wanted="${PVZGE_DOWNLOADER:-auto}"
  case "$wanted" in
    aria2|aria2c) command -v aria2c >/dev/null 2>&1 && printf 'aria2c' || printf 'curl' ;;
    curl) printf 'curl' ;;
    auto|'') command -v aria2c >/dev/null 2>&1 && printf 'aria2c' || printf 'curl' ;;
    *) command -v aria2c >/dev/null 2>&1 && printf 'aria2c' || printf 'curl' ;;
  esac
}
curl_download() {
  local url="$1" dest="$2"
  curl -fSL --retry 5 --retry-all-errors -C - --progress-bar "$url" -o "$dest"
}
bytes_label() {
  local n="${1:-0}"
  awk -v n="$n" 'BEGIN {
    if (n >= 1073741824) printf "%.1fGB", n / 1073741824;
    else if (n >= 1048576) printf "%.1fMB", n / 1048576;
    else if (n >= 1024) printf "%.1fKB", n / 1024;
    else printf "%dB", n;
  }'
}
time_label() {
  local s="${1:-0}"
  case "$s" in ''|*[!0-9]*) s=0 ;; esac
  if [ "$s" -ge 3600 ]; then
    printf '%dh%02dm' "$((s / 3600))" "$(((s % 3600) / 60))"
  elif [ "$s" -ge 60 ]; then
    printf '%dm%02ds' "$((s / 60))" "$((s % 60))"
  else
    printf '%ss' "$s"
  fi
}
file_bytes() {
  [ -f "$1" ] || { printf '0'; return; }
  wc -c < "$1" | tr -d ' '
}
draw_download_progress() {
  [ "$CAN_TTY" = 1 ] || return 0
  local done="$1" total="$2" started="${3:-$(date +%s)}" now elapsed speed eta
  local width=20 filled empty i bar="" gap=""
  case "$done" in ''|*[!0-9]*) done=0 ;; esac
  case "$total" in ''|*[!0-9]*) return 0 ;; esac
  [ "$total" -gt 0 ] || return 0
  [ "$done" -gt "$total" ] && done="$total"
  now="$(date +%s)"
  elapsed=$((now - started)); [ "$elapsed" -lt 1 ] && elapsed=1
  speed=$((done / elapsed))
  [ "$speed" -gt 0 ] && eta=$(((total - done) / speed)) || eta=0
  local pct=$((done * 100 / total))
  filled=$((pct * width / 100))
  empty=$((width - filled))
  i=0; while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i+1)); done
  i=0; while [ "$i" -lt "$empty" ]; do gap="${gap}░"; i=$((i+1)); done
  printf '\r%s' "$EL"
  printf '%s%s[%s%s%s%s] %3d%%  %s/%s  %s/s  eta %s%s' \
    "$MARGIN" "$G5" "$bar" "$D" "$gap" "$G5" "$pct" \
    "$(bytes_label "$done")" "$(bytes_label "$total")" \
    "$(bytes_label "$speed")" "$(time_label "$eta")" "$R"
}
aria2_download() {
  local url="$1" dest="$2" total="${3:-}" rc=0
  local log="${dest}.aria2.log" started
  aria2c \
    --quiet=true \
    --allow-overwrite=true \
    --auto-file-renaming=false \
    --continue=true \
    --file-allocation=none \
    --max-tries=5 \
    --retry-wait=2 \
    --timeout=30 \
    --connect-timeout=20 \
    --summary-interval=0 \
    --show-console-readout=false \
    --console-log-level=error \
    -d "$(dirname "$dest")" \
    -o "$(basename "$dest")" \
    "$url" >"$log" 2>&1 &
  DOWNLOAD_PID=$!

  if [ "$CAN_TTY" = 1 ] && [ -n "$total" ]; then
    printf '%s' "$CIVIS"
    started="$(date +%s)"
    while kill -0 "$DOWNLOAD_PID" 2>/dev/null; do
      draw_download_progress "$(file_bytes "$dest")" "$total" "$started"
      sleep 0.15
    done
  fi

  wait "$DOWNLOAD_PID" || rc=$?
  [ -n "$total" ] && [ "$CAN_TTY" = 1 ] && draw_download_progress "$(file_bytes "$dest")" "$total" "${started:-$(date +%s)}"
  [ "$CAN_TTY" = 1 ] && printf '%s\n' "$CNORM"
  DOWNLOAD_PID=""
  rm -f "$log" 2>/dev/null || true
  return "$rc"
}
download_asset() {
  local url="$1" dest="$2"
  local backend requested total
  requested="${PVZGE_DOWNLOADER:-auto}"
  backend="$(download_backend)"
  total="$(asset_size_bytes "$url")"
  case "$requested" in auto|aria2|aria2c|curl|'') ;; *) bad "Unknown downloader: $requested; using $backend";; esac
  phase_detail "Package" "$(basename "$url")"
  phase_detail "Size" "$(human_size "$url")"
  if [ "$backend" = aria2c ]; then
    phase_detail "Method" "aria2c · progress"
  else
    phase_detail "Method" "curl · progress bar"
    case "$requested" in aria2|aria2c) bad "aria2c unavailable; using curl";; esac
  fi
  msg "Downloading package"
  if [ "$backend" = aria2c ]; then
    aria2_download "$url" "$dest" "$total" || {
      bad "aria2c failed; using curl"
      curl_download "$url" "$dest" || return 1
    }
  else
    curl_download "$url" "$dest" || return 1
  fi
  good "Downloaded"
}

# ── Install / Uninstall / Build ──────────────────────────────────────────
install_macos() {
  phase_step "1/4" "Resolve release package"
  local url; url="$(pick_macos_dmg)"
  [ -n "$url" ] || { bad "No macOS build in $VERSION"; return 1; }
  phase_detail "Version" "$VERSION"
  phase_detail "Platform" "$PLATFORM · $ARCH"
  phase_detail "Target" "/Applications/${APP}.app"
  [ "${ACTION:-}" = reinstall ] && phase_detail "Mode" "Fresh install"
  local dest="/Applications/${APP}.app"
  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION:-}" != reinstall ] && [ -d "$dest" ]; then
    local cur; cur="$(installed_version)"
    [ -n "$cur" ] && [ "$cur" = "$VERSION" ] && { good "Already up to date ($cur)"; DONE_HINT="open -a \"$APP\""; return 0; }
    [ -n "$cur" ] && msg "Updating $cur → $VERSION"
  fi
  TMP="$(mktemp -d)"
  echo ""
  phase_step "2/4" "Download package"
  download_asset "$url" "$TMP/pvzge.dmg" || return 1
  echo ""
  phase_step "3/4" "Mount disk image"
  msg "Mounting image"
  local out; out="$(hdiutil attach -nobrowse -noverify -noautoopen -readonly "$TMP/pvzge.dmg" 2>/dev/null)" || return 1
  MOUNTED_DMG="$(printf '%s' "$out" | grep -Eo '/Volumes/[^[:cntrl:]]*' | tail -1)"
  local app_src; app_src="$(find "$MOUNTED_DMG" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null)"
  [ -n "$app_src" ] || { bad "No .app in image"; return 1; }
  good "Mounted"
  echo ""
  phase_step "4/4" "Install game"
  local S=""; [ ! -w /Applications ] && { S=sudo; sudo -v || return 1; }
  quit_if_running
  [ "${ACTION:-}" = reinstall ] && { msg "Cleaning old data"; wipe_game_data; }
  [ -d "$dest" ] && $S rm -rf "$dest"
  spin "Installing" $S ditto "$app_src" "$dest" || return 1
  hdiutil detach "$MOUNTED_DMG" -quiet 2>/dev/null; MOUNTED_DMG=""
  good "Installed"
  $S xattr -dr com.apple.quarantine "$dest" 2>/dev/null && good "Gatekeeper bypassed" || bad "Strip quarantine manually"
  rm -rf "$TMP" 2>/dev/null; TMP=""
  DONE_HINT="open -a \"$APP\""
}
install_linux() {
  phase_step "1/3" "Resolve release package"
  local asset_arch url kind
  case "$ARCH" in
    x86_64) asset_arch=x86_64 ;;
    arm64|aarch64) asset_arch=aarch64 ;;
    *) bad "Unsupported Linux architecture: $ARCH"; return 1 ;;
  esac
  if [ -n "$(pick "Linux-${asset_arch}" .deb||true)" ] && command -v dpkg >/dev/null; then url="$(pick "Linux-${asset_arch}" .deb)"; kind=deb
  elif [ -n "$(pick "Linux-${asset_arch}" .AppImage||true)" ]; then url="$(pick "Linux-${asset_arch}" .AppImage)"; kind=appimage
  else bad "No Linux build"; return 1; fi
  phase_detail "Version" "$VERSION"
  phase_detail "Format" "$kind"
  phase_detail "Platform" "$PLATFORM · $ARCH"
  [ "${ACTION:-}" = reinstall ] && phase_detail "Mode" "Fresh install"
  if [ -z "${PVZGE_FORCE:-}" ] && [ "${ACTION:-}" != reinstall ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$VERSION" ]; then good "Already up to date ($VERSION)"; return 0; fi
  echo ""
  phase_step "2/3" "Download package"
  TMP="$(mktemp -d)"; download_asset "$url" "$TMP/pkg" || return 1
  echo ""
  phase_step "3/3" "Install package"
  [ "${ACTION:-}" = reinstall ] && { msg "Cleaning old data"; wipe_game_data; }
  if [ "$kind" = deb ]; then spin "Installing" sudo dpkg -i "$TMP/pkg" || { sudo apt-get -yf install || return 1; }
    DONE_HINT=pvzge; LAUNCH_BIN="$(command -v pvzge 2>/dev/null || echo pvzge)"
  else mkdir -p "${HOME}/.local/bin"; local t="${HOME}/.local/bin/PvZ2-Gardendless.AppImage"
    mv "$TMP/pkg" "$t"; chmod +x "$t"; DONE_HINT="$t"; LAUNCH_BIN="$t"; fi
  good "Installed"; rm -rf "$TMP" 2>/dev/null; TMP=""
  mkdir -p "$(dirname "$MARKER")"; printf '%s' "$VERSION" >"$MARKER" 2>/dev/null || true
}
uninstall() {
  is_installed || { bad "Nothing to remove."; return 0; }
  phase_step "1/3" "Files to remove"
  show_removal_targets
  echo ""
  phase_step "2/3" "Confirm removal"
  confirm_destructive "Remove ${APP} completely? [y/N]" "N" || { msg "Cancelled."; return 0; }; echo ""
  phase_step "3/3" "Remove files"
  msg "Removing game"
  if [ "$OS" = Darwin ]; then quit_if_running; local S=""; [ ! -w /Applications ] && { S=sudo; sudo -v || return 1; }
    $S rm -rf "/Applications/${APP}.app"
    wipe_game_data
  else command -v dpkg >/dev/null && dpkg -s pvzge >/dev/null 2>&1 && sudo apt-get -y remove pvzge 2>/dev/null || true
    wipe_game_data; fi
  good "${APP} removed."
}
build_from_source() {
  phase_step "1/4" "Check toolchain"
  phase_detail "Source" "github.com/$REPO"
  phase_detail "Target" "$PLATFORM · $ARCH"
  msg "Checking build tools"
  for t in git cargo node; do command -v "$t" >/dev/null || { bad "Missing: $t"; return 1; }; done
  good "Build tools ready"
  local tc=""; command -v tauri >/dev/null && tc=tauri || { cargo tauri --version >/dev/null 2>&1 && tc="cargo tauri"; } || {
    msg "Installing Tauri CLI..."; cargo install tauri-cli --version "^2" >/dev/null 2>&1 && tc="cargo tauri" || return 1; }
  phase_detail "Builder" "$tc"
  echo ""
  phase_step "2/4" "Clone source"
  TMP="${TMP:-$(mktemp -d)}"; local src="$TMP/pvge"
  spin "Cloning" git clone --depth 1 "https://github.com/${REPO}.git" "$src" || return 1; good "Cloned"
  echo ""
  phase_step "3/4" "Compile bundle"
  msg "Compiling (may take several minutes)..."
  local bundle=app
  [ "$OS" = Linux ] && bundle=appimage
  (cd "$src/src-tauri" && $tc build --bundles "$bundle") || return 1; good "Built"
  echo ""
  phase_step "4/4" "Install built game"
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
  start_phase
  phase_header "Finish" "Game is ready"
  phase_detail "Game" "$APP"
  phase_detail "Version" "$VERSION"
  [ -n "${DONE_HINT:-}" ] && phase_detail "Launch" "$DONE_HINT"
  echo ""
  good "Complete"
  dim "   Game by Gaozih · Port by Marcus Nguyen"; echo ""
}
complete_success() {
  finish
  [ "${1:-0}" = 1 ] && launch_app
  return 0
}
show_help() {
  phase_header "Help" "Game installer flags and one-shot actions"
  phase_detail "Usage" "curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash"
  phase_detail "Repo" "github.com/$REPO"
  echo ""
  phase_step "Actions" "Run one phase without opening the menu"
  p; printf '%s%sPVZGE_ACTION%s     install|reinstall|build|uninstall|help\n' "$MARGIN" "$C" "$R"
  echo ""
  phase_step "Release" "Pin or force package selection"
  p; printf '%s%sPVZGE_VERSION%s    pin release (v0.9.3)\n' "$MARGIN" "$C" "$R"
  p; printf '%s%sPVZGE_FORCE%s      reinstall if current\n' "$MARGIN" "$C" "$R"
  p; printf '%s%sPVZGE_ARCH%s       x86_64|arm64|universal\n' "$MARGIN" "$C" "$R"
  echo ""
  phase_step "Download" "Choose download tool"
  p; printf '%s%sPVZGE_DOWNLOADER%s auto|aria2c|curl\n' "$MARGIN" "$C" "$R"
  echo ""
  phase_step "Display" "Tune terminal behavior"
  p; printf '%s%sPVZGE_NO_LAUNCH%s  skip auto-open\n' "$MARGIN" "$C" "$R"
  p; printf '%s%sPVZGE_ICONS%s      set 0 to disable Nerd Font icons\n' "$MARGIN" "$C" "$R"
  p; printf '%s%sNO_COLOR%s         disable colors\n\n' "$MARGIN" "$C" "$R"
  dim "   github.com/$REPO"; echo ""
}

choose_action() {
  start_phase
  banner
  local cur; cur="$(installed_version)"
  local one="Install"; [ -n "$cur" ] && one="Update"
  menu \
    "$one"       "Download latest" \
    "Reinstall"  "Fresh install" \
    "Uninstall"  "Remove game" \
    "Build"      "Compile from source" \
    "Help"       "Environment overrides" \
    "Quit"       ""
  case $SELECTED in
    0) ACTION=update ;;
    1) ACTION=reinstall; PVZGE_FORCE=1 ;;
    2) ACTION=uninstall ;;
    3) ACTION=build ;;
    4) ACTION=help ;;
    5) return 1 ;;
  esac
}

run_action() {
  local auto_launch="${1:-0}"
  local platform; platform="$([ "$OS" = Darwin ] && echo macos || echo linux)"
  case "$ACTION" in
    uninstall)
      start_phase
      phase_header "Uninstall" "Remove game and saved data"
      uninstall
      ;;
    build)
      start_phase
      phase_header "Build" "Compile from source and install locally"
      build_from_source && complete_success "$auto_launch"
      ;;
    help)
      start_phase
      show_help
      ;;
    reinstall)
      start_phase
      phase_header "Reinstall" "Fresh download and install"
      install_with_fallback "$platform" && complete_success "$auto_launch"
      ;;
    *)
      start_phase
      local cur title detail
      cur="$(installed_version)"
      title="Install"; detail="Download and install latest release"
      [ -n "$cur" ] && { title="Update"; detail="Download and install latest release"; }
      phase_header "$title" "$detail"
      install_with_fallback "$platform" && complete_success "$auto_launch"
      ;;
  esac
}

post_action_prompt() {
  local ok="${1:-0}"
  [ "$INTERACTIVE" = 1 ] || return 1
  echo ""
  phase_step "Next" "Choose what to do now"
  if [ "$ok" = 1 ] && [ -n "${DONE_HINT:-}" ] && [ -z "${PVZGE_NO_LAUNCH:-}" ] && [ "$ACTION" != uninstall ]; then
    menu \
      "Menu"    "Return to installer" \
      "Launch"  "Open game now" \
      "Quit"    ""
    case $SELECTED in
      0) return 0 ;;
      1) launch_app; return 1 ;;
      *) return 1 ;;
    esac
  fi
  menu \
    "Menu"  "Return to installer" \
    "Quit"  ""
  case $SELECTED in
    0) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
  OS="$(uname -s)"; ARCH="$(uname -m)"
  case "$OS" in Darwin) PLATFORM=macOS;; Linux) PLATFORM=Linux;; *) echo "Unsupported: $OS" >&2; exit 1;; esac
  resolve_release

  local env_action="${PVZGE_ACTION:-}"
  local env_force="${PVZGE_FORCE:-}"

  if [ -n "$env_action" ] || [ "$INTERACTIVE" = 0 ]; then
    ACTION="$env_action"
    if [ -z "$ACTION" ]; then
      ACTION=update
      echo ""; p; printf ' %s%s · %s%s\n' "$B" "$APP" "$VERSION" "$R"
    else
      start_phase
    fi
    run_action 1
    return $?
  fi

  intro_load

  while true; do
    DONE_HINT=""; LAUNCH_BIN=""
    if [ -n "$env_force" ]; then PVZGE_FORCE="$env_force"; else unset PVZGE_FORCE; fi
    choose_action || { quit_screen; exit 0; }
    local ok=0
    if run_action 0; then ok=1; else ok=0; fi
    post_action_prompt "$ok" || { quit_screen; exit 0; }
  done
}

main "$@"
