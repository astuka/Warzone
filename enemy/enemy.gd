extends CharacterBody3D
class_name Enemy

const MAX_HEALTH = 100
const MOVE_SPEED = 2.0

var health: int = MAX_HEALTH
var original_color: Color = Color.WHITE
var is_damaged: bool = false

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var damage_timer: Timer = $DamageTimer

func _ready():
	# Create a simple cube mesh for the enemy if not already set
	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
	
	if not mesh_instance.mesh:
		var box_mesh = BoxMesh.new()
		box_mesh.size = Vector3(1, 2, 1)
		mesh_instance.mesh = box_mesh
	
	# Create collision shape if not already set
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		add_child(collision_shape)
	
	if not collision_shape.shape:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(1, 2, 1)
		collision_shape.shape = box_shape
		collision_shape.position = Vector3(0, 1, 0)
	
	# Create material with original color
	if not mesh_instance.material_override:
		var material = StandardMaterial3D.new()
		material.albedo_color = original_color
		mesh_instance.material_override = material
	else:
		original_color = mesh_instance.material_override.albedo_color
	
	# Create damage timer if not already set
	if not damage_timer:
		damage_timer = Timer.new()
		damage_timer.wait_time = 0.2
		damage_timer.one_shot = true
		damage_timer.timeout.connect(_on_damage_timer_timeout)
		add_child(damage_timer)


func take_damage(amount: int):
	health -= amount
	health = max(0, health)
	
	# Turn red when damaged
	_turn_red()
	
	# Check if enemy should be deleted
	if health <= 0:
		queue_free()
		return
	
	# Reset color after a short time
	if damage_timer:
		damage_timer.start()


func _turn_red():
	if mesh_instance and mesh_instance.material_override:
		if mesh_instance.material_override is StandardMaterial3D:
			mesh_instance.material_override.albedo_color = Color.RED
		else:
			# If it's not a StandardMaterial3D, create a new one
			var material = StandardMaterial3D.new()
			material.albedo_color = Color.RED
			mesh_instance.material_override = material
	is_damaged = true


func _on_damage_timer_timeout():
	# Return to original color
	if mesh_instance and mesh_instance.material_override:
		if mesh_instance.material_override is StandardMaterial3D:
			mesh_instance.material_override.albedo_color = original_color
	is_damaged = false

