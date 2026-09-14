extends Node2D
## Entry scene. Phase -1: proves the project boots and the generated rules are callable.


func _ready() -> void:
	var xp_10: float = RulesXp.xp_for_level(10)
	print("Hamirpaa boot ok — xp_for_level(10) = %d" % int(xp_10))
