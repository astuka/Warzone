extends Area3D
class_name Projectile

# Base projectile class for bullets and rockets
var speed: float = 50.0
var damage: int = 0
var max_range: float = 100.0
var direction: Vector3 = Vector3.ZERO
var start_position: Vector3 = Vector3.ZERO
var owner_weapon: Weapon = null
var shooter: Node = null  # The NPC or player that fired this projectile

var has_hit: bool = false
var lifetime: float = 0.0  # Track how long projectile has existed
var max_lifetime: float = 5.0  # Reduced from 10 to 5 seconds for faster cleanup

@onready var collision_shape: CollisionShape3D = null
@onready var mesh_instance: MeshInstance3D = null

func _ready():
	# Set up collision detection
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Set collision layers - projectiles should detect static bodies (terrain) and enemies
	collision_layer = 0  # Projectiles don't need to be detected
	collision_mask = 0xFFFFF  # Detect everything
	
	# Set initial position only if not already set (to avoid range calculation bug)
	if start_position == Vector3.ZERO:
		start_position = global_position
	
	# Rotate to face direction
	if direction.length() > 0:
		look_at(global_position + direction, Vector3.UP)

func _physics_process(delta):
	if has_hit:
		return
	
	# Don't move if game is paused
	if get_tree().paused:
		return
	
	# Track lifetime and auto-cleanup if exceeded
	lifetime += delta
	if lifetime >= max_lifetime:
		queue_free()
		return
	
	# Use raycast to detect terrain collisions
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + direction * speed * delta)
	# Exclude ourselves (need RID, not the object)
	var self_rid = get_rid()
	if self_rid.is_valid():
		query.exclude = [self_rid]
	# Also exclude the shooter from the raycast
	if shooter and is_instance_valid(shooter):
		var shooter_rid = shooter.get_rid()
		if shooter_rid.is_valid():
			query.exclude.append(shooter_rid)
	
	var result = space_state.intersect_ray(query)
	if result:
		# Hit something - check if it's terrain (StaticBody3D) or an NPC
		var hit_body = result.get("collider")
		if hit_body:
			# Don't hit the shooter of the projectile
			if shooter and is_instance_valid(shooter) and hit_body == shooter:
				# Continue moving - don't hit ourselves
				pass
			# Don't hit same team
			elif _is_same_team(hit_body):
				# Continue moving - don't hit friendly
				pass
			else:
				# Hit something - stop and process hit
				_hit_target(hit_body, result.get("position", global_position))
				return
	
	# Move the projectile
	var movement = direction * speed * delta
	global_position += movement
	
	# Check if we've exceeded max range
	var distance_traveled = start_position.distance_to(global_position)
	if distance_traveled >= max_range:
		_hit_target(null, global_position)

func _is_same_team(target: Node) -> bool:
	if not shooter or not is_instance_valid(shooter) or not target:
		return false
	
	# If shooter is player, only allies are same team
	if shooter.name == "Player":
		return target is NPC and (target as NPC).npc_type == NPC.NPCType.ALLY
	
	# If shooter is NPC, check if target is same type
	if shooter is NPC and target is NPC:
		return (shooter as NPC).npc_type == (target as NPC).npc_type
	
	return false

func _on_body_entered(body):
	if has_hit:
		return
	
	# Don't hit the shooter of the projectile
	if shooter and is_instance_valid(shooter) and body == shooter:
		return
	
	# Don't hit same team
	if _is_same_team(body):
		return
	
	# Check collision
	var collision_point = global_position
	_hit_target(body, collision_point)

func _on_area_entered(area):
	if has_hit:
		return
	_hit_target(area, global_position)

func _hit_target(target, hit_position: Vector3):
	if has_hit:
		return
	
	has_hit = true
	
	# Call weapon's hit handler (check if weapon still exists)
	if owner_weapon and is_instance_valid(owner_weapon):
		owner_weapon._on_projectile_hit(self, target, hit_position)
	
	# Remove the projectile
	queue_free()

