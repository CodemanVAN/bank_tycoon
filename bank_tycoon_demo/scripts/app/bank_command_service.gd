class_name BankCommandService
extends RefCounted

## Application command handler and read-query facade between UI/tests and domain services.

var bank_state: BankState = null
var clock: GameClock = null
var event_bus: DomainEventBus = null
var content_defs: Dictionary = {}
var finance_engine: FinanceEngine = null
var dept_service: DepartmentService = null
var policy_service: PolicyService = null
var event_engine: EventEngine = null
var modifier_service: ModifierService = null
var on_state_mutated: Callable = Callable()


func _init(
	p_bank_state: BankState = null,
	p_clock: GameClock = null,
	p_event_bus: DomainEventBus = null,
	p_content_defs: Dictionary = {},
	p_modifier_service: ModifierService = null
) -> void:
	bank_state = p_bank_state
	clock = p_clock
	event_bus = p_event_bus
	content_defs = p_content_defs
	modifier_service = p_modifier_service if p_modifier_service != null else ModifierService.new()
	finance_engine = FinanceEngine.new()
	dept_service = DepartmentService.new()
	policy_service = PolicyService.new()
	event_engine = EventEngine.new()


func _notify_mutated() -> void:
	if on_state_mutated.is_valid():
		on_state_mutated.call()


func open_branch_for_day() -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	bank_state.current_minute_of_day = BalanceConfig.BUSINESS_OPEN_MINUTE
	bank_state.day_phase = Enums.DayPhase.OPEN
	if clock != null:
		clock.reset_accumulator()

	for emp_v: Variant in bank_state.employees.values():
		if emp_v is EmployeeInstance:
			var emp: EmployeeInstance = emp_v as EmployeeInstance
			emp.current_request_id = ""
			if emp.state == Enums.EmployeeState.OFF_DUTY:
				if emp.fatigue >= BalanceConfig.OVERLOAD_FATIGUE_THRESHOLD:
					emp.state = Enums.EmployeeState.OVERLOADED
				else:
					emp.state = Enums.EmployeeState.AVAILABLE

	if not bank_state.scheduled_events.is_empty():
		var has_due: bool = false
		for item in bank_state.scheduled_events:
			if int(item.get("trigger_day", 999999)) <= bank_state.current_day:
				has_due = true
				break
		if has_due:
			var ev_rng: RandomNumberGenerator = bank_state.rng_streams.event_rng if bank_state.rng_streams != null else null
			var ev_res: Result = event_engine.process_scheduled_and_roll_event(bank_state, content_defs, ev_rng, 0)
			if ev_res.ok and ev_res.data is Dictionary and bool((ev_res.data as Dictionary).get("triggered", false)):
				var inst: Dictionary = (ev_res.data as Dictionary).get("instance", {}) as Dictionary
				if event_bus != null:
					event_bus.publish(
						&"EventTriggered",
						{
							"event_instance_id": str(inst.get("instance_id", "")),
							"event_id": str(inst.get("event_id", "")),
						},
						bank_state.current_day,
						bank_state.current_minute_of_day
					)

	if event_bus != null:
		event_bus.publish(
			&"DayStarted",
			{"day": bank_state.current_day},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
		event_bus.publish(
			&"DayPhaseChanged",
			{"phase": bank_state.day_phase, "day": bank_state.current_day},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)

	_notify_mutated()
	return Result.succeed({
		"day": bank_state.current_day,
		"minute": bank_state.current_minute_of_day,
		"phase": bank_state.day_phase,
	})


func advance_to_next_day() -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var settled_day: int = bank_state.current_day
	var report: Dictionary = {}

	if not bank_state.settled_days.has(settled_day):
		var m_rng: RandomNumberGenerator = bank_state.rng_streams.market_rng if bank_state.rng_streams != null else null
		var settle_res: Result = finance_engine.run_daily_settlement(
			bank_state,
			modifier_service,
			m_rng,
			content_defs
		)
		if not settle_res.ok:
			return settle_res
		if settle_res.data is Dictionary:
			report = settle_res.data as Dictionary
		if event_bus != null:
			event_bus.publish(
				&"DailySettlementCompleted",
				{"day": settled_day, "report": report},
				settled_day,
				bank_state.current_minute_of_day
			)
	elif not bank_state.daily_reports.is_empty():
		report = bank_state.daily_reports.back() as Dictionary

	bank_state.current_day += 1
	bank_state.current_minute_of_day = BalanceConfig.BUSINESS_OPEN_MINUTE
	bank_state.day_phase = Enums.DayPhase.PRE_OPEN
	if clock != null:
		clock.reset_accumulator()

	bank_state.active_customers.clear()
	bank_state.service_requests.clear()

	for emp_v: Variant in bank_state.employees.values():
		if emp_v is EmployeeInstance:
			var emp: EmployeeInstance = emp_v as EmployeeInstance
			emp.current_request_id = ""
			if emp.fatigue >= BalanceConfig.OVERLOAD_FATIGUE_THRESHOLD:
				emp.state = Enums.EmployeeState.OVERLOADED
			else:
				emp.state = Enums.EmployeeState.AVAILABLE

	bank_state.strategy_points += 1
	event_engine.expire_event_modifiers(bank_state)

	var ev_rng: RandomNumberGenerator = bank_state.rng_streams.event_rng if bank_state.rng_streams != null else null
	var ev_res: Result = event_engine.process_scheduled_and_roll_event(
		bank_state,
		content_defs,
		ev_rng,
		3500
	)
	if ev_res.ok and ev_res.data is Dictionary and bool((ev_res.data as Dictionary).get("triggered", false)):
		var inst: Dictionary = (ev_res.data as Dictionary).get("instance", {}) as Dictionary
		if event_bus != null:
			event_bus.publish(
				&"EventTriggered",
				{
					"event_instance_id": str(inst.get("instance_id", "")),
					"event_id": str(inst.get("event_id", "")),
				},
				bank_state.current_day,
				bank_state.current_minute_of_day
			)

	if event_bus != null:
		event_bus.publish(
			&"DayPhaseChanged",
			{"phase": bank_state.day_phase, "day": bank_state.current_day},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)

	_notify_mutated()
	return Result.succeed({
		"day": bank_state.current_day,
		"settled_day": settled_day,
		"report": report,
	})


func set_speed(mult: int) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not BalanceConfig.VALID_SPEED_MULTIPLIERS.has(mult):
		return Result.fail(&"INVALID_SPEED", "ERR_INVALID_SPEED", {"speed": mult})
	if clock != null:
		var r: Result = clock.set_speed(mult)
		if not r.ok:
			return r
	bank_state.speed_multiplier = mult
	if event_bus != null:
		event_bus.publish(
			&"SpeedChanged",
			{"speed": mult},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"speed": mult})


func assign_employee_to_station(employee_id: String, station_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.employees.has(employee_id):
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
	if not bank_state.stations.has(station_id):
		return Result.fail(&"STATION_NOT_FOUND", "ERR_STATION_NOT_FOUND", {"station_id": station_id})

	var emp: EmployeeInstance = bank_state.employees[employee_id] as EmployeeInstance
	if emp == null:
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
	if emp.state == Enums.EmployeeState.BREAK:
		return Result.fail(&"ERR_EMPLOYEE_ON_BREAK", "ERR_EMPLOYEE_ON_BREAK", {"employee_id": employee_id})

	# Release active request if employee was mid-service
	if emp.current_request_id != "":
		for req in bank_state.service_requests:
			if req != null and req.request_id == emp.current_request_id and not req.is_terminal():
				req.release_to_queue()
		emp.current_request_id = ""

	# Clear previous station(s) holding this employee_id
	for sid: Variant in bank_state.stations.keys():
		var st_entry: Variant = bank_state.stations[sid]
		if st_entry is Dictionary and str((st_entry as Dictionary).get("assigned_employee_id", "")) == employee_id:
			(st_entry as Dictionary)["assigned_employee_id"] = ""

	# Unbind previous employee on target station if different
	var target_st: Dictionary = bank_state.stations[station_id] as Dictionary
	var prev_emp_id: String = str(target_st.get("assigned_employee_id", ""))
	if prev_emp_id != "" and prev_emp_id != employee_id and bank_state.employees.has(prev_emp_id):
		var prev_emp: EmployeeInstance = bank_state.employees[prev_emp_id] as EmployeeInstance
		if prev_emp != null:
			if prev_emp.current_request_id != "":
				for req in bank_state.service_requests:
					if req != null and req.request_id == prev_emp.current_request_id and not req.is_terminal():
						req.release_to_queue()
				prev_emp.complete_current_task()
			prev_emp.assigned_station_id = ""

	var adapt_days: int = dept_service.get_onboarding_adaptation_days(bank_state)
	var re_res: Result = emp.reassign_station(station_id, "", adapt_days)
	if not re_res.ok:
		return re_res

	var st_pos_v: Variant = target_st.get("grid_pos", emp.grid_pos)
	if st_pos_v is Vector2i:
		emp.target_grid_pos = st_pos_v as Vector2i
		emp.grid_pos = st_pos_v as Vector2i

	target_st["assigned_employee_id"] = employee_id

	if event_bus != null:
		event_bus.publish(
			&"EmployeeAssigned",
			{"employee_id": employee_id, "station_id": station_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({
		"employee_id": employee_id,
		"station_id": station_id,
		"adaptation_days_remaining": emp.adaptation_days_remaining,
	})


func toggle_station_open(station_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.stations.has(station_id):
		return Result.fail(&"STATION_NOT_FOUND", "ERR_STATION_NOT_FOUND", {"station_id": station_id})

	var st: Dictionary = bank_state.stations[station_id] as Dictionary
	var new_open: bool = not bool(st.get("is_open", true))
	st["is_open"] = new_open

	if not new_open:
		for req in bank_state.service_requests:
			if req != null and req.assigned_station_id == station_id and not req.is_terminal():
				var eid: String = req.assigned_employee_id
				req.release_to_queue()
				if eid != "" and bank_state.employees.has(eid):
					var emp: EmployeeInstance = bank_state.employees[eid] as EmployeeInstance
					if emp != null:
						emp.complete_current_task()
				if bank_state.active_customers.has(req.customer_id):
					var cust: CustomerInstance = bank_state.active_customers[req.customer_id] as CustomerInstance
					if cust != null:
						cust.assigned_station_id = ""
						cust.transition_to(Enums.CustomerState.WAITING)

	if event_bus != null:
		event_bus.publish(
			&"StationToggled",
			{"station_id": station_id, "is_open": new_open},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"station_id": station_id, "is_open": new_open})


func set_queue_priority(request_id: String, priority: int) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var target_req: ServiceRequest = null
	for req in bank_state.service_requests:
		if req != null and req.request_id == request_id:
			target_req = req
			break

	if target_req == null:
		return Result.fail(&"REQUEST_NOT_FOUND", "ERR_REQUEST_NOT_FOUND", {"request_id": request_id})

	var res: Result = target_req.set_priority(priority)
	if not res.ok:
		return res

	bank_state.service_requests.sort_custom(ServiceRequest.compare_queue_order)
	_notify_mutated()
	return res


func hire_candidate(candidate_id: String, role_id: String = "") -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var found_idx: int = -1
	var cand: EmployeeInstance = null
	for i in range(bank_state.candidates.size()):
		var c: EmployeeInstance = bank_state.candidates[i]
		if c != null and c.id == candidate_id:
			found_idx = i
			cand = c
			break

	if found_idx < 0 or cand == null:
		return Result.fail(&"CANDIDATE_NOT_FOUND", "ERR_CANDIDATE_NOT_FOUND", {"candidate_id": candidate_id})

	var pay_res: Result = finance_engine.record_operating_cost(
		bank_state,
		BalanceConfig.DEFAULT_RECRUIT_COST_MINOR,
		bank_state.current_day,
		bank_state.current_minute_of_day,
		"hire_" + candidate_id
	)
	if not pay_res.ok:
		return pay_res

	bank_state.candidates.remove_at(found_idx)

	var emp_id: String = cand.id
	if emp_id.is_empty() or bank_state.employees.has(emp_id):
		emp_id = bank_state.next_id("emp")
	cand.id = emp_id
	if role_id != "":
		cand.role_id = role_id
	cand.avatar_id = _avatar_for_role(cand.role_id, cand.avatar_id)
	cand.state = Enums.EmployeeState.AVAILABLE
	cand.fatigue = 0
	cand.current_request_id = ""
	cand.assigned_station_id = ""
	cand.adaptation_days_remaining = dept_service.get_onboarding_adaptation_days(bank_state)

	bank_state.employees[emp_id] = cand
	_spawn_replacement_candidate(1)

	if event_bus != null:
		event_bus.publish(
			&"EmployeeHired",
			{"employee_id": emp_id, "role_id": cand.role_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({
		"employee_id": emp_id,
		"role_id": cand.role_id,
		"adaptation_days_remaining": cand.adaptation_days_remaining,
	})


func fire_employee(employee_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.employees.has(employee_id):
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})

	for sid: Variant in bank_state.stations.keys():
		var st_v: Variant = bank_state.stations[sid]
		if st_v is Dictionary and str((st_v as Dictionary).get("assigned_employee_id", "")) == employee_id:
			(st_v as Dictionary)["assigned_employee_id"] = ""

	for req in bank_state.service_requests:
		if req != null and req.assigned_employee_id == employee_id and not req.is_terminal():
			req.release_to_queue()
			if bank_state.active_customers.has(req.customer_id):
				var cust: CustomerInstance = bank_state.active_customers[req.customer_id] as CustomerInstance
				if cust != null:
					cust.assigned_station_id = ""
					cust.transition_to(Enums.CustomerState.WAITING)

	bank_state.employees.erase(employee_id)

	if event_bus != null:
		event_bus.publish(
			&"EmployeeFired",
			{"employee_id": employee_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"employee_id": employee_id})


func train_employee(employee_id: String) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.employees.has(employee_id):
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})

	var emp: EmployeeInstance = bank_state.employees[employee_id] as EmployeeInstance
	if emp == null:
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
	if emp.state == Enums.EmployeeState.BREAK:
		return Result.fail(&"ERR_EMPLOYEE_ON_BREAK", "ERR_EMPLOYEE_ON_BREAK", {"employee_id": employee_id})

	var pay_res: Result = finance_engine.record_operating_cost(
		bank_state,
		BalanceConfig.DEFAULT_TRAINING_COST_MINOR,
		bank_state.current_day,
		bank_state.current_minute_of_day,
		"train_" + employee_id
	)
	if not pay_res.ok:
		return pay_res

	var hr_lv2: bool = dept_service.is_capability_unlocked(bank_state, "skill_filter_and_training")
	var gain: int = 8 if hr_lv2 else 5
	emp.professionalism = clampi(emp.professionalism + gain, 0, 100)
	emp.efficiency = clampi(emp.efficiency + gain, 0, 100)
	emp.risk_awareness = clampi(emp.risk_awareness + maxi(2, gain / 2), 0, 100)
	emp.training_count += 1

	if event_bus != null:
		event_bus.publish(
			&"EmployeeTrained",
			{"employee_id": employee_id, "training_count": emp.training_count},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({
		"employee_id": employee_id,
		"professionalism": emp.professionalism,
		"efficiency": emp.efficiency,
		"training_count": emp.training_count,
	})


func rest_employee(employee_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.employees.has(employee_id):
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})

	var emp: EmployeeInstance = bank_state.employees[employee_id] as EmployeeInstance
	if emp == null:
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})

	for req in bank_state.service_requests:
		if req != null and req.assigned_employee_id == employee_id and not req.is_terminal():
			req.release_to_queue()
			if bank_state.active_customers.has(req.customer_id):
				var cust: CustomerInstance = bank_state.active_customers[req.customer_id] as CustomerInstance
				if cust != null:
					cust.assigned_station_id = ""
					cust.transition_to(Enums.CustomerState.WAITING)

	for sid: Variant in bank_state.stations.keys():
		var st_v: Variant = bank_state.stations[sid]
		if st_v is Dictionary and str((st_v as Dictionary).get("assigned_employee_id", "")) == employee_id:
			(st_v as Dictionary)["assigned_employee_id"] = ""

	emp.current_request_id = ""
	emp.assigned_station_id = ""
	emp.state = Enums.EmployeeState.BREAK
	emp.target_grid_pos = Vector2i(2, 9)

	if event_bus != null:
		event_bus.publish(
			&"EmployeeRested",
			{"employee_id": employee_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"employee_id": employee_id, "state": emp.state})


func create_department(dept_id: String) -> Result:
	var res: Result = dept_service.create_department(bank_state, dept_id, content_defs, finance_engine)
	if not res.ok:
		return res

	if dept_id == "core:department.hr":
		_spawn_replacement_candidate(2)
	elif dept_id == "core:department.credit":
		if bank_state.stations.has("loan_1") and bank_state.stations["loan_1"] is Dictionary:
			(bank_state.stations["loan_1"] as Dictionary)["is_open"] = true

	if event_bus != null:
		event_bus.publish(
			&"DepartmentCreated",
			{"department_id": dept_id, "level": 1},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return res


func upgrade_department(dept_id: String) -> Result:
	var res: Result = dept_service.upgrade_department(bank_state, dept_id, content_defs, finance_engine)
	if not res.ok:
		return res

	var new_lvl: int = dept_service.get_department_level(bank_state, dept_id)
	if event_bus != null:
		event_bus.publish(
			&"DepartmentUpgraded",
			{"department_id": dept_id, "level": new_lvl},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return res


func adopt_policy(policy_id: String) -> Result:
	var res: Result = policy_service.adopt_policy(bank_state, policy_id, content_defs)
	if not res.ok:
		return res

	if event_bus != null:
		event_bus.publish(
			&"PolicyAdopted",
			{"policy_id": policy_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return res


func approve_loan(approval_id: String) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var found_idx: int = -1
	var app_entry: Dictionary = {}
	for i in range(bank_state.pending_loan_approvals.size()):
		var item: Dictionary = bank_state.pending_loan_approvals[i]
		var aid: String = str(item.get("approval_id", item.get("id", "")))
		if aid == approval_id:
			found_idx = i
			app_entry = item
			break

	if found_idx < 0:
		return Result.fail(&"APPROVAL_NOT_FOUND", "ERR_APPROVAL_NOT_FOUND", {"approval_id": approval_id})

	var cust_id: String = str(app_entry.get("customer_id", "cust_loan"))
	var principal: int = maxi(1, int(app_entry.get("principal_minor", 100_000)))
	var rate_bps: int = maxi(0, int(app_entry.get("annual_rate_bps", bank_state.loan_base_rate_bps)))
	var term_days: int = maxi(1, int(app_entry.get("term_days", 30)))

	var disb_res: Result = finance_engine.disburse_loan(
		bank_state,
		cust_id,
		principal,
		rate_bps,
		term_days,
		approval_id
	)
	if not disb_res.ok:
		return disb_res

	bank_state.pending_loan_approvals.remove_at(found_idx)

	var loan_obj: LoanInstance = disb_res.data as LoanInstance if disb_res.data is LoanInstance else null
	var loan_id: String = ""
	if loan_obj != null:
		loan_obj.credit_score = int(app_entry.get("credit_score", 70))
		loan_obj.risk_grade = Enums.string_to_risk_grade(str(app_entry.get("risk_grade", "B")))
		loan_obj.collateral_value = int(app_entry.get("collateral_value", 0))
		loan_id = loan_obj.loan_id

	if event_bus != null:
		event_bus.publish(
			&"LoanApproved",
			{"approval_id": approval_id, "loan_id": loan_id, "principal_minor": principal},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({
		"approval_id": approval_id,
		"loan_id": loan_id,
		"principal_minor": principal,
	})


func reject_loan(approval_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var found_idx: int = -1
	for i in range(bank_state.pending_loan_approvals.size()):
		var item: Dictionary = bank_state.pending_loan_approvals[i]
		var aid: String = str(item.get("approval_id", item.get("id", "")))
		if aid == approval_id:
			found_idx = i
			break

	if found_idx < 0:
		return Result.fail(&"APPROVAL_NOT_FOUND", "ERR_APPROVAL_NOT_FOUND", {"approval_id": approval_id})

	bank_state.pending_loan_approvals.remove_at(found_idx)

	if event_bus != null:
		event_bus.publish(
			&"LoanRejected",
			{"approval_id": approval_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"approval_id": approval_id})


func resolve_event_option(event_instance_id: String, option_id: String) -> Result:
	var res: Result = event_engine.resolve_event_option(
		bank_state,
		event_instance_id,
		option_id,
		content_defs,
		finance_engine
	)
	if not res.ok:
		return res

	if event_bus != null:
		event_bus.publish(
			&"EventResolved",
			{"event_instance_id": event_instance_id, "option_id": option_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return res


func set_interest_rates(deposit_bps: int, loan_bps: int) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if deposit_bps < BalanceConfig.MIN_DEPOSIT_RATE_BPS or deposit_bps > BalanceConfig.MAX_DEPOSIT_RATE_BPS:
		return Result.fail(
			&"INVALID_DEPOSIT_RATE",
			"ERR_INVALID_DEPOSIT_RATE",
			{
				"deposit_rate_bps": deposit_bps,
				"min": BalanceConfig.MIN_DEPOSIT_RATE_BPS,
				"max": BalanceConfig.MAX_DEPOSIT_RATE_BPS,
			}
		)
	if loan_bps < BalanceConfig.MIN_LOAN_RATE_BPS or loan_bps > BalanceConfig.MAX_LOAN_RATE_BPS:
		return Result.fail(
			&"INVALID_LOAN_RATE",
			"ERR_INVALID_LOAN_RATE",
			{
				"loan_base_rate_bps": loan_bps,
				"min": BalanceConfig.MIN_LOAN_RATE_BPS,
				"max": BalanceConfig.MAX_LOAN_RATE_BPS,
			}
		)

	bank_state.deposit_rate_bps = deposit_bps
	bank_state.loan_base_rate_bps = loan_bps

	if event_bus != null:
		event_bus.publish(
			&"RatesChanged",
			{"deposit_bps": deposit_bps, "loan_bps": loan_bps},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({
		"deposit_rate_bps": deposit_bps,
		"loan_base_rate_bps": loan_bps,
	})


# ---------------------------------------------------------------------------
# Read helpers for UI disabled-reason inspection
# ---------------------------------------------------------------------------

func can_create_department(dept_id: String) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not ContentId.is_valid(dept_id):
		return Result.fail(&"INVALID_CONTENT_ID", "ERR_INVALID_CONTENT_ID", {"id": dept_id})
	var dept_def: Dictionary = DepartmentService._find_dept_def(dept_id, content_defs)
	if dept_def.is_empty():
		return Result.fail(&"DEPT_NOT_FOUND", "ERR_DEPT_NOT_FOUND", {"department_id": dept_id})
	if bank_state.departments.has(dept_id):
		return Result.fail(&"DEPT_ALREADY_EXISTS", "ERR_DEPT_ALREADY_EXISTS", {"department_id": dept_id})
	if not dept_service._check_unlock_conditions(dept_def.get("unlock_conditions", []), bank_state):
		return Result.fail(&"DEPT_LOCKED", "ERR_DEPT_LOCKED", {"department_id": dept_id})
	var cost: int = maxi(0, int(dept_def.get("initial_cost_minor", 0)))
	var cash: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash < cost:
		return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": cost, "available": cash})
	return Result.succeed({"department_id": dept_id, "cost_minor": cost})


func can_upgrade_department(dept_id: String) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	var dept_def: Dictionary = DepartmentService._find_dept_def(dept_id, content_defs)
	if dept_def.is_empty():
		return Result.fail(&"DEPT_NOT_FOUND", "ERR_DEPT_NOT_FOUND", {"department_id": dept_id})
	if not bank_state.departments.has(dept_id):
		return Result.fail(&"DEPT_NOT_CREATED", "ERR_DEPT_NOT_CREATED", {"department_id": dept_id})
	var cur_lvl: int = dept_service.get_department_level(bank_state, dept_id)
	var max_lvl: int = maxi(1, int(dept_def.get("max_level", 3)))
	if cur_lvl >= max_lvl:
		return Result.fail(&"DEPT_MAX_LEVEL", "ERR_DEPT_MAX_LEVEL", {"department_id": dept_id, "level": cur_lvl})
	var cost: int = get_department_upgrade_cost(dept_id)
	var cash: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash < cost:
		return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": cost, "available": cash})
	return Result.succeed({"department_id": dept_id, "next_level": cur_lvl + 1, "cost_minor": cost})


func get_department_upgrade_cost(dept_id: String) -> int:
	if bank_state == null:
		return 0
	var dept_def: Dictionary = DepartmentService._find_dept_def(dept_id, content_defs)
	if dept_def.is_empty():
		return 0
	var cur_lvl: int = dept_service.get_department_level(bank_state, dept_id)
	var init_cost: int = maxi(0, int(dept_def.get("initial_cost_minor", 0)))
	return BalanceConfig.calc_department_upgrade_cost(init_cost, maxi(1, cur_lvl))


func can_adopt_policy(policy_id: String) -> Result:
	return policy_service.can_adopt_policy(bank_state, policy_id, content_defs)


static func _avatar_for_role(role_id: String, fallback: String) -> String:
	match role_id:
		"teller":
			return fallback if (fallback == "emp_teller_f" or fallback == "emp_teller_m") else "emp_teller_m"
		"loan_officer":
			return "emp_credit"
		"analyst":
			return "emp_risk"
		"manager":
			return "emp_ops"
		_:
			return fallback if fallback != "" else "emp_teller_m"


func _spawn_replacement_candidate(count: int) -> void:
	if bank_state == null or bank_state.rng_streams == null:
		return
	var crng: RandomNumberGenerator = bank_state.rng_streams.candidate_rng
	if crng == null:
		return
	var roles: Array[String] = ["teller", "loan_officer", "analyst", "manager"]
	var avatars: Array[String] = ["emp_teller_f", "emp_credit", "emp_risk", "emp_ops"]
	for _i in range(maxi(0, count)):
		var cid: String = bank_state.next_id("cand")
		var r_idx: int = crng.randi_range(0, roles.size() - 1)
		var name_idx: int = (bank_state.next_entity_seq % 3) + 1
		var cand := EmployeeInstance.new()
		cand.id = cid
		cand.name_key = "CAND_NAME_%d" % name_idx
		cand.display_name = cand.name_key
		cand.role_id = roles[r_idx]
		cand.avatar_id = avatars[r_idx]
		cand.grid_pos = Vector2i(2, 2)
		cand.target_grid_pos = Vector2i(2, 2)
		cand.professionalism = crng.randi_range(48, 82)
		cand.efficiency = crng.randi_range(48, 82)
		cand.sociability = crng.randi_range(45, 78)
		cand.risk_awareness = crng.randi_range(45, 80)
		cand.management = crng.randi_range(40, 75)
		cand.loyalty = crng.randi_range(55, 85)
		cand.potential = crng.randi_range(50, 88)
		cand.daily_salary_minor = 18_000 + r_idx * 3_000
		cand.state = Enums.EmployeeState.OFF_DUTY
		bank_state.candidates.append(cand)
