class_name DomainEventBus
extends RefCounted

## Decoupled domain event bus supporting both typed DomainEvent and UI event_published signals.

signal domain_event_emitted(ev: DomainEvent)
signal event_published(event_type: StringName, payload: Dictionary)

const MAX_RECENT_LOG: int = 50

const PASCAL_TO_SNAKE: Dictionary = {
	"MinuteTicked": &"minute_ticked",
	"DayStarted": &"day_started",
	"DayPhaseChanged": &"day_phase_changed",
	"CustomerArrived": &"customer_arrived",
	"ServiceStarted": &"service_started",
	"ServiceCompleted": &"service_completed",
	"CustomerLeftUnserved": &"customer_left_unserved",
	"LoanApprovalRequested": &"loan_approval_requested",
	"LoanApproved": &"loan_approved",
	"LoanRejected": &"loan_rejected",
	"LoanDefaulted": &"loan_defaulted",
	"EmployeeHired": &"employee_hired",
	"EmployeeFired": &"employee_fired",
	"EmployeeAssigned": &"employee_assigned",
	"EmployeeTrained": &"employee_trained",
	"EmployeeRested": &"employee_rested",
	"EmployeeResigned": &"employee_resigned",
	"StationToggled": &"station_toggled",
	"DepartmentCreated": &"department_created",
	"DepartmentUpgraded": &"department_upgraded",
	"PolicyAdopted": &"policy_adopted",
	"EventTriggered": &"event_triggered",
	"EventResolved": &"event_resolved",
	"DailySettlementCompleted": &"daily_settlement_completed",
	"SpeedChanged": &"speed_changed",
	"RatesChanged": &"rates_changed",
	"LiquidityWarning": &"liquidity_warning",
	"BranchOpened": &"day_started",
	"Alert": &"alert",
	"StateReloaded": &"state_reloaded",
}

const SNAKE_TO_PASCAL: Dictionary = {
	"minute_ticked": &"MinuteTicked",
	"day_started": &"DayStarted",
	"day_phase_changed": &"DayPhaseChanged",
	"customer_arrived": &"CustomerArrived",
	"service_started": &"ServiceStarted",
	"service_completed": &"ServiceCompleted",
	"customer_left_unserved": &"CustomerLeftUnserved",
	"loan_approval_requested": &"LoanApprovalRequested",
	"loan_approved": &"LoanApproved",
	"loan_rejected": &"LoanRejected",
	"loan_defaulted": &"LoanDefaulted",
	"employee_hired": &"EmployeeHired",
	"employee_fired": &"EmployeeFired",
	"employee_assigned": &"EmployeeAssigned",
	"employee_trained": &"EmployeeTrained",
	"employee_rested": &"EmployeeRested",
	"employee_resigned": &"EmployeeResigned",
	"station_toggled": &"StationToggled",
	"department_created": &"DepartmentCreated",
	"department_upgraded": &"DepartmentUpgraded",
	"policy_adopted": &"PolicyAdopted",
	"event_triggered": &"EventTriggered",
	"event_resolved": &"EventResolved",
	"daily_settlement_completed": &"DailySettlementCompleted",
	"speed_changed": &"SpeedChanged",
	"rates_changed": &"RatesChanged",
	"liquidity_warning": &"LiquidityWarning",
	"alert": &"Alert",
	"state_reloaded": &"StateReloaded",
}

const LOG_KEY_BY_SNAKE: Dictionary = {
	"day_started": "SIM_LOG_DAY_STARTED",
	"day_phase_changed": "SIM_LOG_PHASE_CHANGED",
	"customer_arrived": "SIM_LOG_CUSTOMER_ARRIVED",
	"service_started": "SIM_LOG_SERVICE_STARTED",
	"service_completed": "SIM_LOG_SERVICE_COMPLETED",
	"customer_left_unserved": "SIM_LOG_CUSTOMER_LEFT_UNSERVED",
	"loan_approval_requested": "SIM_LOG_LOAN_APPROVAL_REQUESTED",
	"loan_approved": "SIM_LOG_LOAN_APPROVED",
	"loan_rejected": "SIM_LOG_LOAN_REJECTED",
	"employee_hired": "SIM_LOG_EMPLOYEE_HIRED",
	"employee_fired": "SIM_LOG_EMPLOYEE_FIRED",
	"employee_assigned": "SIM_LOG_EMPLOYEE_ASSIGNED",
	"employee_trained": "SIM_LOG_EMPLOYEE_TRAINED",
	"employee_rested": "SIM_LOG_EMPLOYEE_RESTED",
	"station_toggled": "SIM_LOG_STATION_TOGGLED",
	"department_created": "SIM_LOG_DEPARTMENT_CREATED",
	"department_upgraded": "SIM_LOG_DEPARTMENT_UPGRADED",
	"policy_adopted": "SIM_LOG_POLICY_ADOPTED",
	"event_triggered": "SIM_LOG_EVENT_TRIGGERED",
	"event_resolved": "SIM_LOG_EVENT_RESOLVED",
	"daily_settlement_completed": "SIM_LOG_DAILY_SETTLEMENT",
	"speed_changed": "SIM_LOG_SPEED_CHANGED",
	"rates_changed": "SIM_LOG_RATES_CHANGED",
	"alert": "SIM_LOG_ALERT",
	"state_reloaded": "SIM_LOG_STATE_RELOADED",
}

var recent_log: Array[Dictionary] = []
var current_day: int = 1
var current_minute: int = BalanceConfig.BUSINESS_OPEN_MINUTE


static func to_pascal_event_type(raw_type: StringName) -> StringName:
	var s: String = String(raw_type)
	if SNAKE_TO_PASCAL.has(s):
		return SNAKE_TO_PASCAL[s] as StringName
	if PASCAL_TO_SNAKE.has(s):
		return raw_type
	return raw_type


static func to_snake_event_type(raw_type: StringName) -> StringName:
	var s: String = String(raw_type)
	if PASCAL_TO_SNAKE.has(s):
		return PASCAL_TO_SNAKE[s] as StringName
	if SNAKE_TO_PASCAL.has(s):
		return raw_type
	return StringName(s.to_snake_case())


func publish(
	event_type: StringName,
	payload: Dictionary = {},
	day: int = -1,
	minute: int = -1
) -> DomainEvent:
	var eff_day: int = day if day > 0 else int(payload.get("day", current_day))
	var eff_min: int = minute if minute >= 0 else int(payload.get("minute", current_minute))
	current_day = eff_day
	current_minute = eff_min

	var pascal_type: StringName = to_pascal_event_type(event_type)
	var snake_type: StringName = to_snake_event_type(event_type)
	var clean_payload: Dictionary = payload.duplicate(true)

	var ev := DomainEvent.new(pascal_type, eff_day, eff_min, clean_payload)

	if snake_type != &"minute_ticked":
		var snake_str: String = String(snake_type)
		var log_key: String = str(clean_payload.get("key", LOG_KEY_BY_SNAKE.get(snake_str, "SIM_LOG_EVENT")))
		var log_params: Dictionary = {}
		var raw_params: Variant = clean_payload.get("params", null)
		if raw_params is Dictionary:
			log_params = (raw_params as Dictionary).duplicate(true)
		else:
			for k: Variant in clean_payload.keys():
				var kv: Variant = clean_payload[k]
				if not (kv is Dictionary or kv is Array or kv is Object):
					log_params[str(k)] = kv
		log_params["day"] = eff_day
		log_params["minute"] = eff_min
		log_params["time"] = FormatService.format_time(eff_min)

		recent_log.append({
			"type": snake_str,
			"event_type": String(pascal_type),
			"day": eff_day,
			"minute": eff_min,
			"key": log_key,
			"params": log_params,
			"payload": clean_payload,
		})
		while recent_log.size() > MAX_RECENT_LOG:
			recent_log.pop_front()

	domain_event_emitted.emit(ev)
	event_published.emit(snake_type, clean_payload)
	return ev


func clear_log() -> void:
	recent_log.clear()
