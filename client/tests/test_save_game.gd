extends GutTest
## T-0.13 DoD: save()/load() round trip real files under user://, and every
## failure mode (missing file, corrupt JSON, non-object JSON, version
## mismatch) returns {} with a push_warning instead of crashing.

const TEST_PATH: String = "user://test_save_game.json"
const OTHER_PATH: String = "user://test_save_game_other.json"


func after_each() -> void:
	for p: String in [TEST_PATH, OTHER_PATH]:
		if SaveGame.exists(p):
			SaveGame.delete(p)


func test_default_path_is_the_documented_slot() -> void:
	assert_eq(SaveGame.default_path(), "user://save_v1.json")


func test_exists_false_before_any_save() -> void:
	assert_false(SaveGame.exists(TEST_PATH))


func test_save_returns_ok_and_creates_the_file() -> void:
	var err: Error = SaveGame.save(TEST_PATH, {"player": {"level": 1}})
	assert_eq(err, OK)
	assert_true(SaveGame.exists(TEST_PATH))


func test_save_then_load_round_trip() -> void:
	# Godot's JSON parser has no int type — every number comes back as a
	# float, so assertions below cast explicitly rather than comparing whole
	# Dictionaries (see SaveGame's header for why that's unreliable).
	var data: Dictionary = {
		"player": {"archetype": "stim", "level": 3, "total_xp": 120, "hp": 90, "position": [12.5, -4.0]},
		"inventory": {"capacity": 20, "slots": [{"item_id": "expired_bandage", "count": 2}], "equipped": {}},
	}
	SaveGame.save(TEST_PATH, data)
	var loaded: Dictionary = SaveGame.load(TEST_PATH)

	var player: Dictionary = loaded["player"]
	assert_eq(String(player["archetype"]), "stim")
	assert_eq(int(player["level"]), 3)
	assert_eq(int(player["total_xp"]), 120)
	assert_eq(int(player["hp"]), 90)
	assert_eq(float(player["position"][0]), 12.5)
	assert_eq(float(player["position"][1]), -4.0)

	var inventory: Dictionary = loaded["inventory"]
	assert_eq(int(inventory["capacity"]), 20)
	assert_eq(inventory["slots"].size(), 1)
	assert_eq(String(inventory["slots"][0]["item_id"]), "expired_bandage")
	assert_eq(int(inventory["slots"][0]["count"]), 2)
	assert_eq(inventory["equipped"], {})


func test_save_stamps_version_and_saved_at() -> void:
	SaveGame.save(TEST_PATH, {})
	var loaded: Dictionary = SaveGame.load(TEST_PATH)
	assert_eq(loaded["version"], SaveGame.SAVE_VERSION)
	assert_true(loaded.has("saved_at"))
	assert_true(int(loaded["saved_at"]) > 0)


func test_save_overwrites_caller_supplied_version() -> void:
	SaveGame.save(TEST_PATH, {"version": 999, "saved_at": 1})
	var loaded: Dictionary = SaveGame.load(TEST_PATH)
	assert_eq(loaded["version"], SaveGame.SAVE_VERSION, "save() always stamps its own version")


func test_load_missing_file_returns_empty_dict() -> void:
	assert_eq(SaveGame.load(TEST_PATH), {})


func test_load_corrupt_json_returns_empty_dict() -> void:
	var f: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{ not valid json ][")
	f.close()
	assert_eq(SaveGame.load(TEST_PATH), {})


func test_load_non_object_json_returns_empty_dict() -> void:
	var f: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	assert_eq(SaveGame.load(TEST_PATH), {})


func test_load_version_mismatch_returns_empty_dict() -> void:
	var f: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": SaveGame.SAVE_VERSION + 1, "player": {}}))
	f.close()
	assert_eq(SaveGame.load(TEST_PATH), {})


func test_delete_removes_the_file() -> void:
	SaveGame.save(TEST_PATH, {})
	assert_true(SaveGame.exists(TEST_PATH))
	assert_eq(SaveGame.delete(TEST_PATH), OK)
	assert_false(SaveGame.exists(TEST_PATH))


func test_delete_is_idempotent_when_file_missing() -> void:
	assert_false(SaveGame.exists(TEST_PATH))
	assert_eq(SaveGame.delete(TEST_PATH), OK)


func test_save_and_load_use_independent_paths() -> void:
	SaveGame.save(TEST_PATH, {"player": {"level": 1}})
	SaveGame.save(OTHER_PATH, {"player": {"level": 9}})
	assert_eq(SaveGame.load(TEST_PATH)["player"]["level"], 1)
	assert_eq(SaveGame.load(OTHER_PATH)["player"]["level"], 9)
