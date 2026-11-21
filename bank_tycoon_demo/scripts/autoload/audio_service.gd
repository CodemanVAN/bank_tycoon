extends Node

## Audio service managing BGM playback, 8-voice SFX pool, bus volume clamping, and user://settings.json persistence.

const SETTINGS_PATH: String = "user://settings.json"
const AUDIO_DIR: String = "res://assets/audio"
const VALID_BUSES: Array[String] = ["Master", "BGM", "SFX"]
const SFX_POOL_SIZE: int = 8

var _bus_volumes: Dictionary = {
	"Master": 1.0,
	"BGM": 0.8,
	"SFX": 1.0,
}
var _muted: bool = false
var _current_bgm_track: String = ""
var _bgm_player: AudioStreamPlayer = null
var _sfx_pool: Array[AudioStreamPlayer] = []
var _next_sfx_idx: int = 0
var _stream_cache: Dictionary = {}


func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BGMPlayer"
	_bgm_player.bus = &"BGM" if AudioServer.get_bus_index("BGM") >= 0 else &"Master"
	add_child(_bgm_player)

	var sfx_bus: StringName = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		p.bus = sfx_bus
		add_child(p)
		_sfx_pool.append(p)

	_load_persisted_audio_settings()
	for bus_name: String in VALID_BUSES:
		_apply_bus_volume_to_server(bus_name, float(_bus_volumes.get(bus_name, 1.0)))
	_apply_mute_to_server(_muted)


func _exit_tree() -> void:
	if _bgm_player != null:
		_bgm_player.stop()
		_bgm_player.stream = null
	for p in _sfx_pool:
		if p != null:
			p.stop()
			p.stream = null
	_stream_cache.clear()



func _resolve_audio_stream(track_or_sfx: String) -> AudioStream:
	if track_or_sfx.is_empty():
		return null
	var res_path: String = track_or_sfx
	if not res_path.begins_with("res://"):
		if not res_path.to_lower().ends_with(".wav"):
			res_path = "%s/%s.wav" % [AUDIO_DIR, track_or_sfx]
		else:
			res_path = "%s/%s" % [AUDIO_DIR, track_or_sfx]

	if _stream_cache.has(res_path):
		return _stream_cache[res_path] as AudioStream

	if not ResourceLoader.exists(res_path):
		return null

	var res: Resource = ResourceLoader.load(res_path)
	if res is AudioStream:
		_stream_cache[res_path] = res
		return res as AudioStream
	return null


func play_bgm(track_name: String = "bgm_starway_lobby", _fade_sec: float = 0.5) -> void:
	var stream: AudioStream = _resolve_audio_stream(track_name)
	if stream == null or _bgm_player == null:
		return
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			if wav.loop_end <= 0:
				var bytes_per_sample: int = 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
				var channels: int = 2 if wav.stereo else 1
				var frame_divisor: int = maxi(1, bytes_per_sample * channels)
				wav.loop_end = wav.data.size() / frame_divisor
	_current_bgm_track = track_name
	_bgm_player.stream = stream
	_bgm_player.play()


func stop_bgm(_fade_sec: float = 0.3) -> void:
	_current_bgm_track = ""
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()


func play_sfx(sfx_name: String) -> void:
	var stream: AudioStream = _resolve_audio_stream(sfx_name)
	if stream == null or _sfx_pool.is_empty():
		return

	var chosen: AudioStreamPlayer = null
	for i in range(_sfx_pool.size()):
		var idx: int = (_next_sfx_idx + i) % _sfx_pool.size()
		var candidate: AudioStreamPlayer = _sfx_pool[idx]
		if not candidate.playing:
			chosen = candidate
			_next_sfx_idx = (idx + 1) % _sfx_pool.size()
			break

	if chosen == null:
		chosen = _sfx_pool[_next_sfx_idx]
		_next_sfx_idx = (_next_sfx_idx + 1) % _sfx_pool.size()

	chosen.stream = stream
	chosen.play()


func set_bus_volume(bus_name: String, linear: float) -> void:
	if not VALID_BUSES.has(bus_name):
		return
	var clamped: float = clampf(linear, 0.0, 1.0)
	_bus_volumes[bus_name] = clamped
	_apply_bus_volume_to_server(bus_name, clamped)
	_persist_audio_settings()


func get_bus_volume(bus_name: String) -> float:
	if _bus_volumes.has(bus_name):
		return float(_bus_volumes[bus_name])
	return 1.0


func set_muted(muted: bool) -> void:
	_muted = muted
	_apply_mute_to_server(_muted)
	_persist_audio_settings()


func is_muted() -> bool:
	return _muted


func _apply_bus_volume_to_server(bus_name: String, clamped: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		if clamped <= 0.0001:
			AudioServer.set_bus_volume_db(bus_idx, -80.0)
		else:
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clamped))


func _apply_mute_to_server(muted: bool) -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, muted)


func _load_persisted_audio_settings() -> void:
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
	if d.has("master_volume"):
		_bus_volumes["Master"] = clampf(float(d["master_volume"]), 0.0, 1.0)
	if d.has("bgm_volume"):
		_bus_volumes["BGM"] = clampf(float(d["bgm_volume"]), 0.0, 1.0)
	if d.has("sfx_volume"):
		_bus_volumes["SFX"] = clampf(float(d["sfx_volume"]), 0.0, 1.0)
	if d.has("muted"):
		_muted = bool(d["muted"])


func _persist_audio_settings() -> void:
	var doc: Dictionary = {}
	if FileAccess.file_exists(SETTINGS_PATH):
		var f_in: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f_in != null:
			var parsed: Variant = JSON.parse_string(f_in.get_as_text())
			f_in.close()
			if parsed is Dictionary:
				doc = (parsed as Dictionary).duplicate(true)

	doc["master_volume"] = float(_bus_volumes.get("Master", 1.0))
	doc["bgm_volume"] = float(_bus_volumes.get("BGM", 0.8))
	doc["sfx_volume"] = float(_bus_volumes.get("SFX", 1.0))
	doc["muted"] = _muted

	var f_out: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f_out != null:
		f_out.store_string(JSON.stringify(doc, "  "))
		f_out.close()
