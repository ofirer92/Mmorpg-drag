#!/usr/bin/env python3
"""Regenerate packages/shared-rules/tests/fixtures/xp_curve.json from docs/balance/xp_curve.yaml,
packages/shared-rules/tests/fixtures/combat.json (damage() + roll_loot() cases), and
packages/shared-rules/tests/fixtures/affixes.json (roll_affix_id() + affix_count() cases, T-1.7).
The fixtures are asserted by both Vitest (TS) and GUT (generated GDScript) — the T-I.5 parity proof."""

from __future__ import annotations

import json
import math
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "packages/shared-rules/tests/fixtures/xp_curve.json"
COMBAT_OUT = ROOT / "packages/shared-rules/tests/fixtures/combat.json"
AFFIXES_OUT = ROOT / "packages/shared-rules/tests/fixtures/affixes.json"

# Kept in sync BY HAND with packages/shared-rules/src/_constants.ts. If those change, update here too.
CRIT_CHANCE = 0.05
CRIT_MULT = 1.5
MIN_DAMAGE = 1


def damage_py(attacker: dict, defender: dict, power: float, roll: float) -> int:
    """Same formula as damage() in packages/shared-rules/src/combat.ts — keep both in sync."""
    raw = attacker["attack"] * power - defender["defense"] * 0.5
    base = max(MIN_DAMAGE, math.floor(raw))
    level_diff = attacker["level"] - defender["level"]
    diff_mult = 1 + max(-0.25, min(0.25, level_diff * 0.05))
    scaled = math.floor(base * diff_mult)
    if roll < CRIT_CHANCE:
        scaled = math.floor(scaled * CRIT_MULT)
    return max(MIN_DAMAGE, scaled)


def roll_loot_py(table_id: str, roll: float, items: dict) -> str:
    """Same formula as roll_loot() in packages/shared-rules/src/loot.ts — keep both in sync."""
    table = items["loot_tables"].get(table_id)
    if table is None:
        return ""
    total = sum(e["weight"] for e in table["entries"])
    if total <= 0:
        return ""
    cumulative = 0.0
    for e in table["entries"]:
        cumulative += e["weight"]
        if roll < cumulative / total:
            return e["item"] or ""
    return ""


def gen_combat_fixture() -> None:
    items = yaml.safe_load((ROOT / "docs/balance/items.yaml").read_text())
    damage_cases = [
        {
            "attacker": {"attack": 20, "defense": 4, "level": 5, "hp": 90},
            "defender": {"attack": 5, "defense": 5, "level": 5, "hp": 60},
            "power": 1.0,
            "roll": 0.5,
        },
        {
            "attacker": {"attack": 20, "defense": 4, "level": 5, "hp": 90},
            "defender": {"attack": 5, "defense": 5, "level": 5, "hp": 60},
            "power": 1.0,
            "roll": 0.049,
        },
        {
            "attacker": {"attack": 20, "defense": 4, "level": 5, "hp": 90},
            "defender": {"attack": 5, "defense": 5, "level": 5, "hp": 60},
            "power": 1.0,
            "roll": 0.05,
        },
        {
            "attacker": {"attack": 1, "defense": 0, "level": 1, "hp": 10},
            "defender": {"attack": 1, "defense": 100, "level": 1, "hp": 10},
            "power": 1.0,
            "roll": 0.9,
        },
        {
            "attacker": {"attack": 12, "defense": 4, "level": 20, "hp": 90},
            "defender": {"attack": 5, "defense": 1, "level": 1, "hp": 60},
            "power": 1.0,
            "roll": 0.5,
        },
        {
            "attacker": {"attack": 12, "defense": 4, "level": 1, "hp": 90},
            "defender": {"attack": 5, "defense": 1, "level": 20, "hp": 60},
            "power": 1.0,
            "roll": 0.5,
        },
        {
            "attacker": {"attack": 10, "defense": 0, "level": 3, "hp": 50},
            "defender": {"attack": 5, "defense": 0, "level": 3, "hp": 50},
            "power": 1.0,
            "roll": 0.5,
        },
        {
            "attacker": {"attack": 10, "defense": 4, "level": 3, "hp": 50},
            "defender": {"attack": 5, "defense": 5, "level": 3, "hp": 50},
            "power": 0.0,
            "roll": 0.5,
        },
        {
            "attacker": {"attack": 10, "defense": 4, "level": 3, "hp": 50},
            "defender": {"attack": 5, "defense": 5, "level": 3, "hp": 50},
            "power": 2.5,
            "roll": 0.5,
        },
        {
            "attacker": {"attack": 12, "defense": 4, "level": 20, "hp": 90},
            "defender": {"attack": 5, "defense": 1, "level": 1, "hp": 60},
            "power": 1.0,
            "roll": 0.01,
        },
    ]
    for c in damage_cases:
        c["expected"] = damage_py(c["attacker"], c["defender"], c["power"], c["roll"])

    loot_cases = [
        {"table_id": "common_trash", "roll": 0.0},
        {"table_id": "common_trash", "roll": 0.1},
        {"table_id": "common_trash", "roll": 0.5},
        {"table_id": "common_trash", "roll": 0.699},
        {"table_id": "common_trash", "roll": 0.7},
        {"table_id": "common_trash", "roll": 0.71},
        {"table_id": "common_trash", "roll": 0.85},
        {"table_id": "common_trash", "roll": 0.999},
        {"table_id": "does_not_exist", "roll": 0.1},
        {"table_id": "does_not_exist", "roll": 0.9},
    ]
    for c in loot_cases:
        c["expected"] = roll_loot_py(c["table_id"], c["roll"], items)

    COMBAT_OUT.parent.mkdir(parents=True, exist_ok=True)
    COMBAT_OUT.write_text(
        json.dumps(
            {
                "_comment": "generated by scripts/gen_fixtures.py — damage()/roll_loot() cases, "
                "computed in Python with the same formulas as packages/shared-rules/src/combat.ts "
                "and loot.ts. Asserted by combat.test.ts, loot.test.ts AND client/tests/test_rules_combat.gd.",
                "damage_cases": damage_cases,
                "loot_cases": loot_cases,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"wrote {COMBAT_OUT.relative_to(ROOT)}: {len(damage_cases)} damage cases, {len(loot_cases)} loot cases")


def affix_allows_rarity_py(affix_id: str, rarity: str, affixes: dict) -> bool:
    """Same rule as affix_allows_rarity() in packages/shared-rules/src/affixes.ts — keep in sync."""
    ax = affixes.get(affix_id)
    if ax is None:
        return False
    return rarity in ax["rarities"]


def affix_weight_py(affix_id: str, affixes: dict) -> float:
    """Same formula as affix_weight() in packages/shared-rules/src/affixes.ts — keep in sync."""
    ax = affixes.get(affix_id)
    if ax is None:
        return 0
    return ax["weight"]


def roll_affix_id_py(rarity: str, roll: float, affixes: dict, affix_order: list) -> str:
    """Same formula as roll_affix_id() in packages/shared-rules/src/affixes.ts — keep in sync."""
    total = 0.0
    for aid in affix_order:
        if affix_allows_rarity_py(aid, rarity, affixes):
            total += affix_weight_py(aid, affixes)
    if total <= 0:
        return ""
    cumulative = 0.0
    for aid in affix_order:
        if affix_allows_rarity_py(aid, rarity, affixes):
            cumulative += affix_weight_py(aid, affixes)
            if roll < cumulative / total:
                return aid
    return ""


def affix_count_py(rarity: str, roll: float, affix_slots: dict) -> int:
    """Same formula as affix_count() in packages/shared-rules/src/affixes.ts — keep in sync."""
    slot = affix_slots.get(rarity)
    if slot is None:
        return 0
    lo = slot["min"]
    hi = max(lo, slot["max"])
    span = hi - lo + 1
    return lo + min(span - 1, math.floor(max(0.0, roll) * span))


def gen_affixes_fixture() -> None:
    items = yaml.safe_load((ROOT / "docs/balance/items.yaml").read_text())
    affixes = items["affixes"]
    affix_order = items["affix_order"]
    affix_slots = items["affix_slots"]

    roll_affix_id_cases = [
        {"rarity": "common", "roll": 0.0},
        {"rarity": "common", "roll": 0.25},
        {"rarity": "common", "roll": 0.5},
        {"rarity": "common", "roll": 0.999},
        {"rarity": "rare", "roll": 0.0},
        {"rarity": "rare", "roll": 0.4},
        {"rarity": "rare", "roll": 0.9},
        {"rarity": "epic", "roll": 0.1},
        {"rarity": "epic", "roll": 0.999},
        {"rarity": "does_not_exist", "roll": 0.5},
    ]
    for c in roll_affix_id_cases:
        c["expected"] = roll_affix_id_py(c["rarity"], c["roll"], affixes, affix_order)

    affix_count_cases = [
        {"rarity": "common", "roll": 0.0},
        {"rarity": "common", "roll": 0.999},
        {"rarity": "rare", "roll": 0.5},
        {"rarity": "epic", "roll": 0.999},
        {"rarity": "does_not_exist", "roll": 0.5},
    ]
    for c in affix_count_cases:
        c["expected"] = affix_count_py(c["rarity"], c["roll"], affix_slots)

    AFFIXES_OUT.parent.mkdir(parents=True, exist_ok=True)
    AFFIXES_OUT.write_text(
        json.dumps(
            {
                "_comment": "generated by scripts/gen_fixtures.py — roll_affix_id()/affix_count() cases, "
                "computed in Python with the same formulas as packages/shared-rules/src/affixes.ts. "
                "Asserted by affixes.test.ts AND client/tests/test_rules_affixes.gd.",
                "roll_affix_id_cases": roll_affix_id_cases,
                "affix_count_cases": affix_count_cases,
            },
            indent=2,
        )
        + "\n"
    )
    print(
        f"wrote {AFFIXES_OUT.relative_to(ROOT)}: {len(roll_affix_id_cases)} roll_affix_id cases, "
        f"{len(affix_count_cases)} affix_count cases"
    )


def main() -> int:
    c = yaml.safe_load((ROOT / "docs/balance/xp_curve.yaml").read_text())
    xp: dict[int, int] = {}
    for level in range(1, c["max_level"] + 1):
        n = level - 1
        xp[level] = 0 if level <= 1 else math.floor(c["base"] * n ** c["exponent"] + c["linear"] * n)
    totals: dict[int, int] = {}
    running = 0
    for level in range(1, c["max_level"] + 1):
        running += xp[level]
        totals[level] = running
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(
            {
                "_comment": "generated by scripts/gen_fixtures.py from docs/balance/xp_curve.yaml — do not edit",
                "xp_for_level": xp,
                "xp_total_for_level": totals,
            },
            indent=2,
        )
        + "\n"
    )
    print(f"wrote {OUT.relative_to(ROOT)}: level 10 = {xp[10]}, level 30 total = {totals[30]}")
    gen_combat_fixture()
    gen_affixes_fixture()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
