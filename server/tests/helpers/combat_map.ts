import type { MapDef } from "../../src/world/tilemap.js";

/**
 * A small flat-ground test map with exactly one monster spawned near the player spawn point —
 * clinic_lobby's real monster positions require walking many ticks to get in range, which combat
 * tests don't need or want. Same ground-row convention as zone_movement.test.ts's flatMap(): one row
 * of solid ground at the bottom, walls left/right, air everywhere else.
 */
export function combatMap(monsterKind: string, opts: { cellsAway?: number } = {}): MapDef {
  const cols = 20;
  const rows = 10;
  const layout: string[] = [];
  for (let r = 0; r < rows; r++) {
    layout.push(r === rows - 1 ? "#".repeat(cols) : "W" + ".".repeat(cols - 2) + "W");
  }
  const spawnCol = 5;
  const monsterCol = spawnCol + (opts.cellsAway ?? 0);
  const tileSize = 32;
  return {
    id: "combat_test",
    tile_size: tileSize,
    cols,
    rows,
    // Same "already resting on the ground" y as flatMap()'s spawn — player.gd/player_sim.ts settle
    // instantly instead of needing a free-fall tick before combat can start.
    spawn: { x: spawnCol * tileSize + tileSize / 2, y: tileSize * (rows - 1) - 16 - 1 },
    solid_chars: ["#", "W"],
    layout,
    monster_spawns: [{ id: monsterKind, cell: [monsterCol, rows - 2] }],
  };
}
