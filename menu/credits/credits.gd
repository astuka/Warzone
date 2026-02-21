extends Control


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS


func _on_Back_pressed():
	get_tree().change_scene_to_packed(preload("res://menu/main/main_menu.tscn"))
