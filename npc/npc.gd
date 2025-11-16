extends CharacterBody3D
class_name NPC

const MAX_HEALTH = 100
const MOVE_SPEED = 3.0
const GRAVITY = 9.8
const JUMP_VELOCITY = 4.5

enum NPCType {
	ALLY,
	ENEMY
}

var npc_type: NPCType
var health: int = MAX_HEALTH
var original_color: Color = Color.WHITE

var current_weapon_index: int = 0
var weapons: Array[Weapon] = []
var target: Node3D = null  # Current target to chase/attack
var detection_range: float = 80.0  # How far NPCs can detect enemies (increased for 16x16 map)
var attack_range: float = 50.0  # How close NPCs need to be to attack (increased for 16x16 map)
var shot_count: int = 0  # Track number of shots fired

# Roaming behavior
var roam_target_position: Vector3 = Vector3.ZERO  # Current roaming destination
var roam_timer: float = 0.0  # Timer for picking new roam target
var roam_interval: float = 3.0  # Pick new roam target every 3 seconds
var roam_range: float = 15.0  # Maximum distance to roam from spawn position
var spawn_position: Vector3 = Vector3.ZERO  # Remember where NPC spawned

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var weapon_mesh: MeshInstance3D = $WeaponMesh
@onready var fire_raycast: RayCast3D = $FireRaycast
@onready var voxel_world = get_tree().get_first_node_in_group("voxel_world")

func _ready():
	# Create mesh if not already set
	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
	
	if not mesh_instance.mesh:
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(1, 2, 1)
		mesh_instance.mesh = box_mesh
	
	# Position mesh to match collision shape center (prevents sinking)
	mesh_instance.position = Vector3(0, 1, 0)
	
	# Create collision shape if not already set
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		add_child(collision_shape)
	
	if not collision_shape.shape:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(1, 2, 1)
		collision_shape.shape = box_shape
		collision_shape.position = Vector3(0, 1, 0)
	
	# Create material with original color
	if not mesh_instance.material_override:
		var material = StandardMaterial3D.new()
		material.albedo_color = original_color
		mesh_instance.material_override = material
	else:
		original_color = mesh_instance.material_override.albedo_color
	
	# Create weapon mesh if not already set
	if not weapon_mesh:
		weapon_mesh = MeshInstance3D.new()
		add_child(weapon_mesh)
		weapon_mesh.position = Vector3(0.0, 1.2, -0.5)  # Levitating in front
	
	# Create fire raycast if not already set
	if not fire_raycast:
		fire_raycast = RayCast3D.new()
		add_child(fire_raycast)
		fire_raycast.position = Vector3(0, 1.5, 0)  # Eye level
		fire_raycast.target_position = Vector3(0, 0, -10)
	
	# Initialize weapons
	_initialize_weapons()
	
	# Set color based on type
	_set_type_color()
	
	# Initialize roaming - set spawn position and pick first roam target
	call_deferred("_initialize_roaming")

func _initialize_weapons():
	# Create pistol and rocket launcher
	var pistol_script = load("res://weapons/pistol.gd")
	var rocket_launcher_script = load("res://weapons/rocket_launcher.gd")
	
	var pistol = pistol_script.new()
	var rocket_launcher = rocket_launcher_script.new()
	
	weapons.append(pistol)
	weapons.append(rocket_launcher)
	
	# Add weapons as children
	add_child(pistol)
	add_child(rocket_launcher)
	
	current_weapon_index = 0  # Start with pistol
	_update_weapon_display()

func _set_type_color():
	if mesh_instance and mesh_instance.material_override:
		var material = mesh_instance.material_override
		if material is StandardMaterial3D:
			if npc_type == NPCType.ALLY:
				material.albedo_color = Color(0.2, 0.8, 0.2)  # Green for allies
			else:
				material.albedo_color = Color(0.8, 0.75, 0.6)  # Beige for enemies
			original_color = material.albedo_color

func _initialize_roaming():
	# Set spawn position to current position
	spawn_position = global_position
	# Pick first roam target
	_pick_new_roam_target()

func _pick_new_roam_target():
	# Pick a random position within roam_range of spawn position
	var random_offset = Vector3(
		randf_range(-roam_range, roam_range),
		0.0,
		randf_range(-roam_range, roam_range)
	)
	roam_target_position = spawn_position + random_offset
	# Reset roam timer
	roam_timer = 0.0

func _move_towards_roam_target(delta):
	# If spawn position wasn't set yet, set it now
	if spawn_position == Vector3.ZERO:
		spawn_position = global_position
	
	if roam_target_position == Vector3.ZERO:
		_pick_new_roam_target()
		return
	
	var direction = (roam_target_position - global_position)
	direction.y = 0  # Don't move vertically
	var distance = direction.length()
	
	# If we've reached the roam target (or are close enough), pick a new one
	if distance < 2.0:
		_pick_new_roam_target()
		return
	
	direction = direction.normalized()
	
	# Move towards roam target at a slower speed than combat movement
	velocity.x = direction.x * MOVE_SPEED * 0.6  # 60% of combat speed
	velocity.z = direction.z * MOVE_SPEED * 0.6
	
	# Face the direction we're moving
	if direction.length() > 0:
		look_at(global_position + direction, Vector3.UP)

func _physics_process(delta):
	# Don't do anything if game is paused
	if get_tree().paused:
		return
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		# Small jump to prevent getting stuck
		if velocity.y < 0:
			velocity.y = 0
	
	# AI: Find and chase target
	_find_target()
	
	# Move towards target
	if target and is_instance_valid(target):
		_move_towards_target(delta)
		_face_target()
		_try_attack()
	else:
		# No target, roam around
		roam_timer += delta
		# Pick a new roam target periodically
		if roam_timer >= roam_interval:
			_pick_new_roam_target()
		_move_towards_roam_target(delta)
	
	move_and_slide()

func _find_target():
	# Find closest enemy based on NPC type
	var potential_targets: Array[Node3D] = []
	
	# Get all NPCs and player
	var all_npcs = get_tree().get_nodes_in_group("npcs")
	var player = get_tree().get_first_node_in_group("player")
	
	# Determine what we're looking for
	if npc_type == NPCType.ALLY:
		# Allies target enemies
		for npc in all_npcs:
			if npc != self and npc is NPC and npc.npc_type == NPCType.ENEMY:
				potential_targets.append(npc)
		# Also target player if they're enemies (but in this game, player is ally)
		# For now, allies don't target player
	elif npc_type == NPCType.ENEMY:
		# Enemies target allies and player
		for npc in all_npcs:
			if npc != self and npc is NPC and npc.npc_type == NPCType.ALLY:
				potential_targets.append(npc)
		if player:
			potential_targets.append(player)
	
	# Find closest target
	var closest_target: Node3D = null
	var closest_distance: float = detection_range
	
	for potential_target in potential_targets:
		if not is_instance_valid(potential_target):
			continue
		
		var distance = global_position.distance_to(potential_target.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_target = potential_target
	
	target = closest_target

func _move_towards_target(delta):
	if not target or not is_instance_valid(target):
		return
	
	var direction = (target.global_position - global_position)
	direction.y = 0  # Don't move vertically
	var distance = direction.length()
	
	# Stop moving if we're within attack range
	if distance <= attack_range:
		velocity.x = 0
		velocity.z = 0
		return
	
	direction = direction.normalized()
	
	# Move towards target
	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED

func _face_target():
	if not target or not is_instance_valid(target):
		return
	
	var direction = (target.global_position - global_position)
	direction.y = 0
	direction = direction.normalized()
	
	if direction.length() > 0:
		look_at(global_position + direction, Vector3.UP)

func _try_attack():
	if not target or not is_instance_valid(target):
		return
	
	var distance = global_position.distance_to(target.global_position)
	if distance > attack_range:
		return
	
	# Check if we can fire
	if weapons.size() == 0:
		return
	
	# Randomly switch to rocket launcher every ~25th shot
	# Check if it's time to potentially use rocket launcher
	if weapons.size() >= 2:
		# Every 25th shot, there's a chance to use rocket launcher
		if shot_count % 25 == 24:  # On the 25th shot (index 24)
			current_weapon_index = 1  # Rocket launcher
			_update_weapon_display()
		else:
			current_weapon_index = 0  # Pistol
			_update_weapon_display()
	
	var current_weapon = weapons[current_weapon_index]
	if not current_weapon or not current_weapon.can_fire:
		return
	
	# Calculate direction to target
	# Aim at target's center/torso height instead of feet
	var target_aim_point = target.global_position
	# If target is a player or another NPC, aim at their torso (roughly y+1.0)
	target_aim_point.y += 1.0
	var direction_to_target = (target_aim_point - fire_raycast.global_position).normalized()
	
	# Add spread/spray to make shots less accurate (but still aim at target)
	var spread_amount = 0.08  # 0.08 radians ≈ 4.6 degrees of spread
	var spread_x = randf_range(-spread_amount, spread_amount)
	var spread_y = randf_range(-spread_amount, spread_amount)
	
	# Apply spread by rotating the direction vector
	# Get perpendicular vectors for rotation
	var right = direction_to_target.cross(Vector3.UP)
	if right.length() < 0.001:
		# If direction is straight up/down, use a different reference
		right = direction_to_target.cross(Vector3.FORWARD)
	right = right.normalized()
	var up = right.cross(direction_to_target).normalized()
	
	# Rotate the direction with spread
	direction_to_target = direction_to_target.rotated(right, spread_y).rotated(up, spread_x).normalized()
	
	# Point the raycast in the direction we want to fire
	# Use look_at to orient the raycast, then set target_position along its forward axis
	fire_raycast.look_at(fire_raycast.global_position + direction_to_target, Vector3.UP)
	fire_raycast.target_position = Vector3(0, 0, -current_weapon.range_distance)
	fire_raycast.force_raycast_update()
	
	# Fire weapon
	if current_weapon.fire(fire_raycast, voxel_world):
		shot_count += 1  # Increment shot counter only on successful fire

func _update_weapon_display():
	if not weapon_mesh:
		return
	
	if weapons.size() == 0:
		weapon_mesh.visible = false
		return
	
	weapon_mesh.visible = true
	
	# Update mesh based on weapon type
	if current_weapon_index == 0:
		# Pistol - smaller cube, levitating in front
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.1, 0.15, 0.3)
		weapon_mesh.mesh = box_mesh
		# Set position directly
		weapon_mesh.position = Vector3(0.0, 1.2, -0.5)  # Levitating in front
		
		# Create material (gold/yellow for pistol)
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.8, 0.0)
		weapon_mesh.material_override = material
	else:
		# Rocket launcher - larger cube, levitating in front
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(0.15, 0.2, 0.5)
		weapon_mesh.mesh = box_mesh
		# Set position directly
		weapon_mesh.position = Vector3(0.0, 1.15, -0.6)  # Levitating in front
		
		# Create material (red/orange for rocket launcher)
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.3, 0.0)
		weapon_mesh.material_override = material

func take_damage(amount: int):
	health -= amount
	health = max(0, health)
	
	# Check if NPC should be deleted
	if health <= 0:
		_on_death()
		queue_free()
		return

func _on_death():
	# Decrement appropriate team's tickets
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		if npc_type == NPCType.ALLY:
			game_manager.decrement_ally_tickets()
		elif npc_type == NPCType.ENEMY:
			game_manager.decrement_enemy_tickets()

