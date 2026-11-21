extends RefCounted

## Tier 2 E2E Suite — 45 Boundary, Corner, Negative & Security Tests (F1:6, F2:8, F3:8, F4:8, F5:8, F6:7).


func run_suite(h: RefCounted) -> Array:
	var results: Array = []
	var tests: Array[Array] = [
		# F1 (6)
		["E2E_T2_F1_01", _t2_f1_01_invalid_camera_zoom_steps],
		["E2E_T2_F1_02", _t2_f1_02_unreachable_and_oob_grid_navigation],
		["E2E_T2_F1_03", _t2_f1_03_unknown_entity_focus_and_clear],
		["E2E_T2_F1_04", _t2_f1_04_strict_pixel_grid_constraints],
		["E2E_T2_F1_05", _t2_f1_05_strict_autoload_count_guard],
		["E2E_T2_F1_06", _t2_f1_06_domain_and_shared_zero_node_boundary],
		# F2 (8)
		["E2E_T2_F2_01", _t2_f2_01_ledger_rejects_zero_and_negative_amounts],
		["E2E_T2_F2_02", _t2_f2_02_ledger_rejects_unbalanced_single_empty_entries],
		["E2E_T2_F2_03", _t2_f2_03_ledger_unknown_account_invalid_side_and_500_cap],
		["E2E_T2_F2_04", _t2_f2_04_insufficient_cash_and_deposit_withdrawal_guard],
		["E2E_T2_F2_05", _t2_f2_05_loan_disbursement_insufficient_cash_guard],
		["E2E_T2_F2_06", _t2_f2_06_duplicate_daily_settlement_idempotency],
		["E2E_T2_F2_07", _t2_f2_07_interest_rate_bounds_rejection_and_boundary],
		["E2E_T2_F2_08", _t2_f2_08_round_div_zero_denom_and_64bit_safety],
		# F3 (8)
		["E2E_T2_F3_01", _t2_f3_01_speed_zero_complete_freeze],
		["E2E_T2_F3_02", _t2_f3_02_invalid_speed_and_max_ticks_catchup_cap],
		["E2E_T2_F3_03", _t2_f3_03_post_1700_closing_stops_new_spawns],
		["E2E_T2_F3_04", _t2_f3_04_bottleneck_all_closed_and_patience_timeout],
		["E2E_T2_F3_05", _t2_f3_05_illegal_employee_and_customer_state_transitions],
		["E2E_T2_F3_06", _t2_f3_06_mutually_exclusive_task_and_invalid_station],
		["E2E_T2_F3_07", _t2_f3_07_invalid_entity_ids_in_hr_and_queue_commands],
		["E2E_T2_F3_08", _t2_f3_08_employee_reassignment_and_adaptation_period],
		# F4 (8)
		["E2E_T2_F4_01", _t2_f4_01_policy_rejected_insufficient_strategy_points],
		["E2E_T2_F4_02", _t2_f4_02_policy_rejected_missing_prerequisite],
		["E2E_T2_F4_03", _t2_f4_03_mutually_exclusive_policy_branch_rejection],
		["E2E_T2_F4_04", _t2_f4_04_duplicate_and_invalid_policy_id_rejection],
		["E2E_T2_F4_05", _t2_f4_05_department_creation_and_upgrade_boundaries],
		["E2E_T2_F4_06", _t2_f4_06_locked_unknown_double_event_option_rejection],
		["E2E_T2_F4_07", _t2_f4_07_event_condition_and_cooldown_gating],
		["E2E_T2_F4_08", _t2_f4_08_modifier_service_clamping_and_idempotency],
		# F5 (8)
		["E2E_T2_F5_01", _t2_f5_01_four_level_localization_fallback_chain],
		["E2E_T2_F5_02", _t2_f5_02_mod_forbidden_vanilla_and_peer_key_override],
		["E2E_T2_F5_03", _t2_f5_03_path_traversal_rejection_dir_and_zip],
		["E2E_T2_F5_04", _t2_f5_04_malformed_json_schema_violations_non_semver],
		["E2E_T2_F5_05", _t2_f5_05_duplicate_content_ids_vanilla_and_inter_mod],
		["E2E_T2_F5_06", _t2_f5_06_unsafe_script_eval_non_png_oversized_rejection],
		["E2E_T2_F5_07", _t2_f5_07_missing_dep_circular_dep_and_conflicts],
		["E2E_T2_F5_08", _t2_f5_08_empty_mods_dir_and_dangling_cross_refs],
		# F6 (7)
		["E2E_T2_F6_01", _t2_f6_01_primary_save_corruption_bak_fallback],
		["E2E_T2_F6_02", _t2_f6_02_double_corruption_and_missing_slot_load],
		["E2E_T2_F6_03", _t2_f6_03_missing_mod_dependency_warning_on_load],
		["E2E_T2_F6_04", _t2_f6_04_invalid_slot_id_and_unsupported_save_version],
		["E2E_T2_F6_05", _t2_f6_05_invalid_audio_bus_track_and_volume_clamping],
		["E2E_T2_F6_06", _t2_f6_06_game_session_inactive_commands_and_null_safety],
		["E2E_T2_F6_07", _t2_f6_07_ui_pause_state_interaction_and_error_feedback],
	]

	for entry in tests:
		var test_id: String = str(entry[0])
		var fn: Callable = entry[1] as Callable
		results.append(h.call("run_test", 2, test_id, fn))
	return results


# ---------------------------------------------------------------------------
# F1 Boundaries (6)
# ---------------------------------------------------------------------------

func _t2_f1_01_invalid_camera_zoom_steps(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("ZoomBounds", 2101)
	if rt.is_empty():
		return
	var world: Node = h.instantiate_scene("res://scenes/world/bank_world.tscn", true)
	if world == null:
		return
	world.call("bind_runtime", rt["sim_host"])
	var cam: Camera2D = _find_camera2d(world)
	h.assert_not_null(cam, "BankWorld must contain Camera2D")
	for bad_step in [0, -5, 4, 99]:
		world.call("set_camera_zoom_step", bad_step)
		if cam != null:
			h.assert_true(cam.zoom.x >= 1.0 and cam.zoom.x <= 3.0, "Zoom must stay in [1, 3] for input %d" % bad_step)
			h.assert_eq(cam.zoom.x, float(int(cam.zoom.x)), "Zoom must remain strictly integer (no fractional zoom)")
			h.assert_eq(cam.zoom.x, cam.zoom.y, "Zoom X and Y must stay equal")


func _t2_f1_02_unreachable_and_oob_grid_navigation(h: Variant) -> void:
	var iso: Variant = h.instantiate_script("res://scripts/presentation/world/iso_grid.gd")
	if iso == null:
		return
	var obj: Object = iso as Object
	# Check OOB / blocked pathfinding returns explicit error or empty path without crash/hang
	var checked: bool = false
	for mname in ["find_path", "compute_path", "get_grid_path"]:
		if obj.has_method(mname):
			checked = true
			var res_oob: Variant = obj.call(mname, Vector2i(1, 1), Vector2i(-1, -1))
			_assert_invalid_path_result(h, res_oob, "OOB (-1,-1)")
			var res_oob2: Variant = obj.call(mname, Vector2i(1, 1), Vector2i(18, 12))
			_assert_invalid_path_result(h, res_oob2, "OOB (18,12)")
			if obj.has_method("set_solid") or obj.has_method("set_cell_solid"):
				var solid_fn: String = "set_solid" if obj.has_method("set_solid") else "set_cell_solid"
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						if not (dx == 0 and dy == 0):
							obj.call(solid_fn, Vector2i(5 + dx, 5 + dy), true)
				var res_blocked: Variant = obj.call(mname, Vector2i(1, 1), Vector2i(5, 5))
				_assert_invalid_path_result(h, res_blocked, "Surrounded blocked cell (5,5)")
			break
	h.assert_true(checked, "IsoGrid must expose pathfinding method (find_path / compute_path / get_grid_path)")


func _t2_f1_03_unknown_entity_focus_and_clear(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("FocusBounds", 2103)
	if rt.is_empty():
		return
	var world: Node = h.instantiate_scene("res://scenes/world/bank_world.tscn", true)
	if world == null:
		return
	world.call("bind_runtime", rt["sim_host"])
	world.call("focus_entity", &"employee", "nonexistent_999")
	world.call("focus_entity", &"unknown_type", "1")
	world.call("focus_entity", &"", "")
	var cam: Camera2D = _find_camera2d(world)
	h.assert_not_null(cam, "Camera2D remains valid after unknown/clear focus_entity calls")


func _t2_f1_04_strict_pixel_grid_constraints(h: Variant) -> void:
	var char_files: Array[String] = h.find_files_recursive("res://assets/characters", ".png")
	h.assert_gt(char_files.size(), 0, "assets/characters must contain PNGs")
	for f in char_files:
		var img := Image.new()
		if img.load(f) == OK:
			var w: int = img.get_width()
			var ht: int = img.get_height()
			var is_sheet: bool = (w == 96 and ht == 128)
			var is_portrait: bool = (w == 32 and ht == 32)
			h.assert_true(is_sheet or is_portrait, "Character PNG must be 96x128 sheet or 32x32 portrait: %s (%dx%d)" % [f.get_file(), w, ht])

	var fountain_abs: String = ProjectSettings.globalize_path("res://assets/environment/prop_fountain_sheet.png")
	if FileAccess.file_exists(fountain_abs):
		var fimg := Image.new()
		h.assert_eq(fimg.load(fountain_abs), OK, "prop_fountain_sheet.png loads cleanly")
		h.assert_eq(fimg.get_width() % 48, 0, "Fountain sheet width divisible by 48")
		h.assert_eq(fimg.get_height() % 48, 0, "Fountain sheet height divisible by 48")


func _t2_f1_05_strict_autoload_count_guard(h: Variant) -> void:
	var cfg := ConfigFile.new()
	h.assert_eq(cfg.load("res://project.godot"), OK, "Load project.godot")
	var keys: PackedStringArray = cfg.get_section_keys("autoload") if cfg.has_section("autoload") else PackedStringArray()
	h.assert_eq(keys.size(), 5, "Autoload count must be strictly 5")
	for forbidden in ["SimulationHost", "BankCommandService", "BranchSimulation", "FinanceEngine", "DomainEventBus"]:
		h.assert_false(keys.has(forbidden), "Forbidden manager registered as Autoload: %s" % forbidden)


func _t2_f1_06_domain_and_shared_zero_node_boundary(h: Variant) -> void:
	var files: Array[String] = []
	files.append_array(h.find_files_recursive("res://scripts/domain", ".gd"))
	files.append_array(h.find_files_recursive("res://scripts/shared", ".gd"))
	h.assert_gt(files.size(), 0, "scripts/domain and scripts/shared must contain .gd files")
	var forbidden_rx := RegEx.new()
	forbidden_rx.compile("(?m)(^\\s*extends\\s+(Node|Node2D|Control|SceneTree)\\b|\\bget_node\\s*\\(|\\bSceneTree\\b|\\bInput\\.)")
	for f in files:
		var raw_src: String = h.read_text_file(f)
		var stripped: String = _strip_gd_comments(raw_src)
		var m: RegExMatch = forbidden_rx.search(stripped)
		h.assert_true(m == null, "Domain/Shared script violates zero-Node boundary (%s): %s" % [f.get_file(), m.get_string() if m != null else ""])


# ---------------------------------------------------------------------------
# F2 Boundaries (8)
# ---------------------------------------------------------------------------

func _t2_f2_01_ledger_rejects_zero_and_negative_amounts(h: Variant) -> void:
	var ledger: Variant = h.instantiate_script("res://scripts/domain/ledger.gd")
	if ledger == null:
		return
	var l0: Array[Dictionary] = [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": 0},
		{"account": &"equity_capital", "side": "credit", "amount_minor": 0},
	]
	var lneg: Array[Dictionary] = [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": -1000},
		{"account": &"equity_capital", "side": "credit", "amount_minor": -1000},
	]
	h.assert_result_err(ledger.call("post_entry", 1, 540, "z", "TEST", l0), "Zero amount_minor")
	h.assert_result_err(ledger.call("post_entry", 1, 540, "n", "TEST", lneg), "Negative amount_minor")
	h.assert_eq(int(ledger.call("get_balance", &"cash_reserves")), 0, "Cash unchanged after rejected entries")
	h.assert_true(bool((ledger.call("get_balance_sheet_snapshot") as Dictionary).get("is_balanced", false)), "Ledger remains balanced")


func _t2_f2_02_ledger_rejects_unbalanced_single_empty_entries(h: Variant) -> void:
	var ledger: Variant = h.instantiate_script("res://scripts/domain/ledger.gd")
	if ledger == null:
		return
	var unbal: Array[Dictionary] = [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": 10_000},
		{"account": &"equity_capital", "side": "credit", "amount_minor": 9_999},
	]
	var single: Array[Dictionary] = [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": 5_000},
	]
	var empty: Array[Dictionary] = []
	h.assert_result_err(ledger.call("post_entry", 1, 540, "u", "TEST", unbal), "Unbalanced lines")
	h.assert_result_err(ledger.call("post_entry", 1, 540, "s", "TEST", single), "Single-line entry")
	h.assert_result_err(ledger.call("post_entry", 1, 540, "e", "TEST", empty), "Empty lines")
	h.assert_eq(int(ledger.call("get_balance", &"cash_reserves")), 0, "No partial writes")


func _t2_f2_03_ledger_unknown_account_invalid_side_and_500_cap(h: Variant) -> void:
	var ledger: Variant = h.instantiate_script("res://scripts/domain/ledger.gd")
	if ledger == null:
		return
	var bad_acct: Array[Dictionary] = [
		{"account": &"magic_gold", "side": "debit", "amount_minor": 100},
		{"account": &"equity_capital", "side": "credit", "amount_minor": 100},
	]
	var bad_side: Array[Dictionary] = [
		{"account": &"cash_reserves", "side": "increase", "amount_minor": 100},
		{"account": &"equity_capital", "side": "credit", "amount_minor": 100},
	]
	h.assert_result_err(ledger.call("post_entry", 1, 540, "ba", "TEST", bad_acct), "Unknown account")
	h.assert_result_err(ledger.call("post_entry", 1, 540, "bs", "TEST", bad_side), "Invalid side")

	# Post 550 balanced entries and check cumulative accuracy & bounded log
	for i in range(550):
		var lines: Array[Dictionary] = [
			{"account": &"cash_reserves", "side": "debit", "amount_minor": 10},
			{"account": &"equity_capital", "side": "credit", "amount_minor": 10},
		]
		var r: Variant = ledger.call("post_entry", 1, 540, "cap_%d" % i, "CAP", lines)
		if not h.is_result_ok(r):
			h.fail_test("Valid balanced entry #%d failed" % i)
			break
	h.assert_eq(int(ledger.call("get_balance", &"cash_reserves")), 5500, "Cumulative cash balance exact across 550 entries")
	h.assert_true(bool((ledger.call("get_balance_sheet_snapshot") as Dictionary).get("is_balanced", false)), "Balanced after 550 entries")
	var entry_count: int = _get_ledger_entry_count(h, ledger)
	h.assert_gt(entry_count, 0, "Ledger must expose retained journal entries after 550 postings")
	h.assert_le(entry_count, 500, "Ledger entry log must be capped at <= 500 entries (got %d)" % entry_count)


func _t2_f2_04_insufficient_cash_and_deposit_withdrawal_guard(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("WdGuard", 2204)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return
	var dep0: int = h.get_ledger_balance(bs, &"customer_deposits")
	h.assert_result_err(h.invoke_finance_amount_op(fe, "record_withdrawal", bs, dep0 + 50_000, 1, 540, "over_dep"), "Withdrawal exceeding deposits rejected")
	h.assert_ge(h.get_ledger_balance(bs, &"customer_deposits"), 0, "Deposits never negative")

	h.assert_result_ok(h.invoke_finance_amount_op(fe, "record_deposit", bs, 100_000, 1, 545, "d1"), "Deposit 100k")
	var cash_now: int = h.get_ledger_balance(bs, &"cash_reserves")
	if cash_now > 10_000:
		var drain_res: Variant = h.invoke_disburse_loan(fe, bs, "c_drain", cash_now - 10_000, 600, 30, 1, 550, "drain")
		h.assert_result_ok(drain_res, "disburse_loan drain to 10k cash")
	h.assert_result_err(h.invoke_finance_amount_op(fe, "record_withdrawal", bs, 20_000, 1, 555, "over_cash"), "Withdrawal exceeding cash_reserves rejected")
	h.assert_ge(h.get_ledger_balance(bs, &"cash_reserves"), 0, "cash_reserves never negative")


func _t2_f2_05_loan_disbursement_insufficient_cash_guard(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("LoanGuard", 2205)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return
	var cash0: int = h.get_ledger_balance(bs, &"cash_reserves")
	var loans_before: int = (bs.get("loans") as Dictionary).size()

	var res: Variant = h.invoke_disburse_loan(fe, bs, "cust_big", cash0 + 1, 700, 30, 1, 540, "over_loan")

	h.assert_result_err(res, "Loan disbursement exceeding cash_reserves must fail")
	h.assert_eq(h.get_ledger_balance(bs, &"cash_reserves"), cash0, "Cash unchanged on rejected loan")
	h.assert_eq((bs.get("loans") as Dictionary).size(), loans_before, "No loan added on rejected disbursement")


func _t2_f2_06_duplicate_daily_settlement_idempotency(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("IdempSettle", 2206)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	var mod_svc: Variant = h.instantiate_script("res://scripts/domain/modifier_service.gd")
	if fe == null or mod_svc == null:
		return
	var rng_streams: Variant = bs.get("rng_streams")
	var market_rng: Variant = (rng_streams as Object).get("market_rng") if rng_streams is Object else null
	var sig: Dictionary = h.has_method_sig(fe, "run_daily_settlement")
	var nargs: int = (sig.get("args", []) as Array).size()

	var r1: Variant = _invoke_settle(fe, nargs, bs, mod_svc, market_rng, rt["defs"])
	h.assert_result_ok(r1, "First daily settlement on Day 1")
	var cash1: int = h.get_ledger_balance(bs, &"cash_reserves")
	var ret1: int = h.get_ledger_balance(bs, &"retained_earnings")
	var count1: int = (bs.get("daily_reports") as Array).size()

	var r2: Variant = _invoke_settle(fe, nargs, bs, mod_svc, market_rng, rt["defs"])
	h.assert_result_err(r2, "Duplicate settlement on same current_day must fail")
	h.assert_eq(h.get_ledger_balance(bs, &"cash_reserves"), cash1, "Cash unchanged on duplicate settlement")
	h.assert_eq(h.get_ledger_balance(bs, &"retained_earnings"), ret1, "Retained earnings unchanged on duplicate settlement")
	h.assert_eq((bs.get("daily_reports") as Array).size(), count1, "daily_reports size unchanged")


func _t2_f2_07_interest_rate_bounds_rejection_and_boundary(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("RateBounds", 2207)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var dep0: int = int(bs.get("deposit_rate_bps"))
	var loan0: int = int(bs.get("loan_base_rate_bps"))

	h.assert_result_err(cmd.call("set_interest_rates", -1, 500), "Negative deposit_rate_bps rejected")
	h.assert_result_err(cmd.call("set_interest_rates", 200, -10), "Negative loan_base_rate_bps rejected")
	h.assert_result_err(cmd.call("set_interest_rates", 50_000, 50_000), "Extreme bps > ceiling rejected")
	h.assert_eq(int(bs.get("deposit_rate_bps")), dep0, "Prior deposit_rate_bps preserved")
	h.assert_eq(int(bs.get("loan_base_rate_bps")), loan0, "Prior loan_base_rate_bps preserved")

	# Query BalanceConfig dynamically if available for min/max bounds
	var cfg_script: GDScript = h.load_script("res://scripts/shared/balance_config.gd")
	if cfg_script != null:
		var min_dep: int = _get_const_or_prop(cfg_script, "MIN_DEPOSIT_RATE_BPS", 0)
		var max_loan: int = _get_const_or_prop(cfg_script, "MAX_LOAN_RATE_BPS", 2000)
		var min_loan: int = _get_const_or_prop(cfg_script, "MIN_LOAN_RATE_BPS", 100)
		h.assert_result_ok(cmd.call("set_interest_rates", min_dep, clampi(max_loan, min_loan, max_loan)), "Valid boundary interest rates accepted")


func _t2_f2_08_round_div_zero_denom_and_64bit_safety(h: Variant) -> void:
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return
	var zero_res: Variant = fe.call("round_div", 1000, 0)
	h.assert_true(zero_res is int, "round_div with denominator=0 handles safely without crashing")
	var big_interest: int = int(fe.call("round_div", 10_000_000_000 * 500, 10_000 * 365))
	h.assert_eq(big_interest, 1_369_863, "64-bit integer interest math must not overflow 32-bit")


# ---------------------------------------------------------------------------
# F3 Boundaries (8)
# ---------------------------------------------------------------------------

func _t2_f3_01_speed_zero_complete_freeze(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Freeze", 2301)
	if rt.is_empty():
		return
	h.ensure_station_staffed(rt["cmd"], rt["bank_state"])
	h.assert_result_ok(rt["cmd"].call("open_branch_for_day"), "open_branch_for_day")
	h.step_minutes(rt["sim_host"], 30, h.get_minute_duration(rt["session"]), 1)
	var min_before: int = int(rt["bank_state"].get("current_minute_of_day"))
	var cash_before: int = h.get_ledger_balance(rt["bank_state"], &"cash_reserves")

	h.assert_result_ok(rt["cmd"].call("set_speed", 0), "set_speed(0)")
	for _i in range(10):
		rt["sim_host"].call("step_simulation", 10.0)
	h.assert_eq(int(rt["bank_state"].get("current_minute_of_day")), min_before, "speed=0 must freeze current_minute_of_day")
	h.assert_eq(h.get_ledger_balance(rt["bank_state"], &"cash_reserves"), cash_before, "speed=0 must freeze Ledger")


func _t2_f3_02_invalid_speed_and_max_ticks_catchup_cap(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("CatchupCap", 2302)
	if rt.is_empty():
		return
	var cmd: Variant = rt["cmd"]
	var bs: Variant = rt["bank_state"]
	h.assert_result_ok(cmd.call("open_branch_for_day"), "open")
	h.assert_result_ok(cmd.call("set_speed", 1), "set_speed(1)")
	h.assert_result_err(cmd.call("set_speed", -1), "set_speed(-1) rejected")
	h.assert_result_err(cmd.call("set_speed", 4), "set_speed(4) rejected")
	h.assert_eq(int(bs.get("speed_multiplier")), 1, "Invalid speed preserves prior multiplier")

	h.assert_result_ok(cmd.call("set_speed", 3), "set_speed(3)")
	var min0: int = int(bs.get("current_minute_of_day"))
	rt["sim_host"].call("step_simulation", 60.0)
	var elapsed: int = int(bs.get("current_minute_of_day")) - min0
	h.assert_true(elapsed > 0 and elapsed <= 5, "Single huge delta must clamp to MAX_TICKS_PER_FRAME=5 (got %d)" % elapsed)


func _t2_f3_03_post_1700_closing_stops_new_spawns(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Closing17", 2303)
	if rt.is_empty():
		return
	h.ensure_station_staffed(rt["cmd"], rt["bank_state"])
	h.assert_result_ok(rt["cmd"].call("open_branch_for_day"), "open")

	var spawn_counts: Dictionary = {"before": 0, "after": 0}
	var bs: Variant = rt["bank_state"]
	(rt["event_bus"] as Object).connect("domain_event_emitted", func(ev: Variant) -> void:
		if ev is Object and str((ev as Object).get("event_type")) == "CustomerArrived":
			if int(bs.get("current_minute_of_day")) >= 1020:
				spawn_counts["after"] = int(spawn_counts["after"]) + 1
			else:
				spawn_counts["before"] = int(spawn_counts["before"]) + 1
	)

	var min_dur: float = h.get_minute_duration(rt["session"])
	h.step_minutes(rt["sim_host"], 510, min_dur, 1)
	h.assert_gt(int(spawn_counts["before"]), 0, "At least 1 customer must arrive before 17:00")
	h.assert_eq(int(spawn_counts["after"]), 0, "Zero new customers may spawn at/after 17:00 (minute >= 1020)")


func _t2_f3_04_bottleneck_all_closed_and_patience_timeout(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Bottleneck", 2304)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	for st_id in h.get_station_ids(bs):
		var st: Dictionary = (bs.get("stations") as Dictionary)[st_id] as Dictionary
		if bool(st.get("is_open", false)):
			cmd.call("toggle_station_open", st_id)

	var unserved_events: Array[int] = [0]
	(rt["event_bus"] as Object).connect("domain_event_emitted", func(ev: Variant) -> void:
		if ev is Object and str((ev as Object).get("event_type")) == "CustomerLeftUnserved":
			unserved_events[0] += 1
	)

	var sat0: int = int(bs.get("satisfaction"))
	h.assert_result_ok(cmd.call("open_branch_for_day"), "open")
	h.step_minutes(rt["sim_host"], 300, h.get_minute_duration(rt["session"]), 1)
	h.assert_gt(unserved_events[0], 0, "Unserved bottlenecked customers must timeout and emit CustomerLeftUnserved")
	h.assert_lt(int(bs.get("satisfaction")), sat0, "CustomerLeftUnserved must lower bank satisfaction")


func _t2_f3_05_illegal_employee_and_customer_state_transitions(h: Variant) -> void:
	var emp: Variant = h.instantiate_script("res://scripts/domain/employee.gd")
	var cust: Variant = h.instantiate_script("res://scripts/domain/customer.gd")
	var enums_script: GDScript = h.load_script("res://scripts/shared/enums.gd")
	if emp == null or cust == null or enums_script == null:
		return

	var emp_ok: bool = false
	for mname in ["transition_to", "set_state", "change_state"]:
		if (emp as Object).has_method(mname):
			emp_ok = true
			var off_val: Variant = _enum_val(enums_script, "EmployeeState", "OFF_DUTY", 5)
			var work_val: Variant = _enum_val(enums_script, "EmployeeState", "WORKING", 2)
			(emp as Object).set("state", off_val)
			var r: Variant = (emp as Object).call(mname, work_val)
			_assert_false_or_err(h, r, "Employee OFF_DUTY -> WORKING must be rejected")
			break
	h.assert_true(emp_ok, "EmployeeInstance must expose state transition validation method")

	var cust_ok: bool = false
	for mname in ["transition_to", "set_state", "change_state"]:
		if (cust as Object).has_method(mname):
			cust_ok = true
			var comp_val: Variant = _enum_val(enums_script, "CustomerState", "COMPLETED", 4)
			var wait_val: Variant = _enum_val(enums_script, "CustomerState", "WAITING", 2)
			(cust as Object).set("state", comp_val)
			var r2: Variant = (cust as Object).call(mname, wait_val)
			_assert_false_or_err(h, r2, "Customer COMPLETED -> WAITING must be rejected")
			break
	h.assert_true(cust_ok, "CustomerInstance must expose state transition validation method")


func _t2_f3_06_mutually_exclusive_task_and_invalid_station(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("MutexTask", 2306)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var emp_ids: Array[String] = h.get_employee_ids(bs)
	h.assert_gt(emp_ids.size(), 0, "Need >= 1 employee")
	if emp_ids.is_empty():
		return
	var eid: String = emp_ids[0]
	h.assert_result_err(cmd.call("assign_employee_to_station", eid, "station_does_not_exist"), "Invalid station rejected")

	# Put employee on BREAK and try assigning/training concurrently if mutually exclusive
	h.assert_result_ok(cmd.call("rest_employee", eid), "rest_employee")
	var st_id: String = h.get_first_station_id(bs)
	if st_id != "":
		var r_busy: Variant = cmd.call("assign_employee_to_station", eid, st_id)
		h.assert_result_err(r_busy, "Cannot assign resting employee to active station")


func _t2_f3_07_invalid_entity_ids_in_hr_and_queue_commands(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("InvalidIds", 2307)
	if rt.is_empty():
		return
	var cmd: Variant = rt["cmd"]
	h.assert_result_err(cmd.call("hire_candidate", "missing_cand", "teller"), "hire missing candidate")
	h.assert_result_err(cmd.call("fire_employee", "missing_emp"), "fire missing employee")
	h.assert_result_err(cmd.call("train_employee", "missing_emp"), "train missing employee")
	h.assert_result_err(cmd.call("rest_employee", "missing_emp"), "rest missing employee")
	h.assert_result_err(cmd.call("toggle_station_open", "missing_station"), "toggle missing station")
	h.assert_result_err(cmd.call("set_queue_priority", "missing_req", 2), "priority missing request")


func _t2_f3_08_employee_reassignment_and_adaptation_period(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Reassign", 2308)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var st_ids: Array[String] = h.get_station_ids(bs)
	var emp_ids: Array[String] = h.get_employee_ids(bs)
	h.assert_ge(st_ids.size(), 2, "Need >= 2 stations for reassignment test")
	h.assert_ge(emp_ids.size(), 1, "Need >= 1 employee")
	if st_ids.size() < 2 or emp_ids.is_empty():
		return

	var eid: String = emp_ids[0]
	var st_a: String = st_ids[0]
	var st_b: String = st_ids[1]
	var stations: Dictionary = bs.get("stations") as Dictionary
	if not bool((stations[st_a] as Dictionary).get("is_open", true)):
		cmd.call("toggle_station_open", st_a)
	if not bool((stations[st_b] as Dictionary).get("is_open", true)):
		cmd.call("toggle_station_open", st_b)

	h.assert_result_ok(cmd.call("assign_employee_to_station", eid, st_a), "Assign to A")
	h.assert_result_ok(cmd.call("assign_employee_to_station", eid, st_b), "Reassign to B")
	h.assert_ne(str((stations[st_a] as Dictionary).get("assigned_employee_id", "")), eid, "Old station A cleared on reassignment")
	h.assert_eq(str((stations[st_b] as Dictionary).get("assigned_employee_id", "")), eid, "New station B holds employee")
	var emp_obj: Variant = (bs.get("employees") as Dictionary)[eid]
	if emp_obj is Object and h.has_prop(emp_obj, "adaptation_days_remaining"):
		h.assert_ge(int((emp_obj as Object).get("adaptation_days_remaining")), 0, "adaptation_days_remaining tracked cleanly")


# ---------------------------------------------------------------------------
# F4 Boundaries (8)
# ---------------------------------------------------------------------------

func _t2_f4_01_policy_rejected_insufficient_strategy_points(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("PolLowSP", 2401)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var pdef: Dictionary = rt["registry"].call("get_policy_def", "core:policy.prudent_lending") as Dictionary
	var cost: int = int(pdef.get("cost_strategy_points", 1))
	bs.set("strategy_points", maxi(0, cost - 1))
	if cost == 0:
		bs.set("strategy_points", -1)
	h.assert_result_err(cmd.call("adopt_policy", "core:policy.prudent_lending"), "Insufficient strategy_points rejected")
	h.assert_eq((bs.get("adopted_policies") as Array).size(), 0, "adopted_policies remains empty")


func _t2_f4_02_policy_rejected_missing_prerequisite(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("PolPrereq", 2402)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	bs.set("strategy_points", 500)
	h.assert_result_err(rt["cmd"].call("adopt_policy", "core:policy.liquidity_first"), "Tier 2 policy rejected without prerequisite")
	h.assert_result_err(rt["cmd"].call("adopt_policy", "core:policy.customer_trust"), "Tier 3 policy rejected without prerequisite")
	h.assert_eq(int(bs.get("strategy_points")), 500, "strategy_points unchanged")


func _t2_f4_03_mutually_exclusive_policy_branch_rejection(h: Variant) -> void:
	var rt1: Dictionary = h.start_session_and_host("PolExcl1", 2403)
	if rt1.is_empty():
		return
	rt1["bank_state"].set("strategy_points", 500)
	h.assert_result_ok(rt1["cmd"].call("adopt_policy", "core:policy.prudent_lending"), "Adopt conservative")
	h.assert_result_err(rt1["cmd"].call("adopt_policy", "core:policy.high_rate_acquisition"), "Aggressive rejected after conservative")

	var rt2: Dictionary = h.start_session_and_host("PolExcl2", 2404)
	if rt2.is_empty():
		return
	rt2["bank_state"].set("strategy_points", 500)
	h.assert_result_ok(rt2["cmd"].call("adopt_policy", "core:policy.high_rate_acquisition"), "Adopt aggressive")
	h.assert_result_err(rt2["cmd"].call("adopt_policy", "core:policy.prudent_lending"), "Conservative rejected after aggressive")


func _t2_f4_04_duplicate_and_invalid_policy_id_rejection(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("PolDup", 2404)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	bs.set("strategy_points", 500)
	h.assert_result_ok(rt["cmd"].call("adopt_policy", "core:policy.prudent_lending"), "First adopt succeeds")
	var sp1: int = int(bs.get("strategy_points"))
	h.assert_result_err(rt["cmd"].call("adopt_policy", "core:policy.prudent_lending"), "Duplicate adopt rejected")
	h.assert_result_err(rt["cmd"].call("adopt_policy", "core:policy.nonexistent"), "Invalid policy ID rejected")
	h.assert_eq(int(bs.get("strategy_points")), sp1, "strategy_points unchanged on rejected adoptions")
	h.assert_eq((bs.get("adopted_policies") as Array).size(), 1, "No duplicate in adopted_policies")


func _t2_f4_05_department_creation_and_upgrade_boundaries(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("DeptBounds", 2405)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return

	# Drain cash via loan/opex? Instead directly test create on low cash by creating a fresh zero-cash BankState or operating cost
	var bs_low: Variant = h.instantiate_script("res://scripts/domain/bank_state.gd")
	if bs_low != null:
		var sim_low: Variant = h.instantiate_script("res://scripts/app/simulation_host.gd")
		if sim_low != null:
			sim_low.call("bind_session", bs_low, rt["defs"])
			var cmd_low: Variant = (sim_low as Object).get("command_service")
			if cmd_low != null:
				h.assert_result_err(cmd_low.call("create_department", "core:department.operations"), "create_department rejected with 0 cash")

	# Boost cash and test duplicate create, missing upgrade, and max_level cap
	h.invoke_finance_amount_op(fe, "record_deposit", bs, 500_000_000, 1, 540, "cap")
	h.assert_result_err(cmd.call("upgrade_department", "core:department.hr"), "Cannot upgrade uncreated department")
	h.assert_result_ok(cmd.call("create_department", "core:department.operations"), "Create operations Lv.1")
	h.assert_result_err(cmd.call("create_department", "core:department.operations"), "Duplicate create_department rejected")
	h.assert_result_ok(cmd.call("upgrade_department", "core:department.operations"), "Upgrade Lv.2")
	h.assert_result_ok(cmd.call("upgrade_department", "core:department.operations"), "Upgrade Lv.3")
	h.assert_result_err(cmd.call("upgrade_department", "core:department.operations"), "Upgrade beyond max_level=3 rejected")


func _t2_f4_06_locked_unknown_double_event_option_rejection(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("EventBounds", 2406)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var reg: Variant = rt["registry"]
	var ee: Variant = h.instantiate_script("res://scripts/domain/event_engine.gd")
	if ee == null:
		return

	var ev_def: Dictionary = reg.call("get_event_def", "core:event.real_estate_boom") as Dictionary
	var opts: Array = ev_def.get("options", []) as Array
	h.assert_gt(opts.size(), 0, "real_estate_boom must have options")
	if opts.is_empty():
		return

	var inst_id: String = "e2e_ev_bounds_1"
	var tr: Variant = h.trigger_event_safely(ee, bs, "core:event.real_estate_boom", rt["defs"])
	h.assert_result_ok(tr, "EventEngine.trigger_event real_estate_boom")
	var tr_data: Dictionary = h.get_result_data_dict(tr)
	if not tr_data.is_empty():
		inst_id = str(tr_data.get("instance_id", inst_id))

	h.assert_result_err(cmd.call("resolve_event_option", inst_id, "invalid_option_id"), "Unknown option_id rejected")
	var valid_opt: String = str((opts[0] as Dictionary).get("id", ""))
	h.assert_result_ok(cmd.call("resolve_event_option", inst_id, valid_opt), "First resolution succeeds")
	h.assert_result_err(cmd.call("resolve_event_option", inst_id, valid_opt), "Double resolution of same event rejected")


func _t2_f4_07_event_condition_and_cooldown_gating(h: Variant) -> void:
	var ee: Variant = h.instantiate_script("res://scripts/domain/event_engine.gd")
	var bs: Variant = h.instantiate_script("res://scripts/domain/bank_state.gd")
	if ee == null or bs == null:
		return
	var test_event: Dictionary = {
		"id": "com.test:event.gated",
		"title_key": "T",
		"description_key": "D",
		"weight": 100,
		"cooldown_days": 7,
		"conditions": [
			{"type": "day_at_least", "value": 10},
			{"type": "department_exists", "value": "core:department.credit"},
		],
		"options": [{"id": "ok", "label_key": "OK", "effects": []}],
	}
	var checked: bool = false
	for mname in ["is_event_eligible", "can_trigger_event", "check_conditions"]:
		if (ee as Object).has_method(mname):
			checked = true
			bs.set("current_day", 3)
			h.assert_false(bool((ee as Object).call(mname, test_event, bs)), "Event gated on Day 3 without credit dept")
			bs.set("current_day", 10)
			h.assert_false(bool((ee as Object).call(mname, test_event, bs)), "Event still gated on Day 10 without credit dept")
			var depts: Dictionary = bs.get("departments") as Dictionary
			depts["core:department.credit"] = _make_department_instance(h, "core:department.credit", 1)
			h.assert_true(bool((ee as Object).call(mname, test_event, bs)), "Event eligible on Day 10 with credit dept")
			(bs.get("event_history") as Array).append({"event_id": "com.test:event.gated", "day": 10})
			bs.set("current_day", 12)
			h.assert_false(bool((ee as Object).call(mname, test_event, bs)), "Event blocked during 7-day cooldown (Day 12)")
			bs.set("current_day", 17)
			h.assert_true(bool((ee as Object).call(mname, test_event, bs)), "Event eligible again after 7-day cooldown (Day 17)")
			break
	h.assert_true(checked, "EventEngine must expose condition/eligibility check method")


func _t2_f4_08_modifier_service_clamping_and_idempotency(h: Variant) -> void:
	var mod_svc: Variant = h.instantiate_script("res://scripts/domain/modifier_service.gd")
	if mod_svc == null:
		return
	var extreme: Array[Dictionary] = [
		{"target": "loan.default_risk_bps", "operation": "add", "value": 999_999, "scope": "global"},
		{"target": "loan.default_risk_bps", "operation": "multiply", "value": 100_000, "scope": "global"},
	]
	var vals: Array[int] = []
	for _i in range(10):
		var v: Variant = _eval_mod(h, mod_svc, "loan.default_risk_bps", 500, extreme)
		if v != null:
			vals.append(int(v))
	h.assert_eq(vals.size(), 10, "ModifierService evaluated 10 times")
	if vals.size() == 10:
		h.assert_le(vals[0], 10000, "loan.default_risk_bps clamped <= 10000 bps (100%)")
		for v in vals:
			h.assert_eq(v, vals[0], "Repeated evaluations must be idempotent (no compounding)")


# ---------------------------------------------------------------------------
# F5 Boundaries (8)
# ---------------------------------------------------------------------------

func _t2_f5_01_four_level_localization_fallback_chain(h: Variant) -> void:
	var loc: Node = h.get_autoload("LocalizationService")
	if loc == null:
		return
	h.mark_mods_touched()
	loc.call("register_mod_translations", "com.e2e.fb", "ja", {"com.e2e.fb:MOD_JA": "ModJA"})
	loc.call("register_mod_translations", "com.e2e.fb", "en", {"com.e2e.fb:EN_ONLY": "ModENOnly"})
	loc.call("set_locale", "ja")

	h.assert_eq(str(loc.call("tr_key", "com.e2e.fb:MOD_JA")), "ModJA", "Level 1: Mod current locale")
	var vanilla_ja: String = str(loc.call("tr_key", "UI_TOPBAR_DAY"))
	h.assert_ne(vanilla_ja, "UI_TOPBAR_DAY", "Level 2: Vanilla current locale ja")
	h.assert_eq(str(loc.call("tr_key", "com.e2e.fb:EN_ONLY")), "ModENOnly", "Level 3: en fallback when ja missing")
	h.assert_eq(str(loc.call("tr_key", "UNKNOWN_TEST_KEY_404")), "UNKNOWN_TEST_KEY_404", "Level 4: missing key returns raw key")


func _t2_f5_02_mod_forbidden_vanilla_and_peer_key_override(h: Variant) -> void:
	var loc: Node = h.get_autoload("LocalizationService")
	if loc == null:
		return
	h.mark_mods_touched()
	loc.call("set_locale", "en")
	var orig_vanilla: String = str(loc.call("tr_key", "UI_TOPBAR_DAY"))
	loc.call("register_mod_translations", "com.peer.a", "en", {"com.peer.a:KEY": "PeerA"})
	loc.call("register_mod_translations", "com.evil.override", "en", {
		"UI_TOPBAR_DAY": "HACKED",
		"com.peer.a:KEY": "HIJACKED",
	})
	h.assert_eq(str(loc.call("tr_key", "UI_TOPBAR_DAY")), orig_vanilla, "Mod cannot override vanilla translation key")
	h.assert_eq(str(loc.call("tr_key", "com.peer.a:KEY")), "PeerA", "Mod cannot override peer Mod translation key")


func _t2_f5_03_path_traversal_rejection_dir_and_zip(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	if reg == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t2_f5_03")
	# Directory mod with ../../ path traversal
	h.write_json_file(mods_root + "/com.evil.dir/manifest.json", {
		"schema_version": 1,
		"id": "com.evil.dir",
		"name_key": "com.evil.dir:NAME",
		"version": "1.0.0",
		"author": "Evil",
		"content": {"departments": "../../data/departments.json"},
		"asset_dir": "../secrets",
	})
	# ZIP mod with ../../evil.json entry
	h.build_zip_from_entries(mods_root + "/evil_zip.zip", {
		"manifest.json": {
			"schema_version": 1,
			"id": "com.evil.zip",
			"name_key": "com.evil.zip:NAME",
			"version": "1.0.0",
			"author": "Evil",
		},
		"../../evil.json": "{\"bad\":true}",
	})

	var rep: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	var loaded: Array = rep.get("loaded_mods", []) as Array
	var rejected: Array = rep.get("rejected_mods", []) as Array
	h.assert_eq(loaded.size(), 0, "Zero path-traversal mods may load")
	h.assert_ge(rejected.size(), 2, "Both path-traversal mods must appear in rejected_mods")


func _t2_f5_04_malformed_json_schema_violations_non_semver(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	if reg == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t2_f5_04")

	# (a) broken JSON
	h.write_text_file(mods_root + "/com.bad.json/manifest.json", "{broken json")
	# (b) schema_version: 2 & non-semver "1.0"
	h.write_json_file(mods_root + "/com.bad.ver/manifest.json", {
		"schema_version": 2,
		"id": "com.bad.ver",
		"name_key": "X",
		"version": "1.0",
		"author": "Bad",
	})
	# (c) valid manifest but bad department schema (max_level=9, daily_cost_minor=-5, extra prop) + valid sibling
	h.write_json_file(mods_root + "/com.bad.schema/manifest.json", {
		"schema_version": 1,
		"id": "com.bad.schema",
		"name_key": "com.bad.schema:NAME",
		"version": "1.0.0",
		"author": "Bad",
		"content": {"departments": "content/departments.json"},
	})
	h.write_json_file(mods_root + "/com.bad.schema/content/departments.json", [
		{
			"id": "com.bad.schema:department.good_sibling",
			"name_key": "A",
			"description_key": "B",
			"initial_cost_minor": 1000,
			"daily_cost_minor": 100,
			"max_level": 3,
			"effects": [],
		},
		{
			"id": "com.bad.schema:department.bad",
			"name_key": "A",
			"description_key": "B",
			"initial_cost_minor": 1000,
			"daily_cost_minor": -5,
			"max_level": 9,
			"unknown_extra_field": 123,
			"effects": [],
		},
	])

	var rep: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	h.assert_eq((rep.get("loaded_mods", []) as Array).size(), 0, "Invalid mods must not load")
	h.assert_ge((rep.get("rejected_mods", []) as Array).size(), 3, "All 3 invalid mods rejected")
	h.assert_true((reg.call("get_department_def", "com.bad.schema:department.good_sibling") as Dictionary).is_empty(), "Atomic rejection: valid sibling must NOT half-register")


func _t2_f5_05_duplicate_content_ids_vanilla_and_inter_mod(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	if reg == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t2_f5_05")
	# Vanilla override
	h.write_json_file(mods_root + "/com.dup.vanilla/manifest.json", {
		"schema_version": 1, "id": "com.dup.vanilla", "name_key": "N", "version": "1.0.0", "author": "A",
		"content": {"departments": "content/departments.json"},
	})
	h.write_json_file(mods_root + "/com.dup.vanilla/content/departments.json", [{
		"id": "core:department.hr", "name_key": "N", "description_key": "D",
		"initial_cost_minor": 100, "daily_cost_minor": 10, "max_level": 1, "effects": [],
	}])
	# Inter-mod collision (com.dup.b validly uses com.dup.b:*; com.dup.c duplicates com.dup.b:policy.p1)
	for mid in ["com.dup.b", "com.dup.c"]:
		h.write_json_file(mods_root + "/%s/manifest.json" % mid, {
			"schema_version": 1, "id": mid, "name_key": "N", "version": "1.0.0", "author": "A",
			"content": {"policies": "content/policies.json"},
		})
		h.write_json_file(mods_root + "/%s/content/policies.json" % mid, [{
			"id": "com.dup.b:policy.p1", "name_key": mid, "description_key": "D",
			"cost_strategy_points": 1, "effects": [],
		}])

	var rep: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	var rejected: Array = rep.get("rejected_mods", []) as Array
	h.assert_ge(rejected.size(), 2, "Vanilla override and conflicting mod rejected")
	var hr_def: Dictionary = reg.call("get_department_def", "core:department.hr") as Dictionary
	h.assert_gt(int(hr_def.get("initial_cost_minor", 0)), 100, "Vanilla core:department.hr remains intact")


func _t2_f5_06_unsafe_script_eval_non_png_oversized_rejection(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	if reg == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t2_f5_06")
	# Disallowed effect target + eval condition + .gd/.svg files
	h.write_json_file(mods_root + "/com.evil.script/manifest.json", {
		"schema_version": 1, "id": "com.evil.script", "name_key": "N", "version": "1.0.0", "author": "A",
		"content": {"events": "content/events.json"},
		"asset_dir": "assets",
	})
	h.write_text_file(mods_root + "/com.evil.script/evil.gd", "extends RefCounted\nfunc _init(): OS.crash('pwn')\n")
	h.write_text_file(mods_root + "/com.evil.script/assets/icon.svg", "<svg/>")
	h.write_json_file(mods_root + "/com.evil.script/content/events.json", [{
		"id": "com.evil.script:event.pwn",
		"title_key": "T", "description_key": "D", "weight": 10, "cooldown_days": 1,
		"conditions": [{"type": "eval(1+1)", "value": true}],
		"options": [{
			"id": "o1", "label_key": "L",
			"effects": [{"target": "bank.cash_infinite", "operation": "add", "value": 999999, "scope": "global"}],
		}],
	}])

	var rep: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	h.assert_eq((rep.get("loaded_mods", []) as Array).size(), 0, "Unsafe mod must be rejected")
	h.assert_ge((rep.get("rejected_mods", []) as Array).size(), 1, "Unsafe mod recorded in rejected_mods")


func _t2_f5_07_missing_dep_circular_dep_and_conflicts(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	if reg == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t2_f5_07")
	# Missing dep
	h.write_json_file(mods_root + "/com.x.miss/manifest.json", {
		"schema_version": 1, "id": "com.x.miss", "name_key": "N", "version": "1.0.0", "author": "A",
		"dependencies": ["com.missing.dep"],
	})
	# Circular Y <-> Z
	h.write_json_file(mods_root + "/com.y.cyc/manifest.json", {
		"schema_version": 1, "id": "com.y.cyc", "name_key": "N", "version": "1.0.0", "author": "A",
		"dependencies": ["com.z.cyc"],
	})
	h.write_json_file(mods_root + "/com.z.cyc/manifest.json", {
		"schema_version": 1, "id": "com.z.cyc", "name_key": "N", "version": "1.0.0", "author": "A",
		"dependencies": ["com.y.cyc"],
	})
	# Mutual conflict P <-> Q
	h.write_json_file(mods_root + "/com.p.conf/manifest.json", {
		"schema_version": 1, "id": "com.p.conf", "name_key": "N", "version": "1.0.0", "author": "A",
		"conflicts": ["com.q.conf"],
	})
	h.write_json_file(mods_root + "/com.q.conf/manifest.json", {
		"schema_version": 1, "id": "com.q.conf", "name_key": "N", "version": "1.0.0", "author": "A",
		"conflicts": ["com.p.conf"],
	})

	var rep: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	var loaded: Array = rep.get("loaded_mods", []) as Array
	var rejected: Array = rep.get("rejected_mods", []) as Array
	h.assert_false(_has_mod(loaded, "com.x.miss"), "Missing dependency mod rejected")
	h.assert_false(_has_mod(loaded, "com.y.cyc"), "Circular dep Y rejected")
	h.assert_false(_has_mod(loaded, "com.z.cyc"), "Circular dep Z rejected")
	h.assert_false(_has_mod(loaded, "com.p.conf") and _has_mod(loaded, "com.q.conf"), "Conflicting P and Q cannot both load")
	h.assert_ge(rejected.size(), 4, "Missing/cyclic/conflicting mods reported in rejected_mods")


func _t2_f5_08_empty_mods_dir_and_dangling_cross_refs(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	if reg == null:
		return
	var empty_dir: String = h.create_temp_mod_dir("t2_f5_08_empty")
	var rep0: Dictionary = reg.call("reload_all", empty_dir) as Dictionary
	h.assert_eq((rep0.get("errors", ["e"]) as Array).size(), 0, "Empty mods dir loads vanilla with 0 errors")

	var mods_root: String = h.create_temp_mod_dir("t2_f5_08_dangle")
	h.write_json_file(mods_root + "/com.bad.ref/manifest.json", {
		"schema_version": 1, "id": "com.bad.ref", "name_key": "N", "version": "1.0.0", "author": "A",
		"content": {"events": "content/events.json"},
	})
	h.write_json_file(mods_root + "/com.bad.ref/content/events.json", [{
		"id": "com.bad.ref:event.dangling",
		"title_key": "T", "description_key": "D", "weight": 10, "cooldown_days": 5,
		"conditions": [{"type": "department_exists", "value": "com.fake:department.none"}],
		"options": [{"id": "o1", "label_key": "L", "effects": [], "next_event_id": "com.fake:event.none"}],
	}])
	var rep1: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	h.assert_ge((rep1.get("rejected_mods", []) as Array).size(), 1, "Dangling reference mod rejected")


# ---------------------------------------------------------------------------
# F6 Boundaries (7)
# ---------------------------------------------------------------------------

func _t2_f6_01_primary_save_corruption_bak_fallback(h: Variant) -> void:
	var save_svc: Node = h.get_autoload("SaveService")
	if save_svc == null:
		return
	var rt: Dictionary = h.start_session_and_host("BakFallback", 2601)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	bs.set("reputation", 77)
	h.assert_result_ok(save_svc.call("save_slot", "slot_01", bs, {}), "Save v1")
	bs.set("reputation", 99)
	h.assert_result_ok(save_svc.call("save_slot", "slot_01", bs, {}), "Save v2 (rotates v1 to .bak)")

	var slot_path: String = str(save_svc.call("get_slot_path", "slot_01"))
	h.assert_true(h.write_text_file(slot_path, "{truncated_bad_json"), "Corrupt primary slot_01.json")

	var res: Variant = save_svc.call("load_slot", "slot_01")
	h.assert_result_ok(res, "Corrupt primary must recover from .bak")
	var data_v: Variant = (res as Object).get("data") if res is Object else null
	h.assert_true(data_v is Dictionary, "load_slot data must be Dictionary")
	if data_v is Dictionary:
		var data: Dictionary = data_v as Dictionary
		h.assert_true(bool(data.get("used_backup", false)), "used_backup must be true on .bak fallback")
		var restored: Variant = data.get("bank_state")
		h.assert_not_null(restored, "Restored BankState non-null")
		if restored != null:
			h.assert_eq(int(restored.get("reputation")), 77, "Backup preserves prior v1 reputation=77")


func _t2_f6_02_double_corruption_and_missing_slot_load(h: Variant) -> void:
	var save_svc: Node = h.get_autoload("SaveService")
	if save_svc == null:
		return
	var rt: Dictionary = h.start_session_and_host("DoubleCorrupt", 2602)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	h.assert_result_ok(save_svc.call("save_slot", "slot_02", bs, {}), "Save slot_02 v1")
	h.assert_result_ok(save_svc.call("save_slot", "slot_02", bs, {}), "Save slot_02 v2")

	var p2: String = str(save_svc.call("get_slot_path", "slot_02"))
	h.write_text_file(p2, "{corrupt_primary")
	h.write_text_file(p2.replace(".json", ".bak"), "{corrupt_bak")
	h.assert_result_err(save_svc.call("load_slot", "slot_02"), "Double corruption must return failed Result")

	save_svc.call("delete_slot", "slot_03")
	h.assert_result_err(save_svc.call("load_slot", "slot_03"), "Missing slot_03 load must return failed Result")


func _t2_f6_03_missing_mod_dependency_warning_on_load(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	var save_svc: Node = h.get_autoload("SaveService")
	if reg == null or save_svc == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t2_f6_03")
	var src_mod: String = h.get_repo_root_abs().path_join("examples/mod_template")
	h.copy_dir_recursive(src_mod, mods_root + "/com.example.extra_departments")

	var rt: Dictionary = h.start_session_and_host("ModWarn", 2603, mods_root)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	h.invoke_finance_amount_op(fe, "record_deposit", bs, 50_000_000, 1, 540, "cap")
	h.assert_result_ok(rt["cmd"].call("create_department", "com.example.extra_departments:department.research_support"), "Create mod dept")
	h.assert_result_ok(save_svc.call("save_slot", "slot_01", bs, {}), "Save with mod dept")

	# Reload without the mod
	var empty_dir: String = h.create_temp_mod_dir("t2_f6_03_empty")
	reg.call("reload_all", empty_dir)
	var load_res: Variant = save_svc.call("load_slot", "slot_01")
	h.assert_result_ok(load_res, "load_slot still succeeds or reports mod_warnings")
	var data_v: Variant = (load_res as Object).get("data") if load_res is Object else null
	h.assert_true(data_v is Dictionary, "load_slot data must be Dictionary")
	if data_v is Dictionary:
		var data: Dictionary = data_v as Dictionary
		var warnings: Array = data.get("mod_warnings", []) as Array
		h.assert_gt(warnings.size(), 0, "mod_warnings must report missing mod dependency")
		var joined: String = str(warnings)
		h.assert_true(joined.contains("com.example.extra_departments"), "mod_warnings must name missing mod ID")
		var restored: Variant = data.get("bank_state")
		if restored != null:
			var depts_v: Variant = restored.get("departments")
			h.assert_true(depts_v is Dictionary, "Restored departments must be Dictionary")
			if depts_v is Dictionary:
				h.assert_has(depts_v as Dictionary, "com.example.extra_departments:department.research_support", "Unknown mod dept must not be silently purged")


func _t2_f6_04_invalid_slot_id_and_unsupported_save_version(h: Variant) -> void:
	var save_svc: Node = h.get_autoload("SaveService")
	if save_svc == null:
		return
	var rt: Dictionary = h.start_session_and_host("BadSlot", 2604)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	h.assert_result_err(save_svc.call("save_slot", "../../escape", bs, {}), "Path traversal slot_id rejected on save")
	h.assert_result_err(save_svc.call("load_slot", "bad/slot"), "Path separator slot_id rejected on load")

	h.assert_result_ok(save_svc.call("save_slot", "slot_01", bs, {}), "Write baseline slot_01")
	var p1: String = str(save_svc.call("get_slot_path", "slot_01"))
	var parsed: Variant = h.read_json_file(p1)
	h.assert_true(parsed is Dictionary, "Save file is valid JSON Dictionary")
	if parsed is Dictionary:
		var d: Dictionary = parsed as Dictionary
		d["save_version"] = 999
		h.write_json_file(p1, d)
		h.assert_result_err(save_svc.call("load_slot", "slot_01"), "Unsupported save_version=999 must fail")


func _t2_f6_05_invalid_audio_bus_track_and_volume_clamping(h: Variant) -> void:
	var audio: Node = h.get_autoload("AudioService")
	if audio == null:
		return
	audio.call("set_bus_volume", "InvalidBus", 0.5)
	audio.call("set_bus_volume", "SFX", -1.5)
	audio.call("set_bus_volume", "BGM", 4.2)
	audio.call("play_bgm", "missing_bgm", 0.1)
	audio.call("play_sfx", "missing_sfx")
	h.assert_near(float(audio.call("get_bus_volume", "SFX")), 0.0, 0.01, "Negative linear volume clamped to 0.0")
	h.assert_near(float(audio.call("get_bus_volume", "BGM")), 1.0, 0.01, "Excessive linear volume clamped to 1.0")


func _t2_f6_06_game_session_inactive_commands_and_null_safety(h: Variant) -> void:
	var sess: Node = h.get_autoload("GameSession")
	if sess == null:
		return
	sess.call("end_session")
	h.assert_false(bool(sess.get("is_active")), "is_active == false after end_session")
	h.assert_result_err(sess.call("save_to_slot", "slot_01"), "save_to_slot when inactive must fail")
	sess.call("end_session")
	h.assert_false(bool(sess.get("is_active")), "Duplicate end_session is idempotent")


func _t2_f6_07_ui_pause_state_interaction_and_error_feedback(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("PauseAction", 2607)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	h.assert_result_ok(cmd.call("open_branch_for_day"), "open")
	h.assert_result_ok(cmd.call("set_speed", 0), "pause")
	var min0: int = int(bs.get("current_minute_of_day"))

	h.assert_result_ok(cmd.call("set_interest_rates", 220, 680), "Commands remain executable while paused")
	bs.set("strategy_points", 0)
	var bad_pol: Variant = cmd.call("adopt_policy", "core:policy.prudent_lending")
	h.assert_result_err(bad_pol, "Failed paused command returns actionable error")
	rt["sim_host"].call("step_simulation", 2.0)
	h.assert_eq(int(bs.get("current_minute_of_day")), min0, "Simulation remains paused after paused UI/commands")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_camera2d(root: Node) -> Camera2D:
	if root is Camera2D:
		return root as Camera2D
	for c in root.get_children():
		var f: Camera2D = _find_camera2d(c)
		if f != null:
			return f
	return null


func _assert_invalid_path_result(h: Variant, res: Variant, ctx: String) -> void:
	if res is Object and h.has_prop(res, "ok"):
		h.assert_result_err(res, ctx)
	elif res is Array:
		h.assert_true((res as Array).is_empty(), "%s must return empty path" % ctx)
	elif res is PackedVector2Array:
		h.assert_true((res as PackedVector2Array).is_empty(), "%s must return empty path" % ctx)
	else:
		h.assert_true(res == null, "%s returned unexpected valid result" % ctx)


func _invoke_settle(fe: Variant, _nargs: int, bs: Variant, mod_svc: Variant, market_rng: Variant, defs: Dictionary) -> Variant:
	var sig: Dictionary = {}
	if fe is Object:
		for m in (fe as Object).get_method_list():
			if str(m.get("name", "")) == "run_daily_settlement":
				sig = m
				break
	var args: Array = sig.get("args", []) as Array
	var def_args: Array = sig.get("default_args", []) as Array
	var max_args: int = args.size()
	var min_args: int = max_args - def_args.size()
	if max_args >= 4 and min_args <= 4:
		return fe.call("run_daily_settlement", bs, mod_svc, market_rng, defs)
	if max_args >= 3 and min_args <= 3:
		return fe.call("run_daily_settlement", bs, mod_svc, market_rng)
	if max_args >= 2 and min_args <= 2:
		return fe.call("run_daily_settlement", bs, mod_svc)
	return fe.call("run_daily_settlement", bs)


func _strip_gd_comments(src: String) -> String:
	var out_lines: Array[String] = []
	for line in src.split("\n"):
		var in_str: String = ""
		var escaped: bool = false
		var cut_idx: int = -1
		for i in range(line.length()):
			var ch: String = line.substr(i, 1)
			if escaped:
				escaped = false
				continue
			if in_str != "":
				if ch == "\\":
					escaped = true
				elif ch == in_str:
					in_str = ""
			else:
				if ch == "\"" or ch == "'":
					in_str = ch
				elif ch == "#":
					cut_idx = i
					break
		if cut_idx >= 0:
			out_lines.append(line.substr(0, cut_idx))
		else:
			out_lines.append(line)
	return "\n".join(out_lines)


func _get_ledger_entry_count(h: Variant, ledger: Variant) -> int:
	if ledger == null or not (ledger is Object):
		return -1
	var obj: Object = ledger as Object
	if obj.has_method("get_entry_count"):
		return int(obj.call("get_entry_count"))
	if obj.has_method("get_recent_entries"):
		var re: Variant = obj.call("get_recent_entries")
		if re is Array:
			return (re as Array).size()
	if obj.has_method("get_entries"):
		var sig: Dictionary = h.has_method_sig(obj, "get_entries")
		var args: Array = sig.get("args", []) as Array
		var ge: Variant = obj.call("get_entries", 0, 1000) if args.size() >= 2 else obj.call("get_entries")
		if ge is Array:
			return (ge as Array).size()
	if h.has_prop(obj, "entries") and obj.get("entries") is Array:
		return (obj.get("entries") as Array).size()
	if h.has_prop(obj, "journal_entries") and obj.get("journal_entries") is Array:
		return (obj.get("journal_entries") as Array).size()
	if obj.has_method("to_dict"):
		var d: Variant = obj.call("to_dict")
		if d is Dictionary and (d as Dictionary).get("entries") is Array:
			return ((d as Dictionary).get("entries") as Array).size()
	return -1


func _make_department_instance(h: Variant, dept_id: String, lvl: int) -> Variant:
	if ResourceLoader.exists("res://scripts/domain/department_instance.gd"):
		var inst: Variant = h.instantiate_script("res://scripts/domain/department_instance.gd")
		if inst is Object:
			(inst as Object).set("id", dept_id)
			(inst as Object).set("level", lvl)
			return inst
	if ResourceLoader.exists("res://scripts/domain/department_service.gd"):
		var ds_script: GDScript = h.load_script("res://scripts/domain/department_service.gd")
		if ds_script != null:
			var cmap: Dictionary = ds_script.get_script_constant_map()
			if cmap.has("DepartmentInstance") and cmap["DepartmentInstance"] is GDScript:
				var di_script: GDScript = cmap["DepartmentInstance"] as GDScript
				var inst: Variant = di_script.new()
				if inst is Object:
					(inst as Object).set("id", dept_id)
					(inst as Object).set("level", lvl)
					return inst
	return {"id": dept_id, "level": lvl}


func _get_const_or_prop(script: GDScript, cname: String, fallback: int) -> int:
	var consts: Dictionary = script.get_script_constant_map()
	if consts.has(cname):
		return int(consts[cname])
	return fallback


func _enum_val(enums_script: GDScript, enum_name: String, key_name: String, fallback: int) -> int:
	var consts: Dictionary = enums_script.get_script_constant_map()
	if consts.has(enum_name) and consts[enum_name] is Dictionary:
		var ed: Dictionary = consts[enum_name] as Dictionary
		if ed.has(key_name):
			return int(ed[key_name])
	return fallback


func _assert_false_or_err(h: Variant, res: Variant, msg: String) -> void:
	if res is bool:
		h.assert_false(bool(res), msg)
	elif res is Object:
		h.assert_result_err(res, msg)
	else:
		h.fail_test("%s: unexpected return type" % msg)


func _eval_mod(h: Variant, mod_svc: Variant, target: String, base_val: int, effects: Array[Dictionary]) -> Variant:
	var obj: Object = mod_svc as Object
	for mname in ["evaluate_effects", "apply_effects", "compute_target", "resolve_target", "evaluate"]:
		if obj.has_method(mname):
			var sig: Dictionary = h.has_method_sig(obj, mname)
			var max_args: int = (sig.get("args", []) as Array).size()
			var min_args: int = max_args - (sig.get("default_args", []) as Array).size()
			if max_args >= 3 and min_args <= 3:
				return obj.call(mname, target, base_val, effects)
			elif max_args >= 4 and min_args == 4:
				return obj.call(mname, target, base_val, effects, "")
			elif max_args >= 2 and min_args <= 2:
				return obj.call(mname, base_val, effects)
	h.fail_test("ModifierService missing evaluation method")
	return null


func _has_mod(loaded: Array, mod_id: String) -> bool:
	for item in loaded:
		if item is String and str(item) == mod_id:
			return true
		if item is Dictionary and str((item as Dictionary).get("id", "")) == mod_id:
			return true
	return false
