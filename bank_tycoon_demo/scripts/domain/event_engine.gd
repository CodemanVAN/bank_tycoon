class_name EventEngine
extends RefCounted

## Data-driven event condition gating, deterministic weighted selection, resolution, and chaining.


static func _find_event_def(event_id: String, content_defs: Dictionary) -> Dictionary:
	var list: Variant = content_defs.get("events", [])
	if list is Array:
		for item in (list as Array):
			if item is Dictionary and str((item as Dictionary).get("id", "")) == event_id:
				return item as Dictionary
	return {}


static func _dept_level(bank_state: BankState, dept_id: String) -> int:
	if bank_state == null or not bank_state.departments.has(dept_id):
		return 0
	var entry: Variant = bank_state.departments[dept_id]
	if entry is Object:
		return maxi(0, int((entry as Object).get("level")))
	if entry is Dictionary:
		return maxi(0, int((entry as Dictionary).get("level", 0)))
	return 0


static func _last_event_day(event_id: String, bank_state: BankState) -> int:
	var last_day: int = -1
	for item in bank_state.event_history:
		if str(item.get("event_id", "")) == event_id:
			var d: int = int(item.get("day", -1))
			if d > last_day:
				last_day = d
	return last_day


static func _read_metric(bank_state: BankState, metric_name: String) -> int:
	match metric_name:
		"reputation":
			return bank_state.reputation
		"satisfaction":
			return bank_state.satisfaction
		"strategy_points":
			return bank_state.strategy_points
		"cash_reserves":
			return bank_state.ledger.get_balance(&"cash_reserves") if bank_state.ledger != null else 0
		"customer_deposits":
			return bank_state.ledger.get_balance(&"customer_deposits") if bank_state.ledger != null else 0
		"loan_principal_outstanding":
			return bank_state.ledger.get_balance(&"loan_principal_outstanding") if bank_state.ledger != null else 0
		"liquidity_ratio_bps":
			if bank_state.ledger == null:
				return 0
			var dep: int = bank_state.ledger.get_balance(&"customer_deposits")
			if dep <= 0:
				return 990_000
			var cash: int = bank_state.ledger.get_balance(&"cash_reserves")
			var base_wd: int = maxi(
				BalanceConfig.MIN_NEAR_TERM_WITHDRAWAL_FLOOR_MINOR,
				FinanceEngine.round_div(dep * BalanceConfig.NEAR_TERM_WITHDRAWAL_RATIO_BPS, BalanceConfig.BPS_DENOMINATOR)
			)
			return FinanceEngine.round_div(cash * BalanceConfig.BPS_DENOMINATOR, maxi(1, base_wd))
		"npl_ratio_bps":
			if bank_state.ledger == null:
				return 0
			var total_loans: int = bank_state.ledger.get_balance(&"loan_principal_outstanding")
			if total_loans <= 0:
				return 0
			var npl: int = 0
			for l: Variant in bank_state.loans.values():
				if l is LoanInstance and (l as LoanInstance).is_npl():
					npl += (l as LoanInstance).principal_outstanding
			return FinanceEngine.round_div(npl * BalanceConfig.BPS_DENOMINATOR, total_loans)
		_:
			return 0


func evaluate_condition(cond: Dictionary, bank_state: BankState, event_id: String = "") -> bool:
	if bank_state == null:
		return false
	var ctype: String = str(cond.get("type", ""))
	if not BalanceConfig.VALID_EVENT_CONDITIONS.has(ctype):
		return false

	match ctype:
		"day_at_least":
			return bank_state.current_day >= int(cond.get("value", 0))
		"department_exists":
			var req_dept: String = str(cond.get("value", ""))
			var min_lvl: int = maxi(1, int(cond.get("min_level", 1)))
			return _dept_level(bank_state, req_dept) >= min_lvl
		"policy_adopted":
			return bank_state.adopted_policies.has(str(cond.get("value", "")))
		"metric_above":
			var raw_val: Variant = cond.get("value", {})
			if not (raw_val is Dictionary):
				return false
			var md: Dictionary = raw_val as Dictionary
			var metric_name: String = str(md.get("metric", ""))
			var threshold: int = int(md.get("threshold", 0))
			return _read_metric(bank_state, metric_name) > threshold
		"cooldown_elapsed":
			var req_days: int = maxi(0, int(cond.get("value", 0)))
			var target_ev: String = str(cond.get("event_id", event_id))
			var last_d: int = _last_event_day(target_ev, bank_state)
			if last_d < 0:
				return true
			return (bank_state.current_day - last_d) >= req_days
		_:
			return false


func is_event_eligible(event_def: Dictionary, bank_state: BankState) -> bool:
	if bank_state == null or event_def.is_empty():
		return false
	var ev_id: String = str(event_def.get("id", ""))
	if ev_id == "":
		return false

	for active_ev in bank_state.active_events:
		if str(active_ev.get("event_id", "")) == ev_id:
			return false

	var cooldown_days: int = maxi(0, int(event_def.get("cooldown_days", 0)))
	if cooldown_days > 0:
		var last_d: int = _last_event_day(ev_id, bank_state)
		if last_d >= 0 and (bank_state.current_day - last_d) < cooldown_days:
			return false

	var conditions: Variant = event_def.get("conditions", [])
	if conditions is Array:
		for raw_c in (conditions as Array):
			if not (raw_c is Dictionary):
				return false
			if not evaluate_condition(raw_c as Dictionary, bank_state, ev_id):
				return false

	return true


func is_option_available(option_def: Dictionary, bank_state: BankState) -> Dictionary:
	if bank_state == null:
		return {"available": false, "reason_key": "ERR_INVALID_BANK_STATE"}
	var min_cash: int = maxi(0, int(option_def.get("min_cash_minor", 0)))
	if min_cash > 0 and bank_state.ledger != null:
		if bank_state.ledger.get_balance(&"cash_reserves") < min_cash:
			return {"available": false, "reason_key": "ERR_INSUFFICIENT_CASH"}

	var conditions: Variant = option_def.get("conditions", [])
	if conditions is Array:
		for raw_c in (conditions as Array):
			if not (raw_c is Dictionary):
				return {"available": false, "reason_key": "ERR_EVENT_OPTION_LOCKED"}
			if not evaluate_condition(raw_c as Dictionary, bank_state):
				return {"available": false, "reason_key": "ERR_EVENT_OPTION_LOCKED"}

	return {"available": true, "reason_key": ""}


func trigger_event(
	bank_state: BankState,
	event_id: String,
	content_defs: Dictionary,
	metadata: Dictionary = {}
) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	var ev_def: Dictionary = _find_event_def(event_id, content_defs)
	if ev_def.is_empty():
		return Result.fail(&"EVENT_NOT_FOUND", "ERR_EVENT_NOT_FOUND", {"event_id": event_id})

	var inst_id: String = bank_state.next_id("ev")
	var inst: Dictionary = {
		"instance_id": inst_id,
		"event_id": event_id,
		"day": bank_state.current_day,
		"minute": bank_state.current_minute_of_day,
		"metadata": metadata.duplicate(true),
	}
	bank_state.active_events.append(inst)
	return Result.succeed(inst)


func process_scheduled_and_roll_event(
	bank_state: BankState,
	content_defs: Dictionary,
	event_rng: RandomNumberGenerator,
	trigger_chance_bps: int = 3500
) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	# Step A: Process due scheduled chain events first (ignores weight == 0)
	var remaining_scheduled: Array[Dictionary] = []
	var triggered_chain: Dictionary = {}
	var fired_chain: bool = false
	for item in bank_state.scheduled_events:
		if not fired_chain and int(item.get("trigger_day", 999999)) <= bank_state.current_day:
			var eid: String = str(item.get("event_id", ""))
			var tr: Result = trigger_event(bank_state, eid, content_defs, {
				"source_event_id": str(item.get("source_event_id", "")),
				"source_option_id": str(item.get("source_option_id", "")),
			})
			if tr.ok:
				triggered_chain = tr.data as Dictionary
				fired_chain = true
				continue
		remaining_scheduled.append(item)
	bank_state.scheduled_events = remaining_scheduled

	if fired_chain:
		return Result.succeed({"triggered": true, "chained": true, "instance": triggered_chain})

	# Step B: Roll weighted random event if no event is currently active
	if not bank_state.active_events.is_empty() or event_rng == null:
		return Result.succeed({"triggered": false, "chained": false})

	var roll_chance: int = event_rng.randi_range(0, 9999)
	if roll_chance >= trigger_chance_bps:
		return Result.succeed({"triggered": false, "chained": false})

	var eligible: Array[Dictionary] = []
	var raw_events: Variant = content_defs.get("events", [])
	if raw_events is Array:
		for raw_ev in (raw_events as Array):
			if not (raw_ev is Dictionary):
				continue
			var ev_def: Dictionary = raw_ev as Dictionary
			if int(ev_def.get("weight", 0)) <= 0:
				continue
			if is_event_eligible(ev_def, bank_state):
				eligible.append(ev_def)

	if eligible.is_empty():
		return Result.succeed({"triggered": false, "chained": false})

	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)

	var total_weight: int = 0
	for ev in eligible:
		total_weight += int(ev.get("weight", 0))
	if total_weight <= 0:
		return Result.succeed({"triggered": false, "chained": false})

	var pick: int = event_rng.randi_range(0, total_weight - 1)
	var accum: int = 0
	var chosen_id: String = str(eligible[0].get("id", ""))
	for ev in eligible:
		accum += int(ev.get("weight", 0))
		if pick < accum:
			chosen_id = str(ev.get("id", ""))
			break

	var res: Result = trigger_event(bank_state, chosen_id, content_defs, {"chained": false})
	if not res.ok:
		return res
	return Result.succeed({"triggered": true, "chained": false, "instance": res.data})


func resolve_event_option(
	bank_state: BankState,
	event_instance_id: String,
	option_id: String,
	content_defs: Dictionary,
	finance_engine: FinanceEngine = null
) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})

	var found_idx: int = -1
	var inst: Dictionary = {}
	for i in range(bank_state.active_events.size()):
		var candidate: Dictionary = bank_state.active_events[i]
		var cid: String = str(candidate.get("instance_id", candidate.get("id", "")))
		if cid == event_instance_id:
			found_idx = i
			inst = candidate
			break

	if found_idx < 0:
		return Result.fail(
			&"EVENT_INSTANCE_NOT_FOUND",
			"ERR_EVENT_INSTANCE_NOT_FOUND",
			{"instance_id": event_instance_id}
		)

	var event_id: String = str(inst.get("event_id", inst.get("definition_id", "")))
	var ev_def: Dictionary = _find_event_def(event_id, content_defs)
	if ev_def.is_empty():
		return Result.fail(&"EVENT_NOT_FOUND", "ERR_EVENT_NOT_FOUND", {"event_id": event_id})

	var opt_def: Dictionary = {}
	var raw_opts: Variant = ev_def.get("options", [])
	if raw_opts is Array:
		for o in (raw_opts as Array):
			if o is Dictionary and str((o as Dictionary).get("id", "")) == option_id:
				opt_def = o as Dictionary
				break

	if opt_def.is_empty():
		return Result.fail(
			&"EVENT_OPTION_NOT_FOUND",
			"ERR_EVENT_OPTION_NOT_FOUND",
			{"event_id": event_id, "option_id": option_id}
		)

	var avail: Dictionary = is_option_available(opt_def, bank_state)
	if not bool(avail.get("available", false)):
		return Result.fail(
			&"EVENT_OPTION_LOCKED",
			str(avail.get("reason_key", "ERR_EVENT_OPTION_LOCKED")),
			{"event_id": event_id, "option_id": option_id}
		)

	var impact_key: String = "%s:%s" % [event_id, option_id]
	var impacts: Dictionary = {}
	if BalanceConfig.EVENT_DOMAIN_IMPACTS.has(impact_key):
		impacts = (BalanceConfig.EVENT_DOMAIN_IMPACTS[impact_key] as Dictionary).duplicate(true)
	var opt_impacts: Variant = opt_def.get("domain_impacts", {})
	if opt_impacts is Dictionary:
		for k: Variant in (opt_impacts as Dictionary).keys():
			impacts[str(k)] = (opt_impacts as Dictionary)[k]

	var duration_days: int = maxi(1, int(opt_def.get("duration_days", impacts.get("duration_days", 3))))

	# Apply schema effects
	var effs: Variant = opt_def.get("effects", [])
	if effs is Array:
		for raw_eff in (effs as Array):
			if not (raw_eff is Dictionary):
				continue
			var eff: Dictionary = raw_eff as Dictionary
			var target: String = str(eff.get("target", ""))
			if not BalanceConfig.MODIFIER_BOUNDS.has(target):
				continue
			var op: String = str(eff.get("operation", ""))
			if not BalanceConfig.VALID_MODIFIER_OPERATIONS.has(op):
				continue
			if target == "bank.reputation_points":
				var val: int = int(eff.get("value", 0))
				if op == "add":
					bank_state.reputation = clampi(bank_state.reputation + val, 0, 100)
				elif op == "set":
					bank_state.reputation = clampi(val, 0, 100)
			else:
				bank_state.active_event_modifiers.append({
					"source_id": event_id,
					"option_id": option_id,
					"effect": eff.duplicate(true),
					"expires_day": bank_state.current_day + duration_days,
				})

	# Apply non-effect domain impacts via Ledger / state fields
	var fe: FinanceEngine = finance_engine if finance_engine != null else FinanceEngine.new()
	var cash_delta: int = int(impacts.get("cash_delta_minor", 0))
	if cash_delta < 0 and bank_state.ledger != null:
		var avail_cash: int = bank_state.ledger.get_balance(&"cash_reserves")
		var spend: int = mini(absi(cash_delta), avail_cash)
		if spend > 0:
			fe.record_event_expense(bank_state, spend, bank_state.current_day, bank_state.current_minute_of_day, "ev_" + event_instance_id)
	elif cash_delta > 0:
		fe.record_service_fee(bank_state, cash_delta, bank_state.current_day, bank_state.current_minute_of_day, "ev_in_" + event_instance_id)

	var stress_prov: int = int(impacts.get("macro_stress_provision_minor", 0))
	if stress_prov > 0 and bank_state.ledger != null:
		var risk_lvl: int = _dept_level(bank_state, "core:department.risk")
		var was_prudent: bool = false
		for h_entry in bank_state.event_history:
			if str(h_entry.get("macro_risk_choice", "")) == "prudent":
				was_prudent = true
				break
		if risk_lvl >= 2:
			stress_prov = FinanceEngine.round_div(stress_prov * 40, 100)
		elif risk_lvl == 1 or was_prudent:
			stress_prov = FinanceEngine.round_div(stress_prov * 65, 100)
		var loan_bal: int = bank_state.ledger.get_balance(&"loan_principal_outstanding")
		var loss_amt: int = mini(stress_prov, loan_bal)
		if loss_amt > 0:
			var rem_to_write_off: int = loss_amt
			var loan_ids: Array[String] = []
			for lid: Variant in bank_state.loans.keys():
				loan_ids.append(str(lid))
			loan_ids.sort()
			for lid in loan_ids:
				if rem_to_write_off <= 0:
					break
				var ln: LoanInstance = bank_state.loans[lid] as LoanInstance
				if ln != null and ln.is_active() and ln.principal_outstanding > 0:
					var chunk: int = mini(rem_to_write_off, ln.principal_outstanding)
					ln.write_off(chunk)
					rem_to_write_off -= chunk
			fe.record_credit_loss(
				bank_state,
				loss_amt,
				bank_state.current_day,
				bank_state.current_minute_of_day,
				"ev_stress_" + event_instance_id
			)

	var sat_delta: int = int(impacts.get("satisfaction_delta", 0))
	if sat_delta != 0:
		bank_state.satisfaction = clampi(bank_state.satisfaction + sat_delta, 0, 100)

	var sp_delta: int = int(impacts.get("strategy_points_delta", 0))
	if sp_delta != 0:
		bank_state.strategy_points = maxi(0, bank_state.strategy_points + sp_delta)

	# Remove from active_events and record in event_history
	bank_state.active_events.remove_at(found_idx)
	var history_entry: Dictionary = {
		"instance_id": event_instance_id,
		"event_id": event_id,
		"option_id": option_id,
		"day": bank_state.current_day,
		"minute": bank_state.current_minute_of_day,
		"macro_risk_choice": str(impacts.get("macro_risk_choice", "")),
	}
	bank_state.event_history.append(history_entry)

	# Schedule chained event if configured
	var next_id: String = str(opt_def.get("next_event_id", ""))
	if next_id != "":
		var delay_days: int = maxi(1, int(opt_def.get("chain_delay_days", BalanceConfig.EVENT_CHAIN_DELAY_DAYS.get(next_id, 2))))
		bank_state.scheduled_events.append({
			"event_id": next_id,
			"trigger_day": bank_state.current_day + delay_days,
			"source_event_id": event_id,
			"source_option_id": option_id,
		})

	return Result.succeed({
		"instance_id": event_instance_id,
		"event_id": event_id,
		"option_id": option_id,
		"next_event_id": next_id,
	})


func expire_event_modifiers(bank_state: BankState) -> void:
	if bank_state == null:
		return
	var kept: Array[Dictionary] = []
	for entry in bank_state.active_event_modifiers:
		if int(entry.get("expires_day", 0)) >= bank_state.current_day:
			kept.append(entry)
	bank_state.active_event_modifiers = kept
