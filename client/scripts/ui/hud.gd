class_name Hud
extends CanvasLayer
## T-0.10: top-left HUD overlay — hp bar, xp bar + level, and a collapsible
## stats panel. `bind()` wires this to a LocalServer entity and only ever
## DISPLAYS what LocalServer/RulesProgression report; it never computes
## hp/xp/stats itself (CLAUDE.md: the client never computes damage/XP).
##
## Positioned below the title label (client/scenes/main.tscn's Label sits at
## y 16–60; this HUD's Panel starts at y 64) and clear of the touch controls
## (which live in the bottom half of the screen) at both 390×844 and
## 1920×1080 — see client/tests/test_hud.gd.

## Display-only: how long the level-up flash label stays visible. Not a
## balance number.
const LEVEL_UP_FLASH_S: float = 1.0

@onready var hp_label: Label = $Panel/HpLabel
@onready var hp_bar: ProgressBar = $Panel/HpBar
@onready var xp_label: Label = $Panel/XpLabel
@onready var xp_bar: ProgressBar = $Panel/XpBar
@onready var stats_toggle: Button = $Panel/StatsToggleButton
@onready var stats_panel: VBoxContainer = $Panel/StatsPanel
@onready var level_detail: Label = $Panel/StatsPanel/LevelDetailLabel
@onready var hp_detail: Label = $Panel/StatsPanel/HpDetailLabel
@onready var attack_detail: Label = $Panel/StatsPanel/AttackDetailLabel
@onready var defense_detail: Label = $Panel/StatsPanel/DefenseDetailLabel
@onready var xp_detail: Label = $Panel/StatsPanel/XpDetailLabel
@onready var level_up_label: Label = $LevelUpLabel
@onready var level_up_timer: Timer = $LevelUpTimer

## T-2.4: typed against CombatAuthority (LocalServer in single-player,
## RemoteAuthority in net mode) — see client/scripts/combat/combat_authority.gd.
var _server: CombatAuthority = null
var _entity_id: String = ""


func _ready() -> void:
	stats_toggle.text = I18n.t("ui.hud.stats")
	level_up_label.text = I18n.t("ui.hud.level_up")
	level_up_label.visible = false
	stats_panel.visible = false

	level_up_timer.wait_time = LEVEL_UP_FLASH_S
	level_up_timer.one_shot = true
	level_up_timer.timeout.connect(_on_level_up_timer_timeout)
	stats_toggle.toggled.connect(_on_stats_toggled)


## Wires this HUD to `entity_id`'s facts on `server` and does one initial
## refresh from its current get_stats() (so the HUD is correct even if it's
## bound after the entity already took damage/gained xp).
func bind(server: CombatAuthority, entity_id: String) -> void:
	_server = server
	_entity_id = entity_id
	server.damage_dealt.connect(_on_damage_dealt)
	server.entity_died.connect(_on_entity_died)
	server.xp_gained.connect(_on_xp_gained)
	server.level_up.connect(_on_level_up)
	server.healed.connect(_on_healed)
	server.stats_synced.connect(_on_stats_synced)
	_refresh_from_stats(server.get_stats(entity_id))


func is_stats_panel_open() -> bool:
	return stats_panel.visible


func _refresh_from_stats(stats: Dictionary) -> void:
	_update_hp(stats.hp, stats.max_hp)
	_update_xp(stats.total_xp, stats.level)
	_update_stats_panel(stats)


## max_hp == 0 means "the authority has not told us yet" (net mode, before the first `state` lands) —
## NOT "dead at 0/0", which is what a naive render looks like. Show a no-data placeholder instead.
func _update_hp(hp: float, max_hp: float) -> void:
	hp_bar.max_value = max(max_hp, 1.0)
	hp_bar.value = hp
	if max_hp <= 0.0:
		hp_label.text = "%s %s" % [I18n.t("ui.hud.hp"), I18n.t("ui.hud.no_data")]
		return
	hp_label.text = "%s %d/%d" % [I18n.t("ui.hud.hp"), int(hp), int(max_hp)]


func _update_xp(total_xp: float, level: float) -> void:
	var into: float = RulesProgression.xp_into_level(total_xp, level)
	var need: float = RulesProgression.xp_to_next_level(level)
	xp_bar.max_value = max(need, 1.0)
	xp_bar.value = into
	xp_label.text = "%s %d — %s" % [I18n.t("ui.hud.level"), int(level), I18n.t("ui.hud.xp")]


func _update_stats_panel(stats: Dictionary) -> void:
	level_detail.text = "%s: %d" % [I18n.t("ui.hud.level"), int(stats.level)]
	if float(stats.max_hp) <= 0.0:
		hp_detail.text = "%s: %s" % [I18n.t("ui.hud.hp"), I18n.t("ui.hud.no_data")]
	else:
		hp_detail.text = "%s: %d/%d" % [I18n.t("ui.hud.hp"), int(stats.hp), int(stats.max_hp)]
	attack_detail.text = "%s: %d" % [I18n.t("ui.hud.attack"), int(stats.attack)]
	defense_detail.text = "%s: %d" % [I18n.t("ui.hud.defense"), int(stats.defense)]
	var into: float = RulesProgression.xp_into_level(stats.total_xp, stats.level)
	var need: float = RulesProgression.xp_to_next_level(stats.level)
	xp_detail.text = "%s: %d/%d" % [I18n.t("ui.hud.xp"), int(into), int(need)]


func _on_damage_dealt(target_id: String, _amount: float, _new_hp: float, _crit: bool) -> void:
	if target_id != _entity_id:
		return
	_refresh_from_stats(_server.get_stats(_entity_id))


func _on_entity_died(id: String, _xp: float, _drop_item_id: String, _drop_affixes: Array) -> void:
	if id != _entity_id:
		return
	_update_hp(0.0, _server.get_max_hp(_entity_id))


func _on_xp_gained(id: String, _amount: float, total_xp: float, level: float) -> void:
	if id != _entity_id:
		return
	_update_xp(total_xp, level)


func _on_level_up(id: String, _new_level: float, stats: Dictionary) -> void:
	if id != _entity_id:
		return
	_refresh_from_stats(stats)
	level_up_label.visible = true
	level_up_timer.start()


func _on_level_up_timer_timeout() -> void:
	level_up_label.visible = false


func _on_stats_toggled(pressed: bool) -> void:
	stats_panel.visible = pressed


## Re-read the server's stats (after a save is loaded, gear changes, ...).
func refresh() -> void:
	if _server == null:
		return
	_refresh_from_stats(_server.get_stats(_entity_id))


func _on_healed(id: String, _amount: float, _new_hp: float) -> void:
	if id == _entity_id:
		refresh()


func _on_stats_synced(id: String) -> void:
	if id == _entity_id:
		refresh()
