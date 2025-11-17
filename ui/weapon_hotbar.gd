extends Control

@onready var slot_1 = $HBoxContainer/Slot1
@onready var slot_2 = $HBoxContainer/Slot2
@onready var slot_3 = $HBoxContainer/Slot3

var current_weapon_index: int = 0

func _ready():
	# Connect to player's weapon change signal if needed
	# For now, we'll update via a reference
	add_to_group("weapon_hotbar")
	update_hotbar()

func set_current_weapon(index: int):
	current_weapon_index = index
	update_hotbar()

func update_hotbar():
	# Highlight the current weapon slot
	if slot_1 and slot_2 and slot_3:
		if current_weapon_index == 0:
			slot_1.modulate = Color.WHITE
			slot_2.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Dimmed
			slot_3.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Dimmed
		elif current_weapon_index == 1:
			slot_1.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Dimmed
			slot_2.modulate = Color.WHITE
			slot_3.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Dimmed
		else:
			slot_1.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Dimmed
			slot_2.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Dimmed
			slot_3.modulate = Color.WHITE

