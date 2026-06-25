#!/bin/bash

# ==========================================================
# RTSP Quad Viewer for Debian (X11 / Wayland + XWayland)
# Launches 4 ffplay RTSP/RTSPS streams in screen quadrants.
# Restarts all streams every hour.
# ==========================================================

RESTART_SECONDS=3600

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/streams.conf}"

PIDS=()
IS_WAYLAND=0
STOPPING=0
SCRIPT_PID=$$

setup_display_env() {
  export DISPLAY="${DISPLAY:-:0}"

  if [ -z "${XAUTHORITY:-}" ]; then
    local mutter_auth
    mutter_auth=$(ls "/run/user/$(id -u)/.mutter-Xwaylandauth."* 2>/dev/null | head -n 1)
    if [ -n "$mutter_auth" ]; then
      export XAUTHORITY="$mutter_auth"
    elif [ -f "${HOME}/.Xauthority" ]; then
      export XAUTHORITY="${HOME}/.Xauthority"
    fi
  fi

  if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    IS_WAYLAND=1
  fi
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

  # Catch ffplay processes that outlive their tracked PID.
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

  if command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo >/dev/null 2>&1; then
    dims=$(xdpyinfo | awk '/dimensions:/ {print $2; exit}')
  elif command -v xrandr >/dev/null 2>&1; then
    dims=$(xrandr --current 2>/dev/null | awk '/ connected primary / {print $4; exit}' | cut -d+ -f1)
    if [ -z "$dims" ]; then
      dims=$(xrandr --current 2>/dev/null | awk '/ connected / {print $3; exit}' | cut -d+ -f1)
    fi
  fi

  if [ -z "$dims" ]; then
    echo "Could not determine screen size."
    echo "Ensure DISPLAY is set and you are running inside a desktop session."
    exit 1
  fi

  SCREEN_WIDTH=$(echo "$dims" | cut -d'x' -f1)
  SCREEN_HEIGHT=$(echo "$dims" | cut -d'x' -f2)

  HALF_WIDTH=$((SCREEN_WIDTH / 2))
  HALF_HEIGHT=$((SCREEN_HEIGHT / 2))

  echo "Detected screen: ${SCREEN_WIDTH}x${SCREEN_HEIGHT}"
  echo "Quadrants: ${HALF_WIDTH}x${HALF_HEIGHT}"
}

wait_for_window_by_title() {
  local TITLE="$1"

  if ! command -v xdotool >/dev/null 2>&1; then
    return 1
  fi

  for _ in {1..40}; do
    local WINDOW_ID
    WINDOW_ID=$(xdotool search --name "$TITLE" 2>/dev/null | head -n 1)
    if [ -n "$WINDOW_ID" ]; then
      echo "$WINDOW_ID"
      return 0
    fi
    sleep 0.5
  done

  return 1
}

reposition_window_x11() {
  local TITLE="$1"
  local X="$2"
  local Y="$3"
  local W="$4"
  local H="$5"

  if [ "$IS_WAYLAND" -eq 1 ]; then
    return 0
  fi

  if ! command -v xdotool >/dev/null 2>&1; then
    return 0
  fi

  local WINDOW_ID
  WINDOW_ID=$(wait_for_window_by_title "$TITLE") || return 0

  echo "Repositioning $TITLE via xdotool (window $WINDOW_ID)..."

  xdotool windowmap "$WINDOW_ID" 2>/dev/null

  if command -v wmctrl >/dev/null 2>&1; then
    wmctrl -ir "$WINDOW_ID" -b remove,maximized_vert,maximized_horz,hidden,fullscreen 2>/dev/null
    local CURRENT_DESKTOP
    CURRENT_DESKTOP=$(xdotool get_desktop 2>/dev/null || echo 0)
    wmctrl -ir "$WINDOW_ID" -t "$CURRENT_DESKTOP" 2>/dev/null
    wmctrl -ir "$WINDOW_ID" -e "0,$X,$Y,$W,$H" 2>/dev/null
  fi

  xdotool windowmove "$WINDOW_ID" "$X" "$Y" 2>/dev/null
  xdotool windowsize "$WINDOW_ID" "$W" "$H" 2>/dev/null
  xdotool windowraise "$WINDOW_ID" 2>/dev/null
}

launch_and_place() {
  local TITLE="$1"
  local URL="$2"
  local X="$3"
  local Y="$4"
  local W="$5"
  local H="$6"

  echo "Launching $TITLE at ${X},${Y} ${W}x${H}..."

  ffplay "${FFPLAY_OPTS[@]}" \
    -window_title "$TITLE" \
    -left "$X" \
    -top "$Y" \
    -x "$W" \
    -y "$H" \
    "$URL" &

  PIDS+=("$!")

  sleep 1
  reposition_window_x11 "$TITLE" "$X" "$Y" "$W" "$H"
}

launch_streams() {
  echo "Launching streams..."

  get_screen_size

  launch_and_place "RTSP Quad 1" "$STREAM_1" 0 0 "$HALF_WIDTH" "$HALF_HEIGHT"
  launch_and_place "RTSP Quad 2" "$STREAM_2" "$HALF_WIDTH" 0 "$HALF_WIDTH" "$HALF_HEIGHT"
  launch_and_place "RTSP Quad 3" "$STREAM_3" 0 "$HALF_HEIGHT" "$HALF_WIDTH" "$HALF_HEIGHT"
  launch_and_place "RTSP Quad 4" "$STREAM_4" "$HALF_WIDTH" "$HALF_HEIGHT" "$HALF_WIDTH" "$HALF_HEIGHT"

  if command -v wmctrl >/dev/null 2>&1; then
    echo "Current RTSP Quad windows:"
    wmctrl -lG | grep "RTSP Quad" || true
  fi
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
    echo "  cp streams.conf.example streams.conf"
    echo "  \$EDITOR streams.conf"
    exit 1
  fi
}

require_commands() {
  local missing=0

  for cmd in ffplay; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Missing required command: $cmd"
      missing=1
    fi
  done

  if ! command -v xdpyinfo >/dev/null 2>&1 && ! command -v xrandr >/dev/null 2>&1; then
    echo "Missing screen-size tool: install xdpyinfo or xrandr (x11-utils / x11-xserver-utils)."
    missing=1
  fi

  if [ "$missing" -eq 1 ]; then
    echo
    echo "Install dependencies with:"
    echo "sudo apt update && sudo apt install ffmpeg xdotool wmctrl x11-utils"
    exit 1
  fi
}

trap cleanup EXIT
trap shutdown INT TERM

setup_display_env
load_config
require_commands
validate_streams

while [ "$STOPPING" -eq 0 ]; do
  cleanup
  launch_streams

  echo "Streams running. Press Ctrl+C to stop. Restarting in $RESTART_SECONDS seconds..."
  interruptible_sleep "$RESTART_SECONDS"
done

