class_name StructureGenerator
extends Resource

# Block IDs
const STONE_BLOCK = 1  # Stone texture
const AIR_BLOCK = 0
const LADDER_BLOCK = 4  # Ladder block (climbable)

# Structure generation probability
const FENCE_PROBABILITY = 0.1
const HOUSE_PROBABILITY = 0.3

# Play area boundaries (16x16 chunks = 128x128 blocks with chunk size 16, ~64 blocks radius)
const BOUNDARY_MIN = -64
const BOUNDARY_MAX = 64
const BOUNDARY_WALL_HEIGHT = 8

# Generates structures on the flat terrain
# Returns a dictionary of block positions and IDs
static func generate_structures(seed_value: int) -> Dictionary:
	var structures = {}
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Generate boundary walls first (so they can't be overwritten)
	var boundary_walls = _generate_boundary_walls()
	for pos in boundary_walls.keys():
		structures[pos] = boundary_walls[pos]
	
	# Generate houses first (urban sprawl density with multi-level buildings) - 2x increased
	# Track building bounding boxes to prevent fence intersections
	var building_bounds = []  # Array of dictionaries with min_x, max_x, min_z, max_z, min_y, max_y
	var num_houses = rng.randi_range(32, 64)  # Doubled from 16-32
	for i in range(num_houses):
		var result = _generate_modular_house_with_bounds(rng)
		var house_structures = result.house
		var bounds = result.bounds
		
		for pos in house_structures.keys():
			structures[pos] = house_structures[pos]
		
		# Track building bounding box (with some padding to prevent fences too close)
		building_bounds.append(bounds)
	
	# Generate fences (urban sprawl density) - 2x increased
	# Check for intersections with buildings before placing
	var num_fences = rng.randi_range(64, 128)  # Doubled from 24-48
	var attempts_per_fence = 10  # Try up to 10 times to find a non-intersecting position
	for i in range(num_fences):
		var fence_placed = false
		for attempt in range(attempts_per_fence):
			var fence_structures = _generate_fence(rng)
			# Check if fence would intersect with any building's bounding box
			var would_intersect = false
			for pos in fence_structures.keys():
				# Check if this fence position is inside any building's bounding box
				for bounds in building_bounds:
					if (pos.x >= bounds.min_x and pos.x <= bounds.max_x and
						pos.z >= bounds.min_z and pos.z <= bounds.max_z and
						pos.y >= bounds.min_y and pos.y <= bounds.max_y):
						would_intersect = true
						break
				if would_intersect:
					break
			
			# If no intersection, place the fence
			if not would_intersect:
				for pos in fence_structures.keys():
					structures[pos] = fence_structures[pos]
				fence_placed = true
				break
		
		# If we couldn't place the fence after all attempts, skip it
		# (This is fine - we'll just have fewer fences)
	
	return structures

# Generate indestructible boundary walls around the play area
static func _generate_boundary_walls() -> Dictionary:
	var walls = {}
	
	# Generate all four walls
	for y in range(BOUNDARY_WALL_HEIGHT):
		# North wall (along positive Z)
		for x in range(BOUNDARY_MIN, BOUNDARY_MAX + 1):
			walls[Vector3i(x, y, BOUNDARY_MAX)] = STONE_BLOCK
		
		# South wall (along negative Z)
		for x in range(BOUNDARY_MIN, BOUNDARY_MAX + 1):
			walls[Vector3i(x, y, BOUNDARY_MIN)] = STONE_BLOCK
		
		# East wall (along positive X)
		for z in range(BOUNDARY_MIN, BOUNDARY_MAX + 1):
			walls[Vector3i(BOUNDARY_MAX, y, z)] = STONE_BLOCK
		
		# West wall (along negative X)
		for z in range(BOUNDARY_MIN, BOUNDARY_MAX + 1):
			walls[Vector3i(BOUNDARY_MIN, y, z)] = STONE_BLOCK
	
	return walls

# Generate a simple fence (line of stone blocks)
static func _generate_fence(rng: RandomNumberGenerator) -> Dictionary:
	var fence = {}
	
	# Random position on the map (16x16 play area)
	var start_x = rng.randi_range(-55, 55)
	var start_z = rng.randi_range(-55, 55)
	var y = 0  # Ground level
	
	# Random direction (horizontal or vertical)
	var horizontal = rng.randf() < 0.5
	var length = rng.randi_range(3, 8)
	
	if horizontal:
		# Fence along X axis
		for i in range(length):
			var pos = Vector3i(start_x + i, y, start_z)
			fence[pos] = STONE_BLOCK
			# Add a second layer for more visibility
			fence[Vector3i(start_x + i, y + 1, start_z)] = STONE_BLOCK
	else:
		# Fence along Z axis
		for i in range(length):
			var pos = Vector3i(start_x, y, start_z + i)
			fence[pos] = STONE_BLOCK
			# Add a second layer for more visibility
			fence[Vector3i(start_x, y + 1, start_z + i)] = STONE_BLOCK
	
	return fence

# Generate a modular house with stairs and flat roof (stackable for multi-level buildings)
# Returns a dictionary with 'house' (block positions) and 'bounds' (bounding box)
static func _generate_modular_house_with_bounds(rng: RandomNumberGenerator) -> Dictionary:
	var result = {}
	var house = {}
	
	# Random position on the map (16x16 play area)
	var base_x = rng.randi_range(-55, 55)
	var base_z = rng.randi_range(-55, 55)
	var base_y = 0  # Start at y=0 (ground level)
	
	# House dimensions (standard module size for stacking)
	var width = rng.randi_range(5, 7)
	var depth = rng.randi_range(5, 7)
	var floor_height = 4  # Standard floor height (3 blocks walls + 1 block ceiling)
	
	# Randomly decide if this is a multi-story building (20% chance of 2-story, 10% chance of 3-story)
	var num_floors = 1
	var rand_val = rng.randf()
	if rand_val < 0.1:
		num_floors = 3
	elif rand_val < 0.3:
		num_floors = 2
	
	# Calculate bounding box (with padding to prevent fences too close)
	var bounds = {
		"min_x": base_x - 1,
		"max_x": base_x + width,
		"min_z": base_z - 1,
		"max_z": base_z + depth,
		"min_y": base_y,
		"max_y": base_y + (num_floors * floor_height)
	}
	
	# Generate each floor
	for floor in range(num_floors):
		var floor_y = base_y + (floor * floor_height)
		
		# Generate walls and ceiling for this level (NO FLOOR on first level!)
		for x in range(width):
			for y in range(floor_height):
				for z in range(depth):
					var pos = Vector3i(base_x + x, floor_y + y, base_z + z)
					
					# Only place blocks on the edges (walls)
					var is_edge = x == 0 or x == width - 1 or z == 0 or z == depth - 1
					var is_floor_block = y == 0
					var is_ceiling = y == floor_height - 1
					
					# Place walls and ceilings, but skip floor blocks on ground level
					if floor == 0:
						# Ground floor: only walls and ceiling, no floor
						if (is_edge and not is_floor_block) or is_ceiling:
							house[pos] = STONE_BLOCK
					else:
						# Upper floors: walls, floor, and ceiling
						if is_edge or is_floor_block or is_ceiling:
							house[pos] = STONE_BLOCK
		
		# Create door opening on ground floor only
		if floor == 0:
			var door_x = base_x + width / 2
			var door_z = base_z  # Door on the front wall
			for y in range(1, 3):  # 2 blocks tall door (y=1 and y=2)
				var door_pos = Vector3i(door_x, floor_y + y, door_z)
				house.erase(door_pos)
		
		# Create windows on each floor (shooting positions)
		# Front windows (2 windows)
		if width >= 5:
			var window_z = base_z
			house.erase(Vector3i(base_x + 1, floor_y + 2, window_z))
			house.erase(Vector3i(base_x + width - 2, floor_y + 2, window_z))
		
		# Back windows (2 windows)
		if width >= 5:
			var window_z = base_z + depth - 1
			house.erase(Vector3i(base_x + 1, floor_y + 2, window_z))
			house.erase(Vector3i(base_x + width - 2, floor_y + 2, window_z))
		
		# Side windows
		if depth >= 5:
			# Left wall
			house.erase(Vector3i(base_x, floor_y + 2, base_z + 1))
			house.erase(Vector3i(base_x, floor_y + 2, base_z + depth - 2))
			# Right wall
			house.erase(Vector3i(base_x + width - 1, floor_y + 2, base_z + 1))
			house.erase(Vector3i(base_x + width - 1, floor_y + 2, base_z + depth - 2))
	
	# Add interior ladder for multi-story buildings
	if num_floors > 1:
		# Choose a wall for the ladder (0 = front, 1 = back, 2 = left, 3 = right)
		var ladder_wall = rng.randi_range(0, 3)
		var ladder_x: int
		var ladder_z: int
		var ladder_inside_x: int  # Position inside the building to access ladder
		var ladder_inside_z: int
		
		# Determine ladder position on wall and inside access point
		if ladder_wall == 0:  # Front wall (base_z)
			ladder_x = base_x + (width / 2) as int  # Center of wall
			ladder_z = base_z  # On the wall
			ladder_inside_x = ladder_x
			ladder_inside_z = base_z + 1  # One block inside
		elif ladder_wall == 1:  # Back wall (base_z + depth - 1)
			ladder_x = base_x + (width / 2) as int  # Center of wall
			ladder_z = base_z + depth - 1  # On the wall
			ladder_inside_x = ladder_x
			ladder_inside_z = base_z + depth - 2  # One block inside
		elif ladder_wall == 2:  # Left wall (base_x)
			ladder_x = base_x  # On the wall
			ladder_z = base_z + (depth / 2) as int  # Center of wall
			ladder_inside_x = base_x + 1  # One block inside
			ladder_inside_z = ladder_z
		else:  # Right wall (base_x + width - 1)
			ladder_x = base_x + width - 1  # On the wall
			ladder_z = base_z + (depth / 2) as int  # Center of wall
			ladder_inside_x = base_x + width - 2  # One block inside
			ladder_inside_z = ladder_z
		
		# Create ladder going up the full height of the building
		var total_height = num_floors * floor_height
		for y in range(total_height):
			var ladder_y = base_y + y
			# Place ladder block on the wall
			house[Vector3i(ladder_x, ladder_y, ladder_z)] = LADDER_BLOCK
		
		# Create access hole on the inside wall for each floor above ground
		for floor in range(1, num_floors):
			var floor_y = base_y + (floor * floor_height)
			# Remove the wall block at the inside access point to create an opening
			# This allows players to enter the ladder area from inside the building
			if ladder_wall == 0:  # Front wall
				house.erase(Vector3i(ladder_inside_x, floor_y + 1, ladder_inside_z))
				house.erase(Vector3i(ladder_inside_x, floor_y + 2, ladder_inside_z))
			elif ladder_wall == 1:  # Back wall
				house.erase(Vector3i(ladder_inside_x, floor_y + 1, ladder_inside_z))
				house.erase(Vector3i(ladder_inside_x, floor_y + 2, ladder_inside_z))
			elif ladder_wall == 2:  # Left wall
				house.erase(Vector3i(ladder_inside_x, floor_y + 1, ladder_inside_z))
				house.erase(Vector3i(ladder_inside_x, floor_y + 2, ladder_inside_z))
			else:  # Right wall
				house.erase(Vector3i(ladder_inside_x, floor_y + 1, ladder_inside_z))
				house.erase(Vector3i(ladder_inside_x, floor_y + 2, ladder_inside_z))
			
			# Also create a hole in the ceiling/floor above to allow vertical passage
			var ceiling_top_y = floor_y + floor_height - 1
			house.erase(Vector3i(ladder_inside_x, ceiling_top_y, ladder_inside_z))
			house.erase(Vector3i(ladder_inside_x, floor_y, ladder_inside_z))
	
	result.house = house
	result.bounds = bounds
	return result

# Generate a modular house with stairs and flat roof (stackable for multi-level buildings)
# Legacy function for backwards compatibility
static func _generate_modular_house(rng: RandomNumberGenerator) -> Dictionary:
	var result = _generate_modular_house_with_bounds(rng)
	return result.house

