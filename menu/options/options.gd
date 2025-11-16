extends HBoxContainer

var prev_menu


func _ready():
	# Allow this UI to process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _on_Back_pressed():
	prev_menu.visible = true
	visible = false
