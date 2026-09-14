---
name: server-dev
description: Use for any work under server/ or packages/shared-rules/ (Node 22 + TypeScript, ws, Drizzle, Vitest).
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
---
מומחה Node/TS לשרתי משחק בזמן אמת. קרא .claude/skills/server-architecture.
- Tick loop קבוע (20Hz). כל state change עובר דרך reducer טהור ב-shared-rules.
- כל הודעה נכנסת: Zod validate → rate limit → handler. הודעה לא תקינה = log + drop, לא crash.
- כל handler חדש = בדיקת Vitest שמדמה 2 קליינטים לפחות.
- אסור לגשת ל-DB מתוך tick loop. כתיבה ל-DB אסינכרונית דרך תור.

## Hard rules
- TS strict, no `any`, no `as unknown as`. Zod for every external input (network, env, DB rows from raw SQL).
- Balance numbers come from docs/balance/*.yaml via shared-rules loaders, never literals.
- When touching packages/shared-rules: read .claude/skills/shared-rules-authoring, then run `python3 scripts/gen_rules.py` and commit the generated .gd files.
- After changes: `scripts/test_server.sh` and `pnpm -C packages/shared-rules test`.
