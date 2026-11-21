class_name CustomerInstance
extends RefCounted

## Pure domain entity representing a lobby customer and patience state machine.

const ALLOWED_TRANSITIONS: Dictionary = {
	Enums.CustomerState.SPAWNING: [
		Enums.CustomerState.FINDING_SERVICE,
		Enums.CustomerState.WAITING,
		Enums.CustomerState.LEAVING,
	],
	Enums.CustomerState.FINDING_SERVICE: [
		Enums.CustomerState.WAITING,
		Enums.CustomerState.IN_SERVICE,
		Enums.CustomerState.LEAVING,
	],
	Enums.CustomerState.WAITING: [
		Enums.CustomerState.IN_SERVICE,
		Enums.CustomerState.LEAVING,
	],
	Enums.CustomerState.IN_SERVICE: [
		Enums.CustomerState.COMPLETED,
		Enums.CustomerState.WAITING,
		Enums.CustomerState.LEAVING,
	],
	Enums.CustomerState.COMPLETED: [
		Enums.CustomerState.LEAVING,
	],
	Enums.CustomerState.LEAVING: [],
}

var id: String = ""
var customer_type: String = "regular"
var avatar_id: String = "cust_regular"
var display_name_key: String = "CUST_TYPE_REGULAR"
var state: int = Enums.CustomerState.SPAWNING
var patience_max: int = 45
var patience_remaining: int = 45
var wait_minutes: int = 0
var credit_profile: Dictionary = {
	"income_minor": 600_000,
	"existing_debt_minor": 50_000,
	"history_score": 70,
	"collateral_value": 0,
	"risk_tag": "normal",
}
var active_request_id: String = ""
var assigned_station_id: String = ""
var grid_pos: Vector2i = Vector2i.ZERO
var target_grid_pos: Vector2i = Vector2i.ZERO
var arrival_day: int = 1
var arrival_minute: int = 540
var approach_minutes_remaining: int = 0
var timed_out: bool = false
var satisfaction_delta: int = 0
var dissatisfaction: int = 0
var browsing_prop_id: String = ""


func can_transition_to(new_state: int) -> bool:
	if new_state < Enums.CustomerState.SPAWNING or new_state > Enums.CustomerState.LEAVING:
		return false
	if new_state == state:
		return true
	var allowed: Array = ALLOWED_TRANSITIONS.get(state, []) as Array
	return allowed.has(new_state)


func transition_to(new_state: int) -> Result:
	if new_state < Enums.CustomerState.SPAWNING or new_state > Enums.CustomerState.LEAVING:
		return Result.fail(
			&"ERR_INVALID_CUSTOMER_STATE",
			"ERR_INVALID_CUSTOMER_STATE",
			{"state": new_state}
		)
	if new_state == state:
		return Result.succeed({"state": state, "changed": false})
	if not can_transition_to(new_state):
		return Result.fail(
			&"ERR_ILLEGAL_CUSTOMER_TRANSITION",
			"ERR_ILLEGAL_CUSTOMER_TRANSITION",
			{"from": state, "to": new_state}
		)
	state = new_state
	return Result.succeed({"state": state, "changed": true})


func tick_patience(delta_minutes: int = 1) -> bool:
	if state != Enums.CustomerState.WAITING and state != Enums.CustomerState.FINDING_SERVICE:
		return false
	var step: int = maxi(0, delta_minutes)
	wait_minutes += step
	patience_remaining = maxi(0, patience_remaining - step)
	if patience_remaining == 0:
		timed_out = true
		return true
	return false


func is_terminal() -> bool:
	return state == Enums.CustomerState.COMPLETED or state == Enums.CustomerState.LEAVING


func to_dict() -> Dictionary:
	return {
		"id": id,
		"customer_type": customer_type,
		"avatar_id": avatar_id,
		"display_name_key": display_name_key,
		"state": state,
		"patience_max": patience_max,
		"patience_remaining": patience_remaining,
		"wait_minutes": wait_minutes,
		"credit_profile": {
			"income_minor": int(credit_profile.get("income_minor", 600_000)),
			"existing_debt_minor": int(credit_profile.get("existing_debt_minor", 50_000)),
			"history_score": int(credit_profile.get("history_score", 70)),
			"collateral_value": int(credit_profile.get("collateral_value", 0)),
			"risk_tag": str(credit_profile.get("risk_tag", "normal")),
		},
		"active_request_id": active_request_id,
		"assigned_station_id": assigned_station_id,
		"grid_pos": [grid_pos.x, grid_pos.y],
		"target_grid_pos": [target_grid_pos.x, target_grid_pos.y],
		"arrival_day": arrival_day,
		"arrival_minute": arrival_minute,
		"approach_minutes_remaining": approach_minutes_remaining,
		"timed_out": timed_out,
		"satisfaction_delta": satisfaction_delta,
		"dissatisfaction": dissatisfaction,
		"browsing_prop_id": browsing_prop_id,
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
	var cust := CustomerInstance.new()
	cust.id = str(data.get("id", ""))
	if cust.id.is_empty():
		return Result.fail(&"INVALID_CUSTOMER_ID", "ERR_INVALID_CUSTOMER_ID", {})
	cust.customer_type = str(data.get("customer_type", "regular"))
	cust.avatar_id = str(data.get("avatar_id", "cust_regular"))
	cust.display_name_key = str(data.get("display_name_key", "CUST_TYPE_REGULAR"))
	cust.state = clampi(
		int(data.get("state", Enums.CustomerState.SPAWNING)),
		Enums.CustomerState.SPAWNING,
		Enums.CustomerState.LEAVING
	)
	cust.patience_max = maxi(1, int(data.get("patience_max", 45)))
	cust.patience_remaining = clampi(int(data.get("patience_remaining", cust.patience_max)), 0, cust.patience_max)
	cust.wait_minutes = maxi(0, int(data.get("wait_minutes", 0)))

	var cp: Variant = data.get("credit_profile", {})
	if cp is Dictionary:
		var cpd: Dictionary = cp as Dictionary
		cust.credit_profile = {
			"income_minor": int(cpd.get("income_minor", 600_000)),
			"existing_debt_minor": int(cpd.get("existing_debt_minor", 50_000)),
			"history_score": int(cpd.get("history_score", 70)),
			"collateral_value": int(cpd.get("collateral_value", 0)),
			"risk_tag": str(cpd.get("risk_tag", "normal")),
		}

	cust.active_request_id = str(data.get("active_request_id", ""))
	cust.assigned_station_id = str(data.get("assigned_station_id", ""))
	cust.grid_pos = _parse_vec2i(data.get("grid_pos", [0, 0]))
	cust.target_grid_pos = _parse_vec2i(data.get("target_grid_pos", [0, 0]))
	cust.arrival_day = maxi(1, int(data.get("arrival_day", 1)))
	cust.arrival_minute = maxi(0, int(data.get("arrival_minute", 540)))
	cust.approach_minutes_remaining = maxi(0, int(data.get("approach_minutes_remaining", 0)))
	cust.timed_out = bool(data.get("timed_out", false))
	cust.satisfaction_delta = int(data.get("satisfaction_delta", 0))
	cust.dissatisfaction = clampi(int(data.get("dissatisfaction", 0)), 0, 100)
	cust.browsing_prop_id = str(data.get("browsing_prop_id", ""))
	return Result.succeed(cust)
