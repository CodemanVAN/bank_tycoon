extends Node

## UI-side fallback SimulationHost used ONLY when res://scripts/app/simulation_host.gd
## is not yet present during parallel build. Replaced automatically by GameRoot._enter_tree()
## when res://scripts/app/simulation_host.gd exists.

signal snapshot_changed()

class FallbackEventBus extends RefCounted:
	signal event_published(event_type: StringName, payload: Dictionary)
	var recent_log: Array[Dictionary] = []

	func publish(event_type: StringName, payload: Dictionary = {}) -> void:
		var entry: Dictionary = {
			"type": String(event_type),
			"day": int(payload.get("day", 1)),
			"minute": int(payload.get("minute", 540)),
			"key": str(payload.get("key", String(event_type))),
			"params": payload.duplicate(true),
		}
		recent_log.append(entry)
		while recent_log.size() > 50:
			recent_log.pop_front()
		event_published.emit(event_type, payload)


class FallbackCommandService extends RefCounted:
	var host: Node = null
	var finance_engine := FinanceEngine.new()
	var dept_service := DepartmentService.new()
	var policy_service := PolicyService.new()
	var event_engine := EventEngine.new()

	func _init(p_host: Node) -> void:
		host = p_host

	func _bs() -> BankState:
		return host.get("bank_state") as BankState

	func _defs() -> Dictionary:
		return host.get("content_defs") as Dictionary

	func _emit(ev_type: StringName, payload: Dictionary = {}) -> void:
		var eb: Variant = host.get("event_bus")
		if eb != null and eb.has_method("publish"):
			eb.call("publish", ev_type, payload)
		if host.has_signal("snapshot_changed"):
			host.emit_signal("snapshot_changed")

	func open_branch_for_day() -> Result:
		var bs: BankState = _bs()
		if bs == null:
			return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
		bs.day_phase = Enums.DayPhase.OPEN
		bs.current_minute_of_day = BalanceConfig.BUSINESS_OPEN_MINUTE
		for eid: Variant in bs.employees.keys():
			var emp: EmployeeInstance = bs.employees[eid] as EmployeeInstance
			if emp != null and emp.state == Enums.EmployeeState.OFF_DUTY:
				emp.state = Enums.EmployeeState.AVAILABLE
		_emit(&"day_phase_changed", {"phase": bs.day_phase, "day": bs.current_day})
		return Result.succeed({"day": bs.current_day, "phase": bs.day_phase})

	func advance_to_next_day() -> Result:
		var bs: BankState = _bs()
		if bs == null:
			return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
		if not bs.settled_days.has(bs.current_day):
			var mod_svc := ModifierService.new()
			var mrng: RandomNumberGenerator = bs.rng_streams.market_rng if bs.rng_streams != null else null
			var sres: Result = finance_engine.run_daily_settlement(bs, mod_svc, mrng, _defs())
			if not sres.ok:
				return sres
			_emit(&"daily_settlement_completed", {"day": bs.current_day, "report": sres.data})
		bs.current_day += 1
		bs.current_minute_of_day = BalanceConfig.BUSINESS_OPEN_MINUTE
		bs.day_phase = Enums.DayPhase.PRE_OPEN
		bs.strategy_points += 1
		_emit(&"day_started", {"day": bs.current_day})
		return Result.succeed({"day": bs.current_day, "phase": bs.day_phase})

	func set_speed(new_speed: int) -> Result:
		var bs: BankState = _bs()
		if bs == null:
			return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
		if not BalanceConfig.VALID_SPEED_MULTIPLIERS.has(new_speed):
			return Result.fail(&"INVALID_SPEED", "ERR_INVALID_SPEED", {"speed": new_speed})
		bs.speed_multiplier = new_speed
		_emit(&"speed_changed", {"speed": new_speed})
		return Result.succeed({"speed": new_speed})

	func toggle_station_open(station_id: String, force_state: Variant = null) -> Result:
		var bs: BankState = _bs()
		if bs == null or not bs.stations.has(station_id):
			return Result.fail(&"STATION_NOT_FOUND", "ERR_STATION_NOT_FOUND", {"station_id": station_id})
		var st: Dictionary = bs.stations[station_id] as Dictionary
		var next_open: bool = not bool(st.get("is_open", true))
		if force_state is bool:
			next_open = bool(force_state)
		st["is_open"] = next_open
		bs.stations[station_id] = st
		_emit(&"station_toggled", {"station_id": station_id, "is_open": next_open})
		return Result.succeed({"station_id": station_id, "is_open": next_open})

	func assign_employee_to_station(employee_id: String, station_id: String) -> Result:
		var bs: BankState = _bs()
		if bs == null or not bs.employees.has(employee_id):
			return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
		if station_id != "" and not bs.stations.has(station_id):
			return Result.fail(&"STATION_NOT_FOUND", "ERR_STATION_NOT_FOUND", {"station_id": station_id})
		var emp: EmployeeInstance = bs.employees[employee_id] as EmployeeInstance
		var res: Result = emp.reassign_station(station_id)
		if not res.ok:
			return res
		for sid: Variant in bs.stations.keys():
			var st: Dictionary = bs.stations[sid] as Dictionary
			if str(st.get("assigned_employee_id", "")) == employee_id:
				st["assigned_employee_id"] = ""
		if station_id != "":
			var target_st: Dictionary = bs.stations[station_id] as Dictionary
			var prev_emp_id: String = str(target_st.get("assigned_employee_id", ""))
			if prev_emp_id != "" and prev_emp_id != employee_id and bs.employees.has(prev_emp_id):
				(bs.employees[prev_emp_id] as EmployeeInstance).assigned_station_id = ""
			target_st["assigned_employee_id"] = employee_id
		_emit(&"employee_assigned", {"employee_id": employee_id, "station_id": station_id})
		return Result.succeed({"employee_id": employee_id, "station_id": station_id})

	func set_queue_priority(request_id: String, priority: int) -> Result:
		var bs: BankState = _bs()
		if bs == null:
			return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
		for req in bs.service_requests:
			if req.request_id == request_id:
				var r: Result = req.set_priority(priority)
				if r.ok:
					_emit(&"queue_priority_changed", {"request_id": request_id, "priority": priority})
				return r
		return Result.fail(&"REQUEST_NOT_FOUND", "ERR_REQUEST_NOT_FOUND", {"request_id": request_id})

	func hire_candidate(candidate_id: String, role_id: String = "") -> Result:
		var bs: BankState = _bs()
		if bs == null:
			return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
		var idx: int = -1
		for i in range(bs.candidates.size()):
			if bs.candidates[i].id == candidate_id:
				idx = i
				break
		if idx < 0:
			return Result.fail(&"CANDIDATE_NOT_FOUND", "ERR_CANDIDATE_NOT_FOUND", {"candidate_id": candidate_id})
		var cost: int = BalanceConfig.DEFAULT_RECRUIT_COST_MINOR
		if bs.ledger.get_balance(&"cash_reserves") < cost:
			return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": cost})
		var pay_res: Result = finance_engine.record_operating_cost(bs, cost, bs.current_day, bs.current_minute_of_day, "hire_" + candidate_id)
		if not pay_res.ok:
			return pay_res
		var cand: EmployeeInstance = bs.candidates[idx]
		bs.candidates.remove_at(idx)
		if role_id != "":
			cand.role_id = role_id
		cand.state = Enums.EmployeeState.AVAILABLE
		cand.adaptation_days_remaining = dept_service.get_onboarding_adaptation_days(bs)
		bs.employees[cand.id] = cand
		_emit(&"employee_hired", {"employee_id": cand.id})
		return Result.succeed(cand)

	func fire_employee(employee_id: String) -> Result:
		var bs: BankState = _bs()
		if bs == null or not bs.employees.has(employee_id):
			return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
		if bs.employees.size() <= 1:
			return Result.fail(&"CANNOT_FIRE_LAST_EMPLOYEE", "ERR_CANNOT_FIRE_LAST_EMPLOYEE", {})
		for sid: Variant in bs.stations.keys():
			var st: Dictionary = bs.stations[sid] as Dictionary
			if str(st.get("assigned_employee_id", "")) == employee_id:
				st["assigned_employee_id"] = ""
		bs.employees.erase(employee_id)
		_emit(&"employee_fired", {"employee_id": employee_id})
		return Result.succeed({"employee_id": employee_id})

	func train_employee(employee_id: String) -> Result:
		var bs: BankState = _bs()
		if bs == null or not bs.employees.has(employee_id):
			return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
		var cost: int = BalanceConfig.DEFAULT_TRAINING_COST_MINOR
		if bs.ledger.get_balance(&"cash_reserves") < cost:
			return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": cost})
		var pay_res: Result = finance_engine.record_operating_cost(bs, cost, bs.current_day, bs.current_minute_of_day, "train_" + employee_id)
		if not pay_res.ok:
			return pay_res
		var emp: EmployeeInstance = bs.employees[employee_id] as EmployeeInstance
		emp.professionalism = mini(100, emp.professionalism + 5)
		emp.efficiency = mini(100, emp.efficiency + 5)
		emp.training_count += 1
		_emit(&"employee_trained", {"employee_id": employee_id})
		return Result.succeed(emp)

	func rest_employee(employee_id: String) -> Result:
		var bs: BankState = _bs()
		if bs == null or not bs.employees.has(employee_id):
			return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
		var emp: EmployeeInstance = bs.employees[employee_id] as EmployeeInstance
		emp.current_request_id = ""
		emp.state = Enums.EmployeeState.BREAK
		emp.recover_fatigue(20)
		_emit(&"employee_rested", {"employee_id": employee_id})
		return Result.succeed(emp)

	func create_department(department_id: String) -> Result:
		var res: Result = dept_service.create_department(_bs(), department_id, _defs(), finance_engine)
		if res.ok:
			_emit(&"department_created", {"department_id": department_id})
		return res

	func upgrade_department(department_id: String) -> Result:
		var res: Result = dept_service.upgrade_department(_bs(), department_id, _defs(), finance_engine)
		if res.ok:
			var lvl: int = dept_service.get_department_level(_bs(), department_id)
			_emit(&"department_upgraded", {"department_id": department_id, "level": lvl})
		return res

	func adopt_policy(policy_id: String) -> Result:
		var res: Result = policy_service.adopt_policy(_bs(), policy_id, _defs())
		if res.ok:
			_emit(&"policy_adopted", {"policy_id": policy_id})
		return res

	func approve_loan(approval_id: String) -> Result:
		var bs: BankState = _bs()
		if bs == null:
			return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
		for i in range(bs.pending_loan_approvals.size()):
			var app: Dictionary = bs.pending_loan_approvals[i]
			var aid: String = str(app.get("approval_id", app.get("id", "")))
			if aid == approval_id:
				var cust_id: String = str(app.get("customer_id", "cust_loan"))
				var principal: int = int(app.get("principal_minor", 500_000))
				var rate_bps: int = int(app.get("annual_rate_bps", bs.loan_base_rate_bps))
				var term: int = int(app.get("term_days", 30))
				var dres: Result = finance_engine.disburse_loan(bs, cust_id, principal, rate_bps, term, aid)
				if not dres.ok:
					return dres
				bs.pending_loan_approvals.remove_at(i)
				var ln: LoanInstance = dres.data as LoanInstance
				_emit(&"loan_approved", {"approval_id": approval_id, "loan_id": ln.loan_id if ln != null else ""})
				return dres
		return Result.fail(&"LOAN_APPROVAL_NOT_FOUND", "ERR_LOAN_APPROVAL_NOT_FOUND", {"approval_id": approval_id})

	func reject_loan(approval_id: String) -> Result:
		var bs: BankState = _bs()
		if bs == null:
			return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
		for i in range(bs.pending_loan_approvals.size()):
			var app: Dictionary = bs.pending_loan_approvals[i]
			var aid: String = str(app.get("approval_id", app.get("id", "")))
			if aid == approval_id:
				bs.pending_loan_approvals.remove_at(i)
				_emit(&"loan_rejected", {"approval_id": approval_id})
				return Result.succeed({"approval_id": approval_id})
		return Result.fail(&"LOAN_APPROVAL_NOT_FOUND", "ERR_LOAN_APPROVAL_NOT_FOUND", {"approval_id": approval_id})

	func resolve_event_option(event_instance_id: String, option_id: String) -> Result:
		var res: Result = event_engine.resolve_event_option(_bs(), event_instance_id, option_id, _defs(), finance_engine)
		if res.ok:
			_emit(&"event_resolved", {"event_instance_id": event_instance_id, "option_id": option_id})
		return res

	func set_interest_rates(deposit_rate_bps: int, loan_base_rate_bps: int) -> Result:
		var bs: BankState = _bs()
		if bs == null:
			return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
		if deposit_rate_bps < BalanceConfig.MIN_DEPOSIT_RATE_BPS or deposit_rate_bps > BalanceConfig.MAX_DEPOSIT_RATE_BPS:
			return Result.fail(&"INVALID_DEPOSIT_RATE", "ERR_INVALID_DEPOSIT_RATE", {"rate": deposit_rate_bps})
		if loan_base_rate_bps < BalanceConfig.MIN_LOAN_RATE_BPS or loan_base_rate_bps > BalanceConfig.MAX_LOAN_RATE_BPS:
			return Result.fail(&"INVALID_LOAN_RATE", "ERR_INVALID_LOAN_RATE", {"rate": loan_base_rate_bps})
		bs.deposit_rate_bps = deposit_rate_bps
		bs.loan_base_rate_bps = loan_base_rate_bps
		_emit(&"rates_changed", {"deposit_bps": deposit_rate_bps, "loan_bps": loan_base_rate_bps})
		return Result.succeed({"deposit_rate_bps": deposit_rate_bps, "loan_base_rate_bps": loan_base_rate_bps})

	func can_create_department(dept_id: String) -> Result:
		var bs: BankState = _bs()
		if bs == null:
			return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
		if bs.departments.has(dept_id):
			return Result.fail(&"DEPT_ALREADY_EXISTS", "ERR_DEPT_ALREADY_EXISTS", {})
		var defs: Dictionary = _defs()
		var ddef: Dictionary = DepartmentService._find_dept_def(dept_id, defs)
		if ddef.is_empty():
			return Result.fail(&"DEPT_NOT_FOUND", "ERR_DEPT_NOT_FOUND", {})
		var cost: int = int(ddef.get("initial_cost_minor", 0))
		if bs.ledger.get_balance(&"cash_reserves") < cost:
			return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": cost})
		return Result.succeed({"cost_minor": cost})

	func can_upgrade_department(dept_id: String) -> Result:
		var bs: BankState = _bs()
		if bs == null or not bs.departments.has(dept_id):
			return Result.fail(&"DEPT_NOT_CREATED", "ERR_DEPT_NOT_CREATED", {})
		var ddef: Dictionary = DepartmentService._find_dept_def(dept_id, _defs())
		var cur_lvl: int = dept_service.get_department_level(bs, dept_id)
		var max_lvl: int = int(ddef.get("max_level", 3))
		if cur_lvl >= max_lvl:
			return Result.fail(&"DEPT_MAX_LEVEL", "ERR_DEPT_MAX_LEVEL", {})
		var cost: int = BalanceConfig.calc_department_upgrade_cost(int(ddef.get("initial_cost_minor", 0)), cur_lvl)
		if bs.ledger.get_balance(&"cash_reserves") < cost:
			return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": cost})
		return Result.succeed({"cost_minor": cost})

	func can_adopt_policy(policy_id: String) -> Result:
		return policy_service.can_adopt_policy(_bs(), policy_id, _defs())


var bank_state: BankState = null
var command_service: FallbackCommandService = null
var event_bus: FallbackEventBus = null
var content_defs: Dictionary = {}
var modifiers: ModifierService = null
var _accum_sec: float = 0.0


func _init() -> void:
	event_bus = FallbackEventBus.new()
	command_service = FallbackCommandService.new(self)
	modifiers = ModifierService.new()


func bind_session(p_state: Variant, p_defs: Dictionary = {}) -> void:
	if p_state is BankState:
		bank_state = p_state as BankState
	else:
		bank_state = BankState.create_starter_branch("Starway Bank", 20261121)
	content_defs = p_defs if not p_defs.is_empty() else UiI18n.get_fallback_content_defs()
	snapshot_changed.emit()


func step_simulation(delta: float) -> int:
	if bank_state == null or bank_state.day_phase != Enums.DayPhase.OPEN or bank_state.speed_multiplier <= 0:
		return 0
	var min_dur: float = 0.25
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var sess: Node = tree.root.get_node_or_null("GameSession")
		if sess != null and sess.get("minute_duration_sec") != null:
			min_dur = maxf(0.01, float(sess.get("minute_duration_sec")))
	_accum_sec += delta * float(bank_state.speed_multiplier)
	var ticks: int = 0
	while _accum_sec >= min_dur and ticks < BalanceConfig.MAX_TICKS_PER_FRAME:
		_accum_sec -= min_dur
		ticks += 1
		bank_state.current_minute_of_day += 1
		if bank_state.current_minute_of_day >= BalanceConfig.BUSINESS_CLOSE_MINUTE:
			var fe := FinanceEngine.new()
			var mrng: RandomNumberGenerator = bank_state.rng_streams.market_rng if bank_state.rng_streams != null else null
			var sres: Result = fe.run_daily_settlement(bank_state, modifiers, mrng, content_defs)
			if sres.ok:
				event_bus.publish(&"daily_settlement_completed", {"day": bank_state.current_day, "report": sres.data})
			break
	if ticks > 0:
		snapshot_changed.emit()
	return ticks


func get_snapshot() -> Dictionary:
	if bank_state == null:
		return {}
	var cash: int = bank_state.ledger.get_balance(&"cash_reserves") if bank_state.ledger != null else 0
	var deposits: int = bank_state.ledger.get_balance(&"customer_deposits") if bank_state.ledger != null else 0
	var loans: int = bank_state.ledger.get_balance(&"loan_principal_outstanding") if bank_state.ledger != null else 0
	var eq_cap: int = bank_state.ledger.get_balance(&"equity_capital") if bank_state.ledger != null else 0
	var ret_earn: int = bank_state.ledger.get_balance(&"retained_earnings") if bank_state.ledger != null else 0
	var fee_inc: int = bank_state.ledger.get_balance(&"fee_income") if bank_state.ledger != null else 0
	var loan_int: int = bank_state.ledger.get_balance(&"loan_interest_income") if bank_state.ledger != null else 0
	var opex: int = bank_state.ledger.get_balance(&"operating_expense") if bank_state.ledger != null else 0
	var dep_int: int = bank_state.ledger.get_balance(&"deposit_interest_expense") if bank_state.ledger != null else 0
	var cred_loss: int = bank_state.ledger.get_balance(&"credit_loss_expense") if bank_state.ledger != null else 0
	var ev_exp: int = bank_state.ledger.get_balance(&"event_expense") if bank_state.ledger != null else 0
	var est_net: int = (fee_inc + loan_int) - (opex + dep_int + cred_loss + ev_exp)

	var liq_bps: int = 990_000
	var liq_status: int = Enums.LiquidityStatus.SAFE
	if deposits > 0:
		var base_wd: int = maxi(
			BalanceConfig.MIN_NEAR_TERM_WITHDRAWAL_FLOOR_MINOR,
			FinanceEngine.round_div(deposits * BalanceConfig.NEAR_TERM_WITHDRAWAL_RATIO_BPS, BalanceConfig.BPS_DENOMINATOR)
		)
		liq_bps = FinanceEngine.round_div(cash * BalanceConfig.BPS_DENOMINATOR, maxi(1, base_wd))
		if liq_bps >= BalanceConfig.LIQUIDITY_SAFE_BPS:
			liq_status = Enums.LiquidityStatus.SAFE
		elif liq_bps >= BalanceConfig.LIQUIDITY_CAUTION_BPS:
			liq_status = Enums.LiquidityStatus.CAUTION
		else:
			liq_status = Enums.LiquidityStatus.DANGER

	var npl_bal: int = 0
	for l: Variant in bank_state.loans.values():
		if l is LoanInstance and (l as LoanInstance).is_npl():
			npl_bal += (l as LoanInstance).principal_outstanding
	var npl_bps: int = FinanceEngine.round_div(npl_bal * BalanceConfig.BPS_DENOMINATOR, loans) if loans > 0 else 0

	return {
		"day": bank_state.current_day,
		"minute": bank_state.current_minute_of_day,
		"phase": bank_state.day_phase,
		"speed": bank_state.speed_multiplier,
		"cash_minor": cash,
		"deposits_minor": deposits,
		"loans_minor": loans,
		"equity_minor": eq_cap + ret_earn,
		"today_profit_minor": est_net,
		"satisfaction": bank_state.satisfaction,
		"reputation": bank_state.reputation,
		"strategy_points": bank_state.strategy_points,
		"employee_count": bank_state.employees.size(),
		"queue_length": bank_state.service_requests.size(),
		"waiting_customers": bank_state.active_customers.size(),
		"pending_approvals": bank_state.pending_loan_approvals.size(),
		"active_events": bank_state.active_events.size(),
		"liquidity_ratio_bps": liq_bps,
		"liquidity_status": liq_status,
		"npl_ratio_bps": npl_bps,
		"deposit_rate_bps": bank_state.deposit_rate_bps,
		"loan_base_rate_bps": bank_state.loan_base_rate_bps,
	}
