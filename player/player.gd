extends CharacterBody3D

const EYE_HEIGHT_STAND = 1.6
const EYE_HEIGHT_CROUCH = 1.4

const MOVEMENT_SPEED_GROUND = 0.6
const MOVEMENT_SPEED_AIR = 0.11
const MOVEMENT_SPEED_CROUCH_MODIFIER = 0.5
const MOVEMENT_FRICTION_GROUND = 0.9
const MOVEMENT_FRICTION_AIR = 0.98

const MAX_HEALTH = 100

var _mouse_motion = Vector2()

var current_weapon_index: int = 0
var weapons: Array[Weapon] = []
var health: int = MAX_HEALTH
var is_dead: bool = false

@onready var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head = $Head
@onready var raycast = $Head/RayCast3D
@onready var camera_attributes = $Head/Camera3D.attributes
@onready var voxel_world = $"../VoxelWorld"
@onready var crosshair = $"../PauseMenu/Crosshair"
@onready var weapon_mesh = $Head/WeaponMesh
@onready var health_bar = $"../PauseMenu/HealthBar"
@onready var pause_menu = $"../PauseMenu"


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Initialize weapons
	var pistol_script = load("res://weapons/pistol.gd")
	var rocket_launcher_script = load("res://weapons/rocket_launcher.gd")
	
	var pistol = pistol_script.new()
	var rocket_launcher = rocket_launcher_script.new()
	
	weapons.append(pistol)
	weapons.append(rocket_launcher)
	
	# Add weapons as children so they can use timers
	add_child(pistol)
	add_child(rocket_launcher)
	
	current_weapon_index = 0
	_update_weapon_display()
	_update_health_bar()
	
	# Fix initial spawn position to be on top of terrain
	call_deferred("_fix_initial_spawn")


func _process(_delta):
	if is_dead:
		return
	
	# Don't process player actions when paused
	if get_tree().paused:
		return
	
	# Mouse movement.
	_mouse_motion.y = clamp(_mouse_motion.y, -1560, 1560)
	transform.basis = Basis.from_euler(Vector3(0, _mouse_motion.x * -0.001, 0))
	head.transform.basis = Basis.from_euler(Vector3(_mouse_motion.y * -0.001, 0, 0))

	# Weapon switching
	if Input.is_action_just_pressed(&"weapon_1"):
		current_weapon_index = 0
		_update_weapon_display()
	elif Input.is_action_just_pressed(&"weapon_2"):
		current_weapon_index = 1
		_update_weapon_display()
	
	current_weapon_index = clamp(current_weapon_index, 0, weapons.size() - 1)
	
	# Shooting
	if crosshair.visible and Input.is_action_just_pressed(&"shoot"):
		if weapons.size() > current_weapon_index:
			var current_weapon = weapons[current_weapon_index]
			# Update raycast range for weapon
			raycast.target_position = Vector3(0, 0, -current_weapon.range_distance)
			raycast.force_raycast_update()
			current_weapon.fire(raycast, voxel_world)
			# Restore original range
			raycast.target_position = Vector3(0, 0, -4)


func _physics_process(delta):
	if is_dead:
		return
	
	# Don't process physics when paused
	if get_tree().paused:
		return
	
	camera_attributes.dof_blur_far_enabled = Settings.fog_enabled
	camera_attributes.dof_blur_far_distance = Settings.fog_distance * 1.5
	camera_attributes.dof_blur_far_transition = Settings.fog_distance * 0.125
	# Crouching.
	var crouching = Input.is_action_pressed(&"crouch")
	head.transform.origin.y = lerpf(head.transform.origin.y, EYE_HEIGHT_CROUCH if crouching else EYE_HEIGHT_STAND, 16 * delta)

	# Check if player is near a ladder block
	var is_near_ladder = _check_near_ladder()
	
	# Keyboard movement.
	var movement_vec2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var movement = transform.basis * (Vector3(movement_vec2.x, 0, movement_vec2.y))

	if is_on_floor():
		movement *= MOVEMENT_SPEED_GROUND
	else:
		movement *= MOVEMENT_SPEED_AIR

	if crouching:
		movement *= MOVEMENT_SPEED_CROUCH_MODIFIER

	# Ladder climbing - allow vertical movement when near ladder
	if is_near_ladder:
		# Reduce gravity when on ladder
		velocity.y *= 0.5  # Slow down vertical velocity
		# Allow climbing up/down with movement keys
		if Input.is_action_pressed(&"move_forward") or Input.is_action_pressed(&"jump"):
			velocity.y = 3.0  # Climb up
		elif Input.is_action_pressed(&"move_back") or Input.is_action_pressed(&"crouch"):
			velocity.y = -3.0  # Climb down
		else:
			# Hold position on ladder
			velocity.y = 0.0
	else:
		# Normal gravity when not on ladder
		velocity.y -= gravity * delta

	velocity += Vector3(movement.x, 0, movement.z)
	# Apply horizontal friction.
	velocity.x *= MOVEMENT_FRICTION_GROUND if is_on_floor() else MOVEMENT_FRICTION_AIR
	velocity.z *= MOVEMENT_FRICTION_GROUND if is_on_floor() else MOVEMENT_FRICTION_AIR
	move_and_slide()

	# Jumping, applied next frame (only when not on ladder).
	if is_on_floor() and Input.is_action_pressed(&"jump") and not is_near_ladder:
		velocity.y = 7.5


func _input(event):
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_mouse_motion += event.relative


func chunk_pos():
	return Vector3i((transform.origin / Chunk.CHUNK_SIZE).floor())


func _update_weapon_display():
	# Update hotbar if it exists
	var hotbar = get_tree().get_first_node_in_group("weapon_hotbar")
	if hotbar:
		hotbar.set_current_weapon(current_weapon_index)
	
	# Update weapon mesh visibility
	if weapon_mesh:
		weapon_mesh.visible = true
		# Update mesh based on weapon type
		if current_weapon_index == 0:
			# Pistol - smaller cube
			weapon_mesh.scale = Vector3(0.1, 0.15, 0.3)
			weapon_mesh.position = Vector3(0.3, -0.2, -0.5)
		else:
			# Rocket launcher - larger cube
			weapon_mesh.scale = Vector3(0.15, 0.2, 0.5)
			weapon_mesh.position = Vector3(0.3, -0.25, -0.6)

func take_damage(amount: int):
	if is_dead:
		return
	
	health -= amount
	health = max(0, health)
	_update_health_bar()
	
	# Show damage effect (red screen overlay)
	if pause_menu and pause_menu.has_method("show_damage_effect"):
		pause_menu.show_damage_effect()
	
	if health <= 0:
		_die()

func _die():
	if is_dead:
		return
	
	# Decrement ally tickets
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		game_manager.decrement_ally_tickets()
		
		# Check if we can respawn
		if game_manager.can_ally_respawn():
			# Respawn the player
			_respawn()
		else:
			# No tickets left, true game over
			is_dead = true
			var game_over = get_tree().get_first_node_in_group("game_over")
			if game_over:
				game_over.show_game_over()
	else:
		# Fallback to old behavior if no game manager
		is_dead = true
		var game_over = get_tree().get_first_node_in_group("game_over")
		if game_over:
			game_over.show_game_over()

func _respawn():
	# Reset health
	health = MAX_HEALTH
	_update_health_bar()
	
	# Find a valid spawn position on ally side
	var spawn_pos = _find_spawn_position()
	global_position = spawn_pos

func _update_health_bar():
	if health_bar:
		health_bar.set_health(health, MAX_HEALTH)

func _fix_initial_spawn():
	# Fix the initial spawn position if player spawned inside terrain
	var spawn_pos = _find_spawn_position()
	global_position = spawn_pos

func _find_spawn_position() -> Vector3:
	# Find a valid spawn position on ally side (negative X)
	var x_pos = randf_range(-55.0, -15.0)
	var z_pos = randf_range(-55.0, 55.0)
	var start_y = 20.0  # Start high enough to clear tall buildings
	
	# Raycast down to find ground level or top of structure
	var space_state = get_world_3d().direct_space_state
	var start_pos = Vector3(x_pos, start_y, z_pos)
	var query = PhysicsRayQueryParameters3D.create(start_pos, start_pos + Vector3.DOWN * 30)
	var result = space_state.intersect_ray(query)
	
	if result:
		# Spawn on top of the surface (ground or structure)
		# Add extra height to ensure player spawns above the block (not inside it)
		# 1.0 to clear the block, 1.5 for player height offset, plus 0.5 buffer
		return result.position + Vector3(0, 10, 0)
	
	# If no ground found, spawn at default ground level
	return Vector3(x_pos, 10, z_pos)

func _check_near_ladder() -> bool:
	# Check if player is near a ladder block (within 0.5 blocks)
	if not voxel_world:
		return false
	
	# Check blocks around player position (including slightly above and below)
	var player_block_pos = Vector3i(global_position.floor())
	var check_positions = [
		player_block_pos,
		player_block_pos + Vector3i(0, 1, 0),
		player_block_pos + Vector3i(0, -1, 0),
		player_block_pos + Vector3i(1, 0, 0),
		player_block_pos + Vector3i(-1, 0, 0),
		player_block_pos + Vector3i(0, 0, 1),
		player_block_pos + Vector3i(0, 0, -1),
	]
	
	for pos in check_positions:
		var block_id = voxel_world.get_block_global_position(pos)
		if block_id == 4:  # LADDER_BLOCK
			return true
	
	return false
