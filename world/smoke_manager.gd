extends Node

# Smoke manager - handles spawning smoke effects at rocket impact locations
# Smoke consists of vertically stacked spheres with slight random offset

# Configuration
const SMOKE_DURATION = 3.0 # How long smoke lasts before disappearing
const SMOKE_PARTICLES_PER_CLOUD = 5 # Number of spheres per smoke cloud
const SMOKE_PARTICLE_SPACING_VERTICAL = 3 # Vertical spacing between smoke particles
const SMOKE_PARTICLE_SPACING_HORIZONTAL = 3 # Vertical spacing between smoke particles
const SMOKE_PARTICLE_SIZE = 3 # Base size of each smoke sphere

# Tracking
var smoke_clouds: Array = []

func spawn_smoke(position: Vector3):
	"""Spawns a smoke cloud at the given position (rocket impact)"""
	var smoke_cloud = {
		"position": position,
		"particles": [],
		"spawn_time": Time.get_ticks_msec() / 1000.0,
		"lifetime": SMOKE_DURATION
	}
	
	# Create smoke particles (spheres stacked vertically)
	for i in range(SMOKE_PARTICLES_PER_CLOUD):
		var particle = _create_smoke_particle(position, i)
		smoke_cloud["particles"].append(particle)
	
	smoke_clouds.append(smoke_cloud)

func _create_smoke_particle(base_position: Vector3, stack_index: int) -> MeshInstance3D:
	"""Creates a single smoke particle sphere"""
	var particle = MeshInstance3D.new()
	
	# Add to world
	var world = get_tree().get_first_node_in_group("world")
	if not world:
		world = get_tree().current_scene
	world.add_child(particle)
	
	# Create sphere mesh
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = SMOKE_PARTICLE_SIZE
	sphere_mesh.height = SMOKE_PARTICLE_SIZE * 2
	particle.mesh = sphere_mesh
	
	# Create smoke material (gray, slightly transparent)
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.3, 0.3, 0.5) # Dark gray, semi-transparent
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED # Visible from all angles
	particle.material_override = material
	
	# Position with vertical stacking and random horizontal offset
	var vertical_offset = stack_index * SMOKE_PARTICLE_SPACING_VERTICAL
	var horizontal_offset = Vector3(
		randf_range(-SMOKE_PARTICLE_SPACING_HORIZONTAL, SMOKE_PARTICLE_SPACING_HORIZONTAL),
		0,
		randf_range(-SMOKE_PARTICLE_SPACING_HORIZONTAL, SMOKE_PARTICLE_SPACING_HORIZONTAL)
	)
	particle.global_position = base_position + Vector3(0, vertical_offset, 0) + horizontal_offset
	
	# Make particles non-collidable (they're just visual)
	# No collision shape needed - MeshInstance3D doesn't collide by default
	
	return particle

func _process(_delta):
	# Update and remove expired smoke clouds (FIFO order)
	var current_time = Time.get_ticks_msec() / 1000.0
	var to_remove = []
	
	for i in range(smoke_clouds.size()):
		var cloud = smoke_clouds[i]
		var spawn_time = cloud["spawn_time"]
		var age = current_time - spawn_time
		
		# Fade out smoke particles over time
		var fade_progress = age / cloud["lifetime"]
		for particle in cloud["particles"]:
			if is_instance_valid(particle) and particle.material_override:
				var alpha = lerp(0.5, 0.0, fade_progress)
				particle.material_override.albedo_color.a = alpha
		
		# Mark for removal if expired
		if age >= cloud["lifetime"]:
			# Clean up particles
			for particle in cloud["particles"]:
				if is_instance_valid(particle):
					particle.queue_free()
			to_remove.append(i)
	
	# Remove expired clouds (reverse order to maintain indices)
	for i in range(to_remove.size() - 1, -1, -1):
		smoke_clouds.remove_at(to_remove[i])

func cleanup_all():
	"""Removes all smoke - useful for scene cleanup"""
	for cloud in smoke_clouds:
		for particle in cloud["particles"]:
			if is_instance_valid(particle):
				particle.queue_free()
	smoke_clouds.clear()
