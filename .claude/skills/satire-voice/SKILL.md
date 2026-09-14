---
name: satire-voice
description: Tone guide for all game text in Hamirpaa — bureaucratic, cynical, absurd pharma-corp satire; vocabulary; hard red lines; NPC template. Load before writing any dialogue, skill description, item name or UI copy.
---
# Satire voice

## The voice
The world is run by a pharma conglomerate that treats every human need as a form to be filed. The comedy is in the **gap between clinical language and absurd content**. Deadpan. Never wink at the player. The system is always polite and always unhelpful.

**Good:** "תופעות הלוואי כוללות: ביטחון עצמי מופרז, ראייה כפולה של המציאות, ואישור מוועדת האתיקה." (12 words, clinical form, absurd payload)
**Good:** "המרפאה סגורה לצהריים. גם אתם." 
**Bad:** "LOL you're so high right now!!" (breaks deadpan, references real intoxication)
**Bad:** "Take two of these and call me in the morning" (real-world dosage instruction)
**Bad:** long explanations of the joke. Max 12 words for a skill description.

## Vocabulary (use liberally)
מינון · טופס · אישור · תופעות לוואי · רוקח · ועדת אתיקה · נספח · בשלושה עותקים · תור · הפניה · קופת חולים · מכסה · פרוטוקול טיפול · חתימת מנהל · "לא באחריותנו" · מרשם · ביטוח משלים · סעיף קטן.
English mirrors: dosage · form · approval · side effects · pharmacist · ethics committee · appendix · in triplicate · referral · HMO · quota · treatment protocol · "not our liability".

## Red lines (hard — non-negotiable)
- No real drug names, brands, or recognisable street names. Everything is fictional: "ממריץ 27-ב", "טיפת שלווה".
- No dosage or usage instructions, real or implied. No "how it feels" descriptions of real substances.
- No romanticising addiction, withdrawal, or overdose. "Crash" is a game mechanic word, keep it mechanical.
- No mocking of real patients or real conditions. The target is the corporation and the bureaucracy, never the sick.
- Not graphic. Blood-free. Monsters are "side effects", "paperwork", "lost referrals".

## i18n
Every string is a key in `docs/content/he.yaml` AND `docs/content/en.yaml`. Hebrew is the primary voice; English is a translation of the joke, not the words. Keys: `<domain>.<id>.<field>` e.g. `npc.pharmacist.greet`.

## NPC template
```yaml
npc.<id>.name: <שם>          # e.g. "רוקח בכיר משה"
# role: shop | quest | flavour
npc.<id>.greet: <one line>    # ברכה
npc.<id>.shop: <one line>     # חנות / שירות
npc.<id>.bye: <one line>      # פרידה
# quirk (one, in docs/content/npcs.md): e.g. "stamps every sentence with a rubber stamp sound"
```
