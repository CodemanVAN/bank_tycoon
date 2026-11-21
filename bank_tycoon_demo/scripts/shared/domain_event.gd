class_name DomainEvent
extends RefCounted

## Typed domain event record for decoupled simulation and telemetry.

const EVT_CUSTOMER_ARRIVED: StringName = &"CustomerArrived"
const EVT_SERVICE_STARTED: StringName = &"ServiceStarted"
const EVT_SERVICE_COMPLETED: StringName = &"ServiceCompleted"
const EVT_CUSTOMER_LEFT_UNSERVED: StringName = &"CustomerLeftUnserved"
const EVT_LOAN_APPROVAL_REQUESTED: StringName = &"LoanApprovalRequested"
const EVT_LOAN_APPROVED: StringName = &"LoanApproved"
const EVT_LOAN_REJECTED: StringName = &"LoanRejected"
const EVT_LOAN_DEFAULTED: StringName = &"LoanDefaulted"
const EVT_DEPARTMENT_CREATED: StringName = &"DepartmentCreated"
const EVT_DEPARTMENT_UPGRADED: StringName = &"DepartmentUpgraded"
const EVT_POLICY_ADOPTED: StringName = &"PolicyAdopted"
const EVT_EMPLOYEE_HIRED: StringName = &"EmployeeHired"
const EVT_EMPLOYEE_FIRED: StringName = &"EmployeeFired"
const EVT_EMPLOYEE_TRAINED: StringName = &"EmployeeTrained"
const EVT_EMPLOYEE_RESTED: StringName = &"EmployeeRested"
const EVT_EMPLOYEE_RESIGNED: StringName = &"EmployeeResigned"
const EVT_DAILY_SETTLEMENT_COMPLETED: StringName = &"DailySettlementCompleted"
const EVT_EVENT_TRIGGERED: StringName = &"EventTriggered"
const EVT_EVENT_RESOLVED: StringName = &"EventResolved"
const EVT_LIQUIDITY_WARNING: StringName = &"LiquidityWarning"
const EVT_BRANCH_OPENED: StringName = &"BranchOpened"
const EVT_RATES_CHANGED: StringName = &"RatesChanged"

var event_type: StringName = &""
var day: int = 1
var minute: int = 0
var payload: Dictionary = {}


func _init(
	p_event_type: StringName = &"",
	p_day: int = 1,
	p_minute: int = 0,
	p_payload: Dictionary = {}
) -> void:
	event_type = p_event_type
	day = p_day
	minute = p_minute
	payload = p_payload.duplicate(true)


func to_dict() -> Dictionary:
	return {
		"event_type": String(event_type),
		"day": day,
		"minute": minute,
		"payload": payload.duplicate(true),
	}


static func from_dict(data: Dictionary) -> DomainEvent:
	var ev_type: StringName = StringName(str(data.get("event_type", "")))
	var d: int = int(data.get("day", 1))
	var m: int = int(data.get("minute", 0))
	var p: Variant = data.get("payload", {})
	var p_dict: Dictionary = (p as Dictionary).duplicate(true) if p is Dictionary else {}
	return DomainEvent.new(ev_type, d, m, p_dict)
