"""Regenerates the vertical clinic_lobby tower.

Run:  python3 scripts/gen_map_tower.py

Writes the layout into BOTH places that describe the map — docs/maps/clinic_lobby.yaml (the server's
copy) and client/scripts/maps/clinic_lobby.gd's LAYOUT (the client's) — plus the spawn, the monster
cells and the pharmacist's map_cell. Keeping one generator means the ADR-016 parity between those two
copies cannot drift, and that re-shaping the tower is a parameter change rather than 60 rows of
hand-editing done twice.

Platform spacing is DERIVED from RulesMovement, not chosen by eye: a full jump rises v^2/2g, so
ledges sit exactly that many whole tiles apart. The asserts here are load-bearing — they are what
stops a "nicer looking" edit from silently producing a tower the player cannot climb or fit inside.
After running this, run scripts/gen_rules.py (balance data) and scripts/check.sh."""

import pathlib
import re

COLS, ROWS, TILE = 20, 60, 32
WALL, GROUND, PLAT, AIR, ACCENT = "W", "#", "=", ".", "A"

# RulesMovement (packages/shared-rules/src/movement.ts) — max rise of a full jump.
JUMP_V, GRAV = 520.0, 1800.0
MAX_RISE_PX = JUMP_V * JUMP_V / (2 * GRAV)
MAX_RISE_ROWS = int(MAX_RISE_PX // TILE)  # 2 rows
STEP = MAX_RISE_ROWS  # vertical gap between platform tops
assert STEP >= 2, "jump must clear at least 2 rows"

GROUND_ROW = ROWS - 1
TOP_PLATFORM_ROW = 3
# Platform rows, climbing from just above the ground to near the ceiling.
PLATFORM_ROWS = list(range(GROUND_ROW - 2, TOP_PLATFORM_ROW - 1, -STEP))

INTERIOR = COLS - 2  # cols 1..COLS-2
# Cols 1..3 are a permanently open SHAFT: no ledge ever covers them. The player spawns there with
# unlimited headroom, and it doubles as a fall-through route back down the tower. Without it the
# spawn sits under a ledge with one row (32px) of clearance and a 30px-tall body — the player
# literally spawns clipped into the ceiling and cannot move (found by server sim, not by eye).
SHAFT_END = 3
LEFT = (SHAFT_END + 1, 11)
RIGHT = (12, COLS - 2)


def span(i):
    """Ledges alternate left/right every STEP rows. The two lanes are column-ADJACENT (left ends 11,
    right starts 12) so the diagonal jump between them always has somewhere to land."""
    return LEFT if i % 2 == 0 else RIGHT


rows = []
for r in range(ROWS):
    if r == GROUND_ROW:
        rows.append(WALL + GROUND * INTERIOR + WALL)
        continue
    line = [AIR] * INTERIOR
    if r in PLATFORM_ROWS:
        a, b = span(PLATFORM_ROWS.index(r))
        for c in range(a, b + 1):
            line[c - 1] = PLAT
    rows.append(WALL + "".join(line) + WALL)

# Decorative signage high on the tower, in open air.
acc = TOP_PLATFORM_ROW - 2
rows[acc] = rows[acc][:9] + ACCENT * 2 + rows[acc][11:]

# The shaft must really be clear, all the way up — the spawn's headroom depends on it.
for r, line in enumerate(rows):
    if r == GROUND_ROW:
        continue
    assert all(line[c] == AIR for c in range(1, SHAFT_END + 1)), f"row {r} blocks the shaft"

# --- spawn + occupants, all derived from the layout so they cannot be invalid ----------------
SPAWN_COL = 2  # inside the shaft
spawn = {"x": SPAWN_COL * TILE + TILE // 2, "y": GROUND_ROW * TILE - 18}


def stand_on(row_index, col):
    """The air cell directly above a solid tile — the convention MONSTER_SPAWNS/map_cell use."""
    assert rows[row_index][col] == AIR, (row_index, col)
    assert rows[row_index + 1][col] in (GROUND, PLAT, WALL), (row_index, col)
    return (col, row_index)


def ledge_cell(i, offset=2):
    r = PLATFORM_ROWS[i]
    a, b = span(i)
    return stand_on(r - 1, min(a + offset, b))


monsters = [
    ("side_effect_slime", stand_on(GROUND_ROW - 1, 16)),
    ("side_effect_slime", ledge_cell(1)),
    ("side_effect_slime", ledge_cell(4)),
    ("lost_referral", ledge_cell(9)),
    ("lost_referral", ledge_cell(14)),
    ("form_27b", ledge_cell(len(PLATFORM_ROWS) - 2)),
]
npc_cell = stand_on(GROUND_ROW - 1, SHAFT_END)  # shaft-side, so the pharmacist is not under a ledge

print(f"max jump rise {MAX_RISE_PX:.1f}px = {MAX_RISE_ROWS} rows; step {STEP}")
print(f"{COLS}x{ROWS} tiles = {COLS * TILE}x{ROWS * TILE}px; {len(PLATFORM_ROWS)} platforms")
print("spawn", spawn, "npc", npc_cell)
for m in monsters:
    print("  monster", m)

root = pathlib.Path("/home/user/Mmorpg-drag")

# --- docs/maps/clinic_lobby.yaml ---------------------------------------------------------------
y = root / "docs/maps/clinic_lobby.yaml"
src = y.read_text(encoding="utf-8")
src = re.sub(r"^cols: \d+$", f"cols: {COLS}", src, flags=re.M)
src = re.sub(r"^rows: \d+$", f"rows: {ROWS}", src, flags=re.M)
src = re.sub(r"^spawn:\n  x: .*\n  y: .*$", f"spawn:\n  x: {spawn['x']}\n  y: {spawn['y']}", src, flags=re.M)
src = re.sub(r"^layout:\n(?:  - \".*\"\n?)+", "layout:\n" + "".join(f'  - "{r}"\n' for r in rows), src, flags=re.M)
mon_yaml = "monster_spawns:\n" + "".join(f"  - {{id: {mid}, cell: [{c}, {r}]}}\n" for mid, (c, r) in monsters)
src = re.sub(r"^monster_spawns:\n(?:  - .*\n?)+", mon_yaml, src, flags=re.M)
y.write_text(src, encoding="utf-8")

# --- client/scripts/maps/clinic_lobby.gd -------------------------------------------------------
g = root / "client/scripts/maps/clinic_lobby.gd"
src = g.read_text(encoding="utf-8")
src = re.sub(r"const GRID_COLS: int = \d+", f"const GRID_COLS: int = {COLS}", src)
src = re.sub(r"const GRID_ROWS: int = \d+", f"const GRID_ROWS: int = {ROWS}", src)
src = re.sub(
    r"const LAYOUT: Array\[String\] = \[\n(?:\t\".*\",\n)+\]",
    "const LAYOUT: Array[String] = [\n" + "".join(f'\t"{r}",\n' for r in rows) + "]",
    src,
)
src = re.sub(
    r"const MONSTER_SPAWNS: Array\[Dictionary\] = \[\n(?:\t\{.*\},\n)+\]",
    "const MONSTER_SPAWNS: Array[Dictionary] = [\n"
    + "".join(f'\t{{"id": "{mid}", "cell": Vector2i({c}, {r})}},\n' for mid, (c, r) in monsters)
    + "]",
    src,
)
g.write_text(src, encoding="utf-8")

# --- docs/balance/npcs.yaml --------------------------------------------------------------------
n = root / "docs/balance/npcs.yaml"
src = n.read_text(encoding="utf-8")
src = re.sub(r"map_cell: \[\d+, \d+\]", f"map_cell: [{npc_cell[0]}, {npc_cell[1]}]", src)
n.write_text(src, encoding="utf-8")
print("written")
