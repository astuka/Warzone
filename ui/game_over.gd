extends Control
class_name GameOver

@onready var game_over_panel: VBoxContainer = $GameOverPanel
@onready var restart_button: TextureButton = $GameOverPanel/RestartButton
@onready var main_menu_button: TextureButton = $GameOverPanel/MainMenuButton

func _ready():
	add_to_group("game_over")
	visible = false
	
	# Allow this UI to work when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if main_menu_button:
		main_menu_button.pressed.connect(_on_main_menu_pressed)

func show_game_over():
	visible = true
	game_over_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Pause the game
	get_tree().paused = true

func _on_restart_pressed():
	# Unpause and respawn player in same map
	get_tree().paused = false
	visible = false
	game_over_panel.visible = false
	
	# Find the player and respawn them
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("_respawn"):
		player._respawn()
		player.is_dead = false
	
	# Recapture mouse
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_main_menu_pressed():
	# Unpause and go to main menu
	get_tree().paused = false
	var voxel_world = get_tree().get_first_node_in_group("voxel_world")
	if voxel_world:
		voxel_world.clean_up()
	get_tree().change_scene_to_packed(load("res://menu/main/main_menu.tscn"))

