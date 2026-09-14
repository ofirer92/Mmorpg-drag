# תוכנית עבודה לפיתוח "המרפאה" — מדריך הפעלה ל-Claude Code
### מטרה: שה-AI יוכל לבנות את המשחק כמעט לבד, משלב 0 ועד מוצר משוחק

---

## 0. איך המסמך הזה עובד

המסמך הזה הוא **"מערכת הפעלה"** לפיתוח. הוא מורכב מ-4 שכבות:

| שכבה | מה זה | איפה זה יושב בריפו |
|---|---|---|
| **חוקה** | CLAUDE.md — מה מותר, מה אסור, איך מקודדים | `/CLAUDE.md` |
| **צוות** | Sub-agents — מומחים לכל תחום | `/.claude/agents/*.md` |
| **ידע** | Skills — ידע ספציפי שנטען לפי צורך | `/.claude/skills/*/SKILL.md` |
| **אוטומציה** | Hooks + Scripts — בדיקות שרצות לבד | `/.claude/settings.json`, `/scripts/` |

**עיקרון מרכזי:** ה-AI לא "זוכר" בין סשנים. לכן כל מצב הפרויקט חייב לחיות בקבצים: `PROGRESS.md`, `TASKS.md`, `DECISIONS.md`. כל סשן מתחיל בקריאה שלהם ומסתיים בעדכון שלהם. זה מה שמאפשר עבודה רציפה לאורך חודשים.

**מה עדיין דורש בן-אדם (Human Checkpoints):**
- החלטות סגנון אמנותי (ה-AI מייצר placeholder art, לא אמנות סופית)
- חשבונות: GitHub, Google Play / App Store, ספק ענן (Hetzner/Fly.io/AWS)
- תשלומים ומשפטי (תנאי שימוש, פרטיות — חובה לאפליקציה בחנויות)
- **Playtesting אנושי** — ה-AI יכול לבדוק שהמכניקה עובדת, לא שהיא כיפית
- אישור לפני כל פריסה (deploy) לפרודקשן

---

## 1. החלטות טכנולוגיות (סגורות — לא לפתוח מחדש בלי DECISIONS.md)

| רכיב | בחירה | למה |
|---|---|---|
| קליינט | **Godot 4.3+ / GDScript** | חינמי, 2D מעולה, ייצוא נייד+דסקטופ+web מאותו קוד, קוד טקסטואלי (טוב ל-AI) |
| שרת | **Node.js 22 + TypeScript** | פיתוח מהיר, ה-AI חזק מאוד ב-TS, ספרייה עשירה |
| רשת | **WebSocket (ws)** + פרוטוקול JSON בשלבים 2-3, MessagePack בשלב 4 | פשוט לדיבוג, אפשר לשדרג |
| DB | **PostgreSQL 16** (persistence) + **Redis 7** (state בזמן אמת, pub/sub) | לפי ה-GDD |
| ORM | **Drizzle** | type-safe, migrations כקוד |
| בדיקות קליינט | **GUT** (Godot Unit Test) | רץ headless ב-CI |
| בדיקות שרת | **Vitest** | מהיר, TS native |
| CI | **GitHub Actions** | חינמי לריפו פתוח/קטן |
| תשתית | **Docker Compose** (dev) → **Fly.io / Hetzner** (prod) | זול, פשוט |
| ניהול משימות | `TASKS.md` בריפו + GitHub Issues (אופציונלי) | ה-AI קורא/כותב קבצים בקלות |
| אמנות זמנית | פיקסל-ארט 32×32 שנוצר פרוצדורלית + Kenney assets (CC0) | עד שיש אמן |

**חוק ברזל:** כל לוגיקת משחק (נזק, XP, דרופ, מיקום) נכתבת **פעם אחת** בחבילה משותפת `packages/shared-rules` (TypeScript) ומועתקת אוטומטית ל-GDScript דרך סקריפט (`scripts/gen_rules.py`) — כך הקליינט והשרת לעולם לא חולקים על מספר.

---

## 2. מבנה הריפו (Monorepo)

```
hamirpaa/
├── CLAUDE.md                    # החוקה
├── PROGRESS.md                  # מה נעשה, מה הבא (ה-AI מעדכן כל סשן)
├── TASKS.md                     # backlog מפורט עם סטטוסים
├── DECISIONS.md                 # ADR — כל החלטה ארכיטקטונית + סיבה
├── docs/
│   ├── GDD.md                   # מסמך העיצוב (הקיים)
│   ├── protocol.md              # פרוטוקול קליינט-שרת (מקור אמת)
│   ├── balance/                 # טבלאות איזון (CSV/YAML)
│   │   ├── classes.yaml
│   │   ├── monsters.yaml
│   │   ├── items.yaml
│   │   └── xp_curve.yaml
│   └── content/                 # טקסטים, דיאלוגים, שמות (עברית + אנגלית)
├── client/                      # פרויקט Godot
│   ├── project.godot
│   ├── scenes/
│   ├── scripts/
│   │   ├── rules/               # ⚠️ נוצר אוטומטית מ-shared-rules, לא לערוך ידנית
│   │   ├── player/
│   │   ├── combat/
│   │   ├── net/
│   │   └── ui/
│   ├── assets/
│   └── tests/                   # GUT
├── server/
│   ├── src/
│   │   ├── world/               # zones, instances, tick loop
│   │   ├── combat/
│   │   ├── economy/
│   │   ├── net/                 # ws handlers, message validation
│   │   ├── persistence/         # drizzle schema, repos
│   │   └── anticheat/
│   ├── tests/
│   └── Dockerfile
├── packages/
│   └── shared-rules/            # לוגיקה טהורה: נוסחאות נזק, XP, דרופ
├── scripts/                     # אוטומציה (ראו סעיף 7)
├── .claude/
│   ├── agents/
│   ├── skills/
│   └── settings.json            # hooks
├── .github/workflows/ci.yml
└── docker-compose.yml
```

---

## 3. CLAUDE.md — החוקה (להעתיק כמו שהוא לשורש הריפו)

```markdown
# CLAUDE.md — "המרפאה" (Hamirpaa)

## מה זה הפרויקט
MMORPG פלטפורמר 2D סאטירי. קרא docs/GDD.md לפני כל עבודה עיצובית.
הטון: הומור בירוקרטי-אבסורדי על תאגידי פארמה. לא גרפי, לא תיאור סמים אמיתיים.

## פרוטוקול תחילת סשן (חובה, בסדר הזה)
1. קרא PROGRESS.md — מה המצב הנוכחי.
2. קרא TASKS.md — קח את המשימה הראשונה עם סטטוס `[ ] ready`.
3. אם המשימה לא ברורה — כתוב ב-TASKS.md שאלה ב-`## Questions for human` ועבור למשימה הבאה. אל תנחש החלטות מוצר.
4. הרץ `scripts/check.sh` לוודא שהמצב ירוק לפני שמתחילים.

## פרוטוקול סיום סשן (חובה)
1. כל הבדיקות עוברות (`scripts/check.sh`).
2. עדכן TASKS.md (סטטוס משימה: done / blocked + סיבה).
3. עדכן PROGRESS.md: 3-5 שורות — מה נעשה, מה הבא, מה שבור.
4. commit עם הודעה בפורמט `[phase-N][area] description`.

## חוקי קוד
- כל לוגיקת משחק ב-packages/shared-rules בלבד. אסור מספרי איזון hardcoded בקליינט או בשרת.
- client/scripts/rules/ נוצר אוטומטית — אל תערוך. הרץ `scripts/gen_rules.py`.
- השרת אוטוריטטיבי. הקליינט רק שולח input ומציג state. אסור לקליינט לחשב נזק.
- כל הודעת רשת מוגדרת ב-docs/protocol.md **לפני** שכותבים אותה בקוד.
- כל feature חדש = בדיקה חדשה. אין merge בלי בדיקה.
- GDScript: static typing תמיד (`var hp: int = 0`). שמות snake_case.
- TypeScript: strict mode, אין `any`, Zod לכל input חיצוני.
- טקסט למשחק: רק דרך docs/content/*.yaml עם מפתחות, לא string בקוד (i18n he/en).

## אסור
- לשנות docker-compose.yml, .github/, או .claude/ בלי לכתוב ב-DECISIONS.md.
- למחוק בדיקות כדי שהן "יעברו".
- להוסיף ספריות בלי לרשום ב-DECISIONS.md.
- לפרוס לפרודקשן. רק בן-אדם מריץ `scripts/deploy.sh prod`.

## סוכנים
השתמש ב-sub-agents לפי תחום (ראו .claude/agents/). למשימה שנוגעת בקליינט+שרת, קודם `protocol-designer`, ואז שני הצדדים במקביל.
```

---

## 4. Sub-Agents (הצוות)

כל סוכן = קובץ ב-`.claude/agents/<name>.md` עם frontmatter. מבנה כל קובץ:

```markdown
---
name: <name>
description: <מתי להפעיל — Claude משתמש בזה כדי לבחור סוכן אוטומטית>
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet   # או opus למשימות תכנון
---
<הנחיות הסוכן>
```

### 4.1 `orchestrator` (model: opus)
**מתי:** תחילת כל משימה גדולה (feature מלא, milestone).
**תפקיד:** מפרק feature ל-subtasks ב-TASKS.md, מחליט איזה סוכנים צריך ובאיזה סדר, לא כותב קוד בעצמו.
```markdown
אתה מנהל הפרויקט הטכני. קלט: משימה מ-TASKS.md.
פלט: רשימת subtasks עם: סוכן אחראי, קבצים שייגעו, בדיקה שמוכיחה סיום, תלויות.
כלל: subtask חייב להסתיים בפחות משעת עבודה של סוכן. אם לא — פצל.
כלל: אם feature נוגע ברשת — הסובטאסק הראשון תמיד `protocol-designer`.
אל תכתוב קוד. רק תכנון ואימות שכל הסובטאסקים הושלמו.
```

### 4.2 `protocol-designer` (model: opus)
**מתי:** כל feature שמשנה תקשורת קליינט-שרת.
```markdown
אתה אחראי על docs/protocol.md — מקור האמת של הפרוטוקול.
לכל הודעה חדשה הגדר: שם, כיוון (C→S / S→C), שדות + טיפוסים, מתי נשלחת, ולידציה בשרת, מה קורה בכישלון.
כתוב סכמת Zod ב-packages/shared-rules/src/protocol.ts ואת המקבילה ב-GDScript דרך gen_rules.py.
עיקרון: הקליינט שולח כוונות (intent), השרת שולח עובדות (state). לעולם לא להפך.
```

### 4.3 `godot-dev`
**מתי:** כל עבודה בתיקיית client/.
```markdown
מומחה Godot 4 / GDScript. קרא .claude/skills/godot-conventions לפני עבודה.
- כל סצנה = קובץ .tscn + סקריפט אחד. אין לוגיקה ב-_process אם אפשר בסיגנלים.
- Mobile first: כל UI נבדק ב-viewport 390×844 לפני 1920×1080.
- אחרי כל שינוי הרץ: scripts/test_client.sh (GUT headless).
- אם משהו נראה ויזואלי — צלם screenshot דרך scripts/screenshot.sh והצג לבן-אדם ב-PROGRESS.md.
- אסור לחשב נזק/XP/דרופ בקליינט. רק להציג מה שהשרת אמר.
```

### 4.4 `server-dev`
**מתי:** כל עבודה בתיקיית server/.
```markdown
מומחה Node/TS לשרתי משחק בזמן אמת. קרא .claude/skills/server-architecture.
- Tick loop קבוע (20Hz). כל state change עובר דרך reducer טהור ב-shared-rules.
- כל הודעה נכנסת: Zod validate → rate limit → handler. הודעה לא תקינה = log + drop, לא crash.
- כל handler חדש = בדיקת Vitest שמדמה 2 קליינטים לפחות.
- אסור לגשת ל-DB מתוך tick loop. כתיבה ל-DB אסינכרונית דרך תור.
```

### 4.5 `game-designer`
**מתי:** משימות תוכן, איזון, מיומנויות, דיאלוגים.
```markdown
אתה מעצב המשחק. עובד רק על docs/balance/*.yaml ו-docs/content/*.yaml — לא על קוד.
קרא .claude/skills/satire-voice לפני כתיבת טקסט.
לכל מספר איזון חדש: הרץ scripts/balance_sim.py והצג טבלת TTK (time-to-kill) ו-XP/שעה. אם ארכיטיפ אחד מנצח ב->15% ברוב התרחישים — לא מאושר.
כל מיומנות: שם עברי + אנגלי, תיאור קומי (עד 12 מילים), מספרים, cooldown, אנימציה נדרשת (placeholder).
```

### 4.6 `qa-tester`
**מתי:** אחרי כל subtask שמסומן done, ולפני merge.
```markdown
אתה בודק עצמאי. אל תסמוך על מה שהמפתח כתב.
1. הרץ scripts/check.sh במלואו.
2. קרא את הבדיקות שנוספו — האם הן באמת בודקות את ה-feature או רק "עוברות"?
3. חפש edge cases: HP=0, רמה 1 מול בוס, 2 שחקנים באותו פיקסל, ניתוק באמצע קרב.
4. כתוב לפחות בדיקה אחת חדשה שהמפתח לא חשב עליה.
5. פלט: דוח ב-TASKS.md תחת המשימה: PASS / FAIL + מה נמצא.
```

### 4.7 `anticheat-reviewer` (model: opus)
**מתי:** שלב 3 ואילך, בכל שינוי בשרת/פרוטוקול.
```markdown
תחשוב כמו רמאי. לכל הודעת פרוטוקול שאל: מה קורה אם הקליינט שולח ערך מזויף? שולח 1000 פעם בשנייה? שולח בזמן שהוא מת?
בדוק: speed hacks (השרת בודק מרחק/זמן?), item duplication, XP injection, teleport.
פלט: רשימת חורים + patch מוצע + בדיקה שמדמה את ההתקפה.
```

### 4.8 `art-pipeline`
**מתי:** צריך ספרייט/אנימציה/tileset חדש.
```markdown
מייצר placeholder art פרוצדורלי בפייתון (Pillow) דרך scripts/gen_sprite.py.
כל ארכיטיפ צבע ייחודי: Stim=צהוב, Numb=כחול-אפור, Illusion=סגול, Zen=ירוק, Rage=אדום.
פלט ל-client/assets/generated/ עם קובץ .import מוכן. רשום ב-docs/art_needed.md מה צריך אמן אמיתי להחליף.
```

### 4.9 `devops`
**מתי:** CI, Docker, פריסה, migrations.
```markdown
אחראי על docker-compose, GitHub Actions, scripts/deploy.sh.
כל שינוי DB = migration ב-server/drizzle/ + בדיקה ש-migrate up/down עובד על DB ריק.
אסור להריץ deploy prod. staging מותר אחרי check.sh ירוק.
```

### 4.10 `doc-keeper` (model: haiku — זול ומהיר)
**מתי:** סוף כל סשן.
```markdown
עדכן PROGRESS.md, TASKS.md, DECISIONS.md לפי ה-git diff של הסשן. אל תמציא — רק מה שבאמת השתנה.
ודא ש-docs/protocol.md תואם ל-packages/shared-rules/src/protocol.ts (הרץ scripts/check_protocol_sync.sh).
```

---

## 5. Skills (ידע שנטען לפי צורך)

כל skill = תיקייה `.claude/skills/<name>/SKILL.md` + קבצי עזר. Claude טוען אותם אוטומטית כשה-description מתאים למשימה.

### 5.1 `godot-conventions`
- תבנית סצנת דמות (CharacterBody2D + StateMachine)
- דוגמת State Machine ל-idle/run/jump/attack/hurt/dead
- איך כותבים בדיקת GUT
- רשימת "מוקשים" ב-Godot 4 (למשל: `await` vs `yield`, שינויים ב-TileMap → TileMapLayer)
- דוגמת Virtual Joystick + כפתורים למובייל
- הנחיות export: presets ל-Android/iOS/Windows/Web

### 5.2 `server-architecture`
- מבנה tick loop, ECS קליל
- תבנית handler: validate → authorize → apply → broadcast
- Interest management (שחקן מקבל רק אירועים ברדיוס X)
- תבנית בדיקה עם 2 קליינטים מדומים
- דוגמת Drizzle schema + repo

### 5.3 `shared-rules-authoring`
- איך כותבים פונקציה טהורה שמתקמפלת גם ל-GDScript (תת-קבוצה של TS: אין closures, אין classes, רק פונקציות ומספרים)
- איך gen_rules.py מתרגם
- דוגמה: `damage(attacker, defender, skill) → number`

### 5.4 `satire-voice`
- מדריך טון: בירוקרטי, ציני, אבסורד. דוגמאות טובות/רעות.
- אוצר מילים: "מינון", "טופס", "אישור", "תופעות לוואי", "רוקח", "ועדת אתיקה"
- **קווים אדומים:** בלי שמות סמים אמיתיים, בלי הוראות שימוש, בלי רומנטיזציה של התמכרות. הכל בדיוני ומוגזם.
- תבנית NPC: שם, תפקיד, 3 שורות דיאלוג (ברכה / חנות / פרידה), quirk אחד

### 5.5 `balance-methodology`
- נוסחאות: TTK, DPS, EHP (effective HP), XP/שעה
- תבנית YAML למפלצת/פריט/מיומנות
- איך מריצים balance_sim.py וקוראים את הפלט
- ספי אישור (אף ארכיטיפ לא מנצח ב-> 15%, TTK של מפלצת רגילה 3-8 שניות)

### 5.6 `release-checklist`
- צ'קליסט לפני כל build: version bump, changelog, migrations, smoke test
- Android: keystore, permissions מינימליות; iOS: privacy manifest
- Web: CORS, WSS, גודל build < 30MB

---

## 6. Hooks (`.claude/settings.json`)

Hooks רצים אוטומטית — זה מה שהופך את העבודה ל"שוטפת" בלי שבן-אדם יזכיר.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "cat PROGRESS.md && echo '--- OPEN TASKS ---' && grep -n '\\[ \\]' TASKS.md | head -20" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "scripts/hooks/guard_protected.sh" }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "scripts/hooks/guard_bash.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "scripts/hooks/format_and_lint.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "scripts/hooks/on_stop.sh" }
        ]
      }
    ]
  }
}
```

### מה כל hook עושה

| Hook | סקריפט | התנהגות |
|---|---|---|
| SessionStart | inline | מדפיס PROGRESS + משימות פתוחות — ה-AI מתחיל עם הקשר |
| PreToolUse (Edit/Write) | `guard_protected.sh` | חוסם עריכה של `client/scripts/rules/`, `.github/`, `docker-compose.yml`, קבצי migration קיימים. יוצא עם exit 2 + הסבר |
| PreToolUse (Bash) | `guard_bash.sh` | חוסם `rm -rf`, `git push --force`, `deploy.sh prod`, `DROP TABLE` |
| PostToolUse (Edit/Write) | `format_and_lint.sh` | לפי סיומת: `.gd` → gdformat+gdlint; `.ts` → prettier+eslint; `.yaml` → yamllint + ולידציה מול schema; `.py` → ruff |
| Stop | `on_stop.sh` | מריץ `check.sh`. אם אדום — מחזיר exit 2 עם הודעה "בדיקות נכשלו, תקן לפני סיום" (Claude ממשיך לעבוד). אם ירוק — מריץ `doc-keeper` וbודק ש-PROGRESS.md השתנה בסשן הזה |

**דוגמת `guard_protected.sh`:**
```bash
#!/usr/bin/env bash
FILE=$(jq -r '.tool_input.file_path // empty')
PROTECTED=("client/scripts/rules/" ".github/" "docker-compose.yml" "server/drizzle/[0-9]")
for p in "${PROTECTED[@]}"; do
  if [[ "$FILE" =~ $p ]]; then
    echo "BLOCKED: $FILE is protected. Write to DECISIONS.md first or use gen_rules.py." >&2
    exit 2
  fi
done
exit 0
```

**דוגמת `on_stop.sh`:**
```bash
#!/usr/bin/env bash
if ! scripts/check.sh > /tmp/check.log 2>&1; then
  echo "Tests failing — fix before ending session:" >&2
  tail -30 /tmp/check.log >&2
  exit 2
fi
if git diff --quiet HEAD -- PROGRESS.md; then
  echo "PROGRESS.md was not updated this session. Update it (3-5 lines: done / next / broken)." >&2
  exit 2
fi
exit 0
```

---

## 7. Scripts (`/scripts/`)

| סקריפט | מה עושה | מי מריץ |
|---|---|---|
| `setup.sh` | מתקין Godot CLI, Node, pnpm, Docker; מרים compose; מריץ migrations; יוצר `.env` | בן-אדם פעם אחת |
| `check.sh` | `test_client.sh` + `test_server.sh` + `check_protocol_sync.sh` + `validate_balance.py` — **הפקודה היחידה שקובעת "ירוק"** | Hooks, CI, AI |
| `test_client.sh` | `godot --headless -s addons/gut/gut_cmdln.gd` | check.sh |
| `test_server.sh` | `pnpm -C server vitest run` | check.sh |
| `gen_rules.py` | מתרגם `packages/shared-rules/src/*.ts` → `client/scripts/rules/*.gd` + מייצר sha לכל קובץ | AI אחרי כל שינוי ב-shared-rules |
| `check_protocol_sync.sh` | מוודא ש-protocol.md, protocol.ts ו-protocol.gd מכילים את אותן הודעות | check.sh |
| `validate_balance.py` | בודק ש-YAML של איזון תקין (schema, אין ערכים שליליים, כל מיומנות שייכת לארכיטיפ קיים) | check.sh |
| `balance_sim.py` | מדמה 1000 קרבות לכל ארכיטיפ מול כל מפלצת → טבלת TTK, שיעור ניצחון, XP/שעה. פלט Markdown ל-docs/balance/report.md | game-designer |
| `gen_sprite.py` | יוצר spritesheet placeholder לפי YAML (צבע, מספר פריימים, גודל) | art-pipeline |
| `screenshot.sh` | מריץ סצנה headless עם רינדור → PNG ל-docs/screenshots/ | godot-dev |
| `sim_clients.ts` | מריץ N קליינטים מדומים נגד השרת (load test + בדיקת sync) | server-dev, qa |
| `export_builds.sh` | ייצוא Godot ל-Android/Windows/Web + העלאה כ-artifact | CI, release |
| `deploy.sh <staging\|prod>` | build Docker → push → migrate → restart. `prod` דורש `CONFIRM=yes` | devops (staging) / בן-אדם (prod) |
| `new_task.sh "title"` | מוסיף משימה ל-TASKS.md בפורמט הנכון | כולם |

---

## 8. Flows — תהליכי עבודה קבועים

### 8.1 Feature Flow (הראשי)
```
1. orchestrator      → קורא משימה, מפרק ל-subtasks ב-TASKS.md
2. protocol-designer → (אם רשת) מגדיר הודעות ב-protocol.md + Zod
3. game-designer     → (אם תוכן/איזון) YAML + balance_sim
4. server-dev ‖ godot-dev → מיישמים במקביל לפי הפרוטוקול (שני sub-agents)
5. gen_rules.py      → סנכרון כללים לקליינט
6. qa-tester         → check.sh + edge cases + בדיקה חדשה
7. anticheat-reviewer→ (שלב 3+) סקירה
8. doc-keeper        → עדכון PROGRESS/TASKS/DECISIONS
9. commit            → [phase-N][area] description
```

### 8.2 Bug Flow
```
1. כתוב בדיקה שמשחזרת את הבאג (חייבת להיכשל)
2. תקן
3. הבדיקה עוברת + check.sh ירוק
4. רשום ב-PROGRESS.md תחת "Fixed"
```

### 8.3 Balance Flow
```
1. game-designer משנה YAML
2. validate_balance.py
3. balance_sim.py → אם מחוץ לספים → חזור ל-1
4. gen_rules.py (המספרים חיים ב-shared-rules שקורא את ה-YAML)
5. commit [balance] + צרף report.md
```

### 8.4 Session Flow (כל הרצה של Claude Code)
```
SessionStart hook → קריאת הקשר
→ בחירת משימה ready ראשונה
→ Feature/Bug flow
→ Stop hook: check.sh ירוק? PROGRESS עודכן? אחרת ממשיך
→ commit
```

### 8.5 Release Flow (שלב 3+)
```
1. release-checklist skill
2. version bump + CHANGELOG.md
3. export_builds.sh
4. deploy.sh staging → sim_clients.ts 50 שחקנים 10 דקות
5. בן-אדם: smoke test ידני על נייד + מחשב
6. בן-אדם: deploy.sh prod
```

---

## 9. פורמט TASKS.md

```markdown
# TASKS

## Questions for human
- [ ] Q1: האם קראש של הממריץ צריך להיות 2 שניות או 3? (game-designer, blocks T-1.4)

## Phase 0
- [x] T-0.1 | godot-dev | Player moves+jumps on flat map | test: tests/test_player_movement.gd
- [ ] ready T-0.2 | godot-dev | Camera follows player with deadzone | test: test_camera.gd
- [ ] blocked T-0.3 | ... | reason: waiting Q1
```

סטטוסים: `ready` / `in-progress` / `blocked` / `[x]` done. ה-AI לוקח תמיד את ה-`ready` הראשון.

---

## 10. תוכנית שלבים מפורטת

לכל שלב: משימות ממוספרות, **תנאי סיום (DoD)** שהסקריפטים מאמתים, ו-Human Checkpoint.

### שלב -1 — תשתית (שבוע 1)
| # | משימה | סוכן | DoD |
|---|---|---|---|
| T-I.1 | יצירת monorepo לפי סעיף 2, CLAUDE.md, .claude/ מלא | devops | `ls` תואם למבנה |
| T-I.2 | `setup.sh` + docker-compose (postgres, redis) | devops | `docker compose ps` — 2 שירותים up |
| T-I.3 | פרויקט Godot ריק + GUT + בדיקה אחת שעוברת | godot-dev | `test_client.sh` ירוק |
| T-I.4 | שרת Node ריק + Vitest + בדיקת health | server-dev | `test_server.sh` ירוק |
| T-I.5 | shared-rules עם פונקציה אחת (`xp_for_level`) + gen_rules.py עובד | server-dev | `.gd` נוצר ובדיקה בשני הצדדים נותנת אותו מספר |
| T-I.6 | כל ה-hooks + check.sh | devops | סימולציה: עריכת קובץ מוגן נחסמת |
| T-I.7 | CI ב-GitHub Actions מריץ check.sh | devops | PR ראשון ירוק |
| T-I.8 | כל ה-Skills כתובים | doc-keeper | 6 תיקיות skills עם SKILL.md |

**Human Checkpoint:** אישור מבנה + חשבון GitHub.

### שלב 0 — פרוטוטייפ Single-player (שבועות 2-4)
| # | משימה | סוכן | DoD |
|---|---|---|---|
| T-0.1 | דמות: תנועה, קפיצה, coyote-time, jump buffer | godot-dev | בדיקות פיזיקה עוברות |
| T-0.2 | State machine לדמות (6 מצבים) | godot-dev | מעבר בין כל המצבים נבדק |
| T-0.3 | מפה אחת (TileMapLayer) 60×20 אריחים עם פלטפורמות | godot-dev + art-pipeline | screenshot ב-docs/ |
| T-0.4 | מצלמה עם deadzone + גבולות מפה | godot-dev | בדיקה |
| T-0.5 | קונטרולים מובייל: joystick + 3 כפתורים, auto-attack toggle | godot-dev | screenshot ב-390×844 |
| T-0.6 | shared-rules: `damage()`, `xp_for_level()`, `roll_loot()` | server-dev | 30+ בדיקות unit |
| T-0.7 | YAML: הממריץ (5 מיומנויות רמות 1-10), 3 מפלצות, 10 פריטים | game-designer | validate + sim ירוקים |
| T-0.8 | מכניקת "קראש": אחרי 4 פגיעות ברצף → 2 שניות פגיעות ×2 | godot-dev | בדיקה + הרגשה מתועדת |
| T-0.9 | מפלצות: AI פשוט (patrol/chase/attack), HP bar, מוות + דרופ | godot-dev | 3 סוגים על המפה |
| T-0.10 | XP, עלייה ברמה, UI של סטטים | godot-dev | רמה 10 מושגת תוך 15 דק' משחק (סימולציה) |
| T-0.11 | Inventory בסיסי + השוואת ציוד | godot-dev | screenshot |
| T-0.12 | NPC "רוקח" עם 3 שורות דיאלוג + חנות | game-designer + godot-dev | קנייה/מכירה נבדקות |
| T-0.13 | שמירה מקומית (JSON) | godot-dev | צא-והיכנס משמר מצב |
| T-0.14 | export ל-Android APK + Windows | devops | APK רץ (בן-אדם מאשר) |

**Human Checkpoint:** לשחק 20 דקות בנייד. לענות: "זה כיף?" אם לא — לא ממשיכים לשלב 1. זה השלב הכי חשוב.

### שלב 1 — מערכת מקצועות מלאה (שבועות 5-8)
| # | משימה | סוכן | DoD |
|---|---|---|---|
| T-1.1 | 4 ארכיטיפים נוספים: YAML מלא (5 מיומנויות כל אחד) | game-designer | sim: אף ארכיטיפ > 15% |
| T-1.2 | מכניקות ייחודיות: Numb (חסינות דיבאף), Illusion (עותקים + "רואה" מפלצות רפאים), Zen (slow zone + heal), Rage (נזק ∝ HP חסר) | godot-dev ×4 (מקביל) | בדיקה לכל מכניקה |
| T-1.3 | מסך בחירת ארכיטיפ עם טקסט סאטירי | godot-dev + game-designer | screenshot |
| T-1.4 | הסתעפות ברמה 10: 2 "מינונים" לכל ארכיטיפ (10 תת-מקצועות) | game-designer | YAML + sim |
| T-1.5 | "טופס עלייה במינון 27-ב" — UI בירוקרטי קומי לשדרוג | godot-dev | screenshot |
| T-1.6 | 3 אזורים חדשים (10 מפלצות סה"כ, 1 בוס) | art-pipeline + game-designer + godot-dev | sim + screenshot |
| T-1.7 | Affixes לפריטים (10 affixes) | game-designer + server-dev | בדיקות roll_loot |
| T-1.8 | עקומת XP סופית לרמות 1-30 | game-designer | sim: רמה 30 ≈ 12 שעות |

**Human Checkpoint:** playtest של כל ארכיטיפ 10 דק'. אישור טון הטקסטים.

### שלב 2 — Multiplayer קליל (שבועות 9-13)
| # | משימה | סוכן | DoD |
|---|---|---|---|
| T-2.1 | protocol.md גרסה 1: join/leave/input/state/attack/damage/loot/chat | protocol-designer | check_protocol_sync ירוק |
| T-2.2 | שרת: room אחד, 4 שחקנים, tick 20Hz, authoritative movement | server-dev | sim_clients 4 |
| T-2.3 | קליינט: net layer, client-side prediction + reconciliation | godot-dev | 200ms latency מדומה — ללא רעידות |
| T-2.4 | לחימה דרך השרת: attack intent → damage event | server-dev + godot-dev | 2 קליינטים רואים אותו HP |
| T-2.5 | Loot per-player | server-dev | בדיקה: 2 שחקנים, 2 דרופים שונים |
| T-2.6 | בונוס XP קבוצתי | server-dev | shared-rules test |
| T-2.7 | צ'אט + אימוג'י מהיר (מובייל) | godot-dev | screenshot |
| T-2.8 | ניתוק/חיבור מחדש באמצע קרב | server-dev + qa | בדיקה |
| T-2.9 | הסרת כל הלוגיקה single-player מהקליינט (השרת תמיד, גם solo — local server mode) | godot-dev | grep: אין `damage(` בקליינט מחוץ ל-rules/ |

**Human Checkpoint:** 3 אנשים משחקים ביחד 30 דק' ברשת מקומית.

### שלב 3 — Persistence ושרת אמיתי (שבועות 14-18)
| # | משימה | סוכן | DoD |
|---|---|---|---|
| T-3.1 | Drizzle schema: users, characters, inventory, progress | server-dev | migrate up/down |
| T-3.2 | Auth: email+password / guest → JWT; refresh; rate limit | server-dev + anticheat | בדיקות |
| T-3.3 | שמירה אסינכרונית (write-behind queue → Postgres) + Redis למצב חי | server-dev | crash test: 0 אובדן > 5 שניות |
| T-3.4 | 3 דמויות לחשבון, מסך בחירה | godot-dev | screenshot |
| T-3.5 | anticheat v1: speed check, cooldown check, sanity על כל input | anticheat-reviewer + server-dev | בדיקות התקפה |
| T-3.6 | Docker prod image + deploy.sh staging (Fly.io) | devops | staging חי |
| T-3.7 | WSS + certificates | devops | קליינט מתחבר ל-staging |
| T-3.8 | Logging/metrics (pino + Prometheus endpoint) | devops | dashboard בסיסי |

**Human Checkpoint:** פתיחת חשבון ענן, אישור עלויות, בדיקה על staging מנייד אמיתי דרך 4G.

### שלב 4 — Scale (שבועות 19-24)
| # | משימה | סוכן | DoD |
|---|---|---|---|
| T-4.1 | Zones כ-processes נפרדים, gateway מנתב | server-dev + devops | sim_clients 200 על 4 zones |
| T-4.2 | Interest management (רדיוס) | server-dev | traffic/שחקן < 10KB/s |
| T-4.3 | MessagePack במקום JSON | protocol-designer + שני הצדדים | ‑60% traffic |
| T-4.4 | מעבר בין zones (portal) עם handoff | server-dev | בדיקה: אין אובדן state |
| T-4.5 | anticheat v2: server-side replay validation, anomaly flags | anticheat-reviewer | דוח |
| T-4.6 | Load test 500 שחקנים מדומים 1 שעה | qa + devops | p95 tick < 30ms |
| T-4.7 | Autoscale / restart policy | devops | zone crash → recovery < 10s |

**Human Checkpoint:** אישור תקציב שרתים חודשי.

### שלב 5 — תוכן ופוליש (שבועות 25-32+)
| # | משימה | סוכן | DoD |
|---|---|---|---|
| T-5.1 | 5 אזורים נוספים, 30 מפלצות, 5 בוסים | game-designer + art + godot | sim ירוק |
| T-5.2 | Quests: 20 "משימות רפואיות" בירוקרטיות | game-designer | YAML + בדיקה |
| T-5.3 | מסחר בין שחקנים (trade window, escrow בשרת) | server-dev + anticheat | dup test |
| T-5.4 | Auction house בסיסי | server-dev + godot-dev | בדיקות |
| T-5.5 | Guilds ("קופות חולים") | server-dev + godot-dev | בדיקות |
| T-5.6 | Localization מלא he/en, RTL UI | godot-dev | screenshots בשתי שפות |
| T-5.7 | Sound/music placeholders + hooks לאמן | godot-dev | — |
| T-5.8 | Onboarding 5 דקות ראשונות | game-designer + godot-dev | playtest |
| T-5.9 | Store listing, privacy policy, ToS (בן-אדם + AI טיוטה) | doc-keeper | — |
| T-5.10 | Release Flow מלא → soft launch | כולם | — |

**Human Checkpoint:** החלפת placeholder art באמנות אמיתית (מחוץ להיקף ה-AI), משפטי, חנויות.

---

## 11. איך מתחילים מחר בבוקר

1. צור ריפו `hamirpaa`, העתק את `docs/GDD.md` (המסמך הקיים) ואת המסמך הזה ל-`docs/WORKPLAN.md`.
2. צור `CLAUDE.md` מסעיף 3.
3. צור `TASKS.md` עם משימות שלב -1 בלבד (T-I.1 עד T-I.8), כולן `ready`.
4. צור `PROGRESS.md` עם שורה אחת: "Session 0: repo created, nothing built yet."
5. הרץ Claude Code בשורש הריפו עם הפרומפט:
   > "קרא CLAUDE.md ו-docs/WORKPLAN.md. בצע T-I.1 — צור את כל מבנה .claude/ (agents, skills, settings.json עם hooks) ואת scripts/ לפי סעיפים 4-7 של WORKPLAN. אל תתחיל T-I.2 לפני ש-T-I.1 נבדק."
6. מכאן והלאה הפרומפט לכל סשן הוא זהה: **"המשך לפי CLAUDE.md."** — ה-hooks וה-TASKS.md עושים את השאר.

---

## 12. מדדי בריאות (לבדוק כל שבוע)

| מדד | יעד | איפה |
|---|---|---|
| check.sh ירוק | 100% מה-commits | CI |
| כיסוי בדיקות shared-rules | > 90% | vitest --coverage |
| משימות blocked | < 3 בכל זמן | TASKS.md |
| Questions for human | נענות תוך 48 שעות | TASKS.md |
| גודל build Android | < 60MB | export_builds.sh |
| p95 tick (משלב 2) | < 30ms | metrics |
