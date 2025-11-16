extends NPC
class_name Ally

func _ready():
	npc_type = NPCType.ALLY
	add_to_group("npcs")
	add_to_group("allies")
	super._ready()

