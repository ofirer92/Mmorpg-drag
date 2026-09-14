#!/usr/bin/env bash
# Export Godot builds for Android / Windows / Web into build/. Presets live in client/export_presets.cfg.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
command -v "$GODOT" >/dev/null || { echo "godot not found"; exit 1; }
[[ -f "$ROOT/client/export_presets.cfg" ]] || { echo "client/export_presets.cfg missing — configure presets first (release-checklist skill)"; exit 1; }
mkdir -p "$ROOT/build"
cd "$ROOT/client"
for preset in "${@:-Android Windows Web}"; do
  case "$preset" in
    Android) out="$ROOT/build/hamirpaa.apk" ;;
    Windows) out="$ROOT/build/hamirpaa.exe" ;;
    Web)     mkdir -p "$ROOT/build/web"; out="$ROOT/build/web/index.html" ;;
    *) echo "unknown preset $preset"; exit 1 ;;
  esac
  echo "== exporting $preset → $out"
  "$GODOT" --headless --export-release "$preset" "$out"
done
echo "== sizes"; du -sh "$ROOT"/build/* | tee "$ROOT/build/sizes.txt"
awk '/apk/ && $1+0 > 60 {print "❌ Android build > 60MB"; exit 1}' "$ROOT/build/sizes.txt" || true
