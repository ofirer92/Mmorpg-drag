#!/usr/bin/env python3
"""Validate docs/balance/*.yaml: required keys, no negative numbers, every skill belongs to an existing
archetype, every loot entry references an existing item, every *_key exists in he.yaml AND en.yaml."""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
BAL, CONTENT = ROOT / "docs/balance", ROOT / "docs/content"
ARCHETYPES = {"stim", "numb", "illusion", "zen", "rage"}
ITEM_SLOTS = {"weapon", "head", "body", "consumable"}
ITEM_RARITIES = {"common", "rare", "epic"}
ITEM_STAT_KEYS = {"attack", "defense", "hp"}
errors: list[str] = []


def err(msg: str):
    errors.append(msg)


def load(name: str) -> dict:
    p = BAL / name
    if not p.exists():
        err(f"missing {p.relative_to(ROOT)}")
        return {}
    return yaml.safe_load(p.read_text()) or {}


def no_negatives(obj, path: str):
    if isinstance(obj, dict):
        for k, v in obj.items():
            no_negatives(v, f"{path}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            no_negatives(v, f"{path}[{i}]")
    elif isinstance(obj, (int, float)) and not isinstance(obj, bool) and obj < 0:
        err(f"negative value at {path}: {obj}")


def require(d: dict, keys: list[str], path: str):
    for k in keys:
        if k not in d:
            err(f"{path}: missing key '{k}'")


def main() -> int:
    he = yaml.safe_load((CONTENT / "he.yaml").read_text()) or {}
    en = yaml.safe_load((CONTENT / "en.yaml").read_text()) or {}
    for k in set(he) ^ set(en):
        err(f"content key only in one language: {k}")
    keys_used: set[str] = set()

    xp = load("xp_curve.yaml")
    require(xp, ["max_level", "base", "exponent", "linear"], "xp_curve")
    if xp.get("max_level", 0) < 2:
        err("xp_curve.max_level must be ≥ 2")

    classes = load("classes.yaml").get("archetypes", {})
    if set(classes) != ARCHETYPES:
        err(f"classes.yaml archetypes must be exactly {sorted(ARCHETYPES)}, got {sorted(classes)}")
    skill_ids: set[str] = set()
    for aid, a in classes.items():
        require(
            a,
            ["name_key", "colour", "base_hp", "base_attack", "base_defense", "attack_speed", "move_speed", "skills"],
            f"classes.{aid}",
        )
        keys_used.add(a.get("name_key", ""))
        growth = a.get("growth")
        if not isinstance(growth, dict):
            err(f"classes.{aid}: missing growth")
        else:
            require(growth, ["hp", "attack", "defense"], f"classes.{aid}.growth")
        for s in a.get("skills", []) or []:
            require(
                s,
                [
                    "id",
                    "name_key",
                    "desc_key",
                    "level",
                    "power",
                    "hits",
                    "cooldown",
                    "crash_hits",
                    "range_px",
                    "animation",
                ],
                f"skill {s.get('id')}",
            )
            if not 1 <= s.get("level", 0) <= xp.get("max_level", 30):
                err(f"skill {s.get('id')}: level must be within 1..max_level")
            if s.get("id") in skill_ids:
                err(f"duplicate skill id {s['id']}")
            skill_ids.add(s.get("id"))
            if not str(s.get("id", "")).startswith(aid + "_"):
                err(f"skill {s.get('id')} must be prefixed with archetype '{aid}_'")
            keys_used.update([s.get("name_key", ""), s.get("desc_key", "")])

    items_doc = load("items.yaml")
    items = items_doc.get("items", {})
    tables = items_doc.get("loot_tables", {})
    for iid, it in items.items():
        require(it, ["name_key", "slot", "rarity", "value"], f"items.{iid}")
        keys_used.add(it.get("name_key", ""))
        if it.get("slot") is not None and it["slot"] not in ITEM_SLOTS:
            err(f"items.{iid}: slot must be one of {sorted(ITEM_SLOTS)}, got {it.get('slot')}")
        if it.get("rarity") is not None and it["rarity"] not in ITEM_RARITIES:
            err(f"items.{iid}: rarity must be one of {sorted(ITEM_RARITIES)}, got {it.get('rarity')}")
        stats = it.get("stats")
        if stats is not None:
            if not isinstance(stats, dict) or set(stats) != ITEM_STAT_KEYS:
                err(f"items.{iid}: stats must have exactly keys {sorted(ITEM_STAT_KEYS)}")
            else:
                for sk, sv in stats.items():
                    if not isinstance(sv, (int, float)) or isinstance(sv, bool) or sv < 0:
                        err(f"items.{iid}: stats.{sk} must be a non-negative number")
    for tid, t in tables.items():
        require(t, ["rolls", "entries"], f"loot_tables.{tid}")
        for e in t.get("entries", []):
            if e.get("item") is not None and e["item"] not in items:
                err(f"loot_tables.{tid}: unknown item {e['item']}")
            if e.get("weight", 0) <= 0:
                err(f"loot_tables.{tid}: weight must be > 0")

    monsters = load("monsters.yaml").get("monsters", {})
    for mid, m in monsters.items():
        require(
            m,
            ["name_key", "level", "hp", "attack", "defense", "attack_speed", "xp", "loot_table", "ai"],
            f"monsters.{mid}",
        )
        keys_used.add(m.get("name_key", ""))
        if m.get("loot_table") not in tables:
            err(f"monsters.{mid}: unknown loot_table {m.get('loot_table')}")
        if m.get("ai") not in {"patrol", "chase", "boss"}:
            err(f"monsters.{mid}: ai must be patrol|chase|boss")
        if m.get("hp", 1) <= 0:
            err(f"monsters.{mid}: hp must be > 0")
        money = m.get("money")
        if not isinstance(money, dict) or "min" not in money or "max" not in money:
            err(f"monsters.{mid}: missing money {{min, max}}")
        elif money["max"] < money["min"]:
            err(f"monsters.{mid}: money.max < money.min")
        ai = m.get("ai_params")
        if not isinstance(ai, dict):
            err(f"monsters.{mid}: missing ai_params")
        else:
            require(
                ai,
                ["patrol_speed", "chase_speed", "aggro_radius", "attack_range", "leash_radius", "patrol_distance"],
                f"monsters.{mid}.ai_params",
            )
            if ai.get("leash_radius", 0) < ai.get("aggro_radius", 0):
                err(f"monsters.{mid}: leash_radius must be ≥ aggro_radius")

    npcs = load("npcs.yaml").get("npcs", {})
    for nid, n in npcs.items():
        require(n, ["name_key", "role", "lines", "stock", "map_cell"], f"npcs.{nid}")
        keys_used.add(n.get("name_key", ""))
        for line_key in (n.get("lines") or {}).values():
            keys_used.add(line_key)
        for sid in n.get("stock", []) or []:
            if sid not in items:
                err(f"npcs.{nid}: unknown stock item {sid}")

    for doc, name in (
        (xp, "xp_curve"),
        (classes, "classes"),
        (items_doc, "items"),
        (monsters, "monsters"),
        (npcs, "npcs"),
    ):
        no_negatives(doc, name)
    for k in keys_used:
        if k and k not in he:
            err(f"content key missing in he.yaml/en.yaml: {k}")

    if errors:
        print("❌ validate_balance:")
        [print("  -", e) for e in errors]
        return 1
    counts = [len(classes), len(skill_ids), len(monsters), len(items), len(npcs)]
    summary = "%d archetypes, %d skills, %d monsters, %d items, %d npcs" % tuple(counts)
    print(f"✅ balance ok: {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
