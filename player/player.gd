extends CharacterBody3D

const EYE_HEIGHT_STAND = 1.6
const EYE_HEIGHT_CROUCH = 1.4

const MOVEMENT_SPEED_GROUND = 0.6
const MOVEMENT_SPEED_AIR = 0.11
const MOVEMENT_SPEED_CROUCH_MODIFIER = 0.5
const MOVEMENT_SPEED_SPRINT_MODIFIER = 1.8
const MOVEMENT_FRICTION_GROUND = 0.9
const MOVEMENT_FRICTION_AIR = 0.98

const MAX_HEALTH = 100
const LEAN_ANGLE = 15.0  # Degrees to lean
const LEAN_SPEED = 8.0  # Speed of lean transition

var _mouse_motion = Vector2()

var current_weapon_index: int = 0
var weapons: Array[Weapon] = []
var health: int = MAX_HEALTH
var is_dead: bool = false
var lean_amount: float = 0.0  # -1.0 to 1.0 (left to right)
var is_iron_sights: bool = false
var is_map_visible: bool = false

# Ammo tracking
const DEFAULT_BULLETS = 50
const DEFAULT_ROCKETS = 5
const DEFAULT_BLOCKS = 15
var bullets: int = DEFAULT_BULLETS
var rockets: int = DEFAULT_ROCKETS
var blocks: int = DEFAULT_BLOCKS

@onready var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/RayCast3D
@onready var camera_attributes = $Head/Camera3D.attributes
@onready var voxel_world = $"../VoxelWorld"
@onready var crosshair = $"../PauseMenu/Crosshair"
@onready var weapon_mesh = $Head/WeaponMesh
@onready var health_bar = $"../PauseMenu/HealthBar"
@onready var pause_menu = $"../PauseMenu"
@onready var map_camera = $"../MapCamera"

var near_restocking_station: bool = false

const FOV_NORMAL = 74.0
const FOV_IRON_SIGHTS = 55.0  # Zoomed in FOV for iron sights

const STONE_BLOCK = 1  # Block ID for stone blocks
const BLOCK_PLACEMENT_RANGE = 5.0  # Maximum distance for block placement


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
	_update_ammo_display()
	
	# Fix initial spawn position to be on top of terrain
	call_deferred("_fix_initial_spawn")


func _process(_delta):
	if is_dead:
		return
	
	# Don't process player actions when paused
	if get_tree().paused:
		return
	
	# Update map camera position if map is visible
	if is_map_visible:
		_update_map_camera()
	
	# Mouse movement.
	_mouse_motion.y = clamp(_mouse_motion.y, -1560, 1560)
	transform.basis = Basis.from_euler(Vector3(0, _mouse_motion.x * -0.001, 0))
	# Note: Head rotation is now handled in _physics_process to include lean
	
	# Map toggle (M key)
	if Input.is_action_just_pressed(&"map"):
		toggle_map()
	
	# Don't process other inputs when map is visible
	if is_map_visible:
		return
	
	# Iron sights (right click)
	is_iron_sights = Input.is_action_pressed(&"iron_sights")
	# Update camera FOV for zoom effect
	if camera:
		var target_fov = FOV_IRON_SIGHTS if is_iron_sights else FOV_NORMAL
		camera.fov = lerpf(camera.fov, target_fov, 0.2)
	_update_weapon_display()

	# Weapon switching
	if Input.is_action_just_pressed(&"weapon_1"):
		current_weapon_index = 0
		_update_weapon_display()
		_update_ammo_display()
	elif Input.is_action_just_pressed(&"weapon_2"):
		current_weapon_index = 1
		_update_weapon_display()
		_update_ammo_display()
	elif Input.is_action_just_pressed(&"weapon_3"):
		current_weapon_index = 2
		_update_weapon_display()
		_update_ammo_display()
	
	current_weapon_index = clamp(current_weapon_index, 0, 2)  # Max index is 2 (0=pistol, 1=rocket, 2=blocks)
	
	# Shooting or block placement
	if crosshair.visible and Input.is_action_just_pressed(&"shoot"):
		if current_weapon_index == 2:
			# Block placement mode
			_place_block()
			_update_ammo_display()
		elif weapons.size() > current_weapon_index:
			var current_weapon = weapons[current_weapon_index]
			# Update raycast range for weapon
			raycast.target_position = Vector3(0, 0, -current_weapon.range_distance)
			raycast.force_raycast_update()
			if current_weapon.fire(raycast, voxel_world):
				# Only update display if weapon actually fired (has ammo)
				_update_ammo_display()
			# Restore original range
			raycast.target_position = Vector3(0, 0, -4)


func _physics_process(delta):
	if is_dead:
		return
	
	# Don't process physics when paused or map is visible
	if get_tree().paused or is_map_visible:
		return
	
	camera_attributes.dof_blur_far_enabled = Settings.fog_enabled
	camera_attributes.dof_blur_far_distance = Settings.fog_distance * 1.5
	camera_attributes.dof_blur_far_transition = Settings.fog_distance * 0.125
	# Crouching.
	var crouching = Input.is_action_pressed(&"crouch")
	head.transform.origin.y = lerpf(head.transform.origin.y, EYE_HEIGHT_CROUCH if crouching else EYE_HEIGHT_STAND, 16 * delta)
	
	# Leaning (Q/E keys) - Fixed: Q leans left, E leans right
	var target_lean: float = 0.0
	
	# Check if near a restocking station
	near_restocking_station = RestockingStation.is_near_station(global_position, 2.5)
	
	# Check if near a friendly NPC to reset
	var nearby_ally = _get_nearby_friendly_npc()
	var near_friendly_npc = nearby_ally != null
	
	# Show appropriate prompts
	if pause_menu:
		if pause_menu.has_method("show_restock_prompt"):
			# Only show restock prompt if not near NPC (NPC reset takes priority)
			pause_menu.show_restock_prompt(near_restocking_station and not near_friendly_npc)
		if pause_menu.has_method("show_npc_reset_prompt"):
			pause_menu.show_npc_reset_prompt(near_friendly_npc)
	
	# Update ammo display periodically to ensure it stays current
	_update_ammo_display()
	
	# Check for interactions (F key) - priority over lean
	var f_key_pressed = Input.is_key_pressed(KEY_F)
	var f_key_just_pressed = Input.is_action_just_pressed(&"interact") or (f_key_pressed and not has_meta("f_key_was_pressed"))
	
	if f_key_pressed:
		# First check if near a friendly NPC to reset (temporary solution for stuck NPCs)
		# Only reset on just_pressed to avoid multiple resets
		if f_key_just_pressed and near_friendly_npc:
			_reset_npc(nearby_ally)
			# Don't lean if interacting
			target_lean = 0.0
			set_meta("f_key_was_pressed", true)
			# Skip rest of F key logic
			return
		
		# Check if near a restocking station (works with held key)
		if near_restocking_station:
			RestockingStation.restock_entity(self)
			# Update ammo display after restocking
			if pause_menu and pause_menu.has_method("update_ammo_display"):
				pause_menu.update_ammo_display(current_weapon_index, bullets, rockets, blocks)
			# Don't lean if interacting
			target_lean = 0.0
			set_meta("f_key_was_pressed", true)
		else:
			# Normal lean behavior
			var lean_left_pressed = Input.is_action_pressed(&"lean_left")
			var lean_right_pressed = Input.is_action_pressed(&"lean_right")
			if lean_left_pressed and not lean_right_pressed:
				target_lean = 1.0  # Positive for left lean (roll right)
			elif lean_right_pressed and not lean_left_pressed:
				target_lean = -1.0  # Negative for right lean (roll left)
			else:
				target_lean = 0.0
			set_meta("f_key_was_pressed", true)
	else:
		# F key not pressed - clear the flag
		if has_meta("f_key_was_pressed"):
			remove_meta("f_key_was_pressed")
		
		# Normal lean behavior when F is not pressed
		var lean_left_pressed = Input.is_action_pressed(&"lean_left")
		var lean_right_pressed = Input.is_action_pressed(&"lean_right")
		if lean_left_pressed and not lean_right_pressed:
			target_lean = 1.0  # Positive for left lean (roll right)
		elif lean_right_pressed and not lean_left_pressed:
			target_lean = -1.0  # Negative for right lean (roll left)
		else:
			target_lean = 0.0
	
	lean_amount = lerpf(lean_amount, target_lean, LEAN_SPEED * delta)
	
	# Apply lean rotation to head (roll rotation)
	var lean_rotation = lean_amount * deg_to_rad(LEAN_ANGLE)
	head.transform.basis = Basis.from_euler(Vector3(_mouse_motion.y * -0.001, 0, lean_rotation))

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
	
	# Sprinting (Shift key)
	var sprinting = Input.is_action_pressed(&"sprint")
	if sprinting and not crouching and is_on_floor():
		movement *= MOVEMENT_SPEED_SPRINT_MODIFIER

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
	
	# Update weapon mesh visibility and position
	if weapon_mesh:
		if current_weapon_index == 2:
			# Block placement mode - hide weapon mesh
			weapon_mesh.visible = false
		else:
			weapon_mesh.visible = true
			# Update mesh based on weapon type and iron sights state
			var base_position: Vector3
			var iron_sights_position: Vector3
			
			if current_weapon_index == 0:
				# Pistol - smaller cube
				weapon_mesh.scale = Vector3(0.1, 0.15, 0.3)
				base_position = Vector3(0.3, -0.2, -0.5)
				iron_sights_position = Vector3(0.0, -0.15, -0.25)  # Center-bottom for iron sights
			else:
				# Rocket launcher - larger cube
				weapon_mesh.scale = Vector3(0.15, 0.2, 0.5)
				base_position = Vector3(0.3, -0.25, -0.6)
				iron_sights_position = Vector3(0.0, -0.4, -0.35)  # Center-bottom for iron sights
			
			# Smoothly transition between normal and iron sights position
			if is_iron_sights:
				weapon_mesh.position = weapon_mesh.position.lerp(iron_sights_position, 0.2)
			else:
				weapon_mesh.position = weapon_mesh.position.lerp(base_position, 0.2)

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
	
	# Reset ammo to default values
	bullets = DEFAULT_BULLETS
	rockets = DEFAULT_ROCKETS
	blocks = DEFAULT_BLOCKS
	_update_ammo_display()
	
	# Find a valid spawn position on ally side
	var spawn_pos = _find_spawn_position()
	global_position = spawn_pos

func _update_health_bar():
	if health_bar:
		health_bar.set_health(health, MAX_HEALTH)

func _update_ammo_display():
	# Update the ammo display in the pause menu
	if pause_menu and pause_menu.has_method("update_ammo_display"):
		pause_menu.update_ammo_display(current_weapon_index, bullets, rockets, blocks)

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

func _place_block():
	# Place a stone block at the location the player is looking at
	if not voxel_world:
		return
	
	# Check if player has blocks available
	if blocks <= 0:
		return
	
	# Update raycast to check for block placement
	raycast.target_position = Vector3(0, 0, -BLOCK_PLACEMENT_RANGE)
	raycast.force_raycast_update()
	
	if raycast.is_colliding():
		var hit_position = raycast.get_collision_point()
		var hit_normal = raycast.get_collision_normal()
		
		# Calculate where to place the block (adjacent to the hit face)
		var block_pos = Vector3i((hit_position + hit_normal * 0.5).floor())
		
		# Don't place blocks inside the player
		var player_block_pos = Vector3i(global_position.floor())
		# Convert to Vector3 to calculate distance
		if Vector3(block_pos).distance_to(Vector3(player_block_pos)) < 1.5:
			return
		
		# Check if there's already a block at this position
		var existing_block = voxel_world.get_block_global_position(block_pos)
		if existing_block == 0:  # Only place if position is empty
			voxel_world.set_block_global_position(block_pos, STONE_BLOCK)
			blocks -= 1  # Decrement block count
	
	# Restore original raycast range
	raycast.target_position = Vector3(0, 0, -4)

func toggle_map():
	is_map_visible = not is_map_visible
	
	if is_map_visible:
		# Show map - switch to map camera
		if camera:
			camera.current = false
		if map_camera:
			map_camera.current = true
			_update_map_camera()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		# Hide map - switch back to normal camera
		if map_camera:
			map_camera.current = false
		if camera:
			camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _update_map_camera():
	if not map_camera:
		return
	
	# Position camera above player looking straight down
	#var player_pos = global_position
	map_camera.global_position = Vector3(0, 100, 0)
	# Set rotation to look straight down (90 degrees on X axis)
	map_camera.rotation_degrees = Vector3(-90, 0, 0)

func _get_nearby_friendly_npc() -> NPC:
	# Check if player is near a friendly NPC (within 3 units)
	var all_npcs = get_tree().get_nodes_in_group("npcs")
	var closest_ally: NPC = null
	var closest_distance: float = 3.0  # Interaction range
	
	for npc in all_npcs:
		if not is_instance_valid(npc) or not npc is NPC:
			continue
		
		# Only check allies (friendly NPCs)
		if (npc as NPC).npc_type == NPC.NPCType.ALLY:
			var distance = global_position.distance_to(npc.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_ally = npc as NPC
	
	return closest_ally

func _reset_npc(npc: NPC):
	# Reset a stuck NPC by deleting it and respawning a new one
	if not npc or not is_instance_valid(npc):
		return
	
	# Get the spawner
	var spawner = get_tree().get_first_node_in_group("enemy_spawner")
	if not spawner:
		# Try alternative ways to find spawner
		spawner = get_tree().current_scene.get_node_or_null("EnemySpawner")
	
	if spawner and spawner is EnemySpawner:
		# Store NPC type before deleting
		var npc_type = npc.npc_type
		
		# Remove from spawner's arrays
		if npc_type == NPC.NPCType.ALLY:
			(spawner as EnemySpawner).allies.erase(npc)
		else:
			(spawner as EnemySpawner).enemies.erase(npc)
		
		# Delete the NPC
		npc.queue_free()
		
		# Spawn a new one of the same type
		if npc_type == NPC.NPCType.ALLY:
			(spawner as EnemySpawner).spawn_ally()
		else:
			(spawner as EnemySpawner).spawn_enemy()
