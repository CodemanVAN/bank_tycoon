extends RefCounted

## Tier 1 E2E Suite — 39 Happy-Path Feature Tests (F1: 6, F2: 7, F3: 7, F4: 7, F5: 6, F6: 6).


func run_suite(h: RefCounted) -> Array:
	var results: Array = []
	var tests: Array[Array] = [
		# F1 (6)
		["E2E_T1_F1_01", _t1_f1_01_project_baseline_and_autoloads],
		["E2E_T1_F1_02", _t1_f1_02_starter_project_untouched_and_adr_sync],
		["E2E_T1_F1_03", _t1_f1_03_pixel_art_assets_and_alpha],
		["E2E_T1_F1_04", _t1_f1_04_audio_assets_and_bus_layout],
		["E2E_T1_F1_05", _t1_f1_05_starway_theme_and_main_menu],
		["E2E_T1_F1_06", _t1_f1_06_bank_world_isogrid_nearest_camera],
		# F2 (7)
		["E2E_T1_F2_01", _t1_f2_01_initial_capital_and_balance_sheet],
		["E2E_T1_F2_02", _t1_f2_02_deposit_and_withdrawal_zero_profit],
		["E2E_T1_F2_03", _t1_f2_03_service_fee_and_operating_cost],
		["E2E_T1_F2_04", _t1_f2_04_loan_evaluation_disburse_repay],
		["E2E_T1_F2_05", _t1_f2_05_round_div_and_daily_interest_formula],
		["E2E_T1_F2_06", _t1_f2_06_daily_settlement_closeout_and_record],
		["E2E_T1_F2_07", _t1_f2_07_interest_rates_and_rng_seed_determinism],
		# F3 (7)
		["E2E_T1_F3_01", _t1_f3_01_open_branch_clock_business_hours],
		["E2E_T1_F3_02", _t1_f3_02_speed_multiplier_equivalence],
		["E2E_T1_F3_03", _t1_f3_03_lobby_customer_full_lifecycle],
		["E2E_T1_F3_04", _t1_f3_04_station_toggle_and_employee_assign],
		["E2E_T1_F3_05", _t1_f3_05_queue_priority_reordering],
		["E2E_T1_F3_06", _t1_f3_06_hire_train_rest_employee_lifecycle],
		["E2E_T1_F3_07", _t1_f3_07_fire_employee_cleanup_and_payroll],
		# F4 (7)
		["E2E_T1_F4_01", _t1_f4_01_create_and_upgrade_operations_dept],
		["E2E_T1_F4_02", _t1_f4_02_all_four_mvp_departments],
		["E2E_T1_F4_03", _t1_f4_03_modifier_service_add_multiply_set],
		["E2E_T1_F4_04", _t1_f4_04_conservative_policy_chain],
		["E2E_T1_F4_05", _t1_f4_05_aggressive_policy_chain],
		["E2E_T1_F4_06", _t1_f4_06_trigger_and_resolve_random_event],
		["E2E_T1_F4_07", _t1_f4_07_event_chaining_real_estate_progression],
		# F5 (6)
		["E2E_T1_F5_01", _t1_f5_01_core_content_registry_and_schemas],
		["E2E_T1_F5_02", _t1_f5_02_localization_default_and_live_switch],
		["E2E_T1_F5_03", _t1_f5_03_parameterized_formatting_and_format_service],
		["E2E_T1_F5_04", _t1_f5_04_valid_directory_mod_loading],
		["E2E_T1_F5_05", _t1_f5_05_valid_zip_mod_and_translations],
		["E2E_T1_F5_06", _t1_f5_06_deterministic_topological_load_order],
		# F6 (6)
		["E2E_T1_F6_01", _t1_f6_01_save_service_slot_roundtrip_and_bak],
		["E2E_T1_F6_02", _t1_f6_02_save_service_autosave_list_delete],
		["E2E_T1_F6_03", _t1_f6_03_audio_service_playback_and_persistence],
		["E2E_T1_F6_04", _t1_f6_04_game_session_lifecycle_and_signals],
		["E2E_T1_F6_05", _t1_f6_05_game_root_hud_and_command_boundary],
		["E2E_T1_F6_06", _t1_f6_06_drawers_modals_and_daily_report_overlay],
	]

	for entry in tests:
		var test_id: String = str(entry[0])
		var fn: Callable = entry[1] as Callable
		results.append(h.call("run_test", 1, test_id, fn))
	return results


# ---------------------------------------------------------------------------
# F1: Baseline, Assets, Theme & World Contracts
# ---------------------------------------------------------------------------

func _t1_f1_01_project_baseline_and_autoloads(h: Variant) -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load("res://project.godot")
	h.assert_eq(err, OK, "res://project.godot must parse cleanly")
	if err != OK:
		return

	var features: Variant = cfg.get_value("application", "config/features", PackedStringArray())
	var feat_str: String = str(features)
	h.assert_true(feat_str.contains("4.7"), "project.godot must target Godot 4.7")
	var render_method: String = str(cfg.get_value("rendering", "renderer/rendering_method", ""))
	h.assert_true(feat_str.contains("GL Compatibility") or render_method == "gl_compatibility", "Renderer must be GL Compatibility")

	h.assert_eq(int(cfg.get_value("display", "window/size/viewport_width", 0)), 1280, "Viewport width must be 1280")
	h.assert_eq(int(cfg.get_value("display", "window/size/viewport_height", 0)), 720, "Viewport height must be 720")
	h.assert_eq(str(cfg.get_value("display", "window/stretch/mode", "")), "canvas_items", "Stretch mode must be canvas_items")
	h.assert_eq(str(cfg.get_value("display", "window/stretch/aspect", "")), "expand", "Stretch aspect must be expand")

	var autoload_keys: PackedStringArray = cfg.get_section_keys("autoload") if cfg.has_section("autoload") else PackedStringArray()
	h.assert_eq(autoload_keys.size(), 5, "project.godot must register exactly 5 Autoloads")
	h.assert_false(autoload_keys.has("SimulationHost"), "SimulationHost must NOT be an Autoload")
	for name in ["LocalizationService", "ContentRegistry", "AudioService", "SaveService", "GameSession"]:
		h.assert_true(autoload_keys.has(name), "Missing Autoload entry in project.godot: %s" % name)
		h.get_autoload(name)


func _t1_f1_02_starter_project_untouched_and_adr_sync(h: Variant) -> void:
	var repo_root: String = h.get_repo_root_abs()
	var starter_dir: String = repo_root.path_join("starter_project")
	h.assert_true(DirAccess.dir_exists_absolute(starter_dir), "starter_project/ must exist")
	h.assert_false(DirAccess.dir_exists_absolute(starter_dir.path_join(".godot")), "starter_project/.godot must not exist")

	var files: Array[String] = h.find_files_recursive(starter_dir)
	var expected_rel: Array[String] = [
		"README.md",
		"project.godot",
		"scenes/boot/main.tscn",
		"scripts/app/main.gd",
		"scripts/autoload/content_registry.gd",
		"scripts/autoload/game_session.gd",
		"scripts/autoload/save_service.gd",
	]
	var actual_rel: Array[String] = []
	for f in files:
		actual_rel.append(f.substr(starter_dir.length() + 1).replace("\\", "/"))
	actual_rel.sort()
	expected_rel.sort()
	h.assert_eq(actual_rel, expected_rel, "starter_project/ must remain strictly unmodified")

	var adr_path: String = repo_root.path_join("docs/12_DECISION_LOG.md")
	var adr_text: String = h.read_text_file(adr_path)
	h.assert_ne(adr_text, "", "docs/12_DECISION_LOG.md must be readable")
	h.assert_true(adr_text.contains("ADR-005"), "12_DECISION_LOG.md must contain ADR-005")
	h.assert_true(adr_text.contains("ADR-006"), "12_DECISION_LOG.md must contain ADR-006")
	h.assert_true(
		adr_text.contains("Starway") or adr_text.contains("#081B36") or adr_text.contains("#1F6FEB"),
		"ADR-005 must reflect Starway modern tech-blue palette"
	)
	h.assert_true(
		adr_text.contains("1280") and adr_text.contains("canvas_items"),
		"ADR-006 must reflect 1280x720 canvas_items stretch"
	)


func _t1_f1_03_pixel_art_assets_and_alpha(h: Variant) -> void:
	var tiles: Array[String] = [
		"res://assets/environment/tile_floor_ivory.png",
		"res://assets/environment/tile_floor_wood.png",
		"res://assets/environment/tile_floor_carpet_blue.png",
		"res://assets/environment/tile_floor_vip.png",
	]
	for tpath in tiles:
		var abs_p: String = ProjectSettings.globalize_path(tpath)
		h.assert_true(FileAccess.file_exists(abs_p), "Missing tile PNG: %s" % tpath)
		if FileAccess.file_exists(abs_p):
			var img := Image.new()
			var ok: int = img.load(abs_p)
			h.assert_eq(ok, OK, "Failed to load tile PNG: %s" % tpath)
			h.assert_eq(img.get_width(), 32, "Tile width must be 32: %s" % tpath)
			h.assert_eq(img.get_height(), 16, "Tile height must be 16: %s" % tpath)
			h.assert_true(img.detect_alpha() != Image.ALPHA_NONE, "Tile must have alpha channel: %s" % tpath)

	var env_props: Array[String] = [
		"res://assets/environment/wall_section_back.png",
		"res://assets/environment/wall_glass_facade.png",
		"res://assets/environment/wall_logo_backdrop.png",
		"res://assets/environment/prop_fountain_sheet.png",
		"res://assets/environment/prop_counter_teller.png",
		"res://assets/environment/prop_desk_loan.png",
		"res://assets/environment/prop_desk_office.png",
		"res://assets/environment/prop_sofa.png",
		"res://assets/environment/prop_plant.png",
		"res://assets/environment/prop_atm.png",
		"res://assets/environment/prop_vault_door.png",
		"res://assets/environment/prop_queue_post.png",
		"res://assets/environment/prop_dept_banner.png",
	]
	for ppath in env_props:
		var abs_p: String = ProjectSettings.globalize_path(ppath)
		h.assert_true(FileAccess.file_exists(abs_p), "Missing environment PNG: %s" % ppath)
		if FileAccess.file_exists(abs_p):
			var img := Image.new()
			h.assert_eq(img.load(abs_p), OK, "Failed to load PNG: %s" % ppath)
			h.assert_gt(img.get_width(), 0, "PNG width > 0: %s" % ppath)

	var char_pngs: Array[String] = h.find_files_recursive("res://assets/characters", ".png")
	var sheets_count: int = 0
	var portraits_count: int = 0
	for cp in char_pngs:
		var img := Image.new()
		if img.load(cp) == OK:
			if img.get_width() == 96 and img.get_height() == 128:
				sheets_count += 1
			elif img.get_width() == 32 and img.get_height() == 32:
				portraits_count += 1
	h.assert_ge(sheets_count, 12, "Must have >= 12 (6 emp + 6 cust) 96x128 character sheets")
	h.assert_ge(portraits_count, 12, "Must have >= 12 32x32 character portraits")

	var icon_pngs: Array[String] = h.find_files_recursive("res://assets/icons", ".png")
	h.assert_ge(icon_pngs.size(), 10, "Must have >= 10 UI/status pixel icons")


func _t1_f1_04_audio_assets_and_bus_layout(h: Variant) -> void:
	h.assert_true(ResourceLoader.exists("res://default_bus_layout.tres"), "Missing res://default_bus_layout.tres")
	if ResourceLoader.exists("res://default_bus_layout.tres"):
		var bus_layout: Resource = ResourceLoader.load("res://default_bus_layout.tres")
		h.assert_not_null(bus_layout, "default_bus_layout.tres must load cleanly")
	h.assert_ge(AudioServer.get_bus_index("Master"), 0, "AudioServer must have Master bus")
	h.assert_ge(AudioServer.get_bus_index("BGM"), 0, "AudioServer must have BGM bus")
	h.assert_ge(AudioServer.get_bus_index("SFX"), 0, "AudioServer must have SFX bus")

	var wavs: Array[String] = [
		"bgm_starway_lobby.wav",
		"sfx_ui_click.wav",
		"sfx_ui_select.wav",
		"sfx_ui_error.wav",
		"sfx_cash_chime.wav",
		"sfx_loan_approve.wav",
		"sfx_loan_reject.wav",
		"sfx_customer_bell.wav",
		"sfx_event_alert.wav",
		"sfx_risk_warning.wav",
		"sfx_day_complete.wav",
		"sfx_upgrade_success.wav",
	]
	for w in wavs:
		var abs_w: String = ProjectSettings.globalize_path("res://assets/audio/" + w)
		h.assert_true(FileAccess.file_exists(abs_w), "Missing audio file: %s" % w)
		if FileAccess.file_exists(abs_w):
			var info: Dictionary = h.parse_wav_header(abs_w)
			h.assert_true(bool(info.get("valid", false)), "Invalid WAV RIFF/WAVE header: %s" % w)
			h.assert_eq(int(info.get("audio_format", 0)), 1, "WAV must be PCM format=1: %s" % w)
			h.assert_eq(int(info.get("bits_per_sample", 0)), 16, "WAV must be 16-bit: %s" % w)
			h.assert_eq(int(info.get("sample_rate", 0)), 44100, "WAV must be 44100Hz: %s" % w)
			h.assert_gt(int(info.get("data_bytes", 0)), 0, "WAV must have non-zero audio data: %s" % w)


func _t1_f1_05_starway_theme_and_main_menu(h: Variant) -> void:
	var theme_script: GDScript = h.load_script("res://scripts/presentation/ui/starway_theme.gd")
	if theme_script == null:
		return

	var built_theme: Variant = null
	var theme_inst: Variant = theme_script.new()
	if theme_inst is Theme:
		built_theme = theme_inst
	elif theme_inst is Object:
		for mname in ["build_theme", "create_theme", "get_theme"]:
			if (theme_inst as Object).has_method(mname):
				built_theme = (theme_inst as Object).call(mname)
				break
	if not (built_theme is Theme):
		for mname in ["build_theme", "create_theme", "get_theme"]:
			for m in theme_script.get_script_method_list():
				if str(m.get("name", "")) == mname:
					built_theme = theme_script.call(mname)
					break
			if built_theme is Theme:
				break
	h.assert_true(built_theme is Theme, "starway_theme.gd must produce a Godot Theme")
	if built_theme is Theme:
		var theme_obj: Theme = built_theme as Theme
		var type_list: PackedStringArray = theme_obj.get_type_list()
		h.assert_gt(type_list.size(), 0, "Starway Theme must define customized control types")
		var theme_colors: Array[Color] = []
		var stylebox_count: int = 0
		for tname in type_list:
			for cname in theme_obj.get_color_list(tname):
				theme_colors.append(theme_obj.get_color(cname, tname))
			for sname in theme_obj.get_stylebox_list(tname):
				var sb: StyleBox = theme_obj.get_stylebox(sname, tname)
				if sb is StyleBoxFlat:
					stylebox_count += 1
					var sbf: StyleBoxFlat = sb as StyleBoxFlat
					theme_colors.append(sbf.bg_color)
					theme_colors.append(sbf.border_color)
		h.assert_gt(stylebox_count, 0, "Starway Theme must configure StyleBoxFlat panel/button styles")
		var starway_tokens: Array[Color] = [
			Color("#081B36"), Color("#0B2D5B"), Color("#1F6FEB"), Color("#2D9CFF"),
			Color("#00C6FF"), Color("#BFE8FF"), Color("#F5F8FF"), Color("#526B8D"),
			Color("#263D5C"), Color("#FFC857"), Color("#35C978"), Color("#E74C3C"),
			Color("#9B8CFF"),
		]
		var matched_tokens: int = 0
		for tok in starway_tokens:
			for tc in theme_colors:
				if absf(tc.r - tok.r) <= 0.02 and absf(tc.g - tok.g) <= 0.02 and absf(tc.b - tok.b) <= 0.02:
					matched_tokens += 1
					break
		h.assert_ge(matched_tokens, 3, "Starway Theme colors/styleboxes must match Starway palette tokens")

	var menu: Node = h.instantiate_scene("res://scenes/menus/main_menu.tscn", true)
	if menu == null:
		return
	h.assert_true(menu is Control, "MainMenu root must be a Control")
	var btn_count: int = _count_nodes_of_type(menu, "BaseButton")
	h.assert_ge(btn_count, 4, "MainMenu must expose New/Continue/Load/Settings/Quit controls")


func _t1_f1_06_bank_world_isogrid_nearest_camera(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Starway World", 20261121)
	if rt.is_empty():
		return
	var world: Node = h.instantiate_scene("res://scenes/world/bank_world.tscn", true)
	if world == null:
		return
	if world is CanvasItem:
		h.assert_eq((world as CanvasItem).texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "BankWorld must use TEXTURE_FILTER_NEAREST")

	h.require_signal(world, "entity_selected", "BankWorld")
	h.require_method(world, "bind_runtime", "BankWorld")
	h.require_method(world, "focus_entity", "BankWorld")
	h.require_method(world, "set_camera_zoom_step", "BankWorld")

	world.call("bind_runtime", rt["sim_host"])
	for step in [1, 2, 3]:
		world.call("set_camera_zoom_step", step)
		var cam: Camera2D = _find_camera2d(world)
		h.assert_not_null(cam, "BankWorld must contain a Camera2D")
		if cam != null:
			h.assert_eq(cam.zoom, Vector2(float(step), float(step)), "Camera zoom step %d must set exact integer zoom" % step)

	var st_id: String = h.get_first_station_id(rt["bank_state"])
	if st_id != "":
		world.call("focus_entity", &"station", st_id)
	h.assert_true(_has_ysort_node(world), "BankWorld must contain a y_sort_enabled layer")


# ---------------------------------------------------------------------------
# F2: Double-Entry Ledger, Finance & Daily Settlement
# ---------------------------------------------------------------------------

func _t1_f2_01_initial_capital_and_balance_sheet(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Starway F2", 20261121)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var snap: Dictionary = h.get_balance_sheet(bs)
	h.assert_true(bool(snap.get("is_balanced", false)), "Initial Ledger balance sheet must be balanced")
	var assets: int = int(snap.get("assets", -1))
	var liab: int = int(snap.get("liabilities", -1))
	var eq: int = int(snap.get("equity", -1))
	var inc: int = int(snap.get("income", -1))
	var exp: int = int(snap.get("expense", -1))
	h.assert_eq(assets, liab + eq + (inc - exp), "Assets must equal Liabilities + Equity + (Income - Expense)")

	var cash: int = h.get_ledger_balance(bs, &"cash_reserves")
	var eq_cap: int = h.get_ledger_balance(bs, &"equity_capital")
	var ret_earn: int = h.get_ledger_balance(bs, &"retained_earnings")
	h.assert_gt(cash, 0, "Initial cash_reserves must be > 0")
	h.assert_eq(eq_cap, cash, "Initial equity_capital must equal initial cash_reserves")
	h.assert_eq(ret_earn, 0, "Initial retained_earnings must be 0")


func _t1_f2_02_deposit_and_withdrawal_zero_profit(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Starway Dep", 101)
	if rt.is_empty():
		return
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return
	var bs: Variant = rt["bank_state"]
	var c0: int = h.get_ledger_balance(bs, &"cash_reserves")
	var d0: int = h.get_ledger_balance(bs, &"customer_deposits")

	var res_dep: Variant = h.invoke_finance_amount_op(fe, "record_deposit", bs, 100_000, 1, 545, "dep_01")
	h.assert_result_ok(res_dep, "record_deposit")
	h.assert_eq(h.get_ledger_balance(bs, &"cash_reserves"), c0 + 100_000, "Deposit increases cash_reserves")
	h.assert_eq(h.get_ledger_balance(bs, &"customer_deposits"), d0 + 100_000, "Deposit increases customer_deposits")
	var snap1: Dictionary = h.get_balance_sheet(bs)
	h.assert_eq(int(snap1.get("income", -1)), 0, "Deposit must have 0 income impact")
	h.assert_eq(int(snap1.get("expense", -1)), 0, "Deposit must have 0 expense impact")
	h.assert_true(bool(snap1.get("is_balanced", false)), "Ledger balanced after deposit")

	var res_wd: Variant = h.invoke_finance_amount_op(fe, "record_withdrawal", bs, 40_000, 1, 550, "wd_01")
	h.assert_result_ok(res_wd, "record_withdrawal")
	h.assert_eq(h.get_ledger_balance(bs, &"cash_reserves"), c0 + 60_000, "Withdrawal reduces cash_reserves")
	h.assert_eq(h.get_ledger_balance(bs, &"customer_deposits"), d0 + 60_000, "Withdrawal reduces customer_deposits")
	var snap2: Dictionary = h.get_balance_sheet(bs)
	h.assert_eq(int(snap2.get("expense", -1)), 0, "Withdrawal must NOT be booked as an expense")
	h.assert_true(bool(snap2.get("is_balanced", false)), "Ledger balanced after withdrawal")


func _t1_f2_03_service_fee_and_operating_cost(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Starway Fee", 102)
	if rt.is_empty():
		return
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return
	var bs: Variant = rt["bank_state"]
	var c0: int = h.get_ledger_balance(bs, &"cash_reserves")

	h.assert_result_ok(h.invoke_finance_amount_op(fe, "record_service_fee", bs, 2_500, 1, 560, "fee_01"), "record_service_fee")
	h.assert_result_ok(h.invoke_finance_amount_op(fe, "record_operating_cost", bs, 1_000, 1, 565, "opex_01"), "record_operating_cost")

	h.assert_eq(h.get_ledger_balance(bs, &"fee_income"), 2_500, "fee_income must equal 2500")
	h.assert_eq(h.get_ledger_balance(bs, &"operating_expense"), 1_000, "operating_expense must equal 1000")
	h.assert_eq(h.get_ledger_balance(bs, &"cash_reserves"), c0 + 1_500, "Net cash change must equal +1500")
	h.assert_true(bool(h.get_balance_sheet(bs).get("is_balanced", false)), "Ledger balanced after fee & opex")


func _t1_f2_04_loan_evaluation_disburse_repay(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Starway Loan", 103)
	if rt.is_empty():
		return
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	var mod_svc: Variant = h.instantiate_script("res://scripts/domain/modifier_service.gd")
	var cust: Variant = h.instantiate_script("res://scripts/domain/customer.gd")
	if fe == null or mod_svc == null or cust == null:
		return
	var bs: Variant = rt["bank_state"]

	h.require_method(fe, "evaluate_loan_application", "FinanceEngine")
	var loan_req: Dictionary = {
		"principal_minor": 500_000,
		"annual_rate_bps": 700,
		"term_days": 30,
		"collateral_value": 250_000,
	}
	var eval_res: Variant = _call_eval_loan(fe, cust, loan_req, bs, mod_svc)
	h.assert_true(eval_res is Dictionary, "evaluate_loan_application must return Dictionary")
	if eval_res is Dictionary:
		var ev: Dictionary = eval_res as Dictionary
		var score: int = int(ev.get("credit_score", -1))
		h.assert_true(score >= 0 and score <= 100, "credit_score must be in [0, 100]")
		h.assert_has(ev, "risk_grade", "Evaluation must include risk_grade")
		h.assert_ge(int(ev.get("estimated_pd_bps", -1)), 0, "estimated_pd_bps must be >= 0")
		h.assert_has(ev, "recommended_action", "Evaluation must include recommended_action")

	var c0: int = h.get_ledger_balance(bs, &"cash_reserves")
	var l0: int = h.get_ledger_balance(bs, &"loan_principal_outstanding")
	var loans_v: Variant = bs.get("loans")
	var loans_before: Array = (loans_v as Dictionary).keys().duplicate() if loans_v is Dictionary else []

	var disb: Variant = h.invoke_disburse_loan(fe, bs, "cust_e2e_1", 500_000, 700, 30)
	h.assert_result_ok(disb, "disburse_loan")
	h.assert_eq(h.get_ledger_balance(bs, &"cash_reserves"), c0 - 500_000, "Loan disbursement reduces cash")
	h.assert_eq(h.get_ledger_balance(bs, &"loan_principal_outstanding"), l0 + 500_000, "Loan disbursement increases loan asset")
	h.assert_eq(int(h.get_balance_sheet(bs).get("income", -1)), 0, "Loan principal disbursement is NOT income")

	var created_loan_id: String = _extract_created_loan_id(disb, bs, loans_before)
	h.assert_ne(created_loan_id, "", "disburse_loan must produce a valid loan_id in BankState.loans or Result.data")
	if created_loan_id == "":
		return

	var rep: Variant = h.invoke_repay_loan(fe, bs, created_loan_id, 100_000)
	h.assert_result_ok(rep, "record_loan_repayment")
	h.assert_eq(h.get_ledger_balance(bs, &"cash_reserves"), c0 - 400_000, "Loan repayment increases cash")
	h.assert_eq(h.get_ledger_balance(bs, &"loan_principal_outstanding"), l0 + 400_000, "Loan repayment decreases loan asset")
	h.assert_true(bool(h.get_balance_sheet(bs).get("is_balanced", false)), "Ledger balanced after loan disburse & repay")


func _t1_f2_05_round_div_and_daily_interest_formula(h: Variant) -> void:
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return
	h.require_method(fe, "round_div", "FinanceEngine")
	h.assert_eq(int(fe.call("round_div", 1, 2)), 1, "round_div(1, 2) half-up must be 1")
	h.assert_eq(int(fe.call("round_div", 5, 2)), 3, "round_div(5, 2) half-up must be 3")
	h.assert_eq(int(fe.call("round_div", 4, 2)), 2, "round_div(4, 2) must be 2")

	var rt: Dictionary = h.start_session_and_host("Starway Interest", 104)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var mod_svc: Variant = h.instantiate_script("res://scripts/domain/modifier_service.gd")
	if mod_svc == null:
		return

	h.assert_result_ok(rt["cmd"].call("set_interest_rates", 200, 730), "set_interest_rates(200, 730)")
	h.assert_result_ok(h.invoke_finance_amount_op(fe, "record_deposit", bs, 10_000_000, 1, 540, "dep_int"), "record_deposit")
	var disb: Variant = h.invoke_disburse_loan(fe, bs, "cust_int", 10_000_000, 730, 30)
	h.assert_result_ok(disb, "disburse_loan")

	var res: Variant = _call_daily_settlement(fe, bs, mod_svc, rt["defs"])
	h.assert_result_ok(res, "run_daily_settlement")
	if h.is_result_ok(res):
		var rec_v: Variant = (res as Object).get("data")
		h.assert_true(rec_v is Dictionary, "run_daily_settlement data must be Dictionary")
		if rec_v is Dictionary:
			var rec: Dictionary = rec_v as Dictionary
			var exp_loan_int: int = int(fe.call("round_div", 10_000_000 * 730, 10_000 * 365))
			var exp_dep_int: int = int(fe.call("round_div", 10_000_000 * 200, 10_000 * 365))
			h.assert_eq(int(rec.get("loan_interest_income", -1)), exp_loan_int, "Loan interest must match daily formula")
			h.assert_eq(int(rec.get("deposit_interest_expense", -1)), exp_dep_int, "Deposit interest must match daily formula")
			h.assert_eq(int(rec.get("net_interest_income", -999999)), exp_loan_int - exp_dep_int, "NII = loan_int - dep_int")
			h.assert_true(bool(h.get_balance_sheet(bs).get("is_balanced", false)), "Ledger balanced after interest settlement")


func _t1_f2_06_daily_settlement_closeout_and_record(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Starway Settle", 105)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return

	h.invoke_finance_amount_op(fe, "record_deposit", bs, 500_000, 1, 550, "d_settle")
	h.invoke_disburse_loan(fe, bs, "cust_settle", 300_000, 700, 30)
	h.invoke_finance_amount_op(fe, "record_service_fee", bs, 15_000, 1, 600, "f_settle")

	h.assert_result_ok(cmd.call("open_branch_for_day"), "open_branch_for_day")
	h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
	var adv_res: Variant = cmd.call("advance_to_next_day")
	h.assert_result_ok(adv_res, "advance_to_next_day")

	var reports_v: Variant = bs.get("daily_reports")
	h.assert_true(reports_v is Array, "daily_reports must be Array")
	if reports_v is Array:
		var reports: Array = reports_v as Array
		h.assert_eq(reports.size(), 1, "daily_reports must have 1 record after Day 1 settlement")
		if not reports.is_empty() and reports[0] is Dictionary:
			var rec: Dictionary = reports[0] as Dictionary
			h.assert_eq(int(rec.get("day", 0)), 1, "DailySettlementRecord day must be 1")
			for req_k in ["loan_interest_income", "deposit_interest_expense", "net_interest_income", "fee_income", "staff_cost", "facility_cost", "credit_loss_expense", "net_profit", "liquidity_ratio", "npl_ratio"]:
				h.assert_has(rec, req_k, "DailySettlementRecord missing key: %s" % req_k)

	var snap: Dictionary = h.get_balance_sheet(bs)
	h.assert_true(bool(snap.get("is_balanced", false)), "Ledger must stay balanced post-closeout")
	h.assert_eq(int(snap.get("income", -1)), 0, "Temporary income closed into retained_earnings")
	h.assert_eq(int(snap.get("expense", -1)), 0, "Temporary expense closed into retained_earnings")


func _t1_f2_07_interest_rates_and_rng_seed_determinism(h: Variant) -> void:
	var rt1: Dictionary = h.start_session_and_host("RNG_A", 424242)
	if rt1.is_empty():
		return
	var bs1: Variant = rt1["bank_state"]
	h.assert_result_ok(rt1["cmd"].call("set_interest_rates", 250, 650), "set_interest_rates(250, 650)")
	h.assert_eq(int(bs1.get("deposit_rate_bps")), 250, "deposit_rate_bps updated to 250")
	h.assert_eq(int(bs1.get("loan_base_rate_bps")), 650, "loan_base_rate_bps updated to 650")

	var rng1: Variant = bs1.get("rng_streams")
	h.assert_not_null(rng1, "BankState.rng_streams must not be null")
	if rng1 == null:
		return
	var seq1: Array = _sample_rng_streams(rng1, 10)
	h.assert_gt(seq1.size(), 0, "Sampled RngStreams sequence must be non-empty")
	var rng_dict_v: Variant = (rng1 as Object).call("to_dict")
	h.assert_true(rng_dict_v is Dictionary, "RngStreams.to_dict must return Dictionary")
	if not (rng_dict_v is Dictionary):
		return
	var rng_dict: Dictionary = rng_dict_v as Dictionary
	var rng_script: GDScript = h.load_script("res://scripts/domain/rng_streams.gd")
	if rng_script == null:
		return
	var restored_res: Variant = rng_script.call("from_dict", rng_dict)
	var rng1_restored: Variant = null
	if restored_res is Object:
		var ok_v: Variant = (restored_res as Object).get("ok")
		if typeof(ok_v) == TYPE_BOOL:
			if bool(ok_v):
				rng1_restored = (restored_res as Object).get("data")
		else:
			rng1_restored = restored_res
	h.assert_not_null(rng1_restored, "RngStreams.from_dict must return/succeed with non-null RngStreams")
	if rng1_restored != null:
		var seq1_after: Array = _sample_rng_streams(rng1_restored, 5)
		var seq1_cont: Array = _sample_rng_streams(rng1, 5)
		h.assert_gt(seq1_after.size(), 0, "Restored RngStreams must produce non-empty samples")
		h.assert_eq(seq1_after, seq1_cont, "RngStreams to_dict/from_dict must preserve exact sequence")

	var rt2: Dictionary = h.start_session_and_host("RNG_B", 424242)
	if rt2.is_empty():
		return
	var seq2: Array = _sample_rng_streams(rt2["bank_state"].get("rng_streams"), 10)
	h.assert_eq(seq1, seq2, "Identical world_seed must produce identical RngStreams sequences")


# ---------------------------------------------------------------------------
# F3: Lobby Simulation, Clock, Dispatcher & Entities
# ---------------------------------------------------------------------------

func _t1_f3_01_open_branch_clock_business_hours(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Clock Test", 301)
	if rt.is_empty():
		return
	var cmd: Variant = rt["cmd"]
	var bs: Variant = rt["bank_state"]
	var sim_host: Variant = rt["sim_host"]
	var bus: Variant = rt["event_bus"]

	var events_seen: Array[StringName] = []
	if (bus as Object).has_signal("domain_event_emitted"):
		(bus as Object).connect("domain_event_emitted", func(ev: Variant) -> void:
			if ev is Object:
				events_seen.append(StringName(str((ev as Object).get("event_type"))))
		)

	h.assert_result_ok(cmd.call("open_branch_for_day"), "open_branch_for_day")
	h.assert_eq(int(bs.get("current_minute_of_day")), 540, "Branch opens at 09:00 (minute 540)")
	h.assert_result_ok(cmd.call("set_speed", 1), "set_speed(1)")

	var min_dur: float = h.get_minute_duration(rt["session"])
	h.step_minutes(sim_host, 60, min_dur, 1)
	h.assert_eq(int(bs.get("current_minute_of_day")), 600, "60 single-minute steps advance clock to 10:00 (600)")


func _t1_f3_02_speed_multiplier_equivalence(h: Variant) -> void:
	var rt_a: Dictionary = h.start_session_and_host("Speed 1x", 77777)
	if rt_a.is_empty():
		return
	h.ensure_station_staffed(rt_a["cmd"], rt_a["bank_state"])
	h.assert_result_ok(rt_a["cmd"].call("open_branch_for_day"), "A open")
	h.assert_result_ok(rt_a["cmd"].call("set_speed", 1), "A speed 1")
	h.step_minutes(rt_a["sim_host"], 480, h.get_minute_duration(rt_a["session"]), 1)
	h.assert_result_ok(rt_a["cmd"].call("advance_to_next_day"), "A settle")
	var snap_a: Dictionary = _capture_economic_snapshot(h, rt_a["bank_state"])
	var minute_a: int = int(rt_a["bank_state"].get("current_minute_of_day"))

	var rt_b: Dictionary = h.start_session_and_host("Speed 3x", 77777)
	if rt_b.is_empty():
		return
	h.ensure_station_staffed(rt_b["cmd"], rt_b["bank_state"])
	h.assert_result_ok(rt_b["cmd"].call("open_branch_for_day"), "B open")
	h.assert_result_ok(rt_b["cmd"].call("set_speed", 3), "B speed 3")
	h.step_minutes(rt_b["sim_host"], 480, h.get_minute_duration(rt_b["session"]), 3)
	h.assert_result_ok(rt_b["cmd"].call("advance_to_next_day"), "B settle")
	var snap_b: Dictionary = _capture_economic_snapshot(h, rt_b["bank_state"])
	var minute_b: int = int(rt_b["bank_state"].get("current_minute_of_day"))

	h.assert_eq(minute_a, minute_b, "1x and 3x must reach identical minute_of_day")
	h.assert_eq(snap_a, snap_b, "1x and 3x must produce identical economic & ledger outcomes")


func _t1_f3_03_lobby_customer_full_lifecycle(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Lobby Loop", 303)
	if rt.is_empty():
		return
	var staffed: Dictionary = h.ensure_station_staffed(rt["cmd"], rt["bank_state"])
	h.assert_false(staffed.is_empty(), "Initial BankState must have at least 1 station and 1 employee")

	var event_counts: Dictionary = {}
	var bus: Variant = rt["event_bus"]
	if (bus as Object).has_signal("domain_event_emitted"):
		(bus as Object).connect("domain_event_emitted", func(ev: Variant) -> void:
			if ev is Object:
				var et: String = str((ev as Object).get("event_type"))
				event_counts[et] = int(event_counts.get(et, 0)) + 1
		)

	h.assert_result_ok(rt["cmd"].call("open_branch_for_day"), "open_branch_for_day")
	h.assert_result_ok(rt["cmd"].call("set_speed", 1), "set_speed(1)")
	h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)

	h.assert_gt(int(event_counts.get("CustomerArrived", 0)), 0, "At least 1 CustomerArrived event during business hours")
	h.assert_gt(int(event_counts.get("ServiceStarted", 0)), 0, "At least 1 ServiceStarted event during business hours")
	h.assert_gt(int(event_counts.get("ServiceCompleted", 0)), 0, "At least 1 ServiceCompleted event during business hours")
	h.assert_true(bool(h.get_balance_sheet(rt["bank_state"]).get("is_balanced", false)), "Ledger balanced after lobby operations")


func _t1_f3_04_station_toggle_and_employee_assign(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Station Assign", 304)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var st_ids: Array[String] = h.get_station_ids(bs)
	var emp_ids: Array[String] = h.get_employee_ids(bs)
	h.assert_gt(st_ids.size(), 0, "Need >= 1 station")
	h.assert_gt(emp_ids.size(), 0, "Need >= 1 employee")
	if st_ids.is_empty() or emp_ids.is_empty():
		return

	var st_id: String = st_ids[0]
	var emp_id: String = emp_ids[0]
	var stations: Dictionary = bs.get("stations") as Dictionary
	var was_open: bool = bool((stations[st_id] as Dictionary).get("is_open", true))
	h.assert_result_ok(cmd.call("toggle_station_open", st_id), "toggle_station_open")
	h.assert_eq(bool((stations[st_id] as Dictionary).get("is_open", was_open)), not was_open, "toggle_station_open flips state")
	if was_open:
		h.assert_result_ok(cmd.call("toggle_station_open", st_id), "re-open station")
	h.assert_result_ok(cmd.call("assign_employee_to_station", emp_id, st_id), "assign_employee_to_station")
	h.assert_eq(str((stations[st_id] as Dictionary).get("assigned_employee_id", "")), emp_id, "Station tracks assigned employee")


func _t1_f3_05_queue_priority_reordering(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Queue Priority", 305)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]

	var st_ids: Array[String] = h.get_station_ids(bs)
	var emp_ids: Array[String] = h.get_employee_ids(bs)
	h.assert_gt(st_ids.size(), 0, "Need >= 1 station")
	h.assert_gt(emp_ids.size(), 0, "Need >= 1 employee")
	if st_ids.is_empty() or emp_ids.is_empty():
		return

	# Pick a station and employee matching each other (prefer teller station + teller employee)
	var target_st_id: String = st_ids[0]
	var target_emp_id: String = emp_ids[0]
	var stations_v: Variant = bs.get("stations")
	var stations: Dictionary = stations_v as Dictionary if stations_v is Dictionary else {}
	var emps_v: Variant = bs.get("employees")
	var emps: Dictionary = emps_v as Dictionary if emps_v is Dictionary else {}
	for sid in st_ids:
		var st_entry: Variant = stations.get(sid)
		if st_entry is Dictionary and str((st_entry as Dictionary).get("station_type", "")) == "teller":
			target_st_id = sid
			break
	for eid in emp_ids:
		var e_entry: Variant = emps.get(eid)
		if e_entry is Object and str((e_entry as Object).get("role_id")) == "teller":
			target_emp_id = eid
			break

	var allowed_services: Array = []
	var target_st_dict: Variant = stations.get(target_st_id)
	if target_st_dict is Dictionary:
		var raw_allowed: Variant = (target_st_dict as Dictionary).get("allowed_services", [])
		if raw_allowed is Array:
			allowed_services = raw_allowed as Array

	# Close all stations temporarily so compatible requests accumulate in queue
	for st_id in st_ids:
		var st_d: Variant = stations.get(st_id)
		if st_d is Dictionary and bool((st_d as Dictionary).get("is_open", false)):
			cmd.call("toggle_station_open", st_id)

	h.assert_result_ok(cmd.call("open_branch_for_day"), "open_branch_for_day")
	var min_dur: float = h.get_minute_duration(rt["session"])
	var paired: Array = []
	var guard: int = 0
	while paired.is_empty() and guard < 420:
		h.step_minutes(rt["sim_host"], 1, min_dur, 1)
		guard += 1
		var reqs_v: Variant = bs.get("service_requests")
		if reqs_v is Array:
			var by_type: Dictionary = {}
			for rq in (reqs_v as Array):
				var stype: String = str((rq as Object).get("service_type") if rq is Object else ((rq as Dictionary).get("service_type", "") if rq is Dictionary else ""))
				if stype == "":
					continue
				if not allowed_services.is_empty() and not allowed_services.has(stype):
					continue
				if not by_type.has(stype):
					by_type[stype] = []
				(by_type[stype] as Array).append(rq)
				if (by_type[stype] as Array).size() >= 2:
					paired = by_type[stype] as Array
					break

	h.assert_ge(paired.size(), 2, "Need >= 2 compatible queued requests of same service_type to test priority reordering")
	if paired.size() < 2:
		return

	var r_high: Variant = paired[paired.size() - 1]
	var id_high: String = str((r_high as Object).get("request_id") if r_high is Object else (r_high as Dictionary).get("request_id", ""))

	h.assert_result_ok(cmd.call("set_queue_priority", id_high, 2), "set_queue_priority high=2")

	var started_ids: Array[String] = []
	var bus: Variant = rt["event_bus"]
	if (bus as Object).has_signal("domain_event_emitted"):
		(bus as Object).connect("domain_event_emitted", func(ev: Variant) -> void:
			if ev is Object and str((ev as Object).get("event_type")) == "ServiceStarted":
				var p_raw: Variant = (ev as Object).get("payload")
				if p_raw is Dictionary:
					started_ids.append(str((p_raw as Dictionary).get("request_id", "")))
		)

	# Open exactly 1 station with compatible employee so dispatch picks strictly 1 request first
	cmd.call("toggle_station_open", target_st_id)
	cmd.call("assign_employee_to_station", target_emp_id, target_st_id)
	h.step_minutes(rt["sim_host"], 5, min_dur, 1)

	h.assert_gt(started_ids.size(), 0, "Expected ServiceStarted after opening station")
	if not started_ids.is_empty():
		h.assert_eq(started_ids[0], id_high, "Higher-priority request must be dispatched before older same-type lower-priority request")


func _t1_f3_06_hire_train_rest_employee_lifecycle(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("HR Lifecycle", 306)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var cand_ids: Array[String] = h.get_candidate_ids(bs)
	h.assert_gt(cand_ids.size(), 0, "Initial BankState must have hireable candidates")
	if cand_ids.is_empty():
		return

	var emp_count0: int = h.get_employee_ids(bs).size()
	var cand_id: String = cand_ids[0]
	h.assert_result_ok(cmd.call("hire_candidate", cand_id, "teller"), "hire_candidate")
	var emp_ids_after: Array[String] = h.get_employee_ids(bs)
	h.assert_eq(emp_ids_after.size(), emp_count0 + 1, "Employee count increases by 1 after hiring")

	var target_emp_id: String = emp_ids_after[0]
	var cash0: int = h.get_ledger_balance(bs, &"cash_reserves")
	h.assert_result_ok(cmd.call("train_employee", target_emp_id), "train_employee")
	h.assert_lt(h.get_ledger_balance(bs, &"cash_reserves"), cash0, "Training deducts cost via Ledger")

	var emp_obj: Variant = (bs.get("employees") as Dictionary).get(target_emp_id)
	if emp_obj is Object:
		(emp_obj as Object).set("fatigue", 60)
	h.assert_result_ok(cmd.call("rest_employee", target_emp_id), "rest_employee")
	h.assert_result_ok(cmd.call("open_branch_for_day"), "open_branch_for_day")
	h.step_minutes(rt["sim_host"], 30, h.get_minute_duration(rt["session"]), 1)
	if emp_obj is Object:
		h.assert_lt(int((emp_obj as Object).get("fatigue")), 60, "Resting reduces employee fatigue over ticks")


func _t1_f3_07_fire_employee_cleanup_and_payroll(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Fire Emp", 307)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var cand_ids: Array[String] = h.get_candidate_ids(bs)
	if h.get_employee_ids(bs).size() < 2 and not cand_ids.is_empty():
		h.assert_result_ok(cmd.call("hire_candidate", cand_ids[0], "teller"), "hire extra employee")
	var emp_ids: Array[String] = h.get_employee_ids(bs)
	h.assert_ge(emp_ids.size(), 2, "Need >= 2 employees for fire_employee test")
	if emp_ids.size() < 2:
		return

	var victim_id: String = emp_ids[emp_ids.size() - 1]
	var st_ids: Array[String] = h.get_station_ids(bs)
	if not st_ids.is_empty():
		cmd.call("assign_employee_to_station", victim_id, st_ids[0])

	var count_before: int = emp_ids.size()
	h.assert_result_ok(cmd.call("fire_employee", victim_id), "fire_employee")
	h.assert_eq(h.get_employee_ids(bs).size(), count_before - 1, "Fired employee removed from BankState.employees")
	if not st_ids.is_empty():
		var st_d: Dictionary = (bs.get("stations") as Dictionary)[st_ids[0]] as Dictionary
		h.assert_ne(str(st_d.get("assigned_employee_id", "")), victim_id, "Station assignment released on fire")

	h.assert_result_ok(cmd.call("open_branch_for_day"), "open_branch_for_day")
	h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
	h.assert_result_ok(cmd.call("advance_to_next_day"), "advance_to_next_day")
	h.assert_true(bool(h.get_balance_sheet(bs).get("is_balanced", false)), "Ledger balanced after fire & payroll")


# ---------------------------------------------------------------------------
# F4: Departments, Synergies, Policies & Macro Events
# ---------------------------------------------------------------------------

func _t1_f4_01_create_and_upgrade_operations_dept(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Ops Dept", 401)
	if rt.is_empty():
		return
	var reg: Variant = rt["registry"]
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]

	var dept_def: Dictionary = reg.call("get_department_def", "core:department.operations") as Dictionary
	h.assert_false(dept_def.is_empty(), "core:department.operations must exist in ContentRegistry")
	var init_cost: int = int(dept_def.get("initial_cost_minor", 0))
	var daily_cost: int = int(dept_def.get("daily_cost_minor", 0))

	var cash0: int = h.get_ledger_balance(bs, &"cash_reserves")
	h.assert_result_ok(cmd.call("create_department", "core:department.operations"), "create_department operations")
	h.assert_eq(h.get_ledger_balance(bs, &"cash_reserves"), cash0 - init_cost, "create_department deducts initial_cost_minor")

	var depts: Dictionary = bs.get("departments") as Dictionary
	h.assert_has(depts, "core:department.operations", "BankState.departments holds operations")
	var d_inst: Variant = depts.get("core:department.operations")
	h.assert_eq(int((d_inst as Object).get("level") if d_inst is Object else (d_inst as Dictionary).get("level", 0)), 1, "New dept starts at level 1")

	var cash1: int = h.get_ledger_balance(bs, &"cash_reserves")
	h.assert_result_ok(cmd.call("upgrade_department", "core:department.operations"), "upgrade_department operations")
	h.assert_eq(int((d_inst as Object).get("level") if d_inst is Object else (d_inst as Dictionary).get("level", 0)), 2, "Upgraded dept level is 2")
	h.assert_lt(h.get_ledger_balance(bs, &"cash_reserves"), cash1, "Upgrade deducts cost via Ledger")

	h.assert_result_ok(cmd.call("open_branch_for_day"), "open_branch_for_day")
	h.step_minutes(rt["sim_host"], 480, h.get_minute_duration(rt["session"]), 1)
	h.assert_result_ok(cmd.call("advance_to_next_day"), "advance_to_next_day")
	var reports: Array = bs.get("daily_reports") as Array
	if not reports.is_empty():
		h.assert_ge(int((reports[0] as Dictionary).get("facility_cost", 0)) + int((reports[0] as Dictionary).get("department_cost", 0)), daily_cost, "Daily settlement charges department daily cost")


func _t1_f4_02_all_four_mvp_departments(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("All Depts", 402)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var fe: Variant = h.instantiate_script("res://scripts/domain/finance_engine.gd")
	if fe == null:
		return
	# Ensure ample liquidity for creating all 4 MVP departments dynamically
	h.invoke_finance_amount_op(fe, "record_deposit", bs, 500_000_000, 1, 540, "cap_boost")

	var cand_before: int = (bs.get("candidates") as Array).size()
	for did in ["core:department.operations", "core:department.hr", "core:department.credit", "core:department.risk"]:
		h.assert_result_ok(cmd.call("create_department", did), "create_department %s" % did)

	var depts: Dictionary = bs.get("departments") as Dictionary
	h.assert_eq(depts.size(), 4, "All 4 MVP departments must be active")
	h.assert_ge((bs.get("candidates") as Array).size(), cand_before, "HR dept keeps/expands candidate pool")


func _t1_f4_03_modifier_service_add_multiply_set(h: Variant) -> void:
	var mod_svc: Variant = h.instantiate_script("res://scripts/domain/modifier_service.gd")
	if mod_svc == null:
		return
	var effects1: Array[Dictionary] = [
		{"target": "staff.productivity_bps", "operation": "multiply", "value": 15000, "scope": "global"},
		{"target": "staff.productivity_bps", "operation": "add", "value": 2000, "scope": "global"},
	]
	var effects2: Array[Dictionary] = [
		{"target": "staff.productivity_bps", "operation": "add", "value": 2000, "scope": "global"},
		{"target": "staff.productivity_bps", "operation": "multiply", "value": 15000, "scope": "global"},
		{"target": "staff.productivity_bps", "operation": "set", "value": 12000, "scope": "global"},
	]

	var evaluated1: Variant = _eval_modifier_effects(h, mod_svc, "staff.productivity_bps", 10000, effects1)
	var evaluated2: Variant = _eval_modifier_effects(h, mod_svc, "staff.productivity_bps", 10000, effects2)
	h.assert_not_null(evaluated1, "ModifierService must expose effect evaluation contract")
	if evaluated1 != null:
		h.assert_eq(int(evaluated1), 18000, "ModifierService must apply add before multiply: (10000+2000)*1.5 = 18000")
	if evaluated2 != null:
		h.assert_eq(int(evaluated2), 12000, "ModifierService set must override after add->multiply")


func _t1_f4_04_conservative_policy_chain(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Pol Cons", 404)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var reg: Variant = rt["registry"]
	var chain: Array[String] = [
		"core:policy.prudent_lending",
		"core:policy.liquidity_first",
		"core:policy.customer_trust",
	]
	var total_cost: int = 0
	for pid in chain:
		var pdef: Dictionary = reg.call("get_policy_def", pid) as Dictionary
		h.assert_false(pdef.is_empty(), "Missing policy def: %s" % pid)
		total_cost += int(pdef.get("cost_strategy_points", 0))
	bs.set("strategy_points", total_cost + 5)

	for pid in chain:
		var sp_before: int = int(bs.get("strategy_points"))
		var pdef: Dictionary = reg.call("get_policy_def", pid) as Dictionary
		var cost: int = int(pdef.get("cost_strategy_points", 0))
		h.assert_result_ok(cmd.call("adopt_policy", pid), "adopt_policy %s" % pid)
		h.assert_eq(int(bs.get("strategy_points")), sp_before - cost, "strategy_points deducted for %s" % pid)

	var adopted: Array = bs.get("adopted_policies") as Array
	for pid in chain:
		h.assert_has(adopted, pid, "adopted_policies contains %s" % pid)


func _t1_f4_05_aggressive_policy_chain(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Pol Aggr", 405)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var reg: Variant = rt["registry"]
	var chain: Array[String] = [
		"core:policy.high_rate_acquisition",
		"core:policy.market_penetration",
		"core:policy.credit_expansion",
	]
	var total_cost: int = 0
	for pid in chain:
		var pdef: Dictionary = reg.call("get_policy_def", pid) as Dictionary
		h.assert_false(pdef.is_empty(), "Missing policy def: %s" % pid)
		total_cost += int(pdef.get("cost_strategy_points", 0))
	bs.set("strategy_points", total_cost + 5)

	for pid in chain:
		h.assert_result_ok(cmd.call("adopt_policy", pid), "adopt_policy %s" % pid)
	var adopted: Array = bs.get("adopted_policies") as Array
	for pid in chain:
		h.assert_has(adopted, pid, "adopted_policies contains %s" % pid)


func _t1_f4_06_trigger_and_resolve_random_event(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Event Resolve", 406)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var reg: Variant = rt["registry"]

	# Run days until an event triggers in active_events (or inject via EventEngine if needed)
	var min_dur: float = h.get_minute_duration(rt["session"])
	for _d in range(10):
		if not (bs.get("active_events") as Array).is_empty():
			break
		cmd.call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 480, min_dur, 1)
		if (bs.get("active_events") as Array).is_empty():
			cmd.call("advance_to_next_day")

	var active: Array = bs.get("active_events") as Array
	h.assert_gt(active.size(), 0, "At least 1 event must trigger within 10 simulated days")
	if active.is_empty():
		return

	var ev_inst: Dictionary = active[0] as Dictionary
	var ev_inst_id: String = str(ev_inst.get("instance_id", ev_inst.get("id", "")))
	var ev_def_id: String = str(ev_inst.get("event_id", ev_inst.get("definition_id", "")))
	var ev_def: Dictionary = reg.call("get_event_def", ev_def_id) as Dictionary
	var opts: Array = ev_def.get("options", ev_inst.get("options", [])) as Array
	h.assert_gt(opts.size(), 0, "Event must have >= 1 option")
	if opts.is_empty():
		return

	var opt_id: String = str((opts[0] as Dictionary).get("id", ""))
	var hist_before: int = (bs.get("event_history") as Array).size()
	h.assert_result_ok(cmd.call("resolve_event_option", ev_inst_id, opt_id), "resolve_event_option")
	h.assert_eq((bs.get("event_history") as Array).size(), hist_before + 1, "event_history records resolved event")
	h.assert_true(bool(h.get_balance_sheet(bs).get("is_balanced", false)), "Ledger balanced after event resolution")


func _t1_f4_07_event_chaining_real_estate_progression(h: Variant) -> void:
	var rt: Dictionary = h.start_session_and_host("Event Chain", 407)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	var reg: Variant = rt["registry"]

	var boom_def: Dictionary = reg.call("get_event_def", "core:event.real_estate_boom") as Dictionary
	var cool_def: Dictionary = reg.call("get_event_def", "core:event.real_estate_cooling") as Dictionary
	h.assert_false(boom_def.is_empty(), "core:event.real_estate_boom must exist")
	h.assert_false(cool_def.is_empty(), "core:event.real_estate_cooling must exist")
	if boom_def.is_empty() or cool_def.is_empty():
		return

	var ee: Variant = h.instantiate_script("res://scripts/domain/event_engine.gd")
	if ee == null:
		return
	# Queue Stage 1 via EventEngine public API or active_events if not yet triggered
	var opts: Array = boom_def.get("options", []) as Array
	var chain_opt_id: String = ""
	for o in opts:
		if str((o as Dictionary).get("next_event_id", "")) == "core:event.real_estate_cooling":
			chain_opt_id = str((o as Dictionary).get("id", ""))
			break
	h.assert_ne(chain_opt_id, "", "real_estate_boom must have an option chaining to real_estate_cooling")

	var boom_inst_id: String = "e2e_boom_1"
	var tr_res: Variant = h.trigger_event_safely(ee, bs, "core:event.real_estate_boom", rt["defs"])
	h.assert_result_ok(tr_res, "EventEngine.trigger_event real_estate_boom")
	var tr_data: Dictionary = h.get_result_data_dict(tr_res)
	if not tr_data.is_empty():
		boom_inst_id = str(tr_data.get("instance_id", boom_inst_id))

	h.assert_result_ok(cmd.call("resolve_event_option", boom_inst_id, chain_opt_id), "resolve Stage 1 boom")

	# Advance days until Stage 2 cooling activates
	var found_stage2: bool = false
	var min_dur: float = h.get_minute_duration(rt["session"])
	for _d in range(15):
		for ev in (bs.get("active_events") as Array):
			if str((ev as Dictionary).get("event_id", "")) == "core:event.real_estate_cooling":
				found_stage2 = true
				break
		if found_stage2:
			break
		cmd.call("open_branch_for_day")
		h.step_minutes(rt["sim_host"], 480, min_dur, 1)
		cmd.call("advance_to_next_day")
		# Resolve unrelated blocking events if any
		for ev in (bs.get("active_events") as Array).duplicate():
			var eid: String = str((ev as Dictionary).get("event_id", ""))
			if eid == "core:event.real_estate_cooling":
				found_stage2 = true
				break
			var ed: Dictionary = reg.call("get_event_def", eid) as Dictionary
			var eopts: Array = ed.get("options", []) as Array
			if not eopts.is_empty():
				cmd.call("resolve_event_option", str((ev as Dictionary).get("instance_id", "")), str((eopts[0] as Dictionary).get("id", "")))
		if found_stage2:
			break
	h.assert_true(found_stage2, "Stage 2 core:event.real_estate_cooling must activate via next_event_id chaining")


# ---------------------------------------------------------------------------
# F5: Localization, ContentRegistry & Safe Modding
# ---------------------------------------------------------------------------

func _t1_f5_01_core_content_registry_and_schemas(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	if reg == null:
		return
	var empty_dir: String = h.create_temp_mod_dir("t1_f5_01_empty")
	var report: Variant = reg.call("reload_all", empty_dir)
	h.assert_true(report is Dictionary, "reload_all must return Dictionary ModLoadReport")
	var rep: Dictionary = report as Dictionary
	h.assert_eq((rep.get("errors", ["err"]) as Array).size(), 0, "Empty mods dir must yield 0 errors")

	var depts: Array = h.build_content_defs(reg).get("departments", []) as Array
	var pols: Array = h.build_content_defs(reg).get("policies", []) as Array
	var evs: Array = h.build_content_defs(reg).get("events", []) as Array
	h.assert_ge(depts.size(), 4, "Must load >= 4 core departments")
	h.assert_ge(pols.size(), 6, "Must load >= 6 core policies")
	h.assert_ge(evs.size(), 10, "Must load >= 10 core events")

	for d in depts:
		h.assert_true(h.validate_content_id(str((d as Dictionary).get("id", ""))), "Dept ID matches pattern")
	for did in ["core:department.operations", "core:department.hr", "core:department.credit", "core:department.risk"]:
		h.assert_false((reg.call("get_department_def", did) as Dictionary).is_empty(), "Missing core dept: %s" % did)
	for eid in ["core:event.real_estate_boom", "core:event.real_estate_cooling", "core:event.real_estate_credit_stress"]:
		h.assert_false((reg.call("get_event_def", eid) as Dictionary).is_empty(), "Missing macro event: %s" % eid)


func _t1_f5_02_localization_default_and_live_switch(h: Variant) -> void:
	var loc: Node = h.get_autoload("LocalizationService")
	if loc == null:
		return
	h.require_signal(loc, "locale_changed", "LocalizationService")
	h.require_method(loc, "get_locale", "LocalizationService")
	h.require_method(loc, "set_locale", "LocalizationService")
	h.require_method(loc, "tr_key", "LocalizationService")

	var orig: String = str(loc.call("get_locale"))
	h.assert_true(orig in ["zh_CN", "en", "ja"], "Initial locale must be a supported locale")

	var emitted: Array[String] = []
	var cb_loc: Callable = func(nl: String) -> void:
		emitted.append(nl)
	(loc as Object).connect("locale_changed", cb_loc)

	var translations: Dictionary = {}
	for lc in ["en", "ja", "zh_CN"]:
		loc.call("set_locale", lc)
		h.assert_eq(str(loc.call("get_locale")), lc, "get_locale reflects %s" % lc)
		var val: String = str(loc.call("tr_key", "UI_TOPBAR_DAY"))
		h.assert_ne(val, "", "Translated key must be non-empty in %s" % lc)
		h.assert_ne(val, "UI_TOPBAR_DAY", "Core key UI_TOPBAR_DAY must resolve in %s" % lc)
		translations[lc] = val

	if (loc as Object).is_connected("locale_changed", cb_loc):
		(loc as Object).disconnect("locale_changed", cb_loc)
	h.assert_eq(emitted, ["en", "ja", "zh_CN"], "locale_changed must emit in switch order")
	h.assert_ne(translations["zh_CN"], translations["en"], "zh_CN and en translations must differ")

	for fpath in ["res://localization/messages.pot", "res://localization/zh_CN.po", "res://localization/en.po", "res://localization/ja.po"]:
		h.assert_true(FileAccess.file_exists(ProjectSettings.globalize_path(fpath)), "Missing gettext file: %s" % fpath)


func _t1_f5_03_parameterized_formatting_and_format_service(h: Variant) -> void:
	var loc: Node = h.get_autoload("LocalizationService")
	var fmt: Variant = h.instantiate_script("res://scripts/shared/format_service.gd")
	if loc == null or fmt == null:
		return

	h.mark_mods_touched()
	loc.call("register_mod_translations", "com.e2e.fmt", "en", {"com.e2e.fmt:GREET": "Day {day}: {cash}"})
	loc.call("set_locale", "en")
	var rendered: String = str(loc.call("tr_key", "com.e2e.fmt:GREET", {"day": 3, "cash": "$500"}))
	h.assert_eq(rendered, "Day 3: $500", "tr_key must substitute params dictionary cleanly")

	# Verify FormatService static/instance methods exist and format deterministically
	var has_time: bool = (fmt as Object).has_method("format_time") or (fmt as Object).has_method("format_minute_of_day")
	var has_money: bool = (fmt as Object).has_method("format_money") or (fmt as Object).has_method("format_currency")
	var has_bps: bool = (fmt as Object).has_method("format_bps") or (fmt as Object).has_method("format_rate_bps")
	h.assert_true(has_time, "FormatService must provide time formatting")
	h.assert_true(has_money, "FormatService must provide money formatting")
	h.assert_true(has_bps, "FormatService must provide bps formatting")

	if (fmt as Object).has_method("format_time"):
		h.assert_eq(str(fmt.call("format_time", 540)), "09:00", "540 formats as 09:00")
	elif (fmt as Object).has_method("format_minute_of_day"):
		h.assert_eq(str(fmt.call("format_minute_of_day", 540)), "09:00", "540 formats as 09:00")

	if (fmt as Object).has_method("format_bps"):
		h.assert_true(str(fmt.call("format_bps", 425)).contains("4.25"), "425 bps formats with 4.25")
	elif (fmt as Object).has_method("format_rate_bps"):
		h.assert_true(str(fmt.call("format_rate_bps", 425)).contains("4.25"), "425 bps formats with 4.25")


func _t1_f5_04_valid_directory_mod_loading(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	if reg == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t1_f5_04")
	var dst_mod: String = mods_root + "/com.example.extra_departments"
	var src_mod: String = h.get_repo_root_abs().path_join("examples/mod_template")
	h.assert_true(h.copy_dir_recursive(src_mod, dst_mod), "Copy examples/mod_template to temp mods dir")

	var rep: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	var loaded: Array = rep.get("loaded_mods", []) as Array
	var rejected: Array = rep.get("rejected_mods", []) as Array
	h.assert_eq(rejected.size(), 0, "Valid mod_template must have 0 rejected mods")
	h.assert_true(_loaded_mods_contains(loaded, "com.example.extra_departments"), "loaded_mods must include com.example.extra_departments")

	var ddef: Dictionary = reg.call("get_department_def", "com.example.extra_departments:department.research_support") as Dictionary
	var pdef: Dictionary = reg.call("get_policy_def", "com.example.extra_departments:policy.process_research") as Dictionary
	var edef: Dictionary = reg.call("get_event_def", "com.example.extra_departments:event.workflow_audit") as Dictionary
	h.assert_false(ddef.is_empty(), "Mod department loaded")
	h.assert_false(pdef.is_empty(), "Mod policy loaded")
	h.assert_false(edef.is_empty(), "Mod event loaded")

	var deps: Array = reg.call("get_loaded_mod_dependencies") as Array
	h.assert_true(_loaded_mods_contains(deps, "com.example.extra_departments"), "get_loaded_mod_dependencies reports loaded mod")


func _t1_f5_05_valid_zip_mod_and_translations(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	var loc: Node = h.get_autoload("LocalizationService")
	if reg == null or loc == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t1_f5_05")
	var src_mod: String = h.get_repo_root_abs().path_join("examples/mod_template")
	var zip_path: String = mods_root + "/extra_departments.zip"
	h.assert_true(h.build_zip_from_dir(zip_path, src_mod), "Pack examples/mod_template into .zip")

	var rep: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	h.assert_eq((rep.get("rejected_mods", []) as Array).size(), 0, "Valid .zip mod must not be rejected")
	h.assert_true(_loaded_mods_contains(rep.get("loaded_mods", []) as Array, "com.example.extra_departments"), "Valid .zip mod loaded")

	loc.call("set_locale", "zh_CN")
	h.assert_eq(str(loc.call("tr_key", "com.example.extra_departments:DEPT_RESEARCH_NAME")), "流程研究部", "Mod zh_CN translation")
	loc.call("set_locale", "en")
	h.assert_eq(str(loc.call("tr_key", "com.example.extra_departments:DEPT_RESEARCH_NAME")), "Process Research", "Mod en translation")
	loc.call("set_locale", "ja")
	h.assert_eq(str(loc.call("tr_key", "com.example.extra_departments:DEPT_RESEARCH_NAME")), "業務研究部", "Mod ja translation")


func _t1_f5_06_deterministic_topological_load_order(h: Variant) -> void:
	var reg: Node = h.get_autoload("ContentRegistry")
	if reg == null:
		return
	var mods_root: String = h.create_temp_mod_dir("t1_f5_06")
	_write_minimal_mod(h, mods_root + "/com.test.b", "com.test.b", "1.0.0", ["com.test.a"])
	_write_minimal_mod(h, mods_root + "/com.test.a", "com.test.a", "1.0.0", [])
	_write_minimal_mod(h, mods_root + "/com.test.c", "com.test.c", "1.0.0", [])

	var rep: Dictionary = reg.call("reload_all", mods_root) as Dictionary
	var loaded: Array = rep.get("loaded_mods", []) as Array
	var ids: Array[String] = _extract_mod_ids(loaded)
	h.assert_true(ids.has("com.test.a") and ids.has("com.test.b") and ids.has("com.test.c"), "All 3 valid mods must load")
	h.assert_lt(ids.find("com.test.a"), ids.find("com.test.b"), "Dependency com.test.a must load strictly before com.test.b")


# ---------------------------------------------------------------------------
# F6: Atomic Save/Load v1, .bak Recovery, Session & Audio/UI Contracts
# ---------------------------------------------------------------------------

func _t1_f6_01_save_service_slot_roundtrip_and_bak(h: Variant) -> void:
	var save_svc: Node = h.get_autoload("SaveService")
	if save_svc == null:
		return
	h.assert_eq(int(save_svc.get("SAVE_VERSION")), 1, "SaveService.SAVE_VERSION must be 1")

	var rt: Dictionary = h.start_session_and_host("Save Slot 1", 601)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]
	var cmd: Variant = rt["cmd"]
	cmd.call("create_department", "core:department.operations")
	bs.set("strategy_points", 20)
	cmd.call("adopt_policy", "core:policy.prudent_lending")

	var cash_v1: int = h.get_ledger_balance(bs, &"cash_reserves")
	h.assert_result_ok(save_svc.call("save_slot", "slot_01", bs, {"note": "v1"}), "save_slot v1")
	var slot_path: String = str(save_svc.call("get_slot_path", "slot_01"))
	h.assert_true(FileAccess.file_exists(slot_path), "slot_01.json created on disk")
	h.assert_false(FileAccess.file_exists(slot_path.replace(".json", ".tmp")), "No .tmp residue after save")

	# Second save rotates v1 to .bak
	bs.set("reputation", 88)
	h.assert_result_ok(save_svc.call("save_slot", "slot_01", bs, {"note": "v2"}), "save_slot v2")
	var bak_path: String = slot_path.replace(".json", ".bak")
	h.assert_true(FileAccess.file_exists(bak_path), ".bak created on overwrite")

	var load_res: Variant = save_svc.call("load_slot", "slot_01")
	h.assert_result_ok(load_res, "load_slot slot_01")
	var data_v: Variant = (load_res as Object).get("data") if load_res is Object else null
	h.assert_true(data_v is Dictionary, "load_slot data must be Dictionary")
	if data_v is Dictionary:
		var data: Dictionary = data_v as Dictionary
		h.assert_false(bool(data.get("used_backup", true)), "Primary load sets used_backup == false")
		var restored: Variant = data.get("bank_state")
		h.assert_not_null(restored, "Restored BankState non-null")
		if restored != null:
			h.assert_eq(int(restored.get("world_seed")), 601, "world_seed preserved")
			h.assert_eq(int(restored.get("reputation")), 88, "reputation preserved")
			h.assert_eq(h.get_ledger_balance(restored, &"cash_reserves"), cash_v1, "Ledger cash preserved")
			var depts_v: Variant = restored.get("departments")
			h.assert_true(depts_v is Dictionary, "Restored departments must be Dictionary")
			if depts_v is Dictionary:
				h.assert_has(depts_v as Dictionary, "core:department.operations", "Departments preserved")
			var pols_v: Variant = restored.get("adopted_policies")
			h.assert_true(pols_v is Array, "Restored adopted_policies must be Array")
			if pols_v is Array:
				h.assert_has(pols_v as Array, "core:policy.prudent_lending", "Adopted policies preserved")


func _t1_f6_02_save_service_autosave_list_delete(h: Variant) -> void:
	var save_svc: Node = h.get_autoload("SaveService")
	if save_svc == null:
		return
	var rt: Dictionary = h.start_session_and_host("AutoList", 602)
	if rt.is_empty():
		return
	var bs: Variant = rt["bank_state"]

	h.assert_result_ok(save_svc.call("save_slot", "autosave", bs, {}), "save autosave")
	h.assert_result_ok(save_svc.call("save_slot", "slot_02", bs, {}), "save slot_02")
	var slots: Array = save_svc.call("list_slots") as Array
	var ids: Array[String] = []
	for s in slots:
		if s is Dictionary:
			ids.append(str((s as Dictionary).get("slot_id", "")))
	h.assert_has(ids, "autosave", "list_slots includes autosave")
	h.assert_has(ids, "slot_02", "list_slots includes slot_02")

	h.assert_result_ok(save_svc.call("delete_slot", "slot_02"), "delete_slot slot_02")
	var slots2: Array = save_svc.call("list_slots") as Array
	var ids2: Array[String] = []
	for s in slots2:
		if s is Dictionary:
			ids2.append(str((s as Dictionary).get("slot_id", "")))
	h.assert_false(ids2.has("slot_02"), "Deleted slot_02 absent from list_slots")


func _t1_f6_03_audio_service_playback_and_persistence(h: Variant) -> void:
	var audio: Node = h.get_autoload("AudioService")
	if audio == null:
		return
	audio.call("play_bgm", "bgm_starway_lobby", 0.05)
	audio.call("play_sfx", "sfx_ui_click")
	audio.call("set_bus_volume", "BGM", 0.4)
	audio.call("set_bus_volume", "SFX", 0.75)
	audio.call("set_muted", true)

	h.assert_near(float(audio.call("get_bus_volume", "BGM")), 0.4, 0.02, "BGM volume updated to 0.4")
	h.assert_near(float(audio.call("get_bus_volume", "SFX")), 0.75, 0.02, "SFX volume updated to 0.75")
	h.assert_true(bool(audio.call("is_muted")), "Mute flag set to true")
	audio.call("stop_bgm", 0.05)

	h.assert_true(FileAccess.file_exists("user://settings.json"), "AudioService/settings persisted to user://settings.json")


func _t1_f6_04_game_session_lifecycle_and_signals(h: Variant) -> void:
	var sess: Node = h.get_autoload("GameSession")
	if sess == null:
		return
	h.mark_session_touched()

	var counts: Dictionary = {"started": 0, "ended": 0, "settings": 0}
	var cb_started: Callable = func(_bs: Variant) -> void:
		counts["started"] = int(counts["started"]) + 1
	var cb_ended: Callable = func() -> void:
		counts["ended"] = int(counts["ended"]) + 1
	var cb_settings: Callable = func(_s: Dictionary) -> void:
		counts["settings"] = int(counts["settings"]) + 1
	(sess as Object).connect("session_started", cb_started)
	(sess as Object).connect("session_ended", cb_ended)
	(sess as Object).connect("settings_changed", cb_settings)

	var bs: Variant = sess.call("start_new_game", "Session Bank", 4242)
	h.assert_not_null(bs, "start_new_game returns BankState")
	h.assert_true(bool(sess.get("is_active")), "is_active == true after start_new_game")
	h.assert_eq(int(counts["started"]), 1, "session_started fired once")

	h.assert_result_ok(sess.call("save_to_slot", "slot_03"), "GameSession.save_to_slot(slot_03)")
	sess.call("end_session")
	h.assert_false(bool(sess.get("is_active")), "is_active == false after end_session")
	h.assert_eq(int(counts["ended"]), 1, "session_ended fired once")

	h.assert_result_ok(sess.call("load_from_slot", "slot_03"), "GameSession.load_from_slot(slot_03)")
	h.assert_true(bool(sess.get("is_active")), "is_active == true after load_from_slot")
	var loaded_bs: Variant = sess.get("bank_state")
	h.assert_not_null(loaded_bs, "Loaded bank_state must not be null")
	if loaded_bs != null:
		h.assert_eq(str(loaded_bs.get("bank_name")), "Session Bank", "Loaded bank_name matches")
		h.assert_eq(int(loaded_bs.get("world_seed")), 4242, "Loaded world_seed matches")

	sess.call("update_settings", {"minute_duration_sec": 1.0})
	h.assert_near(float(sess.get("minute_duration_sec")), 1.0, 0.001, "minute_duration_sec updated to 1.0")
	h.assert_ge(int(counts["settings"]), 1, "settings_changed emitted")

	if (sess as Object).is_connected("session_started", cb_started):
		(sess as Object).disconnect("session_started", cb_started)
	if (sess as Object).is_connected("session_ended", cb_ended):
		(sess as Object).disconnect("session_ended", cb_ended)
	if (sess as Object).is_connected("settings_changed", cb_settings):
		(sess as Object).disconnect("settings_changed", cb_settings)


func _t1_f6_05_game_root_hud_and_command_boundary(h: Variant) -> void:
	var sess: Node = h.get_autoload("GameSession")
	if sess == null:
		return
	h.mark_session_touched()
	sess.call("start_new_game", "HUD Bank", 605)

	var game_root: Node = h.instantiate_scene("res://scenes/gameplay/game_root.tscn", true)
	if game_root == null:
		return
	var sim_host: Node = _find_node_by_name_fragment(game_root, "SimulationHost")
	h.assert_not_null(sim_host, "GameRoot must own a SimulationHost child")
	for ui_part in ["TopBar", "LeftNavigation", "RightInspector", "BottomBar"]:
		h.assert_not_null(_find_node_by_name_fragment(game_root, ui_part), "GameRoot must include %s" % ui_part)


func _t1_f6_06_drawers_modals_and_daily_report_overlay(h: Variant) -> void:
	var sess: Node = h.get_autoload("GameSession")
	if sess == null:
		return
	h.mark_session_touched()
	sess.call("start_new_game", "Overlay Bank", 606)

	var game_root: Node = h.instantiate_scene("res://scenes/gameplay/game_root.tscn", true)
	if game_root == null:
		return
	var report_overlay: Node = _find_node_by_name_fragment(game_root, "DailyReport")
	if report_overlay == null:
		report_overlay = h.instantiate_scene("res://scenes/ui/daily_report_overlay.tscn", true)
	h.assert_not_null(report_overlay, "DailyReportOverlay must exist in GameRoot or scenes/ui/")

	var ui_scripts: Array[String] = h.find_files_recursive("res://scripts/presentation/ui", ".gd")
	var found_draw: bool = false
	for sp in ui_scripts:
		if h.read_text_file(sp).contains("func _draw("):
			found_draw = true
			break
	h.assert_true(found_draw, "Finance UI (scripts/presentation/ui) must implement custom _draw() chart")


# ---------------------------------------------------------------------------
# Internal Opaque Helpers
# ---------------------------------------------------------------------------

func _count_nodes_of_type(root: Node, type_name: String) -> int:
	var cnt: int = 1 if root.is_class(type_name) else 0
	for c in root.get_children():
		cnt += _count_nodes_of_type(c, type_name)
	return cnt


func _find_camera2d(root: Node) -> Camera2D:
	if root is Camera2D:
		return root as Camera2D
	for c in root.get_children():
		var found: Camera2D = _find_camera2d(c)
		if found != null:
			return found
	return null


func _has_ysort_node(root: Node) -> bool:
	if root is Node2D and (root as Node2D).y_sort_enabled:
		return true
	for c in root.get_children():
		if _has_ysort_node(c):
			return true
	return false


func _find_node_by_name_fragment(root: Node, frag: String) -> Node:
	if root.name.to_lower().contains(frag.to_lower()):
		return root
	for c in root.get_children():
		var found: Node = _find_node_by_name_fragment(c, frag)
		if found != null:
			return found
	return null


func _call_eval_loan(fe: Variant, cust: Variant, loan_req: Variant, bs: Variant, mod_svc: Variant) -> Variant:
	var sig: Dictionary = _sig_of(fe, "evaluate_loan_application")
	var args: Array = sig.get("args", []) as Array
	if args.size() >= 4:
		var arg4_type: int = int((args[3] as Dictionary).get("type", TYPE_NIL))
		if arg4_type == TYPE_DICTIONARY:
			return fe.call("evaluate_loan_application", cust, loan_req, bs, {})
		return fe.call("evaluate_loan_application", cust, loan_req, bs, mod_svc)
	return fe.call("evaluate_loan_application", cust, loan_req, bs)


func _extract_created_loan_id(disb: Variant, bs: Variant, loans_before: Array) -> String:
	if disb is Object:
		var data_v: Variant = (disb as Object).get("data")
		if data_v is Object:
			var obj_d: Object = data_v as Object
			var lid: Variant = obj_d.get("loan_id")
			if lid != null and str(lid) != "":
				return str(lid)
			var gid: Variant = obj_d.get("id")
			if gid != null and str(gid) != "":
				return str(gid)
		elif data_v is Dictionary:
			var dd: Dictionary = data_v as Dictionary
			var lid_s: String = str(dd.get("loan_id", dd.get("id", "")))
			if lid_s != "":
				return lid_s
	if bs is Object:
		var loans_after_v: Variant = (bs as Object).get("loans")
		if loans_after_v is Dictionary:
			var new_keys: Array[String] = []
			for k in (loans_after_v as Dictionary).keys():
				if not loans_before.has(k):
					new_keys.append(str(k))
			new_keys.sort()
			if not new_keys.is_empty():
				return new_keys[0]
	return ""


func _call_daily_settlement(fe: Variant, bs: Variant, mod_svc: Variant, defs: Dictionary) -> Variant:
	var rng_streams: Variant = bs.get("rng_streams")
	var market_rng: Variant = rng_streams.get("market_rng") if rng_streams is Object else null
	var sig: Dictionary = _sig_of(fe, "run_daily_settlement")
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


func _eval_modifier_effects(h: Variant, mod_svc: Variant, target: String, base_val: int, effects: Array[Dictionary]) -> Variant:
	var obj: Object = mod_svc as Object
	for mname in ["evaluate_effects", "apply_effects", "compute_target", "resolve_target", "evaluate"]:
		if obj.has_method(mname):
			var sig: Dictionary = _sig_of(obj, mname)
			var max_args: int = (sig.get("args", []) as Array).size()
			var min_args: int = max_args - (sig.get("default_args", []) as Array).size()
			if max_args >= 3 and min_args <= 3:
				return obj.call(mname, target, base_val, effects)
			elif max_args >= 4 and min_args == 4:
				return obj.call(mname, target, base_val, effects, "")
			elif max_args >= 2 and min_args <= 2:
				return obj.call(mname, base_val, effects)
	h.fail_test("ModifierService missing expected evaluation method")
	return null


func _sig_of(obj: Variant, mname: String) -> Dictionary:
	if obj == null or not (obj is Object):
		return {}
	for m in (obj as Object).get_method_list():
		if str(m.get("name", "")) == mname:
			return m
	return {}


func _sample_rng_streams(rng_streams: Variant, count: int) -> Array:
	var out: Array = []
	if rng_streams == null or not (rng_streams is Object):
		return out
	var m_rng: Variant = (rng_streams as Object).get("market_rng")
	var e_rng: Variant = (rng_streams as Object).get("event_rng")
	for _i in range(count):
		if m_rng is RandomNumberGenerator:
			out.append((m_rng as RandomNumberGenerator).randi())
		if e_rng is RandomNumberGenerator:
			out.append((e_rng as RandomNumberGenerator).randi())
	return out


func _capture_economic_snapshot(h: Variant, bs: Variant) -> Dictionary:
	return {
		"cash": h.get_ledger_balance(bs, &"cash_reserves"),
		"loans": h.get_ledger_balance(bs, &"loan_principal_outstanding"),
		"deposits": h.get_ledger_balance(bs, &"customer_deposits"),
		"retained": h.get_ledger_balance(bs, &"retained_earnings"),
		"reputation": int(bs.get("reputation")),
		"satisfaction": int(bs.get("satisfaction")),
		"reports": bs.get("daily_reports"),
	}


func _loaded_mods_contains(arr: Array, mod_id: String) -> bool:
	for item in arr:
		if item is String and str(item) == mod_id:
			return true
		if item is Dictionary and str((item as Dictionary).get("id", "")) == mod_id:
			return true
	return false


func _extract_mod_ids(arr: Array) -> Array[String]:
	var out: Array[String] = []
	for item in arr:
		if item is String:
			out.append(str(item))
		elif item is Dictionary:
			out.append(str((item as Dictionary).get("id", "")))
	return out


func _write_minimal_mod(h: Variant, dir_path: String, mod_id: String, ver: String, deps: Array) -> void:
	h.write_json_file(dir_path + "/manifest.json", {
		"schema_version": 1,
		"id": mod_id,
		"name_key": "%s:MOD_NAME" % mod_id,
		"version": ver,
		"author": "E2E",
		"dependencies": deps,
		"content": {
			"departments": "content/departments.json",
		},
	})
	h.write_json_file(dir_path + "/content/departments.json", [{
		"id": "%s:department.sample" % mod_id,
		"name_key": "%s:DEPT_NAME" % mod_id,
		"description_key": "%s:DEPT_DESC" % mod_id,
		"initial_cost_minor": 100000,
		"daily_cost_minor": 5000,
		"max_level": 2,
		"effects": [],
	}])
