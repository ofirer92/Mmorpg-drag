#!/usr/bin/env bash
# Usage: scripts/screenshot.sh <scene.tscn> [name] [WxH]   → docs/screenshots/<name>.png
# Runs the scene headless-with-rendering for a few frames and captures the viewport.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENE="${1:?scene path (res://... or client-relative)}"; NAME="${2:-$(basename "${SCENE%.tscn}")}"; RES="${3:-390x844}"
GODOT="${GODOT_BIN:-godot}"
command -v "$GODOT" >/dev/null || { echo "godot not found"; exit 1; }
mkdir -p "$ROOT/docs/screenshots"
OUT="$ROOT/docs/screenshots/${NAME}_${RES}.png"
cd "$ROOT/client"
# No display (CI / sandbox)? Wrap in xvfb-run when available. Audio is forced to the dummy driver.
RUNNER=()
if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v xvfb-run >/dev/null; then RUNNER=(xvfb-run -a -s "-screen 0 1280x1024x24"); fi
SCREENSHOT_OUT="$OUT" SCREENSHOT_SCENE="$SCENE" "${RUNNER[@]}" "$GODOT" --path . --resolution "$RES" --rendering-driver opengl3 --audio-driver Dummy -s tools/screenshot_runner.gd --quit-after 30 2>&1 | grep -vE "ALSA|audio_driver|audio drivers|audio_server" || true
[[ -f "$OUT" ]] && echo "saved $OUT" || { echo "no screenshot produced"; exit 1; }
