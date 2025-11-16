extends NPC
class_name EnemyNPC

func _ready():
	npc_type = NPCType.ENEMY
	add_to_group("npcs")
	add_to_group("enemies")
	super._ready()

