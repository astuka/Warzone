extends Weapon
class_name Pistol

const PISTOL_DAMAGE = 25
const PISTOL_RANGE = 50.0
const PISTOL_FIRE_RATE = 0.25
const BULLET_SPEED = 60.0
const BLOCK_HITS_TO_DESTROY = 10

# Static dictionary to track block damage across all pistol instances
static var block_damage_tracker = {}

func _ready():
	damage = PISTOL_DAMAGE
	range_distance = PISTOL_RANGE
	fire_rate = PISTOL_FIRE_RATE
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
	
	# Create a bullet projectile
	_create_bullet(raycast.global_position, fire_direction, voxel_world)
	
	return true


func _create_bullet(start_pos: Vector3, direction: Vector3, voxel_world: Node):
	var bullet = Projectile.new()
	bullet.speed = BULLET_SPEED
	bullet.damage = damage
	bullet.max_range = range_distance
	bullet.direction = direction
	bullet.owner_weapon = self
	bullet.shooter = get_parent()  # The NPC or player that owns this weapon
	
	# Create visual representation (small sphere for bullet)
	var mesh_inst = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.05
	sphere_mesh.height = 0.1
	mesh_inst.mesh = sphere_mesh
	
	# Create material (yellow/gold for bullet)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.8, 0.0)  # Gold/yellow
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.8, 0.0, 0.5)
	mesh_inst.material_override = material
	bullet.add_child(mesh_inst)
	bullet.mesh_instance = mesh_inst
	
	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = 0.05
	collision_shape.shape = sphere_shape
	bullet.add_child(collision_shape)
	bullet.collision_shape = collision_shape
	
	# Set start_position BEFORE adding to scene tree to avoid range calculation bug
	bullet.start_position = start_pos
	
	# Add to scene FIRST, then set position (global_position requires node to be in tree)
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	world.add_child(bullet)
	
	# Now set position after it's in the tree
	bullet.global_position = start_pos


func _on_projectile_hit(projectile: Projectile, target: Node, hit_position: Vector3):
	# Get weapon owner
	var weapon_owner = get_parent()
	
	# Calculate impact direction for physics
	var impact_direction = projectile.direction if projectile else Vector3.ZERO
	
	# Check if we hit an NPC
	if target and target is NPC:
		var npc = target as NPC
		# Don't damage same team
		if weapon_owner is NPC and (weapon_owner as NPC).npc_type == npc.npc_type:
			return
		# Player's weapons don't damage allies
		if weapon_owner and weapon_owner.name == "Player" and npc.npc_type == NPC.NPCType.ALLY:
			return
		# Apply bullet force (scaled for physics effect)
		var bullet_force = impact_direction * 2.0
		npc.take_damage(damage, bullet_force)
		# Show hit marker if player hit an enemy
		if weapon_owner and weapon_owner.name == "Player" and npc.npc_type == NPC.NPCType.ENEMY:
			_show_hit_marker()
	# Check if we hit the player
	elif target and target.name == "Player" and target.has_method("take_damage"):
		# Don't damage player if weapon owner is player or ally
		if weapon_owner == target:
			return
		if weapon_owner is NPC and (weapon_owner as NPC).npc_type == NPC.NPCType.ALLY:
			return
		target.take_damage(damage)
	# Check if we hit terrain/blocks (StaticBody3D or Chunk)
	elif target and (target is StaticBody3D or target is Chunk):
		_damage_block_at_position(hit_position)
	# Also check for old Enemy class for backwards compatibility
	elif target and target.has_method("take_damage"):
		target.take_damage(damage)

func _damage_block_at_position(hit_position: Vector3):
	# Get the voxel world
	var voxel_world = get_tree().get_first_node_in_group("voxel_world")
	if not voxel_world:
		return
	
	# Convert hit position to block position
	var block_pos = Vector3i(hit_position.floor())
	
	# Get the current block at this position
	var current_block_id = voxel_world.get_block_global_position(block_pos)
	if current_block_id == 0:
		return  # No block here
	
	# Track damage to this block
	var block_key = str(block_pos)
	if not block_damage_tracker.has(block_key):
		block_damage_tracker[block_key] = {
			"hits": 0,
			"original_block_id": current_block_id
		}
	
	# Increment hit count
	block_damage_tracker[block_key]["hits"] += 1
	var hits = block_damage_tracker[block_key]["hits"]
	
	# Check if block should be destroyed
	if hits >= BLOCK_HITS_TO_DESTROY:
		voxel_world.set_block_global_position(block_pos, 0)  # Destroy block
		block_damage_tracker.erase(block_key)  # Remove from tracker
	# Don't change the block texture during damage - just track hits until destruction

func _show_hit_marker():
	# Get the pause menu and show hit marker
	var pause_menu = get_tree().get_first_node_in_group("pause_menu")
	if not pause_menu:
		# Try alternative path
		pause_menu = get_tree().current_scene.get_node_or_null("PauseMenu")
	if pause_menu and pause_menu.has_method("show_hit_marker"):
		pause_menu.show_hit_marker()

