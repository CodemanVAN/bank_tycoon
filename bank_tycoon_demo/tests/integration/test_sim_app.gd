extends SceneTree

## Integration tests for M4 Real-Time Simulation & Application Command Layer.

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("=== [M4 Integration Test] Starting test_sim_app.gd ===")
	_test_game_clock()
	_test_domain_event_bus()
	_test_dispatcher_and_queue_priority()
	_test_lobby_lifecycle_and_closing_cutoff()
	_test_bottleneck_timeout_and_hr_commands()
	_test_speed_equivalence_and_jitter_interleaving()
	_test_departments_policies_and_event_chain()
	_test_mid_day_save_load_replay_parity()
	_test_tier3_and_tier4_economic_scenarios()

	print("=== [M4 Integration Test] Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[M4 FAIL] %s" % msg)
		print("[M4 FAIL] %s" % msg)


func _check_eq(actual: Variant, expected: Variant, msg: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		var err: String = "%s (expected=%s, actual=%s)" % [msg, str(expected), str(actual)]
		push_error("[M4 FAIL] %s" % err)
		print("[M4 FAIL] %s" % err)


static func _sample_defs() -> Dictionary:
	return {
		"departments": [
			{
				"id": "core:department.operations",
				"name_key": "DEPT_OPERATIONS_NAME",
				"description_key": "DEPT_OPERATIONS_DESC",
				"initial_cost_minor": 100_000,
				"daily_cost_minor": 10_000,
				"max_level": 3,
				"effects": [{"target": "staff.productivity_bps", "operation": "add", "value": 500, "scope": "global"}],
			},
			{
				"id": "core:department.hr",
				"name_key": "DEPT_HR_NAME",
				"description_key": "DEPT_HR_DESC",
				"initial_cost_minor": 100_000,
				"daily_cost_minor": 10_000,
				"max_level": 3,
				"effects": [{"target": "staff.productivity_bps", "operation": "add", "value": 300, "scope": "global"}],
			},
			{
				"id": "core:department.credit",
				"name_key": "DEPT_CREDIT_NAME",
				"description_key": "DEPT_CREDIT_DESC",
				"initial_cost_minor": 120_000,
				"daily_cost_minor": 12_000,
				"max_level": 3,
				"effects": [],
			},
			{
				"id": "core:department.risk",
				"name_key": "DEPT_RISK_NAME",
				"description_key": "DEPT_RISK_DESC",
				"initial_cost_minor": 120_000,
				"daily_cost_minor": 12_000,
				"max_level": 3,
				"effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": -200, "scope": "global"}],
			},
		],
		"policies": [
			{
				"id": "core:policy.prudent_lending",
				"name_key": "POLICY_PRUDENT_LENDING_NAME",
				"description_key": "POLICY_PRUDENT_LENDING_DESC",
				"cost_strategy_points": 2,
				"exclusive_group": "doctrine_tier_1",
				"prerequisites": [],
				"effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": -300, "scope": "global"}],
			},
			{
				"id": "core:policy.liquidity_first",
				"name_key": "POLICY_LIQUIDITY_FIRST_NAME",
				"description_key": "POLICY_LIQUIDITY_FIRST_DESC",
				"cost_strategy_points": 3,
				"exclusive_group": "doctrine_tier_2",
				"prerequisites": ["core:policy.prudent_lending"],
				"effects": [],
			},
			{
				"id": "core:policy.high_rate_acquisition",
				"name_key": "POLICY_HIGH_RATE_ACQUISITION_NAME",
				"description_key": "POLICY_HIGH_RATE_ACQUISITION_DESC",
				"cost_strategy_points": 2,
				"exclusive_group": "doctrine_tier_1",
				"prerequisites": [],
				"effects": [{"target": "customer.deposit_growth_bps", "operation": "add", "value": 1500, "scope": "global"}],
			},
		],
		"events": [
			{
				"id": "core:event.real_estate_boom",
				"title_key": "EVENT_REAL_ESTATE_BOOM_TITLE",
				"description_key": "EVENT_REAL_ESTATE_BOOM_DESC",
				"weight": 100,
				"cooldown_days": 10,
				"conditions": [{"type": "day_at_least", "value": 1}],
				"options": [
					{
						"id": "aggressive_expand",
						"label_key": "O1",
						"effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": 300, "scope": "global"}],
						"next_event_id": "core:event.real_estate_cooling",
					},
					{
						"id": "prudent_cap",
						"label_key": "O2",
						"effects": [{"target": "bank.reputation_points", "operation": "add", "value": 2, "scope": "global"}],
						"next_event_id": "core:event.real_estate_cooling",
					},
				],
			},
			{
				"id": "core:event.real_estate_cooling",
				"title_key": "EVENT_REAL_ESTATE_COOLING_TITLE",
				"description_key": "EVENT_REAL_ESTATE_COOLING_DESC",
				"weight": 0,
				"cooldown_days": 10,
				"conditions": [],
				"options": [
					{
						"id": "tighten_credit",
						"label_key": "O1",
						"effects": [],
						"next_event_id": "core:event.real_estate_credit_stress",
					},
				],
			},
			{
				"id": "core:event.real_estate_credit_stress",
				"title_key": "EVENT_REAL_ESTATE_CREDIT_STRESS_TITLE",
				"description_key": "EVENT_REAL_ESTATE_CREDIT_STRESS_DESC",
				"weight": 0,
				"cooldown_days": 10,
				"conditions": [],
				"options": [
					{
						"id": "emergency_provision",
						"label_key": "O1",
						"effects": [{"target": "loan.default_risk_bps", "operation": "add", "value": 400, "scope": "global"}],
					},
				],
			},
		],
	}


func _test_game_clock() -> void:
	var clk := GameClock.new()
	clk.minute_duration_sec = 0.25
	_check(clk.set_speed(0).ok, "set_speed(0) valid")
	_check_eq(clk.advance(10.0), 0, "speed=0 freezes ticks")
	_check(not clk.set_speed(-1).ok, "set_speed(-1) rejected")
	_check(not clk.set_speed(4).ok, "set_speed(4) rejected")
	_check(clk.set_speed(3).ok, "set_speed(3) valid")
	_check_eq(clk.speed, 3, "clock.speed synced with speed_multiplier")
	_check_eq(clk.advance(0.25 / 3.0), 1, "3x single minute step handles IEEE-754 precision cleanly")
	_check_eq(clk.advance(60.0), BalanceConfig.MAX_TICKS_PER_FRAME, "Huge delta clamped to MAX_TICKS_PER_FRAME=5")


func _test_domain_event_bus() -> void:
	var bus := DomainEventBus.new()
	var domain_events: Array[String] = []
	var ui_events: Array[String] = []
	bus.domain_event_emitted.connect(func(ev: DomainEvent) -> void:
		domain_events.append(String(ev.event_type))
	)
	bus.event_published.connect(func(et: StringName, _p: Dictionary) -> void:
		ui_events.append(String(et))
	)
	bus.publish(&"CustomerArrived", {"customer_id": "c_1"}, 1, 545)
	_check_eq(domain_events.size(), 1, "domain_event_emitted fired")
	_check_eq(domain_events[0], "CustomerArrived", "PascalCase on domain_event_emitted")
	_check_eq(ui_events[0], "customer_arrived", "snake_case on event_published")
	_check_eq(bus.recent_log.size(), 1, "recent_log recorded")


func _test_dispatcher_and_queue_priority() -> void:
	var bs := BankState.create_starter_branch("Dispatch Test", 305)
	var host := SimulationHost.new()
	host.bind_session(bs, _sample_defs())
	var cmd: BankCommandService = host.command_service

	for sid: Variant in bs.stations.keys():
		var st: Dictionary = bs.stations[sid] as Dictionary
		if bool(st.get("is_open", false)):
			cmd.toggle_station_open(str(sid))

	_check(cmd.open_branch_for_day().ok, "open_branch_for_day")
	var paired: Array[ServiceRequest] = []
	var guard: int = 0
	while paired.size() < 2 and guard < 200:
		host.step_simulation(0.25)
		guard += 1
		paired.clear()
		for rq in bs.service_requests:
			if String(rq.service_type) == "cash_deposit":
				paired.append(rq)

	_check(paired.size() >= 2, "Accumulated >= 2 cash_deposit requests while stations closed")
	var high_id: String = paired.back().request_id
	_check(cmd.set_queue_priority(high_id, Enums.QueuePriority.VIP).ok, "set_queue_priority VIP")

	var started: Array[String] = []
	host.event_bus.domain_event_emitted.connect(func(ev: DomainEvent) -> void:
		if ev.event_type == &"ServiceStarted":
			started.append(str(ev.payload.get("request_id", "")))
	)

	var teller_emp_id: String = ""
	for eid: Variant in bs.employees.keys():
		var e: EmployeeInstance = bs.employees[eid] as EmployeeInstance
		if e.role_id == "teller":
			teller_emp_id = e.id
			break

	_check(cmd.toggle_station_open("teller_1").ok, "Open teller_1")
	_check(cmd.assign_employee_to_station(teller_emp_id, "teller_1").ok, "Assign teller to teller_1")
	host.step_simulation(0.25)
	_check(not started.is_empty(), "ServiceStarted emitted")
	if not started.is_empty():
		_check_eq(started[0], high_id, "VIP request dispatched first")
	host.free()


func _test_lobby_lifecycle_and_closing_cutoff() -> void:
	var bs := BankState.create_starter_branch("Lifecycle Test", 303)
	var host := SimulationHost.new()
	host.bind_session(bs, _sample_defs())
	var cmd: BankCommandService = host.command_service

	var counts: Dictionary = {"arrived": 0, "started": 0, "completed": 0, "after_1700": 0}
	host.event_bus.domain_event_emitted.connect(func(ev: DomainEvent) -> void:
		var et: String = String(ev.event_type)
		if et == "CustomerArrived":
			counts["arrived"] = int(counts["arrived"]) + 1
			if bs.current_minute_of_day >= 1020:
				counts["after_1700"] = int(counts["after_1700"]) + 1
		elif et == "ServiceStarted":
			counts["started"] = int(counts["started"]) + 1
		elif et == "ServiceCompleted":
			counts["completed"] = int(counts["completed"]) + 1
	)

	_check(cmd.open_branch_for_day().ok, "open_branch_for_day")
	for _i in range(510):
		host.step_simulation(0.25)

	_check(int(counts["arrived"]) > 0, "Customers arrived before 17:00")
	_check(int(counts["started"]) > 0, "Services started")
	_check(int(counts["completed"]) > 0, "Services completed")
	_check_eq(int(counts["after_1700"]), 0, "Zero customer spawns at or after 17:00")
	_check(bool(bs.ledger.get_balance_sheet_snapshot().get("is_balanced", false)), "Ledger balanced")
	host.free()


func _test_bottleneck_timeout_and_hr_commands() -> void:
	var bs := BankState.create_starter_branch("Bottleneck HR", 2304)
	var host := SimulationHost.new()
	host.bind_session(bs, _sample_defs())
	var cmd: BankCommandService = host.command_service

	for sid: Variant in bs.stations.keys():
		var st: Dictionary = bs.stations[sid] as Dictionary
		if bool(st.get("is_open", false)):
			cmd.toggle_station_open(str(sid))

	var unserved: Array[int] = [0]
	host.event_bus.domain_event_emitted.connect(func(ev: DomainEvent) -> void:
		if ev.event_type == &"CustomerLeftUnserved":
			unserved[0] += 1
	)
	var sat0: int = bs.satisfaction
	cmd.open_branch_for_day()
	for _i in range(250):
		host.step_simulation(0.25)
	_check(unserved[0] > 0, "Bottleneck emits CustomerLeftUnserved")
	_check(bs.satisfaction < sat0, "Timeout reduces satisfaction")

	var cand_id: String = bs.candidates[0].id
	_check(cmd.hire_candidate(cand_id, "teller").ok, "hire_candidate")
	_check(cmd.train_employee(cand_id).ok, "train_employee")
	var emp: EmployeeInstance = bs.employees[cand_id] as EmployeeInstance
	emp.fatigue = 50
	_check(cmd.rest_employee(cand_id).ok, "rest_employee")
	_check(not cmd.assign_employee_to_station(cand_id, "teller_1").ok, "Cannot assign resting employee")
	for _i in range(15):
		host.step_simulation(0.25)
	_check(emp.fatigue < 50, "Resting recovers fatigue")
	_check(cmd.fire_employee(cand_id).ok, "fire_employee")
	_check(not bs.employees.has(cand_id), "Fired employee removed")
	host.free()


func _test_speed_equivalence_and_jitter_interleaving() -> void:
	var defs: Dictionary = _sample_defs()
	var bs1 := BankState.create_starter_branch("Speed1x", 4205)
	var h1 := SimulationHost.new()
	h1.bind_session(bs1, defs)
	h1.command_service.assign_employee_to_station("emp_0001", "loan_1")

	for d in range(1, 5):
		h1.command_service.open_branch_for_day()
		if d == 3:
			h1.command_service.set_interest_rates(250, 700)
			h1.command_service.create_department("core:department.operations")
		for _m in range(480):
			h1.step_simulation(0.25)
		h1.command_service.advance_to_next_day()

	var bs2 := BankState.create_starter_branch("Speed3x", 4205)
	var h2 := SimulationHost.new()
	h2.bind_session(bs2, defs)
	h2.command_service.assign_employee_to_station("emp_0001", "loan_1")
	var jitter: Array[float] = [0.016, 0.05, 0.2, 0.4, 0.5]
	var target_sec: float = 480.0 * 0.25 / 3.0

	for d in range(1, 5):
		h2.command_service.open_branch_for_day()
		if d == 3:
			h2.command_service.set_speed(0)
			h2.step_simulation(1.0)
			h2.command_service.set_interest_rates(250, 700)
			h2.command_service.create_department("core:department.operations")
		h2.command_service.set_speed(3)
		var acc_t: float = 0.0
		var idx: int = 0
		while bs2.current_minute_of_day < 1020 and acc_t < target_sec + 1.0:
			var raw_dt: float = jitter[idx % jitter.size()]
			var step_dt: float = raw_dt if bs2.current_minute_of_day < 960 else minf(raw_dt, 0.25 / 3.0)
			h2.step_simulation(step_dt)
			acc_t += step_dt
			idx += 1
		var rem: int = 1020 - bs2.current_minute_of_day
		for _r in range(rem):
			h2.step_simulation(0.25 / 3.0)
		h2.command_service.advance_to_next_day()

	_check_eq(bs2.ledger.get_balance(&"cash_reserves"), bs1.ledger.get_balance(&"cash_reserves"), "1x vs 3x jitter cash parity")
	_check_eq(bs2.ledger.get_balance(&"retained_earnings"), bs1.ledger.get_balance(&"retained_earnings"), "1x vs 3x jitter retained_earnings parity")
	h1.free()
	h2.free()


func _test_departments_policies_and_event_chain() -> void:
	var defs: Dictionary = _sample_defs()
	var bs := BankState.create_starter_branch("EventChain", 407)
	var host := SimulationHost.new()
	host.bind_session(bs, defs)
	var cmd: BankCommandService = host.command_service

	_check(cmd.create_department("core:department.operations").ok, "create operations")
	_check(cmd.upgrade_department("core:department.operations").ok, "upgrade operations Lv.2")
	_check(cmd.create_department("core:department.hr").ok, "create hr")
	_check(cmd.adopt_policy("core:policy.prudent_lending").ok, "adopt prudent_lending")
	_check(not cmd.adopt_policy("core:policy.high_rate_acquisition").ok, "reject opposing policy")

	var ee := EventEngine.new()
	var tr: Result = ee.trigger_event(bs, "core:event.real_estate_boom", defs)
	_check(tr.ok, "trigger real_estate_boom")
	var inst_id: String = str((tr.data as Dictionary).get("instance_id", ""))
	_check(cmd.resolve_event_option(inst_id, "aggressive_expand").ok, "resolve boom")

	var saw_cooling: bool = false
	var saw_stress: bool = false
	for _d in range(10):
		cmd.open_branch_for_day()
		for _m in range(480):
			host.step_simulation(0.25)
		cmd.advance_to_next_day()
		for ev in bs.active_events.duplicate():
			var eid: String = str(ev.get("event_id", ""))
			if eid == "core:event.real_estate_cooling":
				saw_cooling = true
				cmd.resolve_event_option(str(ev.get("instance_id", "")), "tighten_credit")
			elif eid == "core:event.real_estate_credit_stress":
				saw_stress = true
				cmd.resolve_event_option(str(ev.get("instance_id", "")), "emergency_provision")

	_check(saw_cooling, "Chained Stage 2 real_estate_cooling activated")
	_check(saw_stress, "Chained Stage 3 real_estate_credit_stress activated")
	host.free()


func _test_mid_day_save_load_replay_parity() -> void:
	var defs: Dictionary = _sample_defs()
	var bs_a := BankState.create_starter_branch("Replay", 7777)
	var host_a := SimulationHost.new()
	host_a.bind_session(bs_a, defs)
	host_a.command_service.assign_employee_to_station("emp_0001", "loan_1")

	for _d in range(3):
		host_a.command_service.open_branch_for_day()
		for _m in range(480):
			host_a.step_simulation(0.25)
		host_a.command_service.advance_to_next_day()

	var bs_b := BankState.create_starter_branch("Replay", 7777)
	var host_b1 := SimulationHost.new()
	host_b1.bind_session(bs_b, defs)
	host_b1.command_service.assign_employee_to_station("emp_0001", "loan_1")

	host_b1.command_service.open_branch_for_day()
	for _m in range(480):
		host_b1.step_simulation(0.25)
	host_b1.command_service.advance_to_next_day()

	host_b1.command_service.open_branch_for_day()
	for _m in range(180):
		host_b1.step_simulation(0.25)

	var serialized: String = JSON.stringify(bs_b.to_dict())
	var parsed: Dictionary = JSON.parse_string(serialized) as Dictionary
	var load_res: Result = BankState.from_dict(parsed)
	_check(load_res.ok, "Mid-day BankState roundtrip from_dict ok")
	var bs_loaded: BankState = load_res.data as BankState

	var host_b2 := SimulationHost.new()
	host_b2.bind_session(bs_loaded, defs)
	for _m in range(300):
		host_b2.step_simulation(0.25)
	host_b2.command_service.advance_to_next_day()

	host_b2.command_service.open_branch_for_day()
	for _m in range(480):
		host_b2.step_simulation(0.25)
	host_b2.command_service.advance_to_next_day()

	_check_eq(bs_loaded.current_day, bs_a.current_day, "Mid-day reload day parity")
	_check_eq(bs_loaded.ledger.get_balance(&"cash_reserves"), bs_a.ledger.get_balance(&"cash_reserves"), "Mid-day reload cash parity")
	_check_eq(bs_loaded.ledger.get_balance(&"customer_deposits"), bs_a.ledger.get_balance(&"customer_deposits"), "Mid-day reload deposits parity")
	_check_eq(bs_loaded.daily_reports, bs_a.daily_reports, "Mid-day reload daily_reports parity")

	host_a.free()
	host_b1.free()
	host_b2.free()


func _test_tier3_and_tier4_economic_scenarios() -> void:
	var defs: Dictionary = _sample_defs()

	# Snapshot keys contract
	var bs_snap := BankState.create_starter_branch("Snap", 100)
	var h_snap := SimulationHost.new()
	h_snap.bind_session(bs_snap, defs)
	var snap: Dictionary = h_snap.get_snapshot()
	for req_k in [
		"day", "minute", "phase", "speed", "cash_minor", "deposits_minor", "loans_minor",
		"equity_minor", "today_profit_minor", "satisfaction", "reputation", "strategy_points",
		"employee_count", "queue_length", "waiting_customers", "pending_approvals",
		"active_events", "liquidity_ratio_bps", "liquidity_status", "npl_ratio_bps",
		"deposit_rate_bps", "loan_base_rate_bps"
	]:
		_check(snap.has(req_k), "SimulationHost.get_snapshot has key: %s" % req_k)
	_check(h_snap.command_service.can_create_department("core:department.operations").ok, "can_create_department ok")
	_check(not h_snap.command_service.can_upgrade_department("core:department.operations").ok, "can_upgrade_department fails before creation")
	h_snap.free()

	# T3_01: Operations Lv.2 throughput >= baseline
	var bs_t31_a := BankState.create_starter_branch("T31A", 8001)
	var h_t31_a := SimulationHost.new()
	h_t31_a.bind_session(bs_t31_a, defs)
	h_t31_a.command_service.assign_employee_to_station("emp_0001", "loan_1")
	var comp_a: Array[int] = [0]
	h_t31_a.event_bus.domain_event_emitted.connect(func(ev: DomainEvent) -> void:
		if ev.event_type == &"ServiceCompleted":
			comp_a[0] += 1
	)
	h_t31_a.command_service.open_branch_for_day()
	for _m in range(480):
		h_t31_a.step_simulation(0.25)
	h_t31_a.command_service.advance_to_next_day()

	var bs_t31_b := BankState.create_starter_branch("T31B", 8001)
	var h_t31_b := SimulationHost.new()
	h_t31_b.bind_session(bs_t31_b, defs)
	h_t31_b.command_service.create_department("core:department.operations")
	h_t31_b.command_service.upgrade_department("core:department.operations")
	h_t31_b.command_service.assign_employee_to_station("emp_0001", "loan_1")
	var comp_b: Array[int] = [0]
	h_t31_b.event_bus.domain_event_emitted.connect(func(ev: DomainEvent) -> void:
		if ev.event_type == &"ServiceCompleted":
			comp_b[0] += 1
	)
	h_t31_b.command_service.open_branch_for_day()
	var prio_ok: bool = false
	for _m in range(480):
		h_t31_b.step_simulation(0.25)
		if not prio_ok and not bs_t31_b.service_requests.is_empty():
			prio_ok = h_t31_b.command_service.set_queue_priority(bs_t31_b.service_requests[0].request_id, 2).ok
	h_t31_b.command_service.advance_to_next_day()
	_check(prio_ok, "T3_01 priority exercised on active/queued request")
	_check(comp_b[0] >= comp_a[0], "T3_01 Operations Lv.2 throughput >= baseline (%d >= %d)" % [comp_b[0], comp_a[0]])
	h_t31_a.free()
	h_t31_b.free()

	# T3_07: HR Lv.3 fatigue mitigation
	var bs_f_a := BankState.create_starter_branch("FatA", 9006)
	var h_f_a := SimulationHost.new()
	h_f_a.bind_session(bs_f_a, defs)
	h_f_a.command_service.assign_employee_to_station("emp_0001", "loan_1")

	var bs_f_b := BankState.create_starter_branch("FatB", 9006)
	var h_f_b := SimulationHost.new()
	h_f_b.bind_session(bs_f_b, defs)
	h_f_b.command_service.create_department("core:department.hr")
	h_f_b.command_service.upgrade_department("core:department.hr")
	h_f_b.command_service.upgrade_department("core:department.hr")
	h_f_b.command_service.assign_employee_to_station("emp_0001", "loan_1")

	for d in range(1, 4):
		h_f_a.command_service.open_branch_for_day()
		h_f_b.command_service.open_branch_for_day()
		for _m in range(480):
			h_f_a.step_simulation(0.25)
			h_f_b.step_simulation(0.25)
		if d == 3:
			var fa_eod: int = _avg_emp_fatigue(bs_f_a)
			var fb_eod: int = _avg_emp_fatigue(bs_f_b)
			_check(fa_eod > 0, "Day 3 EOD baseline fatigue > 0 (got %d)" % fa_eod)
			_check(fb_eod <= fa_eod, "HR Lv.3 EOD fatigue <= baseline (%d <= %d)" % [fb_eod, fa_eod])
		h_f_a.command_service.advance_to_next_day()
		h_f_b.command_service.advance_to_next_day()
	_check(_avg_emp_fatigue(bs_f_b) <= _avg_emp_fatigue(bs_f_a), "HR Lv.3 overnight fatigue <= baseline")
	h_f_a.free()
	h_f_b.free()

	# T4_03: Liquidity stress (< 1.5) and player recovery (>= 1.5)
	var bs_liq := BankState.create_starter_branch("LiqTest", 4203)
	var h_liq := SimulationHost.new()
	h_liq.bind_session(bs_liq, defs)
	h_liq.command_service.assign_employee_to_station("emp_0001", "loan_1")
	var fe := FinanceEngine.new()
	fe.record_deposit(bs_liq, 20_000_000, 1, 540, "d_liq")
	var cash_avail: int = bs_liq.ledger.get_balance(&"cash_reserves")
	fe.disburse_loan(bs_liq, "c_liq", int(float(cash_avail) * 0.78), 700, 30, "liq_loan")
	var low_seen: bool = false
	for _d in range(3):
		h_liq.command_service.open_branch_for_day()
		for _m in range(480):
			h_liq.step_simulation(0.25)
		h_liq.command_service.advance_to_next_day()
		var lr: float = float((bs_liq.daily_reports.back() as Dictionary).get("liquidity_ratio", 99.0))
		if lr < 1.5:
			low_seen = true
	h_liq.command_service.set_interest_rates(400, 750)
	fe.record_deposit(bs_liq, 30_000_000, bs_liq.current_day, 545, "d_recov")
	for _d in range(3):
		h_liq.command_service.open_branch_for_day()
		for _m in range(480):
			h_liq.step_simulation(0.25)
		h_liq.command_service.advance_to_next_day()
	var final_lr: float = float((bs_liq.daily_reports.back() as Dictionary).get("liquidity_ratio", 0.0))
	_check(low_seen, "T4_03 Liquidity stress < 1.5 observed")
	_check(final_lr >= 1.5, "T4_03 Recovered liquidity_ratio >= 1.5 (got %.2f)" % final_lr)
	h_liq.free()


static func _avg_emp_fatigue(bs: BankState) -> int:
	if bs.employees.is_empty():
		return 0
	var total: int = 0
	for e_v: Variant in bs.employees.values():
		if e_v is EmployeeInstance:
			total += (e_v as EmployeeInstance).fatigue
	return total / bs.employees.size()

