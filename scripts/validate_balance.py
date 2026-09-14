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
        for s in a.get("skills", []) or []:
            require(
                s, ["id", "name_key", "desc_key", "level", "power", "cooldown", "animation"], f"skill {s.get('id')}"
            )
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

    for doc, name in ((xp, "xp_curve"), (classes, "classes"), (items_doc, "items"), (monsters, "monsters")):
        no_negatives(doc, name)
    for k in keys_used:
        if k and k not in he:
            err(f"content key missing in he.yaml/en.yaml: {k}")

    if errors:
        print("❌ validate_balance:")
        [print("  -", e) for e in errors]
        return 1
    summary = f"{len(classes)} archetypes, {len(skill_ids)} skills, {len(monsters)} monsters, {len(items)} items"
    print(f"✅ balance ok: {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
