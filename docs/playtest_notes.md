# Playtest notes

## Stim "crash" feel (T-0.8)

- Tuned the visual-only bits in `client/scripts/player/player.gd`: a flat red
  tint (`CRASH_TINT`, no fade in/out — abrupt on purpose, so the moment you
  cross the 4-hit threshold is unmistakable) plus a ±2px random horizontal
  jitter on the sprite each physics frame (`CRASH_SHAKE_PX`), reset the
  instant `crash_ended` fires.
- Deliberately did NOT slow the player's movement or lock input during a
  crash — only incoming damage is doubled (`damage_taken_mult` from
  classes.yaml). A human should playtest whether "still fully mobile but
  fragile" reads as intended, or whether it needs a movement/attack-speed
  penalty too to feel like a genuine "crash" rather than just a damage debuff.
- 2-second duration (from classes.yaml, not tuned by this session) felt long
  enough in manual testing (via the arena scene) to notice but short enough
  not to feel punishing after a single overextended combo — a human should
  confirm against real monster damage output once game-designer numbers land.
