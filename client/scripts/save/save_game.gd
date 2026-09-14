class_name SaveGame
extends RefCounted
## T-0.13: local save/load, JSON, single slot. A pure module — it does NOT
## know about Player/LocalServer/Inventory; the caller assembles the
## Dictionary to save (typically from Player state + Inventory.to_dict())
## and hands it to save(), and applies whatever load() returns back onto
## those objects itself.
##
## Save file shape (save() stamps "version" and "saved_at" itself — callers
## only need to provide the rest):
## {
##   "version": int,                 # SAVE_VERSION; a mismatch on load = {}
##   "saved_at": int,                # unix seconds, set by save()
##   "player": {
##     "archetype": String,
##     "level": int,
##     "total_xp": int,
##     "hp": int,
##     "position": [x: float, y: float],
##   },
##   "inventory": <Inventory.to_dict()>,
## }
##
## load() never crashes: a missing file, corrupt JSON, a JSON value that
## isn't an object, or a version mismatch all push_warning() and return {}.
##
## Godot JSON caveat: every number round-trips through JSON as a float
## (JSON.parse_string() has no int type), even if it was written as an int.
## Callers must cast fields back explicitly when reading load()'s result,
## e.g. `int(loaded.player.level)` — never compare a whole loaded Dictionary
## for equality against an int-typed one, it will spuriously fail
## (Array/Dictionary `==` in Godot requires exact per-value type match).

const SAVE_VERSION: int = 1
const DEFAULT_PATH: String = "user://save_v1.json"


static func default_path() -> String:
	return DEFAULT_PATH


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


## Writes `data` as JSON to `path`, adding/overwriting "version" and
## "saved_at". Returns OK, or the FileAccess error on failure.
static func save(path: String, data: Dictionary) -> Error:
	var out: Dictionary = data.duplicate(true)
	out["version"] = SAVE_VERSION
	out["saved_at"] = int(Time.get_unix_time_from_system())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var open_err: Error = FileAccess.get_open_error()
		push_warning("SaveGame.save: cannot open %s for writing (%s)" % [path, open_err])
		return open_err
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	return OK


## Reads and validates the JSON at `path`. Returns {} (with a push_warning)
## if the file is missing, unreadable, not valid JSON, not a JSON object, or
## saved by an incompatible version.
static func load(path: String) -> Dictionary:
	if not exists(path):
		push_warning("SaveGame.load: no save file at %s" % path)
		return {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("SaveGame.load: cannot open %s for reading (%s)" % [path, FileAccess.get_open_error()])
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("SaveGame.load: corrupt/non-object JSON at %s" % path)
		return {}
	var loaded: Dictionary = parsed
	if int(loaded.get("version", -1)) != SAVE_VERSION:
		push_warning(
			"SaveGame.load: version mismatch at %s (expected %d, got %s)" % [path, SAVE_VERSION, loaded.get("version")]
		)
		return {}
	return loaded


## Deletes the save file at `path`. Returns OK if it didn't exist to begin
## with (delete is idempotent), or the DirAccess error on failure.
static func delete(path: String) -> Error:
	if not exists(path):
		return OK
	return DirAccess.remove_absolute(path)
