class_name BranchSimulation
extends RefCounted

## Fixed 8-step per-minute branch simulation loop.
## Purely stateful through BankState and its RngStreams for 100% mid-day save/load replay parity.

const HARD_CLOSE_MINUTE: int = 1_080
const INTRADAY_EVENT_ROLL_MINUTE: int = 720

var bank_state: BankState = null
var event_bus: DomainEventBus = null
var content_defs: Dictionary = {}
var dispatcher: EmployeeDispatcher = null
var finance_engine: FinanceEngine = null
var dept_service: DepartmentService = null
var event_engine: EventEngine = null
var modifiers: ModifierService = null


func _init(
	p_bank_state: BankState = null,
	p_event_bus: DomainEventBus = null,
	p_content_defs: Dictionary = {},
	p_modifiers: ModifierService = null
) -> void:
	bank_state = p_bank_state
	event_bus = p_event_bus
	content_defs = p_content_defs
	modifiers = p_modifiers if p_modifiers != null else ModifierService.new()
	dispatcher = EmployeeDispatcher.new()
	finance_engine = FinanceEngine.new()
	dept_service = DepartmentService.new()
	event_engine = EventEngine.new()


func tick_minute() -> void:
	if bank_state == null:
		return

	# Step 1: Advance time & phase (no ticks when PRE_OPEN or SETTLED)
	if bank_state.day_phase == Enums.DayPhase.PRE_OPEN or bank_state.day_phase == Enums.DayPhase.SETTLED:
		return

	bank_state.current_minute_of_day += 1
	var cur_day: int = bank_state.current_day
	var cur_min: int = bank_state.current_minute_of_day

	if event_bus != null:
		event_bus.publish(
			&"MinuteTicked",
			{"day": cur_day, "minute": cur_min},
			cur_day,
			cur_min
		)

	if bank_state.day_phase == Enums.DayPhase.OPEN and cur_min >= BalanceConfig.BUSINESS_CLOSE_MINUTE:
		bank_state.day_phase = Enums.DayPhase.CLOSING
		if event_bus != null:
			event_bus.publish(
				&"DayPhaseChanged",
				{"phase": bank_state.day_phase, "day": cur_day, "minute": cur_min},
				cur_day,
				cur_min
			)

	# Step 2: Spawn new customers, tick active event timers, & roll intraday events (ONLY during OPEN before 17:00)
	var expired_evs: Array[Dictionary] = event_engine.tick_active_events(bank_state, content_defs, 1)
	for exp_rec: Dictionary in expired_evs:
		if event_bus != null:
			event_bus.publish(
				&"EventExpired",
				{
					"event_instance_id": str(exp_rec.get("instance_id", "")),
					"event_id": str(exp_rec.get("event_id", "")),
					"followup_event_id": str(exp_rec.get("followup_event_id", "")),
				},
				cur_day,
				cur_min
			)
		var f_inst: Variant = exp_rec.get("followup_instance", {})
		if f_inst is Dictionary and not (f_inst as Dictionary).is_empty() and event_bus != null:
			var fi: Dictionary = f_inst as Dictionary
			event_bus.publish(
				&"EventTriggered",
				{
					"event_instance_id": str(fi.get("instance_id", "")),
					"event_id": str(fi.get("event_id", "")),
				},
				cur_day,
				cur_min
			)

	if bank_state.day_phase == Enums.DayPhase.OPEN and cur_min < BalanceConfig.BUSINESS_CLOSE_MINUTE:
		_step_customer_spawns(cur_day, cur_min)
		if cur_min == INTRADAY_EVENT_ROLL_MINUTE and bank_state.active_events.is_empty():
			var ev_rng: RandomNumberGenerator = bank_state.rng_streams.event_rng if bank_state.rng_streams != null else null
			var ev_res: Result = event_engine.process_scheduled_and_roll_event(bank_state, content_defs, ev_rng, 4500)
			if ev_res.ok and ev_res.data is Dictionary and bool((ev_res.data as Dictionary).get("triggered", false)):
				var inst: Dictionary = (ev_res.data as Dictionary).get("instance", {}) as Dictionary
				if event_bus != null:
					event_bus.publish(
						&"EventTriggered",
						{
							"event_instance_id": str(inst.get("instance_id", "")),
							"event_id": str(inst.get("event_id", "")),
						},
						cur_day,
						cur_min
					)

	# Step 3: Advance arriving customers, step ATM self-service, update patience & run Lobby Manager
	_step_customer_approach()
	_step_atm_self_service(cur_day, cur_min)
	_step_queue_patience(cur_day, cur_min)
	_step_lobby_manager(cur_day, cur_min)

	# Step 4: Dispatch queued requests to open stations & available employees
	dispatcher.dispatch(bank_state, event_bus, dept_service)

	# Step 5: Advance in-progress work & resting employee fatigue recovery
	_step_work_and_break_recovery()

	# Step 6: Complete finished services & post transactions to Ledger
	_step_complete_services(cur_day, cur_min)

	# Step 7: Re-dispatch immediately if stations freed up during Step 6
	dispatcher.dispatch(bank_state, event_bus, dept_service)
	if cur_min % 60 == 0 and bank_state.day_phase == Enums.DayPhase.OPEN:
		_check_employee_resignation_risk(cur_day, cur_min)

	# Step 8: Hard closing stop at 18:00 (minute 1080) for live real-time play
	if bank_state.day_phase == Enums.DayPhase.CLOSING and cur_min >= HARD_CLOSE_MINUTE:
		_flush_closing_and_auto_settle(cur_day, cur_min)


func _step_customer_spawns(cur_day: int, cur_min: int) -> void:
	if bank_state.rng_streams == null or bank_state.rng_streams.customer_rng == null:
		return
	var rng: RandomNumberGenerator = bank_state.rng_streams.customer_rng
	var spawn_roll: int = rng.randi_range(0, 9999)

	var offset_from_open: int = cur_min - BalanceConfig.BUSINESS_OPEN_MINUTE
	var aware_spawn_thresh: int = 160 + maxi(0, bank_state.awareness - 22) * 4
	var should_spawn: bool = (
		cur_min == BalanceConfig.BUSINESS_OPEN_MINUTE + 1
		or cur_min == BalanceConfig.BUSINESS_CLOSE_MINUTE - 7
		or (offset_from_open % 28 == 12)
		or spawn_roll < aware_spawn_thresh
	)
	if not should_spawn:
		return

	# Always consume fixed 6 RNG samples per spawned customer for strict stream determinism
	var type_roll: int = rng.randi_range(0, 99)
	var srv_roll: int = rng.randi_range(0, 99)
	var amt_roll: int = rng.randi_range(25, 110)
	var pat_roll: int = rng.randi_range(55, 85)
	var credit_roll: int = rng.randi_range(48, 92)
	var col_roll: int = rng.randi_range(0, 100)

	var cust_type: String = "regular"
	var avatar_id: String = "cust_regular"
	var name_key: String = "CUSTOMER_REGULAR_NAME"

	if type_roll < 36:
		cust_type = "regular"
		avatar_id = "cust_regular"
		name_key = "CUSTOMER_REGULAR_NAME"
	elif type_roll < 62:
		cust_type = "salaried"
		avatar_id = "cust_salaried"
		name_key = "CUSTOMER_SALARIED_NAME"
	elif type_roll < 78:
		cust_type = "borrower"
		avatar_id = "cust_borrower"
		name_key = "CUSTOMER_BORROWER_NAME"
	elif type_roll < 90:
		cust_type = "smb"
		avatar_id = "cust_smb"
		name_key = "CUSTOMER_SMB_NAME"
	elif type_roll < 97:
		cust_type = "vip"
		avatar_id = "cust_vip"
		name_key = "CUSTOMER_VIP_NAME"
	else:
		cust_type = "suspicious"
		avatar_id = "cust_suspicious"
		name_key = "CUSTOMER_SUSPICIOUS_NAME"

	var srv_type_str: String = "cash_deposit"
	if cur_min == BalanceConfig.BUSINESS_OPEN_MINUTE + 1 or cur_min == BalanceConfig.BUSINESS_CLOSE_MINUTE - 7:
		srv_type_str = "cash_deposit"
	else:
		match cust_type:
			"regular":
				if srv_roll < 36:
					srv_type_str = "cash_deposit"
				elif srv_roll < 62:
					srv_type_str = "cash_withdrawal"
				elif srv_roll < 78:
					srv_type_str = "transfer"
				elif srv_roll < 92:
					srv_type_str = "account_opening"
				else:
					srv_type_str = "complaint"
			"salaried":
				if srv_roll < 36:
					srv_type_str = "cash_deposit"
				elif srv_roll < 58:
					srv_type_str = "cash_withdrawal"
				elif srv_roll < 74:
					srv_type_str = "transfer"
				elif srv_roll < 88:
					srv_type_str = "account_opening"
				else:
					srv_type_str = "personal_loan_application"
			"borrower":
				if srv_roll < 52:
					srv_type_str = "personal_loan_application"
				elif srv_roll < 74:
					srv_type_str = "cash_deposit"
				elif srv_roll < 88:
					srv_type_str = "cash_withdrawal"
				else:
					srv_type_str = "transfer"
			"smb":
				if srv_roll < 30:
					srv_type_str = "cash_deposit"
				elif srv_roll < 54:
					srv_type_str = "account_opening"
				elif srv_roll < 74:
					srv_type_str = "business_meeting"
				elif srv_roll < 90:
					srv_type_str = "personal_loan_application"
				else:
					srv_type_str = "wealth_advisory"
			"vip":
				if srv_roll < 35:
					srv_type_str = "cash_deposit"
				elif srv_roll < 65:
					srv_type_str = "wealth_advisory"
				elif srv_roll < 85:
					srv_type_str = "business_meeting"
				else:
					srv_type_str = "personal_loan_application"
			"suspicious":
				if srv_roll < 42:
					srv_type_str = "personal_loan_application"
				elif srv_roll < 76:
					srv_type_str = "cash_withdrawal"
				else:
					srv_type_str = "complaint"

	var cust := CustomerInstance.new()
	cust.id = bank_state.next_id("cust")
	cust.customer_type = cust_type
	cust.avatar_id = avatar_id
	cust.display_name_key = name_key
	cust.patience_max = pat_roll
	cust.patience_remaining = pat_roll
	cust.arrival_day = cur_day
	cust.arrival_minute = cur_min
	cust.grid_pos = Vector2i(9, 10)
	cust.target_grid_pos = Vector2i(7, 7)

	var aware_excess: int = maxi(0, bank_state.awareness - BalanceConfig.INITIAL_AWARENESS)
	var aware_mult_bps: int = 10_000 + aware_excess * 150
	var base_amt_minor: int = amt_roll * 2_500
	if cust_type == "vip" or cust_type == "smb":
		base_amt_minor = amt_roll * 5_000
	base_amt_minor = FinanceEngine.round_div(base_amt_minor * aware_mult_bps, 10_000)
	# High awareness unlocks large-ticket cash deposits & withdrawals
	if bank_state.awareness >= 30 and (srv_type_str == "cash_deposit" or srv_type_str == "cash_withdrawal") and col_roll >= 75:
		base_amt_minor *= 2
	var loan_principal_minor: int = clampi(amt_roll * 80_000, 3_000_000, 9_000_000)
	var loan_term_days: int = 60 if (col_roll % 2 == 0) else 90
	if cust_type == "vip" or cust_type == "smb":
		loan_principal_minor = clampi(amt_roll * 140_000, 6_000_000, 15_000_000)
		loan_term_days = 120 if (col_roll % 2 == 0) else 180
	elif cust_type == "suspicious":
		loan_principal_minor = clampi(amt_roll * 100_000, 4_000_000, 10_000_000)
		loan_term_days = 90
	if aware_excess >= 5:
		loan_principal_minor = FinanceEngine.round_div(loan_principal_minor * (10_000 + aware_excess * 100), 10_000)
	var collateral_val: int = (loan_principal_minor * col_roll) / 100 if col_roll >= 40 else 0

	var hist_score: int = credit_roll
	var income_minor: int = 400_000 + credit_roll * 7_500
	var risk_tag: String = "normal"
	if cust_type == "vip":
		hist_score = maxi(82, credit_roll)
		income_minor = 1_200_000
	elif cust_type == "suspicious":
		hist_score = mini(42, credit_roll)
		income_minor = 260_000
		risk_tag = "high"

	cust.credit_profile = {
		"income_minor": income_minor,
		"existing_debt_minor": 40_000,
		"history_score": hist_score,
		"collateral_value": collateral_val,
		"risk_tag": risk_tag,
	}

	var req := ServiceRequest.new()
	req.request_id = bank_state.next_id("req")
	req.customer_id = cust.id
	req.service_type = StringName(srv_type_str)
	req.required_skill = StringName(str(BalanceConfig.SERVICE_REQUIRED_SKILL.get(srv_type_str, "teller")))
	req.priority = Enums.QueuePriority.NORMAL
	if dept_service.is_capability_unlocked(bank_state, "auto_queue_priority"):
		if cust_type == "vip":
			req.priority = Enums.QueuePriority.VIP
		elif cust_type == "smb":
			req.priority = Enums.QueuePriority.PRIORITY

	var base_mins: int = int(BalanceConfig.BASE_SERVICE_MINUTES.get(srv_type_str, 6))
	var is_complex_case: bool = false
	if cur_min == BalanceConfig.BUSINESS_CLOSE_MINUTE - 7:
		base_mins = 8
	else:
		# Varied realistic per-customer handling duration; higher awareness attracts more complex cases
		base_mins = maxi(4, base_mins + (col_roll % 5) - 1)
		var complex_thresh: int = maxi(65, 85 - (bank_state.awareness / 5))
		if col_roll >= complex_thresh and srv_type_str != "complaint":
			is_complex_case = true
			base_mins = base_mins * 2 + 4
		elif srv_type_str == "complaint" and dept_service.is_capability_unlocked(bank_state, "auto_complaint_handling"):
			base_mins = maxi(2, base_mins / 2)

	var base_fee: int = int(BalanceConfig.BASE_SERVICE_FEE_MINOR.get(srv_type_str, 0))
	if is_complex_case:
		base_fee = maxi(6_000, base_fee * 2)

	var is_atm_eligible: bool = (
		(srv_type_str == "cash_deposit" or srv_type_str == "cash_withdrawal" or srv_type_str == "transfer")
		and not is_complex_case
		and base_amt_minor <= BalanceConfig.ATM_MAX_AMOUNT_MINOR
	)
	var atm_count: int = _count_atms()
	var self_atm_chance_bps: int = mini(
		BalanceConfig.ATM_SELF_SERVICE_MAX_BPS,
		BalanceConfig.ATM_SELF_SERVICE_BASE_BPS + maxi(0, atm_count - 1) * BalanceConfig.ATM_PER_UNIT_BONUS_BPS
	) if atm_count > 0 else 0
	var will_self_atm: bool = is_atm_eligible and atm_count > 0 and ((col_roll * 100) < self_atm_chance_bps)

	req.estimated_work_minutes = base_mins
	req.remaining_work_units = base_mins * 100
	req.created_at_day = cur_day
	req.created_at_minute = cur_min
	req.deadline_minute = cur_min + pat_roll
	req.status = Enums.RequestStatus.QUEUED
	req.payload = {
		"amount_minor": base_amt_minor,
		"principal_minor": loan_principal_minor,
		"annual_rate_bps": bank_state.loan_base_rate_bps,
		"term_days": loan_term_days,
		"collateral_value": collateral_val,
		"fee_minor": base_fee,
		"is_complex_case": is_complex_case,
		"is_atm_eligible": is_atm_eligible,
		"atm_mode": "self" if will_self_atm else "",
		"atm_walk_minutes": 0,
		"atm_minutes_remaining": BalanceConfig.ATM_SERVICE_MINUTES if will_self_atm else 0,
		"atm_started": false,
	}

	cust.active_request_id = req.request_id
	# Customer walks in from the front entrance before reaching the counter or ATM
	cust.approach_minutes_remaining = BalanceConfig.ATM_APPROACH_MINUTES if will_self_atm else 2
	cust.transition_to(Enums.CustomerState.FINDING_SERVICE)

	bank_state.active_customers[cust.id] = cust
	bank_state.service_requests.append(req)

	if event_bus != null:
		event_bus.publish(
			&"CustomerArrived",
			{
				"customer_id": cust.id,
				"customer_type": cust.customer_type,
				"request_id": req.request_id,
				"service_type": srv_type_str,
			},
			cur_day,
			cur_min
		)


func _count_atms() -> int:
	if bank_state == null:
		return 0
	var cnt: int = 0
	for pid_v: Variant in bank_state.lobby_props.keys():
		var pr: Variant = bank_state.lobby_props[pid_v]
		if pr is Dictionary and str((pr as Dictionary).get("prop_type", "")) == "atm":
			cnt += 1
	return cnt


func _step_atm_self_service(cur_day: int, cur_min: int) -> void:
	if bank_state.service_requests.is_empty():
		return
	var remaining: Array[ServiceRequest] = []
	for req in bank_state.service_requests:
		if req == null:
			continue
		var atm_mode: String = str(req.payload.get("atm_mode", ""))
		if req.status == Enums.RequestStatus.QUEUED and not atm_mode.is_empty():
			var cust_v: Variant = bank_state.active_customers.get(req.customer_id, null)
			if cust_v is CustomerInstance and (cust_v as CustomerInstance).state == Enums.CustomerState.WAITING:
				var walk_rem: int = int(req.payload.get("atm_walk_minutes", 0))
				if walk_rem > 0:
					req.payload["atm_walk_minutes"] = walk_rem - 1
					remaining.append(req)
					continue
				if not bool(req.payload.get("atm_started", false)):
					req.payload["atm_started"] = true
					if event_bus != null:
						event_bus.publish(
							&"AtmServiceStarted",
							{
								"request_id": req.request_id,
								"customer_id": req.customer_id,
								"service_type": String(req.service_type),
							},
							cur_day,
							cur_min
						)
				var rem_m: int = int(req.payload.get("atm_minutes_remaining", 0)) - 1
				req.payload["atm_minutes_remaining"] = rem_m
				if rem_m <= 0:
					var srv_str: String = String(req.service_type)
					var amt: int = maxi(10_000, int(req.payload.get("amount_minor", 40_000)))
					var tx_amt: int = 0
					var tx_fee: int = 0
					if srv_str == "cash_deposit":
						var dr: Result = finance_engine.record_deposit(bank_state, amt, cur_day, cur_min, "atm_" + req.request_id)
						if dr.ok:
							tx_amt = amt
					elif srv_str == "cash_withdrawal":
						var avail_dep: int = bank_state.ledger.get_balance(&"customer_deposits") if bank_state.ledger != null else 0
						var avail_cash: int = bank_state.ledger.get_balance(&"cash_reserves") if bank_state.ledger != null else 0
						var safe_wd: int = mini(amt, mini(avail_dep / 2, avail_cash / 4))
						if safe_wd >= 1_000:
							var wr: Result = finance_engine.record_withdrawal(bank_state, safe_wd, cur_day, cur_min, "atm_" + req.request_id)
							if wr.ok:
								tx_amt = safe_wd
						else:
							var f_r: Result = finance_engine.record_service_fee(bank_state, 1_500, cur_day, cur_min, "atm_fee_" + req.request_id)
							if f_r.ok:
								tx_fee = 1_500
					else:
						var fee_amt: int = maxi(1_500, int(req.payload.get("fee_minor", 3_500)))
						var fr: Result = finance_engine.record_service_fee(bank_state, fee_amt, cur_day, cur_min, "atm_tr_" + req.request_id)
						if fr.ok:
							tx_fee = fee_amt
							tx_amt = fee_amt

					req.status = Enums.RequestStatus.COMPLETED
					var cust: CustomerInstance = cust_v as CustomerInstance
					cust.transition_to(Enums.CustomerState.COMPLETED)
					cust.transition_to(Enums.CustomerState.LEAVING)
					bank_state.active_customers.erase(req.customer_id)
					bank_state.satisfaction = clampi(bank_state.satisfaction + 1, 0, 100)
					if event_bus != null:
						event_bus.publish(
							&"ServiceCompleted",
							{
								"request_id": req.request_id,
								"customer_id": req.customer_id,
								"employee_id": "",
								"station_id": "atm",
								"service_type": srv_str,
								"amount_minor": tx_amt,
								"fee_minor": tx_fee,
								"via_atm": true,
							},
							cur_day,
							cur_min
						)
					continue
		remaining.append(req)
	bank_state.service_requests = remaining


func _step_customer_approach() -> void:
	for cust_v: Variant in bank_state.active_customers.values():
		if not (cust_v is CustomerInstance):
			continue
		var cust: CustomerInstance = cust_v as CustomerInstance
		if cust.state == Enums.CustomerState.FINDING_SERVICE:
			if cust.approach_minutes_remaining > 0:
				cust.approach_minutes_remaining -= 1
			if cust.approach_minutes_remaining <= 0:
				cust.transition_to(Enums.CustomerState.WAITING)


func _step_lobby_manager(cur_day: int, cur_min: int) -> void:
	var managers: Array[EmployeeInstance] = []
	var emp_ids: Array[String] = []
	for eid: Variant in bank_state.employees.keys():
		emp_ids.append(str(eid))
	emp_ids.sort()
	for eid in emp_ids:
		var ev: Variant = bank_state.employees[eid]
		if ev is EmployeeInstance:
			var emp: EmployeeInstance = ev as EmployeeInstance
			if emp.role_id == "lobby_manager" and emp.department_id == "" and emp.state != Enums.EmployeeState.BREAK and emp.state != Enums.EmployeeState.OFF_DUTY:
				managers.append(emp)
	if managers.is_empty() or bank_state.service_requests.is_empty():
		return

	# 1. Actively guide ATM-eligible waiting customers (who didn't self-route to ATM) to ATMs!
	# Runs every minute when ATMs exist; each lobby manager can guide 1 waiting customer per cycle.
	var atm_count: int = _count_atms()
	var guided_cids: Dictionary = {}
	for mgr: EmployeeInstance in managers:
		var acted: bool = false
		if atm_count > 0:
			for req in bank_state.service_requests:
				if req == null or req.status != Enums.RequestStatus.QUEUED:
					continue
				if guided_cids.has(req.customer_id):
					continue
				var already_atm: bool = not str(req.payload.get("atm_mode", "")).is_empty()
				if already_atm:
					continue
				var cust_v: Variant = bank_state.active_customers.get(req.customer_id, null)
				if not (cust_v is CustomerInstance):
					continue
				var cust: CustomerInstance = cust_v as CustomerInstance
				if cust.state != Enums.CustomerState.WAITING:
					continue
				var srv_str: String = String(req.service_type)
				var amt: int = int(req.payload.get("amount_minor", 0))
				var can_atm: bool = bool(req.payload.get("is_atm_eligible", false)) or (
					(srv_str == "cash_deposit" or srv_str == "cash_withdrawal" or srv_str == "transfer")
					and not bool(req.payload.get("is_complex_case", false))
					and amt <= BalanceConfig.ATM_MAX_AMOUNT_MINOR
				)
				if can_atm:
					# Route the waiting customer to walk over to the ATM and complete self-service there
					req.payload["atm_mode"] = "guided"
					req.payload["atm_walk_minutes"] = BalanceConfig.ATM_GUIDED_WALK_MINUTES
					req.payload["atm_minutes_remaining"] = BalanceConfig.ATM_SERVICE_MINUTES
					req.payload["atm_started"] = false
					cust.browsing_prop_id = ""
					cust.dissatisfaction = maxi(0, cust.dissatisfaction - 15)
					cust.patience_remaining = mini(cust.patience_max, cust.patience_remaining + 6)
					mgr.add_fatigue(1)
					mgr.gain_work_experience(10)
					guided_cids[req.customer_id] = true
					acted = true
					if event_bus != null:
						event_bus.publish(
							&"LobbyManagerAction",
							{
								"action": "atm_guide",
								"employee_id": mgr.id,
								"customer_id": req.customer_id,
								"amount_minor": amt,
							},
							cur_day,
							cur_min
						)
					break

		if acted:
			continue

		# 1b. Resolve waiting complaint customers
		if cur_min % 2 == 0:
			for req_c in bank_state.service_requests:
				if req_c == null or req_c.status != Enums.RequestStatus.QUEUED:
					continue
				if String(req_c.service_type) != "complaint":
					continue
				var cust_cv: Variant = bank_state.active_customers.get(req_c.customer_id, null)
				if not (cust_cv is CustomerInstance):
					continue
				var cust_c: CustomerInstance = cust_cv as CustomerInstance
				if cust_c.state != Enums.CustomerState.WAITING:
					continue
				req_c.status = Enums.RequestStatus.COMPLETED
				cust_c.transition_to(Enums.CustomerState.COMPLETED)
				cust_c.transition_to(Enums.CustomerState.LEAVING)
				bank_state.active_customers.erase(req_c.customer_id)
				bank_state.satisfaction = clampi(bank_state.satisfaction + 2, 0, 100)
				mgr.add_fatigue(1)
				mgr.gain_work_experience(15)
				if event_bus != null:
					event_bus.publish(
						&"LobbyManagerAction",
						{
							"action": "resolve_complaint",
							"employee_id": mgr.id,
							"customer_id": req_c.customer_id,
						},
						cur_day,
						cur_min
					)
				break

	# 2. Soothe impatient waiting customers every 3 minutes
	var primary_mgr: EmployeeInstance = managers[0]
	if cur_min % 3 == 0:
		var most_impatient: CustomerInstance = null
		var lowest_ratio: float = 0.72
		for cust_v2: Variant in bank_state.active_customers.values():
			if not (cust_v2 is CustomerInstance):
				continue
			var c2: CustomerInstance = cust_v2 as CustomerInstance
			if c2.state != Enums.CustomerState.WAITING:
				continue
			var r: float = float(c2.patience_remaining) / float(maxi(1, c2.patience_max))
			if r < lowest_ratio:
				lowest_ratio = r
				most_impatient = c2
		if most_impatient != null:
			most_impatient.patience_remaining = mini(most_impatient.patience_max, most_impatient.patience_remaining + 8)
			most_impatient.dissatisfaction = maxi(0, most_impatient.dissatisfaction - 10)
			if event_bus != null:
				event_bus.publish(
					&"LobbyManagerAction",
					{
						"action": "soothe",
						"employee_id": primary_mgr.id,
						"customer_id": most_impatient.id,
					},
					cur_day,
					cur_min
				)


func _step_queue_patience(cur_day: int, cur_min: int) -> void:
	if bank_state.service_requests.is_empty():
		return

	# Collect available luxury decor & basic amenities in the lobby
	var luxury_prop_ids: Array[String] = []
	var has_basic_amenity: bool = false
	for pid_v: Variant in bank_state.lobby_props.keys():
		var pr: Variant = bank_state.lobby_props[pid_v]
		if pr is Dictionary:
			var pt: String = str((pr as Dictionary).get("prop_type", ""))
			if BalanceConfig.LUXURY_DECOR_TYPES.has(pt):
				luxury_prop_ids.append(str(pid_v))
			elif BalanceConfig.AMENITY_PROP_TYPES.has(pt):
				has_basic_amenity = true
	luxury_prop_ids.sort()

	var remaining_reqs: Array[ServiceRequest] = []
	for req in bank_state.service_requests:
		if req == null:
			continue
		if req.status == Enums.RequestStatus.QUEUED:
			var cust_v: Variant = bank_state.active_customers.get(req.customer_id, null)
			var timed_out: bool = false
			var angry_leave: bool = false
			if cust_v is CustomerInstance:
				var cust: CustomerInstance = cust_v as CustomerInstance
				timed_out = cust.tick_patience(1)

				# Waiting customers can randomly browse luxury decor to calm down & gain satisfaction
				var is_atm_routed: bool = not str(req.payload.get("atm_mode", "")).is_empty()
				if cust.state == Enums.CustomerState.WAITING and not is_atm_routed:
					if not cust.browsing_prop_id.is_empty() and not bank_state.lobby_props.has(cust.browsing_prop_id):
						cust.browsing_prop_id = ""
					if cust.browsing_prop_id.is_empty() and not luxury_prop_ids.is_empty() and cust.wait_minutes >= 2 and ((cur_min + cust.wait_minutes) % 5 == 0):
						var pick_pid: String = luxury_prop_ids[(cur_min + cust.arrival_minute) % luxury_prop_ids.size()]
						cust.browsing_prop_id = pick_pid
						cust.satisfaction_delta = mini(3, cust.satisfaction_delta + 1)
						if event_bus != null:
							var pr_d: Dictionary = bank_state.lobby_props[pick_pid] as Dictionary
							event_bus.publish(
								&"CustomerBrowsedDecor",
								{
									"customer_id": cust.id,
									"prop_id": pick_pid,
									"prop_type": str(pr_d.get("prop_type", "fountain")),
								},
								cur_day,
								cur_min
							)

					# Dissatisfaction progression: luxury browsing lowers it; lack of amenities accelerates it
					if not cust.browsing_prop_id.is_empty():
						cust.dissatisfaction = maxi(0, cust.dissatisfaction - 1)
						if cust.wait_minutes % 2 == 0:
							cust.patience_remaining = mini(cust.patience_max, cust.patience_remaining + 1)
					elif not luxury_prop_ids.is_empty():
						cust.dissatisfaction = mini(100, cust.dissatisfaction + 1)
					elif has_basic_amenity:
						cust.dissatisfaction = mini(100, cust.dissatisfaction + 2)
					else:
						cust.dissatisfaction = mini(100, cust.dissatisfaction + 4)

					if cust.dissatisfaction >= 100 or (timed_out and cust.dissatisfaction >= 60):
						angry_leave = true

			if angry_leave or timed_out or cur_min >= req.deadline_minute:
				req.status = Enums.RequestStatus.TIMED_OUT
				if cust_v is CustomerInstance:
					var cust_out: CustomerInstance = cust_v as CustomerInstance
					cust_out.timed_out = true
					cust_out.browsing_prop_id = ""
					cust_out.transition_to(Enums.CustomerState.LEAVING)
				bank_state.active_customers.erase(req.customer_id)
				if angry_leave:
					bank_state.satisfaction = clampi(bank_state.satisfaction - BalanceConfig.ANGRY_COMPLAINT_SAT_PENALTY, 0, 100)
					bank_state.reputation = clampi(bank_state.reputation - BalanceConfig.ANGRY_COMPLAINT_REP_PENALTY, 0, 100)
					bank_state.awareness = clampi(bank_state.awareness - 1, 0, 100)
					if event_bus != null:
						event_bus.publish(
							&"CustomerAngryComplaint",
							{
								"customer_id": req.customer_id,
								"request_id": req.request_id,
								"satisfaction_penalty": BalanceConfig.ANGRY_COMPLAINT_SAT_PENALTY,
							},
							cur_day,
							cur_min
						)
				else:
					bank_state.satisfaction = clampi(bank_state.satisfaction - 2, 0, 100)
				if event_bus != null:
					event_bus.publish(
						&"CustomerLeftUnserved",
						{
							"customer_id": req.customer_id,
							"request_id": req.request_id,
							"angry_complaint": angry_leave,
						},
						cur_day,
						cur_min
					)
				continue
		if not req.is_terminal():
			remaining_reqs.append(req)

	bank_state.service_requests = remaining_reqs


func _step_work_and_break_recovery() -> void:
	var emp_ids: Array[String] = []
	for eid: Variant in bank_state.employees.keys():
		emp_ids.append(str(eid))
	emp_ids.sort()

	for eid in emp_ids:
		var emp_v: Variant = bank_state.employees.get(eid, null)
		if emp_v is EmployeeInstance:
			var emp: EmployeeInstance = emp_v as EmployeeInstance
			if emp.state == Enums.EmployeeState.BREAK:
				emp.recover_fatigue(BalanceConfig.REST_FATIGUE_RECOVERY_PER_MIN)

	if bank_state.service_requests.is_empty():
		return

	var global_prod_bps: int = BalanceConfig.BPS_DENOMINATOR
	var teller_dur_bps: int = BalanceConfig.BPS_DENOMINATOR
	if modifiers != null:
		global_prod_bps = modifiers.evaluate_state_target(
			bank_state,
			content_defs,
			"staff.productivity_bps",
			BalanceConfig.BPS_DENOMINATOR
		)
		teller_dur_bps = modifiers.evaluate_state_target(
			bank_state,
			content_defs,
			"service.teller_duration_bps",
			BalanceConfig.BPS_DENOMINATOR
		)

	var ops_lvl: int = dept_service.get_department_level(bank_state, "core:department.operations")

	for req in bank_state.service_requests:
		if req == null or req.status != Enums.RequestStatus.IN_PROGRESS:
			continue

		var emp_prod_bps: int = BalanceConfig.BPS_DENOMINATOR
		if req.assigned_employee_id != "" and bank_state.employees.has(req.assigned_employee_id):
			var emp_v2: Variant = bank_state.employees[req.assigned_employee_id]
			if emp_v2 is EmployeeInstance:
				emp_prod_bps = (emp_v2 as EmployeeInstance).get_effective_productivity_bps()

		var combined_bps: int = FinanceEngine.round_div(
			emp_prod_bps * (global_prod_bps + ops_lvl * 1500),
			BalanceConfig.BPS_DENOMINATOR
		)

		var srv_str: String = String(req.service_type)
		var is_teller_srv: bool = (
			srv_str == "cash_deposit"
			or srv_str == "cash_withdrawal"
			or srv_str == "transfer"
			or srv_str == "complaint"
		)
		if is_teller_srv and teller_dur_bps > 0 and teller_dur_bps != BalanceConfig.BPS_DENOMINATOR:
			combined_bps = FinanceEngine.round_div(
				combined_bps * BalanceConfig.BPS_DENOMINATOR,
				maxi(2500, teller_dur_bps)
			)

		var work_units: int = maxi(25, FinanceEngine.round_div(100 * combined_bps, BalanceConfig.BPS_DENOMINATOR))
		req.advance_work(work_units)


func _step_complete_services(cur_day: int, cur_min: int) -> void:
	if bank_state.service_requests.is_empty():
		return

	var remaining_reqs: Array[ServiceRequest] = []
	var dep_growth_bps: int = BalanceConfig.BPS_DENOMINATOR
	if modifiers != null:
		dep_growth_bps = modifiers.evaluate_state_target(
			bank_state,
			content_defs,
			"customer.deposit_growth_bps",
			BalanceConfig.BPS_DENOMINATOR
		)
	var rate_factor_bps: int = clampi(8000 + bank_state.deposit_rate_bps * 10, 5000, 25000)
	var hr_lv3: bool = dept_service.is_capability_unlocked(bank_state, "fatigue_mitigation")
	var ops_lv3: bool = dept_service.is_capability_unlocked(bank_state, "auto_complaint_handling")
	var auto_loan_ok: bool = dept_service.is_capability_unlocked(bank_state, "auto_approve_low_risk_loans")

	for req in bank_state.service_requests:
		if req == null:
			continue
		if req.status != Enums.RequestStatus.IN_PROGRESS or req.remaining_work_units > 0:
			remaining_reqs.append(req)
			continue

		var srv_str: String = String(req.service_type)
		var tx_amount_minor: int = 0
		var tx_fee_minor: int = 0
		var cust_v: Variant = bank_state.active_customers.get(req.customer_id, null)
		var cust: CustomerInstance = cust_v as CustomerInstance if cust_v is CustomerInstance else null

		match srv_str:
			"cash_deposit":
				var base_amt: int = maxi(10_000, int(req.payload.get("amount_minor", 60_000)))
				var scaled_amt: int = FinanceEngine.round_div(
					FinanceEngine.round_div(base_amt * dep_growth_bps, BalanceConfig.BPS_DENOMINATOR) * rate_factor_bps,
					BalanceConfig.BPS_DENOMINATOR
				)
				scaled_amt = maxi(5_000, scaled_amt)
				var dep_res: Result = finance_engine.record_deposit(bank_state, scaled_amt, cur_day, cur_min, req.request_id)
				if dep_res.ok:
					tx_amount_minor = scaled_amt
			"cash_withdrawal":
				var req_wd: int = maxi(5_000, int(req.payload.get("amount_minor", 40_000)))
				var avail_dep: int = bank_state.ledger.get_balance(&"customer_deposits") if bank_state.ledger != null else 0
				var avail_cash: int = bank_state.ledger.get_balance(&"cash_reserves") if bank_state.ledger != null else 0
				var safe_wd: int = mini(req_wd, mini(avail_dep / 2, avail_cash / 4))
				if safe_wd >= 1_000:
					var wd_res: Result = finance_engine.record_withdrawal(bank_state, safe_wd, cur_day, cur_min, req.request_id)
					if wd_res.ok:
						tx_amount_minor = safe_wd
				else:
					var wd_fee: int = 2_000
					var wf_res: Result = finance_engine.record_service_fee(bank_state, wd_fee, cur_day, cur_min, "wd_fee_" + req.request_id)
					if wf_res.ok:
						tx_fee_minor = wd_fee
						tx_amount_minor = wd_fee
			"transfer", "business_meeting", "account_opening", "wealth_advisory":
				var fee_amt: int = maxi(
					500,
					int(req.payload.get("fee_minor", BalanceConfig.BASE_SERVICE_FEE_MINOR.get(srv_str, 1_500)))
				)
				var fee_res: Result = finance_engine.record_service_fee(bank_state, fee_amt, cur_day, cur_min, req.request_id)
				if fee_res.ok:
					tx_fee_minor = fee_amt
					tx_amount_minor = fee_amt
				if srv_str == "account_opening" or srv_str == "wealth_advisory":
					bank_state.satisfaction = clampi(bank_state.satisfaction + 1, 0, 100)
			"personal_loan_application":
				var app_fee: int = int(BalanceConfig.BASE_SERVICE_FEE_MINOR.get("personal_loan_application", 5_000))
				if app_fee > 0:
					var af_res: Result = finance_engine.record_service_fee(bank_state, app_fee, cur_day, cur_min, "fee_" + req.request_id)
					if af_res.ok:
						tx_fee_minor = app_fee
				var eval_dict: Dictionary = finance_engine.evaluate_loan_application(cust, req.payload, bank_state, modifiers)
				var rec_action: String = str(eval_dict.get("recommended_action", "review"))
				var principal_minor: int = maxi(50_000, int(req.payload.get("principal_minor", 250_000)))
				var rate_bps: int = maxi(100, int(req.payload.get("annual_rate_bps", bank_state.loan_base_rate_bps)))
				var term_days: int = maxi(5, int(req.payload.get("term_days", 30)))
				var cash_now: int = bank_state.ledger.get_balance(&"cash_reserves") if bank_state.ledger != null else 0

				if rec_action == "approve" and auto_loan_ok and principal_minor <= BalanceConfig.LOAN_AUTO_APPROVAL_LIMIT_MINOR and cash_now >= principal_minor + 2_000_000:
					var disb_res: Result = finance_engine.disburse_loan(
						bank_state,
						req.customer_id,
						principal_minor,
						rate_bps,
						term_days,
						req.request_id
					)
					if disb_res.ok and disb_res.data is LoanInstance:
						var ln: LoanInstance = disb_res.data as LoanInstance
						var ctype_l: String = cust.customer_type if cust != null else "borrower"
						ln.customer_type = ctype_l
						ln.borrower_name = LoanInstance.generate_borrower_name(req.customer_id, ctype_l)
						ln.credit_score = int(eval_dict.get("credit_score", 72))
						ln.risk_grade = Enums.string_to_risk_grade(str(eval_dict.get("risk_grade", "B")))
						ln.collateral_value = int(req.payload.get("collateral_value", 0))
						tx_amount_minor = principal_minor
				elif rec_action != "reject" and cash_now >= principal_minor + 2_000_000 and bank_state.pending_loan_approvals.size() < 5:
					var app_id: String = bank_state.next_id("app")
					var ctype_p: String = cust.customer_type if cust != null else "borrower"
					bank_state.pending_loan_approvals.append({
						"approval_id": app_id,
						"id": app_id,
						"request_id": req.request_id,
						"customer_id": req.customer_id,
						"customer_type": ctype_p,
						"borrower_name": LoanInstance.generate_borrower_name(req.customer_id, ctype_p),
						"principal_minor": principal_minor,
						"annual_rate_bps": rate_bps,
						"term_days": term_days,
						"collateral_value": int(req.payload.get("collateral_value", 0)),
						"credit_score": int(eval_dict.get("credit_score", 68)),
						"risk_grade": str(eval_dict.get("risk_grade", "B")),
						"estimated_pd_bps": int(eval_dict.get("estimated_pd_bps", 300)),
						"recommended_action": rec_action,
						"day": cur_day,
						"minute": cur_min,
					})
					if event_bus != null:
						event_bus.publish(
							&"LoanApprovalRequested",
							{
								"approval_id": app_id,
								"customer_id": req.customer_id,
								"principal_minor": principal_minor,
							},
							cur_day,
							cur_min
						)
			"complaint":
				bank_state.satisfaction = clampi(bank_state.satisfaction + (3 if ops_lv3 else 1), 0, 100)

		var emp_id: String = req.assigned_employee_id
		var st_id: String = req.assigned_station_id
		if emp_id != "" and bank_state.employees.has(emp_id):
			var emp_v: Variant = bank_state.employees[emp_id]
			if emp_v is EmployeeInstance:
				var emp: EmployeeInstance = emp_v as EmployeeInstance
				emp.add_fatigue(1 if hr_lv3 else 3)
				emp.gain_work_experience()
				emp.complete_current_task()

		req.status = Enums.RequestStatus.COMPLETED
		if cust != null:
			if cust.wait_minutes <= 8 and srv_str != "complaint":
				bank_state.satisfaction = clampi(bank_state.satisfaction + 1, 0, 100)
			cust.transition_to(Enums.CustomerState.COMPLETED)
			cust.transition_to(Enums.CustomerState.LEAVING)
		bank_state.active_customers.erase(req.customer_id)

		if event_bus != null:
			event_bus.publish(
				&"ServiceCompleted",
				{
					"request_id": req.request_id,
					"customer_id": req.customer_id,
					"employee_id": emp_id,
					"station_id": st_id,
					"service_type": srv_str,
					"amount_minor": tx_amount_minor,
					"fee_minor": tx_fee_minor,
				},
				cur_day,
				cur_min
			)

	bank_state.service_requests = remaining_reqs


func _check_employee_resignation_risk(cur_day: int, cur_min: int) -> void:
	if bank_state == null or bank_state.employees.size() <= 1:
		return
	var emp_ids: Array[String] = []
	for eid: Variant in bank_state.employees.keys():
		emp_ids.append(str(eid))
	emp_ids.sort()
	for eid: String in emp_ids:
		var emp: EmployeeInstance = bank_state.employees[eid] as EmployeeInstance
		if emp == null:
			continue
		var eff_a: Dictionary = emp.get_effective_attributes(content_defs)
		var eff_loyalty: int = int(eff_a["loyalty"])
		var high_risk: bool = (emp.fatigue >= 75 and eff_loyalty <= 45) or (emp.fatigue >= 90 and eff_loyalty <= 60)
		if not high_risk:
			continue
		var already_pending: bool = false
		for pr: Dictionary in bank_state.pending_resignations:
			if str(pr.get("employee_id", "")) == eid:
				already_pending = true
				break
		if already_pending:
			continue
		var entry: Dictionary = {
			"employee_id": eid,
			"fatigue": emp.fatigue,
			"loyalty": eff_loyalty,
			"day": cur_day,
			"minute": cur_min,
		}
		bank_state.pending_resignations.append(entry)
		if event_bus != null:
			event_bus.publish(&"EmployeeResignationRequested", entry, cur_day, cur_min)
		break


func _flush_closing_and_auto_settle(cur_day: int, cur_min: int) -> void:
	for emp_v: Variant in bank_state.employees.values():
		if emp_v is EmployeeInstance:
			(emp_v as EmployeeInstance).complete_current_task()
	bank_state.service_requests.clear()
	bank_state.active_customers.clear()

	if not bank_state.settled_days.has(cur_day):
		var m_rng: RandomNumberGenerator = bank_state.rng_streams.market_rng if bank_state.rng_streams != null else null
		var settle_res: Result = finance_engine.run_daily_settlement(bank_state, modifiers, m_rng, content_defs)
		if settle_res.ok:
			var rep: Dictionary = settle_res.data as Dictionary if settle_res.data is Dictionary else {}
			if event_bus != null:
				event_bus.publish(
					&"DailySettlementCompleted",
					{"day": cur_day, "report": rep},
					cur_day,
					cur_min
				)
				event_bus.publish(
					&"DayPhaseChanged",
					{"phase": bank_state.day_phase, "day": cur_day, "minute": cur_min},
					cur_day,
					cur_min
				)
