extends Node

# Blood particle manager - handles spawning and managing blood particles
# with a configurable limit to improve performance

# Configuration
const MAX_BLOOD_PARTICLES = 100  # Maximum number of blood particles in scene at once
const BLOOD_PARTICLE_LIFETIME = 10.0  # How long blood particles last before cleanup

# Tracking
var blood_particles: Array[RigidBody3D] = []

func spawn_blood(position: Vector3, hit_normal: Vector3 = Vector3.UP):
	"""Spawns 3-5 blood particles at the given position with physics"""
	var num_particles = randi_range(3, 5)
	
	for i in range(num_particles):
		# Check limit before spawning
		if blood_particles.size() >= MAX_BLOOD_PARTICLES:
			# Remove oldest blood particle
			var oldest = blood_particles[0]
			if is_instance_valid(oldest):
				oldest.queue_free()
			blood_particles.remove_at(0)
		
		var blood = _create_blood_particle(position, hit_normal)
		blood_particles.append(blood)

func _create_blood_particle(position: Vector3, hit_normal: Vector3) -> RigidBody3D:
	"""Creates a single blood particle RigidBody3D"""
	var blood = RigidBody3D.new()
	
	# Add to world
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	world.add_child(blood)
	
	# Set position
	blood.global_position = position + Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.1), randf_range(-0.2, 0.2))
	
	# Create small cube mesh (coin-shaped by making it flat)
	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(0.1, 0.05, 0.1)  # Flat coin-like shape
	mesh_inst.mesh = box_mesh
	
	# Red blood material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.0, 0.0)  # Dark red
	material.roughness = 0.8
	mesh_inst.material_override = material
	blood.add_child(mesh_inst)
	
	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(0.1, 0.05, 0.1)
	collision_shape.shape = box_shape
	blood.add_child(collision_shape)
	
	# Set physics properties for "spray" effect
	blood.mass = 0.1
	blood.gravity_scale = 1.0
	
	# Apply impulse to spray out from hit position
	# Spray mostly away from hit normal with some randomness
	var spray_direction = hit_normal + Vector3(
		randf_range(-0.5, 0.5),
		randf_range(0.2, 0.8),  # More upward bias
		randf_range(-0.5, 0.5)
	).normalized()
	var spray_force = randf_range(2.0, 5.0)
	blood.apply_central_impulse(spray_direction * spray_force)
	
	# Add random angular velocity for tumbling effect
	blood.angular_velocity = Vector3(
		randf_range(-10, 10),
		randf_range(-10, 10),
		randf_range(-10, 10)
	)
	
	# Set up lifetime cleanup
	blood.set_meta("spawn_time", Time.get_ticks_msec() / 1000.0)
	
	return blood

func _process(_delta):
	# Clean up old blood particles
	var current_time = Time.get_ticks_msec() / 1000.0
	var to_remove = []
	
	for i in range(blood_particles.size()):
		var blood = blood_particles[i]
		if not is_instance_valid(blood):
			to_remove.append(i)
			continue
		
		var spawn_time = blood.get_meta("spawn_time", 0.0)
		if current_time - spawn_time >= BLOOD_PARTICLE_LIFETIME:
			blood.queue_free()
			to_remove.append(i)
	
	# Remove from tracking array (reverse order to maintain indices)
	for i in range(to_remove.size() - 1, -1, -1):
		blood_particles.remove_at(to_remove[i])

func cleanup_all():
	"""Removes all blood particles - useful for scene cleanup"""
	for blood in blood_particles:
		if is_instance_valid(blood):
			blood.queue_free()
	blood_particles.clear()

