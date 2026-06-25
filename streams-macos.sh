#!/bin/bash

# ==========================================================
# RTSP Quad Viewer for macOS (Intel + Apple Silicon)
# Launches 4 ffplay RTSP/RTSPS streams in screen quadrants.
# Restarts all streams every hour.
#
# Uses the main display (menu bar screen) by default. To target
# another monitor, set TARGET_DISPLAY to its index (0-based):
#   TARGET_DISPLAY=2 ./streams-macos.sh
# ==========================================================

RESTART_SECONDS=3600

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/streams.conf}"

PIDS=()
STOPPING=0
SCRIPT_PID=$$

setup_brew_path() {
  # Homebrew lives in /opt/homebrew on Apple Silicon, /usr/local on Intel.
  for brew_prefix in /opt/homebrew /usr/local; do
    if [ -d "$brew_prefix/bin" ]; then
      PATH="$brew_prefix/bin:$PATH"
    fi
  done
  export PATH
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi

  STREAM_1="${STREAM_1:-}"
  STREAM_2="${STREAM_2:-}"
  STREAM_3="${STREAM_3:-}"
  STREAM_4="${STREAM_4:-}"
}

FFPLAY_OPTS=(
  -fflags nobuffer
  -flags low_delay
  -framedrop
  -an
  -loglevel warning
  -rtsp_transport tcp
  -noborder
)

cleanup() {
  echo "Stopping ffplay streams..."

  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
    fi
  done

  pkill -P "$SCRIPT_PID" -x ffplay 2>/dev/null

  sleep 1

  for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null
    fi
  done

  pkill -9 -P "$SCRIPT_PID" -x ffplay 2>/dev/null

  PIDS=()
}

shutdown() {
  STOPPING=1
  cleanup
  exit 0
}

interruptible_sleep() {
  local seconds="$1"
  local elapsed=0

  while [ "$elapsed" -lt "$seconds" ] && [ "$STOPPING" -eq 0 ]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done
}

get_screen_size() {
  local dims=""

  # NSScreen.main reports the display with the menu bar, not the combined
  # virtual desktop (Finder bounds span every connected monitor).
  if command -v swift >/dev/null 2>&1; then
    dims=$(swift - 2>/dev/null <<'SWIFT'
import Cocoa

let screens = NSScreen.screens
guard !screens.isEmpty else { exit(1) }

let targetIndex: Int? = ProcessInfo.processInfo.environment["TARGET_DISPLAY"].flatMap { Int($0) }

guard let main = NSScreen.main else { exit(1) }
let screen: NSScreen
if let idx = targetIndex, idx >= 0, idx < screens.count {
    screen = screens[idx]
} else {
    screen = main
}

let mainFrame = main.frame
let frame = screen.frame
let originX = Int(frame.origin.x - mainFrame.origin.x)
let originY = Int(mainFrame.maxY - frame.maxY)
let width = Int(frame.width)
let height = Int(frame.height)

print("\(width):\(height):\(originX):\(originY)")
SWIFT
)
  fi

  if [ -z "$dims" ]; then
    echo "Could not determine screen size."
    echo "Ensure at least one display is connected and you are in a logged-in desktop session."
    exit 1
  fi

  SCREEN_WIDTH=$(echo "$dims" | cut -d':' -f1 | tr -d '[:space:]')
  SCREEN_HEIGHT=$(echo "$dims" | cut -d':' -f2 | tr -d '[:space:]')
  SCREEN_ORIGIN_X=$(echo "$dims" | cut -d':' -f3 | tr -d '[:space:]')
  SCREEN_ORIGIN_Y=$(echo "$dims" | cut -d':' -f4 | tr -d '[:space:]')

  HALF_WIDTH=$((SCREEN_WIDTH / 2))
  HALF_HEIGHT=$((SCREEN_HEIGHT / 2))

  echo "Detected display: ${SCREEN_WIDTH}x${SCREEN_HEIGHT} at ${SCREEN_ORIGIN_X},${SCREEN_ORIGIN_Y}"
  echo "Quadrants: ${HALF_WIDTH}x${HALF_HEIGHT}"
}

reposition_window_macos() {
  local title="$1"
  local x="$2"
  local y="$3"
  local w="$4"
  local h="$5"

  if ! command -v osascript >/dev/null 2>&1; then
    return 0
  fi

  # Requires Accessibility permission for the terminal running this script.
  osascript <<EOF >/dev/null 2>&1
tell application "System Events"
  repeat with proc in (every process whose background only is false)
    try
      repeat with win in (every window of proc whose name contains "$title")
        set position of win to {$x, $y}
        set size of win to {$w, $h}
      end repeat
    end try
  end repeat
end tell
EOF
}

launch_and_place() {
  local title="$1"
  local url="$2"
  local x="$3"
  local y="$4"
  local w="$5"
  local h="$6"

  echo "Launching $title at ${x},${y} ${w}x${h}..."

  ffplay "${FFPLAY_OPTS[@]}" \
    -window_title "$title" \
    -left "$x" \
    -top "$y" \
    -x "$w" \
    -y "$h" \
    "$url" &

  PIDS+=("$!")

  sleep 1
  reposition_window_macos "$title" "$x" "$y" "$w" "$h"
}

launch_streams() {
  echo "Launching streams..."

  get_screen_size

  local x0=$SCREEN_ORIGIN_X
  local y0=$SCREEN_ORIGIN_Y
  local x1=$((SCREEN_ORIGIN_X + HALF_WIDTH))
  local y1=$((SCREEN_ORIGIN_Y + HALF_HEIGHT))

  launch_and_place "RTSP Quad 1" "$STREAM_1" "$x0" "$y0" "$HALF_WIDTH" "$HALF_HEIGHT"
  launch_and_place "RTSP Quad 2" "$STREAM_2" "$x1" "$y0" "$HALF_WIDTH" "$HALF_HEIGHT"
  launch_and_place "RTSP Quad 3" "$STREAM_3" "$x0" "$y1" "$HALF_WIDTH" "$HALF_HEIGHT"
  launch_and_place "RTSP Quad 4" "$STREAM_4" "$x1" "$y1" "$HALF_WIDTH" "$HALF_HEIGHT"
}

validate_streams() {
  local missing=0

  for i in 1 2 3 4; do
    local var="STREAM_$i"
    local url="${!var}"
    if [ -z "$url" ] || [[ "$url" == *"example.com"* ]]; then
      echo "STREAM_$i is not configured."
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    echo
    echo "Create $CONFIG_FILE with your camera URLs."
    echo "  cp sample.streams.conf streams.conf"
    echo "  \$EDITOR streams.conf"
    exit 1
  fi
}

require_commands() {
  local missing=0

  if ! command -v ffplay >/dev/null 2>&1; then
    echo "Missing required command: ffplay"
    missing=1
  fi

  if ! command -v swift >/dev/null 2>&1; then
    echo "Missing required command: swift (should be built into macOS)."
    missing=1
  fi

  if [ "$missing" -eq 1 ]; then
    echo
    echo "Install ffmpeg (includes ffplay) with Homebrew:"
    echo "  brew install ffmpeg"
    exit 1
  fi
}

trap cleanup EXIT
trap shutdown INT TERM

setup_brew_path
load_config
require_commands
validate_streams

while [ "$STOPPING" -eq 0 ]; do
  cleanup
  launch_streams

  echo "Streams running. Press Ctrl+C to stop. Restarting in $RESTART_SECONDS seconds..."
  interruptible_sleep "$RESTART_SECONDS"
done
