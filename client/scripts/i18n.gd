class_name I18n
## Game text lookup. Keys live in docs/content/{he,en}.yaml — never string literals in code.
## Phase -1: keys are loaded from a JSON export of the YAML (T-0.x adds the loader); missing key returns the key itself.

static var _lang: String = "he"
static var _table: Dictionary = {}


static func set_language(lang: String) -> void:
	_lang = lang


static func load_table(table: Dictionary) -> void:
	_table = table


static func t(key: String) -> String:
	if _table.has(key):
		return str(_table[key])
	return key
