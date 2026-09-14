extends SceneTree
## One-off tool: builds client/assets/generated/tileset_clinic.tres from the
## generated tileset_clinic.png (see scripts/gen_tileset.py, which owns tile
## order/colours). Runs through the engine itself so the TileSet resource
## format is Godot-validated rather than hand-written.
## Usage: godot --headless --path client -s tools/gen_tileset_resource.gd
## Re-run whenever tileset_clinic.png's tile layout/order changes.

## Must match docs/art/specs/tileset_clinic.yaml `tiles:` order exactly —
## that order is the atlas column index (col 0 = "ground", col 1 =
## "ground_top", ...).
const TILE_NAMES: Array[String] = ["ground", "ground_top", "platform", "wall", "background", "accent"]
const SOLID_TILES: Array[String] = ["ground", "ground_top", "platform", "wall"]
const TILE_SIZE: int = 32

const SRC_PNG: String = "res://assets/generated/tileset_clinic.png"
const OUT_TRES: String = "res://assets/generated/tileset_clinic.tres"


func _init() -> void:
	var tex: Texture2D = load(SRC_PNG)
	if tex == null:
		push_error("%s not found — run scripts/gen_tileset.py first" % SRC_PNG)
		quit(1)
		return

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var physics_layer: int = tile_set.get_physics_layers_count()
	tile_set.add_physics_layer(physics_layer)
	tile_set.set_physics_layer_collision_layer(physics_layer, 1)
	tile_set.set_physics_layer_collision_mask(physics_layer, 1)

	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	# Link the source to the tile set BEFORE creating tiles: TileData only
	# allocates per-layer physics slots once it knows the owning TileSet's
	# physics layer count.
	tile_set.add_source(source, 0)

	var half: float = TILE_SIZE / 2.0
	var full_tile_polygon: PackedVector2Array = PackedVector2Array(
		[Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
	)

	for i in range(TILE_NAMES.size()):
		var coords := Vector2i(i, 0)
		source.create_tile(coords)
		if TILE_NAMES[i] in SOLID_TILES:
			var data: TileData = source.get_tile_data(coords, 0)
			data.add_collision_polygon(physics_layer)
			data.set_collision_polygon_points(physics_layer, 0, full_tile_polygon)

	var err: Error = ResourceSaver.save(tile_set, OUT_TRES)
	if err != OK:
		push_error("save failed: %s" % err)
		quit(1)
		return
	print("saved %s" % OUT_TRES)
	quit(0)
