extends Node
## Autoload (see project.godot [autoload], registered as I18nBoot) that
## populates I18n's table BEFORE the main scene (and everything under it,
## e.g. touch_controls.gd's buttons) runs _ready(). Autoloads enter the tree
## — and get their own _ready() — before the main scene is instantiated, so
## this ordering is guaranteed rather than a lucky coincidence.
##
## docs/content/*.yaml is a flat `key: value` list (one per line, `#`
## comments, no nesting) so a hand-rolled parser is enough for phase 0.
## Reads via the same "escape res://" pattern client/tests/test_rules_xp.gd
## already uses for shared-rules fixtures. Replace with a real build-time
## export into res:// once content grows past flat key/value pairs.

const DEFAULT_LANG: String = "he"


func _ready() -> void:
	I18n.load_table(_load_content_table(DEFAULT_LANG))


func _load_content_table(lang: String) -> Dictionary:
	var table: Dictionary = {}
	var f: FileAccess = FileAccess.open("res://../docs/content/%s.yaml" % lang, FileAccess.READ)
	if f == null:
		push_warning("i18n content table not found for lang '%s'" % lang)
		return table
	while not f.eof_reached():
		var trimmed: String = f.get_line().strip_edges()
		if trimmed.is_empty() or trimmed.begins_with("#"):
			continue
		var sep: int = trimmed.find(": ")
		if sep == -1:
			continue
		table[trimmed.substr(0, sep)] = trimmed.substr(sep + 2)
	return table
