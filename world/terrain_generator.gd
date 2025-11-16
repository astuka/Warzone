class_name TerrainGenerator
extends Resource

# Can't be "Chunk.CHUNK_SIZE" due to cyclic dependency issues.
# https://github.com/godotengine/godot/issues/21461
const CHUNK_SIZE = 16

const RANDOM_BLOCK_PROBABILITY = 0.015

# Static structures cache - generated once and reused
static var _structures_cache = null
static var _structures_generated = false


static func reset_cache():
	# Call this when starting a new world to ensure different generation
	_structures_cache = null
	_structures_generated = false


static func empty():
	return {}


static func random_blocks():
	var random_data = {}
	for x in range(CHUNK_SIZE):
		for y in range(CHUNK_SIZE):
			for z in range(CHUNK_SIZE):
				var vec = Vector3i(x, y, z)
				if randf() < RANDOM_BLOCK_PROBABILITY:
					random_data[vec] = randi() % 29 + 1
	return random_data


static func flat(chunk_position):
	var data = {}

	# Generate multiple layers: grass on top, dirt below
	# Ground level is at global y=0, which is in chunk y=0
	
	var num_dirt_layers = 4  # Number of dirt layers below grass
	
	# Generate grass layer at ground level (chunk y=0, local y=0 = global y=0)
	if chunk_position.y == 0:
		# Grass layer at y=0 (ground level)
		for x in range(CHUNK_SIZE):
			for z in range(CHUNK_SIZE):
				data[Vector3i(x, 0, z)] = 3  # Grass
	
	# Generate dirt layers below grass (in chunk y=-1)
	if chunk_position.y == -1:
		# Fill the top part of this chunk with dirt
		# These represent blocks at global y = -1, -2, -3, -4
		# In chunk y=-1, these are at local y = 15, 14, 13, 12
		for layer in range(num_dirt_layers):
			var local_y = CHUNK_SIZE - 1 - layer  # Start from top of chunk
			for x in range(CHUNK_SIZE):
				for z in range(CHUNK_SIZE):
					data[Vector3i(x, local_y, z)] = 2  # Dirt
	
	# Generate structures on ground level (chunk_position.y == 0)
	if chunk_position.y == 0:
		# Generate structures once and cache them
		if not _structures_generated:
			# Use a random seed based on time for different maps each game
			randomize()
			var random_seed = randi()
			_structures_cache = StructureGenerator.generate_structures(random_seed)
			_structures_generated = true
		
		# Check if any structures fall within this chunk
		if _structures_cache:
			for global_pos in _structures_cache.keys():
				# Convert global position to chunk position using floor division
				var chunk_pos = Vector3i(
					floori(float(global_pos.x) / float(CHUNK_SIZE)),
					floori(float(global_pos.y) / float(CHUNK_SIZE)),
					floori(float(global_pos.z) / float(CHUNK_SIZE))
				)
				
				if chunk_pos == chunk_position:
					# Calculate local position properly for negative coordinates
					# Use posmod which always returns positive values
					var local_pos = Vector3i(
						posmod(global_pos.x, CHUNK_SIZE),
						posmod(global_pos.y, CHUNK_SIZE),
						posmod(global_pos.z, CHUNK_SIZE)
					)
					
					data[local_pos] = _structures_cache[global_pos]

	return data


# Used to create the project icon.
static func origin_grass(chunk_position):
	if chunk_position == Vector3i.ZERO:
		return {Vector3i.ZERO: 3}

	return {}
