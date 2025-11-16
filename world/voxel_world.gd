extends Node
# This file manages the creation and deletion of Chunks.

const CHUNK_MIDPOINT = Vector3(0.5, 0.5, 0.5) * Chunk.CHUNK_SIZE
const CHUNK_END_SIZE = Chunk.CHUNK_SIZE - 1

# Boundary wall limits (must match structure_generator.gd)
const BOUNDARY_MIN = -64
const BOUNDARY_MAX = 64
const BOUNDARY_WALL_HEIGHT = 8

var render_distance:
	set(value):
		render_distance = value
		_delete_distance = value + 2

var _delete_distance = 0
var effective_render_distance = 0
var _old_player_chunk = Vector3i()

var _generating = true
var _deleting = false

var _chunks = {}

@onready var player = $"../Player"


func _ready():
	# Reset terrain generation cache to ensure different maps each time
	TerrainGenerator.reset_cache()


func _process(_delta):
	render_distance = Settings.render_distance
	var player_chunk = Vector3i((player.transform.origin / Chunk.CHUNK_SIZE).round())

	if _deleting or player_chunk != _old_player_chunk:
		_delete_far_away_chunks(player_chunk)
		_generating = true

	if not _generating:
		return

	# Try to generate chunks ahead of time based on where the player is moving.
	player_chunk.y += round(clamp(player.velocity.y, -render_distance / 4, render_distance / 4))

	# Check existing chunks within range. If it doesn't exist, create it.
	for x in range(player_chunk.x - effective_render_distance, player_chunk.x + effective_render_distance):
		for y in range(player_chunk.y - effective_render_distance, player_chunk.y + effective_render_distance):
			for z in range(player_chunk.z - effective_render_distance, player_chunk.z + effective_render_distance):
				var chunk_position = Vector3i(x, y, z)
				if Vector3(player_chunk).distance_to(Vector3(chunk_position)) > render_distance:
					continue

				if _chunks.has(chunk_position):
					continue

				var chunk = Chunk.new()
				chunk.chunk_position = chunk_position
				_chunks[chunk_position] = chunk
				add_child(chunk)
				return

	# If we didn't generate any chunks (and therefore didn't return), what next?
	if effective_render_distance < render_distance:
		# We can move on to the next stage by increasing the effective distance.
		effective_render_distance += 1
	else:
		# Effective render distance is maxed out, done generating.
		_generating = false


func get_block_global_position(block_global_position: Vector3i):
	var chunk_position = Vector3i((Vector3(block_global_position) / Chunk.CHUNK_SIZE).floor())
	if _chunks.has(chunk_position):
		var chunk = _chunks[chunk_position]
		var sub_position = Vector3i(Vector3(block_global_position).posmod(Chunk.CHUNK_SIZE))
		if chunk.data.has(sub_position):
			return chunk.data[sub_position]
	return 0


func _is_boundary_wall(pos: Vector3i) -> bool:
	# Check if position is part of the boundary wall
	if pos.y < 0 or pos.y >= BOUNDARY_WALL_HEIGHT:
		return false
	
	# Check if on any of the four walls
	return (pos.x == BOUNDARY_MIN or pos.x == BOUNDARY_MAX or 
			pos.z == BOUNDARY_MIN or pos.z == BOUNDARY_MAX)

func set_block_global_position(block_global_position: Vector3i, block_id):
	# Prevent modification of boundary walls
	if _is_boundary_wall(block_global_position):
		return
	
	var chunk_position = Vector3i((Vector3(block_global_position) / Chunk.CHUNK_SIZE).floor())
	
	# Only modify blocks in chunks that exist - prevents lag from generating new chunks
	if not _chunks.has(chunk_position):
		return
	
	var chunk = _chunks[chunk_position]
	var sub_position = Vector3i(Vector3(block_global_position).posmod(Chunk.CHUNK_SIZE))
	if block_id == 0:
		chunk.data.erase(sub_position)
	else:
		chunk.data[sub_position] = block_id
	chunk.regenerate()

	# We also might need to regenerate some neighboring chunks (only if they exist).
	if Chunk.is_block_transparent(block_id):
		if sub_position.x == 0:
			var neighbor_pos = chunk_position + Vector3i.LEFT
			if _chunks.has(neighbor_pos):
				_chunks[neighbor_pos].regenerate()
		elif sub_position.x == CHUNK_END_SIZE:
			var neighbor_pos = chunk_position + Vector3i.RIGHT
			if _chunks.has(neighbor_pos):
				_chunks[neighbor_pos].regenerate()
		if sub_position.z == 0:
			var neighbor_pos = chunk_position + Vector3i.FORWARD
			if _chunks.has(neighbor_pos):
				_chunks[neighbor_pos].regenerate()
		elif sub_position.z == CHUNK_END_SIZE:
			var neighbor_pos = chunk_position + Vector3i.BACK
			if _chunks.has(neighbor_pos):
				_chunks[neighbor_pos].regenerate()
		if sub_position.y == 0:
			var neighbor_pos = chunk_position + Vector3i.DOWN
			if _chunks.has(neighbor_pos):
				_chunks[neighbor_pos].regenerate()
		elif sub_position.y == CHUNK_END_SIZE:
			var neighbor_pos = chunk_position + Vector3i.UP
			if _chunks.has(neighbor_pos):
				_chunks[neighbor_pos].regenerate()


# Batch version that doesn't regenerate until all blocks are set
func set_blocks_batch(block_positions: Array, block_ids: Array):
	if block_positions.size() != block_ids.size():
		push_error("set_blocks_batch: arrays must be same size")
		return
	
	var affected_chunks = {}  # Track which chunks need regeneration
	
	# Set all blocks without regenerating
	for i in range(block_positions.size()):
		var block_global_position = block_positions[i]
		var block_id = block_ids[i]
		
		# Skip boundary walls
		if _is_boundary_wall(block_global_position):
			continue
		
		var chunk_position = Vector3i((Vector3(block_global_position) / Chunk.CHUNK_SIZE).floor())
		
		# Only modify blocks in chunks that exist
		if not _chunks.has(chunk_position):
			continue
		
		var chunk = _chunks[chunk_position]
		var sub_position = Vector3i(Vector3(block_global_position).posmod(Chunk.CHUNK_SIZE))
		
		if block_id == 0:
			chunk.data.erase(sub_position)
		else:
			chunk.data[sub_position] = block_id
		
		# Mark this chunk and potentially neighboring chunks for regeneration
		affected_chunks[chunk_position] = true
		
		# Check if we need to regenerate neighboring chunks
		if Chunk.is_block_transparent(block_id):
			if sub_position.x == 0:
				var neighbor_pos = chunk_position + Vector3i.LEFT
				if _chunks.has(neighbor_pos):
					affected_chunks[neighbor_pos] = true
			elif sub_position.x == CHUNK_END_SIZE:
				var neighbor_pos = chunk_position + Vector3i.RIGHT
				if _chunks.has(neighbor_pos):
					affected_chunks[neighbor_pos] = true
			if sub_position.z == 0:
				var neighbor_pos = chunk_position + Vector3i.FORWARD
				if _chunks.has(neighbor_pos):
					affected_chunks[neighbor_pos] = true
			elif sub_position.z == CHUNK_END_SIZE:
				var neighbor_pos = chunk_position + Vector3i.BACK
				if _chunks.has(neighbor_pos):
					affected_chunks[neighbor_pos] = true
			if sub_position.y == 0:
				var neighbor_pos = chunk_position + Vector3i.DOWN
				if _chunks.has(neighbor_pos):
					affected_chunks[neighbor_pos] = true
			elif sub_position.y == CHUNK_END_SIZE:
				var neighbor_pos = chunk_position + Vector3i.UP
				if _chunks.has(neighbor_pos):
					affected_chunks[neighbor_pos] = true
	
	# Now regenerate all affected chunks once
	for chunk_pos in affected_chunks.keys():
		if _chunks.has(chunk_pos):
			_chunks[chunk_pos].regenerate()


func clean_up():
	for chunk_position_key in _chunks.keys():
		var thread = _chunks[chunk_position_key]._thread
		if thread:
			thread.wait_to_finish()
	_chunks = {}
	set_process(false)
	for c in get_children():
		c.free()


func _delete_far_away_chunks(player_chunk):
	_old_player_chunk = player_chunk
	# If we need to delete chunks, give the new chunk system a chance to catch up.
	effective_render_distance = max(1, effective_render_distance - 1)

	var deleted_this_frame = 0
	# We should delete old chunks more aggressively if moving fast.
	# An easy way to calculate this is by using the effective render distance.
	# The specific values in this formula are arbitrary and from experimentation.
	var max_deletions = clamp(2 * (render_distance - effective_render_distance), 2, 8)
	# Also take the opportunity to delete far away chunks.
	for chunk_position_key in _chunks.keys():
		if Vector3(player_chunk).distance_to(Vector3(chunk_position_key)) > _delete_distance:
			var thread = _chunks[chunk_position_key]._thread
			if thread:
				thread.wait_to_finish()
			_chunks[chunk_position_key].queue_free()
			_chunks.erase(chunk_position_key)
			deleted_this_frame += 1
			# Limit the amount of deletions per frame to avoid lag spikes.
			if deleted_this_frame > max_deletions:
				# Continue deleting next frame.
				_deleting = true
				return

	# We're done deleting.
	_deleting = false
