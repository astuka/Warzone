extends Control

@onready var title = $TitleScreen
@onready var start = $StartGame
@onready var options = $Options
@onready var splash_text = $SplashText
@onready var splash_text2 = $SplashText2


func _ready():
	# Process even if tree is still paused from previous scene
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Ensure game is unpaused and mouse is visible when entering main menu
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Ensure Labels inside buttons don't block mouse clicks
	_fix_button_mouse_filters(title)
	_fix_button_mouse_filters(start)

	# Prevent splash text labels from intercepting input
	splash_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	splash_text2.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Show splash texts when options is closed
	options.visibility_changed.connect(_on_options_visibility_changed)


func _fix_button_mouse_filters(node: Node):
	for child in node.get_children():
		if child is BaseButton:
			for sub in child.get_children():
				if sub is Label:
					sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			_fix_button_mouse_filters(child)


func _on_options_visibility_changed():
	if not options.visible:
		splash_text.visible = true
		splash_text2.visible = true


func _on_Start_pressed():
	# Reset game state to defaults
	GameManager.reset_game_state()

	# Load Flatgrass world directly
	Settings.world_type = 1
	get_tree().change_scene_to_file("res://world/world.tscn")


func _on_Options_pressed():
	options.prev_menu = title
	options.visible = true
	title.visible = false
	splash_text.visible = false
	splash_text2.visible = false


func _on_Credits_pressed():
	get_tree().change_scene_to_file("res://menu/credits/credits.tscn")


func _on_Exit_pressed():
	get_tree().quit()
