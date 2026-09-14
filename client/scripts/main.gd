extends Node2D
## Entry scene. Phase 0: boots into the clinic-lobby prototype map (player +
## touch controls + monsters) and the HUD, and proves the generated rules
## are callable. The I18n table itself is populated earlier, by the
## I18nBoot autoload (see client/scripts/i18n_boot.gd) — before this or any
## child scene's _ready().

@onready var clinic_lobby: ClinicLobby = $ClinicLobby
@onready var hud: Hud = $Hud


func _ready() -> void:
	($Label as Label).text = I18n.t("ui.title")
	hud.bind(clinic_lobby.local_server, Player.ENTITY_ID)
	var xp_10: float = RulesXp.xp_for_level(10)
	print("Hamirpaa boot ok — xp_for_level(10) = %d" % int(xp_10))
