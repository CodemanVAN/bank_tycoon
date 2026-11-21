extends Node

## Atomic JSON save/load service (save_version = 1) with .tmp verification, .bak fallback, and Mod dependency check.

const SAVE_VERSION: int = 1
const GAME_VERSION: String = "0.1.0"
const SAVES_DIR: String = "user://saves"


static func _get_slot_rx() -> RegEx:
	var rx := RegEx.new()
	rx.compile("^[A-Za-z0-9_-]+$")
	return rx


static func _is_valid_slot_id(slot_id: String) -> bool:
	if slot_id.is_empty() or slot_id.contains("..") or slot_id.contains("/") or slot_id.contains("\\") or slot_id.contains(":"):
		return false
	if slot_id.contains("\n") or slot_id.contains("\r") or slot_id.contains("\t") or slot_id.contains(" "):
		return false
	return _get_slot_rx().search(slot_id) != null


func get_slot_path(slot_id: String) -> String:
	var safe_slot_id: String = slot_id.replace("/", "_").replace("\\", "_").replace("..", "_").replace(":", "_")
	if safe_slot_id.is_empty():
		safe_slot_id = "autosave"
	return "%s/%s.json" % [SAVES_DIR, safe_slot_id]


func _get_bak_path(slot_id: String) -> String:
	return "%s/%s.bak" % [SAVES_DIR, slot_id]


func _get_tmp_path(slot_id: String) -> String:
	return "%s/%s.tmp" % [SAVES_DIR, slot_id]


func save_slot(slot_id: String, bank_state: Variant, metadata: Dictionary = {}) -> Result:
	if not _is_valid_slot_id(slot_id):
		return Result.fail(&"INVALID_SLOT_ID", "ERR_INVALID_SLOT_ID", {"slot_id": slot_id})
	if bank_state == null or not (bank_state is Object) or not (bank_state as Object).has_method("to_dict"):
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var saves_abs: String = ProjectSettings.globalize_path(SAVES_DIR)
	DirAccess.make_dir_recursive_absolute(saves_abs)

	var loaded_mods: Array[Dictionary] = []
	if ContentRegistry != null and ContentRegistry.has_method("get_loaded_mod_dependencies"):
		loaded_mods = ContentRegistry.get_loaded_mod_dependencies()

	var bs_obj: Object = bank_state as Object
	var merged_mods: Array[Dictionary] = []
	var seen_mods: Dictionary = {}
	for m in loaded_mods:
		var mid: String = str(m.get("id", ""))
		if mid != "" and not seen_mods.has(mid):
			seen_mods[mid] = true
			merged_mods.append(m.duplicate(true))

	var existing_bs_mods: Variant = bs_obj.get("mod_dependencies")
	if existing_bs_mods is Array:
		for em in (existing_bs_mods as Array):
			if em is Dictionary:
				var em_d: Dictionary = em as Dictionary
				var mid: String = str(em_d.get("id", ""))
				if mid != "" and not seen_mods.has(mid):
					seen_mods[mid] = true
					merged_mods.append(em_d.duplicate(true))

	bs_obj.set("mod_dependencies", merged_mods)

	var state_dict: Dictionary = bs_obj.call("to_dict") as Dictionary
	var now_utc: String = Time.get_datetime_string_from_system(true) + "Z"

	var save_doc: Dictionary = {
		"save_version": SAVE_VERSION,
		"game_version": GAME_VERSION,
		"created_at_utc": now_utc,
		"saved_at_utc": now_utc,
		"slot_id": slot_id,
		"world_seed": state_dict.get("world_seed", "20261121"),
		"current_day": int(state_dict.get("current_day", 1)),
		"current_minute_of_day": int(state_dict.get("current_minute_of_day", 540)),
		"currency_code": str(state_dict.get("currency_code", "CNY")),
		"metadata": metadata.duplicate(true),
		"mod_dependencies": merged_mods,
		"bank_state": state_dict,
	}

	var json_text: String = JSON.stringify(save_doc, "  ")
	var primary_path: String = get_slot_path(slot_id)
	var bak_path: String = _get_bak_path(slot_id)
	var tmp_path: String = _get_tmp_path(slot_id)

	var primary_abs: String = ProjectSettings.globalize_path(primary_path)
	var bak_abs: String = ProjectSettings.globalize_path(bak_path)
	var tmp_abs: String = ProjectSettings.globalize_path(tmp_path)

	# Step 1: Write to .tmp
	var f_tmp: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f_tmp == null:
		return Result.fail(&"SAVE_WRITE_FAILED", "ERR_SAVE_WRITE_FAILED", {"slot_id": slot_id})
	f_tmp.store_string(json_text)
	f_tmp.close()

	# Step 2: Read back and verify .tmp JSON integrity
	var f_ver: FileAccess = FileAccess.open(tmp_path, FileAccess.READ)
	if f_ver == null:
		_remove_abs_if_exists(tmp_abs)
		return Result.fail(&"SAVE_WRITE_FAILED", "ERR_SAVE_WRITE_FAILED", {"slot_id": slot_id})
	var verify_text: String = f_ver.get_as_text()
	f_ver.close()
	var verify_parsed: Variant = JSON.parse_string(verify_text)
	if not (verify_parsed is Dictionary):
		_remove_abs_if_exists(tmp_abs)
		return Result.fail(&"SAVE_WRITE_FAILED", "ERR_SAVE_WRITE_FAILED", {"slot_id": slot_id})

	# Step 3: Rotate existing primary .json -> .bak
	if FileAccess.file_exists(primary_abs):
		var old_bytes: PackedByteArray = FileAccess.get_file_as_bytes(primary_path)
		var f_bak: FileAccess = FileAccess.open(bak_path, FileAccess.WRITE)
		if f_bak != null:
			f_bak.store_buffer(old_bytes)
			f_bak.close()

	# Step 4: Promote .tmp -> .json and remove .tmp
	var new_bytes: PackedByteArray = FileAccess.get_file_as_bytes(tmp_path)
	var f_pri: FileAccess = FileAccess.open(primary_path, FileAccess.WRITE)
	if f_pri == null:
		_remove_abs_if_exists(tmp_abs)
		return Result.fail(&"SAVE_WRITE_FAILED", "ERR_SAVE_WRITE_FAILED", {"slot_id": slot_id})
	f_pri.store_buffer(new_bytes)
	f_pri.close()
	_remove_abs_if_exists(tmp_abs)

	return Result.succeed({
		"slot_id": slot_id,
		"path": primary_path,
		"bak_exists": FileAccess.file_exists(bak_abs),
		"saved_at_utc": now_utc,
	})


func load_slot(slot_id: String) -> Result:
	if not _is_valid_slot_id(slot_id):
		return Result.fail(&"INVALID_SLOT_ID", "ERR_INVALID_SLOT_ID", {"slot_id": slot_id})

	var primary_path: String = get_slot_path(slot_id)
	var bak_path: String = _get_bak_path(slot_id)
	var primary_exists: bool = FileAccess.file_exists(ProjectSettings.globalize_path(primary_path))
	var bak_exists: bool = FileAccess.file_exists(ProjectSettings.globalize_path(bak_path))

	if not primary_exists and not bak_exists:
		return Result.fail(&"SAVE_NOT_FOUND", "ERR_SAVE_NOT_FOUND", {"slot_id": slot_id})

	var used_backup: bool = false
	var parse_res: Result = null

	if primary_exists:
		parse_res = _parse_and_restore_file(primary_path)
		if not parse_res.ok and parse_res.error_code == &"UNSUPPORTED_SAVE_VERSION":
			return parse_res

	if (parse_res == null or not parse_res.ok) and bak_exists:
		var bak_res: Result = _parse_and_restore_file(bak_path)
		if bak_res.ok:
			parse_res = bak_res
			used_backup = true
		elif bak_res.error_code == &"UNSUPPORTED_SAVE_VERSION":
			return bak_res

	if parse_res == null or not parse_res.ok:
		return Result.fail(&"SAVE_CORRUPTED", "ERR_SAVE_CORRUPTED", {"slot_id": slot_id})

	var payload: Dictionary = parse_res.data as Dictionary
	var doc: Dictionary = payload["doc"] as Dictionary
	var restored_state: BankState = payload["bank_state"] as BankState
	var mod_warnings: Array[String] = _compute_mod_warnings(doc, restored_state)
	var meta: Dictionary = {}
	if doc.get("metadata") is Dictionary:
		meta = (doc["metadata"] as Dictionary).duplicate(true)

	return Result.succeed({
		"bank_state": restored_state,
		"metadata": meta,
		"used_backup": used_backup,
		"mod_warnings": mod_warnings,
	})


func _parse_and_restore_file(file_path: String) -> Result:
	var f: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return Result.fail(&"SAVE_NOT_FOUND", "ERR_SAVE_NOT_FOUND", {"path": file_path})
	var txt: String = f.get_as_text()
	f.close()
	if txt.is_empty():
		return Result.fail(&"SAVE_CORRUPTED", "ERR_SAVE_CORRUPTED", {"path": file_path})

	var json := JSON.new()
	if json.parse(txt) != OK or not (json.data is Dictionary):
		return Result.fail(&"SAVE_CORRUPTED", "ERR_SAVE_CORRUPTED", {"path": file_path})

	var doc: Dictionary = BankState._coerce_json_numbers(json.data) as Dictionary
	if not doc.has("save_version"):
		return Result.fail(&"SAVE_CORRUPTED", "ERR_SAVE_CORRUPTED", {"path": file_path})

	var ver: int = int(doc.get("save_version", -1))
	if ver != SAVE_VERSION:
		return Result.fail(
			&"UNSUPPORTED_SAVE_VERSION",
			"ERR_UNSUPPORTED_SAVE_VERSION",
			{"version": ver}
		)

	var bs_raw: Variant = doc.get("bank_state", null)
	if not (bs_raw is Dictionary):
		return Result.fail(&"SAVE_CORRUPTED", "ERR_SAVE_CORRUPTED", {"path": file_path})

	var bs_res: Result = BankState.from_dict(bs_raw as Dictionary)
	if not bs_res.ok:
		return bs_res

	var restored: BankState = bs_res.data as BankState
	# Ensure top-level mod_dependencies are also reflected on restored BankState
	var top_mods: Variant = doc.get("mod_dependencies", [])
	if top_mods is Array and restored.mod_dependencies.is_empty():
		for item in (top_mods as Array):
			if item is Dictionary:
				restored.mod_dependencies.append((item as Dictionary).duplicate(true))

	return Result.succeed({
		"doc": doc,
		"bank_state": restored,
	})


func _compute_mod_warnings(doc: Dictionary, bank_state: BankState) -> Array[String]:
	var warnings: Array[String] = []
	var active_mod_ids: Dictionary = {}
	if ContentRegistry != null and ContentRegistry.has_method("get_loaded_mod_dependencies"):
		for m in ContentRegistry.get_loaded_mod_dependencies():
			var mid: String = str(m.get("id", ""))
			if mid != "":
				active_mod_ids[mid] = str(m.get("version", ""))

	var warned_ids: Dictionary = {}
	var saved_mods: Array = []
	if doc.get("mod_dependencies") is Array:
		saved_mods.append_array(doc["mod_dependencies"] as Array)
	for m in bank_state.mod_dependencies:
		saved_mods.append(m)

	for item in saved_mods:
		if item is Dictionary:
			var md: Dictionary = item as Dictionary
			var mid: String = str(md.get("id", ""))
			if mid != "" and mid != "core" and not active_mod_ids.has(mid) and not warned_ids.has(mid):
				warned_ids[mid] = true
				warnings.append("Missing mod dependency: %s (v%s)" % [mid, str(md.get("version", "1.0.0"))])

	# Also inspect departments and adopted_policies for non-core namespaces
	for did_v: Variant in bank_state.departments.keys():
		var did: String = str(did_v)
		var ns: String = ContentId.get_namespace(did)
		if ns != "" and ns != "core" and not active_mod_ids.has(ns) and not warned_ids.has(ns):
			warned_ids[ns] = true
			warnings.append("Missing mod dependency for department '%s': %s" % [did, ns])

	for pid in bank_state.adopted_policies:
		var ns: String = ContentId.get_namespace(pid)
		if ns != "" and ns != "core" and not active_mod_ids.has(ns) and not warned_ids.has(ns):
			warned_ids[ns] = true
			warnings.append("Missing mod dependency for policy '%s': %s" % [pid, ns])

	return warnings


func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var saves_abs: String = ProjectSettings.globalize_path(SAVES_DIR)
	if not DirAccess.dir_exists_absolute(saves_abs):
		return out
	var da: DirAccess = DirAccess.open(saves_abs)
	if da == null:
		return out

	var slot_ids: Array[String] = []
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.ends_with(".json"):
			var sid: String = fname.trim_suffix(".json")
			if _is_valid_slot_id(sid) and not slot_ids.has(sid):
				slot_ids.append(sid)
		fname = da.get_next()
	da.list_dir_end()
	slot_ids.sort()

	for sid in slot_ids:
		var p: String = get_slot_path(sid)
		var f: FileAccess = FileAccess.open(p, FileAccess.READ)
		var day: int = 1
		var cash_minor: int = 0
		var bank_name: String = "Starway Bank"
		var saved_at_utc: String = ""
		var save_ver: int = SAVE_VERSION
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				var d: Dictionary = parsed as Dictionary
				save_ver = int(d.get("save_version", SAVE_VERSION))
				saved_at_utc = str(d.get("saved_at_utc", d.get("created_at_utc", "")))
				var bs_d: Variant = d.get("bank_state", {})
				if bs_d is Dictionary:
					var bsd: Dictionary = bs_d as Dictionary
					day = int(bsd.get("current_day", d.get("current_day", 1)))
					bank_name = str(bsd.get("bank_name", "Starway Bank"))
					var ledger_d: Variant = bsd.get("ledger", {})
					if ledger_d is Dictionary:
						var bals: Variant = (ledger_d as Dictionary).get("balances", {})
						if bals is Dictionary:
							cash_minor = Ledger._parse_i64((bals as Dictionary).get("cash_reserves", 0), 0)
		out.append({
			"slot_id": sid,
			"exists": true,
			"day": day,
			"cash_minor": cash_minor,
			"bank_name": bank_name,
			"saved_at_utc": saved_at_utc,
			"save_version": save_ver,
		})
	return out


func delete_slot(slot_id: String) -> Result:
	if not _is_valid_slot_id(slot_id):
		return Result.fail(&"INVALID_SLOT_ID", "ERR_INVALID_SLOT_ID", {"slot_id": slot_id})

	_remove_abs_if_exists(ProjectSettings.globalize_path(get_slot_path(slot_id)))
	_remove_abs_if_exists(ProjectSettings.globalize_path(_get_bak_path(slot_id)))
	_remove_abs_if_exists(ProjectSettings.globalize_path(_get_tmp_path(slot_id)))
	return Result.succeed({"slot_id": slot_id})


static func _remove_abs_if_exists(abs_path: String) -> void:
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)
