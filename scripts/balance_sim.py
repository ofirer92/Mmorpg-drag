#!/usr/bin/env python3
"""Simulate N fights per archetype × monster → docs/balance/report.md (TTK, win-rate, XP/hour).
Formulas mirror .claude/skills/balance-methodology. Uses the same damage model as shared-rules via
packages/shared-rules/src/_balance_data.ts semantics (numbers), not by importing TS."""

from __future__ import annotations

import argparse
import math
import random
import statistics
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
BAL = ROOT / "docs/balance"
DEF_SCALE = 20.0  # must equal DEF_SCALE in packages/shared-rules/src/_constants.ts
CRIT_CHANCE, CRIT_MULT = 0.05, 1.5
OVERHEAD = 0.6  # fraction of an hour actually spent fighting


def damage(att: float, dfn: float, power: float, roll: float) -> float:
    base = max(1.0, (att * power - dfn * 0.5) // 1)
    return (base * CRIT_MULT) // 1 if roll < CRIT_CHANCE else base


def xp_for_level(level: int, c: dict) -> int:
    if level <= 1:
        return 0
    n = level - 1
    return math.floor(c["base"] * n ** c["exponent"] + c["linear"] * n)


def xp_total_for_level(level: int, c: dict) -> int:
    return sum(xp_for_level(lv, c) for lv in range(2, level + 1))


def time_to_level(a: dict, monsters: dict, xp_curve: dict, rng: random.Random, target: int = 10) -> float:
    """Seconds for one archetype to reach `target` grinding the lowest-level monster, stats growing per level."""
    m = min(monsters.values(), key=lambda mm: mm["level"])
    g = a["growth"]
    level, total_xp, t = 1, 0.0, 0.0
    while level < target and t < 3600 * 24:
        n = level - 1
        hero = dict(a)
        hero["base_hp"] = a["base_hp"] + g["hp"] * n
        hero["base_attack"] = a["base_attack"] + g["attack"] * n
        hero["base_defense"] = a["base_defense"] + g["defense"] * n
        won, dt = fight(hero, m, rng)
        t += dt / OVERHEAD
        if won:
            total_xp += m["xp"]
            while level < xp_curve["max_level"] and total_xp >= xp_total_for_level(level + 1, xp_curve):
                level += 1
    return t


def fight(a: dict, m: dict, rng: random.Random) -> tuple[bool, float]:
    hp_a, hp_m, t = float(a["base_hp"]), float(m["hp"]), 0.0
    next_a, next_m = 0.0, 0.5 / m["attack_speed"]
    power = max([s["power"] for s in a.get("skills") or []] or [1.0])
    while t < 600:
        t = min(next_a, next_m)
        if t == next_a:
            hp_m -= damage(a["base_attack"], m["defense"], power, rng.random())
            next_a += 1.0 / a["attack_speed"]
            if hp_m <= 0:
                return True, t
        else:
            hp_a -= damage(m["attack"], a["base_defense"], 1.0, rng.random())
            next_m += 1.0 / m["attack_speed"]
            if hp_a <= 0:
                return False, t
    return False, t


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fights", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    classes = yaml.safe_load((BAL / "classes.yaml").read_text())["archetypes"]
    monsters = yaml.safe_load((BAL / "monsters.yaml").read_text())["monsters"]
    rows, spread_fail = [], []
    for mid, m in monsters.items():
        wins = {}
        for aid, a in classes.items():
            res = [fight(a, m, rng) for _ in range(args.fights)]
            wr = sum(1 for w, _ in res if w) / len(res)
            ttk = [t for w, t in res if w] or [float("nan")]
            mean_ttk = statistics.fmean(ttk)
            p90 = sorted(ttk)[int(0.9 * (len(ttk) - 1))]
            xph = (3600 * OVERHEAD / mean_ttk) * m["xp"] * wr if mean_ttk == mean_ttk and mean_ttk > 0 else 0
            wins[aid] = wr
            flag = "" if 3 <= mean_ttk <= 8 or m["ai"] == "boss" else " ⚠️TTK"
            rows.append(f"| {aid} | {mid} | {wr:.0%} | {mean_ttk:.1f}s | {p90:.1f}s | {xph:,.0f}{flag} |")
        spread = max(wins.values()) - min(wins.values())
        rows.append(f"| **spread** | {mid} | {spread:.0%}{' ⚠️>15%' if spread > 0.15 else ''} | | | |")
        if spread > 0.15:
            spread_fail.append(mid)
    xp_curve = yaml.safe_load((BAL / "xp_curve.yaml").read_text())
    prog_rows = []
    for aid, a in classes.items():
        minutes = time_to_level(a, monsters, xp_curve, rng) / 60
        prog_rows.append(f"| {aid} | {minutes:.1f} min{'' if 10 <= minutes <= 20 else ' ⚠️target 15±5'} |")
    report = [
        "# Balance report",
        f"fights per pair: {args.fights}, seed {args.seed}",
        "",
        "| archetype | monster | win-rate | mean TTK | p90 TTK | XP/hour |",
        "|---|---|---|---|---|---|",
        *rows,
        "",
        "Thresholds: spread ≤ 15 pts on the majority of monsters; normal TTK 3–8 s.",
        "",
        "## Time to level 10 (grinding the lowest-level monster, T-0.10 target ≈ 15 min)",
        "",
        "| archetype | time |",
        "|---|---|",
        *prog_rows,
    ]
    verdict = "APPROVED" if len(spread_fail) <= len(monsters) / 2 else "NOT APPROVED"
    report.append(
        f"\n**Verdict: {verdict}**" + (f" — spread > 15% on: {', '.join(spread_fail)}" if spread_fail else "")
    )
    (BAL / "report.md").write_text("\n".join(report) + "\n")
    print("\n".join(report))
    return 0 if verdict == "APPROVED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
