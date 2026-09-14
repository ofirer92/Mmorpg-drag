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
SCREENSHOT_OUT="$OUT" SCREENSHOT_SCENE="$SCENE" "$GODOT" --path . --resolution "$RES" --rendering-driver opengl3 -s tools/screenshot_runner.gd --quit-after 30 || true
[[ -f "$OUT" ]] && echo "saved $OUT" || { echo "no screenshot produced"; exit 1; }
