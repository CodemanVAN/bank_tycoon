extends Node

## M1 baseline stub for GameSession.
## M1 stub: Result/BankState parameters and returns are typed as Variant until M2 defines them;
## M3 will restore strict BankState/Result types and full lifecycle integration.

signal session_started(bank_state: Variant)
signal session_ended()
signal settings_changed(settings: Dictionary)

var bank_state: Variant = null
var is_active: bool = false
var minute_duration_sec: float = 0.25

var _settings: Dictionary = {
	"locale": "zh_CN",
	"minute_duration_sec": 0.25,
	"master_volume": 1.0,
	"bgm_volume": 0.8,
	"sfx_volume": 1.0,
	"muted": false,
}


func start_new_game(_bank_name: String = "Starway Bank", _world_seed: int = 20261121) -> Variant:
	is_active = true
	session_started.emit(bank_state)
	return bank_state


func load_from_slot(_slot_id: String) -> Variant:
	return null


func save_to_slot(_slot_id: String) -> Variant:
	return null


func end_session() -> void:
	is_active = false
	bank_state = null
	session_ended.emit()


func get_settings() -> Dictionary:
	return _settings.duplicate(true)


func update_settings(patch: Dictionary) -> void:
	for key: Variant in patch.keys():
		_settings[key] = patch[key]
	if _settings.has("minute_duration_sec"):
		minute_duration_sec = float(_settings["minute_duration_sec"])
	settings_changed.emit(get_settings())
