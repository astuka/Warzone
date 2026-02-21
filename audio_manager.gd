extends Node

var master_volume: float = 1.0
var sfx_volume: float = 1.0

var _sfx_bus_index: int = -1


func _ready():
	# Create SFX bus if it doesn't exist
	_sfx_bus_index = AudioServer.get_bus_index("SFX")
	if _sfx_bus_index == -1:
		AudioServer.add_bus()
		_sfx_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_sfx_bus_index, "SFX")
		AudioServer.set_bus_send(_sfx_bus_index, "Master")
	
	# Load saved volumes from settings
	if "master_volume" in Settings:
		master_volume = Settings.master_volume
	if "sfx_volume" in Settings:
		sfx_volume = Settings.sfx_volume
	
	_apply_volumes()


func set_master_volume(value: float):
	master_volume = clamp(value, 0.0, 1.0)
	_apply_volumes()


func set_sfx_volume(value: float):
	sfx_volume = clamp(value, 0.0, 1.0)
	_apply_volumes()


func _apply_volumes():
	# Master bus
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_volume))
		AudioServer.set_bus_mute(master_idx, master_volume <= 0.001)
	
	# SFX bus
	if _sfx_bus_index >= 0:
		AudioServer.set_bus_volume_db(_sfx_bus_index, linear_to_db(sfx_volume))
		AudioServer.set_bus_mute(_sfx_bus_index, sfx_volume <= 0.001)
