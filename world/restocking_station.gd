extends Node
class_name RestockingStation

# Global manager for restocking stations
# Tracks which block positions are restocking stations

static var station_positions: Array[Vector3i] = []

# Station positions (3x3x3 cubes)
static var ally_station_center: Vector3i = Vector3i(-50, 1, 0)  # Center of ally station
static var enemy_station_center: Vector3i = Vector3i(50, 1, 0)  # Center of enemy station

static func initialize_stations():
	# Clear existing stations
	station_positions.clear()
	
	# Generate all block positions for each 3x3x3 station
	for station_center in [ally_station_center, enemy_station_center]:
		for x in range(-1, 2):  # -1 to 1
			for y in range(-1, 2):
				for z in range(-1, 2):
					var pos = station_center + Vector3i(x, y, z)
					station_positions.append(pos)

static func is_restocking_station(block_pos: Vector3i) -> bool:
	for pos in station_positions:
		if pos == block_pos:
			return true
	return false

static func get_nearest_station_center(position: Vector3) -> Vector3:
	# Get the center position of the nearest restocking station
	var pos_v3i = Vector3i(position.floor())
	var ally_dist = Vector3(pos_v3i).distance_to(Vector3(ally_station_center))
	var enemy_dist = Vector3(pos_v3i).distance_to(Vector3(enemy_station_center))
	
	if ally_dist < enemy_dist:
		return Vector3(ally_station_center)
	else:
		return Vector3(enemy_station_center)

static func is_near_station(position: Vector3, distance_threshold: float = 2.0) -> bool:
	# Check if position is near any restocking station that still exists
	var pos_v3i = Vector3i(position.floor())
	var voxel_world = Engine.get_main_loop().current_scene.get_node_or_null("VoxelWorld")
	if not voxel_world:
		return false
	
	for station_pos in station_positions:
		# Check if station block still exists (not destroyed)
		var block_id = voxel_world.get_block_global_position(station_pos)
		if block_id != 0:  # Block exists (not air)
			if Vector3(pos_v3i).distance_to(Vector3(station_pos)) <= distance_threshold:
				return true
	return false

static func restock_entity(entity):
	# Restock ammo for an entity (player or NPC)
	# Both Player and NPC classes have these properties defined
	entity.bullets = entity.DEFAULT_BULLETS
	entity.rockets = entity.DEFAULT_ROCKETS
	entity.blocks = entity.DEFAULT_BLOCKS

