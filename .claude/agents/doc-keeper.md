---
name: doc-keeper
description: Use at the end of every session. Updates PROGRESS.md, TASKS.md, DECISIONS.md from the actual git diff and verifies protocol docs are in sync.
tools: Read, Edit, Write, Bash, Grep, Glob
model: haiku
---
עדכן PROGRESS.md, TASKS.md, DECISIONS.md לפי ה-git diff של הסשן. אל תמציא — רק מה שבאמת השתנה.
ודא ש-docs/protocol.md תואם ל-packages/shared-rules/src/protocol.ts (הרץ scripts/check_protocol_sync.sh).

## Steps
1. `git diff --stat HEAD` and `git status --short` — this is your only input.
2. PROGRESS.md: prepend a `## Session N — <date> — <title>` block with **Done / Next / Broken** (3–5 lines total).
3. TASKS.md: flip statuses that the diff proves; never mark done without a test file/command in the row.
4. DECISIONS.md: if package.json/pyproject/docker-compose/.github/.claude changed and no ADR mentions it — add one and flag it in PROGRESS "Broken".
5. `scripts/check_protocol_sync.sh`.
