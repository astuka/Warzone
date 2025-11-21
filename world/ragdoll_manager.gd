extends Node

# Ragdoll manager - handles converting dead NPCs to ragdolls with physics
# with a configurable limit to improve performance

# Configuration
const MAX_RAGDOLLS = 30  # Maximum number of ragdolls in scene at once
const RAGDOLL_LIFETIME = 15.0  # How long ragdolls last before cleanup
const DEATH_COLOR = Color(0.7, 0.7, 0.7)  # Light gray for dead NPCs

# Tracking
var ragdolls: Array[RigidBody3D] = []

func create_ragdoll(npc_position: Vector3, npc_color: Color, impulse: Vector3 = Vector3.ZERO):
	"""Creates a ragdoll from an NPC's death, with physics enabled"""
	
	# Check limit before spawning
	if ragdolls.size() >= MAX_RAGDOLLS:
		# Remove oldest ragdoll
		var oldest = ragdolls[0]
		if is_instance_valid(oldest):
			oldest.queue_free()
		ragdolls.remove_at(0)
	
	var ragdoll = _create_ragdoll_body(npc_position, npc_color, impulse)
	ragdolls.append(ragdoll)

func _create_ragdoll_body(position: Vector3, original_color: Color, impulse: Vector3) -> RigidBody3D:
	"""Creates a single ragdoll RigidBody3D"""
	var ragdoll = RigidBody3D.new()
	
	# Add to world
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	world.add_child(ragdoll)
	
	# Set position
	ragdoll.global_position = position
	
	# Create mesh matching NPC body (2 units tall, 1x1 base)
	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1, 2, 1)
	mesh_inst.mesh = box_mesh
	mesh_inst.position = Vector3(0, 1, 0)  # Center mesh vertically
	
	# Death material (light gray)
	var material = StandardMaterial3D.new()
	material.albedo_color = DEATH_COLOR
	material.roughness = 0.9
	mesh_inst.material_override = material
	ragdoll.add_child(mesh_inst)
	
	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(1, 2, 1)
	collision_shape.shape = box_shape
	collision_shape.position = Vector3(0, 1, 0)  # Match mesh position
	ragdoll.add_child(collision_shape)
	
	# Set physics properties
	ragdoll.mass = 70.0  # Human-like weight
	ragdoll.gravity_scale = 1.0
	
	# Apply initial impulse (from bullet/rocket impact)
	if impulse.length() > 0:
		ragdoll.apply_central_impulse(impulse)
	
	# Add some random angular velocity for tumbling
	ragdoll.angular_velocity = Vector3(
		randf_range(-2, 2),
		randf_range(-2, 2),
		randf_range(-2, 2)
	)
	
	# Set up lifetime cleanup
	ragdoll.set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)
	
	return ragdoll

func _process(_delta):
	# Clean up old ragdolls
	var current_time = Time.get_ticks_msec() / 1000.0
	var to_remove = []
	
	for i in range(ragdolls.size()):
		var ragdoll = ragdolls[i]
		if not is_instance_valid(ragdoll):
			to_remove.append(i)
			continue
		
		var spawn_time = ragdoll.get_meta("spawn_time", 0.0)
		if current_time - spawn_time >= RAGDOLL_LIFETIME:
			ragdoll.queue_free()
			to_remove.append(i)
	
	# Remove from tracking array (reverse order to maintain indices)
	for i in range(to_remove.size() - 1, -1, -1):
		ragdolls.remove_at(to_remove[i])

func cleanup_all():
	"""Removes all ragdolls - useful for scene cleanup"""
	for ragdoll in ragdolls:
		if is_instance_valid(ragdoll):
			ragdoll.queue_free()
	ragdolls.clear()

