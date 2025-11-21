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

func show_game_over(winning_team: String):
	visible = true
	game_over_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	var title_label = $GameOverPanel/GameOverLabel
	var restart_label = $GameOverPanel/RestartButton/Label
	
	# Disconnect previous connections to avoid duplicates
	if restart_button.pressed.is_connected(_on_restart_pressed):
		restart_button.pressed.disconnect(_on_restart_pressed)
	if restart_button.pressed.is_connected(_on_next_map_pressed):
		restart_button.pressed.disconnect(_on_next_map_pressed)
	
	if winning_team == "Ally":
		# Victory (Allies won, Enemies lost tickets)
		# Note: trigger_game_over passes the WINNING team.
		# If Enemy tickets reach 0, Allies win.
		title_label.text = "Victory!"
		restart_label.text = "Next Map"
		restart_button.pressed.connect(_on_next_map_pressed)
	else:
		# Defeat (Enemies won, Allies lost tickets)
		title_label.text = "Defeat!"
		restart_label.text = "Restart"
		restart_button.pressed.connect(_on_restart_pressed)

func _on_next_map_pressed():
	visible = false
	game_over_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameManager.restart_game(true)

func _on_restart_pressed():
	visible = false
	game_over_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GameManager.restart_game(false)

func _on_main_menu_pressed():
	# Unpause and go to main menu
	get_tree().paused = false
	var voxel_world = get_tree().get_first_node_in_group("voxel_world")
	if voxel_world:
		voxel_world.clean_up()
	get_tree().change_scene_to_packed(load("res://menu/main/main_menu.tscn"))
