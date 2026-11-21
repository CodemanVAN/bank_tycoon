extends Node

## Global session lifecycle and settings coordinator bridging SaveService, ContentRegistry, LocalizationService, and AudioService.

signal session_started(bank_state: BankState)
signal session_ended()
signal settings_changed(settings: Dictionary)

const SETTINGS_PATH: String = "user://settings.json"

var bank_state: BankState = null
var is_active: bool = false
var minute_duration_sec: float = 0.25

var _settings: Dictionary = {
	"locale": "zh_CN",
	"minute_duration_sec": 0.25,
	"master_volume": 1.0,
	"bgm_volume": 0.8,
	"sfx_volume": 1.0,
	"muted": false,
	"auto_pause_on_event": true,
}


func _ready() -> void:
	_load_settings_from_disk()


func start_new_game(bank_name: String = "Starway Bank", world_seed: int = 20261121) -> BankState:
	var state: BankState = BankState.create_starter_branch(bank_name, world_seed)
	if ContentRegistry != null and ContentRegistry.has_method("get_loaded_mod_dependencies"):
		state.mod_dependencies = ContentRegistry.get_loaded_mod_dependencies()
	bank_state = state
	is_active = true
	session_started.emit(bank_state)
	return bank_state


func save_to_slot(slot_id: String) -> Result:
	if not is_active or bank_state == null:
		return Result.fail(&"NO_ACTIVE_SESSION", "ERR_NO_ACTIVE_SESSION", {})
	if SaveService == null:
		return Result.fail(&"SAVE_WRITE_FAILED", "ERR_SAVE_WRITE_FAILED", {})
	return SaveService.save_slot(slot_id, bank_state, {
		"bank_name": bank_state.bank_name,
		"day": bank_state.current_day,
	})


func load_from_slot(slot_id: String) -> Result:
	if SaveService == null:
		return Result.fail(&"SAVE_NOT_FOUND", "ERR_SAVE_NOT_FOUND", {"slot_id": slot_id})
	var res: Result = SaveService.load_slot(slot_id)
	if not res.ok:
		return res
	var payload: Dictionary = res.data as Dictionary
	var restored: BankState = payload.get("bank_state") as BankState
	if restored == null:
		return Result.fail(&"SAVE_CORRUPTED", "ERR_SAVE_CORRUPTED", {"slot_id": slot_id})
	bank_state = restored
	is_active = true
	session_started.emit(bank_state)
	return res


func end_session() -> void:
	var was_active: bool = is_active
	is_active = false
	bank_state = null
	if was_active:
		session_ended.emit()


func get_most_recent_slot() -> String:
	if SaveService == null or not SaveService.has_method("list_slots"):
		return ""
	var slots: Array[Dictionary] = SaveService.list_slots()
	if slots.is_empty():
		return ""
	var best_slot: String = ""
	var best_time: String = ""
	for s in slots:
		var sid: String = str(s.get("slot_id", ""))
		var ts: String = str(s.get("saved_at_utc", ""))
		if best_slot == "" or ts > best_time or (ts == best_time and sid == "autosave"):
			best_slot = sid
			best_time = ts
	return best_slot


func get_settings() -> Dictionary:
	if LocalizationService != null and LocalizationService.has_method("get_locale"):
		_settings["locale"] = LocalizationService.get_locale()
	if AudioService != null:
		_settings["master_volume"] = AudioService.get_bus_volume("Master")
		_settings["bgm_volume"] = AudioService.get_bus_volume("BGM")
		_settings["sfx_volume"] = AudioService.get_bus_volume("SFX")
		_settings["muted"] = AudioService.is_muted()
	_settings["minute_duration_sec"] = minute_duration_sec
	return _settings.duplicate(true)


func update_settings(patch: Dictionary) -> void:
	for key: Variant in patch.keys():
		_settings[str(key)] = patch[key]

	if patch.has("minute_duration_sec"):
		minute_duration_sec = clampf(float(patch["minute_duration_sec"]), 0.05, 10.0)
		_settings["minute_duration_sec"] = minute_duration_sec

	if patch.has("locale") and LocalizationService != null:
		var target_locale: String = str(patch["locale"])
		if LocalizationService.get_locale() != target_locale:
			LocalizationService.set_locale(target_locale)
		_settings["locale"] = LocalizationService.get_locale()

	if AudioService != null:
		if patch.has("master_volume"):
			AudioService.set_bus_volume("Master", float(patch["master_volume"]))
			_settings["master_volume"] = AudioService.get_bus_volume("Master")
		if patch.has("bgm_volume"):
			AudioService.set_bus_volume("BGM", float(patch["bgm_volume"]))
			_settings["bgm_volume"] = AudioService.get_bus_volume("BGM")
		if patch.has("sfx_volume"):
			AudioService.set_bus_volume("SFX", float(patch["sfx_volume"]))
			_settings["sfx_volume"] = AudioService.get_bus_volume("SFX")
		if patch.has("muted"):
			AudioService.set_muted(bool(patch["muted"]))
			_settings["muted"] = AudioService.is_muted()

	_write_settings_to_disk()
	settings_changed.emit(get_settings())


func _load_settings_from_disk() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed as Dictionary
	for k: Variant in d.keys():
		_settings[str(k)] = d[k]
	if _settings.has("minute_duration_sec"):
		minute_duration_sec = clampf(float(_settings["minute_duration_sec"]), 0.05, 10.0)
	if _settings.has("locale") and LocalizationService != null:
		var lc: String = str(_settings["locale"])
		if LocalizationService.get_locale() != lc:
			LocalizationService.set_locale(lc)


func _write_settings_to_disk() -> void:
	var snap: Dictionary = get_settings()
	var f: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(snap, "  "))
		f.close()
