---
name: balance-methodology
description: Balance formulas (TTK, DPS, EHP, XP/hour), YAML templates for monsters/items/skills, how to run and read balance_sim.py, and approval thresholds. Load for any change under docs/balance/.
---
# Balance methodology

## Formulas
- `DPS = attack_per_hit × attack_speed` where `attack_per_hit = damage(attacker, defender, power, roll=0.5)` from shared-rules.
- `EHP = hp × (1 + defense / DEF_SCALE)` (DEF_SCALE in shared-rules constants).
- `TTK(a → b) = EHP_b / DPS_a` seconds.
- `XP/hour = Σ over kills in 1 simulated hour (monster.xp) — with travel/respawn overhead factor 0.6`.
- Level curve: `xp_for_level(L)` from docs/balance/xp_curve.yaml; time-to-level = cumulative xp / XP-per-hour at that level band.

## YAML templates
```yaml
# monster
<id>:
  name_key: monster.<id>.name
  level: 1
  hp: 40
  attack: 5
  defense: 1
  attack_speed: 0.8
  xp: 12
  loot_table: <table id>
  ai: patrol | chase | boss
# item
<id>:
  name_key: item.<id>.name
  slot: weapon | head | body | consumable
  rarity: common | rare | epic
  value: 3
  stats: { attack: 0, defense: 0, hp: 0 }
  affixes: []          # phase 1 T-1.7
# skill (inside archetypes.<id>.skills)
- id: <archetype>_<name>
  name_key: skill.<id>.name
  desc_key: skill.<id>.desc
  level: 1
  power: 1.0
  cooldown: 0.0
  animation: <placeholder name>
```

## Running the sim
```
python3 scripts/validate_balance.py        # schema, no negatives, every skill's archetype exists
python3 scripts/balance_sim.py             # 1000 fights per archetype × monster → docs/balance/report.md
```
Report columns: archetype, monster, win-rate, mean TTK, p90 TTK, XP/hour. Read the **spread** row: max win-rate minus min win-rate across archetypes for the same monster.

## Approval thresholds
- No archetype wins > 15 percentage points more than the lowest archetype on the majority of monsters.
- Normal monster TTK for a same-level player: **3–8 s**. Boss: 60–180 s for a 4-player group.
- Level 10 in ≈ 15 min; level 30 ≈ 12 h (±20%).
- A player at monster level must win ≥ 90% 1v1 vs a normal monster; ≤ 30% vs a boss solo.
Outside thresholds → not approved; iterate the YAML, re-run, attach report.md to the commit.
