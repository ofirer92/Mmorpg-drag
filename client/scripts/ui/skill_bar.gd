class_name SkillBar
extends CanvasLayer
## T-0.7: one button per Stim skill (docs/balance/classes.yaml
## archetypes.stim.skills, levels 1/3/5/7/10) — shows the skill's name, a
## locked-until-level message, or the seconds left on cooldown, all read from
## LocalServer/RulesSkills. Tapping an unlocked button makes it the skill_1
## target via Player.select_skill(). This node never computes damage or
## cooldown itself — only DISPLAYS what LocalServer/RulesSkills report
## (CLAUDE.md: the client never computes damage/XP).

## Display refresh cadence for the cooldown countdown label — not a balance number.
const REFRESH_INTERVAL_S: float = 0.1

@onready var bar: HBoxContainer = $Bar
@onready var refresh_timer: Timer = $RefreshTimer

## Exposed for tests (same pattern as hud.gd's public @onready bars/labels).
var buttons: Array[Button] = []
var status_labels: Array[Label] = []
## Skill ids in archetypes.stim.skills order — buttons[i]/status_labels[i] is skill_ids[i].
var skill_ids: Array[String] = []

## T-2.4: typed against CombatAuthority (LocalServer in single-player,
## RemoteAuthority in net mode) — see client/scripts/combat/combat_authority.gd.
var _server: CombatAuthority = null
var _player: Player = null
var _entity_id: String = ""
var _skills: Array = []


func _ready() -> void:
	_skills = RulesBalanceData.CLASSES.archetypes.stim.skills
	for slot: Node in bar.get_children():
		var button: Button = slot.get_node("Button")
		var status: Label = slot.get_node("StatusLabel")
		buttons.append(button)
		status_labels.append(status)

	for i in range(buttons.size()):
		if i >= _skills.size():
			break
		var skill: Dictionary = _skills[i]
		var skill_id: String = String(skill.id)
		skill_ids.append(skill_id)
		buttons[i].text = I18n.t(String(skill.name_key))
		buttons[i].pressed.connect(_on_button_pressed.bind(skill_id))

	refresh_timer.wait_time = REFRESH_INTERVAL_S
	refresh_timer.timeout.connect(_refresh)


## Wires this bar to `server`'s facts for `player` and does one initial refresh.
func bind(server: CombatAuthority, player: Player) -> void:
	_server = server
	_player = player
	_entity_id = Player.ENTITY_ID
	refresh_timer.start()
	_refresh()


func _on_button_pressed(skill_id: String) -> void:
	if _player == null:
		return
	_player.select_skill(skill_id)
	_refresh()


## Re-read the server's unlock/cooldown state right now — tests use this
## instead of waiting on RefreshTimer; RefreshTimer calls it too.
func refresh() -> void:
	_refresh()


func _refresh() -> void:
	if _server == null or not _server.is_registered(_entity_id):
		return
	var level: float = _server.get_level(_entity_id)
	for i in range(skill_ids.size()):
		var skill: Dictionary = _skills[i]
		var skill_id: String = skill_ids[i]
		var unlocked: bool = RulesSkills.skill_unlocked(float(skill.level), level)
		var button: Button = buttons[i]
		var status: Label = status_labels[i]

		button.disabled = not unlocked
		button.button_pressed = _player != null and _player.selected_skill_id == skill_id

		if not unlocked:
			status.text = I18n.t("ui.skills.locked") % int(skill.level)
		else:
			var left: float = _server.skill_cooldown_left(_entity_id, skill_id)
			status.text = ("%.1f" % left) if left > 0.0 else ""
