extends Control

@onready var render_distance_label = $RenderDistanceLabel
@onready var render_distance_slider = $RenderDistanceSlider
@onready var fog_checkbox: CheckBox = $FogCheckBox
@onready var master_volume_label = $MasterVolumeLabel
@onready var master_volume_slider = $MasterVolumeSlider
@onready var sfx_volume_label = $SFXVolumeLabel
@onready var sfx_volume_slider = $SFXVolumeSlider


func _ready():
	# Allow this UI to process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	render_distance_slider.value = Settings.render_distance
	render_distance_label.text = "Render distance: " + str(Settings.render_distance)
	fog_checkbox.button_pressed = Settings.fog_enabled
	
	# Volume sliders
	master_volume_slider.value = Settings.master_volume * 100
	master_volume_label.text = "Master Volume: " + str(int(Settings.master_volume * 100)) + "%"
	sfx_volume_slider.value = Settings.sfx_volume * 100
	sfx_volume_label.text = "SFX Volume: " + str(int(Settings.sfx_volume * 100)) + "%"


func _on_RenderDistanceSlider_value_changed(value):
	Settings.render_distance = value
	render_distance_label.text = "Render distance: " + str(value)
	Settings.save_settings()


func _on_FogCheckBox_pressed():
	Settings.fog_enabled = fog_checkbox.button_pressed
	Settings.save_settings()


func _on_MasterVolumeSlider_value_changed(value):
	var vol = value / 100.0
	Settings.master_volume = vol
	master_volume_label.text = "Master Volume: " + str(int(value)) + "%"
	AudioManager.set_master_volume(vol)
	Settings.save_settings()


func _on_SFXVolumeSlider_value_changed(value):
	var vol = value / 100.0
	Settings.sfx_volume = vol
	sfx_volume_label.text = "SFX Volume: " + str(int(value)) + "%"
	AudioManager.set_sfx_volume(vol)
	Settings.save_settings()
