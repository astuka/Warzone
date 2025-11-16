extends Control
class_name HealthBar

@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel

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
	
	if not health_label:
		# Create health label if it doesn't exist
		health_label = Label.new()
		health_label.name = "HealthLabel"
		health_label.anchors_preset = Control.PRESET_TOP_LEFT
		health_label.offset_left = 20
		health_label.offset_top = 20
		health_label.offset_right = 320
		health_label.offset_bottom = 60
		health_label.text = "Health: 100/100"
		health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(health_label)

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
	
	if health_label:
		health_label.text = "Health: %d/%d" % [current, maximum]

