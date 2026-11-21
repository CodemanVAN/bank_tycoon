extends Node

## M1 baseline stub for AudioService.
## M3 will wire BGM crossfade/looping, SFX voice pool, and user://settings.json persistence.

var _bus_volumes: Dictionary = {
	"Master": 1.0,
	"BGM": 0.8,
	"SFX": 1.0,
}
var _muted: bool = false


func _ready() -> void:
	for bus_name: String in _bus_volumes.keys():
		set_bus_volume(bus_name, float(_bus_volumes[bus_name]))
	set_muted(_muted)


func play_bgm(_track_name: String = "bgm_starway_lobby", _fade_sec: float = 0.5) -> void:
	pass


func stop_bgm(_fade_sec: float = 0.3) -> void:
	pass


func play_sfx(_sfx_name: String) -> void:
	pass


func set_bus_volume(bus_name: String, linear: float) -> void:
	var clamped: float = clampf(linear, 0.0, 1.0)
	_bus_volumes[bus_name] = clamped
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(clamped, 0.0001)))


func get_bus_volume(bus_name: String) -> float:
	if _bus_volumes.has(bus_name):
		return float(_bus_volumes[bus_name])
	return 1.0


func set_muted(muted: bool) -> void:
	_muted = muted
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, _muted)


func is_muted() -> bool:
	return _muted
