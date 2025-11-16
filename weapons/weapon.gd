extends Node
class_name Weapon

# Base weapon class that all weapons inherit from
signal weapon_fired

var damage: int = 0
var range_distance: float = 100.0
var fire_rate: float = 0.0  # Time between shots in seconds
var can_fire: bool = true

@onready var fire_timer: Timer = $FireTimer if has_node("FireTimer") else null

func _ready():
	if not fire_timer and fire_rate > 0:
		fire_timer = Timer.new()
		fire_timer.wait_time = fire_rate
		fire_timer.one_shot = true
		fire_timer.timeout.connect(_on_fire_timer_timeout)
		add_child(fire_timer)


func fire(raycast: RayCast3D, voxel_world: Node = null) -> bool:
	if not can_fire:
		return false
	
	# Don't fire if game is paused
	if get_tree().paused:
		return false
	
	# Ensure timer exists and is properly configured
	if not fire_timer:
		if fire_rate > 0:
			fire_timer = Timer.new()
			fire_timer.wait_time = fire_rate
			fire_timer.one_shot = true
			fire_timer.timeout.connect(_on_fire_timer_timeout)
			add_child(fire_timer)
	
	# Only start timer if it's not already running
	# If timer is running, we can't fire (already checked by can_fire)
	if fire_timer and fire_timer.is_stopped():
		# Ensure timer is properly configured
		if fire_timer.wait_time != fire_rate:
			fire_timer.wait_time = fire_rate
		fire_timer.start()
		can_fire = false
	
	weapon_fired.emit()
	return true


func _on_fire_timer_timeout():
	# Ensure can_fire is reset when timer fires
	can_fire = true
	# Stop the timer to ensure it's in a clean state
	if fire_timer:
		fire_timer.stop()
	
# Track if we were paused last frame to detect unpause
var _was_paused = false

# Safety mechanism: ensure can_fire is never stuck for too long
func _process(_delta):
	var is_paused = get_tree().paused
	
	# If we just unpaused and timer should have finished, reset can_fire
	if _was_paused and not is_paused:
		if not can_fire and fire_timer and fire_timer.is_stopped():
			# Timer finished while paused - reset it
			can_fire = true
	
	_was_paused = is_paused
	
	# Don't check timer state when paused (timers don't advance)
	if is_paused:
		return
	
	# Safety check: if timer is stopped but can_fire is false, reset it
	# This handles edge cases where the timer finished but the callback didn't fire
	if not can_fire and fire_timer:
		if fire_timer.is_stopped():
			# Timer stopped but can_fire is still false - reset it immediately
			can_fire = true
		elif fire_timer.time_left <= 0.001:  # Very small threshold to catch near-zero cases
			# Timer should have fired but didn't - reset it
			can_fire = true
			if fire_timer:
				fire_timer.stop()


# Override this in subclasses to handle projectile hits
func _on_projectile_hit(projectile: Projectile, target: Node, hit_position: Vector3):
	pass
