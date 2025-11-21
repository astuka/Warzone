extends Control

@onready var tree = get_tree()

@onready var title = $TitleScreen
@onready var start = $StartGame
@onready var options = $Options


func _ready():
	# Ensure game is unpaused when entering main menu
	get_tree().paused = false


func _on_Start_pressed():
	# Reset game state to defaults
	GameManager.reset_game_state()
	
	# Load Flatgrass world directly
	Settings.world_type = 1
	tree.change_scene_to_packed(preload("res://world/world.tscn"))


func _on_Options_pressed():
	options.prev_menu = title
	options.visible = true
	title.visible = false


func _on_Exit_pressed():
	tree.quit()
