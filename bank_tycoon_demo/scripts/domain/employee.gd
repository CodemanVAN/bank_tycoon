class_name EmployeeInstance
extends RefCounted

## Pure domain entity representing a bank employee or hireable candidate.

const ALLOWED_TRANSITIONS: Dictionary = {
	Enums.EmployeeState.AVAILABLE: [
		Enums.EmployeeState.MOVING,
		Enums.EmployeeState.WORKING,
		Enums.EmployeeState.BREAK,
		Enums.EmployeeState.OFF_DUTY,
	],
	Enums.EmployeeState.MOVING: [
		Enums.EmployeeState.WORKING,
		Enums.EmployeeState.AVAILABLE,
		Enums.EmployeeState.BREAK,
		Enums.EmployeeState.OFF_DUTY,
	],
	Enums.EmployeeState.WORKING: [
		Enums.EmployeeState.AVAILABLE,
		Enums.EmployeeState.OVERLOADED,
		Enums.EmployeeState.BREAK,
		Enums.EmployeeState.OFF_DUTY,
	],
	Enums.EmployeeState.BREAK: [
		Enums.EmployeeState.AVAILABLE,
		Enums.EmployeeState.OFF_DUTY,
	],
	Enums.EmployeeState.OVERLOADED: [
		Enums.EmployeeState.AVAILABLE,
		Enums.EmployeeState.WORKING,
		Enums.EmployeeState.BREAK,
		Enums.EmployeeState.OFF_DUTY,
	],
	Enums.EmployeeState.OFF_DUTY: [
		Enums.EmployeeState.AVAILABLE,
		Enums.EmployeeState.BREAK,
	],
}

var id: String = ""
var name_key: String = ""
var display_name: String = ""
var avatar_id: String = "emp_teller_m"
var role_id: String = "teller"
var department_id: String = ""

var assigned_station_id: String = ""
var current_request_id: String = ""
var grid_pos: Vector2i = Vector2i.ZERO
var target_grid_pos: Vector2i = Vector2i.ZERO

# 7 core attributes (0..100)
var professionalism: int = 50
var efficiency: int = 50
var sociability: int = 50
var risk_awareness: int = 50
var management: int = 40
var loyalty: int = 60
var potential: int = 50

var traits: Array[String] = []
var level: int = 1
var work_xp: int = 0
var fatigue: int = 0
var adaptation_days_remaining: int = 0
var daily_salary_minor: int = 20_000
var training_count: int = 0
var state: int = Enums.EmployeeState.OFF_DUTY


func get_stat_cap() -> int:
	return int(BalanceConfig.EMPLOYEE_LEVEL_STAT_CAPS.get(clampi(level, 1, BalanceConfig.EMPLOYEE_MAX_LEVEL), 65))


func get_xp_required() -> int:
	if level >= BalanceConfig.EMPLOYEE_MAX_LEVEL:
		return 0
	return int(BalanceConfig.EMPLOYEE_PROMOTE_XP_REQUIRED.get(level, 100))


func can_promote() -> bool:
	if level >= BalanceConfig.EMPLOYEE_MAX_LEVEL:
		return false
	return work_xp >= get_xp_required()


func add_experience(xp_amount: int) -> void:
	if level >= BalanceConfig.EMPLOYEE_MAX_LEVEL:
		return
	var req_xp: int = get_xp_required()
	work_xp = clampi(work_xp + maxi(0, xp_amount), 0, req_xp)


func gain_work_experience(xp_amount: int = BalanceConfig.EMPLOYEE_XP_PER_SERVICE) -> Dictionary:
	add_experience(xp_amount)
	var cap: int = get_stat_cap()
	var grew: bool = false
	var at_cap: bool = true
	match role_id:
		"loan_officer":
			if risk_awareness < cap:
				risk_awareness = mini(cap, risk_awareness + 1)
				grew = true
				at_cap = false
			if professionalism < cap:
				professionalism = mini(cap, professionalism + 1)
				grew = true
				at_cap = false
		"lobby_manager":
			if sociability < cap:
				sociability = mini(cap, sociability + 1)
				grew = true
				at_cap = false
			if management < cap:
				management = mini(cap, management + 1)
				grew = true
				at_cap = false
		"analyst", "manager":
			if management < cap:
				management = mini(cap, management + 1)
				grew = true
				at_cap = false
			if risk_awareness < cap:
				risk_awareness = mini(cap, risk_awareness + 1)
				grew = true
				at_cap = false
		_:
			if efficiency < cap:
				efficiency = mini(cap, efficiency + 1)
				grew = true
				at_cap = false
			if professionalism < cap:
				professionalism = mini(cap, professionalism + 1)
				grew = true
				at_cap = false
	return {"grew": grew, "at_cap": at_cap and level < BalanceConfig.EMPLOYEE_MAX_LEVEL, "can_promote": can_promote()}


func can_transition_to(new_state: int) -> bool:
	if new_state < Enums.EmployeeState.AVAILABLE or new_state > Enums.EmployeeState.OFF_DUTY:
		return false
	if new_state == state:
		return true
	var allowed: Array = ALLOWED_TRANSITIONS.get(state, []) as Array
	return allowed.has(new_state)


func transition_to(new_state: int) -> Result:
	if new_state < Enums.EmployeeState.AVAILABLE or new_state > Enums.EmployeeState.OFF_DUTY:
		return Result.fail(
			&"ERR_INVALID_EMPLOYEE_STATE",
			"ERR_INVALID_EMPLOYEE_STATE",
			{"state": new_state}
		)
	if new_state == state:
		return Result.succeed({"state": state, "changed": false})
	if not can_transition_to(new_state):
		return Result.fail(
			&"ERR_ILLEGAL_EMPLOYEE_TRANSITION",
			"ERR_ILLEGAL_EMPLOYEE_TRANSITION",
			{"from": state, "to": new_state}
		)
	state = new_state
	return Result.succeed({"state": state, "changed": true})


func has_active_task() -> bool:
	return current_request_id != "" or state == Enums.EmployeeState.WORKING or state == Enums.EmployeeState.MOVING


func can_accept_task() -> bool:
	return current_request_id == "" and (
		state == Enums.EmployeeState.AVAILABLE or state == Enums.EmployeeState.OVERLOADED
	)


func assign_task(request_id: String, station_pos: Vector2i = Vector2i.ZERO) -> Result:
	if request_id.is_empty():
		return Result.fail(&"ERR_INVALID_REQUEST_ID", "ERR_INVALID_REQUEST_ID", {})
	if current_request_id != "":
		return Result.fail(
			&"ERR_EMPLOYEE_TASK_CONFLICT",
			"ERR_EMPLOYEE_TASK_CONFLICT",
			{"employee_id": id, "current_request_id": current_request_id}
		)
	if state == Enums.EmployeeState.BREAK:
		return Result.fail(&"ERR_EMPLOYEE_ON_BREAK", "ERR_EMPLOYEE_ON_BREAK", {"employee_id": id})
	if state == Enums.EmployeeState.OFF_DUTY:
		return Result.fail(&"ERR_EMPLOYEE_OFF_DUTY", "ERR_EMPLOYEE_OFF_DUTY", {"employee_id": id})
	if state == Enums.EmployeeState.MOVING or state == Enums.EmployeeState.WORKING:
		return Result.fail(&"ERR_EMPLOYEE_BUSY", "ERR_EMPLOYEE_BUSY", {"employee_id": id})

	current_request_id = request_id
	target_grid_pos = station_pos
	var next_state: int = Enums.EmployeeState.MOVING if grid_pos != station_pos else Enums.EmployeeState.WORKING
	if state == Enums.EmployeeState.OVERLOADED and next_state == Enums.EmployeeState.MOVING:
		state = Enums.EmployeeState.AVAILABLE
	var tr: Result = transition_to(next_state)
	if not tr.ok:
		current_request_id = ""
		return tr
	return Result.succeed({"employee_id": id, "request_id": request_id, "state": state})


func complete_current_task() -> void:
	current_request_id = ""
	if state == Enums.EmployeeState.BREAK or state == Enums.EmployeeState.OFF_DUTY:
		return
	if fatigue >= BalanceConfig.OVERLOAD_FATIGUE_THRESHOLD:
		state = Enums.EmployeeState.OVERLOADED
	else:
		state = Enums.EmployeeState.AVAILABLE


func can_assign_to_station() -> Result:
	if state == Enums.EmployeeState.BREAK:
		return Result.fail(&"ERR_EMPLOYEE_ON_BREAK", "ERR_EMPLOYEE_ON_BREAK", {"employee_id": id})
	if has_active_task():
		return Result.fail(&"ERR_EMPLOYEE_BUSY", "ERR_EMPLOYEE_BUSY", {"employee_id": id})
	return Result.succeed({"employee_id": id})


func reassign_station(
	station_id: String,
	new_role_id: String = "",
	adaptation_days: int = BalanceConfig.DEFAULT_ADAPTATION_DAYS
) -> Result:
	if state == Enums.EmployeeState.BREAK:
		return Result.fail(&"ERR_EMPLOYEE_ON_BREAK", "ERR_EMPLOYEE_ON_BREAK", {"employee_id": id})
	var prev_req: String = current_request_id
	var prev_station: String = assigned_station_id
	var prev_role: String = role_id
	current_request_id = ""
	if state == Enums.EmployeeState.WORKING or state == Enums.EmployeeState.MOVING:
		state = Enums.EmployeeState.AVAILABLE
	assigned_station_id = station_id
	if new_role_id != "":
		role_id = new_role_id
	if (prev_station != "" and prev_station != station_id) or (new_role_id != "" and new_role_id != prev_role):
		adaptation_days_remaining = maxi(adaptation_days_remaining, maxi(0, adaptation_days))
	return Result.succeed({
		"employee_id": id,
		"station_id": assigned_station_id,
		"previous_request_id": prev_req,
		"adaptation_days_remaining": adaptation_days_remaining,
	})


func add_fatigue(delta: int) -> void:
	fatigue = clampi(fatigue + delta, 0, 100)
	if fatigue >= BalanceConfig.OVERLOAD_FATIGUE_THRESHOLD and state == Enums.EmployeeState.WORKING:
		state = Enums.EmployeeState.OVERLOADED


func recover_fatigue(delta: int) -> void:
	fatigue = clampi(fatigue - maxi(0, delta), 0, 100)
	if fatigue < BalanceConfig.OVERLOAD_FATIGUE_THRESHOLD and state == Enums.EmployeeState.OVERLOADED:
		state = Enums.EmployeeState.AVAILABLE


func tick_adaptation_day() -> void:
	adaptation_days_remaining = maxi(0, adaptation_days_remaining - 1)


func get_trait_bonuses(content_defs: Dictionary = {}) -> Dictionary:
	var bonuses: Dictionary = {
		"professionalism": 0,
		"efficiency": 0,
		"sociability": 0,
		"risk_awareness": 0,
		"management": 0,
		"loyalty": 0,
		"potential": 0,
	}
	if traits.is_empty():
		return bonuses
	var raw_traits: Variant = content_defs.get("traits", [])
	if not (raw_traits is Array):
		return bonuses
	for tid: String in traits:
		for raw_t: Variant in (raw_traits as Array):
			if raw_t is Dictionary and str((raw_t as Dictionary).get("id", "")) == tid:
				var ab: Variant = (raw_t as Dictionary).get("attribute_bonuses", {})
				if ab is Dictionary:
					for k: Variant in (ab as Dictionary).keys():
						var sk: String = str(k)
						if bonuses.has(sk):
							bonuses[sk] = int(bonuses[sk]) + int((ab as Dictionary)[k])
				break
	return bonuses


func get_effective_attributes(content_defs: Dictionary = {}) -> Dictionary:
	# Base stats are bounded by level cap; exclusive trait bonuses bypass the level cap (both + and -)
	var cap: int = get_stat_cap()
	var b: Dictionary = get_trait_bonuses(content_defs)
	return {
		"professionalism": clampi(mini(professionalism, cap) + int(b["professionalism"]), 0, 120),
		"efficiency": clampi(mini(efficiency, cap) + int(b["efficiency"]), 0, 120),
		"sociability": clampi(mini(sociability, cap) + int(b["sociability"]), 0, 120),
		"risk_awareness": clampi(mini(risk_awareness, cap) + int(b["risk_awareness"]), 0, 120),
		"management": clampi(mini(management, cap) + int(b["management"]), 0, 120),
		"loyalty": clampi(mini(loyalty, cap) + int(b["loyalty"]), 0, 120),
		"potential": clampi(potential + int(b["potential"]), 0, 120),
		"bonuses": b,
		"cap": cap,
	}


func get_effective_productivity_bps(content_defs: Dictionary = {}) -> int:
	# Baseline 10000 bps (1.0x), scaled by effective efficiency & professionalism (including traits), penalized by fatigue & adaptation
	var eff_attrs: Dictionary = get_effective_attributes(content_defs)
	var eff_v: int = int(eff_attrs["efficiency"])
	var prof_v: int = int(eff_attrs["professionalism"])
	var base_bps: int = 7500 + (eff_v * 30) + (prof_v * 20)
	if adaptation_days_remaining > 0:
		base_bps -= 2500
	if fatigue >= BalanceConfig.OVERLOAD_FATIGUE_THRESHOLD:
		base_bps -= 2000
	elif fatigue >= 50:
		base_bps -= 800
	return clampi(base_bps, 2500, 30000)


func to_dict() -> Dictionary:
	var traits_copy: Array[String] = []
	for t in traits:
		traits_copy.append(t)
	return {
		"id": id,
		"name_key": name_key,
		"display_name": display_name,
		"avatar_id": avatar_id,
		"role_id": role_id,
		"department_id": department_id,
		"assigned_station_id": assigned_station_id,
		"current_request_id": current_request_id,
		"grid_pos": [grid_pos.x, grid_pos.y],
		"target_grid_pos": [target_grid_pos.x, target_grid_pos.y],
		"professionalism": professionalism,
		"efficiency": efficiency,
		"sociability": sociability,
		"risk_awareness": risk_awareness,
		"management": management,
		"loyalty": loyalty,
		"potential": potential,
		"traits": traits_copy,
		"level": level,
		"work_xp": work_xp,
		"fatigue": fatigue,
		"adaptation_days_remaining": adaptation_days_remaining,
		"daily_salary_minor": daily_salary_minor,
		"training_count": training_count,
		"state": state,
	}


static func _parse_vec2i(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw as Vector2i
	if raw is Array and (raw as Array).size() >= 2:
		var arr: Array = raw as Array
		return Vector2i(int(arr[0]), int(arr[1]))
	if raw is Dictionary:
		var d: Dictionary = raw as Dictionary
		return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
	return Vector2i.ZERO


static func from_dict(data: Dictionary) -> Result:
	var emp := EmployeeInstance.new()
	emp.id = str(data.get("id", ""))
	if emp.id.is_empty():
		return Result.fail(&"INVALID_EMPLOYEE_ID", "ERR_INVALID_EMPLOYEE_ID", {})
	emp.name_key = str(data.get("name_key", ""))
	emp.display_name = str(data.get("display_name", emp.id))
	emp.avatar_id = str(data.get("avatar_id", "emp_teller_m"))
	emp.role_id = str(data.get("role_id", "teller"))
	emp.department_id = str(data.get("department_id", ""))
	emp.assigned_station_id = str(data.get("assigned_station_id", ""))
	emp.current_request_id = str(data.get("current_request_id", ""))
	emp.grid_pos = _parse_vec2i(data.get("grid_pos", [0, 0]))
	emp.target_grid_pos = _parse_vec2i(data.get("target_grid_pos", [0, 0]))
	emp.professionalism = clampi(int(data.get("professionalism", 50)), 0, 100)
	emp.efficiency = clampi(int(data.get("efficiency", 50)), 0, 100)
	emp.sociability = clampi(int(data.get("sociability", 50)), 0, 100)
	emp.risk_awareness = clampi(int(data.get("risk_awareness", 50)), 0, 100)
	emp.management = clampi(int(data.get("management", 40)), 0, 100)
	emp.loyalty = clampi(int(data.get("loyalty", 60)), 0, 100)
	emp.potential = clampi(int(data.get("potential", 50)), 0, 100)

	emp.traits = []
	var raw_traits: Variant = data.get("traits", [])
	if raw_traits is Array:
		for t in (raw_traits as Array):
			emp.traits.append(str(t))

	emp.level = clampi(int(data.get("level", 1)), 1, BalanceConfig.EMPLOYEE_MAX_LEVEL)
	emp.work_xp = maxi(0, int(data.get("work_xp", 0)))
	emp.fatigue = clampi(int(data.get("fatigue", 0)), 0, 100)
	emp.adaptation_days_remaining = maxi(0, int(data.get("adaptation_days_remaining", 0)))
	emp.daily_salary_minor = maxi(0, int(data.get("daily_salary_minor", 20_000)))
	emp.training_count = maxi(0, int(data.get("training_count", 0)))
	emp.state = clampi(
		int(data.get("state", Enums.EmployeeState.OFF_DUTY)),
		Enums.EmployeeState.AVAILABLE,
		Enums.EmployeeState.OFF_DUTY
	)
	return Result.succeed(emp)
