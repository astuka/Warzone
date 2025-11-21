extends Node

# Camera shake manager - handles screen shake effects for nearby explosions
# This should be attached to the player's camera or called from player

# Configuration
const SHAKE_RADIUS = 15.0 # Distance within which player feels shake
const SHAKE_AMOUNT = 0.3 # Maximum shake intensity (camera offset in units)
const SHAKE_DURATION = 0.3 # How long the shake lasts
const SHAKE_FREQUENCY = 30.0 # How fast the shake oscillates

# State
var shake_time_remaining: float = 0.0
var shake_intensity: float = 0.0
var original_position: Vector3 = Vector3.ZERO
var is_shaking: bool = false

func trigger_shake(explosion_position: Vector3, player_position: Vector3):
	"""Triggers a screen shake if the explosion is near the player"""
	var distance = player_position.distance_to(explosion_position)
	
	if distance <= SHAKE_RADIUS:
		# Calculate intensity based on distance (closer = stronger shake)
		var distance_factor = 1.0 - (distance / SHAKE_RADIUS)
		shake_intensity = SHAKE_AMOUNT * distance_factor
		shake_time_remaining = SHAKE_DURATION

func apply_shake(camera: Camera3D, delta: float):
	"""Apply shake effect to the camera - call this from player's _process"""
	if shake_time_remaining <= 0:
		if is_shaking:
			stop(camera)
		return
	
	# Store original position on first shake frame
	if not is_shaking:
		original_position = camera.position
		is_shaking = true
	
	# Calculate shake offset
	var shake_offset = Vector3(
		randf_range(-shake_intensity, shake_intensity),
		randf_range(-shake_intensity, shake_intensity),
		randf_range(-shake_intensity, shake_intensity)
	)
	
	# Apply shake with oscillation
	var shake_progress = 1.0 - (shake_time_remaining / SHAKE_DURATION)
	var decay_factor = 1.0 - shake_progress # Fade out over time
	camera.position = original_position + (shake_offset * decay_factor)
	
	# Update shake timer
	shake_time_remaining -= delta
	
	# Reset position when shake is done
	if shake_time_remaining <= 0:
		stop(camera)

func stop(camera: Camera3D):
	"""Forcefully stop the shake and reset camera position"""
	if is_shaking:
		camera.position = original_position
		is_shaking = false
	
	shake_time_remaining = 0.0
	shake_intensity = 0.0
