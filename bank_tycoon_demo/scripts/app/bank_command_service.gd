class_name BankCommandService
extends RefCounted

## Application command handler and read-query facade between UI/tests and domain services.

const ContentStudioStoreScript := preload("res://scripts/infrastructure/content_studio_store.gd")

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


func advance_to_next_month() -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var cal: Dictionary = FormatService.day_to_calendar(bank_state.current_day)
	var days_left: int = maxi(1, int(cal.get("days_remaining_in_month", 30)))
	var month_num: int = int(cal.get("month", 1))
	var year_num: int = int(cal.get("year", 2026))

	var agg: Dictionary = {
		"day": bank_state.current_day,
		"is_monthly": true,
		"year": year_num,
		"month": month_num,
		"days_advanced": days_left,
		"loan_interest_income": 0,
		"deposit_interest_expense": 0,
		"fee_income": 0,
		"staff_cost": 0,
		"facility_cost": 0,
		"department_cost": 0,
		"credit_loss_expense": 0,
		"event_expense": 0,
		"net_profit": 0,
		"driver_keys": [],
	}

	var m_rng: RandomNumberGenerator = bank_state.rng_streams.market_rng if bank_state.rng_streams != null else null
	var last_rep: Dictionary = {}
	for _step in range(days_left):
		var cur_d: int = bank_state.current_day
		var day_rep: Dictionary = {}
		if not bank_state.settled_days.has(cur_d):
			var sr: Result = finance_engine.run_daily_settlement(bank_state, modifier_service, m_rng, content_defs)
			if not sr.ok:
				return sr
			if sr.data is Dictionary:
				day_rep = sr.data as Dictionary
		elif not bank_state.daily_reports.is_empty():
			day_rep = bank_state.daily_reports.back() as Dictionary

		if not day_rep.is_empty():
			last_rep = day_rep
			for k_sum: String in [
				"loan_interest_income", "deposit_interest_expense", "fee_income",
				"staff_cost", "facility_cost", "department_cost", "credit_loss_expense",
				"event_expense", "net_profit",
			]:
				agg[k_sum] = int(agg[k_sum]) + int(day_rep.get(k_sum, 0))

		bank_state.current_day += 1
		bank_state.strategy_points += 1
		event_engine.expire_event_modifiers(bank_state)

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
			emp.state = Enums.EmployeeState.OVERLOADED if emp.fatigue >= BalanceConfig.OVERLOAD_FATIGUE_THRESHOLD else Enums.EmployeeState.AVAILABLE

	if not last_rep.is_empty():
		for k_end: String in [
			"cash_reserves", "loan_principal_outstanding", "customer_deposits",
			"equity_capital", "retained_earnings", "liquidity_ratio", "liquidity_status",
			"npl_ratio", "warning_level", "reputation", "satisfaction", "awareness", "driver_keys",
		]:
			if last_rep.has(k_end):
				agg[k_end] = last_rep[k_end]
		agg["day"] = int(last_rep.get("day", bank_state.current_day - 1))

	var ev_rng: RandomNumberGenerator = bank_state.rng_streams.event_rng if bank_state.rng_streams != null else null
	var ev_res: Result = event_engine.process_scheduled_and_roll_event(bank_state, content_defs, ev_rng, 4500)
	if ev_res.ok and ev_res.data is Dictionary and bool((ev_res.data as Dictionary).get("triggered", false)):
		var inst: Dictionary = (ev_res.data as Dictionary).get("instance", {}) as Dictionary
		if event_bus != null:
			event_bus.publish(&"EventTriggered", {
				"event_instance_id": str(inst.get("instance_id", "")),
				"event_id": str(inst.get("event_id", "")),
			}, bank_state.current_day, bank_state.current_minute_of_day)

	if event_bus != null:
		event_bus.publish(&"DailySettlementCompleted", {"day": int(agg["day"]), "report": agg}, bank_state.current_day, bank_state.current_minute_of_day)
		event_bus.publish(&"DayPhaseChanged", {"phase": bank_state.day_phase, "day": bank_state.current_day}, bank_state.current_day, bank_state.current_minute_of_day)

	_notify_mutated()
	return Result.succeed({
		"day": bank_state.current_day,
		"days_advanced": days_left,
		"report": agg,
	})


func set_loan_repayment_mode(mode: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not ["equal_installment", "interest_first", "principal_first"].has(mode):
		return Result.fail(&"INVALID_REPAYMENT_MODE", "ERR_INVALID_REPAYMENT_MODE", {"mode": mode})
	if mode != "equal_installment" and not bank_state.adopted_policies.has("core:policy.flexible_repayment"):
		return Result.fail(&"REPAYMENT_POLICY_REQUIRED", "ERR_REPAYMENT_POLICY_REQUIRED", {})
	bank_state.loan_repayment_mode = mode
	if event_bus != null:
		event_bus.publish(&"LoanRepaymentModeChanged", {"mode": mode}, bank_state.current_day, bank_state.current_minute_of_day)
	_notify_mutated()
	return Result.succeed({"mode": mode})


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

	_remove_employee_from_all_departments(employee_id)
	emp.department_id = ""
	if emp.role_id == "lobby_manager":
		emp.role_id = "loan_officer" if station_id.begins_with("loan") else "teller"

	var st_pos_v: Variant = target_st.get("grid_pos", emp.grid_pos)
	if st_pos_v is Vector2i:
		var behind_pos: Vector2i = (st_pos_v as Vector2i) + Vector2i(0, -1)
		emp.target_grid_pos = behind_pos
		emp.grid_pos = behind_pos

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


func assign_employee_to_department(employee_id: String, dept_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.employees.has(employee_id):
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
	if not bank_state.departments.has(dept_id):
		return Result.fail(&"DEPT_NOT_CREATED", "ERR_DEPT_NOT_CREATED", {"department_id": dept_id})

	var emp: EmployeeInstance = bank_state.employees[employee_id] as EmployeeInstance
	if emp == null:
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
	if emp.state == Enums.EmployeeState.BREAK:
		return Result.fail(&"ERR_EMPLOYEE_ON_BREAK", "ERR_EMPLOYEE_ON_BREAK", {"employee_id": employee_id})

	# Release active station request & unbind any station
	if emp.current_request_id != "":
		for req in bank_state.service_requests:
			if req != null and req.request_id == emp.current_request_id and not req.is_terminal():
				req.release_to_queue()
		emp.complete_current_task()
	for sid: Variant in bank_state.stations.keys():
		var st_entry: Variant = bank_state.stations[sid]
		if st_entry is Dictionary and str((st_entry as Dictionary).get("assigned_employee_id", "")) == employee_id:
			(st_entry as Dictionary)["assigned_employee_id"] = ""
	emp.assigned_station_id = ""

	_remove_employee_from_all_departments(employee_id)
	emp.department_id = dept_id
	var dept_entry: Variant = bank_state.departments[dept_id]
	if dept_entry is Object:
		var s_arr: Array = (dept_entry as Object).get("staff_ids") as Array
		if not s_arr.has(employee_id):
			s_arr.append(employee_id)
	elif dept_entry is Dictionary:
		var sd: Dictionary = dept_entry as Dictionary
		var s_arr2: Array = sd.get("staff_ids", []) as Array
		if not s_arr2.has(employee_id):
			s_arr2.append(employee_id)
		sd["staff_ids"] = s_arr2

	var room_rect: Rect2i = DepartmentService.get_department_room_rect(bank_state, dept_id)
	if room_rect.size.x > 0:
		var desk_cell := Vector2i(room_rect.position.x + room_rect.size.x / 2, room_rect.position.y + room_rect.size.y / 2)
		emp.grid_pos = desk_cell
		emp.target_grid_pos = desk_cell

	if event_bus != null:
		event_bus.publish(
			&"EmployeeAssigned",
			{"employee_id": employee_id, "department_id": dept_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"employee_id": employee_id, "department_id": dept_id})


func assign_employee_as_lobby_manager(employee_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.employees.has(employee_id):
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
	var emp: EmployeeInstance = bank_state.employees[employee_id] as EmployeeInstance
	if emp == null:
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
	if emp.state == Enums.EmployeeState.BREAK:
		return Result.fail(&"ERR_EMPLOYEE_ON_BREAK", "ERR_EMPLOYEE_ON_BREAK", {"employee_id": employee_id})

	if emp.current_request_id != "":
		for req in bank_state.service_requests:
			if req != null and req.request_id == emp.current_request_id and not req.is_terminal():
				req.release_to_queue()
		emp.complete_current_task()
	for sid: Variant in bank_state.stations.keys():
		var st_entry: Variant = bank_state.stations[sid]
		if st_entry is Dictionary and str((st_entry as Dictionary).get("assigned_employee_id", "")) == employee_id:
			(st_entry as Dictionary)["assigned_employee_id"] = ""
	emp.assigned_station_id = ""
	_remove_employee_from_all_departments(employee_id)
	emp.department_id = ""
	emp.role_id = "lobby_manager"
	emp.grid_pos = Vector2i(8, 8)
	emp.target_grid_pos = Vector2i(8, 8)

	if event_bus != null:
		event_bus.publish(
			&"EmployeeAssigned",
			{"employee_id": employee_id, "role_id": "lobby_manager"},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"employee_id": employee_id, "role_id": "lobby_manager"})


func _remove_employee_from_all_departments(employee_id: String) -> void:
	if bank_state == null:
		return
	for did: Variant in bank_state.departments.keys():
		var entry: Variant = bank_state.departments[did]
		if entry is Object:
			var s_arr: Variant = (entry as Object).get("staff_ids")
			if s_arr is Array:
				(s_arr as Array).erase(employee_id)
		elif entry is Dictionary:
			var s_arr2: Variant = (entry as Dictionary).get("staff_ids", [])
			if s_arr2 is Array:
				(s_arr2 as Array).erase(employee_id)


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
	if priority > Enums.QueuePriority.NORMAL:
		target_req.payload["atm_mode"] = ""
		target_req.payload["atm_walk_minutes"] = 0
		if bank_state.active_customers.has(target_req.customer_id):
			var pcust: CustomerInstance = bank_state.active_customers[target_req.customer_id] as CustomerInstance
			if pcust != null and pcust.state == Enums.CustomerState.FINDING_SERVICE:
				pcust.approach_minutes_remaining = 0
				pcust.transition_to(Enums.CustomerState.WAITING)

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

	_remove_employee_from_all_departments(employee_id)
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
	var sub_gain: int = maxi(2, gain / 2)
	var cap: int = emp.get_stat_cap()
	emp.professionalism = clampi(emp.professionalism + gain, 0, cap)
	emp.efficiency = clampi(emp.efficiency + gain, 0, cap)
	emp.risk_awareness = clampi(emp.risk_awareness + sub_gain, 0, cap)
	emp.sociability = clampi(emp.sociability + sub_gain, 0, cap)
	emp.management = clampi(emp.management + sub_gain, 0, cap)
	emp.loyalty = clampi(emp.loyalty + 2, 0, cap)
	emp.add_experience(BalanceConfig.EMPLOYEE_XP_PER_TRAINING)
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
		"risk_awareness": emp.risk_awareness,
		"sociability": emp.sociability,
		"management": emp.management,
		"training_count": emp.training_count,
	})


func refresh_employee_trait(employee_id: String) -> Result:
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
		BalanceConfig.DEFAULT_TRAIT_REFRESH_COST_MINOR,
		bank_state.current_day,
		bank_state.current_minute_of_day,
		"trait_" + employee_id
	)
	if not pay_res.ok:
		return pay_res

	var pool: Array[Dictionary] = []
	var neg_ids: Dictionary = {}
	var raw_traits: Variant = content_defs.get("traits", [])
	if raw_traits is Array:
		for raw_t: Variant in (raw_traits as Array):
			if raw_t is Dictionary:
				var td: Dictionary = raw_t as Dictionary
				var tid: String = str(td.get("id", ""))
				var pol: String = str(td.get("polarity", "positive"))
				if pol == "negative":
					neg_ids[tid] = true
					continue
				if not tid.is_empty() and not emp.traits.has(tid):
					pool.append(td)
	if pool.is_empty():
		var fallback_ids: Array[String] = [
			"core:trait.sales_prodigy", "core:trait.risk_expert", "core:trait.workaholic",
			"core:trait.detail_oriented", "core:trait.bank_veteran", "core:trait.team_leader",
			"core:trait.vip_whisperer", "core:trait.fast_hands", "core:trait.compliance_shield",
			"core:trait.rising_star",
		]
		for fid: String in fallback_ids:
			if not emp.traits.has(fid):
				pool.append({"id": fid, "name_key": fid})
	if pool.is_empty():
		return Result.fail(&"NO_TRAITS_AVAILABLE", "ERR_NO_TRAITS_AVAILABLE", {})

	var rng: RandomNumberGenerator = bank_state.rng_streams.candidate_rng if bank_state.rng_streams != null else null
	var pick_idx: int = rng.randi_range(0, pool.size() - 1) if rng != null else (emp.training_count % pool.size())
	var chosen: Dictionary = pool[pick_idx]
	var chosen_id: String = str(chosen.get("id", ""))
	var chosen_name_key: String = str(chosen.get("name_key", chosen_id))

	# Replace a negative trait first if present; otherwise cap at 2 traits
	var replaced_neg: bool = false
	for ti: int in range(emp.traits.size()):
		if neg_ids.has(emp.traits[ti]):
			emp.traits.remove_at(ti)
			replaced_neg = true
			break
	if not replaced_neg and emp.traits.size() >= 2:
		emp.traits.remove_at(0)
	emp.traits.append(chosen_id)
	emp.training_count += 1

	if event_bus != null:
		event_bus.publish(
			&"EmployeeTraitRefreshed",
			{
				"employee_id": employee_id,
				"trait_id": chosen_id,
				"trait_name_key": chosen_name_key,
			},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({
		"employee_id": employee_id,
		"trait_id": chosen_id,
		"trait_name_key": chosen_name_key,
		"traits": emp.traits.duplicate(),
	})


func promote_employee(employee_id: String) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.employees.has(employee_id):
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})

	var emp: EmployeeInstance = bank_state.employees[employee_id] as EmployeeInstance
	if emp == null:
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})
	if emp.level >= BalanceConfig.EMPLOYEE_MAX_LEVEL:
		return Result.fail(&"EMPLOYEE_MAX_LEVEL", "ERR_EMPLOYEE_MAX_LEVEL", {"employee_id": employee_id})
	if not emp.can_promote():
		return Result.fail(
			&"EMPLOYEE_XP_NOT_FULL",
			"ERR_EMPLOYEE_XP_NOT_FULL",
			{"xp": emp.work_xp, "required": emp.get_xp_required()}
		)

	var cost: int = int(BalanceConfig.EMPLOYEE_PROMOTE_COSTS_MINOR.get(emp.level, 80_000))
	var pay_res: Result = finance_engine.record_operating_cost(
		bank_state,
		cost,
		bank_state.current_day,
		bank_state.current_minute_of_day,
		"promote_" + employee_id
	)
	if not pay_res.ok:
		return pay_res

	var salary_inc: int = int(BalanceConfig.EMPLOYEE_PROMOTE_SALARY_INCREASE_MINOR.get(emp.level, 8_000))
	emp.level = mini(BalanceConfig.EMPLOYEE_MAX_LEVEL, emp.level + 1)
	emp.work_xp = 0
	emp.daily_salary_minor += salary_inc
	emp.loyalty = clampi(emp.loyalty + 6, 0, emp.get_stat_cap())

	if event_bus != null:
		event_bus.publish(
			&"EmployeePromoted",
			{
				"employee_id": employee_id,
				"level": emp.level,
				"stat_cap": emp.get_stat_cap(),
				"daily_salary_minor": emp.daily_salary_minor,
			},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({
		"employee_id": employee_id,
		"level": emp.level,
		"stat_cap": emp.get_stat_cap(),
		"daily_salary_minor": emp.daily_salary_minor,
	})


func resolve_employee_resignation(employee_id: String, action: String) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var found_idx: int = -1
	for i in range(bank_state.pending_resignations.size()):
		if str(bank_state.pending_resignations[i].get("employee_id", "")) == employee_id:
			found_idx = i
			break

	if not bank_state.employees.has(employee_id):
		if found_idx >= 0:
			bank_state.pending_resignations.remove_at(found_idx)
		return Result.fail(&"EMPLOYEE_NOT_FOUND", "ERR_EMPLOYEE_NOT_FOUND", {"employee_id": employee_id})

	var emp: EmployeeInstance = bank_state.employees[employee_id] as EmployeeInstance
	if action == "retain":
		var pay_res: Result = finance_engine.record_operating_cost(
			bank_state,
			BalanceConfig.EMPLOYEE_RETAIN_BONUS_MINOR,
			bank_state.current_day,
			bank_state.current_minute_of_day,
			"retain_" + employee_id
		)
		if not pay_res.ok:
			return pay_res
		if found_idx >= 0:
			bank_state.pending_resignations.remove_at(found_idx)
		emp.daily_salary_minor += BalanceConfig.EMPLOYEE_RETAIN_SALARY_RAISE_MINOR
		emp.recover_fatigue(25)
		emp.loyalty = clampi(emp.loyalty + 15, 0, emp.get_stat_cap())
		if event_bus != null:
			event_bus.publish(
				&"EmployeeRetained",
				{"employee_id": employee_id},
				bank_state.current_day,
				bank_state.current_minute_of_day
			)
		_notify_mutated()
		return Result.succeed({"employee_id": employee_id, "action": "retain"})

	# Accept dissatisfaction resignation -> employee leaves & hurts bank awareness, satisfaction, reputation
	if found_idx >= 0:
		bank_state.pending_resignations.remove_at(found_idx)
	var fire_r: Result = fire_employee(employee_id)
	if not fire_r.ok:
		return fire_r
	bank_state.awareness = clampi(bank_state.awareness - 3, 0, 100)
	bank_state.satisfaction = clampi(bank_state.satisfaction - 5, 0, 100)
	bank_state.reputation = clampi(bank_state.reputation - 4, 0, 100)
	if event_bus != null:
		event_bus.publish(
			&"EmployeeResigned",
			{"employee_id": employee_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"employee_id": employee_id, "action": "accept"})


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


func create_department(
	dept_id: String,
	grid_pos: Vector2i = Vector2i(-1, -1),
	room_size: Vector2i = Vector2i(1, 1)
) -> Result:
	var res: Result = dept_service.create_department(
		bank_state, dept_id, content_defs, finance_engine, grid_pos, room_size
	)
	if not res.ok:
		return res

	# Every newly created department comes with 1 dedicated specialist whose daily salary
	# equals the department's base maintenance cost; firing them leaves the department inactive.
	_attach_initial_department_specialist(dept_id)

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


func _attach_initial_department_specialist(dept_id: String) -> void:
	if bank_state == null or not bank_state.departments.has(dept_id):
		return
	var ddef: Dictionary = DepartmentService._find_dept_def(dept_id, content_defs)
	var salary_minor: int = maxi(10_000, int(ddef.get("daily_cost_minor", 15_000)))
	var role_id: String = "manager"
	var avatar_id: String = "emp_ops"
	var name_key: String = "EMP_DEPT_OPS_LEAD"
	match dept_id:
		"core:department.hr":
			role_id = "manager"
			avatar_id = "emp_hr"
			name_key = "EMP_DEPT_HR_LEAD"
		"core:department.credit":
			role_id = "loan_officer"
			avatar_id = "emp_credit"
			name_key = "EMP_DEPT_CREDIT_LEAD"
		"core:department.risk":
			role_id = "analyst"
			avatar_id = "emp_risk"
			name_key = "EMP_DEPT_RISK_LEAD"

	var spec := EmployeeInstance.new()
	spec.id = bank_state.next_id("emp")
	spec.name_key = name_key
	spec.display_name = name_key
	spec.avatar_id = avatar_id
	spec.role_id = role_id
	spec.department_id = dept_id
	spec.daily_salary_minor = salary_minor
	spec.professionalism = 68
	spec.efficiency = 66
	spec.sociability = 64
	spec.risk_awareness = 70
	spec.management = 68
	spec.loyalty = 75
	spec.potential = 72
	spec.state = Enums.EmployeeState.AVAILABLE if (
		bank_state.day_phase == Enums.DayPhase.OPEN or bank_state.day_phase == Enums.DayPhase.CLOSING
	) else Enums.EmployeeState.OFF_DUTY

	var room_rect: Rect2i = DepartmentService.get_department_room_rect(bank_state, dept_id)
	if room_rect.size.x > 0:
		var desk_cell := Vector2i(room_rect.position.x + room_rect.size.x / 2, room_rect.position.y + room_rect.size.y / 2)
		spec.grid_pos = desk_cell
		spec.target_grid_pos = desk_cell
	else:
		spec.grid_pos = Vector2i(2, 2)
		spec.target_grid_pos = Vector2i(2, 2)

	bank_state.employees[spec.id] = spec
	var entry: Variant = bank_state.departments[dept_id]
	if entry is Object:
		(entry as Object).set("requires_staff", true)
		var arr: Array = (entry as Object).get("staff_ids") as Array
		if not arr.has(spec.id):
			arr.append(spec.id)
	elif entry is Dictionary:
		var ed: Dictionary = entry as Dictionary
		ed["requires_staff"] = true
		var arr2: Array = ed.get("staff_ids", []) as Array
		if not arr2.has(spec.id):
			arr2.append(spec.id)
		ed["staff_ids"] = arr2


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


func demolish_department(dept_id: String) -> Result:
	var res: Result = dept_service.demolish_department(bank_state, dept_id)
	if not res.ok:
		return res

	if event_bus != null:
		var dismissed: Array = (res.data as Dictionary).get("dismissed_employee_ids", []) as Array if res.data is Dictionary else []
		for eid_v in dismissed:
			event_bus.publish(
				&"EmployeeFired",
				{"employee_id": str(eid_v), "reason": "department_demolished"},
				bank_state.current_day,
				bank_state.current_minute_of_day
			)
		event_bus.publish(
			&"DepartmentDemolished",
			{"department_id": dept_id, "dismissed_count": dismissed.size()},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return res


func move_department(dept_id: String, new_grid_pos: Vector2i) -> Result:
	var res: Result = dept_service.move_department(bank_state, dept_id, new_grid_pos)
	if not res.ok:
		return res
	if event_bus != null:
		event_bus.publish(
			&"DepartmentMoved",
			{"department_id": dept_id, "grid_pos": [new_grid_pos.x, new_grid_pos.y]},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return res


func move_station(station_id: String, new_cell: Vector2i) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.stations.has(station_id):
		return Result.fail(&"STATION_NOT_FOUND", "ERR_STATION_NOT_FOUND", {"station_id": station_id})
	if new_cell.x < 1 or new_cell.x > 16 or new_cell.y < 2 or new_cell.y > 10:
		return Result.fail(&"LAYOUT_CELL_INVALID", "ERR_DEPT_PLOT_INVALID", {"x": new_cell.x, "y": new_cell.y})
	for sid_v: Variant in bank_state.stations.keys():
		var sid: String = str(sid_v)
		if sid == station_id:
			continue
		var st_other: Variant = bank_state.stations[sid]
		if st_other is Dictionary and (st_other as Dictionary).get("grid_pos") == new_cell:
			return Result.fail(&"LAYOUT_CELL_OCCUPIED", "ERR_DEPT_PLOT_OCCUPIED", {"x": new_cell.x, "y": new_cell.y})
	for pid_v: Variant in bank_state.lobby_props.keys():
		var pr: Variant = bank_state.lobby_props[pid_v]
		if pr is Dictionary and bool((pr as Dictionary).get("solid", false)) and (pr as Dictionary).get("grid_pos") == new_cell:
			return Result.fail(&"LAYOUT_CELL_OCCUPIED", "ERR_DEPT_PLOT_OCCUPIED", {"x": new_cell.x, "y": new_cell.y})

	var target_st: Dictionary = bank_state.stations[station_id] as Dictionary
	target_st["grid_pos"] = new_cell
	var assigned_eid: String = str(target_st.get("assigned_employee_id", ""))
	if not assigned_eid.is_empty() and bank_state.employees.has(assigned_eid):
		var emp: EmployeeInstance = bank_state.employees[assigned_eid] as EmployeeInstance
		if emp != null:
			emp.grid_pos = new_cell + Vector2i(0, -1)
			emp.target_grid_pos = new_cell + Vector2i(0, -1)

	if event_bus != null:
		event_bus.publish(
			&"LayoutChanged",
			{"kind": "station", "id": station_id, "grid_pos": [new_cell.x, new_cell.y]},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"station_id": station_id, "grid_pos": [new_cell.x, new_cell.y]})


func move_lobby_prop(prop_id: String, new_cell: Vector2i) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.lobby_props.has(prop_id):
		return Result.fail(&"PROP_NOT_FOUND", "ERR_DEPT_PLOT_INVALID", {"prop_id": prop_id})
	if new_cell.x < 1 or new_cell.x > 16 or new_cell.y < 1 or new_cell.y > 10:
		return Result.fail(&"LAYOUT_CELL_INVALID", "ERR_DEPT_PLOT_INVALID", {"x": new_cell.x, "y": new_cell.y})
	for sid_v: Variant in bank_state.stations.keys():
		var st_other: Variant = bank_state.stations[sid_v]
		if st_other is Dictionary and (st_other as Dictionary).get("grid_pos") == new_cell:
			return Result.fail(&"LAYOUT_CELL_OCCUPIED", "ERR_DEPT_PLOT_OCCUPIED", {"x": new_cell.x, "y": new_cell.y})
	for pid_v: Variant in bank_state.lobby_props.keys():
		var pid: String = str(pid_v)
		if pid == prop_id:
			continue
		var pr_other: Variant = bank_state.lobby_props[pid]
		if pr_other is Dictionary and (pr_other as Dictionary).get("grid_pos") == new_cell:
			return Result.fail(&"LAYOUT_CELL_OCCUPIED", "ERR_DEPT_PLOT_OCCUPIED", {"x": new_cell.x, "y": new_cell.y})

	var prop_d: Dictionary = bank_state.lobby_props[prop_id] as Dictionary
	prop_d["grid_pos"] = new_cell
	if event_bus != null:
		event_bus.publish(
			&"LayoutChanged",
			{"kind": "prop", "id": prop_id, "grid_pos": [new_cell.x, new_cell.y]},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"prop_id": prop_id, "grid_pos": [new_cell.x, new_cell.y]})


func build_station(station_type: String, cell: Vector2i) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	var catalog: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
	if not catalog.has(station_type):
		return Result.fail(&"INVALID_BUILD_ITEM", "ERR_DEPT_PLOT_INVALID", {"type": station_type})
	var spec: Dictionary = catalog[station_type] as Dictionary
	if str(spec.get("kind", "")) != "station":
		return Result.fail(&"INVALID_BUILD_ITEM", "ERR_DEPT_PLOT_INVALID", {"type": station_type})
	if cell.x < 1 or cell.x > 16 or cell.y < 2 or cell.y > 10:
		return Result.fail(&"LAYOUT_CELL_INVALID", "ERR_DEPT_PLOT_INVALID", {"x": cell.x, "y": cell.y})
	for sid_v: Variant in bank_state.stations.keys():
		var st_other: Variant = bank_state.stations[sid_v]
		if st_other is Dictionary and (st_other as Dictionary).get("grid_pos") == cell:
			return Result.fail(&"LAYOUT_CELL_OCCUPIED", "ERR_DEPT_PLOT_OCCUPIED", {"x": cell.x, "y": cell.y})
	for pid_v: Variant in bank_state.lobby_props.keys():
		var pr_other: Variant = bank_state.lobby_props[pid_v]
		if pr_other is Dictionary and (pr_other as Dictionary).get("grid_pos") == cell:
			return Result.fail(&"LAYOUT_CELL_OCCUPIED", "ERR_DEPT_PLOT_OCCUPIED", {"x": cell.x, "y": cell.y})

	var cost: int = int(spec.get("cost_minor", 800_000))
	var cash_now: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash_now < cost:
		return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": cost, "available": cash_now})

	var pay_res: Result = finance_engine.record_operating_cost(
		bank_state, cost, bank_state.current_day, bank_state.current_minute_of_day, "build_st_" + station_type
	)
	if not pay_res.ok:
		return pay_res

	var prefix: String = "loan" if station_type == "loan_desk" else "teller"
	var idx: int = 1
	while bank_state.stations.has("%s_%d" % [prefix, idx]):
		idx += 1
	var new_sid: String = "%s_%d" % [prefix, idx]
	var allowed: Array[String] = []
	if station_type == "loan_desk":
		allowed = ["personal_loan_application", "business_meeting", "wealth_advisory"]
	else:
		allowed = ["cash_deposit", "cash_withdrawal", "transfer", "account_opening", "complaint"]
	bank_state.stations[new_sid] = {
		"station_id": new_sid,
		"station_type": station_type,
		"is_open": true,
		"assigned_employee_id": "",
		"grid_pos": cell,
		"allowed_services": allowed,
	}
	bank_state.reputation = clampi(bank_state.reputation + int(spec.get("rep_bonus", 0)), 0, 100)

	if event_bus != null:
		event_bus.publish(
			&"LayoutChanged",
			{"kind": "station_built", "id": new_sid, "grid_pos": [cell.x, cell.y], "cost_minor": cost},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"station_id": new_sid, "cost_minor": cost, "grid_pos": [cell.x, cell.y]})


func build_lobby_prop(prop_type: String, cell: Vector2i) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	var catalog: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
	if not catalog.has(prop_type):
		return Result.fail(&"INVALID_BUILD_ITEM", "ERR_DEPT_PLOT_INVALID", {"type": prop_type})
	var spec: Dictionary = catalog[prop_type] as Dictionary
	if str(spec.get("kind", "")) != "prop":
		return Result.fail(&"INVALID_BUILD_ITEM", "ERR_DEPT_PLOT_INVALID", {"type": prop_type})
	if cell.x < 1 or cell.x > 16 or cell.y < 1 or cell.y > 10:
		return Result.fail(&"LAYOUT_CELL_INVALID", "ERR_DEPT_PLOT_INVALID", {"x": cell.x, "y": cell.y})
	for sid_v: Variant in bank_state.stations.keys():
		var st_other: Variant = bank_state.stations[sid_v]
		if st_other is Dictionary and (st_other as Dictionary).get("grid_pos") == cell:
			return Result.fail(&"LAYOUT_CELL_OCCUPIED", "ERR_DEPT_PLOT_OCCUPIED", {"x": cell.x, "y": cell.y})
	for pid_v: Variant in bank_state.lobby_props.keys():
		var pr_other: Variant = bank_state.lobby_props[pid_v]
		if pr_other is Dictionary and (pr_other as Dictionary).get("grid_pos") == cell:
			return Result.fail(&"LAYOUT_CELL_OCCUPIED", "ERR_DEPT_PLOT_OCCUPIED", {"x": cell.x, "y": cell.y})

	var cost: int = int(spec.get("cost_minor", 100_000))
	var cash_now: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash_now < cost:
		return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": cost, "available": cash_now})

	var pay_res: Result = finance_engine.record_operating_cost(
		bank_state, cost, bank_state.current_day, bank_state.current_minute_of_day, "build_prop_" + prop_type
	)
	if not pay_res.ok:
		return pay_res

	var new_pid: String = bank_state.next_id(prop_type)
	bank_state.lobby_props[new_pid] = {
		"prop_id": new_pid,
		"prop_type": prop_type,
		"grid_pos": cell,
		"solid": bool(spec.get("solid", false)),
	}
	bank_state.satisfaction = clampi(bank_state.satisfaction + int(spec.get("sat_bonus", 0)), 0, 100)
	bank_state.reputation = clampi(bank_state.reputation + int(spec.get("rep_bonus", 0)), 0, 100)

	if event_bus != null:
		event_bus.publish(
			&"LayoutChanged",
			{"kind": "prop_built", "id": new_pid, "prop_type": prop_type, "grid_pos": [cell.x, cell.y], "cost_minor": cost},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"prop_id": new_pid, "prop_type": prop_type, "cost_minor": cost, "grid_pos": [cell.x, cell.y]})


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
		loan_obj.customer_type = str(app_entry.get("customer_type", "borrower"))
		loan_obj.borrower_name = str(app_entry.get("borrower_name", ""))
		if loan_obj.borrower_name.is_empty():
			loan_obj.borrower_name = LoanInstance.generate_borrower_name(cust_id, loan_obj.customer_type)
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


func write_off_bad_loan(loan_id: String) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.loans.has(loan_id):
		return Result.fail(&"LOAN_NOT_FOUND", "ERR_LOAN_NOT_FOUND", {"loan_id": loan_id})

	var loan: LoanInstance = bank_state.loans[loan_id] as LoanInstance
	if loan == null or loan.principal_outstanding <= 0 or loan.status == Enums.LoanStatus.WRITTEN_OFF or loan.status == Enums.LoanStatus.REPAID:
		return Result.fail(&"ERR_LOAN_ALREADY_CLOSED", "ERR_LOAN_ALREADY_CLOSED", {"loan_id": loan_id})
	if not loan.is_npl() and loan.days_past_due <= 0:
		return Result.fail(&"ERR_LOAN_NOT_OVERDUE", "ERR_LOAN_NOT_OVERDUE", {"loan_id": loan_id})

	# Step 1: Liquidate collateral salvage (60% recovery up to remaining principal) if pledged
	var salvage: int = 0
	if loan.collateral_value > 0:
		var raw_salvage: int = FinanceEngine.round_div(loan.collateral_value * 60, 100)
		var max_ledger_prin: int = bank_state.ledger.get_balance(&"loan_principal_outstanding")
		salvage = mini(mini(raw_salvage, loan.principal_outstanding), max_ledger_prin)
		if salvage > 0:
			finance_engine.record_loan_repayment(
				bank_state,
				loan_id,
				salvage,
				bank_state.current_day,
				bank_state.current_minute_of_day
			)

	# Step 2: Book remaining unrecoverable principal as Credit Loss and write off bad debt
	var remaining_loss: int = mini(loan.principal_outstanding, bank_state.ledger.get_balance(&"loan_principal_outstanding"))
	if remaining_loss > 0:
		var cl_res: Result = finance_engine.record_credit_loss(
			bank_state,
			remaining_loss,
			bank_state.current_day,
			bank_state.current_minute_of_day,
			"writeoff_" + loan_id
		)
		if not cl_res.ok:
			return cl_res
	loan.write_off()

	if event_bus != null:
		event_bus.publish(
			&"LoanWrittenOff",
			{
				"loan_id": loan_id,
				"borrower_name": loan.borrower_name,
				"salvage_minor": salvage,
				"loss_minor": remaining_loss,
			},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({
		"loan_id": loan_id,
		"salvage_minor": salvage,
		"loss_minor": remaining_loss,
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


func trigger_event_by_id(event_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	var ev_def: Dictionary = {}
	var raw_events: Variant = content_defs.get("events", [])
	if raw_events is Array:
		for e: Variant in (raw_events as Array):
			if e is Dictionary and str((e as Dictionary).get("id", "")) == event_id:
				ev_def = e as Dictionary
				break
	if ev_def.is_empty():
		return Result.fail(&"EVENT_NOT_FOUND", "ERR_EVENT_NOT_FOUND", {"event_id": event_id})
	var inst_id: String = bank_state.next_id("evt")
	var expire_mins: int = int(ev_def.get("expire_minutes", 120))
	var inst: Dictionary = {
		"instance_id": inst_id,
		"event_id": event_id,
		"title_key": str(ev_def.get("title_key", event_id)),
		"description_key": str(ev_def.get("description_key", "")),
		"options": (ev_def.get("options", []) as Array).duplicate(true),
		"triggered_day": bank_state.current_day,
		"triggered_minute": bank_state.current_minute_of_day,
		"remaining_minutes": expire_mins,
		"expire_minutes": expire_mins,
	}
	bank_state.active_events.append(inst)
	if event_bus != null:
		event_bus.publish(
			&"EventTriggered",
			{"instance_id": inst_id, "event_id": event_id},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed(inst)


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

func delete_station(station_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.stations.has(station_id):
		return Result.fail(&"STATION_NOT_FOUND", "ERR_STATION_NOT_FOUND", {"station_id": station_id})

	var st_entry: Dictionary = bank_state.stations[station_id] as Dictionary
	var st_type: String = str(st_entry.get("station_type", "teller"))
	if st_type == "teller":
		var teller_cnt: int = 0
		for sid_v: Variant in bank_state.stations.keys():
			var sv: Variant = bank_state.stations[sid_v]
			if sv is Dictionary and str((sv as Dictionary).get("station_type", "")) == "teller":
				teller_cnt += 1
		if teller_cnt <= 1:
			return Result.fail(&"CANNOT_DELETE_LAST_TELLER", "ERR_CANNOT_DELETE_LAST_TELLER", {})

	# Release any in-progress request & unassign bound employee
	var bound_emp_id: String = str(st_entry.get("assigned_employee_id", ""))
	if not bound_emp_id.is_empty() and bank_state.employees.has(bound_emp_id):
		var emp: EmployeeInstance = bank_state.employees[bound_emp_id] as EmployeeInstance
		if emp != null:
			emp.assigned_station_id = ""
			emp.complete_current_task()
	for req in bank_state.service_requests:
		if req != null and req.assigned_station_id == station_id and not req.is_terminal():
			req.release_to_queue()
			if bank_state.active_customers.has(req.customer_id):
				var cust: CustomerInstance = bank_state.active_customers[req.customer_id] as CustomerInstance
				if cust != null:
					cust.assigned_station_id = ""
					cust.transition_to(Enums.CustomerState.WAITING)

	bank_state.stations.erase(station_id)
	if event_bus != null:
		event_bus.publish(
			&"StationDeleted",
			{"station_id": station_id, "station_type": st_type},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"station_id": station_id})


func delete_lobby_prop(prop_id: String) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not bank_state.lobby_props.has(prop_id):
		return Result.fail(&"PROP_NOT_FOUND", "ERR_PROP_NOT_FOUND", {"prop_id": prop_id})

	var pr: Dictionary = bank_state.lobby_props[prop_id] as Dictionary
	var ptype: String = str(pr.get("prop_type", ""))
	bank_state.lobby_props.erase(prop_id)
	for cust_v: Variant in bank_state.active_customers.values():
		if cust_v is CustomerInstance and (cust_v as CustomerInstance).browsing_prop_id == prop_id:
			(cust_v as CustomerInstance).browsing_prop_id = ""
	if event_bus != null:
		event_bus.publish(
			&"LobbyPropDeleted",
			{"prop_id": prop_id, "prop_type": ptype},
			bank_state.current_day,
			bank_state.current_minute_of_day
		)
	_notify_mutated()
	return Result.succeed({"prop_id": prop_id, "prop_type": ptype})


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
		"lobby_manager":
			return "emp_hr"
		_:
			return fallback if fallback != "" else "emp_teller_m"


func _spawn_replacement_candidate(count: int) -> void:
	if bank_state == null or bank_state.rng_streams == null:
		return
	var crng: RandomNumberGenerator = bank_state.rng_streams.candidate_rng
	if crng == null:
		return
	var roles: Array[String] = ["teller", "loan_officer", "analyst", "manager", "lobby_manager"]
	var avatars: Array[String] = ["emp_teller_f", "emp_credit", "emp_risk", "emp_ops", "emp_hr"]
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
		var lvl_roll: int = crng.randi_range(0, 99)
		var cand_lvl: int = 1 if lvl_roll < 55 else (2 if lvl_roll < 85 else 3)
		cand.level = cand_lvl
		var c_cap: int = cand.get_stat_cap()
		cand.professionalism = mini(c_cap, crng.randi_range(44 + (cand_lvl - 1) * 14, 65 + (cand_lvl - 1) * 16))
		cand.efficiency = mini(c_cap, crng.randi_range(44 + (cand_lvl - 1) * 14, 65 + (cand_lvl - 1) * 16))
		cand.sociability = mini(c_cap, crng.randi_range(42 + (cand_lvl - 1) * 12, 64 + (cand_lvl - 1) * 16))
		cand.risk_awareness = mini(c_cap, crng.randi_range(42 + (cand_lvl - 1) * 12, 64 + (cand_lvl - 1) * 16))
		cand.management = mini(c_cap, crng.randi_range(38 + (cand_lvl - 1) * 12, 60 + (cand_lvl - 1) * 16))
		cand.loyalty = mini(c_cap, crng.randi_range(50, 82))
		cand.potential = crng.randi_range(50, 88)
		var base_sal: int = 18_000 if cand_lvl == 1 else (28_000 if cand_lvl == 2 else 42_000)
		cand.daily_salary_minor = base_sal + r_idx * 2_500
		var pos_pool: Array[String] = [
			"core:trait.sales_prodigy", "core:trait.risk_expert", "core:trait.workaholic",
			"core:trait.detail_oriented", "core:trait.bank_veteran", "core:trait.team_leader",
			"core:trait.vip_whisperer", "core:trait.fast_hands", "core:trait.compliance_shield",
			"core:trait.rising_star",
		]
		var neg_pool: Array[String] = [
			"core:trait.procrastinator", "core:trait.impatient", "core:trait.careless", "core:trait.burnout_prone",
		]
		if crng.randi_range(0, 99) < 25:
			cand.traits = [neg_pool[crng.randi_range(0, neg_pool.size() - 1)]]
		else:
			cand.traits = [pos_pool[crng.randi_range(0, pos_pool.size() - 1)]]
		cand.state = Enums.EmployeeState.OFF_DUTY
		bank_state.candidates.append(cand)
