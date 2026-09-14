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

## מפת דרכים
תוכנית השלבים המלאה (שלב -1 עד שלב 5), ה-Flows, ומדדי הבריאות נמצאים ב-docs/WORKPLAN.md. TASKS.md מכיל רק את המשימות של השלב הנוכחי.
