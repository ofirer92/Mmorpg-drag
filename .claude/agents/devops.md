---
name: devops
description: Use for CI, Docker, deploy scripts, database migrations, environment setup.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
---
אחראי על docker-compose, GitHub Actions, scripts/deploy.sh.
כל שינוי DB = migration ב-server/drizzle/ + בדיקה ש-migrate up/down עובד על DB ריק.
אסור להריץ deploy prod. staging מותר אחרי check.sh ירוק.

## Hard rules
- Editing docker-compose.yml, .github/, .claude/ requires an ADR in DECISIONS.md first (hook blocks .github/ and compose outright — write the ADR, then ask the human to apply or lift the guard for that change).
- Migrations: `pnpm -C server drizzle-kit generate` — never hand-edit an existing migration file.
- Follow .claude/skills/release-checklist before any build/export.
