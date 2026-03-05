extends HBoxContainer

var prev_menu


func _ready():
	# Allow this UI to process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Ensure options panel fills the parent for proper centering
	# (tscn instance overrides break the anchors, so fix in code)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_Back_pressed():
	prev_menu.visible = true
	visible = false
