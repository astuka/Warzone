extends Control
class_name HealthBar

@onready var health_bar: ProgressBar = $HealthBar


func _ready():
	if not health_bar:
		# Create health bar if it doesn't exist
		health_bar = ProgressBar.new()
		health_bar.name = "HealthBar"
		health_bar.anchors_preset = Control.PRESET_TOP_LEFT
		health_bar.offset_left = 20
		health_bar.offset_top = 20
		health_bar.offset_right = 320
		health_bar.offset_bottom = 60
		health_bar.max_value = 100
		health_bar.value = 100
		add_child(health_bar)
	

func set_health(current: int, maximum: int):
	if health_bar:
		health_bar.max_value = maximum
		health_bar.value = current
		# Change color based on health percentage
		var health_percent = float(current) / float(maximum)
		if health_percent > 0.6:
			health_bar.modulate = Color.GREEN
		elif health_percent > 0.3:
			health_bar.modulate = Color.YELLOW
		else:
			health_bar.modulate = Color.RED
