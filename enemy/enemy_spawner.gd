extends Node3D
class_name EnemySpawner

const ALLY_SCENE = preload("res://npc/ally.tscn")
const ENEMY_SCENE = preload("res://npc/enemy_npc.tscn")
const SPAWN_DISTANCE = 20.0 # Distance from center to spawn NPCs
const MAX_ALLIES = 15 # Maximum number of allies at once
var max_enemies: int = 15 # Maximum number of enemies at once

# Map is split down the middle along X axis
# Negative X side = Ally territory
# Positive X side = Enemy territory
# Play area is 16x16 blocks (128x128 voxels with 8 block size)
const ALLY_SPAWN_X_MIN = -60.0
const ALLY_SPAWN_X_MAX = -10.0
const ENEMY_SPAWN_X_MIN = 10.0
const ENEMY_SPAWN_X_MAX = 60.0
const SPAWN_Z_MIN = -60.0
const SPAWN_Z_MAX = 60.0

var allies: Array[NPC] = []
var enemies: Array[NPC] = []
var spawn_timer: float = 0.0
var spawn_interval: float = 5.0 # Spawn a new NPC every 5 seconds

@onready var player = get_tree().get_first_node_in_group("player")
@onready var voxel_world = get_tree().get_first_node_in_group("voxel_world")

func _ready():
	# Add to group so player can find it
	add_to_group("enemy_spawner")
	
	if not player:
		# Try to find player in the scene
		player = get_tree().get_first_node_in_group("Player")
	if not player:
		# Fallback: find by name
		player = get_node_or_null("../Player")
	
	# Spawn initial enemies after scene is fully ready
	call_deferred("_spawn_initial_enemies")
	
	if GameManager:
		max_enemies = GameManager.current_max_enemies


func _spawn_initial_enemies():
	# Spawn initial enemies
	for i in range(3):
		spawn_enemy()
	# Spawn initial allies
	for i in range(2):
		spawn_ally()


func _process(delta):
	spawn_timer += delta
	
	# Remove dead NPCs from the arrays
	allies = allies.filter(func(ally): return is_instance_valid(ally))
	enemies = enemies.filter(func(enemy): return is_instance_valid(enemy))
	
	# Spawn new NPCs if needed
	if spawn_timer >= spawn_interval:
		# Spawn enemy if needed
		if enemies.size() < max_enemies:
			spawn_enemy()
		# Spawn ally if needed
		if allies.size() < MAX_ALLIES:
			spawn_ally()
		spawn_timer = 0.0


func spawn_enemy():
	var spawn_pos = _get_enemy_spawn_position()
	if spawn_pos == Vector3.ZERO:
		return
	
	# Create enemy instance
	var enemy_instance = ENEMY_SCENE.instantiate()
	enemy_instance.set_meta("spawn_position", spawn_pos)
	
	# Add to the world scene
	var world = get_tree().current_scene
	if not world:
		world = get_parent()
	
	world.add_child.call_deferred(enemy_instance)
	enemy_instance.tree_entered.connect(_on_npc_entered_tree.bind(enemy_instance, spawn_pos))
	
	enemies.append(enemy_instance)

func spawn_ally():
	var spawn_pos = _get_ally_spawn_position()
	if spawn_pos == Vector3.ZERO:
		return
	
	# Create ally instance
	var ally_instance = ALLY_SCENE.instantiate()
	ally_instance.set_meta("spawn_position", spawn_pos)
	
	# Add to the world scene
	var world = get_tree().current_scene
	if not world:
		world = get_parent()
	
	world.add_child.call_deferred(ally_instance)
	ally_instance.tree_entered.connect(_on_npc_entered_tree.bind(ally_instance, spawn_pos))
	
	allies.append(ally_instance)

func _get_ally_spawn_position() -> Vector3:
	# Spawn allies on negative X side
	var spawn_pos = Vector3(
		randf_range(ALLY_SPAWN_X_MIN, ALLY_SPAWN_X_MAX),
		10.0, # Start high enough to clear tall buildings
		randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX)
	)
	
	# Raycast down to find ground level or top of structure
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(spawn_pos, spawn_pos + Vector3.DOWN * 30)
	var result = space_state.intersect_ray(query)
	
	if result:
		spawn_pos = result.position + Vector3(0, 10, 0) # Place NPC on ground/structure
		return spawn_pos
	
	# If no ground found, spawn at default ground level
	return Vector3(spawn_pos.x, 1.5, spawn_pos.z)

func _get_enemy_spawn_position() -> Vector3:
	# Spawn enemies on positive X side
	var spawn_pos = Vector3(
		randf_range(ENEMY_SPAWN_X_MIN, ENEMY_SPAWN_X_MAX),
		20.0, # Start high enough to clear tall buildings
		randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX)
	)
	
	# Raycast down to find ground level or top of structure
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(spawn_pos, spawn_pos + Vector3.DOWN * 30)
	var result = space_state.intersect_ray(query)
	
	if result:
		spawn_pos = result.position + Vector3(0, 10, 0) # Place NPC on ground/structure
		return spawn_pos
	
	# If no ground found, spawn at default ground level
	return Vector3(spawn_pos.x, 10, spawn_pos.z)

func _on_npc_entered_tree(npc: Node, spawn_pos: Vector3):
	# Set position once NPC is in the tree
	if npc and is_instance_valid(npc) and npc.is_inside_tree():
		npc.global_position = spawn_pos
		if npc.has_meta("spawn_position"):
			npc.remove_meta("spawn_position")
