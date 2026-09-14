# GDD — "המרפאה" (Hamirpaa)

> ⚠️ **PLACEHOLDER.** The real Game Design Document already exists outside this repo and must be
> copied over this file by a human (see TASKS.md Q1). What follows is only the subset of facts the
> WORKPLAN relies on, so agents have a consistent reference until the real GDD lands.

## Elevator pitch
A satirical 2D platformer MMORPG. Players are "patients" of a giant pharma conglomerate, levelling
up by increasing their "dosage". Tone: bureaucratic-absurd comedy. Nothing graphic, no real drugs,
no usage instructions, no romanticising addiction — everything fictional and exaggerated.

## Archetypes (5) — colour code for placeholder art
| id | Hebrew | Colour | Fantasy |
|---|---|---|---|
| stim | הממריץ | yellow | fast, burst, "crash" after 4 consecutive hits (2s, damage taken ×2) |
| numb | המאלחש | blue-grey | tank, debuff immunity |
| illusion | ההוזה | purple | clones; sees "ghost" monsters |
| zen | המרגיע | green | slow zone + heal |
| rage | הזועם | red | damage ∝ missing HP |

Each archetype: 5 skills over levels 1–10. At level 10: branch into 2 "dosages" (sub-classes) → 10 total.
Upgrade UI: "טופס עלייה במינון 27-ב".

## Core loop
Move/jump (coyote-time, jump buffer) → fight monsters (simple patrol/chase/attack AI) → XP → level →
loot with affixes → NPC "רוקח" (pharmacist) shop → new zones → bosses.

## Multiplayer
Server-authoritative. Client sends intents, server sends state. Rooms of 4 (phase 2) → zones as
separate processes with a gateway (phase 4). Per-player loot. Group XP bonus. Guilds = "קופות חולים".

## Targets
- Level 10 reachable in ~15 minutes; level 30 ≈ 12 hours.
- Normal monster TTK 3–8 s. No archetype wins >15% more often than others.
- Mobile first (390×844), then desktop (1920×1080), then web.
