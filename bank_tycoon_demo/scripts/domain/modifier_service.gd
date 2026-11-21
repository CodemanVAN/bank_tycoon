class_name ModifierService
extends RefCounted

## Whitelisted effect aggregator and deterministic add -> multiply -> set evaluator.


const INT64_MAX_VAL: int = 9223372036854775807
const INT64_MIN_VAL: int = -9223372036854775807 - 1


static func _sat_add(a: int, b: int) -> int:
	if b > 0 and a > INT64_MAX_VAL - b:
		return INT64_MAX_VAL
	if b < 0 and a < INT64_MIN_VAL - b:
		return INT64_MIN_VAL
	return a + b


static func _sat_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	if a == INT64_MIN_VAL:
		if b == 1:
			return INT64_MIN_VAL
		return INT64_MAX_VAL if b < 0 else INT64_MIN_VAL
	if b == INT64_MIN_VAL:
		if a == 1:
			return INT64_MIN_VAL
		return INT64_MAX_VAL if a < 0 else INT64_MIN_VAL
	var abs_a: int = absi(a)
	var abs_b: int = absi(b)
	if abs_a > INT64_MAX_VAL / abs_b:
		return INT64_MIN_VAL if ((a < 0) != (b < 0)) else INT64_MAX_VAL
	return a * b


static func _round_div(numerator: int, denominator: int) -> int:
	if denominator == 0 or numerator == 0:
		return 0
	if denominator == INT64_MIN_VAL:
		if numerator == INT64_MIN_VAL:
			return 1
		var abs_n: int = absi(numerator)
		if abs_n >= 4611686018427387904:
			return -1 if numerator > 0 else 1
		return 0
	var abs_den: int = absi(denominator)
	if numerator == INT64_MIN_VAL and abs_den == 1:
		return INT64_MIN_VAL if denominator > 0 else INT64_MAX_VAL
	var sign_val: int = -1 if ((numerator < 0) != (denominator < 0)) else 1
	var neg_num: int = numerator if numerator < 0 else -numerator
	var quotient: int = -(neg_num / abs_den)
	var remainder: int = -(neg_num % abs_den)
	var half_up: int = (abs_den / 2) + (abs_den % 2)
	if remainder >= half_up:
		quotient += 1
	return sign_val * quotient


static func _sat_mul_bps(val: int, mult_bps: int) -> int:
	if val == 0 or mult_bps <= 0:
		return 0
	var den: int = BalanceConfig.BPS_DENOMINATOR
	var q_v: int = val / den
	var r_v: int = val % den
	var q_m: int = mult_bps / den
	var r_m: int = mult_bps % den
	var p1: int = _sat_mul(q_v, mult_bps)
	var p2: int = _sat_mul(r_v, q_m)
	var p3: int = _round_div(r_v * r_m, den)
	return _sat_add(_sat_add(p1, p2), p3)


func is_valid_target(target: String) -> bool:
	return BalanceConfig.MODIFIER_BOUNDS.has(target)


func is_valid_operation(op: String) -> bool:
	return BalanceConfig.VALID_MODIFIER_OPERATIONS.has(op)


func evaluate_effects(target: String, base_value: int, effects: Array) -> int:
	return evaluate_effects_scoped(target, base_value, effects, "")


func evaluate_effects_scoped(
	target: String,
	base_value: int,
	effects: Array,
	scope_filter: String = ""
) -> int:
	if not is_valid_target(target):
		return base_value

	var add_sum: int = 0
	var mult_list: Array[int] = []
	var has_set: bool = false
	var set_val: int = base_value

	for raw_eff in effects:
		if not (raw_eff is Dictionary):
			continue
		var eff: Dictionary = raw_eff as Dictionary
		if str(eff.get("target", "")) != target:
			continue
		if scope_filter != "":
			var eff_scope: String = str(eff.get("scope", "global"))
			if eff_scope != "global" and eff_scope != scope_filter:
				continue

		var op: String = str(eff.get("operation", ""))
		if not is_valid_operation(op):
			continue
		var val: Variant = eff.get("value", null)
		if not (val is int or val is float):
			continue
		var num_val: int = int(val)

		match op:
			"add":
				add_sum = _sat_add(add_sum, num_val)
			"multiply":
				mult_list.append(maxi(0, num_val))
			"set":
				has_set = true
				set_val = num_val

	var result_val: int = _sat_add(base_value, add_sum)
	for mult_bps in mult_list:
		result_val = _sat_mul_bps(result_val, mult_bps)
	if has_set:
		result_val = set_val

	var bounds: Dictionary = BalanceConfig.MODIFIER_BOUNDS[target] as Dictionary
	return clampi(result_val, int(bounds["min"]), int(bounds["max"]))


func evaluate_chance_modifiers(target: String, base_chance_bps: int, effects: Array) -> int:
	if not is_valid_target(target):
		return clampi(base_chance_bps, 0, BalanceConfig.BPS_DENOMINATOR)
	var total: int = base_chance_bps
	for raw_eff in effects:
		if not (raw_eff is Dictionary):
			continue
		var eff: Dictionary = raw_eff as Dictionary
		if str(eff.get("target", "")) != target:
			continue
		if str(eff.get("operation", "")) != "modify_chance":
			continue
		var val: Variant = eff.get("value", 0)
		if val is int or val is float:
			total = _sat_add(total, int(val))
	return clampi(total, 0, BalanceConfig.BPS_DENOMINATOR)


static func _extract_dept_level(entry: Variant) -> int:
	if entry is Object:
		return maxi(0, int((entry as Object).get("level")))
	if entry is Dictionary:
		return maxi(0, int((entry as Dictionary).get("level", 0)))
	return 0


static func _index_defs_by_id(defs_list: Variant) -> Dictionary:
	var idx: Dictionary = {}
	if defs_list is Array:
		for item in (defs_list as Array):
			if item is Dictionary:
				var did: String = str((item as Dictionary).get("id", ""))
				if did != "":
					idx[did] = item
	return idx


func collect_active_effects(bank_state: BankState, content_defs: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if bank_state == null:
		return out

	var dept_defs: Dictionary = _index_defs_by_id(content_defs.get("departments", []))
	var dept_ids: Array[String] = []
	for k: Variant in bank_state.departments.keys():
		dept_ids.append(str(k))
	dept_ids.sort()

	for did in dept_ids:
		var lvl: int = _extract_dept_level(bank_state.departments[did])
		if lvl <= 0:
			continue
		if dept_defs.has(did):
			var ddef: Dictionary = dept_defs[did] as Dictionary
			var effs: Variant = ddef.get("effects", [])
			if effs is Array:
				for raw_eff in (effs as Array):
					if not (raw_eff is Dictionary):
						continue
					var eff: Dictionary = (raw_eff as Dictionary).duplicate(true)
					var op: String = str(eff.get("operation", ""))
					if op == "add" and (eff.get("value") is int or eff.get("value") is float):
						eff["value"] = int(eff["value"]) * lvl
					out.append(eff)

	# Department synergies
	var has_ops: bool = _extract_dept_level(bank_state.departments.get("core:department.operations", null)) >= 1
	var has_hr: bool = _extract_dept_level(bank_state.departments.get("core:department.hr", null)) >= 1
	var has_credit: bool = _extract_dept_level(bank_state.departments.get("core:department.credit", null)) >= 1
	var has_risk: bool = _extract_dept_level(bank_state.departments.get("core:department.risk", null)) >= 1

	if has_ops and has_hr:
		out.append({
			"target": "staff.productivity_bps",
			"operation": "add",
			"value": 500,
			"scope": "global",
		})
		out.append({
			"target": "staff.productivity_bps",
			"operation": "unlock",
			"value": "synergy:hr_operations",
			"scope": "global",
		})

	if has_credit and has_risk:
		out.append({
			"target": "loan.default_risk_bps",
			"operation": "add",
			"value": -500,
			"scope": "global",
		})
		out.append({
			"target": "service.teller_duration_bps",
			"operation": "add",
			"value": -300,
			"scope": "service",
		})
		out.append({
			"target": "loan.default_risk_bps",
			"operation": "unlock",
			"value": "synergy:credit_risk",
			"scope": "global",
		})

	# Adopted policies
	var pol_defs: Dictionary = _index_defs_by_id(content_defs.get("policies", []))
	for pid in bank_state.adopted_policies:
		if pol_defs.has(pid):
			var pdef: Dictionary = pol_defs[pid] as Dictionary
			var effs: Variant = pdef.get("effects", [])
			if effs is Array:
				for raw_eff in (effs as Array):
					if not (raw_eff is Dictionary):
						continue
					var eff: Dictionary = raw_eff as Dictionary
					# One-shot reputation effects are applied at adoption time
					if str(eff.get("target", "")) == "bank.reputation_points":
						continue
					out.append(eff.duplicate(true))

	# Active temporary event modifiers
	for entry in bank_state.active_event_modifiers:
		if int(entry.get("expires_day", 0)) >= bank_state.current_day:
			var eff: Variant = entry.get("effect", null)
			if eff is Dictionary:
				out.append((eff as Dictionary).duplicate(true))

	return out


func evaluate_state_target(
	bank_state: BankState,
	content_defs: Dictionary,
	target: String,
	base_value: int
) -> int:
	var active: Array[Dictionary] = collect_active_effects(bank_state, content_defs)
	return evaluate_effects(target, base_value, active)


func get_unlocked_features(bank_state: BankState, content_defs: Dictionary) -> Array[String]:
	var unlocked: Array[String] = []
	var active: Array[Dictionary] = collect_active_effects(bank_state, content_defs)
	for eff in active:
		if str(eff.get("operation", "")) == "unlock":
			var val: String = str(eff.get("value", ""))
			if val != "" and not unlocked.has(val):
				unlocked.append(val)

	# Built-in level-based department unlocks
	var ops_lvl: int = _extract_dept_level(bank_state.departments.get("core:department.operations", null))
	if ops_lvl >= 2 and not unlocked.has("auto_queue_priority"):
		unlocked.append("auto_queue_priority")
	if ops_lvl >= 3 and not unlocked.has("auto_complaint_handling"):
		unlocked.append("auto_complaint_handling")

	var hr_lvl: int = _extract_dept_level(bank_state.departments.get("core:department.hr", null))
	if hr_lvl >= 1 and not unlocked.has("extended_candidate_pool"):
		unlocked.append("extended_candidate_pool")
	if hr_lvl >= 2 and not unlocked.has("skill_filter_and_training"):
		unlocked.append("skill_filter_and_training")
	if hr_lvl >= 3 and not unlocked.has("fatigue_mitigation"):
		unlocked.append("fatigue_mitigation")

	var credit_lvl: int = _extract_dept_level(bank_state.departments.get("core:department.credit", null))
	if credit_lvl >= 1 and not unlocked.has("loan_desk"):
		unlocked.append("loan_desk")
	if credit_lvl >= 2 and not unlocked.has("auto_approve_low_risk_loans"):
		unlocked.append("auto_approve_low_risk_loans")
	if credit_lvl >= 3 and not unlocked.has("loan_pricing_and_limit"):
		unlocked.append("loan_pricing_and_limit")

	var risk_lvl: int = _extract_dept_level(bank_state.departments.get("core:department.risk", null))
	if risk_lvl >= 1 and not unlocked.has("exact_credit_score"):
		unlocked.append("exact_credit_score")
	if risk_lvl >= 2 and not unlocked.has("high_risk_warning_and_review"):
		unlocked.append("high_risk_warning_and_review")
	if risk_lvl >= 3 and not unlocked.has("stress_mitigation"):
		unlocked.append("stress_mitigation")

	return unlocked


func has_unlock(bank_state: BankState, content_defs: Dictionary, feature_id: String) -> bool:
	return get_unlocked_features(bank_state, content_defs).has(feature_id)
