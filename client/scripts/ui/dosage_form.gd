class_name DosageForm
extends CanvasLayer
## T-1.5: "טופס עלייה במינון 27-ב" — the bureaucratic level-up form. Every level-up is, in this
## world, an approval that the clinic grants you retroactively and takes no responsibility for; this
## panel is where the player reads it.
##
## SHELL (per TASKS.md T-1.5): it displays the stat grants the authority ALREADY applied — it never
## grants anything itself and has no branching choices yet. The real "2 dosages per archetype" branch
## at level 10 is T-1.4, blocked on Q1 (the real GDD), so the form shows that section as pending an
## ethics-committee approval rather than faking a choice.
##
## Works against either CombatAuthority (client/scripts/combat/combat_authority.gd). Note that in net
## mode RemoteAuthority.get_stats() reports attack/defense as 0.0 — the server does not put them in
## `state` snapshots — so those rows simply do not appear there, while max_hp (which IS in the
## snapshot) does. Rows are built from whatever actually changed, so this degrades cleanly instead of
## rendering "0 → 0" lines.

## Emitted once the player has signed (in triplicate). `level` is the approved level, so main.gd can
## save on approval without re-reading the authority.
signal approved(level: int)

## Stat rows the form reports on, in display order. Keys of CombatAuthority.get_stats(); the label
## for each comes from the matching ui.dosage_form.stat.* i18n key.
const STAT_KEYS: Array[String] = ["max_hp", "attack", "defense"]

## Display-only: how long the "APPROVED" stamp stays on screen after signing, before the form closes
## (or the next queued form replaces it). Same idea as hud.gd's LEVEL_UP_FLASH_S — not a balance number.
const STAMP_HOLD_S: float = 0.6

## Grant rows are built in code, so they do not inherit the scene's per-label colour overrides — on
## the form's cream paper the theme default is almost invisible. Same ink as the scene's other body
## labels (see dosage_form.tscn).
const INK: Color = Color(0.12, 0.12, 0.14, 1.0)

@onready var root: Control = $Root
@onready var title_label: Label = $Root/Window/Margin/Content/Header/TitleLabel
@onready var subtitle_label: Label = $Root/Window/Margin/Content/SubtitleLabel
@onready var applicant_label: Label = $Root/Window/Margin/Content/ApplicantLabel
@onready var grade_label: Label = $Root/Window/Margin/Content/GradeLabel
@onready var granted_label: Label = $Root/Window/Margin/Content/GrantedLabel
@onready var grants_vbox: VBoxContainer = $Root/Window/Margin/Content/GrantsVBox
@onready var pending_label: Label = $Root/Window/Margin/Content/PendingLabel
@onready var side_effects_label: Label = $Root/Window/Margin/Content/SideEffectsLabel
@onready var approve_button: Button = $Root/Window/Margin/Content/ApproveButton
@onready var stamp_label: Label = $Root/StampLabel
@onready var stamp_timer: Timer = $StampTimer

var _authority: CombatAuthority = null
var _entity_id: String = ""
var _archetype: String = ""
## Last stats seen for _entity_id, so the NEXT level-up can be reported as a delta. The authority's
## level_up signal only carries the new stats, never the old ones.
var _prev_stats: Dictionary = {}
## Pending forms, oldest first. A single xp award can cross several levels at once (a big kill at low
## level), and every one of them is its own form — the clinic does not batch paperwork.
var _queue: Array[Dictionary] = []
var _current_level: int = 0


func _ready() -> void:
	root.visible = false
	stamp_label.visible = false
	title_label.text = I18n.t("ui.dosage_form.title")
	subtitle_label.text = I18n.t("ui.dosage_form.subtitle")
	pending_label.text = I18n.t("ui.dosage_form.pending")
	side_effects_label.text = I18n.t("ui.dosage_form.side_effects")
	granted_label.text = I18n.t("ui.dosage_form.granted")
	approve_button.text = I18n.t("ui.dosage_form.approve")
	stamp_label.text = I18n.t("ui.dosage_form.stamp")
	stamp_timer.wait_time = STAMP_HOLD_S
	stamp_timer.one_shot = true
	stamp_timer.timeout.connect(_on_stamp_timer_timeout)
	approve_button.pressed.connect(_on_approve_pressed)


## Wires the form to `entity_id`'s level-ups on `authority`. `archetype` is only used for the
## applicant line's display name (docs/balance/classes.yaml's name_key) — never for any number.
func bind(authority: CombatAuthority, entity_id: String, archetype: String) -> void:
	_authority = authority
	_entity_id = entity_id
	_archetype = archetype
	_prev_stats = _snapshot(authority.get_stats(entity_id))
	authority.level_up.connect(_on_level_up)


## Re-reads the authority's current stats as the baseline the NEXT level-up is measured against.
## Call after anything that moves level/stats WITHOUT a level_up signal — loading a save
## (LocalServer.set_progress sets level directly and stays silent) or a gear change. Without this the
## first level-up after a load would be reported as a delta from the level-1 baseline taken at bind().
func resync() -> void:
	if _authority == null:
		return
	_prev_stats = _snapshot(_authority.get_stats(_entity_id))


func is_open() -> bool:
	return root.visible


## How many forms are still waiting to be signed (the one on screen is not counted — it is no longer
## queued). Lets a test prove that a multi-level jump produces one form per level.
func pending_count() -> int:
	return _queue.size()


func _snapshot(stats: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in STAT_KEYS:
		out[key] = float(stats.get(key, 0.0))
	out["level"] = float(stats.get("level", 0.0))
	return out


func _on_level_up(id: String, new_level: float, stats: Dictionary) -> void:
	if id != _entity_id:
		return
	var next: Dictionary = _snapshot(stats)
	_queue.append({"level": int(new_level), "from": _prev_stats, "to": next})
	_prev_stats = next
	if not root.visible:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		root.visible = false
		return
	var form: Dictionary = _queue.pop_front()
	_current_level = int(form["level"])
	_render(form)
	stamp_label.visible = false
	approve_button.disabled = false
	root.visible = true


func _render(form: Dictionary) -> void:
	var from_stats: Dictionary = form["from"]
	var to_stats: Dictionary = form["to"]
	applicant_label.text = "%s: %s" % [I18n.t("ui.dosage_form.applicant"), I18n.t(_archetype_name_key())]
	grade_label.text = (
		"%s: %d → %d"
		% [I18n.t("ui.dosage_form.grade"), int(from_stats.get("level", 0.0)), _current_level]
	)

	for child: Node in grants_vbox.get_children():
		child.queue_free()
		grants_vbox.remove_child(child)

	var rows: int = 0
	for key: String in STAT_KEYS:
		var before: float = float(from_stats.get(key, 0.0))
		var after: float = float(to_stats.get(key, 0.0))
		if is_equal_approx(before, after):
			continue
		var row: Label = Label.new()
		row.text = (
			"%s: %d → %d (%+d)"
			% [I18n.t("ui.dosage_form.stat.%s" % key), int(before), int(after), int(after) - int(before)]
		)
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", INK)
		grants_vbox.add_child(row)
		rows += 1

	if rows == 0:
		var none: Label = Label.new()
		none.text = I18n.t("ui.dosage_form.no_change")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_font_size_override("font_size", 14)
		none.add_theme_color_override("font_color", INK)
		grants_vbox.add_child(none)


func _archetype_name_key() -> String:
	var archetypes: Dictionary = RulesBalanceData.CLASSES.get("archetypes", {})
	var def: Dictionary = archetypes.get(_archetype, {})
	return String(def.get("name_key", _archetype))


## Signing does not close the form instantly: the stamp has to be visible long enough to read, so the
## form stays up (with the button disabled, so it cannot be signed twice) until STAMP_HOLD_S elapses.
## Only then does the next queued form — or an empty screen — take over.
func _on_approve_pressed() -> void:
	if not root.visible or approve_button.disabled:
		return
	stamp_label.visible = true
	approve_button.disabled = true
	approved.emit(_current_level)
	stamp_timer.start()


func _on_stamp_timer_timeout() -> void:
	_show_next()
