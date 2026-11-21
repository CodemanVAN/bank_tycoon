extends RefCounted

## Opaque-box E2E test harness for Starway Bank / Bank Tycoon.
## Dynamically resolves PROJECT.md interface contracts without preload() or
## compile-time class_name dependencies on unbuilt M2-M6 modules.

const AUTOLOAD_NAMES: Array[String] = [
	"LocalizationService",
	"ContentRegistry",
	"AudioService",
	"SaveService",
	"GameSession",
]

const CANONICAL_ACCOUNTS: Array[StringName] = [
	&"cash_reserves",
	&"loan_principal_outstanding",
	&"customer_deposits",
	&"equity_capital",
	&"retained_earnings",
	&"loan_interest_income",
	&"fee_income",
	&"deposit_interest_expense",
	&"operating_expense",
	&"credit_loss_expense",
	&"event_expense",
]

const SAVE_SLOT_PREFIX: String = "__e2e_test_"
const TEMP_MODS_ROOT: String = "user://__e2e_mods"

var root_tree: SceneTree = null
var _assertions: int = 0
var _failures: Array[String] = []
var _temp_nodes: Array[Node] = []
var _temp_save_slots: Array[String] = []
var _temp_mod_dirs: Array[String] = []
var _touched_mods: bool = false
var _touched_session: bool = false

var _snapshot_taken: bool = false
var _snap_files: Dictionary = {}
var _snap_locale: String = ""
var _snap_audio_volumes: Dictionary = {}
var _snap_audio_muted: bool = false
var _snap_session_settings: Dictionary = {}

const STANDARD_SAVE_SLOTS: Array[String] = [
	"autosave",
	"slot_01",
	"slot_02",
	"slot_03",
]

const SNAPSHOT_FILES: Array[String] = [
	"user://saves/autosave.json",
	"user://saves/autosave.bak",
	"user://saves/slot_01.json",
	"user://saves/slot_01.bak",
	"user://saves/slot_02.json",
	"user://saves/slot_02.bak",
	"user://saves/slot_03.json",
	"user://saves/slot_03.bak",
	"user://settings.json",
]


func _init(tree: SceneTree = null) -> void:
	root_tree = tree


func snapshot_environment() -> void:
	if _snapshot_taken:
		return
	_snapshot_taken = true
	_snap_files.clear()
	for fpath in SNAPSHOT_FILES:
		if FileAccess.file_exists(fpath):
			_snap_files[fpath] = FileAccess.get_file_as_bytes(fpath)
	var loc: Node = _try_get_autoload("LocalizationService")
	if loc != null and loc.has_method("get_locale"):
		_snap_locale = str(loc.call("get_locale"))
	var audio: Node = _try_get_autoload("AudioService")
	if audio != null:
		_snap_audio_volumes.clear()
		if audio.has_method("get_bus_volume"):
			for bus_name in ["Master", "BGM", "SFX"]:
				_snap_audio_volumes[bus_name] = float(audio.call("get_bus_volume", bus_name))
		if audio.has_method("is_muted"):
			_snap_audio_muted = bool(audio.call("is_muted"))
	var sess: Node = _try_get_autoload("GameSession")
	if sess != null:
		if sess.has_method("get_settings"):
			var raw_set: Variant = sess.call("get_settings")
			if raw_set is Dictionary:
				_snap_session_settings = (raw_set as Dictionary).duplicate(true)
	_purge_e2e_save_artifacts()
	remove_dir_recursive(TEMP_MODS_ROOT)


func restore_environment() -> void:
	cleanup_temp_nodes()
	_purge_e2e_save_artifacts()
	_purge_standard_save_slots()
	remove_dir_recursive(TEMP_MODS_ROOT)

	var sess: Node = _try_get_autoload("GameSession")
	if sess != null and sess.has_method("end_session"):
		if bool(sess.get("is_active")):
			sess.call("end_session")

	var loc: Node = _try_get_autoload("LocalizationService")
	if loc != null:
		if loc.has_method("clear_mod_translations"):
			loc.call("clear_mod_translations")
		if _snap_locale != "" and loc.has_method("set_locale"):
			loc.call("set_locale", _snap_locale)

	var reg: Node = _try_get_autoload("ContentRegistry")
	if reg != null and reg.has_method("reload_all"):
		reg.call("reload_all", "user://mods")

	if _snapshot_taken:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
		for fpath in SNAPSHOT_FILES:
			if _snap_files.has(fpath):
				_write_bytes_file(fpath, _snap_files[fpath] as PackedByteArray)
			else:
				_remove_file_if_exists(fpath)

	_restore_audio_and_session_state()


func _restore_audio_and_session_state() -> void:
	var sess: Node = _try_get_autoload("GameSession")
	if sess != null:
		if not _snap_session_settings.is_empty() and sess.has_method("update_settings"):
			sess.call("update_settings", _snap_session_settings.duplicate(true))
		elif has_prop(sess, "minute_duration_sec"):
			sess.set("minute_duration_sec", 0.25)

	var audio: Node = _try_get_autoload("AudioService")
	if audio != null:
		if audio.has_method("stop_bgm"):
			audio.call("stop_bgm", 0.0)
		if audio.has_method("set_muted"):
			audio.call("set_muted", _snap_audio_muted)
		if audio.has_method("set_bus_volume"):
			for bus_name in ["Master", "BGM", "SFX"]:
				var default_vol: float = 0.8 if bus_name == "BGM" else 1.0
				var target_vol: float = float(_snap_audio_volumes.get(bus_name, default_vol))
				audio.call("set_bus_volume", bus_name, target_vol)


func _purge_standard_save_slots() -> void:
	var save_svc: Node = _try_get_autoload("SaveService")
	for slot_id in STANDARD_SAVE_SLOTS:
		if save_svc != null and save_svc.has_method("delete_slot"):
			save_svc.call("delete_slot", slot_id)
		_remove_file_if_exists("user://saves/%s.json" % slot_id)
		_remove_file_if_exists("user://saves/%s.bak" % slot_id)
		_remove_file_if_exists("user://saves/%s.tmp" % slot_id)


func run_test(tier: int, test_id: String, fn: Callable) -> Dictionary:
	_assertions = 0
	_failures.clear()
	_temp_nodes.clear()
	_temp_save_slots.clear()
	_temp_mod_dirs.clear()
	_touched_mods = false
	_touched_session = false

	fn.call(self)

	_cleanup_per_test()

	if _assertions == 0 and _failures.is_empty():
		_failures.append("Zero assertions executed (zero-false-pass guard)")

	var passed: bool = _failures.is_empty()
	var reason: String = "; ".join(_failures)
	if passed:
		print("[E2E] Tier %d | %s | PASS" % [tier, test_id])
	else:
		print("[E2E] Tier %d | %s | FAIL: %s" % [tier, test_id, reason])

	return {
		"tier": "tier%d" % tier,
		"test": test_id,
		"passed": passed,
		"reason": reason,
		"assertions": _assertions,
	}


func _cleanup_per_test() -> void:
	cleanup_temp_nodes()
	if _touched_session:
		var sess: Node = _try_get_autoload("GameSession")
		if sess != null and sess.has_method("end_session") and bool(sess.get("is_active")):
			sess.call("end_session")

	var save_svc: Node = _try_get_autoload("SaveService")
	for slot_id in _temp_save_slots:
		if save_svc != null and save_svc.has_method("delete_slot"):
			save_svc.call("delete_slot", slot_id)
		_remove_file_if_exists("user://saves/%s.json" % slot_id)
		_remove_file_if_exists("user://saves/%s.bak" % slot_id)
		_remove_file_if_exists("user://saves/%s.tmp" % slot_id)

	_purge_e2e_save_artifacts()
	_purge_standard_save_slots()
	_remove_file_if_exists("user://settings.json")

	for d in _temp_mod_dirs:
		remove_dir_recursive(d)

	var loc: Node = _try_get_autoload("LocalizationService")
	if _touched_mods:
		if loc != null and loc.has_method("clear_mod_translations"):
			loc.call("clear_mod_translations")
		var reg: Node = _try_get_autoload("ContentRegistry")
		if reg != null and reg.has_method("reload_all"):
			var empty_dir: String = create_temp_mod_dir("__clean_empty")
			reg.call("reload_all", empty_dir)
			remove_dir_recursive(empty_dir)

	if loc != null and _snap_locale != "" and loc.has_method("set_locale"):
		loc.call("set_locale", _snap_locale)

	_restore_audio_and_session_state()


func _purge_e2e_save_artifacts() -> void:
	var saves_abs: String = ProjectSettings.globalize_path("user://saves")
	if not DirAccess.dir_exists_absolute(saves_abs):
		return
	var da: DirAccess = DirAccess.open(saves_abs)
	if da == null:
		return
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.begins_with(SAVE_SLOT_PREFIX):
			da.remove(fname)
		fname = da.get_next()
	da.list_dir_end()


# ---------------------------------------------------------------------------
# Dynamic Contract Loading & Reflection
# ---------------------------------------------------------------------------

func load_script(res_path: String) -> GDScript:
	_assertions += 1
	if not ResourceLoader.exists(res_path):
		_failures.append("Missing required script: %s" % res_path)
		return null
	var res: Resource = ResourceLoader.load(res_path)
	if res == null or not (res is GDScript):
		_failures.append("Failed to load GDScript: %s" % res_path)
		return null
	return res as GDScript


func instantiate_script(res_path: String, args: Array = []) -> Variant:
	var script: GDScript = load_script(res_path)
	if script == null:
		return null
	var inst: Variant = _new_from_script(script, args)
	_assertions += 1
	if inst == null:
		_failures.append("Failed to instantiate script: %s" % res_path)
		return null
	if inst is Node:
		_temp_nodes.append(inst as Node)
	return inst


func _new_from_script(script: GDScript, args: Array) -> Variant:
	match args.size():
		0:
			return script.new()
		1:
			return script.new(args[0])
		2:
			return script.new(args[0], args[1])
		3:
			return script.new(args[0], args[1], args[2])
		4:
			return script.new(args[0], args[1], args[2], args[3])
		5:
			return script.new(args[0], args[1], args[2], args[3], args[4])
		_:
			return script.new()


func load_scene(res_path: String) -> PackedScene:
	_assertions += 1
	if not ResourceLoader.exists(res_path):
		_failures.append("Missing required scene: %s" % res_path)
		return null
	var res: Resource = ResourceLoader.load(res_path)
	if res == null or not (res is PackedScene):
		_failures.append("Resource is not a PackedScene: %s" % res_path)
		return null
	return res as PackedScene


func instantiate_scene(res_path: String, mount: bool = false) -> Node:
	var packed: PackedScene = load_scene(res_path)
	if packed == null:
		return null
	var node: Node = packed.instantiate()
	_assertions += 1
	if node == null:
		_failures.append("PackedScene.instantiate() returned null: %s" % res_path)
		return null
	if mount:
		mount_temp_node(node)
	else:
		_temp_nodes.append(node)
	return node


func mount_temp_node(node: Node) -> Node:
	if node == null:
		return null
	if not _temp_nodes.has(node):
		_temp_nodes.append(node)
	if root_tree != null and root_tree.root != null and node.get_parent() == null:
		root_tree.root.add_child(node)
	return node


func cleanup_temp_nodes() -> void:
	for i in range(_temp_nodes.size() - 1, -1, -1):
		var n: Node = _temp_nodes[i]
		if is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_temp_nodes.clear()


func _try_get_autoload(autoload_name: String) -> Node:
	if root_tree == null or root_tree.root == null:
		return null
	return root_tree.root.get_node_or_null(NodePath(autoload_name))


func get_autoload(autoload_name: String) -> Node:
	_assertions += 1
	if root_tree == null or root_tree.root == null:
		_failures.append("SceneTree unavailable for Autoload lookup: %s" % autoload_name)
		return null
	var node: Node = root_tree.root.get_node_or_null(NodePath(autoload_name))
	if node == null:
		_failures.append("Missing Autoload /root/%s" % autoload_name)
		return null
	return node


func require_method(obj: Variant, method_name: String, label: String = "") -> bool:
	_assertions += 1
	if obj == null or not (obj is Object):
		_failures.append("Cannot check method %s on null/non-Object (%s)" % [method_name, label])
		return false
	var target: Object = obj as Object
	if not target.has_method(method_name):
		var ctx: String = label if label != "" else str(target)
		_failures.append("Missing required method '%s' on %s" % [method_name, ctx])
		return false
	return true


func require_signal(obj: Variant, signal_name: String, label: String = "") -> bool:
	_assertions += 1
	if obj == null or not (obj is Object):
		_failures.append("Cannot check signal %s on null/non-Object (%s)" % [signal_name, label])
		return false
	var target: Object = obj as Object
	if not target.has_signal(signal_name):
		var ctx: String = label if label != "" else str(target)
		_failures.append("Missing required signal '%s' on %s" % [signal_name, ctx])
		return false
	return true


func require_property(obj: Variant, prop_name: String, label: String = "") -> bool:
	_assertions += 1
	if obj == null or not (obj is Object):
		_failures.append("Cannot check property %s on null/non-Object (%s)" % [prop_name, label])
		return false
	var target: Object = obj as Object
	for prop in target.get_property_list():
		if str(prop.get("name", "")) == prop_name:
			return true
	var ctx: String = label if label != "" else str(target)
	_failures.append("Missing required property '%s' on %s" % [prop_name, ctx])
	return false


func has_prop(obj: Variant, prop_name: String) -> bool:
	if obj == null or not (obj is Object):
		return false
	for prop in (obj as Object).get_property_list():
		if str(prop.get("name", "")) == prop_name:
			return true
	return false


func has_method_sig(obj: Variant, method_name: String) -> Dictionary:
	if obj == null or not (obj is Object):
		return {}
	for m in (obj as Object).get_method_list():
		if str(m.get("name", "")) == method_name:
			return m
	return {}


# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

func fail_test(reason: String) -> void:
	_assertions += 1
	_failures.append(reason)


func assert_true(cond: bool, msg: String) -> bool:
	_assertions += 1
	if not cond:
		_failures.append(msg)
		return false
	return true


func assert_false(cond: bool, msg: String) -> bool:
	_assertions += 1
	if cond:
		_failures.append(msg)
		return false
	return true


func assert_not_null(val: Variant, msg: String) -> bool:
	_assertions += 1
	if val == null:
		_failures.append(msg)
		return false
	return true


func assert_eq(actual: Variant, expected: Variant, msg: String) -> bool:
	_assertions += 1
	if actual != expected:
		_failures.append("%s (expected=%s, actual=%s)" % [msg, str(expected), str(actual)])
		return false
	return true


func assert_ne(actual: Variant, unexpected: Variant, msg: String) -> bool:
	_assertions += 1
	if actual == unexpected:
		_failures.append("%s (unexpected=%s)" % [msg, str(unexpected)])
		return false
	return true


func assert_gt(actual: Variant, threshold: Variant, msg: String) -> bool:
	_assertions += 1
	if not (actual > threshold):
		_failures.append("%s (expected > %s, actual=%s)" % [msg, str(threshold), str(actual)])
		return false
	return true


func assert_ge(actual: Variant, threshold: Variant, msg: String) -> bool:
	_assertions += 1
	if not (actual >= threshold):
		_failures.append("%s (expected >= %s, actual=%s)" % [msg, str(threshold), str(actual)])
		return false
	return true


func assert_lt(actual: Variant, threshold: Variant, msg: String) -> bool:
	_assertions += 1
	if not (actual < threshold):
		_failures.append("%s (expected < %s, actual=%s)" % [msg, str(threshold), str(actual)])
		return false
	return true


func assert_le(actual: Variant, threshold: Variant, msg: String) -> bool:
	_assertions += 1
	if not (actual <= threshold):
		_failures.append("%s (expected <= %s, actual=%s)" % [msg, str(threshold), str(actual)])
		return false
	return true


func assert_near(actual: float, expected: float, eps: float, msg: String) -> bool:
	_assertions += 1
	if absf(actual - expected) > eps:
		_failures.append("%s (expected=%f +- %f, actual=%f)" % [msg, expected, eps, actual])
		return false
	return true


func assert_has(container: Variant, key: Variant, msg: String) -> bool:
	_assertions += 1
	var found: bool = false
	if container is Dictionary:
		found = (container as Dictionary).has(key)
	elif container is Array:
		found = (container as Array).has(key)
	if not found:
		_failures.append("%s (missing key/item=%s)" % [msg, str(key)])
		return false
	return true


func assert_result_ok(res: Variant, ctx: String) -> bool:
	_assertions += 1
	if res == null or not (res is Object):
		_failures.append("%s: Result is null or non-Object" % ctx)
		return false
	var ok_val: Variant = (res as Object).get("ok")
	if typeof(ok_val) != TYPE_BOOL or not bool(ok_val):
		var ec: String = str((res as Object).get("error_code"))
		var ek: String = str((res as Object).get("error_key"))
		_failures.append("%s: expected Result.ok==true, got ok=%s (error_code=%s, error_key=%s)" % [ctx, str(ok_val), ec, ek])
		return false
	return true


func assert_result_err(res: Variant, ctx: String) -> bool:
	_assertions += 1
	if res == null or not (res is Object):
		_failures.append("%s: Result is null or non-Object" % ctx)
		return false
	var ok_val: Variant = (res as Object).get("ok")
	if typeof(ok_val) != TYPE_BOOL or bool(ok_val):
		_failures.append("%s: expected Result.ok==false, got ok=%s" % [ctx, str(ok_val)])
		return false
	var ec: String = str((res as Object).get("error_code"))
	var ek: String = str((res as Object).get("error_key"))
	if ec == "" and ek == "":
		_failures.append("%s: failed Result must provide non-empty error_code or error_key" % ctx)
		return false
	return true


# ---------------------------------------------------------------------------
# File / JSON / ZIP / WAV / Regex Utilities
# ---------------------------------------------------------------------------

func get_project_root_abs() -> String:
	return ProjectSettings.globalize_path("res://").rstrip("/\\")


func get_repo_root_abs() -> String:
	return get_project_root_abs().get_base_dir()


func register_temp_slot(short_name: String) -> String:
	var slot_id: String = SAVE_SLOT_PREFIX + short_name
	if not _temp_save_slots.has(slot_id):
		_temp_save_slots.append(slot_id)
	return slot_id


func mark_mods_touched() -> void:
	_touched_mods = true


func mark_session_touched() -> void:
	_touched_session = true


func create_temp_mod_dir(case_id: String) -> String:
	var dir_path: String = "%s/%s" % [TEMP_MODS_ROOT, case_id]
	var abs_path: String = ProjectSettings.globalize_path(dir_path)
	DirAccess.make_dir_recursive_absolute(abs_path)
	if not _temp_mod_dirs.has(dir_path):
		_temp_mod_dirs.append(dir_path)
	_touched_mods = true
	return dir_path


func read_text_file(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt


func write_text_file(path: String, content: String) -> bool:
	var parent_abs: String = ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(parent_abs)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(content)
	f.close()
	return true


func _write_bytes_file(path: String, data: PackedByteArray) -> bool:
	var parent_abs: String = ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(parent_abs)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	f.close()
	return true


func _remove_file_if_exists(path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


func read_json_file(path: String) -> Variant:
	var txt: String = read_text_file(path)
	if txt == "":
		return null
	var json := JSON.new()
	if json.parse(txt) != OK:
		return null
	return json.data


func write_json_file(path: String, data: Variant) -> bool:
	return write_text_file(path, JSON.stringify(data, "  "))


func copy_file(src_path: String, dst_path: String) -> bool:
	if not FileAccess.file_exists(src_path):
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src_path)
	return _write_bytes_file(dst_path, bytes)


func copy_dir_recursive(src_dir: String, dst_dir: String) -> bool:
	var src_abs: String = ProjectSettings.globalize_path(src_dir)
	var dst_abs: String = ProjectSettings.globalize_path(dst_dir)
	if not DirAccess.dir_exists_absolute(src_abs):
		return false
	DirAccess.make_dir_recursive_absolute(dst_abs)
	var da: DirAccess = DirAccess.open(src_abs)
	if da == null:
		return false
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var s_sub: String = src_abs.path_join(entry)
			var d_sub: String = dst_abs.path_join(entry)
			if da.current_is_dir():
				if not copy_dir_recursive(s_sub, d_sub):
					da.list_dir_end()
					return false
			else:
				if not copy_file(s_sub, d_sub):
					da.list_dir_end()
					return false
		entry = da.get_next()
	da.list_dir_end()
	return true


func remove_dir_recursive(dir_path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var da: DirAccess = DirAccess.open(abs_path)
	if da == null:
		return
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var sub: String = abs_path.path_join(entry)
			if da.current_is_dir():
				remove_dir_recursive(sub)
			else:
				DirAccess.remove_absolute(sub)
		entry = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(abs_path)


func find_files_recursive(dir_path: String, ext_filter: String = "") -> Array[String]:
	var out: Array[String] = []
	var abs_path: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_path):
		return out
	var da: DirAccess = DirAccess.open(abs_path)
	if da == null:
		return out
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var sub: String = abs_path.path_join(entry)
			if da.current_is_dir():
				out.append_array(find_files_recursive(sub, ext_filter))
			else:
				if ext_filter == "" or entry.to_lower().ends_with(ext_filter.to_lower()):
					out.append(sub)
		entry = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func build_zip_from_entries(zip_path: String, entries: Dictionary) -> bool:
	var abs_zip: String = ProjectSettings.globalize_path(zip_path)
	DirAccess.make_dir_recursive_absolute(abs_zip.get_base_dir())
	var packer := ZIPPacker.new()
	if packer.open(abs_zip) != OK:
		return false
	for key in entries.keys():
		var entry_name: String = str(key)
		var val: Variant = entries[key]
		var bytes: PackedByteArray
		if val is PackedByteArray:
			bytes = val
		elif val is String:
			bytes = (val as String).to_utf8_buffer()
		else:
			bytes = JSON.stringify(val, "  ").to_utf8_buffer()
		if packer.start_file(entry_name) != OK:
			packer.close()
			return false
		if packer.write_file(bytes) != OK:
			packer.close()
			return false
		if packer.close_file() != OK:
			packer.close()
			return false
	packer.close()
	return true


func build_zip_from_dir(zip_path: String, src_dir: String) -> bool:
	var src_abs: String = ProjectSettings.globalize_path(src_dir).rstrip("/\\")
	var files: Array[String] = find_files_recursive(src_abs)
	var entries: Dictionary = {}
	for fpath in files:
		var rel: String = fpath.substr(src_abs.length() + 1).replace("\\", "/")
		entries[rel] = FileAccess.get_file_as_bytes(fpath)
	return build_zip_from_entries(zip_path, entries)


func parse_wav_header(file_path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file_path)
	if bytes.size() < 44:
		return {"valid": false, "reason": "File smaller than 44 bytes"}
	var riff: String = bytes.slice(0, 4).get_string_from_ascii()
	var wave: String = bytes.slice(8, 12).get_string_from_ascii()
	if riff != "RIFF" or wave != "WAVE":
		return {"valid": false, "reason": "Missing RIFF/WAVE header"}
	var offset: int = 12
	var audio_format: int = 0
	var channels: int = 0
	var sample_rate: int = 0
	var bits_per_sample: int = 0
	var data_bytes: int = 0
	var found_fmt: bool = false
	var found_data: bool = false
	while offset + 8 <= bytes.size():
		var chunk_id: String = bytes.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size: int = bytes.decode_u32(offset + 4)
		var chunk_data_start: int = offset + 8
		if chunk_id == "fmt " and chunk_data_start + 16 <= bytes.size():
			found_fmt = true
			audio_format = bytes.decode_u16(chunk_data_start)
			channels = bytes.decode_u16(chunk_data_start + 2)
			sample_rate = bytes.decode_u32(chunk_data_start + 4)
			bits_per_sample = bytes.decode_u16(chunk_data_start + 14)
		elif chunk_id == "data":
			found_data = true
			data_bytes = chunk_size
		var step: int = 8 + chunk_size + (chunk_size % 2)
		if step <= 8:
			break
		offset += step
	return {
		"valid": found_fmt and found_data,
		"audio_format": audio_format,
		"channels": channels,
		"sample_rate": sample_rate,
		"bits_per_sample": bits_per_sample,
		"data_bytes": data_bytes,
	}


func validate_content_id(id_str: String) -> bool:
	var rx := RegEx.new()
	rx.compile("^[a-z0-9_.-]+:[a-z0-9_.-]+$")
	return rx.search(id_str) != null


func validate_semver(ver_str: String) -> bool:
	var rx := RegEx.new()
	rx.compile("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	return rx.search(ver_str) != null


# ---------------------------------------------------------------------------
# Opaque-Box Gameplay & Contract Helpers
# ---------------------------------------------------------------------------

func build_content_defs(content_registry: Variant) -> Dictionary:
	if content_registry == null or not (content_registry is Object):
		return {}
	var reg: Object = content_registry as Object
	if not reg.has_method("get_all_by_type"):
		return {}
	return {
		"departments": _query_registry_list(reg, &"department", &"departments"),
		"policies": _query_registry_list(reg, &"policy", &"policies"),
		"events": _query_registry_list(reg, &"event", &"events"),
		"traits": _query_registry_list(reg, &"trait", &"traits"),
		"customers": _query_registry_list(reg, &"customer", &"customers"),
	}


func _query_registry_list(reg: Object, singular: StringName, plural: StringName) -> Array:
	var res: Variant = reg.call("get_all_by_type", singular)
	if res is Array and not (res as Array).is_empty():
		return res as Array
	var res2: Variant = reg.call("get_all_by_type", plural)
	if res2 is Array:
		return res2 as Array
	return []


func start_session_and_host(bank_name: String, world_seed: int, mods_root: String = "") -> Dictionary:
	var reg: Node = get_autoload("ContentRegistry")
	var sess: Node = get_autoload("GameSession")
	if reg == null or sess == null:
		return {}
	if not require_method(reg, "reload_all", "ContentRegistry"):
		return {}
	if not require_method(sess, "start_new_game", "GameSession"):
		return {}

	if mods_root != "":
		mark_mods_touched()
		reg.call("reload_all", mods_root)
	else:
		var empty_mods: String = create_temp_mod_dir("__baseline_empty")
		reg.call("reload_all", empty_mods)

	mark_session_touched()
	var bank_state: Variant = sess.call("start_new_game", bank_name, world_seed)
	if not assert_not_null(bank_state, "GameSession.start_new_game returned null"):
		return {}

	var sim_host: Variant = instantiate_script("res://scripts/app/simulation_host.gd")
	if sim_host == null:
		return {}
	if sim_host is Node:
		mount_temp_node(sim_host as Node)

	if not require_method(sim_host, "bind_session", "SimulationHost"):
		return {}
	if not require_method(sim_host, "step_simulation", "SimulationHost"):
		return {}

	var defs: Dictionary = build_content_defs(reg)
	sim_host.call("bind_session", bank_state, defs)

	var cmd: Variant = (sim_host as Object).get("command_service")
	var event_bus: Variant = (sim_host as Object).get("event_bus")
	if not assert_not_null(cmd, "SimulationHost.command_service is null"):
		return {}
	if not assert_not_null(event_bus, "SimulationHost.event_bus is null"):
		return {}

	return {
		"registry": reg,
		"session": sess,
		"bank_state": bank_state,
		"sim_host": sim_host,
		"cmd": cmd,
		"event_bus": event_bus,
		"defs": defs,
	}


func get_minute_duration(session: Variant) -> float:
	if session != null and (session is Object):
		var v: Variant = (session as Object).get("minute_duration_sec")
		if v is float or v is int:
			var f: float = float(v)
			if f > 0.0:
				return f
	return 0.25


func step_minutes(sim_host: Variant, minutes: int, minute_dur: float = 0.25, speed: int = 1) -> void:
	if sim_host == null or not (sim_host is Object):
		return
	var host: Object = sim_host as Object
	var sp: int = maxi(1, speed)
	var step_delta: float = minute_dur / float(sp)
	for _i in range(minutes):
		host.call("step_simulation", step_delta)


func invoke_finance_amount_op(
	finance_obj: Variant,
	method_name: String,
	bank_state: Variant,
	amount_minor: int,
	day: int = 1,
	minute: int = 540,
	ref_id: String = "e2e_ref"
) -> Variant:
	if not require_method(finance_obj, method_name, "FinanceEngine"):
		return null
	var sig: Dictionary = has_method_sig(finance_obj, method_name)
	var args_meta: Array = sig.get("args", [])
	var def_meta: Array = sig.get("default_args", [])
	var max_args: int = args_meta.size()
	var min_args: int = max_args - def_meta.size()
	var target: Object = finance_obj as Object

	if max_args >= 5 or (min_args <= 5 and max_args == 5):
		return target.call(method_name, bank_state, amount_minor, day, minute, ref_id)
	if max_args == 4:
		return target.call(method_name, bank_state, amount_minor, day, ref_id)
	if max_args == 3:
		return target.call(method_name, bank_state, amount_minor, ref_id)
	if max_args == 2:
		return target.call(method_name, bank_state, amount_minor)
	return target.call(method_name, bank_state, amount_minor, day, minute, ref_id)


func get_ledger_balance(bank_state: Variant, account: StringName) -> int:
	if bank_state == null or not (bank_state is Object):
		return 0
	var ledger: Variant = (bank_state as Object).get("ledger")
	if ledger == null or not (ledger is Object):
		return 0
	return int((ledger as Object).call("get_balance", account))


func get_balance_sheet(bank_state: Variant) -> Dictionary:
	if bank_state == null or not (bank_state is Object):
		return {}
	var ledger: Variant = (bank_state as Object).get("ledger")
	if ledger == null or not (ledger is Object):
		return {}
	var snap: Variant = (ledger as Object).call("get_balance_sheet_snapshot")
	return snap as Dictionary if snap is Dictionary else {}


func get_first_station_id(bank_state: Variant) -> String:
	if bank_state == null or not (bank_state is Object):
		return ""
	var stations: Variant = (bank_state as Object).get("stations")
	if stations is Dictionary and not (stations as Dictionary).is_empty():
		var keys: Array = (stations as Dictionary).keys()
		keys.sort()
		return str(keys[0])
	return ""


func get_station_ids(bank_state: Variant) -> Array[String]:
	var out: Array[String] = []
	if bank_state == null or not (bank_state is Object):
		return out
	var stations: Variant = (bank_state as Object).get("stations")
	if stations is Dictionary:
		for k in (stations as Dictionary).keys():
			out.append(str(k))
	out.sort()
	return out


func get_employee_ids(bank_state: Variant) -> Array[String]:
	var out: Array[String] = []
	if bank_state == null or not (bank_state is Object):
		return out
	var emps: Variant = (bank_state as Object).get("employees")
	if emps is Dictionary:
		for k in (emps as Dictionary).keys():
			out.append(str(k))
	out.sort()
	return out


func get_candidate_ids(bank_state: Variant) -> Array[String]:
	var out: Array[String] = []
	if bank_state == null or not (bank_state is Object):
		return out
	var cands: Variant = (bank_state as Object).get("candidates")
	if cands is Array:
		for c in (cands as Array):
			if c is Object:
				out.append(str((c as Object).get("id")))
			elif c is Dictionary:
				out.append(str((c as Dictionary).get("id", "")))
	return out


func ensure_station_staffed(cmd: Variant, bank_state: Variant) -> Dictionary:
	var st_ids: Array[String] = get_station_ids(bank_state)
	var emp_ids: Array[String] = get_employee_ids(bank_state)
	if st_ids.is_empty() or emp_ids.is_empty() or cmd == null:
		return {}
	var st_id: String = st_ids[0]
	var emp_id: String = emp_ids[0]
	var stations_v: Variant = (bank_state as Object).get("stations")
	if stations_v is Dictionary:
		var st: Variant = (stations_v as Dictionary).get(st_id, {})
		if st is Dictionary and not bool((st as Dictionary).get("is_open", true)):
			(cmd as Object).call("toggle_station_open", st_id)
	(cmd as Object).call("assign_employee_to_station", emp_id, st_id)
	return {"station_id": st_id, "employee_id": emp_id}


func is_result_ok(res: Variant) -> bool:
	if res == null or not (res is Object):
		return false
	var ok_val: Variant = (res as Object).get("ok")
	return typeof(ok_val) == TYPE_BOOL and bool(ok_val)


func get_result_data_dict(res: Variant) -> Dictionary:
	if res == null or not (res is Object):
		return {}
	var d: Variant = (res as Object).get("data")
	return d as Dictionary if d is Dictionary else {}


func invoke_disburse_loan(
	fe: Variant,
	bs: Variant,
	cust_id: String,
	amount: int,
	rate_bps: int = 700,
	term_days: int = 30,
	day: int = 1,
	minute: int = 540,
	ref_id: String = "e2e_loan"
) -> Variant:
	if not require_method(fe, "disburse_loan", "FinanceEngine"):
		return null
	var sig: Dictionary = has_method_sig(fe, "disburse_loan")
	var args: Array = sig.get("args", []) as Array
	var def_args: Array = sig.get("default_args", []) as Array
	var max_args: int = args.size()
	var min_args: int = max_args - def_args.size()
	var obj: Object = fe as Object

	if max_args >= 6 and min_args <= 6 and int((args[5] as Dictionary).get("type", 0)) == TYPE_STRING:
		return obj.call("disburse_loan", bs, cust_id, amount, rate_bps, term_days, ref_id)
	if max_args >= 5 and min_args <= 5:
		return obj.call("disburse_loan", bs, cust_id, amount, rate_bps, term_days)
	if max_args >= 8:
		return obj.call("disburse_loan", bs, cust_id, amount, rate_bps, term_days, day, minute, ref_id)
	if max_args == 7:
		return obj.call("disburse_loan", bs, cust_id, amount, rate_bps, term_days, day, minute)
	if max_args == 6:
		return obj.call("disburse_loan", bs, cust_id, amount, rate_bps, term_days, ref_id)
	if max_args == 4:
		return obj.call("disburse_loan", bs, amount, rate_bps, term_days)
	if max_args == 3:
		return obj.call("disburse_loan", bs, amount, ref_id)
	return obj.call("disburse_loan", bs, amount)


func invoke_repay_loan(
	fe: Variant,
	bs: Variant,
	loan_id: String,
	amount: int,
	day: int = 1,
	minute: int = 560,
	ref_id: String = "e2e_repay"
) -> Variant:
	if not require_method(fe, "record_loan_repayment", "FinanceEngine"):
		return null
	var sig: Dictionary = has_method_sig(fe, "record_loan_repayment")
	var args: Array = sig.get("args", []) as Array
	var def_args: Array = sig.get("default_args", []) as Array
	var max_args: int = args.size()
	var min_args: int = max_args - def_args.size()
	var obj: Object = fe as Object

	if max_args >= 5 and min_args <= 5:
		return obj.call("record_loan_repayment", bs, loan_id, amount, day, minute)
	if max_args >= 6:
		return obj.call("record_loan_repayment", bs, loan_id, amount, day, minute, ref_id)
	if max_args == 4:
		if int((args[3] as Dictionary).get("type", 0)) == TYPE_STRING:
			return obj.call("record_loan_repayment", bs, loan_id, amount, ref_id)
		return obj.call("record_loan_repayment", bs, loan_id, amount, day)
	if max_args == 3:
		return obj.call("record_loan_repayment", bs, loan_id, amount)
	return obj.call("record_loan_repayment", bs, amount)


func trigger_event_safely(ee: Variant, bs: Variant, event_id: String, defs: Dictionary) -> Variant:
	if not require_method(ee, "trigger_event", "EventEngine"):
		return null
	var sig: Dictionary = has_method_sig(ee, "trigger_event")
	var args: Array = sig.get("args", []) as Array
	var def_args: Array = sig.get("default_args", []) as Array
	var max_args: int = args.size()
	var min_args: int = max_args - def_args.size()
	var obj: Object = ee as Object
	if max_args >= 4 and min_args > 3:
		return obj.call("trigger_event", bs, event_id, defs, {})
	if max_args >= 3 and min_args <= 3:
		return obj.call("trigger_event", bs, event_id, defs)
	if max_args == 2:
		return obj.call("trigger_event", bs, event_id)
	return obj.call("trigger_event", bs, event_id, defs)
