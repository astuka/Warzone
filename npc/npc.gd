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

# Ammo tracking
const DEFAULT_BULLETS = 50
const DEFAULT_ROCKETS = 5
const DEFAULT_BLOCKS = 15
var bullets: int = DEFAULT_BULLETS
var rockets: int = DEFAULT_ROCKETS
var blocks: int = DEFAULT_BLOCKS

# Restocking behavior
var restocking_station_target: Vector3 = Vector3.ZERO  # Target restocking station position
var needs_restock: bool = false  # Whether NPC needs to restock

# Roaming behavior
var roam_target_position: Vector3 = Vector3.ZERO  # Current roaming destination
var roam_timer: float = 0.0  # Timer for picking new roam target
var roam_interval: float = 3.0  # Pick new roam target every 3 seconds
var roam_range: float = 15.0  # Maximum distance to roam from spawn position
var spawn_position: Vector3 = Vector3.ZERO  # Remember where NPC spawned

# Jump cooldown for restocking
var jump_cooldown: float = 0.0  # Cooldown to prevent constant jumping

# Crowding avoidance
var crowding_repel_strength: float = 8.0  # How strongly NPCs repel from each other (increased)
var crowding_check_range: float = 7.0  # Distance to check for nearby NPCs (increased)
var crowding_restock_multiplier: float = 2.0  # Extra repel strength when near restocking station

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

func _handle_roaming(delta):
	# Priority 4: Roaming around to find enemies
	
	# If spawn position wasn't set yet, set it now
	if spawn_position == Vector3.ZERO:
		spawn_position = global_position
	
	# Update roam timer
	roam_timer += delta
	
	# Pick a new roam target periodically or if we don't have one
	if roam_timer >= roam_interval or roam_target_position == Vector3.ZERO:
		_pick_new_roam_target()
		roam_timer = 0.0
	
	# Move towards roam target
	var direction = (roam_target_position - global_position)
	direction.y = 0
	var distance = direction.length()
	
	# If we've reached the roam target, pick a new one
	if distance < 2.0:
		_pick_new_roam_target()
		return
	
	direction = direction.normalized()
	
	# Move towards roam target at slower speed
	velocity.x = direction.x * MOVE_SPEED * 0.6
	velocity.z = direction.z * MOVE_SPEED * 0.6
	
	# Face the direction we're moving
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta):
	# Don't do anything if game is paused
	if get_tree().paused:
		return
	
	# Update jump cooldown
	if jump_cooldown > 0:
		jump_cooldown -= delta
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		# Reset vertical velocity when on floor
		if velocity.y < 0:
			velocity.y = 0
	
	# PRIORITY 1: Restocking if ammo == 0
	_check_restock_needed()
	if needs_restock:
		# Reset velocity first to ensure clean state
		velocity.x = 0
		velocity.z = 0
		
		_handle_restocking(delta)
		
		# Apply minimal crowding avoidance during restocking (don't let it override direction)
		_apply_crowding_avoidance_restocking(delta)
		
		move_and_slide()
		return
	
	# PRIORITY 2: Find and shoot enemies
	_find_target()
	if target and is_instance_valid(target):
		_handle_combat(delta)
		# Apply crowding avoidance
		_apply_crowding_avoidance(delta)
		move_and_slide()
		return
	
	# PRIORITY 3: Roaming (no enemies found)
	_handle_roaming(delta)
	
	# Apply crowding avoidance
	_apply_crowding_avoidance(delta)
	
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

func _count_blocks_in_direction(check_position: Vector3, direction: Vector3, max_distance: float = 5.0) -> int:
	# Count how many blocks are in front of a position in a given direction
	# Returns the number of blocks found
	if not voxel_world:
		return 0
	
	var block_count = 0
	var check_distance = 0.5  # Check every 0.5 units
	var max_checks = int(max_distance / check_distance)
	
	# Start checking from slightly in front of the position (eye level)
	var start_pos = check_position + Vector3(0, 1.5, 0)  # Eye level
	var normalized_dir = direction.normalized()
	
	for i in range(1, max_checks + 1):
		var check_pos = start_pos + normalized_dir * (check_distance * i)
		var block_pos = Vector3i(check_pos.floor())
		var block_id = voxel_world.get_block_global_position(block_pos)
		
		if block_id != 0:  # Block exists
			block_count += 1
	
	return block_count

func _find_better_position_towards_target(target_pos: Vector3) -> Vector3:
	# Try to find a better position that has good cover (1 block) and clear view
	# Only prioritize cover that faces towards the map center (where combat happens)
	if not target or not is_instance_valid(target):
		return global_position
	
	var direction_to_target = (target_pos - global_position)
	direction_to_target.y = 0
	var distance = direction_to_target.length()
	
	# If too far, just move directly
	if distance > attack_range * 1.5:
		return target_pos
	
	# Map center is at (0, 0, 0) - this is where most combat happens
	var map_center = Vector3(0, 0, 0)
	
	# Try several positions around the direct path to find good cover
	var best_position = target_pos
	var best_score = -999.0
	
	# Check positions at different angles and distances
	var base_direction = direction_to_target.normalized()
	var perpendicular = Vector3(-base_direction.z, 0, base_direction.x)  # 90 degree rotation
	
	# Try positions: direct, left, right, slightly back
	var test_positions = [
		target_pos,  # Direct
		global_position + base_direction * (distance * 0.8) + perpendicular * 2.0,  # Left
		global_position + base_direction * (distance * 0.8) - perpendicular * 2.0,  # Right
		global_position + base_direction * (distance * 0.6),  # Closer
	]
	
	for test_pos in test_positions:
		# Make sure position is within reasonable range
		if global_position.distance_to(test_pos) > attack_range * 1.2:
			continue
		
		# Check blocks in direction to target from this position
		var dir_to_target_from_pos = (target_pos - test_pos).normalized()
		var blocks_in_view = _count_blocks_in_direction(test_pos, dir_to_target_from_pos, 5.0)
		
		# Check if this position faces towards the map center
		var dir_to_center_from_pos = (map_center - test_pos)
		dir_to_center_from_pos.y = 0
		dir_to_center_from_pos = dir_to_center_from_pos.normalized()
		
		# Calculate dot product to see if directions are similar (facing same general direction)
		var direction_similarity = dir_to_target_from_pos.dot(dir_to_center_from_pos)
		
		# Only prioritize cover if it faces towards the center (similar direction)
		# Use a threshold of 0.3 (roughly 70+ degrees) to allow some flexibility
		var faces_towards_center = direction_similarity > 0.3
		
		# Score: prefer 1 block (cover), avoid 3+ blocks (blocked)
		var score = 0.0
		if blocks_in_view == 1:
			if faces_towards_center:
				score = 10.0  # Best: good cover facing center
			else:
				score = 2.0   # Cover but wrong direction - low priority
		elif blocks_in_view == 0:
			score = 5.0   # Good: clear view
		elif blocks_in_view == 2:
			score = 2.0   # Acceptable: some obstruction
		else:  # 3 or more
			score = -10.0  # Bad: blocked view
		
		# Prefer positions closer to target (within attack range)
		var dist_to_target = test_pos.distance_to(target_pos)
		if dist_to_target <= attack_range:
			score += 5.0
		
		if score > best_score:
			best_score = score
			best_position = test_pos
	
	return best_position

func _handle_combat(_delta):
	# Priority 2: Find and shoot enemies
	# Priority 3: Find cover (1 block, facing enemy)
	
	if not target or not is_instance_valid(target):
		return
	
	var direction = (target.global_position - global_position)
	direction.y = 0
	var distance = direction.length()
	
	# Face the target
	_face_target()
	
	# If within attack range, try to find cover and shoot
	if distance <= attack_range:
		# Priority 3: Find cover (1 block, facing enemy)
		var dir_to_target = direction.normalized()
		var blocks_in_view = _count_blocks_in_direction(global_position, dir_to_target, 5.0)
		
		# If we have good cover (1 block) or clear view (0 blocks), stay and shoot
		if blocks_in_view <= 1:
			velocity.x = 0
			velocity.z = 0
			_try_attack()
			return
		
		# If view is blocked (3+ blocks), try to find better position with cover
		if blocks_in_view >= 3:
			var better_pos = _find_better_position_towards_target(target.global_position)
			var move_dir = (better_pos - global_position)
			move_dir.y = 0
			if move_dir.length() > 1.0:
				move_dir = move_dir.normalized()
				velocity.x = move_dir.x * MOVE_SPEED
				velocity.z = move_dir.z * MOVE_SPEED
				return
		
		# Otherwise, stay and shoot
		velocity.x = 0
		velocity.z = 0
		_try_attack()
		return
	
	# Move towards target, trying to find cover along the way
	direction = direction.normalized()
	var preferred_position = _find_better_position_towards_target(target.global_position)
	var move_direction = (preferred_position - global_position)
	move_direction.y = 0
	
	# Move towards preferred position (which considers cover)
	if move_direction.length() > 1.0:
		move_direction = move_direction.normalized()
		velocity.x = move_direction.x * MOVE_SPEED
		velocity.z = move_direction.z * MOVE_SPEED
	else:
		# Move directly towards target
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

func _check_restock_needed():
	# PRIORITY 1: If current weapon has 0 ammo, restocking is ALWAYS highest priority
	if weapons.size() > 0 and current_weapon_index < weapons.size():
		var current_weapon = weapons[current_weapon_index]
		var current_weapon_ammo = 0
		
		if current_weapon is Pistol:
			current_weapon_ammo = bullets
		elif current_weapon is RocketLauncher:
			current_weapon_ammo = rockets
		
		# If current weapon has 0 ammo, restock immediately (highest priority)
		if current_weapon_ammo <= 0:
			needs_restock = true
			if restocking_station_target == Vector3.ZERO:
				restocking_station_target = RestockingStation.get_nearest_station_center(global_position)
			return
	
	# Check if NPC is out of ammo for any weapon
	if bullets <= 0 and rockets <= 0:
		needs_restock = true
		if restocking_station_target == Vector3.ZERO:
			restocking_station_target = RestockingStation.get_nearest_station_center(global_position)
	elif bullets <= 0 and current_weapon_index == 0:
		# Out of bullets but has rockets - switch to rocket launcher if available
		if rockets > 0 and weapons.size() > 1:
			current_weapon_index = 1
			_update_weapon_display()
		else:
			needs_restock = true
			if restocking_station_target == Vector3.ZERO:
				restocking_station_target = RestockingStation.get_nearest_station_center(global_position)
	elif rockets <= 0 and current_weapon_index == 1:
		# Out of rockets but has bullets - switch to pistol if available
		if bullets > 0 and weapons.size() > 0:
			current_weapon_index = 0
			_update_weapon_display()
		else:
			needs_restock = true
			if restocking_station_target == Vector3.ZERO:
				restocking_station_target = RestockingStation.get_nearest_station_center(global_position)
	else:
		# Has ammo, no need to restock
		needs_restock = false

func _handle_restocking(delta):
	# Priority 1: Go to restocking station if ammo == 0
	# Automatically jump at intervals to avoid getting stuck
	# IMPORTANT: This completely overrides roaming - clear roam state
	
	# Clear any roaming state to prevent interference
	roam_target_position = Vector3.ZERO
	roam_timer = 0.0
	
	# Get restocking station target
	if restocking_station_target == Vector3.ZERO:
		restocking_station_target = RestockingStation.get_nearest_station_center(global_position)
	
	# Check if we've reached the station (use more lenient distance check)
	# Check both the station blocks and the center position for better reliability
	var near_station = RestockingStation.is_near_station(global_position, 4.0)  # Increased from 2.0 to 4.0
	
	# Also check distance to station center as fallback
	if not near_station and restocking_station_target != Vector3.ZERO:
		var distance_to_center = global_position.distance_to(restocking_station_target)
		if distance_to_center <= 4.0:  # Within 4 units of center
			near_station = true
	
	if near_station:
		RestockingStation.restock_entity(self)
		needs_restock = false
		restocking_station_target = Vector3.ZERO
		# Reset velocity to ensure clean state
		velocity.x = 0
		velocity.z = 0
		return
	
	# Move towards restocking station
	var direction = (restocking_station_target - global_position)
	direction.y = 0
	var distance = direction.length()
	
	# Stop moving if we're close enough (within 4 units)
	if distance < 4.0:
		velocity.x = 0
		velocity.z = 0
		# Still check if we can restock (might be close enough now)
		return
	
	direction = direction.normalized()
	
	# Move towards station at FULL speed (not slowed by roaming)
	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED
	
	# Face the direction we're moving
	look_at(global_position + direction, Vector3.UP)
	
	# Automatically jump at intervals to avoid getting stuck
	if is_on_floor() and jump_cooldown <= 0:
		# Jump periodically (every 1 second) when moving to restock
		if not has_meta("last_restock_jump_time"):
			set_meta("last_restock_jump_time", 0.0)
		
		var time_since_last_jump = get_meta("last_restock_jump_time")
		if time_since_last_jump >= 1.0:
			velocity.y = JUMP_VELOCITY
			jump_cooldown = 0.5
			set_meta("last_restock_jump_time", 0.0)
		else:
			set_meta("last_restock_jump_time", time_since_last_jump + delta)


func _apply_crowding_avoidance_restocking(delta):
	# Minimal crowding avoidance during restocking - don't override movement direction
	# Only apply very light repulsion to prevent complete overlap
	var all_npcs = get_tree().get_nodes_in_group("npcs")
	var repel_force = Vector3.ZERO
	
	for npc in all_npcs:
		if npc == self or not is_instance_valid(npc):
			continue
		
		# Only avoid NPCs of the same type
		if npc is NPC and (npc as NPC).npc_type == npc_type:
			var distance = global_position.distance_to(npc.global_position)
			
			# Only apply very light repulsion if extremely close (within 1 unit)
			if distance < 1.0 and distance > 0.1:
				var direction_away = (global_position - npc.global_position).normalized()
				var strength = 1.0  # Very light repulsion
				repel_force += direction_away * strength
	
	# Apply minimal repel force (much weaker than normal)
	if repel_force.length() > 0.1:
		repel_force.y = 0
		# Only apply a very small adjustment, don't override main movement
		velocity.x += repel_force.x * delta * 0.5  # Much weaker than normal
		velocity.z += repel_force.z * delta * 0.5

func _apply_crowding_avoidance(delta):
	# Repel from nearby NPCs of the same type to avoid crowding
	var all_npcs = get_tree().get_nodes_in_group("npcs")
	var repel_force = Vector3.ZERO
	var nearby_count = 0  # Count how many NPCs are too close
	
	# Check if we're near a restocking station (higher priority for spreading out)
	var near_restock = RestockingStation.is_near_station(global_position, 10.0)
	var strength_multiplier = crowding_restock_multiplier if near_restock else 1.0
	
	for npc in all_npcs:
		if npc == self or not is_instance_valid(npc):
			continue
		
		# Only avoid NPCs of the same type (allies avoid allies, enemies avoid enemies)
		if npc is NPC and (npc as NPC).npc_type == npc_type:
			var distance = global_position.distance_to(npc.global_position)
			
			# If too close, apply repel force
			if distance < crowding_check_range and distance > 0.1:
				nearby_count += 1
				var direction_away = (global_position - npc.global_position).normalized()
				# Stronger repel when closer, and extra strength near restocking stations
				var distance_factor = 1.0 - (distance / crowding_check_range)
				var strength = crowding_repel_strength * distance_factor * strength_multiplier
				# Make it even stronger if very close (within 2 units)
				if distance < 2.0:
					strength *= 2.0
				repel_force += direction_away * strength
	
	# Apply repel force to velocity with higher priority
	if repel_force.length() > 0.1:
		repel_force.y = 0  # Don't affect vertical movement
		repel_force = repel_force.normalized() * min(repel_force.length(), MOVE_SPEED * 1.5)  # Cap the force
		
		# If there are multiple NPCs nearby, prioritize spreading out more
		if nearby_count >= 2:
			# Override some movement to prioritize spreading out
			var current_speed = Vector2(velocity.x, velocity.z).length()
			if current_speed < MOVE_SPEED * 0.5:  # If not moving much, prioritize spreading
				velocity.x = repel_force.x * MOVE_SPEED
				velocity.z = repel_force.z * MOVE_SPEED
			else:
				# Blend with current movement, but give more weight to repel force
				velocity.x = lerpf(velocity.x, repel_force.x * MOVE_SPEED, 0.6)
				velocity.z = lerpf(velocity.z, repel_force.z * MOVE_SPEED, 0.6)
		else:
			# Normal application when fewer NPCs nearby
			velocity.x += repel_force.x * delta * 10.0  # Multiply by 10 to make it more immediate
			velocity.z += repel_force.z * delta * 10.0

func _on_death():
	# Decrement appropriate team's tickets
	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		if npc_type == NPCType.ALLY:
			game_manager.decrement_ally_tickets()
		elif npc_type == NPCType.ENEMY:
			game_manager.decrement_enemy_tickets()

