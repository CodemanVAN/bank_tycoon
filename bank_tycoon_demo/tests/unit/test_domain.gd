extends SceneTree

## Standalone headless unit test suite for Milestone M2 (shared + domain core).

static var _total: int = 0
static var _passed: int = 0
static var _failed: int = 0
static var _errors: Array[String] = []


func _initialize() -> void:
	var summary: Dictionary = run_all()
	var passed_count: int = int(summary.get("passed", 0))
	var failed_count: int = int(summary.get("failed", 0))
	var total_count: int = int(summary.get("total", 0))
	print("[M2_UNIT] Summary: %d/%d passed, %d failed" % [passed_count, total_count, failed_count])
	quit(0 if (failed_count == 0 and total_count > 0) else 1)


static func _check(cond: bool, msg: String) -> void:
	_total += 1
	if cond:
		_passed += 1
	else:
		_failed += 1
		_errors.append(msg)
		print("[M2_UNIT] FAIL: %s" % msg)


static func _check_eq(actual: Variant, expected: Variant, msg: String) -> void:
	_total += 1
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		var detail: String = "%s (expected=%s, actual=%s)" % [msg, str(expected), str(actual)]
		_errors.append(detail)
		print("[M2_UNIT] FAIL: %s" % detail)


static func _run_case(name: String, fn: Callable) -> void:
	var fail_before: int = _failed
	fn.call()
	if _failed == fail_before:
		print("[M2_UNIT] PASS: %s" % name)


static func run_all() -> Dictionary:
	_total = 0
	_passed = 0
	_failed = 0
	_errors.clear()

	_run_case("zero_node_boundary_regex", _test_zero_node_boundary)
	_run_case("content_id_validation", _test_content_id)
	_run_case("result_and_enums_and_format_and_domain_event", _test_shared_types)
	_run_case("rng_streams_determinism_and_json_roundtrip", _test_rng_streams)
	_run_case("ledger_double_entry_and_500_cap", _test_ledger)
	_run_case("finance_engine_math_ops_eval_and_settlement", _test_finance_engine)
	_run_case("employee_and_customer_state_machines", _test_employee_and_customer)
	_run_case("loan_and_service_request_entities", _test_loan_and_service_request)
	_run_case("modifier_service_order_clamping_and_synergies", _test_modifier_service)
	_run_case("department_and_policy_services", _test_department_and_policy)
	_run_case("event_engine_conditions_cooldown_and_chaining", _test_event_engine)
	_run_case("bank_state_zero_cash_starter_and_json_roundtrip", _test_bank_state_roundtrip)

	return {
		"total": _total,
		"passed": _passed,
		"failed": _failed,
		"errors": _errors.duplicate(),
	}


static func _collect_gd_files(res_dir: String) -> Array[String]:
	var out: Array[String] = []
	var abs_dir: String = ProjectSettings.globalize_path(res_dir)
	var da: DirAccess = DirAccess.open(abs_dir)
	if da == null:
		return out
	da.list_dir_begin()
	var fname: String = da.get_next()
	while fname != "":
		if not da.current_is_dir() and fname.ends_with(".gd"):
			out.append(abs_dir.path_join(fname))
		fname = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


static func _test_zero_node_boundary() -> void:
	var rx := RegEx.new()
	rx.compile("(?m)(^\\s*extends\\s+(Node|Node2D|Control|SceneTree)\\b|\\bget_node\\s*\\(|\\bSceneTree\\b|\\bInput\\.)")
	var files: Array[String] = []
	files.append_array(_collect_gd_files("res://scripts/shared"))
	files.append_array(_collect_gd_files("res://scripts/domain"))
	_check_eq(files.size(), 19, "Expected 6 shared + 13 domain = 19 scripts")
	for fpath in files:
		var fa: FileAccess = FileAccess.open(fpath, FileAccess.READ)
		_check(fa != null, "Readable script: %s" % fpath)
		if fa != null:
			var src: String = fa.get_as_text()
			fa.close()
			var m: RegExMatch = rx.search(src)
			_check(m == null, "Zero-Node violation in %s: %s" % [fpath.get_file(), m.get_string() if m != null else ""])


static func _test_content_id() -> void:
	_check(ContentId.is_valid("core:department.operations"), "Valid core content ID")
	_check(ContentId.is_valid("com.mod_1:policy.alpha-2"), "Valid mod content ID")
	_check(not ContentId.is_valid(""), "Empty content ID rejected")
	_check(not ContentId.is_valid("no_colon"), "Missing colon rejected")
	_check(not ContentId.is_valid("Core:Upper"), "Uppercase rejected")
	_check(not ContentId.is_valid("core:dept\n"), "Trailing newline rejected")
	_check(not ContentId.is_valid("core:dept space"), "Whitespace rejected")
	_check_eq(ContentId.get_namespace("core:policy.a"), "core", "get_namespace")
	_check_eq(ContentId.get_local_id("core:policy.a"), "policy.a", "get_local_id")
	_check(ContentId.is_core("core:event.boom"), "is_core true")
	_check(not ContentId.is_core("mod.x:event.boom"), "is_core false for mod")
	_check(ContentId.is_valid_mod_id("com.example.mod_1"), "Valid mod ID")
	_check(not ContentId.is_valid_mod_id("single"), "Single segment mod ID rejected")
	_check(ContentId.is_valid_semver("1.2.3"), "Valid semver")
	_check(not ContentId.is_valid_semver("1.2"), "Invalid semver rejected")
	var bad_res: Result = ContentId.validate("BAD")
	_check(not bad_res.ok and bad_res.error_code != &"" and bad_res.error_key != "", "ContentId.validate fail populates error_code and error_key")


static func _test_shared_types() -> void:
	var r_ok1: Result = Result.success({"x": 1})
	var r_ok2: Result = Result.succeed(42)
	var r_err: Result = Result.fail(&"TEST_ERR", "", {"k": "v"})
	_check(r_ok1.ok and r_ok1.is_ok() and not r_ok1.is_err(), "Result.success works")
	_check(r_ok2.ok and int(r_ok2.data) == 42, "Result.succeed works")
	_check(not r_err.ok and r_err.error_code == &"TEST_ERR" and r_err.error_key == "ERR_TEST_ERR", "Result.fail populates fallback error_key")

	# Exact enum ordinals required by M2 & E2E
	_check_eq(int(Enums.EmployeeState.WORKING), 2, "EmployeeState.WORKING == 2")
	_check_eq(int(Enums.EmployeeState.OFF_DUTY), 5, "EmployeeState.OFF_DUTY == 5")
	_check_eq(int(Enums.CustomerState.WAITING), 2, "CustomerState.WAITING == 2")
	_check_eq(int(Enums.CustomerState.COMPLETED), 4, "CustomerState.COMPLETED == 4")
	_check_eq(int(Enums.QueuePriority.VIP), 2, "QueuePriority.VIP == 2")
	_check_eq(int(Enums.LoanStatus.REPAID), 4, "LoanStatus.REPAID == 4")

	# FormatService
	var fmt := FormatService.new()
	_check_eq(fmt.call("format_time", 540), "09:00", "540 -> 09:00")
	_check_eq(FormatService.format_minute_of_day(1020), "17:00", "1020 -> 17:00")
	_check_eq(FormatService.format_bps(425), "4.25%", "425 -> 4.25%")
	_check_eq(FormatService.format_money(123456, "CNY", false), "¥1,234.56", "format_money positive")
	_check_eq(FormatService.format_signed_delta(-5000, "CNY"), "-¥50.00", "format_signed_delta negative")
	_check_eq(FormatService.format_money_compact(150_000_000, "CNY"), "¥1.5M", "format_money_compact M")

	# DomainEvent
	var ev := DomainEvent.new(DomainEvent.EVT_LOAN_APPROVED, 3, 610, {"loan_id": "loan_0001"})
	var ev_rt: DomainEvent = DomainEvent.from_dict(ev.to_dict())
	_check_eq(ev_rt.event_type, DomainEvent.EVT_LOAN_APPROVED, "DomainEvent roundtrip type")
	_check_eq(ev_rt.day, 3, "DomainEvent roundtrip day")


static func _test_rng_streams() -> void:
	var r1 := RngStreams.new(20261121)
	var r2 := RngStreams.new(20261121)
	for _i in range(25):
		_check_eq(r1.customer_rng.randi(), r2.customer_rng.randi(), "Identical seed customer_rng")
		_check_eq(r1.event_rng.randi(), r2.event_rng.randi(), "Identical seed event_rng")
		_check_eq(r1.market_rng.randi(), r2.market_rng.randi(), "Identical seed market_rng")
		_check_eq(r1.candidate_rng.randi(), r2.candidate_rng.randi(), "Identical seed candidate_rng")

	var json_str: String = JSON.stringify(r1.to_dict())
	var parsed: Variant = JSON.parse_string(json_str)
	_check(parsed is Dictionary, "RngStreams JSON parsed")
	var res: Result = RngStreams.from_dict(parsed as Dictionary)
	_check(res.ok, "RngStreams.from_dict succeeded")
	if res.ok:
		var r1_restored: RngStreams = res.data as RngStreams
		for _i in range(20):
			_check_eq(r1_restored.customer_rng.randi(), r1.customer_rng.randi(), "Restored customer_rng parity")
			_check_eq(r1_restored.event_rng.randi(), r1.event_rng.randi(), "Restored event_rng parity")
			_check_eq(r1_restored.market_rng.randi(), r1.market_rng.randi(), "Restored market_rng parity")
			_check_eq(r1_restored.candidate_rng.randi(), r1.candidate_rng.randi(), "Restored candidate_rng parity")


static func _test_ledger() -> void:
	var ledger := Ledger.new()
	# Rejections
	_check(not ledger.post_entry(1, 540, "z", "Z", [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": 0},
		{"account": &"equity_capital", "side": "credit", "amount_minor": 0},
	]).ok, "Reject zero amount")
	_check(not ledger.post_entry(1, 540, "neg", "N", [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": -10},
		{"account": &"equity_capital", "side": "credit", "amount_minor": -10},
	]).ok, "Reject negative amount")
	_check(not ledger.post_entry(1, 540, "unb", "U", [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": 100},
		{"account": &"equity_capital", "side": "credit", "amount_minor": 99},
	]).ok, "Reject unbalanced entry")
	_check(not ledger.post_entry(1, 540, "one", "O", [
		{"account": &"cash_reserves", "side": "debit", "amount_minor": 100},
	]).ok, "Reject single line")
	_check(not ledger.post_entry(1, 540, "bad_a", "A", [
		{"account": &"fake_account", "side": "debit", "amount_minor": 100},
		{"account": &"equity_capital", "side": "credit", "amount_minor": 100},
	]).ok, "Reject unknown account")
	_check(not ledger.post_entry(1, 540, "bad_s", "S", [
		{"account": &"cash_reserves", "side": "plus", "amount_minor": 100},
		{"account": &"equity_capital", "side": "credit", "amount_minor": 100},
	]).ok, "Reject invalid side")

	# 550 entries -> cap at 500, cumulative balance exact
	for i in range(550):
		var pr: Result = ledger.post_entry(1, 540, "c_%d" % i, "CAP", [
			{"account": &"cash_reserves", "side": "debit", "amount_minor": 10},
			{"account": &"equity_capital", "side": "credit", "amount_minor": 10},
		])
		if not pr.ok:
			_check(false, "Valid entry #%d failed" % i)
			break
	_check_eq(ledger.get_balance(&"cash_reserves"), 5500, "Cumulative cash balance 5500")
	_check_eq(ledger.get_entry_count(), 500, "Journal entry log capped at 500")
	var snap: Dictionary = ledger.get_balance_sheet_snapshot()
	_check(bool(snap.get("is_balanced", false)), "Ledger balanced after 550 entries")

	var json_data: Variant = JSON.parse_string(JSON.stringify(ledger.to_dict()))
	var rt_res: Result = Ledger.from_dict(json_data as Dictionary)
	_check(rt_res.ok, "Ledger.from_dict roundtrip ok")
	if rt_res.ok:
		var l2: Ledger = rt_res.data as Ledger
		_check_eq(l2.get_balance(&"cash_reserves"), 5500, "Ledger restored cash balance")
		_check_eq(l2.get_entry_count(), 500, "Ledger restored entry count")


static func _test_finance_engine() -> void:
	_check_eq(FinanceEngine.round_div(1, 2), 1, "round_div(1, 2) == 1")
	_check_eq(FinanceEngine.round_div(5, 2), 3, "round_div(5, 2) == 3")
	_check_eq(FinanceEngine.round_div(4, 2), 2, "round_div(4, 2) == 2")
	_check_eq(FinanceEngine.round_div(-1, 2), -1, "round_div(-1, 2) == -1")
	_check_eq(FinanceEngine.round_div(1000, 0), 0, "round_div(1000, 0) == 0")
	_check_eq(FinanceEngine.round_div(10_000_000_000 * 500, 10_000 * 365), 1_369_863, "64-bit round_div precision")

	var bs := BankState.create_starter_branch("Test Bank", 101)
	var fe := FinanceEngine.new()
	var mod := ModifierService.new()

	var dep_res: Result = fe.record_deposit(bs, 10_000_000, 1, 540, "d1")
	_check(dep_res.ok, "Deposit 10M ok")
	_check_eq(bs.ledger.get_balance_sheet_snapshot()["income"], 0, "Deposit is NOT income")

	_check(not fe.record_withdrawal(bs, 999_999_999, 1, 545, "bad_wd").ok, "Over-withdrawal rejected")
	_check(fe.record_withdrawal(bs, 1_000_000, 1, 545, "wd1").ok, "Valid withdrawal ok")

	var cust := CustomerInstance.new()
	var eval_res: Dictionary = fe.evaluate_loan_application(cust, {
		"principal_minor": 400_000,
		"annual_rate_bps": 700,
		"term_days": 30,
		"collateral_value": 200_000,
	}, bs, mod)
	_check(int(eval_res.get("credit_score", -1)) >= 0 and int(eval_res.get("credit_score", -1)) <= 100, "Credit score 0..100")

	var disb_res: Result = fe.disburse_loan(bs, "cust_1", 5_000_000, 730, 30, "l1")
	_check(disb_res.ok, "Disburse loan ok")
	var loan_obj: LoanInstance = disb_res.data as LoanInstance
	_check(fe.record_loan_repayment(bs, loan_obj.loan_id, 1_000_000, 1, 600).ok, "Loan repayment ok")
	_check_eq(loan_obj.principal_outstanding, 4_000_000, "Loan principal decremented")
	_check(fe.record_loan_repayment(bs, "unlinked_loan", 500_000, 1, 605).ok, "Unlinked loan repayment ok")

	_check(fe.record_service_fee(bs, 25_000, 1, 610, "f1").ok, "Service fee ok")
	_check(fe.record_event_expense(bs, 10_000, 1, 620, "e1").ok, "Event expense ok")

	var settle1: Result = fe.run_daily_settlement(bs, mod, bs.rng_streams.market_rng, {})
	_check(settle1.ok, "First daily settlement ok")
	var rec: Dictionary = settle1.data as Dictionary
	_check_eq(int(rec.get("day", 0)), 1, "Settlement day == 1")
	_check_eq(int(bs.ledger.get_balance_sheet_snapshot().get("income", -1)), 0, "Income closed to retained_earnings")
	_check_eq(int(bs.ledger.get_balance_sheet_snapshot().get("expense", -1)), 0, "Expense closed to retained_earnings")
	_check(bool(bs.ledger.get_balance_sheet_snapshot().get("is_balanced", false)), "Balanced post-settlement")

	# Idempotency check
	var cash_before: int = bs.ledger.get_balance(&"cash_reserves")
	var settle2: Result = fe.run_daily_settlement(bs, mod, bs.rng_streams.market_rng, {})
	_check(not settle2.ok, "Duplicate settlement on same day rejected")
	_check_eq(bs.ledger.get_balance(&"cash_reserves"), cash_before, "Cash unchanged after duplicate settlement")


static func _test_employee_and_customer() -> void:
	var emp := EmployeeInstance.new()
	emp.id = "emp_t1"
	emp.state = Enums.EmployeeState.OFF_DUTY
	_check(not emp.transition_to(Enums.EmployeeState.WORKING).ok, "Reject OFF_DUTY -> WORKING")
	_check(emp.transition_to(Enums.EmployeeState.AVAILABLE).ok, "Allow OFF_DUTY -> AVAILABLE")
	_check(emp.assign_task("req_1", Vector2i(4, 4)).ok, "Assign task ok")
	_check(not emp.assign_task("req_2", Vector2i(4, 4)).ok, "Reject concurrent task assignment")
	emp.complete_current_task()
	_check(emp.transition_to(Enums.EmployeeState.BREAK).ok, "Transition to BREAK")
	_check(not emp.transition_to(Enums.EmployeeState.WORKING).ok, "Reject BREAK -> WORKING")
	_check(not emp.reassign_station("teller_2", "teller", 2).ok, "Reject station assignment on BREAK")

	var cust := CustomerInstance.new()
	cust.id = "cust_t1"
	cust.patience_max = 3
	cust.patience_remaining = 3
	_check(cust.transition_to(Enums.CustomerState.WAITING).ok, "Customer SPAWNING -> WAITING")
	_check(not cust.tick_patience(2), "Patience 3->1 not timed out")
	_check(cust.tick_patience(1), "Patience 1->0 timed out")
	_check(cust.timed_out, "timed_out flag set")
	_check(cust.transition_to(Enums.CustomerState.IN_SERVICE).ok, "WAITING -> IN_SERVICE")
	_check(cust.transition_to(Enums.CustomerState.COMPLETED).ok, "IN_SERVICE -> COMPLETED")
	_check(not cust.transition_to(Enums.CustomerState.WAITING).ok, "Reject COMPLETED -> WAITING")


static func _test_loan_and_service_request() -> void:
	var loan := LoanInstance.new()
	loan.loan_id = "ln_1"
	loan.principal_original = 100_000
	loan.principal_outstanding = 100_000
	_check(loan.apply_repayment(40_000).ok, "Partial repayment ok")
	_check_eq(loan.principal_outstanding, 60_000, "Outstanding 60k")
	_check(loan.apply_repayment(60_000).ok, "Final repayment ok")
	_check_eq(loan.status, Enums.LoanStatus.REPAID, "Status REPAID")
	_check(not loan.apply_repayment(1000).ok, "Repayment on REPAID loan rejected")

	var r_low := ServiceRequest.new()
	r_low.request_id = "req_1"
	r_low.priority = Enums.QueuePriority.NORMAL
	r_low.created_at_minute = 540
	var r_vip := ServiceRequest.new()
	r_vip.request_id = "req_2"
	r_vip.priority = Enums.QueuePriority.VIP
	r_vip.created_at_minute = 550
	_check(ServiceRequest.compare_queue_order(r_vip, r_low), "VIP sorts ahead of older NORMAL request")
	_check(r_vip.assign("emp_1", "teller_1").ok, "Assign queued request ok")
	_check(not r_vip.assign("emp_2", "teller_2").ok, "Reject double assign")


static func _test_modifier_service() -> void:
	var mod := ModifierService.new()
	# Verify strictly 3 parameters on evaluate_effects
	var sig_args: int = -1
	for m in mod.get_method_list():
		if str(m.get("name", "")) == "evaluate_effects":
			sig_args = (m.get("args", []) as Array).size()
			break
	_check_eq(sig_args, 3, "ModifierService.evaluate_effects has strictly 3 params")

	var effs1: Array[Dictionary] = [
		{"target": "staff.productivity_bps", "operation": "multiply", "value": 15000, "scope": "global"},
		{"target": "staff.productivity_bps", "operation": "add", "value": 2000, "scope": "global"},
	]
	_check_eq(mod.evaluate_effects("staff.productivity_bps", 10000, effs1), 18000, "add before multiply: (10000+2000)*1.5=18000")

	var effs2: Array[Dictionary] = [
		{"target": "staff.productivity_bps", "operation": "add", "value": 2000},
		{"target": "staff.productivity_bps", "operation": "set", "value": 12000},
	]
	_check_eq(mod.evaluate_effects("staff.productivity_bps", 10000, effs2), 12000, "set overrides")

	var extreme: Array[Dictionary] = [
		{"target": "loan.default_risk_bps", "operation": "add", "value": 999999},
		{"target": "loan.default_risk_bps", "operation": "multiply", "value": 100000},
	]
	_check_eq(mod.evaluate_effects("loan.default_risk_bps", 500, extreme), 10000, "loan.default_risk_bps clamped <= 10000")

	# Non-whitelisted target ignored
	_check_eq(mod.evaluate_effects("bank.cash_infinite", 100, [{"target": "bank.cash_infinite", "operation": "add", "value": 999}]), 100, "Unknown target ignored")


static func _sample_defs() -> Dictionary:
	return {
		"departments": [
			{"id": "core:department.operations", "name_key": "D1", "description_key": "D1", "initial_cost_minor": 100_000, "daily_cost_minor": 10_000, "max_level": 3, "effects": [{"target": "staff.productivity_bps", "operation": "add", "value": 500, "scope": "global"}]},
			{"id": "core:department.hr", "name_key": "D2", "description_key": "D2", "initial_cost_minor": 100_000, "daily_cost_minor": 10_000, "max_level": 3, "effects": [{"target": "staff.productivity_bps", "operation": "add", "value": 300, "scope": "global"}]},
			{"id": "core:department.credit", "name_key": "D3", "description_key": "D3", "initial_cost_minor": 100_000, "daily_cost_minor": 10_000, "max_level": 3, "effects": []},
			{"id": "core:department.risk", "name_key": "D4", "description_key": "D4", "initial_cost_minor": 100_000, "daily_cost_minor": 10_000, "max_level": 3, "effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": -200, "scope": "global"}]},
		],
		"policies": [
			{"id": "core:policy.prudent_lending", "name_key": "P1", "description_key": "P1", "cost_strategy_points": 2, "exclusive_group": "doctrine_tier_1", "prerequisites": [], "effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": -300, "scope": "global"}]},
			{"id": "core:policy.liquidity_first", "name_key": "P2", "description_key": "P2", "cost_strategy_points": 3, "exclusive_group": "doctrine_tier_2", "prerequisites": ["core:policy.prudent_lending"], "effects": []},
			{"id": "core:policy.customer_trust", "name_key": "P3", "description_key": "P3", "cost_strategy_points": 4, "exclusive_group": "doctrine_tier_3", "prerequisites": ["core:policy.liquidity_first"], "effects": [{"target": "bank.reputation_points", "operation": "add", "value": 5, "scope": "global"}]},
			{"id": "core:policy.high_rate_acquisition", "name_key": "P4", "description_key": "P4", "cost_strategy_points": 2, "exclusive_group": "doctrine_tier_1", "prerequisites": [], "effects": []},
		],
		"events": [
			{
				"id": "core:event.real_estate_boom",
				"title_key": "E1", "description_key": "E1", "weight": 100, "cooldown_days": 10,
				"conditions": [{"type": "day_at_least", "value": 1}],
				"options": [
					{"id": "aggressive_expand", "label_key": "O1", "effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": 300, "scope": "global"}], "next_event_id": "core:event.real_estate_cooling"},
					{"id": "prudent_cap", "label_key": "O2", "effects": [{"target": "bank.reputation_points", "operation": "add", "value": 2, "scope": "global"}], "next_event_id": "core:event.real_estate_cooling"},
				],
			},
			{
				"id": "core:event.real_estate_cooling",
				"title_key": "E2", "description_key": "E2", "weight": 0, "cooldown_days": 10,
				"conditions": [],
				"options": [
					{"id": "tighten_credit", "label_key": "O1", "effects": [], "next_event_id": "core:event.real_estate_credit_stress"},
				],
			},
			{
				"id": "core:event.real_estate_credit_stress",
				"title_key": "E3", "description_key": "E3", "weight": 0, "cooldown_days": 10,
				"conditions": [],
				"options": [
					{"id": "emergency_provision", "label_key": "O1", "effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": 400, "scope": "global"}]},
				],
			},
		],
	}


static func _test_department_and_policy() -> void:
	var defs: Dictionary = _sample_defs()
	var bs := BankState.create_starter_branch("DeptPolicy", 202)
	var ds := DepartmentService.new()
	var ps := PolicyService.new()
	var mod := ModifierService.new()

	_check(ds.create_department(bs, "core:department.operations", defs).ok, "Create operations Lv.1")
	_check(not ds.create_department(bs, "core:department.operations", defs).ok, "Reject duplicate dept")
	_check(ds.upgrade_department(bs, "core:department.operations", defs).ok, "Upgrade operations Lv.2")
	_check(ds.is_capability_unlocked(bs, "auto_queue_priority"), "Operations Lv.2 capability unlocked")
	_check(ds.create_department(bs, "core:department.hr", defs).ok, "Create HR Lv.1")
	_check(ds.get_active_synergies(bs).has("synergy:hr_operations"), "HR+Ops synergy active")
	_check_eq(ds.get_onboarding_adaptation_days(bs, 3), 1, "HR+Ops shortens adaptation to 1 day")
	_check(mod.has_unlock(bs, defs, "synergy:hr_operations"), "ModifierService sees HR+Ops synergy unlock")

	# Dictionary dept entry compatibility
	bs.departments["core:department.credit"] = {"id": "core:department.credit", "level": 1}
	_check(ds.has_department(bs, "core:department.credit", 1), "Supports Dictionary department entry")

	# Player-chosen plot (grid_pos): stored, unique, enforced against stations, save-safe
	var bs_plot := BankState.create_starter_branch("DeptPlot", 203)
	var chosen_cell := Vector2i(4, 3)
	var plotted: Result = ds.create_department(bs_plot, "core:department.risk", defs, null, chosen_cell)
	_check(plotted.ok, "Create department on a player-chosen plot")
	_check_eq(DepartmentService.get_department_grid_pos(bs_plot, "core:department.risk"), chosen_cell, "Department stores the chosen grid_pos")
	_check(not ds.create_department(bs_plot, "core:department.hr", defs, null, chosen_cell).ok, "Reject a plot already taken by another department")
	_check(not ds.create_department(bs_plot, "core:department.hr", defs, null, Vector2i(4, 4)).ok, "Reject a plot taken by a service station")
	_check(not ds.create_department(bs_plot, "core:department.hr", defs, null, Vector2i(2, -1)).ok, "Reject a partially negative plot")

	var bs_legacy := BankState.create_starter_branch("DeptLegacy", 204)
	_check(ds.create_department(bs_legacy, "core:department.hr", defs).ok, "Unplaced legacy call (no grid_pos) still allowed")
	_check_eq(DepartmentService.get_department_grid_pos(bs_legacy, "core:department.hr"), Vector2i(-1, -1), "Unplaced department keeps (-1, -1)")
	_check_eq(DepartmentService.get_department_room_rect(bs_legacy, "core:department.hr"), Rect2i(), "Unplaced department has no room rect")

	# Whole-room footprint (construction-game style): stored, non-overlapping, save-safe
	var bs_room := BankState.create_starter_branch("DeptRoom", 205)
	var room_rect := Rect2i(Vector2i(2, 0), Vector2i(3, 3))
	_check(
		ds.create_department(bs_room, "core:department.operations", defs, null, room_rect.position, room_rect.size).ok,
		"Create a 3x3 department room"
	)
	_check_eq(
		DepartmentService.get_department_room_rect(bs_room, "core:department.operations"),
		room_rect,
		"Room rectangle is stored as a whole"
	)
	_check(
		not ds.create_department(bs_room, "core:department.hr", defs, null, Vector2i(3, 1), Vector2i(3, 3)).ok,
		"Reject a room overlapping an existing room"
	)
	bs_room.stations["t5_test_desk"] = {
		"station_id": "t5_test_desk",
		"station_type": "teller",
		"is_open": true,
		"grid_pos": Vector2i(6, 1),
	}
	_check(
		not ds.create_department(bs_room, "core:department.credit", defs, null, Vector2i(5, 0), Vector2i(3, 3)).ok,
		"Reject a room overlapping a service station footprint"
	)
	var room_json: Variant = JSON.parse_string(JSON.stringify(bs_room.to_dict()))
	var room_rt: Result = BankState.from_dict(room_json as Dictionary)
	_check(room_rt.ok, "Room save round-trip parsed")
	if room_rt.ok:
		_check_eq(
			DepartmentService.get_department_room_rect(room_rt.data as BankState, "core:department.operations"),
			room_rect,
			"Room rectangle survives JSON save/load"
		)

	var plot_json: Variant = JSON.parse_string(JSON.stringify(bs_plot.to_dict()))
	var plot_rt: Result = BankState.from_dict(plot_json as Dictionary)
	_check(plot_rt.ok, "Plot save round-trip parsed")
	if plot_rt.ok:
		var bs_plot_rt: BankState = plot_rt.data as BankState
		_check_eq(
			DepartmentService.get_department_grid_pos(bs_plot_rt, "core:department.risk"),
			chosen_cell,
			"grid_pos survives JSON save/load"
		)

	# Policy chain & exclusion
	bs.strategy_points = 20
	_check(not ps.adopt_policy(bs, "core:policy.liquidity_first", defs).ok, "Reject missing prerequisite")
	_check(ps.adopt_policy(bs, "core:policy.prudent_lending", defs).ok, "Adopt tier 1 conservative")
	_check(not ps.adopt_policy(bs, "core:policy.high_rate_acquisition", defs).ok, "Reject opposing exclusive branch")
	_check(ps.adopt_policy(bs, "core:policy.liquidity_first", defs).ok, "Adopt tier 2 conservative")
	_check(ps.adopt_policy(bs, "core:policy.customer_trust", defs).ok, "Adopt tier 3 conservative")


static func _test_event_engine() -> void:
	var defs: Dictionary = _sample_defs()
	var bs := BankState.create_starter_branch("EventTest", 303)
	var ee := EventEngine.new()

	_check(not ee.evaluate_condition({"type": "eval(1+1)", "value": true}, bs), "Unknown/eval condition returns false")
	_check(ee.evaluate_condition({"type": "metric_above", "value": {"metric": "reputation", "threshold": 40}}, bs), "metric_above true")

	var tr: Result = ee.trigger_event(bs, "core:event.real_estate_boom", defs)
	_check(tr.ok, "Trigger boom ok")
	var inst_id: String = str((tr.data as Dictionary).get("instance_id", ""))
	_check(not ee.resolve_event_option(bs, inst_id, "missing_opt", defs).ok, "Reject invalid option")
	_check(ee.resolve_event_option(bs, inst_id, "prudent_cap", defs).ok, "Resolve boom option ok")
	_check(not ee.resolve_event_option(bs, inst_id, "prudent_cap", defs).ok, "Reject double resolution")
	_check_eq(bs.scheduled_events.size(), 1, "Stage 2 cooling scheduled")

	# Advance day to trigger scheduled Stage 2 cooling
	bs.current_day = int(bs.scheduled_events[0].get("trigger_day", 3))
	var proc: Result = ee.process_scheduled_and_roll_event(bs, defs, bs.rng_streams.event_rng, 0)
	_check(proc.ok and bool((proc.data as Dictionary).get("chained", false)), "Scheduled Stage 2 event triggered")
	_check_eq(bs.active_events.size(), 1, "Stage 2 active")


static func _test_bank_state_roundtrip() -> void:
	var empty_bs := BankState.new()
	_check_eq(empty_bs.ledger.get_balance(&"cash_reserves"), 0, "BankState.new() starts with 0 cash")

	var bs := BankState.create_starter_branch("Roundtrip Bank", 9999)
	bs.departments["core:department.credit"] = {"id": "core:department.credit", "level": 1, "daily_cost_minor": 5000}
	bs.adopted_policies.append("core:policy.prudent_lending")
	var req := ServiceRequest.new()
	req.request_id = bs.next_id("req")
	req.customer_id = "c1"
	bs.service_requests.append(req)

	var json_text: String = JSON.stringify(bs.to_dict())
	var parsed: Variant = JSON.parse_string(json_text)
	_check(parsed is Dictionary, "BankState JSON parsed")
	var rt_res: Result = BankState.from_dict(parsed as Dictionary)
	_check(rt_res.ok, "BankState.from_dict succeeded")
	if rt_res.ok:
		var bs2: BankState = rt_res.data as BankState
		_check_eq(bs2.bank_name, "Roundtrip Bank", "Restored bank_name")
		_check_eq(bs2.world_seed, 9999, "Restored world_seed")
		_check_eq(bs2.ledger.get_balance(&"cash_reserves"), BalanceConfig.INITIAL_EQUITY_CAPITAL_MINOR, "Restored cash_reserves")
		_check_eq(bs2.employees.size(), bs.employees.size(), "Restored employees count")
		_check_eq(bs2.candidates.size(), bs.candidates.size(), "Restored candidates count")
		_check_eq(bs2.service_requests.size(), 1, "Restored typed service_requests")
		_check_eq(bs2.adopted_policies.size(), 1, "Restored typed adopted_policies")
		_check_eq(bs2.rng_streams.market_rng.randi(), bs.rng_streams.market_rng.randi(), "Restored rng_streams parity")
