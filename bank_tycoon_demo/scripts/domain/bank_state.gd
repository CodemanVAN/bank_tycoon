class_name BankState
extends RefCounted

## Root domain state container for a bank branch simulation and save persistence.

var world_seed: int = 20261121
var bank_name: String = "Starway Bank"
var currency_code: String = "CNY"
var current_day: int = 1
var current_minute_of_day: int = BalanceConfig.BUSINESS_OPEN_MINUTE
var day_phase: int = Enums.DayPhase.PRE_OPEN
var speed_multiplier: int = 1

var ledger: Ledger = null
var rng_streams: RngStreams = null

var employees: Dictionary = {}
var candidates: Array[EmployeeInstance] = []
var active_customers: Dictionary = {}
var service_requests: Array[ServiceRequest] = []
var loans: Dictionary = {}
var pending_loan_approvals: Array[Dictionary] = []
var pending_resignations: Array[Dictionary] = []

var departments: Dictionary = {}
var adopted_policies: Array[String] = []
var active_events: Array[Dictionary] = []
var event_history: Array[Dictionary] = []
var scheduled_events: Array[Dictionary] = []
var active_event_modifiers: Array[Dictionary] = []

var daily_reports: Array[Dictionary] = []
var settled_days: Array[int] = []
var last_settled_day: int = 0

var stations: Dictionary = {}
var lobby_props: Dictionary = {}

var reputation: int = BalanceConfig.INITIAL_REPUTATION
var satisfaction: int = BalanceConfig.INITIAL_SATISFACTION
var awareness: int = BalanceConfig.INITIAL_AWARENESS
var strategy_points: int = BalanceConfig.INITIAL_STRATEGY_POINTS
var deposit_rate_bps: int = BalanceConfig.DEFAULT_DEPOSIT_RATE_BPS
var loan_base_rate_bps: int = BalanceConfig.DEFAULT_LOAN_BASE_RATE_BPS
var loan_repayment_mode: String = "equal_installment"

var mod_dependencies: Array[Dictionary] = []
var next_entity_seq: int = 1


func _init(p_world_seed: int = 20261121, p_bank_name: String = "Starway Bank") -> void:
	world_seed = p_world_seed
	bank_name = p_bank_name
	ledger = Ledger.new()
	rng_streams = RngStreams.new(world_seed)


func next_id(prefix: String) -> String:
	var out: String = "%s_%04d" % [prefix, next_entity_seq]
	next_entity_seq += 1
	return out


static func create_starter_branch(
	p_bank_name: String = "Starway Bank",
	p_world_seed: int = 20261121
) -> BankState:
	var state := BankState.new(p_world_seed, p_bank_name)
	state.initialize_starter_branch()
	return state


func initialize_starter_branch() -> void:
	if ledger.get_balance(&"equity_capital") == 0 and ledger.get_balance(&"cash_reserves") == 0:
		ledger.post_entry(
			current_day,
			BalanceConfig.BUSINESS_OPEN_MINUTE,
			"init_cap",
			"LEDGER_INIT_CAPITAL",
			[
				{
					"account": &"cash_reserves",
					"side": "debit",
					"amount_minor": BalanceConfig.INITIAL_EQUITY_CAPITAL_MINOR,
				},
				{
					"account": &"equity_capital",
					"side": "credit",
					"amount_minor": BalanceConfig.INITIAL_EQUITY_CAPITAL_MINOR,
				},
			]
		)

	if stations.is_empty():
		stations = {
			"teller_1": {
				"station_id": "teller_1",
				"station_type": "teller",
				"is_open": true,
				"assigned_employee_id": "",
				"grid_pos": Vector2i(4, 4),
				"allowed_services": ["cash_deposit", "cash_withdrawal", "transfer", "account_opening", "complaint"],
			},
			"teller_2": {
				"station_id": "teller_2",
				"station_type": "teller",
				"is_open": true,
				"assigned_employee_id": "",
				"grid_pos": Vector2i(6, 4),
				"allowed_services": ["cash_deposit", "cash_withdrawal", "transfer", "account_opening", "complaint"],
			},
			"teller_3": {
				"station_id": "teller_3",
				"station_type": "teller",
				"is_open": false,
				"assigned_employee_id": "",
				"grid_pos": Vector2i(8, 4),
				"allowed_services": ["cash_deposit", "cash_withdrawal", "transfer", "account_opening", "complaint"],
			},
			"loan_1": {
				"station_id": "loan_1",
				"station_type": "loan_desk",
				"is_open": true,
				"assigned_employee_id": "",
				"grid_pos": Vector2i(11, 4),
				"allowed_services": ["personal_loan_application", "business_meeting", "wealth_advisory"],
			},
		}

	if employees.is_empty():
		var e1 := _make_generated_employee(
			next_id("emp"),
			"EMP_NAME_STARTER_1",
			"emp_teller_f",
			"teller",
			Vector2i(4, 3),
			62, 60, 58, 55, 40, 75, 65,
			20_000
		)
		var e2 := _make_generated_employee(
			next_id("emp"),
			"EMP_NAME_STARTER_2",
			"emp_credit",
			"loan_officer",
			Vector2i(11, 3),
			64, 56, 60, 62, 48, 72, 68,
			25_000
		)
		e1.assigned_station_id = "teller_1"
		e1.traits = ["core:trait.fast_hands"]
		e2.assigned_station_id = "loan_1"
		e2.traits = ["core:trait.risk_expert"]
		if stations.has("teller_1") and stations["teller_1"] is Dictionary:
			(stations["teller_1"] as Dictionary)["assigned_employee_id"] = e1.id
		if stations.has("loan_1") and stations["loan_1"] is Dictionary:
			(stations["loan_1"] as Dictionary)["assigned_employee_id"] = e2.id
		employees[e1.id] = e1
		employees[e2.id] = e2

	if lobby_props.is_empty():
		lobby_props = default_lobby_props()

	if candidates.is_empty():
		var roles: Array[String] = ["teller", "loan_officer", "analyst"]
		var avatars: Array[String] = ["emp_teller_m", "emp_credit", "emp_risk"]
		var starter_traits: Array[String] = [
			"core:trait.sales_prodigy",
			"core:trait.procrastinator",
			"core:trait.vip_whisperer",
		]
		var starter_levels: Array[int] = [1, 2, 3]
		var starter_salaries: Array[int] = [18_000, 29_000, 44_000]
		var crng: RandomNumberGenerator = rng_streams.candidate_rng
		for i in range(3):
			var c := _make_generated_employee(
				next_id("cand"),
				"CAND_NAME_%d" % (i + 1),
				avatars[i % avatars.size()],
				roles[i % roles.size()],
				Vector2i(2, 2),
				crng.randi_range(45, 78),
				crng.randi_range(45, 78),
				crng.randi_range(40, 75),
				crng.randi_range(40, 78),
				crng.randi_range(35, 70),
				crng.randi_range(50, 80),
				crng.randi_range(45, 85),
				starter_salaries[i % starter_salaries.size()]
			)
			c.level = starter_levels[i % starter_levels.size()]
			var c_cap: int = c.get_stat_cap()
			c.professionalism = mini(c.professionalism, c_cap)
			c.efficiency = mini(c.efficiency, c_cap)
			c.sociability = mini(c.sociability, c_cap)
			c.risk_awareness = mini(c.risk_awareness, c_cap)
			c.management = mini(c.management, c_cap)
			c.loyalty = mini(c.loyalty, c_cap)
			c.traits = [starter_traits[i % starter_traits.size()]]
			c.state = Enums.EmployeeState.OFF_DUTY
			candidates.append(c)


static func default_lobby_props() -> Dictionary:
	return {
		"fountain_1": {"prop_id": "fountain_1", "prop_type": "fountain", "grid_pos": Vector2i(9, 7), "solid": true},
		"sofa_1": {"prop_id": "sofa_1", "prop_type": "sofa", "grid_pos": Vector2i(3, 8), "solid": false},
		"sofa_2": {"prop_id": "sofa_2", "prop_type": "sofa", "grid_pos": Vector2i(14, 8), "solid": false},
		"atm_1": {"prop_id": "atm_1", "prop_type": "atm", "grid_pos": Vector2i(1, 5), "solid": false},
		"atm_2": {"prop_id": "atm_2", "prop_type": "atm", "grid_pos": Vector2i(1, 7), "solid": false},
		"plant_1": {"prop_id": "plant_1", "prop_type": "plant", "grid_pos": Vector2i(1, 1), "solid": false},
		"plant_2": {"prop_id": "plant_2", "prop_type": "plant", "grid_pos": Vector2i(16, 1), "solid": false},
		"plant_3": {"prop_id": "plant_3", "prop_type": "plant", "grid_pos": Vector2i(1, 10), "solid": false},
		"plant_4": {"prop_id": "plant_4", "prop_type": "plant", "grid_pos": Vector2i(16, 10), "solid": false},
		"plant_5": {"prop_id": "plant_5", "prop_type": "plant", "grid_pos": Vector2i(10, 4), "solid": false},
		"queue_1": {"prop_id": "queue_1", "prop_type": "queue_post", "grid_pos": Vector2i(4, 6), "solid": false},
		"queue_2": {"prop_id": "queue_2", "prop_type": "queue_post", "grid_pos": Vector2i(6, 6), "solid": false},
		"queue_3": {"prop_id": "queue_3", "prop_type": "queue_post", "grid_pos": Vector2i(8, 6), "solid": false},
		"queue_4": {"prop_id": "queue_4", "prop_type": "queue_post", "grid_pos": Vector2i(11, 6), "solid": false},
	}


static func _make_generated_employee(
	p_id: String,
	p_name_key: String,
	p_avatar: String,
	p_role: String,
	p_pos: Vector2i,
	prof: int,
	eff: int,
	soc: int,
	risk_aw: int,
	mgmt: int,
	loy: int,
	pot: int,
	salary: int
) -> EmployeeInstance:
	var emp := EmployeeInstance.new()
	emp.id = p_id
	emp.name_key = p_name_key
	emp.display_name = p_name_key
	emp.avatar_id = p_avatar
	emp.role_id = p_role
	emp.grid_pos = p_pos
	emp.target_grid_pos = p_pos
	emp.professionalism = prof
	emp.efficiency = eff
	emp.sociability = soc
	emp.risk_awareness = risk_aw
	emp.management = mgmt
	emp.loyalty = loy
	emp.potential = pot
	emp.daily_salary_minor = salary
	emp.state = Enums.EmployeeState.AVAILABLE
	return emp


func to_dict() -> Dictionary:
	var ser_emps: Dictionary = {}
	for eid: Variant in employees.keys():
		var e: Variant = employees[eid]
		if e is EmployeeInstance:
			ser_emps[str(eid)] = (e as EmployeeInstance).to_dict()
		elif e is Object and (e as Object).has_method("to_dict"):
			ser_emps[str(eid)] = (e as Object).call("to_dict")

	var ser_cands: Array[Dictionary] = []
	for c in candidates:
		ser_cands.append(c.to_dict())

	var ser_custs: Dictionary = {}
	for cid: Variant in active_customers.keys():
		var cu: Variant = active_customers[cid]
		if cu is CustomerInstance:
			ser_custs[str(cid)] = (cu as CustomerInstance).to_dict()

	var ser_reqs: Array[Dictionary] = []
	for req in service_requests:
		ser_reqs.append(req.to_dict())

	var ser_loans: Dictionary = {}
	for lid: Variant in loans.keys():
		var ln: Variant = loans[lid]
		if ln is LoanInstance:
			ser_loans[str(lid)] = (ln as LoanInstance).to_dict()

	var ser_depts: Dictionary = {}
	for did: Variant in departments.keys():
		var dv: Variant = departments[did]
		if dv is Object and (dv as Object).has_method("to_dict"):
			ser_depts[str(did)] = (dv as Object).call("to_dict")
		elif dv is Dictionary:
			var dept_copy: Dictionary = (dv as Dictionary).duplicate(true)
			var gp: Variant = dept_copy.get("grid_pos", null)
			if gp is Vector2i:
				var gp_cell: Vector2i = gp as Vector2i
				dept_copy["grid_pos"] = [gp_cell.x, gp_cell.y]
			var rs: Variant = dept_copy.get("room_size", null)
			if rs is Vector2i:
				var rs_cell: Vector2i = rs as Vector2i
				dept_copy["room_size"] = [rs_cell.x, rs_cell.y]
			ser_depts[str(did)] = dept_copy

	var ser_stations: Dictionary = {}
	for sid: Variant in stations.keys():
		var st: Variant = stations[sid]
		if st is Dictionary:
			var std: Dictionary = (st as Dictionary).duplicate(true)
			var gp: Variant = std.get("grid_pos", Vector2i.ZERO)
			if gp is Vector2i:
				var gp2: Vector2i = gp as Vector2i
				std["grid_pos"] = [gp2.x, gp2.y]
			ser_stations[str(sid)] = std

	var pol_copy: Array[String] = []
	for p in adopted_policies:
		pol_copy.append(p)

	var settled_copy: Array[int] = []
	for sd in settled_days:
		settled_copy.append(sd)

	var ser_props: Dictionary = {}
	for pid: Variant in lobby_props.keys():
		var pr: Variant = lobby_props[pid]
		if pr is Dictionary:
			var prd: Dictionary = (pr as Dictionary).duplicate(true)
			var pgp: Variant = prd.get("grid_pos", Vector2i.ZERO)
			if pgp is Vector2i:
				var pgp2: Vector2i = pgp as Vector2i
				prd["grid_pos"] = [pgp2.x, pgp2.y]
			ser_props[str(pid)] = prd

	return {
		"world_seed": str(world_seed),
		"bank_name": bank_name,
		"currency_code": currency_code,
		"current_day": current_day,
		"current_minute_of_day": current_minute_of_day,
		"day_phase": day_phase,
		"speed_multiplier": speed_multiplier,
		"ledger": ledger.to_dict(),
		"rng_streams": rng_streams.to_dict(),
		"employees": ser_emps,
		"candidates": ser_cands,
		"active_customers": ser_custs,
		"service_requests": ser_reqs,
		"loans": ser_loans,
		"pending_loan_approvals": pending_loan_approvals.duplicate(true),
		"pending_resignations": pending_resignations.duplicate(true),
		"departments": ser_depts,
		"adopted_policies": pol_copy,
		"active_events": active_events.duplicate(true),
		"event_history": event_history.duplicate(true),
		"scheduled_events": scheduled_events.duplicate(true),
		"active_event_modifiers": active_event_modifiers.duplicate(true),
		"daily_reports": daily_reports.duplicate(true),
		"settled_days": settled_copy,
		"last_settled_day": last_settled_day,
		"stations": ser_stations,
		"lobby_props": ser_props,
		"reputation": reputation,
		"satisfaction": satisfaction,
		"awareness": awareness,
		"strategy_points": strategy_points,
		"deposit_rate_bps": deposit_rate_bps,
		"loan_base_rate_bps": loan_base_rate_bps,
		"loan_repayment_mode": loan_repayment_mode,
		"mod_dependencies": mod_dependencies.duplicate(true),
		"next_entity_seq": next_entity_seq,
	}


static func _coerce_json_numbers(val: Variant) -> Variant:
	if val is float:
		var f: float = float(val)
		if is_equal_approx(f, float(int(f))):
			return int(f)
		return f
	if val is Dictionary:
		var out_d: Dictionary = {}
		for k: Variant in (val as Dictionary).keys():
			out_d[str(k)] = _coerce_json_numbers((val as Dictionary)[k])
		return out_d
	if val is Array:
		var out_a: Array = []
		for item in (val as Array):
			out_a.append(_coerce_json_numbers(item))
		return out_a
	return val


static func _parse_vec2i(raw: Variant, default_value: Vector2i = Vector2i.ZERO) -> Vector2i:
	if raw is Vector2i:
		return raw as Vector2i
	if raw is Array and (raw as Array).size() >= 2:
		var arr: Array = raw as Array
		return Vector2i(int(arr[0]), int(arr[1]))
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		if not d.has("x") or not d.has("y"):
			return default_value
		return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	return default_value


static func from_dict(data: Dictionary) -> Result:
	if not data.has("ledger") or not (data["ledger"] is Dictionary):
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {"missing": "ledger"})
	if not data.has("rng_streams") or not (data["rng_streams"] is Dictionary):
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {"missing": "rng_streams"})

	var w_seed_raw: Variant = data.get("world_seed", 20261121)
	var w_seed: int = (w_seed_raw as String).to_int() if w_seed_raw is String else int(w_seed_raw)
	var b_name: String = str(data.get("bank_name", "Starway Bank"))
	var state := BankState.new(w_seed, b_name)

	state.currency_code = str(data.get("currency_code", "CNY"))
	state.current_day = maxi(1, int(data.get("current_day", 1)))
	state.current_minute_of_day = maxi(0, int(data.get("current_minute_of_day", BalanceConfig.BUSINESS_OPEN_MINUTE)))
	state.day_phase = clampi(
		int(data.get("day_phase", Enums.DayPhase.PRE_OPEN)),
		Enums.DayPhase.PRE_OPEN,
		Enums.DayPhase.SETTLED
	)
	state.speed_multiplier = clampi(int(data.get("speed_multiplier", 1)), 0, 3)

	var ledger_res: Result = Ledger.from_dict(data["ledger"] as Dictionary)
	if not ledger_res.ok:
		return ledger_res
	state.ledger = ledger_res.data as Ledger

	var rng_res: Result = RngStreams.from_dict(data["rng_streams"] as Dictionary)
	if not rng_res.ok:
		return rng_res
	state.rng_streams = rng_res.data as RngStreams

	var raw_emps: Variant = data.get("employees", {})
	if raw_emps is Dictionary:
		for eid: Variant in (raw_emps as Dictionary).keys():
			var ed: Variant = (raw_emps as Dictionary)[eid]
			if ed is Dictionary:
				var er: Result = EmployeeInstance.from_dict(ed as Dictionary)
				if not er.ok:
					return er
				state.employees[str(eid)] = er.data

	state.candidates = []
	var raw_cands: Variant = data.get("candidates", [])
	if raw_cands is Array:
		for item in (raw_cands as Array):
			if item is Dictionary:
				var cr: Result = EmployeeInstance.from_dict(item as Dictionary)
				if not cr.ok:
					return cr
				state.candidates.append(cr.data as EmployeeInstance)

	var raw_custs: Variant = data.get("active_customers", {})
	if raw_custs is Dictionary:
		for cid: Variant in (raw_custs as Dictionary).keys():
			var cd: Variant = (raw_custs as Dictionary)[cid]
			if cd is Dictionary:
				var cur: Result = CustomerInstance.from_dict(cd as Dictionary)
				if not cur.ok:
					return cur
				state.active_customers[str(cid)] = cur.data

	state.service_requests = []
	var raw_reqs: Variant = data.get("service_requests", [])
	if raw_reqs is Array:
		for item in (raw_reqs as Array):
			if item is Dictionary:
				var rr: Result = ServiceRequest.from_dict(item as Dictionary)
				if not rr.ok:
					return rr
				state.service_requests.append(rr.data as ServiceRequest)

	var raw_loans: Variant = data.get("loans", {})
	if raw_loans is Dictionary:
		for lid: Variant in (raw_loans as Dictionary).keys():
			var ld: Variant = (raw_loans as Dictionary)[lid]
			if ld is Dictionary:
				var lr: Result = LoanInstance.from_dict(ld as Dictionary)
				if not lr.ok:
					return lr
				state.loans[str(lid)] = lr.data

	state.pending_loan_approvals = []
	var raw_apps: Variant = data.get("pending_loan_approvals", [])
	if raw_apps is Array:
		for item in (raw_apps as Array):
			if item is Dictionary:
				state.pending_loan_approvals.append(_coerce_json_numbers(item) as Dictionary)

	var raw_depts: Variant = data.get("departments", {})
	if raw_depts is Dictionary:
		for did: Variant in (raw_depts as Dictionary).keys():
			var dv: Variant = (raw_depts as Dictionary)[did]
			if dv is Dictionary:
				var dd: Dictionary = dv as Dictionary
				var staff_arr: Array[String] = []
				var raw_staff: Variant = dd.get("staff_ids", [])
				if raw_staff is Array:
					for sid in (raw_staff as Array):
						staff_arr.append(str(sid))
				state.departments[str(did)] = {
					"id": str(dd.get("id", str(did))),
					"level": maxi(1, int(dd.get("level", 1))),
					"created_day": maxi(1, int(dd.get("created_day", 1))),
					"daily_cost_minor": maxi(0, int(dd.get("daily_cost_minor", 0))),
					"staff_ids": staff_arr,
					"grid_pos": _parse_vec2i(dd.get("grid_pos", null), Vector2i(-1, -1)),
					"room_size": Vector2i(
						maxi(1, _parse_vec2i(dd.get("room_size", null), Vector2i(1, 1)).x),
						maxi(1, _parse_vec2i(dd.get("room_size", null), Vector2i(1, 1)).y)
					),
				}

	state.adopted_policies = []
	var raw_pols: Variant = data.get("adopted_policies", [])
	if raw_pols is Array:
		for p in (raw_pols as Array):
			state.adopted_policies.append(str(p))

	state.active_events = []
	var raw_ae: Variant = data.get("active_events", [])
	if raw_ae is Array:
		for item in (raw_ae as Array):
			if item is Dictionary:
				state.active_events.append(_coerce_json_numbers(item) as Dictionary)

	state.pending_resignations = []
	var raw_pr: Variant = data.get("pending_resignations", [])
	if raw_pr is Array:
		for item in (raw_pr as Array):
			if item is Dictionary:
				state.pending_resignations.append(_coerce_json_numbers(item) as Dictionary)

	state.event_history = []
	var raw_eh: Variant = data.get("event_history", [])
	if raw_eh is Array:
		for item in (raw_eh as Array):
			if item is Dictionary:
				state.event_history.append(_coerce_json_numbers(item) as Dictionary)

	state.scheduled_events = []
	var raw_se: Variant = data.get("scheduled_events", data.get("queued_chain_events", []))
	if raw_se is Array:
		for item in (raw_se as Array):
			if item is Dictionary:
				state.scheduled_events.append(_coerce_json_numbers(item) as Dictionary)

	state.active_event_modifiers = []
	var raw_aem: Variant = data.get("active_event_modifiers", data.get("active_temporary_modifiers", []))
	if raw_aem is Array:
		for item in (raw_aem as Array):
			if item is Dictionary:
				state.active_event_modifiers.append(_coerce_json_numbers(item) as Dictionary)

	state.daily_reports = []
	var raw_dr: Variant = data.get("daily_reports", [])
	if raw_dr is Array:
		for item in (raw_dr as Array):
			if item is Dictionary:
				var rep_d: Dictionary = _coerce_json_numbers(item) as Dictionary
				if rep_d.has("liquidity_ratio"):
					rep_d["liquidity_ratio"] = float(rep_d["liquidity_ratio"])
				if rep_d.has("npl_ratio"):
					rep_d["npl_ratio"] = float(rep_d["npl_ratio"])
				state.daily_reports.append(rep_d)

	state.settled_days = []
	var raw_sd: Variant = data.get("settled_days", [])
	if raw_sd is Array:
		for sd in (raw_sd as Array):
			state.settled_days.append(int(sd))
	for rep in state.daily_reports:
		var rday: int = int(rep.get("day", 0))
		if rday > 0 and not state.settled_days.has(rday):
			state.settled_days.append(rday)
	state.last_settled_day = maxi(0, int(data.get("last_settled_day", 0)))

	var raw_stations: Variant = data.get("stations", {})
	if raw_stations is Dictionary:
		for sid: Variant in (raw_stations as Dictionary).keys():
			var st: Variant = (raw_stations as Dictionary)[sid]
			if st is Dictionary:
				var std: Dictionary = _coerce_json_numbers(st) as Dictionary
				std["grid_pos"] = _parse_vec2i(std.get("grid_pos", [0, 0]))
				var allowed_srv: Array[String] = []
				var raw_srv: Variant = std.get("allowed_services", [])
				if raw_srv is Array:
					for sv in (raw_srv as Array):
						allowed_srv.append(str(sv))
				std["allowed_services"] = allowed_srv
				state.stations[str(sid)] = std

	var raw_props: Variant = data.get("lobby_props", {})
	if raw_props is Dictionary and not (raw_props as Dictionary).is_empty():
		for pid: Variant in (raw_props as Dictionary).keys():
			var pr: Variant = (raw_props as Dictionary)[pid]
			if pr is Dictionary:
				var prd: Dictionary = _coerce_json_numbers(pr) as Dictionary
				prd["grid_pos"] = _parse_vec2i(prd.get("grid_pos", [0, 0]))
				state.lobby_props[str(pid)] = prd
	else:
		state.lobby_props = default_lobby_props()

	state.reputation = clampi(int(data.get("reputation", BalanceConfig.INITIAL_REPUTATION)), 0, 100)
	state.satisfaction = clampi(int(data.get("satisfaction", BalanceConfig.INITIAL_SATISFACTION)), 0, 100)
	state.awareness = clampi(int(data.get("awareness", BalanceConfig.INITIAL_AWARENESS)), 0, 100)
	state.strategy_points = maxi(0, int(data.get("strategy_points", BalanceConfig.INITIAL_STRATEGY_POINTS)))
	state.deposit_rate_bps = clampi(
		int(data.get("deposit_rate_bps", BalanceConfig.DEFAULT_DEPOSIT_RATE_BPS)),
		BalanceConfig.MIN_DEPOSIT_RATE_BPS,
		BalanceConfig.MAX_DEPOSIT_RATE_BPS
	)
	state.loan_base_rate_bps = clampi(
		int(data.get("loan_base_rate_bps", BalanceConfig.DEFAULT_LOAN_BASE_RATE_BPS)),
		BalanceConfig.MIN_LOAN_RATE_BPS,
		BalanceConfig.MAX_LOAN_RATE_BPS
	)
	state.loan_repayment_mode = str(data.get("loan_repayment_mode", "equal_installment"))

	state.mod_dependencies = []
	var raw_mods: Variant = data.get("mod_dependencies", [])
	if raw_mods is Array:
		for item in (raw_mods as Array):
			if item is Dictionary:
				state.mod_dependencies.append(_coerce_json_numbers(item) as Dictionary)

	state.next_entity_seq = maxi(1, int(data.get("next_entity_seq", 1)))
	return Result.succeed(state)
