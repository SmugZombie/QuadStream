# QuadStream

Launch four RTSP/RTSPS camera streams in a 2×2 grid, each filling a screen quadrant. Streams restart automatically every hour to recover from dropped connections.

## Requirements

| Platform | Script | Dependencies |
|----------|--------|--------------|
| Linux (Debian, X11/Wayland) | `streams.sh` | `ffmpeg` (`ffplay`), `xdotool`, `wmctrl`, `xdpyinfo` or `xrandr` |
| macOS (Intel + Apple Silicon) | `streams-macos.sh` | `ffmpeg` (`ffplay`) via [Homebrew](https://brew.sh) |

## Quick start

1. Clone the repo and create your config:

```bash
cp sample.streams.conf streams.conf
```

2. Edit `streams.conf` with your four camera URLs:

```bash
STREAM_1="rtsps://user:pass@camera1.example.com/stream1"
STREAM_2="rtsps://user:pass@camera2.example.com/stream2"
STREAM_3="rtsps://user:pass@camera3.example.com/stream3"
STREAM_4="rtsps://user:pass@camera4.example.com/stream4"
```

3. Run the script for your platform:

```bash
# Linux
./streams.sh

# macOS
./streams-macos.sh
```

Press **Ctrl+C** to stop all streams.

## Linux

Install dependencies:

```bash
sudo apt update && sudo apt install ffmpeg xdotool wmctrl x11-utils
```

The script detects screen size via `xdpyinfo` or `xrandr`, launches four borderless `ffplay` windows, and uses `xdotool`/`wmctrl` to position them when needed (especially on X11).

## macOS

Install ffmpeg:

```bash
brew install ffmpeg
```

The script uses Swift (`NSScreen`) to detect the **main display** (the one with the menu bar) and places all four quadrants on that screen only — even when multiple monitors are connected.

### Multiple monitors

By default, streams appear on the main display. To use a different monitor, set `TARGET_DISPLAY` to its zero-based index:

```bash
TARGET_DISPLAY=2 ./streams-macos.sh
```

To list display indices, run:

```bash
swift - <<'SWIFT'
import Cocoa
for (i, s) in NSScreen.screens.enumerated() {
  let f = s.frame
  print("screen \(i): \(Int(f.width))x\(Int(f.height)) main=\(s == NSScreen.main!)")
}
SWIFT
```

If windows are not positioned correctly, grant **Accessibility** permission to your terminal app under **System Settings → Privacy & Security → Accessibility**. This is only needed for the AppleScript window-placement fallback.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CONFIG_FILE` | `./streams.conf` | Path to the stream URL config file |
| `TARGET_DISPLAY` | *(main display)* | macOS only — zero-based monitor index |
| `RESTART_SECONDS` | `3600` | Seconds between full stream restarts (edit in script) |

## How it works

1. Reads four stream URLs from `streams.conf`
2. Detects the target display size and divides it into four equal quadrants
3. Launches `ffplay` for each stream with low-latency options (`-fflags nobuffer`, `-rtsp_transport tcp`, etc.)
4. Positions each window in its quadrant
5. Restarts all streams every hour until stopped

## Files

| File | Description |
|------|-------------|
| `streams.sh` | Linux launcher |
| `streams-macos.sh` | macOS launcher |
| `sample.streams.conf` | Example config — copy to `streams.conf` |
| `streams.conf` | Your camera URLs (not committed — create locally) |
