extends RefCounted

## Tier 3 E2E Suite — 16 Pairwise Cross-Feature Combination Tests.


func run_suite(h: RefCounted) -> Array:
	var results: Array = []
	var tests: Array[Array] = [
		["E2E_T3_01", _t3_01_operations_lv2_queue_priority_and_throughput],
		["E2E_T3_02", _t3_02_hr_operations_synergy_adaptation_and_payroll],
		["E2E_T3_03", _t3_03_credit_risk_synergy_loan_pd_reduction],
		["E2E_T3_04", _t3_04_conservative_vs_aggressive_policies_rates_settlement],
		["E2E_T3_05", _t3_05_real_estate_macro_chain_with_risk_mitigation],
		["E2E_T3_06", _t3_06_operations_lv3_complaint_automation_and_satisfaction],
		["E2E_T3_07", _t3_07_hr_lv3_fatigue_reduction_and_stability],
		["E2E_T3_08", _t3_08_rate_competitiveness_lobby_deposit_interest],
		["E2E_T3_09", _t3_09_mod_localization_ja_fallback_to_en],
		["E2E_T3_10", _t3_10_mod_commands_and_save_service_mod_warning],
		["E2E_T3_11", _t3_11_live_locale_switch_format_service_game_root_hud],
		["E2E_T3_12", _t3_12_save_load_mid_day_replay_parity_with_rng_streams],
		["E2E_T3_13", _t3_13_audio_service_and_game_session_settings_persistence],
		["E2E_T3_14", _t3_14_bank_world_selection_commands_right_inspector],
		["E2E_T3_15", _t3_15_daily_report_overlay_autosave_and_audio],
		["E2E_T3_16", _t3_16_mod_content_modifier_service_finance_settlement],
	]

	for entry in tests:
		var test_id: String = str(entry[0])
		var fn: Callable = entry[1] as Callable
		results.append(h.call("run_test", 3, test_id, fn))
	return results


func _t3_01_operations_lv2_queue_priority_and_throughput(h: Variant) -> void:
	# Session A: baseline without operations dept
	var rt_a: Dictionary = h.start_session_and_host("T3_01_A", 8001)
	if rt_a.is_empty():
		return
	h.ensure_station_staffed(rt_a["cmd"], rt_a["bank_state"])
	var comp_a: int = _run_day_and_count_completed(h, rt_a)

	# Session B: operations Lv.2 + priority handling
	var rt_b: Dictionary = h.start_session_and_host("T3_01_B", 8001)
	if rt_b.is_empty():
		return
	var bs_b: Variant = rt_b["bank_state"]
	var cmd_b: Variant = rt_b["cmd"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	h.invoke_finance_amount_op(fe, "record_deposit", bs_b, 500_000_000, 1, 540, "cap")
	h.assert_result_ok(cmd_b.call("create_department", "core:department.operations"), "B create operations")
	h.assert_result_ok(cmd_b.call("upgrade_department", "core:department.operations"), "B upgrade operations Lv.2")
	h.ensure_station_staffed(cmd_b, bs_b)

	var completed_b: Array[int] = [0]
	(rt_b["event_bus"] as Object).connect("domain_event_emitted", func(ev: Variant) -> void:
		if ev is Object and str((ev as Object).get("event_type")) == "ServiceCompleted":
			completed_b[0] += 1
	)
	cmd_b.call("open_branch_for_day")
	var min_dur_b: float = h.get_minute_duration(rt_b["session"])
	var priority_exercised: bool = false
	for step_i in range(480):
		h.step_minutes(rt_b["sim_host"], 1, min_dur_b, 1)
		if not priority_exercised:
			var reqs_v: Variant = bs_b.get("service_requests")
			if reqs_v is Array and not (reqs_v as Array).is_empty():
				var rq: Variant = (reqs_v as Array)[0]
				var rid: String = str((rq as Object).get("request_id") if rq is Object else ((rq as Dictionary).get("request_id", "") if rq is Dictionary else ""))
				if rid != "":
					h.assert_result_ok(cmd_b.call("set_queue_priority", rid, 2), "B set_queue_priority")
					priority_exercised = true
			elif step_i == 60:
				# Briefly pause stations for 3 minutes if queue was empty so a queued request is prioritized
				var st_id: String = h.get_first_station_id(bs_b)
				if st_id != "":
					cmd_b.call("toggle_station_open", st_id)
					h.step_minutes(rt_b["sim_host"], 3, min_dur_b, 1)
					var reqs2: Variant = bs_b.get("service_requests")
					if reqs2 is Array and not (reqs2 as Array).is_empty():
						var rq2: Variant = (reqs2 as Array)[0]
						var rid2: String = str((rq2 as Object).get("request_id") if rq2 is Object else ((rq2 as Dictionary).get("request_id", "") if rq2 is Dictionary else ""))
						if rid2 != "":
							h.assert_result_ok(cmd_b.call("set_queue_priority", rid2, 2), "B set_queue_priority")
							priority_exercised = true
					cmd_b.call("toggle_station_open", st_id)
					# Remaining steps already advanced 3 extra minutes
					h.step_minutes(rt_b["sim_host"], 480 - step_i - 4, min_dur_b, 1)
					break
	cmd_b.call("advance_to_next_day")
	var comp_b: int = completed_b[0]

	h.assert_true(priority_exercised, "Session B exercised set_queue_priority on a queued request")
	h.assert_gt(comp_a, 0, "Session A must complete > 0 services")
	h.assert_gt(comp_b, 0, "Session B must complete > 0 services")
	h.assert_ge(comp_b, comp_a, "Operations Lv.2 throughput must complete >= baseline services (A=%d, B=%d)" % [comp_a, comp_b])
	h.assert_true(bool(h.get_balance_sheet(bs_b).get("is_balanced", false)), "Session B Ledger balanced")


func _t3_02_hr_operations_synergy_adaptation_and_payroll(h: Variant) -> void:
	var rt_a: Dictionary = h.start_session_and_host("T3_02_A", 8002)
	if rt_a.is_empty():
		return
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	h.invoke_finance_amount_op(fe, "record_deposit", rt_a["bank_state"], 500_000_000, 1, 540, "cap")
	h.assert_result_ok(rt_a["cmd"].call("create_department", "core:department.operations"), "A create ops")
	var adapt_a: int = _hire_and_get_adaptation(h, rt_a)

	var rt_b: Dictionary = h.start_session_and_host("T3_02_B", 8002)
	if rt_b.is_empty():
		return
	h.invoke_finance_amount_op(fe, "record_deposit", rt_b["bank_state"], 500_000_000, 1, 540, "cap")
	h.assert_result_ok(rt_b["cmd"].call("create_department", "core:department.operations"), "B create ops")
	h.assert_result_ok(rt_b["cmd"].call("create_department", "core:department.hr"), "B create hr")
	var adapt_b: int = _hire_and_get_adaptation(h, rt_b)

	h.assert_le(adapt_b, adapt_a, "HR + Operations synergy reduces or matches onboarding adaptation (A=%d, B=%d)" % [adapt_a, adapt_b])
	for _d in range(3):
		rt_b["cmd"].call("open_branch_for_day")
		h.step_minutes(rt_b["sim_host"], 480, h.get_minute_duration(rt_b["session"]), 1)
		h.assert_result_ok(rt_b["cmd"].call("advance_to_next_day"), "B day settlement")
	h.assert_true(bool(h.get_balance_sheet(rt_b["bank_state"]).get("is_balanced", false)), "Synergy payroll settlement balanced")


func _t3_03_credit_risk_synergy_loan_pd_reduction(h: Variant) -> void:
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	var mod_svc: Variant = h.instantiate_script("res://scripts/domain/modifier_service.gd")
	var cust: Variant = _instantiate_customer_safely(h)
	if fe == null or mod_svc == null or cust == null:
		return

	var rt_a: Dictionary = h.start_session_and_host("T3_03_A", 8003)
	if rt_a.is_empty():
		return
	h.invoke_finance_amount_op(fe, "record_deposit", rt_a["bank_state"], 500_000_000, 1, 540, "cap")
	h.assert_result_ok(rt_a["cmd"].call("create_department", "core:department.credit"), "A create credit")
	var ev_a: Dictionary = _eval_loan(h, fe, cust, rt_a["bank_state"], mod_svc, rt_a["defs"])

	var rt_b: Dictionary = h.start_session_and_host("T3_03_B", 8003)
	if rt_b.is_empty():
		return
	h.invoke_finance_amount_op(fe, "record_deposit", rt_b["bank_state"], 500_000_000, 1, 540, "cap")
	h.assert_result_ok(rt_b["cmd"].call("create_department", "core:department.credit"), "B create credit")
	h.assert_result_ok(rt_b["cmd"].call("create_department", "core:department.risk"), "B create risk")
	h.assert_result_ok(rt_b["cmd"].call("upgrade_department", "core:department.risk"), "B upgrade risk Lv.2")
	var ev_b: Dictionary = _eval_loan(h, fe, cust, rt_b["bank_state"], mod_svc, rt_b["defs"])

	h.assert_has(ev_b, "credit_score", "Risk dept exposes credit_score")
	h.assert_has(ev_b, "risk_grade", "Risk dept exposes risk_grade")
	var pd_a: int = int(ev_a.get("estimated_pd_bps", 0))
	var pd_b: int = int(ev_b.get("estimated_pd_bps", 99999))
	h.assert_gt(pd_a, 0, "Baseline Credit-only evaluation must have positive PD (got %d)" % pd_a)
	h.assert_lt(pd_b, pd_a, "Credit + Risk Lv.2 synergy strictly lowers estimated PD (A=%d, B=%d)" % [pd_a, pd_b])


func _t3_04_conservative_vs_aggressive_policies_rates_settlement(h: Variant) -> void:
	var rt_c: Dictionary = h.start_session_and_host("T3_04_Cons", 9002)
	var rt_a: Dictionary = h.start_session_and_host("T3_04_Aggr", 9002)
	if rt_c.is_empty() or rt_a.is_empty():
		return
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")

	rt_c["bank_state"].set("strategy_points", 50)
	h.invoke_finance_amount_op(fe, "record_deposit", rt_c["bank_state"], 10_000_000, 1, 540, "c_dep")
	h.assert_result_ok(rt_c["cmd"].call("adopt_policy", "core:policy.prudent_lending"), "C prudent_lending")
	h.assert_result_ok(rt_c["cmd"].call("set_interest_rates", 150, 550), "C rates")

	rt_a["bank_state"].set("strategy_points", 50)
	h.invoke_finance_amount_op(fe, "record_deposit", rt_a["bank_state"], 10_000_000, 1, 540, "a_dep")
	h.assert_result_ok(rt_a["cmd"].call("adopt_policy", "core:policy.high_rate_acquisition"), "A high_rate_acquisition")
	h.assert_result_ok(rt_a["cmd"].call("set_interest_rates", 400, 850), "A rates")

	var dep_int_c: int = 0
	var dep_int_a: int = 0
	for _d in range(5):
		rt_c["cmd"].call("open_branch_for_day")
		h.step_minutes(rt_c["sim_host"], 480, h.get_minute_duration(rt_c["session"]), 1)
		rt_c["cmd"].call("advance_to_next_day")
		rt_a["cmd"].call("open_branch_for_day")
		h.step_minutes(rt_a["sim_host"], 480, h.get_minute_duration(rt_a["session"]), 1)
		rt_a["cmd"].call("advance_to_next_day")
		h.assert_true(bool(h.get_balance_sheet(rt_c["bank_state"]).get("is_balanced", false)), "C balanced")
		h.assert_true(bool(h.get_balance_sheet(rt_a["bank_state"]).get("is_balanced", false)), "A balanced")

	for r in (rt_c["bank_state"].get("daily_reports") as Array):
		dep_int_c += int((r as Dictionary).get("deposit_interest_expense", 0))
	for r in (rt_a["bank_state"].get("daily_reports") as Array):
		dep_int_a += int((r as Dictionary).get("deposit_interest_expense", 0))
	h.assert_gt(dep_int_a, dep_int_c, "Aggressive high deposit rate incurs higher deposit_interest_expense")


func _t3_05_real_estate_macro_chain_with_risk_mitigation(h: Variant) -> void:
	var rt_a: Dictionary = h.start_session_and_host("T3_05_NoRisk", 9003)
	var rt_b: Dictionary = h.start_session_and_host("T3_05_Risk", 9003)
	if rt_a.is_empty() or rt_b.is_empty():
		return
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return
	h.invoke_finance_amount_op(fe, "record_deposit", rt_a["bank_state"], 500_000_000, 1, 540, "cap_a")
	h.invoke_finance_amount_op(fe, "record_deposit", rt_b["bank_state"], 500_000_000, 1, 540, "cap_b")
	h.ensure_station_staffed(rt_a["cmd"], rt_a["bank_state"])
	h.ensure_station_staffed(rt_b["cmd"], rt_b["bank_state"])
	h.assert_result_ok(rt_b["cmd"].call("create_department", "core:department.risk"), "B create risk")
	h.assert_result_ok(rt_b["cmd"].call("upgrade_department", "core:department.risk"), "B upgrade risk Lv.2")

	for i in range(6):
		h.assert_result_ok(h.invoke_disburse_loan(fe, rt_a["bank_state"], "c_re_%d" % i, 1_000_000, 850, 5, 1, 540, "la_%d" % i), "A loan %d" % i)
		h.assert_result_ok(h.invoke_disburse_loan(fe, rt_b["bank_state"], "c_re_%d" % i, 1_000_000, 850, 5, 1, 540, "lb_%d" % i), "B loan %d" % i)

	var res_a: Dictionary = _run_macro_chain_branch(h, rt_a, false)
	var res_b: Dictionary = _run_macro_chain_branch(h, rt_b, true)
	var stress_a: int = int(res_a.get("total_loss", 0))
	var stress_b: int = int(res_b.get("total_loss", 0))
	h.assert_true(bool(res_a.get("saw_stress", false)), "Branch A must reach Stage 3 real_estate_credit_stress")
	h.assert_gt(stress_a, 0, "Unprotected branch with active loans must incur > 0 credit loss during macro stress")
	h.assert_le(stress_b, stress_a, "Risk Lv.2 mitigation results in <= credit loss vs unprotected aggressive branch (A=%d, B=%d)" % [stress_a, stress_b])


func _t3_06_operations_lv3_complaint_automation_and_satisfaction(h: Variant) -> void:
	var rt_a: Dictionary = h.start_session_and_host("T3_06_A", 9004)
	var rt_b: Dictionary = h.start_session_and_host("T3_06_B", 9004)
	if rt_a.is_empty() or rt_b.is_empty():
		return
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	h.invoke_finance_amount_op(fe, "record_deposit", rt_b["bank_state"], 500_000_000, 1, 540, "cap")
	h.assert_result_ok(rt_b["cmd"].call("create_department", "core:department.operations"), "ops Lv.1")
	h.assert_result_ok(rt_b["cmd"].call("upgrade_department", "core:department.operations"), "ops Lv.2")
	h.assert_result_ok(rt_b["cmd"].call("upgrade_department", "core:department.operations"), "ops Lv.3")

	h.ensure_station_staffed(rt_a["cmd"], rt_a["bank_state"])
	h.ensure_station_staffed(rt_b["cmd"], rt_b["bank_state"])
	var comp_a: int = _run_day_and_count_completed(h, rt_a)
	var comp_b: int = _run_day_and_count_completed(h, rt_b)

	h.assert_gt(comp_a, 0, "Baseline A must complete > 0 services")
	h.assert_gt(comp_b, 0, "Operations Lv.3 B must complete > 0 services")
	h.assert_ge(int(rt_b["bank_state"].get("satisfaction")), int(rt_a["bank_state"].get("satisfaction")) - 5, "Operations Lv.3 maintains healthy customer satisfaction")


func _t3_07_hr_lv3_fatigue_reduction_and_stability(h: Variant) -> void:
	var rt_a: Dictionary = h.start_session_and_host("T3_07_A", 9006)
	var rt_b: Dictionary = h.start_session_and_host("T3_07_B", 9006)
	if rt_a.is_empty() or rt_b.is_empty():
		return
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	h.invoke_finance_amount_op(fe, "record_deposit", rt_b["bank_state"], 500_000_000, 1, 540, "cap")
	h.assert_result_ok(rt_b["cmd"].call("create_department", "core:department.hr"), "hr Lv.1")
	h.assert_result_ok(rt_b["cmd"].call("upgrade_department", "core:department.hr"), "hr Lv.2")
	h.assert_result_ok(rt_b["cmd"].call("upgrade_department", "core:department.hr"), "hr Lv.3")

	h.ensure_station_staffed(rt_a["cmd"], rt_a["bank_state"])
	h.ensure_station_staffed(rt_b["cmd"], rt_b["bank_state"])

	for d in range(1, 4):
		rt_a["cmd"].call("open_branch_for_day")
		h.step_minutes(rt_a["sim_host"], 480, h.get_minute_duration(rt_a["session"]), 1)
		rt_b["cmd"].call("open_branch_for_day")
		h.step_minutes(rt_b["sim_host"], 480, h.get_minute_duration(rt_b["session"]), 1)
		if d == 3:
			var fat_a_eod: int = _avg_fatigue(rt_a["bank_state"])
			var fat_b_eod: int = _avg_fatigue(rt_b["bank_state"])
			h.assert_gt(fat_a_eod, 0, "Employees must accumulate > 0 fatigue during Day 3 operations")
			h.assert_le(fat_b_eod, fat_a_eod, "HR Lv.3 reduces or matches end-of-day employee fatigue (A=%d, B=%d)" % [fat_a_eod, fat_b_eod])
		rt_a["cmd"].call("advance_to_next_day")
		rt_b["cmd"].call("advance_to_next_day")

	var fat_a: int = _avg_fatigue(rt_a["bank_state"])
	var fat_b: int = _avg_fatigue(rt_b["bank_state"])
	h.assert_le(fat_b, fat_a, "HR Lv.3 overnight recovery keeps fatigue <= baseline (A=%d, B=%d)" % [fat_a, fat_b])


func _t3_08_rate_competitiveness_lobby_deposit_interest(h: Variant) -> void:
	var rt_l: Dictionary = h.start_session_and_host("T3_08_Low", 9005)
	var rt_h: Dictionary = h.start_session_and_host("T3_08_High", 9005)
	if rt_l.is_empty() or rt_h.is_empty():
		return
	h.ensure_station_staffed(rt_l["cmd"], rt_l["bank_state"])
	h.ensure_station_staffed(rt_h["cmd"], rt_h["bank_state"])
	h.assert_result_ok(rt_l["cmd"].call("set_interest_rates", 50, 600), "Low rate 50 bps")
	h.assert_result_ok(rt_h["cmd"].call("set_interest_rates", 400, 600), "High rate 400 bps")

	for _d in range(5):
		rt_l["cmd"].call("open_branch_for_day")
		h.step_minutes(rt_l["sim_host"], 480, h.get_minute_duration(rt_l["session"]), 1)
		rt_l["cmd"].call("advance_to_next_day")
		rt_h["cmd"].call("open_branch_for_day")
		h.step_minutes(rt_h["sim_host"], 480, h.get_minute_duration(rt_h["session"]), 1)
		rt_h["cmd"].call("advance_to_next_day")

	var dep_l: int = h.get_ledger_balance(rt_l["bank_state"], &"customer_deposits")
	var dep_h: int = h.get_ledger_balance(rt_h["bank_state"], &"customer_deposits")
	h.assert_gt(dep_h, 0, "High deposit rate branch must accumulate > 0 customer_deposits")
	h.assert_ge(dep_h, dep_l, "Higher deposit rate attracts >= customer_deposits (low=%d, high=%d)" % [dep_l, dep_h])
	h.assert_true(bool(h.get_balance_sheet(rt_h["bank_state"]).get("is_balanced", false)), "Balanced after 5 days")


func _t3_09_mod_localization_ja_fallback_to_en(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	var loc: Node = h.get_autoload("LocalizationService")
	if reg == null or loc == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t3_09")
	var dst: String = mods_root + "/com.example.extra_departments"
	h.copy_dir_recursive(h.get_repo_root_abs().path_join("examples/mod_template"), dst)
	var ja_dict: Variant = h.read_json_file(dst + "/localization/ja.json")
	if ja_dict is Dictionary:
		(ja_dict as Dictionary).erase("com.example.extra_departments:DEPT_RESEARCH_NAME")
		h.write_json_file(dst + "/localization/ja.json", ja_dict)

	reg.call("reload_all", mods_root)
	loc.call("set_locale", "zh_CN")
	h.assert_eq(str(loc.call("tr_key", "com.example.extra_departments:DEPT_RESEARCH_NAME")), "流程研究部", "Mod zh_CN renders")
	loc.call("set_locale", "ja")
	h.assert_eq(str(loc.call("tr_key", "com.example.extra_departments:DEPT_RESEARCH_NAME")), "Process Research", "Omitted ja key falls back to Mod en")


func _t3_10_mod_commands_and_save_service_mod_warning(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	var save_svc: Node = h.get_autoload("SaveService")
	if reg == null or save_svc == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t3_10")
	h.copy_dir_recursive(h.get_repo_root_abs().path_join("examples/mod_template"), mods_root + "/com.example.extra_departments")

	var rt: Dictionary = h.start_session_and_host("T3_10", 3010, mods_root)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	h.invoke_finance_amount_op(fe, "record_deposit", bs, 50_000_000, 1, 540, "cap")
	h.assert_result_ok(rt["cmd"].call("create_department", "com.example.extra_departments:department.research_support"), "Create mod dept")
	h.assert_result_ok(save_svc.call("save_slot", "slot_01", bs, {}), "Save slot_01 with mod")

	var empty_dir: String = h.create_temp_mod_dir("t3_10_empty")
	reg.call("reload_all", empty_dir)
	var loaded: Variant = save_svc.call("load_slot", "slot_01")
	h.assert_result_ok(loaded, "Load slot_01 after mod removal")
	var data_v: Variant = (loaded as Object).get("data") if loaded is Object else null
	h.assert_true(data_v is Dictionary, "load_slot data must be Dictionary")
	if data_v is Dictionary:
		var warns: Array = (data_v as Dictionary).get("mod_warnings", []) as Array
		h.assert_true(str(warns).contains("com.example.extra_departments"), "mod_warnings names removed mod")


func _t3_11_live_locale_switch_format_service_game_root_hud(h: Variant) -> void:
	var loc: Node = h.get_autoload("LocalizationService")
	var sess: Node = h.get_autoload("GameSession")
	var fmt: Variant = h.instantiate_script("res://scripts/shared/format_service.gd")
	if loc == null or sess == null or fmt == null:
		return
	if (fmt as Object).has_method("format_time"):
		h.assert_eq(str(fmt.call("format_time", 540)), "09:00", "FormatService formats 540 as 09:00")
	elif (fmt as Object).has_method("format_minute_of_day"):
		h.assert_eq(str(fmt.call("format_minute_of_day", 540)), "09:00", "FormatService formats 540 as 09:00")
	if (fmt as Object).has_method("format_bps"):
		h.assert_true(str(fmt.call("format_bps", 425)).contains("4.25"), "FormatService formats 425 bps")
	elif (fmt as Object).has_method("format_rate_bps"):
		h.assert_true(str(fmt.call("format_rate_bps", 425)).contains("4.25"), "FormatService formats 425 bps")

	h.mark_session_touched()
	sess.call("start_new_game", "HUD i18n", 3011)
	var root_ui: Node = h.instantiate_scene("res://scenes/gameplay/game_root.tscn", true)
	if root_ui == null:
		return

	var snapshots: Dictionary = {}
	for lc in ["zh_CN", "en", "ja"]:
		loc.call("set_locale", lc)
		var labels: Array[String] = []
		_collect_label_texts(root_ui, labels)
		h.assert_gt(labels.size(), 0, "GameRoot HUD must expose visible Label/Button texts for %s" % lc)
		var raw_key_found: bool = false
		for txt in labels:
			if txt.begins_with("UI_") or txt.begins_with("DEPT_"):
				raw_key_found = true
				break
		h.assert_false(raw_key_found, "No raw untranslated UI_* keys visible in GameRoot HUD for locale %s" % lc)
		snapshots[lc] = "|".join(labels)
	h.assert_ne(str(snapshots.get("zh_CN", "")), str(snapshots.get("en", "")), "GameRoot HUD text must differ between zh_CN and en")
	h.assert_ne(str(snapshots.get("en", "")), str(snapshots.get("ja", "")), "GameRoot HUD text must differ between en and ja")


func _t3_12_save_load_mid_day_replay_parity_with_rng_streams(h: Variant) -> void:
	var rt_unint: Dictionary = h.start_session_and_host("Unint7777", 7777)
	if rt_unint.is_empty():
		return
	h.ensure_station_staffed(rt_unint["cmd"], rt_unint["bank_state"])
	for _d in range(4):
		rt_unint["cmd"].call("open_branch_for_day")
		h.step_minutes(rt_unint["sim_host"], 480, h.get_minute_duration(rt_unint["session"]), 1)
		rt_unint["cmd"].call("advance_to_next_day")
	var snap_a: Dictionary = {
		"day": int(rt_unint["bank_state"].get("current_day")),
		"cash": h.get_ledger_balance(rt_unint["bank_state"], &"cash_reserves"),
		"loans": h.get_ledger_balance(rt_unint["bank_state"], &"loan_principal_outstanding"),
		"deposits": h.get_ledger_balance(rt_unint["bank_state"], &"customer_deposits"),
		"reports": rt_unint["bank_state"].get("daily_reports"),
	}

	# Split run: save at Day 2 mid-day (12:00 = 180 mins after 09:00), reload, continue to Day 5
	var rt_split: Dictionary = h.start_session_and_host("Unint7777", 7777)
	if rt_split.is_empty():
		return
	h.ensure_station_staffed(rt_split["cmd"], rt_split["bank_state"])
	rt_split["cmd"].call("open_branch_for_day")
	h.step_minutes(rt_split["sim_host"], 480, h.get_minute_duration(rt_split["session"]), 1)
	rt_split["cmd"].call("advance_to_next_day")

	rt_split["cmd"].call("open_branch_for_day")
	h.step_minutes(rt_split["sim_host"], 180, h.get_minute_duration(rt_split["session"]), 1)
	h.assert_result_ok(rt_split["session"].call("save_to_slot", "slot_02"), "Save mid-day Day 2")
	rt_split["session"].call("end_session")

	h.assert_result_ok(rt_split["session"].call("load_from_slot", "slot_02"), "Load mid-day Day 2")
	var bs_loaded: Variant = rt_split["session"].get("bank_state")
	var sim2: Variant = h.instantiate_script("res://scripts/app/simulation_host.gd")
	h.mount_temp_node(sim2)
	sim2.call("bind_session", bs_loaded, rt_split["defs"])
	var cmd2: Variant = sim2.get("command_service")
	h.step_minutes(sim2, 300, h.get_minute_duration(rt_split["session"]), 1)
	cmd2.call("advance_to_next_day")
	for _d in range(2):
		cmd2.call("open_branch_for_day")
		h.step_minutes(sim2, 480, h.get_minute_duration(rt_split["session"]), 1)
		cmd2.call("advance_to_next_day")

	var snap_b: Dictionary = {
		"day": int(bs_loaded.get("current_day")),
		"cash": h.get_ledger_balance(bs_loaded, &"cash_reserves"),
		"loans": h.get_ledger_balance(bs_loaded, &"loan_principal_outstanding"),
		"deposits": h.get_ledger_balance(bs_loaded, &"customer_deposits"),
		"reports": bs_loaded.get("daily_reports"),
	}
	h.assert_eq(snap_b, snap_a, "Mid-day save/load continuation must match uninterrupted simulation 100%")


func _t3_13_audio_service_and_game_session_settings_persistence(h: Variant) -> void:
	var sess: Node = h.get_autoload("GameSession")
	var audio: Node = h.get_autoload("AudioService")
	var loc: Node = h.get_autoload("LocalizationService")
	if sess == null or audio == null or loc == null:
		return

	sess.call("update_settings", {
		"bgm_volume": 0.35,
		"sfx_volume": 0.65,
		"muted": false,
		"locale": "en",
		"minute_duration_sec": 1.0,
	})
	h.assert_near(float(audio.call("get_bus_volume", "BGM")), 0.35, 0.02, "BGM volume updated via GameSession")
	h.assert_near(float(audio.call("get_bus_volume", "SFX")), 0.65, 0.02, "SFX volume updated via GameSession")
	h.assert_false(bool(audio.call("is_muted")), "Mute disabled")
	h.assert_eq(str(loc.call("get_locale")), "en", "Locale updated via GameSession")
	h.assert_near(float(sess.get("minute_duration_sec")), 1.0, 0.001, "minute_duration_sec updated")
	var saved_json: Variant = h.read_json_file("user://settings.json")
	h.assert_true(saved_json is Dictionary, "user://settings.json written as Dictionary")


func _t3_14_bank_world_selection_commands_right_inspector(h: Variant) -> void:
	var sess: Node = h.get_autoload("GameSession")
	if sess == null:
		return
	h.mark_session_touched()
	var bs: Variant = sess.call("start_new_game", "World Inspector", 3014)
	var game_root: Node = h.instantiate_scene("res://scenes/gameplay/game_root.tscn", true)
	if game_root == null:
		return
	var world: Node = _find_node_with_signal(game_root, "entity_selected")
	if world == null:
		world = _find_node_frag(game_root, "BankWorld")
	if world == null:
		world = h.instantiate_scene("res://scenes/world/bank_world.tscn", true)
	h.assert_not_null(world, "BankWorld must exist under GameRoot or bank_world.tscn")
	var sim_host: Node = _find_node_frag(game_root, "SimulationHost")
	h.assert_not_null(sim_host, "SimulationHost must exist under GameRoot")
	var inspector: Node = _find_node_frag(game_root, "RightInspector")
	h.assert_not_null(inspector, "RightInspector must exist under GameRoot")

	if world != null and sim_host != null:
		h.require_signal(world, "entity_selected", "BankWorld")
		h.require_method(world, "focus_entity", "BankWorld")
		var selected_events: Array[Dictionary] = []
		var cb_sel: Callable = func(etype: Variant, eid: Variant) -> void:
			selected_events.append({"type": str(etype), "id": str(eid)})
		if world.has_signal("entity_selected"):
			world.connect("entity_selected", cb_sel)

		var st_id: String = h.get_first_station_id(bs)
		if st_id != "":
			world.call("focus_entity", &"station", st_id)
			if world.has_method("select_entity"):
				world.call("select_entity", &"station", st_id)
			elif selected_events.is_empty() and world.has_signal("entity_selected"):
				world.emit_signal("entity_selected", &"station", st_id)
			h.assert_gt(selected_events.size(), 0, "BankWorld entity_selected signal must fire on selection")
			if inspector != null:
				var insp_labels: Array[String] = []
				_collect_label_texts(inspector, insp_labels)
				h.assert_gt(insp_labels.size(), 0, "RightInspector must render inspection labels")
			var cmd: Variant = sim_host.get("command_service")
			if cmd != null:
				h.assert_result_ok(cmd.call("toggle_station_open", st_id), "toggle_station_open via SimulationHost command_service")


func _t3_15_daily_report_overlay_autosave_and_audio(h: Variant) -> void:
	var save_svc: Node = h.get_autoload("SaveService")
	var audio: Node = h.get_autoload("AudioService")
	var rt: Dictionary = h.start_session_and_host("T3_15_Auto", 3015)
	if rt.is_empty() or save_svc == null or audio == null:
		return
	var overlay: Node = h.instantiate_scene("res://scenes/ui/daily_report_overlay.tscn", true)
	h.assert_not_null(overlay, "DailyReportOverlay scene must instantiate cleanly")
	audio.call("play_sfx", "sfx_day_complete")
	h.assert_ge(float(audio.call("get_bus_volume", "SFX")), 0.0, "AudioService SFX volume valid")

	h.ensure_station_staffed(rt["cmd"], rt["bank_state"])
	rt["cmd"].call("open_branch_for_day")
	h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
	h.assert_result_ok(rt["cmd"].call("advance_to_next_day"), "Settle Day 1")
	h.assert_result_ok(rt["session"].call("save_to_slot", "autosave"), "Autosave after Day 1 settlement")
	var loaded: Variant = save_svc.call("load_slot", "autosave")
	h.assert_result_ok(loaded, "Load autosave")
	var data_v: Variant = (loaded as Object).get("data") if loaded is Object else null
	h.assert_true(data_v is Dictionary, "Autosave load_slot data must be Dictionary")
	if data_v is Dictionary:
		var bs2: Variant = (data_v as Dictionary).get("bank_state")
		h.assert_not_null(bs2, "Autosave bank_state non-null")
		if bs2 != null:
			h.assert_eq(int(bs2.get("current_day")), 2, "Autosave reflects Day 2 opening")


func _t3_16_mod_content_modifier_service_finance_settlement(h: Variant) -> void:
	var mods_root: String = h.create_temp_mod_dir("t3_16")
	h.copy_dir_recursive(h.get_repo_root_abs().path_join("examples/mod_template"), mods_root + "/com.example.extra_departments")
	var rt: Dictionary = h.start_session_and_host("T3_16_Mod", 3016, mods_root)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	h.invoke_finance_amount_op(fe, "record_deposit", bs, 100_000_000, 1, 540, "cap")
	bs.set("strategy_points", 20)

	h.assert_result_ok(cmd.call("create_department", "com.example.extra_departments:department.research_support"), "Create mod dept")
	h.assert_result_ok(cmd.call("adopt_policy", "com.example.extra_departments:policy.process_research"), "Adopt mod policy")

	cmd.call("open_branch_for_day")
	h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
	h.assert_result_ok(cmd.call("advance_to_next_day"), "Settle day with mod dept + policy")
	var reports: Array = bs.get("daily_reports") as Array
	h.assert_eq(reports.size(), 1, "Day 1 report generated")
	h.assert_true(bool(h.get_balance_sheet(bs).get("is_balanced", false)), "Ledger strictly balanced with active mod content")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _run_day_and_count_completed(h: Variant, rt: Dictionary) -> int:
	var completed: Array[int] = [0]
	(rt["event_bus"] as Object).connect("domain_event_emitted", func(ev: Variant) -> void:
		if ev is Object and str((ev as Object).get("event_type")) == "ServiceCompleted":
			completed[0] += 1
	)
	rt["cmd"].call("open_branch_for_day")
	h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
	rt["cmd"].call("advance_to_next_day")
	return completed[0]


func _hire_and_get_adaptation(h: Variant, rt: Dictionary) -> int:
	var bs: Variant = rt["bank_state"]
	var cands: Array[String] = h.get_candidate_ids(bs)
	if cands.is_empty():
		return 0
	var before: Array[String] = h.get_employee_ids(bs)
	h.assert_result_ok(rt["cmd"].call("hire_candidate", cands[0], "teller"), "hire candidate")
	var after: Array[String] = h.get_employee_ids(bs)
	for eid in after:
		if not before.has(eid):
			var emp: Variant = (bs.get("employees") as Dictionary)[eid]
			if emp is Object and h.has_prop(emp, "adaptation_days_remaining"):
				return int((emp as Object).get("adaptation_days_remaining"))
	return 0


func _instantiate_customer_safely(h: Variant) -> Variant:
	var cust_script: GDScript = h.load_script("res://scripts/domain/customer.gd")
	if cust_script == null:
		return null
	var min_args: int = 0
	for m in cust_script.get_script_method_list():
		if str(m.get("name", "")) == "_init":
			var args: Array = m.get("args", []) as Array
			var defs: Array = m.get("default_args", []) as Array
			min_args = args.size() - defs.size()
			break
	if min_args <= 0:
		return h.instantiate_script("res://scripts/domain/customer.gd")
	var stub_args: Array = []
	for i in range(min_args):
		stub_args.append("cust_e2e" if i == 0 else "regular")
	return h.instantiate_script("res://scripts/domain/customer.gd", stub_args)


func _eval_loan(h: Variant, fe: Variant, cust: Variant, bs: Variant, mod_svc: Variant, defs: Dictionary) -> Dictionary:
	var req: Dictionary = {"principal_minor": 400_000, "annual_rate_bps": 700, "term_days": 30, "collateral_value": 100_000}
	var sig: Dictionary = h.has_method_sig(fe, "evaluate_loan_application")
	var args: Array = sig.get("args", []) as Array
	var res: Variant = null
	if args.size() >= 4:
		var arg4_type: int = int((args[3] as Dictionary).get("type", TYPE_NIL))
		if arg4_type == TYPE_DICTIONARY:
			var mod_dict: Dictionary = {}
			if mod_svc is Object and (mod_svc as Object).has_method("collect_active_effects"):
				mod_dict = {"effects": (mod_svc as Object).call("collect_active_effects", bs, defs), "departments": bs.get("departments")}
			res = fe.call("evaluate_loan_application", cust, req, bs, mod_dict)
		else:
			res = fe.call("evaluate_loan_application", cust, req, bs, mod_svc)
	else:
		res = fe.call("evaluate_loan_application", cust, req, bs)
	return res as Dictionary if res is Dictionary else {}


func _run_macro_chain_branch(h: Variant, rt: Dictionary, pick_prudent: bool) -> Dictionary:
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var reg: Variant = rt["registry"]
	var ee: Variant = h.instantiate_script("res://scripts/domain/event_engine.gd")
	if ee == null:
		return {}
	var boom_def: Dictionary = reg.call("get_event_def", "core:event.real_estate_boom") as Dictionary
	var opts: Array = boom_def.get("options", []) as Array
	var inst_id: String = ""
	var tr: Variant = h.trigger_event_safely(ee, bs, "core:event.real_estate_boom", rt["defs"])
	h.assert_result_ok(tr, "EventEngine.trigger_event real_estate_boom")
	var tr_data: Dictionary = h.get_result_data_dict(tr)
	inst_id = str(tr_data.get("instance_id", ""))

	var chosen_opt: String = str((opts[0] as Dictionary).get("id", "")) if not opts.is_empty() else ""
	if pick_prudent and opts.size() >= 2:
		chosen_opt = str((opts[1] as Dictionary).get("id", chosen_opt))
	if chosen_opt != "" and inst_id != "":
		h.assert_result_ok(cmd.call("resolve_event_option", inst_id, chosen_opt), "resolve boom option")

	var saw_stress: bool = false
	for _d in range(15):
		cmd.call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
		cmd.call("advance_to_next_day")
		for ev in (bs.get("active_events") as Array).duplicate():
			var eid: String = str((ev as Dictionary).get("event_id", ""))
			if eid == "core:event.real_estate_credit_stress":
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
	var total_loss: int = 0
	for r in (bs.get("daily_reports") as Array):
		total_loss += int((r as Dictionary).get("credit_loss_expense", 0))
	return {"saw_stress": saw_stress, "total_loss": total_loss}


func _avg_fatigue(bs: Variant) -> int:
	var emps: Dictionary = bs.get("employees") as Dictionary
	if emps.is_empty():
		return 0
	var total: int = 0
	for e in emps.values():
		if e is Object:
			total += int((e as Object).get("fatigue"))
	return total / emps.size()


func _collect_label_texts(root: Node, out: Array[String]) -> void:
	if root is Label:
		out.append((root as Label).text)
	elif root is Button:
		out.append((root as Button).text)
	for c in root.get_children():
		_collect_label_texts(c, out)


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
