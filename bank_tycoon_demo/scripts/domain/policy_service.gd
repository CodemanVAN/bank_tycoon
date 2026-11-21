class_name PolicyService
extends RefCounted

## Strategic policy branch validation and irreversible adoption rules.

const CONSERVATIVE_BRANCH_IDS: Array[String] = [
	"core:policy.prudent_lending",
	"core:policy.liquidity_first",
	"core:policy.customer_trust",
]

const AGGRESSIVE_BRANCH_IDS: Array[String] = [
	"core:policy.high_rate_acquisition",
	"core:policy.market_penetration",
	"core:policy.credit_expansion",
]


static func _find_policy_def(policy_id: String, content_defs: Dictionary) -> Dictionary:
	var list: Variant = content_defs.get("policies", [])
	if list is Array:
		for item in (list as Array):
			if item is Dictionary and str((item as Dictionary).get("id", "")) == policy_id:
				return item as Dictionary
	return {}


static func _infer_doctrine_branch(policy_id: String, policy_def: Dictionary) -> String:
	if CONSERVATIVE_BRANCH_IDS.has(policy_id):
		return "conservative"
	if AGGRESSIVE_BRANCH_IDS.has(policy_id):
		return "aggressive"
	var grp: String = str(policy_def.get("exclusive_group", ""))
	if grp == "conservative" or grp == "aggressive":
		return grp
	return ""


static func _collect_transitive_prereqs(policy_id: String, content_defs: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var visited: Dictionary = {policy_id: true}
	var queue: Array[String] = [policy_id]
	while not queue.is_empty():
		var cur_id: String = queue.pop_front()
		var cur_def: Dictionary = _find_policy_def(cur_id, content_defs)
		var raw_prereqs: Variant = cur_def.get("prerequisites", [])
		if raw_prereqs is Array:
			for pre in (raw_prereqs as Array):
				var pid_str: String = str(pre)
				if pid_str != "" and not visited.has(pid_str):
					visited[pid_str] = true
					result.append(pid_str)
					queue.append(pid_str)
	return result


func can_adopt_policy(
	bank_state: BankState,
	policy_id: String,
	content_defs: Dictionary
) -> Result:
	if bank_state == null:
		return Result.fail(&"INVALID_BANK_STATE", "ERR_INVALID_BANK_STATE", {})
	if not ContentId.is_valid(policy_id):
		return Result.fail(&"INVALID_CONTENT_ID", "ERR_INVALID_CONTENT_ID", {"id": policy_id})

	var policy_def: Dictionary = _find_policy_def(policy_id, content_defs)
	if policy_def.is_empty():
		return Result.fail(&"POLICY_NOT_FOUND", "ERR_POLICY_NOT_FOUND", {"policy_id": policy_id})

	if bank_state.adopted_policies.has(policy_id):
		return Result.fail(&"POLICY_ALREADY_ADOPTED", "ERR_POLICY_ALREADY_ADOPTED", {"policy_id": policy_id})

	# Prerequisites check
	var prereqs: Variant = policy_def.get("prerequisites", [])
	var prereq_strs: Array[String] = []
	if prereqs is Array:
		for pre_id in (prereqs as Array):
			var pid_str: String = str(pre_id)
			prereq_strs.append(pid_str)
			if not bank_state.adopted_policies.has(pid_str):
				return Result.fail(
					&"POLICY_PREREQUISITE_MISSING",
					"ERR_POLICY_PREREQUISITE_MISSING",
					{"policy_id": policy_id, "missing_prerequisite": pid_str}
				)
	var transitive_prereqs: Array[String] = _collect_transitive_prereqs(policy_id, content_defs)

	# Mutual exclusion check (exclusive_group + cross-branch guard)
	var grp: String = str(policy_def.get("exclusive_group", ""))
	var target_branch: String = _infer_doctrine_branch(policy_id, policy_def)

	for adopted_id in bank_state.adopted_policies:
		var adopted_def: Dictionary = _find_policy_def(adopted_id, content_defs)
		var adopted_grp: String = str(adopted_def.get("exclusive_group", ""))
		var adopted_branch: String = _infer_doctrine_branch(adopted_id, adopted_def)

		if target_branch != "" and adopted_branch != "" and target_branch != adopted_branch:
			return Result.fail(
				&"POLICY_BRANCH_CONFLICT",
				"ERR_POLICY_BRANCH_CONFLICT",
				{"policy_id": policy_id, "conflicting_policy": adopted_id}
			)

		if grp != "" and adopted_grp == grp:
			var is_same_branch_chain: bool = (
				prereq_strs.has(adopted_id)
				or transitive_prereqs.has(adopted_id)
				or ((grp == "conservative" or grp == "aggressive") and target_branch == adopted_branch)
			)
			if not is_same_branch_chain:
				return Result.fail(
					&"POLICY_EXCLUSIVE_CONFLICT",
					"ERR_POLICY_EXCLUSIVE_CONFLICT",
					{"policy_id": policy_id, "exclusive_group": grp, "conflicting_policy": adopted_id}
				)

	# Optional metric requirements
	var reqs: Variant = BalanceConfig.POLICY_METRIC_REQUIREMENTS.get(policy_id, [])
	if reqs is Array:
		for r in (reqs as Array):
			if r is Dictionary:
				var rd: Dictionary = r as Dictionary
				var metric: String = str(rd.get("metric", ""))
				var threshold: int = int(rd.get("threshold", 0))
				if metric == "reputation" and bank_state.reputation < threshold:
					return Result.fail(&"POLICY_CONDITION_UNMET", "ERR_POLICY_CONDITION_UNMET", {"policy_id": policy_id})

	var cost: int = maxi(0, int(policy_def.get("cost_strategy_points", 0)))
	if bank_state.strategy_points < cost:
		return Result.fail(
			&"INSUFFICIENT_STRATEGY_POINTS",
			"ERR_INSUFFICIENT_STRATEGY_POINTS",
			{"required": cost, "available": bank_state.strategy_points}
		)

	return Result.succeed({
		"policy_id": policy_id,
		"cost_strategy_points": cost,
	})


func adopt_policy(
	bank_state: BankState,
	policy_id: String,
	content_defs: Dictionary
) -> Result:
	var check: Result = can_adopt_policy(bank_state, policy_id, content_defs)
	if not check.ok:
		return check

	var policy_def: Dictionary = _find_policy_def(policy_id, content_defs)
	var cost: int = maxi(0, int(policy_def.get("cost_strategy_points", 0)))
	bank_state.strategy_points -= cost
	bank_state.adopted_policies.append(policy_id)

	var effs: Variant = policy_def.get("effects", [])
	if effs is Array:
		for raw_eff in (effs as Array):
			if not (raw_eff is Dictionary):
				continue
			var eff: Dictionary = raw_eff as Dictionary
			if str(eff.get("target", "")) == "bank.reputation_points":
				var op: String = str(eff.get("operation", ""))
				var val: int = int(eff.get("value", 0))
				if op == "add":
					bank_state.reputation = clampi(bank_state.reputation + val, 0, 100)
				elif op == "set":
					bank_state.reputation = clampi(val, 0, 100)

	return Result.succeed({
		"policy_id": policy_id,
		"cost_strategy_points": cost,
		"strategy_points_remaining": bank_state.strategy_points,
	})
