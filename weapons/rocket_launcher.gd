extends Weapon
class_name RocketLauncher

const ROCKET_DAMAGE = 50
const ROCKET_RANGE = 100.0
const ROCKET_FIRE_RATE = 1.0
const EXPLOSION_RADIUS = 2.0  # Reduced from 3.0 to minimize lag
const ROCKET_SPEED = 30.0

func _ready():
	damage = ROCKET_DAMAGE
	range_distance = ROCKET_RANGE
	fire_rate = ROCKET_FIRE_RATE
	super._ready()


func fire(raycast: RayCast3D, voxel_world: Node = null) -> bool:
	if not super.fire(raycast, voxel_world):
		return false
	
	# Get the fire direction from the raycast
	var fire_direction: Vector3
	if raycast.is_colliding():
		fire_direction = (raycast.get_collision_point() - raycast.global_position).normalized()
	else:
		# Fire in the direction the raycast is pointing
		fire_direction = -raycast.global_transform.basis.z
	
	# Create a rocket projectile
	_create_rocket(raycast.global_position, fire_direction, voxel_world)
	
	return true


func _create_rocket(start_pos: Vector3, direction: Vector3, voxel_world: Node):
	var rocket = Projectile.new()
	rocket.speed = ROCKET_SPEED
	rocket.damage = damage
	rocket.max_range = range_distance
	rocket.direction = direction
	rocket.owner_weapon = self
	rocket.shooter = get_parent()  # The NPC or player that owns this weapon
	
	# Store voxel_world reference for explosion
	rocket.set_meta("voxel_world", voxel_world)
	
	# Create visual representation (cylinder for rocket)
	var mesh_inst = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.1
	cylinder_mesh.bottom_radius = 0.1
	cylinder_mesh.height = 0.3
	mesh_inst.mesh = cylinder_mesh
	
	# Create material (red/orange for rocket)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.3, 0.0)  # Red-orange
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.0, 0.8)
	mesh_inst.material_override = material
	rocket.add_child(mesh_inst)
	rocket.mesh_instance = mesh_inst
	
	# Rotate mesh to face forward (cylinder needs to be rotated)
	mesh_inst.rotation.x = PI / 2
	
	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.15
	collision_shape.shape = sphere_shape
	rocket.add_child(collision_shape)
	rocket.collision_shape = collision_shape
	
	# Set start_position BEFORE adding to scene tree to avoid range calculation bug
	rocket.start_position = start_pos
	
	# Add to scene FIRST, then set position (global_position requires node to be in tree)
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	world.add_child(rocket)
	
	# Now set position after it's in the tree
	rocket.global_position = start_pos
	
	# Add trail effect (simple particle or line)
	_add_rocket_trail(rocket)


func _add_rocket_trail(rocket: Projectile):
	# Add a simple trail effect using a small light or particle
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.0)
	light.light_energy = 2.0
	light.omni_range = 1.0
	rocket.add_child(light)


func _on_projectile_hit(projectile: Projectile, target: Node, hit_position: Vector3):
	var voxel_world = projectile.get_meta("voxel_world", null)
	var weapon_owner = get_parent()
	
	# Damage NPCs in explosion radius (only if not same team)
	if target and target is NPC:
		var npc = target as NPC
		# Don't damage same team
		if weapon_owner is NPC and (weapon_owner as NPC).npc_type == npc.npc_type:
			pass  # Skip direct hit, but explosion will handle radius damage
		# Player's weapons don't damage allies
		elif weapon_owner and weapon_owner.name == "Player" and npc.npc_type == NPC.NPCType.ALLY:
			pass  # Skip direct hit
		else:
			npc.take_damage(damage)
			# Show hit marker if player hit an enemy
			if weapon_owner and weapon_owner.name == "Player" and npc.npc_type == NPC.NPCType.ENEMY:
				_show_hit_marker()
	# Check if we hit the player
	elif target and target.name == "Player" and target.has_method("take_damage"):
		# Don't damage player if weapon owner is player or ally
		if weapon_owner != target and not (weapon_owner is NPC and (weapon_owner as NPC).npc_type == NPC.NPCType.ALLY):
			target.take_damage(damage)
	# Also check for old Enemy class for backwards compatibility
	elif target and target.has_method("take_damage"):
		target.take_damage(damage)
	
	# Destroy terrain in explosion radius (only in existing chunks)
	if voxel_world:
		_destroy_terrain_around_point(hit_position, voxel_world)
	
	# Also check for NPCs and player near the explosion
	_damage_npcs_in_radius(hit_position, EXPLOSION_RADIUS)
	_damage_player_in_radius(hit_position, EXPLOSION_RADIUS)
	
	# Create explosion visual effect
	_create_explosion_effect(hit_position)


func _destroy_terrain_around_point(point: Vector3, voxel_world: Node):
	# Destroy blocks in a sphere around the explosion point
	# Only destroy blocks in chunks that already exist to prevent lag
	# Use sampling to reduce calculations - check every other block for better performance
	var radius = EXPLOSION_RADIUS
	var center = Vector3i(point.floor())
	
	# Collect all blocks to destroy
	var blocks_to_destroy = []
	
	# Use sampling - check every block but optimize distance calculation
	# Pre-calculate radius squared to avoid sqrt in inner loop
	var radius_squared = radius * radius
	
	for x in range(-int(radius), int(radius) + 1):
		for y in range(-int(radius), int(radius) + 1):
			for z in range(-int(radius), int(radius) + 1):
				var offset = Vector3i(x, y, z)
				# Use squared distance to avoid expensive sqrt
				var distance_squared = offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
				
				if distance_squared <= radius_squared:
					var block_pos = center + offset
					# Only add if the chunk exists
					var chunk_pos = Vector3i((Vector3(block_pos) / Chunk.CHUNK_SIZE).floor())
					if voxel_world._chunks.has(chunk_pos):
						blocks_to_destroy.append(block_pos)
	
	# Use batch update to destroy all blocks at once - regenerates each chunk only once!
	# Defer to next frame if too many blocks to avoid lag spike
	if blocks_to_destroy.size() > 0:
		if blocks_to_destroy.size() > 50:
			# For large explosions, split into smaller batches
			call_deferred("_destroy_blocks_batch", blocks_to_destroy, voxel_world)
		else:
			var block_ids = []
			block_ids.resize(blocks_to_destroy.size())
			block_ids.fill(0)  # 0 means empty/destroyed
			voxel_world.set_blocks_batch(blocks_to_destroy, block_ids)

func _destroy_blocks_batch(blocks_to_destroy: Array, voxel_world: Node):
	# Process blocks in smaller batches to avoid frame drops
	var batch_size = 30
	var processed = 0
	
	for i in range(0, blocks_to_destroy.size(), batch_size):
		var end_idx = min(i + batch_size, blocks_to_destroy.size())
		var batch = blocks_to_destroy.slice(i, end_idx)
		var block_ids = []
		block_ids.resize(batch.size())
		block_ids.fill(0)
		voxel_world.set_blocks_batch(batch, block_ids)
		processed += batch.size()
		
		# Yield every few batches to keep frame rate smooth
		if processed % (batch_size * 2) == 0:
			await get_tree().process_frame


func _damage_npcs_in_radius(point: Vector3, radius: float):
	# Find all NPCs in the scene and damage those within radius
	# Use groups instead of recursive search for better performance
	var weapon_owner = get_parent()
	var radius_squared = radius * radius  # Use squared distance to avoid sqrt
	
	# Get all NPCs from groups (much faster than recursive search)
	var all_npcs = get_tree().get_nodes_in_group("npcs")
	if all_npcs.is_empty():
		# Fallback to recursive search if group not used
		var world = get_tree().get_first_node_in_group("world")
		if not world:
			world = get_tree().current_scene
		var npcs = []
		_find_npcs_recursive(world, npcs)
		all_npcs = npcs
	
	for npc in all_npcs:
		if not npc or not is_instance_valid(npc):
			continue
		
		# Don't damage same team
		if weapon_owner is NPC and npc is NPC:
			if (weapon_owner as NPC).npc_type == (npc as NPC).npc_type:
				continue
		# Player's weapons don't damage allies
		if weapon_owner and weapon_owner.name == "Player":
			if npc is NPC and (npc as NPC).npc_type == NPC.NPCType.ALLY:
				continue
		
		# Use squared distance to avoid expensive sqrt
		var offset = point - npc.global_position
		var distance_squared = offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
		if distance_squared <= radius_squared:
			npc.take_damage(damage)
			# Show hit marker if player hit an enemy
			if weapon_owner and weapon_owner.name == "Player" and npc is NPC and (npc as NPC).npc_type == NPC.NPCType.ENEMY:
				_show_hit_marker()


func _find_npcs_recursive(node: Node, npcs: Array):
	if node is NPC:
		npcs.append(node)
	# Also check for old Enemy class for backwards compatibility
	elif node.has_method("take_damage") and node.has_method("get") and node.get("health"):
		npcs.append(node)
	
	for child in node.get_children():
		_find_npcs_recursive(child, npcs)

func _damage_player_in_radius(point: Vector3, radius: float):
	# Find player and damage if within radius
	var player = get_tree().get_first_node_in_group("player")
	if player and is_instance_valid(player) and player.has_method("take_damage"):
		# Don't damage player if weapon owner is player or ally
		var weapon_owner = get_parent()
		if weapon_owner == player:
			return
		if weapon_owner is NPC and (weapon_owner as NPC).npc_type == NPC.NPCType.ALLY:
			return
		
		# Use squared distance to avoid expensive sqrt
		var offset = point - player.global_position
		var radius_squared = radius * radius
		var distance_squared = offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
		if distance_squared <= radius_squared:
			player.take_damage(damage)


func _create_explosion_effect(position: Vector3):
	# Create a sphere mesh for the explosion
	var explosion_mesh = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = EXPLOSION_RADIUS * 0.5
	sphere_mesh.height = EXPLOSION_RADIUS
	explosion_mesh.mesh = sphere_mesh
	
	# Create a simple material (red/orange for explosion)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.0, 0.8)  # Orange
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.3, 0.0, 1.0)
	explosion_mesh.material_override = material
	
	# Add to scene FIRST
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	world.add_child(explosion_mesh)
	
	# Set position AFTER adding to scene tree (global_position requires node to be in tree)
	explosion_mesh.global_position = position
	
	# Animate and remove after a short time
	# Start with scale at 0 for a pop effect
	explosion_mesh.scale = Vector3(0.5, 0.5, 0.5)
	var tween = explosion_mesh.create_tween()
	tween.tween_property(explosion_mesh, "scale", Vector3(1.5, 1.5, 1.5), 0.2)
	tween.parallel().tween_property(explosion_mesh.material_override, "albedo_color:a", 0.0, 0.5)
	tween.tween_callback(explosion_mesh.queue_free)

func _show_hit_marker():
	# Get the pause menu and show hit marker
	var pause_menu = get_tree().get_first_node_in_group("pause_menu")
	if not pause_menu:
		# Try alternative path
		pause_menu = get_tree().current_scene.get_node_or_null("PauseMenu")
	if pause_menu and pause_menu.has_method("show_hit_marker"):
		pause_menu.show_hit_marker()

