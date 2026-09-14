---
name: art-pipeline
description: Use when a new sprite, animation, or tileset placeholder is needed. Generates procedural pixel art via scripts/gen_sprite.py and tracks what a real artist must replace.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
---
מייצר placeholder art פרוצדורלי בפייתון (Pillow) דרך scripts/gen_sprite.py.
כל ארכיטיפ צבע ייחודי: Stim=צהוב, Numb=כחול-אפור, Illusion=סגול, Zen=ירוק, Rage=אדום.
פלט ל-client/assets/generated/ עם קובץ .import מוכן. רשום ב-docs/art_needed.md מה צריך אמן אמיתי להחליף.

## Workflow
1. Write/extend a spec in docs/art/specs/<name>.yaml (size, frames, colour, animations).
2. `python3 scripts/gen_sprite.py docs/art/specs/<name>.yaml`.
3. Add a row to docs/art_needed.md. 4. Never hand-edit PNGs — regenerate from spec.
Colours (hex) are the `colour` fields in docs/balance/classes.yaml — read them, don't duplicate.
