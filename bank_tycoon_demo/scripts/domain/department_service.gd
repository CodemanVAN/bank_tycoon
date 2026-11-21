class_name DepartmentService
extends RefCounted

## Department lifecycle, level upgrades, capability unlocks, and synergy evaluation.

class DepartmentInstance extends RefCounted:
	var id: String = ""
	var level: int = 1
	var created_day: int = 1
	var daily_cost_minor: int = 0
	var staff_ids: Array[String] = []
	## Logical lobby cell chosen by the player. (-1, -1) = legacy/unplaced department.
	var grid_pos: Vector2i = Vector2i(-1, -1)

	func to_dict() -> Dictionary:
		var staff_copy: Array[String] = []
		for sid in staff_ids:
			staff_copy.append(sid)
		return {
			"id": id,
			"level": level,
			"created_day": created_day,
			"daily_cost_minor": daily_cost_minor,
			"staff_ids": staff_copy,
			"grid_pos": [grid_pos.x, grid_pos.y],
		}

	static func from_dict(data: Dictionary) -> DepartmentInstance:
		var inst := DepartmentInstance.new()
		inst.id = str(data.get("id", ""))
		inst.level = maxi(1, int(data.get("level", 1)))
		inst.created_day = maxi(1, int(data.get("created_day", 1)))
		inst.daily_cost_minor = maxi(0, int(data.get("daily_cost_minor", 0)))
		inst.grid_pos = _parse_grid_pos(data.get("grid_pos", null))
		inst.staff_ids = []
		var raw_staff: Variant = data.get("staff_ids", [])
		if raw_staff is Array:
			for sid in (raw_staff as Array):
				inst.staff_ids.append(str(sid))
		return inst

	static func _parse_grid_pos(raw: Variant) -> Vector2i:
		if raw is Vector2i:
			return raw as Vector2i
		if raw is Array:
			var arr: Array = raw as Array
			if arr.size() >= 2:
				return Vector2i(int(arr[0]), int(arr[1]))
		if raw is Dictionary:
			var d: Dictionary = raw as Dictionary
			return Vector2i(int(d.get("x", -1)), int(d.get("y", -1)))
		return Vector2i(-1, -1)


static func _find_dept_def(dept_id: String, content_defs: Dictionary) -> Dictionary:
	var list: Variant = content_defs.get("departments", [])
	if list is Array:
		for item in (list as Array):
			if item is Dictionary and str((item as Dictionary).get("id", "")) == dept_id:
				return item as Dictionary
	return {}


static func _extract_level(entry: Variant) -> int:
	if entry is Object:
		return maxi(0, int((entry as Object).get("level")))
	if entry is Dictionary:
		return maxi(0, int((entry as Dictionary).get("level", 0)))
	return 0


static func _set_level(entry: Variant, new_level: int) -> void:
	if entry is Object:
		(entry as Object).set("level", new_level)
	elif entry is Dictionary:
		(entry as Dictionary)["level"] = new_level


func _check_unlock_conditions(conditions: Variant, bank_state: BankState) -> bool:
	if not (conditions is Array):
		return true
	for raw_cond in (conditions as Array):
		if not (raw_cond is Dictionary):
			return false
		var cond: Dictionary = raw_cond as Dictionary
		var ctype: String = str(cond.get("type", ""))
		match ctype:
			"day_at_least":
				if bank_state.current_day < int(cond.get("value", 0)):
					return false
			"department_exists":
				if not has_department(bank_state, str(cond.get("value", "")), int(cond.get("min_level", 1))):
					return false
			"policy_adopted":
				if not bank_state.adopted_policies.has(str(cond.get("value", ""))):
					return false
			"metric_above":
				var val: Variant = cond.get("value", {})
				if not (val is Dictionary):
					return false
				var md: Dictionary = val as Dictionary
				var metric_name: String = str(md.get("metric", ""))
				var threshold: int = int(md.get("threshold", 0))
				var actual: int = _read_metric(bank_state, metric_name)
				if actual <= threshold:
					return false
			_:
				return false
	return true


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
		_:
			return 0


func create_department(
	bank_state: BankState,
	dept_id: String,
	content_defs: Dictionary,
	finance_engine: FinanceEngine = null,
	grid_pos: Vector2i = Vector2i(-1, -1)
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not ContentId.is_valid(dept_id):
		return Result.fail(&"INVALID_CONTENT_ID", "ERR_INVALID_CONTENT_ID", {"id": dept_id})
	var dept_def: Dictionary = _find_dept_def(dept_id, content_defs)
	if dept_def.is_empty():
		return Result.fail(&"DEPT_NOT_FOUND", "ERR_DEPT_NOT_FOUND", {"department_id": dept_id})
	if bank_state.departments.has(dept_id):
		return Result.fail(&"DEPT_ALREADY_EXISTS", "ERR_DEPT_ALREADY_EXISTS", {"department_id": dept_id})

	# Plot is optional for backward compatibility (tests / auto placement), but a partially
	# negative cell is a bug at the call site and is rejected instead of silently ignored.
	var has_plot: bool = grid_pos.x >= 0 and grid_pos.y >= 0
	if (grid_pos.x >= 0) != (grid_pos.y >= 0):
		return Result.fail(&"DEPT_PLOT_INVALID", "ERR_DEPT_PLOT_INVALID", {"x": grid_pos.x, "y": grid_pos.y})
	if has_plot and not is_plot_free(bank_state, grid_pos, dept_id):
		return Result.fail(&"DEPT_PLOT_OCCUPIED", "ERR_DEPT_PLOT_OCCUPIED", {"x": grid_pos.x, "y": grid_pos.y})

	if not _check_unlock_conditions(dept_def.get("unlock_conditions", []), bank_state):
		return Result.fail(&"DEPT_LOCKED", "ERR_DEPT_LOCKED", {"department_id": dept_id})

	var cost: int = maxi(0, int(dept_def.get("initial_cost_minor", 0)))
	var cash_bal: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash_bal < cost:
		return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": cost, "available": cash_bal})

	if cost > 0:
		var fe: FinanceEngine = finance_engine if finance_engine != null else FinanceEngine.new()
		var pay_res: Result = fe.record_operating_cost(
			bank_state,
			cost,
			bank_state.current_day,
			bank_state.current_minute_of_day,
			"dept_create_" + dept_id
		)
		if not pay_res.ok:
			return pay_res

	var inst := DepartmentInstance.new()
	inst.id = dept_id
	inst.level = 1
	inst.created_day = bank_state.current_day
	inst.daily_cost_minor = maxi(0, int(dept_def.get("daily_cost_minor", 0)))
	inst.grid_pos = grid_pos if has_plot else Vector2i(-1, -1)
	bank_state.departments[dept_id] = inst

	return Result.succeed({
		"department_id": dept_id,
		"level": 1,
		"cost_minor": cost,
		"grid_pos": [inst.grid_pos.x, inst.grid_pos.y],
	})


## Returns the stored lobby cell or (-1, -1) when the department is unplaced / unknown.
static func get_department_grid_pos(bank_state: BankState, dept_id: String) -> Vector2i:
	if bank_state == null:
		return Vector2i(-1, -1)
	if not bank_state.departments.has(dept_id):
		return Vector2i(-1, -1)
	return _entry_grid_pos(bank_state.departments[dept_id])


## True when no station and no other department occupies `cell`.
static func is_plot_free(bank_state: BankState, cell: Vector2i, ignore_dept_id: String = "") -> bool:
	if bank_state == null:
		return false
	for sid: Variant in bank_state.stations.keys():
		var st: Variant = bank_state.stations[sid]
		if st is Dictionary:
			var gp: Variant = (st as Dictionary).get("grid_pos", null)
			if gp is Vector2i and (gp as Vector2i) == cell:
				return false
	for did: Variant in bank_state.departments.keys():
		if str(did) == ignore_dept_id:
			continue
		if _entry_grid_pos(bank_state.departments[did]) == cell:
			return false
	return true


static func _entry_grid_pos(entry: Variant) -> Vector2i:
	if entry is Object:
		var raw: Variant = (entry as Object).get("grid_pos")
		if raw is Vector2i:
			return raw as Vector2i
		return DepartmentInstance._parse_grid_pos(raw)
	if entry is Dictionary:
		return DepartmentInstance._parse_grid_pos((entry as Dictionary).get("grid_pos", null))
	return Vector2i(-1, -1)


func upgrade_department(
	bank_state: BankState,
	dept_id: String,
	content_defs: Dictionary,
	finance_engine: FinanceEngine = null
) -> Result:
	if bank_state == null or bank_state.ledger == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	var dept_def: Dictionary = _find_dept_def(dept_id, content_defs)
	if dept_def.is_empty():
		return Result.fail(&"DEPT_NOT_FOUND", "ERR_DEPT_NOT_FOUND", {"department_id": dept_id})
	if not bank_state.departments.has(dept_id):
		return Result.fail(&"DEPT_NOT_CREATED", "ERR_DEPT_NOT_CREATED", {"department_id": dept_id})

	var entry: Variant = bank_state.departments[dept_id]
	var cur_lvl: int = _extract_level(entry)
	var max_lvl: int = maxi(1, int(dept_def.get("max_level", 3)))
	if cur_lvl >= max_lvl:
		return Result.fail(
			&"DEPT_MAX_LEVEL",
			"ERR_DEPT_MAX_LEVEL",
			{"department_id": dept_id, "level": cur_lvl, "max_level": max_lvl}
		)

	var init_cost: int = maxi(0, int(dept_def.get("initial_cost_minor", 0)))
	var upgrade_cost: int = BalanceConfig.calc_department_upgrade_cost(init_cost, cur_lvl)
	var cash_bal: int = bank_state.ledger.get_balance(&"cash_reserves")
	if cash_bal < upgrade_cost:
		return Result.fail(&"INSUFFICIENT_CASH", "ERR_INSUFFICIENT_CASH", {"required": upgrade_cost, "available": cash_bal})

	if upgrade_cost > 0:
		var fe: FinanceEngine = finance_engine if finance_engine != null else FinanceEngine.new()
		var pay_res: Result = fe.record_operating_cost(
			bank_state,
			upgrade_cost,
			bank_state.current_day,
			bank_state.current_minute_of_day,
			"dept_upgrade_%s_lv%d" % [dept_id, cur_lvl + 1]
		)
		if not pay_res.ok:
			return pay_res

	_set_level(entry, cur_lvl + 1)
	return Result.succeed({
		"department_id": dept_id,
		"level": cur_lvl + 1,
		"cost_minor": upgrade_cost,
	})


func get_department_level(bank_state: BankState, dept_id: String) -> int:
	if bank_state == null or not bank_state.departments.has(dept_id):
		return 0
	return _extract_level(bank_state.departments[dept_id])


func has_department(bank_state: BankState, dept_id: String, min_level: int = 1) -> bool:
	return get_department_level(bank_state, dept_id) >= min_level


func is_capability_unlocked(bank_state: BankState, capability_id: String) -> bool:
	match capability_id:
		"auto_queue_priority":
			return has_department(bank_state, "core:department.operations", 2)
		"auto_complaint_handling":
			return has_department(bank_state, "core:department.operations", 3)
		"extended_candidate_pool":
			return has_department(bank_state, "core:department.hr", 1)
		"skill_filter_and_training":
			return has_department(bank_state, "core:department.hr", 2)
		"fatigue_mitigation", "auto_hire_rules":
			return has_department(bank_state, "core:department.hr", 3)
		"loan_desk":
			return has_department(bank_state, "core:department.credit", 1)
		"auto_approve_low_risk_loans":
			return has_department(bank_state, "core:department.credit", 2)
		"loan_pricing_and_limit":
			return has_department(bank_state, "core:department.credit", 3)
		"exact_credit_score":
			return has_department(bank_state, "core:department.risk", 1)
		"high_risk_warning_and_review":
			return has_department(bank_state, "core:department.risk", 2)
		"stress_mitigation":
			return has_department(bank_state, "core:department.risk", 3)
		"synergy:hr_operations":
			return has_department(bank_state, "core:department.hr", 1) and has_department(bank_state, "core:department.operations", 1)
		"synergy:credit_risk":
			return has_department(bank_state, "core:department.credit", 1) and has_department(bank_state, "core:department.risk", 1)
		_:
			return false


func get_active_synergies(bank_state: BankState) -> Array[String]:
	var synergies: Array[String] = []
	if is_capability_unlocked(bank_state, "synergy:hr_operations"):
		synergies.append("synergy:hr_operations")
	if is_capability_unlocked(bank_state, "synergy:credit_risk"):
		synergies.append("synergy:credit_risk")
	return synergies


func get_total_daily_cost_minor(bank_state: BankState, content_defs: Dictionary) -> int:
	if bank_state == null:
		return 0
	var total: int = 0
	for did: Variant in bank_state.departments.keys():
		var dept_id: String = str(did)
		if get_department_level(bank_state, dept_id) <= 0:
			continue
		var ddef: Dictionary = _find_dept_def(dept_id, content_defs)
		if not ddef.is_empty():
			total += maxi(0, int(ddef.get("daily_cost_minor", 0)))
		else:
			var entry: Variant = bank_state.departments[did]
			if entry is Object:
				total += maxi(0, int((entry as Object).get("daily_cost_minor")))
			elif entry is Dictionary:
				total += maxi(0, int((entry as Dictionary).get("daily_cost_minor", 0)))
	return total


func get_onboarding_adaptation_days(
	bank_state: BankState,
	base_days: int = BalanceConfig.DEFAULT_ADAPTATION_DAYS
) -> int:
	if is_capability_unlocked(bank_state, "synergy:hr_operations"):
		return mini(base_days, BalanceConfig.SYNERGY_ADAPTATION_DAYS)
	return maxi(0, base_days)
