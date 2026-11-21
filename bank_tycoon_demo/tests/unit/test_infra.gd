extends SceneTree

## Headless unit and integration test suite for Milestone M3 (Content Data, Localization, Mod Loader, SaveService, AudioService, GameSession).

const TEMP_MODS_ROOT: String = "user://__m3_unit_mods"
const TEMP_SLOT_A: String = "__m3_slot_a"
const TEMP_SLOT_B: String = "__m3_slot_b"

var _started: bool = false

static var _total: int = 0
static var _passed: int = 0
static var _failed: int = 0
static var _errors: Array[String] = []


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var summary: Dictionary = run_all(self)
	var passed_count: int = int(summary.get("passed", 0))
	var failed_count: int = int(summary.get("failed", 0))
	var total_count: int = int(summary.get("total", 0))
	print("[M3_INFRA] Summary: %d/%d assertions passed, %d failed" % [passed_count, total_count, failed_count])
	quit(0 if (failed_count == 0 and total_count > 0) else 1)
	return false


static func _get_autoload(tree: SceneTree, name_str: String) -> Node:
	var t: SceneTree = tree if tree != null else (Engine.get_main_loop() as SceneTree)
	if t == null or t.root == null:
		return null
	return t.root.get_node_or_null(NodePath(name_str))


static func _check(cond: bool, msg: String) -> void:
	_total += 1
	if cond:
		_passed += 1
	else:
		_failed += 1
		_errors.append(msg)
		print("[M3_INFRA] FAIL: %s" % msg)


static func _check_eq(actual: Variant, expected: Variant, msg: String) -> void:
	_total += 1
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		var detail: String = "%s (expected=%s, actual=%s)" % [msg, str(expected), str(actual)]
		_errors.append(detail)
		print("[M3_INFRA] FAIL: %s" % detail)


static func _run_case(name: String, fn: Callable) -> void:
	var fail_before: int = _failed
	fn.call()
	if _failed == fail_before:
		print("[M3_INFRA] PASS: %s" % name)


static func run_all(tree: SceneTree = null) -> Dictionary:
	_total = 0
	_passed = 0
	_failed = 0
	_errors.clear()

	var t: SceneTree = tree if tree != null else (Engine.get_main_loop() as SceneTree)
	var loc: Node = _get_autoload(t, "LocalizationService")
	var reg: Node = _get_autoload(t, "ContentRegistry")
	var audio: Node = _get_autoload(t, "AudioService")
	var save_svc: Node = _get_autoload(t, "SaveService")
	var sess: Node = _get_autoload(t, "GameSession")

	_check(loc != null, "LocalizationService autoload exists")
	_check(reg != null, "ContentRegistry autoload exists")
	_check(audio != null, "AudioService autoload exists")
	_check(save_svc != null, "SaveService autoload exists")
	_check(sess != null, "GameSession autoload exists")

	if loc == null or reg == null or audio == null or save_svc == null or sess == null:
		return {"total": _total, "passed": _passed, "failed": _failed, "errors": _errors.duplicate()}

	var orig_locale: String = str(loc.call("get_locale"))
	var orig_settings: Dictionary = sess.call("get_settings") as Dictionary

	_run_case("core_content_registry_and_schemas", func() -> void: _test_core_content_registry(reg))
	_run_case("localization_live_switch_and_gettext_files", func() -> void: _test_localization_live_switch(loc))
	_run_case("localization_4_level_fallback_and_override_guard", func() -> void: _test_localization_fallback_and_security(loc))
	_run_case("mod_loader_valid_dir_zip_and_topological_order", func() -> void: _test_mod_loader_valid_and_topo(reg, loc))
	_run_case("mod_loader_adversarial_hygiene_and_atomic_rejection", func() -> void: _test_mod_loader_security_and_atomic(reg))
	_run_case("save_service_atomic_roundtrip_bak_and_mod_warnings", func() -> void: _test_save_service(save_svc))
	_run_case("audio_service_and_game_session_lifecycle", func() -> void: _test_audio_and_game_session(audio, sess, loc))

	# Restore clean state
	_remove_dir_recursive(TEMP_MODS_ROOT)
	save_svc.call("delete_slot", TEMP_SLOT_A)
	save_svc.call("delete_slot", TEMP_SLOT_B)
	sess.call("end_session")
	loc.call("clear_mod_translations")
	reg.call("reload_all", "user://mods")
	loc.call("set_locale", orig_locale)
	sess.call("update_settings", orig_settings)
	_remove_file_if_exists("user://settings.json")

	return {
		"total": _total,
		"passed": _passed,
		"failed": _failed,
		"errors": _errors.duplicate(),
	}


static func _test_core_content_registry(reg: Node) -> void:
	var empty_dir: String = TEMP_MODS_ROOT + "/empty_core"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(empty_dir))
	var rep: Dictionary = reg.call("reload_all", empty_dir) as Dictionary
	_check_eq((rep.get("errors", []) as Array).size(), 0, "Empty mods dir produces 0 errors")
	_check_eq((rep.get("loaded_mods", []) as Array).size(), 0, "Empty mods dir loads 0 mods")

	var defs: Dictionary = reg.call("get_content_defs") as Dictionary
	var depts: Array = defs.get("departments", []) as Array
	var pols: Array = defs.get("policies", []) as Array
	var evs: Array = defs.get("events", []) as Array
	var traits: Array = defs.get("traits", []) as Array
	var custs: Array = defs.get("customers", []) as Array

	_check(depts.size() >= 4, "Loaded >= 4 core departments")
	_check(pols.size() >= 6, "Loaded >= 6 core policies")
	_check(evs.size() >= 10, "Loaded >= 10 core events")
	_check(traits.size() >= 6, "Loaded >= 6 core traits")
	_check(custs.size() >= 6, "Loaded >= 6 core customers")

	for did in ["core:department.operations", "core:department.hr", "core:department.credit", "core:department.risk"]:
		var ddef: Dictionary = reg.call("get_department_def", did) as Dictionary
		_check(not ddef.is_empty(), "Department exists: " + did)
		_check(ddef.get("initial_cost_minor") is int, "Department initial_cost_minor is int: " + did)

	for pid in [
		"core:policy.prudent_lending",
		"core:policy.liquidity_first",
		"core:policy.customer_trust",
		"core:policy.high_rate_acquisition",
		"core:policy.market_penetration",
		"core:policy.credit_expansion",
	]:
		var pdef: Dictionary = reg.call("get_policy_def", pid) as Dictionary
		_check(not pdef.is_empty(), "Policy exists: " + pid)

	for eid in [
		"core:event.real_estate_boom",
		"core:event.real_estate_cooling",
		"core:event.real_estate_credit_stress",
	]:
		var edef: Dictionary = reg.call("get_event_def", eid) as Dictionary
		_check(not edef.is_empty(), "Macro chain event exists: " + eid)


static func _test_localization_live_switch(loc: Node) -> void:
	var avail: PackedStringArray = loc.call("get_available_locales") as PackedStringArray
	_check(avail.has("zh_CN") and avail.has("en") and avail.has("ja"), "Available locales include zh_CN, en, ja")

	var emitted: Array[String] = []
	var cb: Callable = func(lc: String) -> void:
		emitted.append(lc)
	loc.connect("locale_changed", cb)

	var vals: Dictionary = {}
	for lc in ["en", "ja", "zh_CN"]:
		loc.call("set_locale", lc)
		_check_eq(str(loc.call("get_locale")), lc, "get_locale matches " + lc)
		var rendered: String = str(loc.call("tr_key", "UI_TOPBAR_DAY", {"day": 5}))
		_check(rendered != "" and rendered != "UI_TOPBAR_DAY", "UI_TOPBAR_DAY resolves in " + lc)
		vals[lc] = rendered

	loc.disconnect("locale_changed", cb)
	_check_eq(emitted, ["en", "ja", "zh_CN"], "locale_changed emitted in exact switch order")
	_check(vals["zh_CN"] != vals["en"] and vals["en"] != vals["ja"], "Translations differ across zh_CN, en, ja")

	for fpath in [
		"res://localization/messages.pot",
		"res://localization/zh_CN.po",
		"res://localization/en.po",
		"res://localization/ja.po",
	]:
		_check(FileAccess.file_exists(ProjectSettings.globalize_path(fpath)), "Gettext file exists: " + fpath)


static func _test_localization_fallback_and_security(loc: Node) -> void:
	loc.call("clear_mod_translations")
	loc.call("register_mod_translations", "com.unit.fb", "ja", {"com.unit.fb:JA_KEY": "ModJAValue"})
	loc.call("register_mod_translations", "com.unit.fb", "en", {
		"com.unit.fb:JA_KEY": "ModENValue",
		"com.unit.fb:EN_ONLY": "ModENFallback",
	})
	loc.call("set_locale", "ja")

	_check_eq(str(loc.call("tr_key", "com.unit.fb:JA_KEY")), "ModJAValue", "Level 1: Mod current locale")
	_check(str(loc.call("tr_key", "DEPT_OPERATIONS_NAME")) != "DEPT_OPERATIONS_NAME", "Level 2: Vanilla current locale")
	_check_eq(str(loc.call("tr_key", "com.unit.fb:EN_ONLY")), "ModENFallback", "Level 3: Mod EN fallback when JA missing")
	_check_eq(str(loc.call("tr_key", "MISSING_KEY_XYZ_999")), "MISSING_KEY_XYZ_999", "Level 4: Missing key returns raw key")

	# Security: forbid overriding vanilla or peer mod keys
	loc.call("set_locale", "en")
	var vanilla_day: String = str(loc.call("tr_key", "UI_TOPBAR_DAY"))
	loc.call("register_mod_translations", "com.peer.one", "en", {"com.peer.one:TITLE": "PeerOne"})
	loc.call("register_mod_translations", "com.evil.mod", "en", {
		"UI_TOPBAR_DAY": "OVERRIDDEN_VANILLA",
		"com.peer.one:TITLE": "OVERRIDDEN_PEER",
	})
	_check_eq(str(loc.call("tr_key", "UI_TOPBAR_DAY")), vanilla_day, "Vanilla key protected from mod override")
	_check_eq(str(loc.call("tr_key", "com.peer.one:TITLE")), "PeerOne", "Peer mod key protected from override")
	loc.call("clear_mod_translations")


static func _test_mod_loader_valid_and_topo(reg: Node, loc: Node) -> void:
	var project_abs: String = ProjectSettings.globalize_path("res://").rstrip("/\\")
	var repo_abs: String = project_abs.get_base_dir()
	var template_abs: String = repo_abs.path_join("examples/mod_template")

	# 1. Valid directory mod
	var dir_mods: String = TEMP_MODS_ROOT + "/valid_dir"
	_remove_dir_recursive(dir_mods)
	_copy_dir_recursive(template_abs, ProjectSettings.globalize_path(dir_mods + "/com.example.extra_departments"))
	var rep_dir: Dictionary = reg.call("reload_all", dir_mods) as Dictionary
	_check_eq((rep_dir.get("rejected_mods", []) as Array).size(), 0, "Valid directory mod has 0 rejections")
	_check(not (reg.call("get_department_def", "com.example.extra_departments:department.research_support") as Dictionary).is_empty(), "Directory mod department registered")

	# 2. Valid ZIP mod + translations
	var zip_mods: String = TEMP_MODS_ROOT + "/valid_zip"
	_remove_dir_recursive(zip_mods)
	var zip_path: String = zip_mods + "/extra_departments.zip"
	_check(_build_zip_from_dir(zip_path, template_abs), "Built ZIP from examples/mod_template")
	var rep_zip: Dictionary = reg.call("reload_all", zip_mods) as Dictionary
	_check_eq((rep_zip.get("rejected_mods", []) as Array).size(), 0, "Valid ZIP mod has 0 rejections")
	loc.call("set_locale", "zh_CN")
	_check_eq(str(loc.call("tr_key", "com.example.extra_departments:DEPT_RESEARCH_NAME")), "流程研究部", "ZIP mod zh_CN translation loaded")
	loc.call("set_locale", "en")
	_check_eq(str(loc.call("tr_key", "com.example.extra_departments:DEPT_RESEARCH_NAME")), "Process Research", "ZIP mod en translation loaded")
	loc.call("set_locale", "ja")
	_check_eq(str(loc.call("tr_key", "com.example.extra_departments:DEPT_RESEARCH_NAME")), "業務研究部", "ZIP mod ja translation loaded")

	# 3. Topological load order
	var topo_mods: String = TEMP_MODS_ROOT + "/topo"
	_remove_dir_recursive(topo_mods)
	_write_minimal_mod(topo_mods + "/com.test.b", "com.test.b", "1.0.0", ["com.test.a"])
	_write_minimal_mod(topo_mods + "/com.test.a", "com.test.a", "1.0.0", [])
	_write_minimal_mod(topo_mods + "/com.test.c", "com.test.c", "1.0.0", [])
	var rep_topo: Dictionary = reg.call("reload_all", topo_mods) as Dictionary
	var loaded_ids: Array[String] = []
	for m in (rep_topo.get("loaded_mods", []) as Array):
		if m is Dictionary:
			loaded_ids.append(str((m as Dictionary).get("id", "")))
	_check_eq(loaded_ids.size(), 3, "All 3 topological mods loaded")
	_check(loaded_ids.find("com.test.a") < loaded_ids.find("com.test.b"), "com.test.a loaded strictly before com.test.b")


static func _test_mod_loader_security_and_atomic(reg: Node) -> void:
	var adv_mods: String = TEMP_MODS_ROOT + "/adversarial"
	_remove_dir_recursive(adv_mods)

	# 1. Path traversal dir & zip
	_write_json(adv_mods + "/com.evil.dir/manifest.json", {
		"schema_version": 1, "id": "com.evil.dir", "name_key": "N", "version": "1.0.0", "author": "A",
		"content": {"departments": "../../data/departments.json"},
	})
	_build_zip_from_entries(adv_mods + "/evil.zip", {
		"manifest.json": {"schema_version": 1, "id": "com.evil.zip", "name_key": "N", "version": "1.0.0", "author": "A"},
		"../../escape.json": "{}",
	})

	# 2. Atomic rejection on bad schema sibling
	_write_json(adv_mods + "/com.bad.atomic/manifest.json", {
		"schema_version": 1, "id": "com.bad.atomic", "name_key": "N", "version": "1.0.0", "author": "A",
		"content": {"departments": "content/departments.json"},
	})
	_write_json(adv_mods + "/com.bad.atomic/content/departments.json", [
		{
			"id": "com.bad.atomic:department.good",
			"name_key": "N", "description_key": "D",
			"initial_cost_minor": 1000, "daily_cost_minor": 100, "max_level": 3, "effects": [],
		},
		{
			"id": "com.bad.atomic:department.bad",
			"name_key": "N", "description_key": "D",
			"initial_cost_minor": 1000, "daily_cost_minor": -10, "max_level": 9, "extra_bad": 1, "effects": [],
		},
	])

	# 3. Script + eval + non-whitelisted effect
	_write_json(adv_mods + "/com.evil.script/manifest.json", {
		"schema_version": 1, "id": "com.evil.script", "name_key": "N", "version": "1.0.0", "author": "A",
		"content": {"events": "content/events.json"},
	})
	_write_text(adv_mods + "/com.evil.script/hack.gd", "extends Node\n")
	_write_json(adv_mods + "/com.evil.script/content/events.json", [{
		"id": "com.evil.script:event.bad", "title_key": "T", "description_key": "D", "weight": 10, "cooldown_days": 1,
		"conditions": [{"type": "eval(1)", "value": 1}],
		"options": [{"id": "o1", "label_key": "L", "effects": [{"target": "bank.infinite", "operation": "add", "value": 1}]}],
	}])

	# 4. Dangling cross-reference
	_write_json(adv_mods + "/com.bad.dangle/manifest.json", {
		"schema_version": 1, "id": "com.bad.dangle", "name_key": "N", "version": "1.0.0", "author": "A",
		"content": {"events": "content/events.json"},
	})
	_write_json(adv_mods + "/com.bad.dangle/content/events.json", [{
		"id": "com.bad.dangle:event.d", "title_key": "T", "description_key": "D", "weight": 10, "cooldown_days": 1,
		"conditions": [{"type": "department_exists", "value": "com.nonexistent:department.none"}],
		"options": [{"id": "o1", "label_key": "L", "effects": [], "next_event_id": "com.nonexistent:event.none"}],
	}])

	var rep: Dictionary = reg.call("reload_all", adv_mods) as Dictionary
	_check_eq((rep.get("loaded_mods", []) as Array).size(), 0, "Zero adversarial mods loaded")
	_check((rep.get("rejected_mods", []) as Array).size() >= 5, "All 5 adversarial mods recorded in rejected_mods")
	_check((reg.call("get_department_def", "com.bad.atomic:department.good") as Dictionary).is_empty(), "Atomic rejection prevented good sibling from registering")


static func _test_save_service(save_svc: Node) -> void:
	_check_eq(int(save_svc.get("SAVE_VERSION")), 1, "SaveService.SAVE_VERSION == 1")
	save_svc.call("delete_slot", TEMP_SLOT_A)
	save_svc.call("delete_slot", TEMP_SLOT_B)

	var bs: BankState = BankState.create_starter_branch("SaveUnit Bank", 7788)
	bs.reputation = 66
	bs.adopted_policies.append("core:policy.prudent_lending")
	bs.departments["com.missing.mod:department.custom"] = {
		"id": "com.missing.mod:department.custom",
		"level": 2,
		"created_day": 1,
		"daily_cost_minor": 5000,
		"staff_ids": [],
	}

	var r1: Result = save_svc.call("save_slot", TEMP_SLOT_A, bs, {"tag": "v1"}) as Result
	_check(r1.ok, "Save v1 succeeds")
	var slot_path: String = str(save_svc.call("get_slot_path", TEMP_SLOT_A))
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(slot_path)), "Primary .json exists")
	_check(not FileAccess.file_exists(ProjectSettings.globalize_path(slot_path.replace(".json", ".tmp"))), "No .tmp residue")

	bs.reputation = 91
	var r2: Result = save_svc.call("save_slot", TEMP_SLOT_A, bs, {"tag": "v2"}) as Result
	_check(r2.ok, "Save v2 succeeds and rotates v1 to .bak")
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(slot_path.replace(".json", ".bak"))), ".bak file exists")

	# Primary load + missing mod warning check
	var load_primary: Result = save_svc.call("load_slot", TEMP_SLOT_A) as Result
	_check(load_primary.ok, "Primary load succeeds")
	var ldata: Dictionary = load_primary.data as Dictionary
	_check_eq(bool(ldata.get("used_backup", true)), false, "Primary load used_backup == false")
	var restored: BankState = ldata.get("bank_state") as BankState
	_check_eq(restored.reputation, 91, "Primary load reputation == 91")
	_check(restored.departments.has("com.missing.mod:department.custom"), "Unknown mod department preserved")
	var warns: Array = ldata.get("mod_warnings", []) as Array
	_check(str(warns).contains("com.missing.mod"), "mod_warnings mentions missing mod namespace")

	# Corrupt primary -> .bak recovery
	_write_text(slot_path, "{corrupted_json")
	var load_bak: Result = save_svc.call("load_slot", TEMP_SLOT_A) as Result
	_check(load_bak.ok, "Backup recovery succeeds when primary is corrupt")
	var bdata: Dictionary = load_bak.data as Dictionary
	_check_eq(bool(bdata.get("used_backup", false)), true, "Backup load sets used_backup == true")
	var restored_bak: BankState = bdata.get("bank_state") as BankState
	_check_eq(restored_bak.reputation, 66, "Backup load restores v1 reputation == 66")

	# Invalid slot ID & unsupported save_version
	_check(not (save_svc.call("save_slot", "../bad", bs) as Result).ok, "Path traversal slot_id rejected on save")
	_check(not (save_svc.call("load_slot", "bad/slot") as Result).ok, "Path separator slot_id rejected on load")

	save_svc.call("save_slot", TEMP_SLOT_B, bs)
	var p_b: String = str(save_svc.call("get_slot_path", TEMP_SLOT_B))
	var doc_b: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p_b)) as Dictionary
	doc_b["save_version"] = 999
	_write_json(p_b, doc_b)
	var bad_ver: Result = save_svc.call("load_slot", TEMP_SLOT_B) as Result
	_check(not bad_ver.ok, "Unsupported save_version=999 rejected")


static func _test_audio_and_game_session(audio: Node, sess: Node, loc: Node) -> void:
	audio.call("set_bus_volume", "InvalidBus", 0.5)
	audio.call("set_bus_volume", "BGM", -0.5)
	_check(is_equal_approx(float(audio.call("get_bus_volume", "BGM")), 0.0), "Negative BGM volume clamped to 0.0")
	audio.call("set_bus_volume", "SFX", 3.5)
	_check(is_equal_approx(float(audio.call("get_bus_volume", "SFX")), 1.0), "Excessive SFX volume clamped to 1.0")
	audio.call("play_bgm", "missing_bgm_track", 0.0)
	audio.call("play_sfx", "missing_sfx_clip")
	audio.call("play_bgm", "bgm_starway_lobby", 0.0)
	audio.call("play_sfx", "sfx_ui_click")
	audio.call("stop_bgm", 0.0)

	sess.call("end_session")
	_check(not bool(sess.get("is_active")), "Session inactive after end_session")
	_check(not (sess.call("save_to_slot", TEMP_SLOT_A) as Result).ok, "save_to_slot fails when session inactive")

	var bs: BankState = sess.call("start_new_game", "Infra Session Bank", 13579) as BankState
	_check(bs != null and bool(sess.get("is_active")), "start_new_game activates session")
	_check((sess.call("save_to_slot", TEMP_SLOT_A) as Result).ok, "save_to_slot succeeds when active")
	sess.call("end_session")
	_check((sess.call("load_from_slot", TEMP_SLOT_A) as Result).ok, "load_from_slot restores active session")
	var loaded_bs: BankState = sess.get("bank_state") as BankState
	_check_eq(loaded_bs.bank_name, "Infra Session Bank", "Restored session bank_name matches")

	sess.call("update_settings", {
		"locale": "ja",
		"bgm_volume": 0.45,
		"sfx_volume": 0.85,
		"muted": false,
		"minute_duration_sec": 0.5,
	})
	_check_eq(str(loc.call("get_locale")), "ja", "GameSession.update_settings updates LocalizationService")
	_check(is_equal_approx(float(audio.call("get_bus_volume", "BGM")), 0.45), "GameSession.update_settings updates BGM volume")
	_check(is_equal_approx(float(sess.get("minute_duration_sec")), 0.5), "GameSession.update_settings updates minute_duration_sec")


static func _write_text(path: String, text: String) -> bool:
	var abs_p: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_p.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


static func _write_json(path: String, data: Variant) -> bool:
	return _write_text(path, JSON.stringify(data, "  "))


static func _remove_file_if_exists(path: String) -> void:
	var abs_p: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_p):
		DirAccess.remove_absolute(abs_p)


static func _write_minimal_mod(dir_path: String, mod_id: String, ver: String, deps: Array) -> void:
	_write_json(dir_path + "/manifest.json", {
		"schema_version": 1,
		"id": mod_id,
		"name_key": "%s:MOD_NAME" % mod_id,
		"version": ver,
		"author": "UnitTest",
		"dependencies": deps,
		"content": {"departments": "content/departments.json"},
	})
	_write_json(dir_path + "/content/departments.json", [{
		"id": "%s:department.sample" % mod_id,
		"name_key": "%s:DEPT_NAME" % mod_id,
		"description_key": "%s:DEPT_DESC" % mod_id,
		"initial_cost_minor": 100000,
		"daily_cost_minor": 5000,
		"max_level": 2,
		"effects": [],
	}])


static func _copy_dir_recursive(src_abs: String, dst_abs: String) -> bool:
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
				_copy_dir_recursive(s_sub, d_sub)
			else:
				var bytes: PackedByteArray = FileAccess.get_file_as_bytes(s_sub)
				var f: FileAccess = FileAccess.open(d_sub, FileAccess.WRITE)
				if f != null:
					f.store_buffer(bytes)
					f.close()
		entry = da.get_next()
	da.list_dir_end()
	return true


static func _remove_dir_recursive(dir_path: String) -> void:
	var abs_p: String = ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_p):
		return
	var da: DirAccess = DirAccess.open(abs_p)
	if da == null:
		return
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var sub: String = abs_p.path_join(entry)
			if da.current_is_dir():
				_remove_dir_recursive(sub)
			else:
				DirAccess.remove_absolute(sub)
		entry = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(abs_p)


static func _find_files_recursive(abs_dir: String) -> Array[String]:
	var out: Array[String] = []
	var da: DirAccess = DirAccess.open(abs_dir)
	if da == null:
		return out
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var sub: String = abs_dir.path_join(entry)
			if da.current_is_dir():
				out.append_array(_find_files_recursive(sub))
			else:
				out.append(sub)
		entry = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


static func _build_zip_from_entries(zip_path: String, entries: Dictionary) -> bool:
	var abs_zip: String = ProjectSettings.globalize_path(zip_path)
	DirAccess.make_dir_recursive_absolute(abs_zip.get_base_dir())
	var packer := ZIPPacker.new()
	if packer.open(abs_zip) != OK:
		return false
	for k: Variant in entries.keys():
		var val: Variant = entries[k]
		var bytes: PackedByteArray
		if val is PackedByteArray:
			bytes = val
		elif val is String:
			bytes = (val as String).to_utf8_buffer()
		else:
			bytes = JSON.stringify(val, "  ").to_utf8_buffer()
		packer.start_file(str(k))
		packer.write_file(bytes)
		packer.close_file()
	packer.close()
	return true


static func _build_zip_from_dir(zip_path: String, src_abs_dir: String) -> bool:
	var clean_src: String = src_abs_dir.rstrip("/\\")
	var files: Array[String] = _find_files_recursive(clean_src)
	var entries: Dictionary = {}
	for fpath in files:
		var rel: String = fpath.substr(clean_src.length() + 1).replace("\\", "/")
		entries[rel] = FileAccess.get_file_as_bytes(fpath)
	return _build_zip_from_entries(zip_path, entries)
