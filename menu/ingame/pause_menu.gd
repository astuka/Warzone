extends Control

@onready var tree = get_tree()

@onready var crosshair = $Crosshair
@onready var pause = $Pause
@onready var options = $Options
@onready var voxel_world = $"../VoxelWorld"
@onready var damage_overlay = $DamageOverlay
@onready var hit_marker = $Crosshair/HitMarker


func _ready():
	# Allow this UI to process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta):
	if Input.is_action_just_pressed(&"pause"):
		pause.visible = crosshair.visible
		crosshair.visible = not crosshair.visible
		options.visible = false
		if crosshair.visible:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			get_tree().paused = false
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_tree().paused = true


func _on_Resume_pressed():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	crosshair.visible = true
	pause.visible = false
	get_tree().paused = false


func _on_Options_pressed():
	options.prev_menu = pause
	options.visible = true
	pause.visible = false


func _on_MainMenu_pressed():
	voxel_world.clean_up()
	get_tree().paused = false  # Unpause before changing scenes
	tree.change_scene_to_packed(load("res://menu/main/main_menu.tscn"))


func _on_Exit_pressed():
	voxel_world.clean_up()
	get_tree().paused = false  # Unpause before exiting
	tree.quit()

var damage_tween: Tween = null
var hit_marker_tween: Tween = null

func show_hit_marker():
	# Show hit marker briefly when player hits an enemy
	if hit_marker:
		# Stop any existing tween
		if hit_marker_tween and hit_marker_tween.is_valid():
			hit_marker_tween.kill()
		
		# Reset alpha and make hit marker visible
		hit_marker.modulate.a = 0.8
		hit_marker.visible = true
		
		# Create a tween to fade it out quickly
		hit_marker_tween = create_tween()
		# Fade out over 0.15 seconds
		hit_marker_tween.tween_property(hit_marker, "modulate:a", 0.0, 0.15)
		hit_marker_tween.tween_callback(func(): hit_marker.visible = false)

func show_damage_effect():
	# Show red overlay briefly when player takes damage
	if damage_overlay:
		# Stop any existing tween to prevent overlapping effects
		if damage_tween and damage_tween.is_valid():
			damage_tween.kill()
		
		# Create a tween for smooth fade in/out
		damage_tween = create_tween()
		# Fade in to red (alpha 0.3) quickly
		damage_tween.tween_property(damage_overlay, "color:a", 0.3, 0.1)
		# Then fade out back to transparent
		damage_tween.tween_property(damage_overlay, "color:a", 0.0, 0.2)
