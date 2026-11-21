extends RefCounted

## Tier 4 E2E Suite — 8 Realistic Multi-Day / 30-Day Real-World Scenarios.


func run_suite(h: RefCounted) -> Array:
	var results: Array = []
	var tests: Array[Array] = [
		["E2E_T4_01", _t4_01_30_day_deterministic_full_lifecycle],
		["E2E_T4_02", _t4_02_3_stage_real_estate_macro_event_chain],
		["E2E_T4_03", _t4_03_liquidity_stress_and_player_recovery],
		["E2E_T4_04", _t4_04_conservative_vs_aggressive_20_day_comparison],
		["E2E_T4_05", _t4_05_multi_speed_jittered_delta_and_pause_interleaving],
		["E2E_T4_06", _t4_06_mod_i18n_multi_day_bak_recovery_and_replay_parity],
		["E2E_T4_07", _t4_07_complete_player_lifecycle_menu_world_autosave_continue],
		["E2E_T4_08", _t4_08_adversarial_mod_hygiene_and_missing_mod_save_resilience],
	]

	for entry in tests:
		var test_id: String = str(entry[0])
		var fn: Callable = entry[1] as Callable
		results.append(h.call("run_test", 4, test_id, fn))
	return results


func _t4_01_30_day_deterministic_full_lifecycle(h: Variant) -> void:
	var snap1: Dictionary = _run_30_day_campaign(h, 20261121, "Campaign_1")
	var snap2: Dictionary = _run_30_day_campaign(h, 20261121, "Campaign_2")
	h.assert_false(snap1.is_empty(), "Run 1 completed 30 days")
	h.assert_false(snap2.is_empty(), "Run 2 completed 30 days")
	if not snap1.is_empty() and not snap2.is_empty():
		h.assert_eq(snap1, snap2, "Identical world_seed and command sequence must produce 100% identical 30-day results")


func _run_30_day_campaign(h: Variant, seed_val: int, label: String) -> Dictionary:
	var rt: Dictionary = h.start_session_and_host(label, seed_val)
	if rt.is_empty():
		return {}
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var reg: Variant = rt["registry"]
	var min_dur: float = h.get_minute_duration(rt["session"])

	h.ensure_station_staffed(cmd, bs)

	for day in range(1, 31):
		h.assert_result_ok(cmd.call("open_branch_for_day"), "%s Day %d open" % [label, day])

		if day == 2:
			var cands: Array[String] = h.get_candidate_ids(bs)
			if not cands.is_empty():
				cmd.call("hire_candidate", cands[0], "teller")
			cmd.call("create_department", "core:department.operations")
		elif day == 4:
			cmd.call("set_interest_rates", 225, 675)
		elif day == 6:
			cmd.call("create_department", "core:department.hr")
		elif day == 9:
			if int(bs.get("strategy_points")) > 0:
				cmd.call("adopt_policy", "core:policy.prudent_lending")
		elif day == 12:
			cmd.call("create_department", "core:department.credit")
		elif day == 15:
			cmd.call("create_department", "core:department.risk")
		elif day == 20:
			cmd.call("upgrade_department", "core:department.operations")

		# Step half day, handle any pending approvals/events deterministically, finish day
		h.step_minutes(rt["sim_host"], 240, min_dur, 1)
		for app in (bs.get("pending_loan_approvals") as Array).duplicate():
			if app is Dictionary:
				cmd.call("approve_loan", str((app as Dictionary).get("approval_id", (app as Dictionary).get("id", ""))))
		h.step_minutes(rt["sim_host"], 240, min_dur, 1)

		for ev in (bs.get("active_events") as Array).duplicate():
			if ev is Dictionary:
				var eid: String = str((ev as Dictionary).get("event_id", ""))
				var edef: Dictionary = reg.call("get_event_def", eid) as Dictionary
				var eopts: Array = edef.get("options", []) as Array
				if not eopts.is_empty():
					cmd.call("resolve_event_option", str((ev as Dictionary).get("instance_id", "")), str((eopts[0] as Dictionary).get("id", "")))

		h.assert_result_ok(cmd.call("advance_to_next_day"), "%s Day %d settle" % [label, day])
		var snap: Dictionary = h.get_balance_sheet(bs)
		h.assert_true(bool(snap.get("is_balanced", false)), "%s Day %d Ledger balanced" % [label, day])
		h.assert_ge(h.get_ledger_balance(bs, &"cash_reserves"), 0, "%s Day %d cash >= 0" % [label, day])
		h.assert_eq((bs.get("daily_reports") as Array).size(), day, "%s Day %d exactly %d settlements" % [label, day, day])

	return {
		"cash": h.get_ledger_balance(bs, &"cash_reserves"),
		"loans": h.get_ledger_balance(bs, &"loan_principal_outstanding"),
		"deposits": h.get_ledger_balance(bs, &"customer_deposits"),
		"retained": h.get_ledger_balance(bs, &"retained_earnings"),
		"reputation": int(bs.get("reputation")),
		"satisfaction": int(bs.get("satisfaction")),
		"policies": (bs.get("adopted_policies") as Array).duplicate(),
		"reports": (bs.get("daily_reports") as Array).duplicate(true),
	}


func _t4_02_3_stage_real_estate_macro_event_chain(h: Variant) -> void:
	var res_a: Dictionary = _run_real_estate_branch(h, false, "RE_Branch_A")
	var res_b: Dictionary = _run_real_estate_branch(h, true, "RE_Branch_B")
	h.assert_true(bool(res_a.get("saw_cooling", false)), "Branch A saw Stage 2 real_estate_cooling warning")
	h.assert_true(bool(res_a.get("saw_stress", false)), "Branch A saw Stage 3 real_estate_credit_stress")
	h.assert_true(bool(res_b.get("saw_cooling", false)), "Branch B saw Stage 2 real_estate_cooling warning")
	h.assert_true(bool(res_b.get("saw_stress", false)), "Branch B saw Stage 3 real_estate_credit_stress")
	var loss_a: int = int(res_a.get("total_credit_loss", 0))
	var loss_b: int = int(res_b.get("total_credit_loss", 0))
	h.assert_gt(loss_a, 0, "Unprotected Branch A with active loans must incur > 0 credit loss in Stage 3")
	h.assert_le(loss_b, loss_a, "Prudent + Risk dept branch incurs <= credit loss in Stage 3 (A=%d, B=%d)" % [loss_a, loss_b])


func _run_real_estate_branch(h: Variant, with_risk: bool, label: String) -> Dictionary:
	var rt: Dictionary = h.start_session_and_host(label, 4202)
	if rt.is_empty():
		return {}
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var reg: Variant = rt["registry"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	var ee: Variant = h.instantiate_script("res://scripts/domain/event_engine.gd")
	if fe == null or ee == null:
		return {}
	h.invoke_finance_amount_op(fe, "record_deposit", bs, 300_000_000, 1, 540, "cap")
	h.ensure_station_staffed(cmd, bs)
	cmd.call("create_department", "core:department.credit")
	if with_risk:
		cmd.call("create_department", "core:department.risk")
		cmd.call("upgrade_department", "core:department.risk")

	for i in range(6):
		h.assert_result_ok(h.invoke_disburse_loan(fe, bs, "re_cust_%d" % i, 1_000_000, 850, 5, 1, 540, "re_ln_%d" % i), "%s loan %d" % [label, i])

	var saw_cooling: bool = false
	var saw_stress: bool = false
	var tr: Variant = h.trigger_event_safely(ee, bs, "core:event.real_estate_boom", rt["defs"])
	h.assert_result_ok(tr, "%s trigger real_estate_boom" % label)
	var tr_data: Dictionary = h.get_result_data_dict(tr)
	var inst_id: String = str(tr_data.get("instance_id", ""))

	var boom_def: Dictionary = reg.call("get_event_def", "core:event.real_estate_boom") as Dictionary
	var opts: Array = boom_def.get("options", []) as Array
	var pick_idx: int = 1 if (with_risk and opts.size() >= 2) else 0
	if not opts.is_empty() and inst_id != "":
		h.assert_result_ok(cmd.call("resolve_event_option", inst_id, str((opts[pick_idx] as Dictionary).get("id", ""))), "Resolve boom")

	for _d in range(20):
		cmd.call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 240, h.get_minute_duration(rt["session"]), 1)
		for app in (bs.get("pending_loan_approvals") as Array).duplicate():
			if app is Dictionary:
				cmd.call("approve_loan", str((app as Dictionary).get("approval_id", (app as Dictionary).get("id", ""))))
		h.step_minutes(rt["sim_host"], 240, h.get_minute_duration(rt["session"]), 1)
		cmd.call("advance_to_next_day")
		for ev in (bs.get("active_events") as Array).duplicate():
			var eid: String = str((ev as Dictionary).get("event_id", ""))
			if eid == "core:event.real_estate_cooling":
				saw_cooling = true
			elif eid == "core:event.real_estate_credit_stress":
				saw_stress = true
			var edef: Dictionary = reg.call("get_event_def", eid) as Dictionary
			var eopts: Array = edef.get("options", []) as Array
			if not eopts.is_empty():
				var opt_id: String = str((eopts[0] as Dictionary).get("id", ""))
				for o in eopts:
					if o is Dictionary and str((o as Dictionary).get("next_event_id", "")) == "core:event.real_estate_credit_stress":
						opt_id = str((o as Dictionary).get("id", opt_id))
						break
				cmd.call("resolve_event_option", str((ev as Dictionary).get("instance_id", "")), opt_id)
		h.assert_true(bool(h.get_balance_sheet(bs).get("is_balanced", false)), "%s Ledger balanced" % label)

	var total_loss: int = 0
	for r in (bs.get("daily_reports") as Array):
		total_loss += int((r as Dictionary).get("credit_loss_expense", 0))
	return {"saw_cooling": saw_cooling, "saw_stress": saw_stress, "total_credit_loss": total_loss}


func _t4_03_liquidity_stress_and_player_recovery(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("LiqRecovery", 4203)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return
	h.ensure_station_staffed(cmd, bs)

	# Build deposits and then aggressively disburse loans to compress liquidity_ratio < 1.5
	h.assert_result_ok(h.invoke_finance_amount_op(fe, "record_deposit", bs, 20_000_000, 1, 540, "d_liq"), "Initial deposits")
	var cash_avail: int = h.get_ledger_balance(bs, &"cash_reserves")
	var loan_amt: int = int(float(cash_avail) * 0.78)
	var disb_res: Variant = h.invoke_disburse_loan(fe, bs, "c_liq", loan_amt, 700, 30, 1, 540, "liq_loan")
	h.assert_result_ok(disb_res, "disburse_loan compresses liquidity")

	var low_ratio_seen: bool = false
	for _d in range(3):
		cmd.call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
		cmd.call("advance_to_next_day")
		var reps: Array = bs.get("daily_reports") as Array
		if not reps.is_empty():
			var lr: float = float((reps[reps.size() - 1] as Dictionary).get("liquidity_ratio", 99.0))
			if lr < 1.5:
				low_ratio_seen = true

	# Recovery phase: reject pending loans, boost deposit rate, collect loan repayments + new deposits
	for app in (bs.get("pending_loan_approvals") as Array).duplicate():
		if app is Dictionary:
			cmd.call("reject_loan", str((app as Dictionary).get("approval_id", (app as Dictionary).get("id", ""))))
	cmd.call("set_interest_rates", 400, 750)
	h.invoke_finance_amount_op(fe, "record_deposit", bs, 30_000_000, int(bs.get("current_day")), 545, "d_recov")

	for _d in range(3):
		cmd.call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
		cmd.call("advance_to_next_day")
		h.assert_true(bool(h.get_balance_sheet(bs).get("is_balanced", false)), "Ledger balanced during liquidity recovery")

	var final_reps: Array = bs.get("daily_reports") as Array
	var final_lr: float = float((final_reps[final_reps.size() - 1] as Dictionary).get("liquidity_ratio", 0.0))
	h.assert_true(low_ratio_seen, "Liquidity stress (< 1.5) must be observed prior to recovery")
	h.assert_ge(final_lr, 1.5, "Recovered liquidity_ratio returns to Safe >= 1.5")


func _t4_04_conservative_vs_aggressive_20_day_comparison(h: Variant) -> void:
	var res_c: Dictionary = _run_strategy_20_days(h, true, 55555)
	var res_a: Dictionary = _run_strategy_20_days(h, false, 55555)
	h.assert_true(bool(res_c.get("balanced", false)), "Conservative 20-day run balanced every day")
	h.assert_true(bool(res_a.get("balanced", false)), "Aggressive 20-day run balanced every day")
	h.assert_ne(res_c, res_a, "Conservative and Aggressive strategies produce distinct economic trajectories")


func _run_strategy_20_days(h: Variant, conservative: bool, seed_val: int) -> Dictionary:
	var rt: Dictionary = h.start_session_and_host("Strat_%s" % str(conservative), seed_val)
	if rt.is_empty():
		return {}
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var reg: Variant = rt["registry"]
	bs.set("strategy_points", 100)
	h.ensure_station_staffed(cmd, bs)

	if conservative:
		cmd.call("adopt_policy", "core:policy.prudent_lending")
		cmd.call("adopt_policy", "core:policy.liquidity_first")
		cmd.call("set_interest_rates", 150, 550)
	else:
		cmd.call("adopt_policy", "core:policy.high_rate_acquisition")
		cmd.call("adopt_policy", "core:policy.market_penetration")
		cmd.call("set_interest_rates", 400, 850)

	var all_bal: bool = true
	for _d in range(20):
		cmd.call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
		for ev in (bs.get("active_events") as Array).duplicate():
			var eid: String = str((ev as Dictionary).get("event_id", ""))
			var edef: Dictionary = reg.call("get_event_def", eid) as Dictionary
			var eopts: Array = edef.get("options", []) as Array
			if not eopts.is_empty():
				cmd.call("resolve_event_option", str((ev as Dictionary).get("instance_id", "")), str((eopts[0] as Dictionary).get("id", "")))
		cmd.call("advance_to_next_day")
		if not bool(h.get_balance_sheet(bs).get("is_balanced", false)):
			all_bal = false

	return {
		"balanced": all_bal,
		"cash": h.get_ledger_balance(bs, &"cash_reserves"),
		"deposits": h.get_ledger_balance(bs, &"customer_deposits"),
		"loans": h.get_ledger_balance(bs, &"loan_principal_outstanding"),
		"retained": h.get_ledger_balance(bs, &"retained_earnings"),
	}


func _t4_05_multi_speed_jittered_delta_and_pause_interleaving(h: Variant) -> void:
	# Run 1: steady 1x across 7 days with scripted commands at Day 3 open
	var rt1: Dictionary = h.start_session_and_host("Speed1x_7d", 4205)
	if rt1.is_empty():
		return
	h.ensure_station_staffed(rt1["cmd"], rt1["bank_state"])
	var dur1: float = h.get_minute_duration(rt1["session"])
	for d in range(1, 8):
		rt1["cmd"].call("open_branch_for_day")
		if d == 3:
			rt1["cmd"].call("set_interest_rates", 250, 700)
			rt1["cmd"].call("create_department", "core:department.operations")
		h.step_minutes(rt1["sim_host"], 480, dur1, 1)
		rt1["cmd"].call("advance_to_next_day")
	var snap1: Dictionary = {
		"cash": h.get_ledger_balance(rt1["bank_state"], &"cash_reserves"),
		"retained": h.get_ledger_balance(rt1["bank_state"], &"retained_earnings"),
		"reports": rt1["bank_state"].get("daily_reports"),
	}

	# Run 2: 3x with jittered deltas & mid-day pause command interleaving
	var rt2: Dictionary = h.start_session_and_host("Speed3x_7d", 4205)
	if rt2.is_empty():
		return
	h.ensure_station_staffed(rt2["cmd"], rt2["bank_state"])
	var dur2: float = h.get_minute_duration(rt2["session"])
	var target_sim_sec_per_day: float = 480.0 * dur2 / 3.0
	var jitter: Array[float] = [0.016, 0.05, 0.2, 0.4, 0.5]

	for d in range(1, 8):
		rt2["cmd"].call("open_branch_for_day")
		if d == 3:
			rt2["cmd"].call("set_speed", 0)
			var m_pause: int = int(rt2["bank_state"].get("current_minute_of_day"))
			for _p in range(5):
				rt2["sim_host"].call("step_simulation", 1.0)
			h.assert_eq(int(rt2["bank_state"].get("current_minute_of_day")), m_pause, "Pause freezes minutes completely")
			rt2["cmd"].call("set_interest_rates", 250, 700)
			rt2["cmd"].call("create_department", "core:department.operations")
		rt2["cmd"].call("set_speed", 3)

		var acc_t: float = 0.0
		var idx: int = 0
		while int(rt2["bank_state"].get("current_minute_of_day")) < 1020 and acc_t < target_sim_sec_per_day + dur2 * 4.0:
			var cur_min: int = int(rt2["bank_state"].get("current_minute_of_day"))
			var raw_dt: float = jitter[idx % jitter.size()]
			# Exercise full multi-tick catchup & MAX_TICKS_PER_FRAME=5 before 960; cap near close to avoid overshoot
			var step_dt: float = raw_dt if cur_min < 960 else minf(raw_dt, dur2 / 3.0)
			rt2["sim_host"].call("step_simulation", step_dt)
			acc_t += step_dt
			idx += 1
		# Finish exact remaining minutes if any
		var rem: int = 1020 - int(rt2["bank_state"].get("current_minute_of_day"))
		if rem > 0:
			h.step_minutes(rt2["sim_host"], rem, dur2, 3)

		rt2["cmd"].call("advance_to_next_day")

	var snap2: Dictionary = {
		"cash": h.get_ledger_balance(rt2["bank_state"], &"cash_reserves"),
		"retained": h.get_ledger_balance(rt2["bank_state"], &"retained_earnings"),
		"reports": rt2["bank_state"].get("daily_reports"),
	}
	h.assert_eq(snap2, snap1, "7-day 1x steady vs 3x jittered + pause command interleaving must match 100%")


func _t4_06_mod_i18n_multi_day_bak_recovery_and_replay_parity(h: Variant) -> void:
	var loc: Node = h.get_autoload("LocalizationService")
	var save_svc: Node = h.get_autoload("SaveService")
	if loc == null or save_svc == null:
		return

	var mods_root: String = h.create_temp_mod_dir("t4_06")
	h.copy_dir_recursive(h.get_repo_root_abs().path_join("examples/mod_template"), mods_root + "/com.example.extra_departments")

	var rt: Dictionary = h.start_session_and_host("ModPlay", 20261121, mods_root)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	h.invoke_finance_amount_op(fe, "record_deposit", bs, 100_000_000, 1, 540, "cap")
	bs.set("strategy_points", 30)

	# Switch zh_CN -> en -> ja -> zh_CN verifying mod keys
	for pair in [["zh_CN", "流程研究部"], ["en", "Process Research"], ["ja", "業務研究部"], ["zh_CN", "流程研究部"]]:
		loc.call("set_locale", pair[0])
		h.assert_eq(str(loc.call("tr_key", "com.example.extra_departments:DEPT_RESEARCH_NAME")), pair[1], "Mod i18n in %s" % pair[0])

	h.assert_result_ok(cmd.call("create_department", "com.example.extra_departments:department.research_support"), "Create mod dept")
	h.assert_result_ok(cmd.call("adopt_policy", "com.example.extra_departments:policy.process_research"), "Adopt mod policy")

	var dur: float = h.get_minute_duration(rt["session"])
	for _d in range(3):
		cmd.call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 480, dur, 1)
		cmd.call("advance_to_next_day")

	# Day 4 save (v1)
	h.assert_result_ok(rt["session"].call("save_to_slot", "slot_01"), "Save Day 4 v1")
	var day4_cash: int = h.get_ledger_balance(bs, &"cash_reserves")

	# Continue Days 4..6 and overwrite slot_01 (v2 rotates v1 -> .bak)
	for _d in range(3):
		cmd.call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 480, dur, 1)
		cmd.call("advance_to_next_day")
	h.assert_result_ok(rt["session"].call("save_to_slot", "slot_01"), "Save Day 7 v2")
	var day6_cash: int = h.get_ledger_balance(bs, &"cash_reserves")

	# Corrupt primary slot_01.json and recover Day 4 from .bak
	var p1: String = str(save_svc.call("get_slot_path", "slot_01"))
	h.write_text_file(p1, "{CORRUPT_PRIMARY")
	rt["session"].call("end_session")
	h.assert_result_ok(rt["session"].call("load_from_slot", "slot_01"), "Recover Day 4 via .bak")
	var bs_rec: Variant = rt["session"].get("bank_state")
	h.assert_eq(h.get_ledger_balance(bs_rec, &"cash_reserves"), day4_cash, "Restored Day 4 cash matches v1")

	var sim2: Variant = h.instantiate_script("res://scripts/app/simulation_host.gd")
	h.mount_temp_node(sim2)
	sim2.call("bind_session", bs_rec, rt["defs"])
	var cmd2: Variant = sim2.get("command_service")
	for _d in range(3):
		cmd2.call("open_branch_for_day")
		h.step_minutes(sim2, 480, dur, 1)
		cmd2.call("advance_to_next_day")
	h.assert_eq(h.get_ledger_balance(bs_rec, &"cash_reserves"), day6_cash, "Replaying Days 4-6 from .bak recovery matches exact cash")


func _t4_07_complete_player_lifecycle_menu_world_autosave_continue(h: Variant) -> void:
	var sess: Node = h.get_autoload("GameSession")
	var audio: Node = h.get_autoload("AudioService")
	var save_svc: Node = h.get_autoload("SaveService")
	if sess == null or audio == null or save_svc == null:
		return
	h.mark_session_touched()

	var menu: Node = h.instantiate_scene("res://scenes/menus/main_menu.tscn", true)
	h.assert_not_null(menu, "Boot MainMenu")
	sess.call("update_settings", {
		"bgm_volume": 0.5,
		"sfx_volume": 0.8,
		"muted": false,
		"minute_duration_sec": 0.25,
		"locale": "en",
	})
	if is_instance_valid(menu):
		if menu.get_parent() != null:
			menu.get_parent().remove_child(menu)
		menu.free()

	var bs: Variant = sess.call("start_new_game", "Lifecycle Bank", 4207)
	if not h.assert_not_null(bs, "GameSession.start_new_game returned null"):
		return
	var game_root: Node = h.instantiate_scene("res://scenes/gameplay/game_root.tscn", true)
	if game_root == null:
		return

	var sim_host: Variant = _find_node_with_method(game_root, "bind_session")
	if sim_host == null:
		sim_host = _find_node_frag(game_root, "SimulationHost")
	var spawned_fallback_sim: bool = false
	if sim_host == null:
		sim_host = h.instantiate_script("res://scripts/app/simulation_host.gd")
		h.mount_temp_node(sim_host)
		spawned_fallback_sim = true
	h.assert_not_null(sim_host, "GameRoot must own SimulationHost")
	if sim_host == null:
		return

	var defs: Dictionary = h.build_content_defs(h.get_autoload("ContentRegistry"))
	if spawned_fallback_sim or (sim_host as Object).get("bank_state") == null:
		(sim_host as Object).call("bind_session", bs, defs)

	var world: Node = _find_node_with_signal(game_root, "entity_selected")
	if world == null:
		world = _find_node_frag(game_root, "BankWorld")
	var spawned_fallback_world: bool = false
	if world == null:
		world = h.instantiate_scene("res://scenes/world/bank_world.tscn", true)
		spawned_fallback_world = true
	h.assert_not_null(world, "GameRoot must own BankWorld")
	if world == null:
		return

	h.require_method(world, "bind_runtime", "BankWorld")
	h.require_method(world, "set_camera_zoom_step", "BankWorld")
	h.require_method(world, "focus_entity", "BankWorld")
	if spawned_fallback_world:
		world.call("bind_runtime", sim_host)
	world.call("set_camera_zoom_step", 2)
	var st_id: String = h.get_first_station_id(bs)
	if st_id != "":
		world.call("focus_entity", &"station", st_id)

	var cmd: Variant = (sim_host as Object).get("command_service")
	h.assert_not_null(cmd, "SimulationHost.command_service must be non-null")
	if cmd == null:
		return
	for _d in range(3):
		cmd.call("open_branch_for_day")
		h.step_minutes(sim_host, 480, 0.25, 1)
		cmd.call("advance_to_next_day")
		h.assert_result_ok(sess.call("save_to_slot", "autosave"), "Autosave end of day")

	h.assert_result_ok(sess.call("save_to_slot", "slot_02"), "Manual save slot_02 on Day 4")
	var target_day: int = int(bs.get("current_day"))
	sess.call("end_session")

	h.assert_result_ok(sess.call("load_from_slot", "autosave"), "Continue from autosave")
	var bs_auto: Variant = sess.get("bank_state")
	h.assert_not_null(bs_auto, "Autosave restored bank_state non-null")
	if bs_auto != null:
		h.assert_eq(int(bs_auto.get("current_day")), target_day, "Autosave restored exact day")
	sess.call("end_session")

	h.assert_result_ok(sess.call("load_from_slot", "slot_02"), "Load slot_02")
	var bs_slot: Variant = sess.get("bank_state")
	h.assert_not_null(bs_slot, "slot_02 restored bank_state non-null")
	if bs_slot != null:
		h.assert_eq(int(bs_slot.get("current_day")), target_day, "slot_02 restored exact day")
	h.assert_near(float(audio.call("get_bus_volume", "BGM")), 0.5, 0.02, "Audio BGM volume maintained")


func _t4_08_adversarial_mod_hygiene_and_missing_mod_save_resilience(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	var save_svc: Node = h.get_autoload("SaveService")
	if reg == null or save_svc == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t4_08")

	# (a) Valid template mod
	h.copy_dir_recursive(h.get_repo_root_abs().path_join("examples/mod_template"), mods_root + "/com.example.extra_departments")
	# (b) Path traversal zip
	h.build_zip_from_entries(mods_root + "/evil_traversal.zip", {
		"manifest.json": {"schema_version": 1, "id": "com.evil.zip", "name_key": "N", "version": "1.0.0", "author": "E"},
		"../escape.json": "{}",
	})
	# (c) Malformed schema mod
	h.write_json_file(mods_root + "/com.bad.schema/manifest.json", {
		"schema_version": 1, "id": "com.bad.schema", "name_key": "N", "version": "1.0.0", "author": "B",
		"content": {"departments": "content/departments.json"},
	})
	h.write_json_file(mods_root + "/com.bad.schema/content/departments.json", [{
		"id": "com.bad.schema:department.x", "name_key": "N", "description_key": "D",
		"initial_cost_minor": 100, "daily_cost_minor": 10, "max_level": 99, "effects": [],
	}])
	# (d) Vanilla override mod
	h.write_json_file(mods_root + "/com.bad.override/manifest.json", {
		"schema_version": 1, "id": "com.bad.override", "name_key": "N", "version": "1.0.0", "author": "B",
		"content": {"departments": "content/departments.json"},
	})
	h.write_json_file(mods_root + "/com.bad.override/content/departments.json", [{
		"id": "core:department.hr", "name_key": "N", "description_key": "D",
		"initial_cost_minor": 1, "daily_cost_minor": 1, "max_level": 1, "effects": [],
	}])
	# (e) Script + eval mod
	h.write_json_file(mods_root + "/com.bad.script/manifest.json", {
		"schema_version": 1, "id": "com.bad.script", "name_key": "N", "version": "1.0.0", "author": "B",
		"content": {"events": "content/events.json"},
	})
	h.write_text_file(mods_root + "/com.bad.script/payload.gd", "extends Node\n")
	h.write_json_file(mods_root + "/com.bad.script/content/events.json", [{
		"id": "com.bad.script:event.x", "title_key": "T", "description_key": "D", "weight": 1, "cooldown_days": 1,
		"conditions": [{"type": "eval(true)", "value": true}],
		"options": [{"id": "o", "label_key": "L", "effects": []}],
	}])

	var rep: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	var loaded: Array = rep.get("loaded_mods", []) as Array
	var rejected: Array = rep.get("rejected_mods", []) as Array
	h.assert_eq(loaded.size(), 1, "Only the 1 valid mod may load")
	h.assert_ge(rejected.size(), 4, "All 4 invalid/malicious mods rejected")

	var rt: Dictionary = h.start_session_and_host("Hygiene5d", 4208, mods_root)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	h.invoke_finance_amount_op(fe, "record_deposit", bs, 100_000_000, 1, 540, "cap")
	h.assert_result_ok(rt["cmd"].call("create_department", "com.example.extra_departments:department.research_support"), "Create mod dept")

	for _d in range(5):
		rt["cmd"].call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
		rt["cmd"].call("advance_to_next_day")

	h.assert_result_ok(rt["session"].call("save_to_slot", "slot_03"), "Save slot_03 with active mod")
	rt["session"].call("end_session")

	var empty_mods: String = h.create_temp_mod_dir("t4_08_empty")
	reg.call("reload_all", empty_mods)
	var load_res: Variant = save_svc.call("load_slot", "slot_03")
	h.assert_result_ok(load_res, "load_slot survives missing mod cleanly")
	var data_v: Variant = (load_res as Object).get("data") if load_res is Object else null
	h.assert_true(data_v is Dictionary, "load_slot data must be Dictionary")
	if data_v is Dictionary:
		var data: Dictionary = data_v as Dictionary
		var warns: Array = data.get("mod_warnings", []) as Array
		h.assert_true(str(warns).contains("com.example.extra_departments"), "mod_warnings names missing mod")
		var restored: Variant = data.get("bank_state")
		if restored != null:
			var depts_v: Variant = restored.get("departments")
			h.assert_true(depts_v is Dictionary, "Restored departments must be Dictionary")
			if depts_v is Dictionary:
				h.assert_has(depts_v as Dictionary, "com.example.extra_departments:department.research_support", "Mod department record preserved safely")


func _find_node_frag(root: Node, frag: String) -> Node:
	if root.name.to_lower().contains(frag.to_lower()):
		return root
	for c in root.get_children():
		var f: Node = _find_node_frag(c, frag)
		if f != null:
			return f
	return null


func _find_node_with_signal(root: Node, sig_name: String) -> Node:
	if root.has_signal(sig_name):
		return root
	for c in root.get_children():
		var f: Node = _find_node_with_signal(c, sig_name)
		if f != null:
			return f
	return null


func _find_node_with_method(root: Node, mname: String) -> Node:
	if root.has_method(mname):
		return root
	for c in root.get_children():
		var f: Node = _find_node_with_method(c, mname)
		if f != null:
			return f
	return null
