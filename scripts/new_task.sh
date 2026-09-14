#!/usr/bin/env bash
# Usage: scripts/new_task.sh "T-0.3" "godot-dev" "Camera follows player with deadzone" "test: tests/test_camera.gd" [section]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:?task id e.g. T-0.3}"; AGENT="${2:?agent}"; TITLE="${3:?title}"; TEST="${4:-test: TBD}"; SECTION="${5:-}"
LINE="- [ ] ready $ID | $AGENT | $TITLE | $TEST"
if [[ -z "$SECTION" ]]; then
  phase="${ID#T-}"; phase="${phase%%.*}"
  case "$phase" in I) SECTION="## Phase -1" ;; *) SECTION="## Phase $phase" ;; esac
fi
if ! grep -qF "$SECTION" "$ROOT/TASKS.md"; then printf "\n%s\n" "$SECTION" >> "$ROOT/TASKS.md"; fi
# insert after the last task line of the section
python3 - "$ROOT/TASKS.md" "$SECTION" "$LINE" <<'PY'
import sys, re
path, section, line = sys.argv[1:4]
txt = open(path, encoding="utf-8").read().split("\n")
i = next(i for i, l in enumerate(txt) if l.strip() == section)
j = i + 1
while j < len(txt) and not txt[j].startswith("## ") and not txt[j].startswith("### "): j += 1
k = j
while k > i + 1 and txt[k - 1].strip() == "": k -= 1
txt.insert(k, line)
open(path, "w", encoding="utf-8").write("\n".join(txt))
PY
echo "added to $SECTION: $LINE"
