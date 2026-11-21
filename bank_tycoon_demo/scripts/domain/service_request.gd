class_name ServiceRequest
extends RefCounted

## Pure domain entity representing a queued or active customer service request.

var request_id: String = ""
var customer_id: String = ""
var service_type: StringName = &"cash_deposit"
var priority: int = Enums.QueuePriority.NORMAL
var required_skill: StringName = &"teller"
var estimated_work_minutes: int = 6
var remaining_work_units: int = 600
var risk_level: int = 0
var created_at_day: int = 1
var created_at_minute: int = 540
var deadline_minute: int = 600
var status: int = Enums.RequestStatus.QUEUED
var assigned_employee_id: String = ""
var assigned_station_id: String = ""
var payload: Dictionary = {}


func is_queued() -> bool:
	return status == Enums.RequestStatus.QUEUED


func is_terminal() -> bool:
	return (
		status == Enums.RequestStatus.COMPLETED
		or status == Enums.RequestStatus.CANCELLED
		or status == Enums.RequestStatus.TIMED_OUT
	)


func assign(employee_id: String, station_id: String) -> Result:
	if status != Enums.RequestStatus.QUEUED:
		return Result.fail(
			&"ERR_REQUEST_NOT_QUEUED",
			"ERR_REQUEST_NOT_QUEUED",
			{"request_id": request_id, "status": status}
		)
	if assigned_employee_id != "":
		return Result.fail(
			&"ERR_REQUEST_ALREADY_ASSIGNED",
			"ERR_REQUEST_ALREADY_ASSIGNED",
			{"request_id": request_id, "employee_id": assigned_employee_id}
		)
	assigned_employee_id = employee_id
	assigned_station_id = station_id
	status = Enums.RequestStatus.ASSIGNED
	return Result.succeed({"request_id": request_id, "employee_id": employee_id, "station_id": station_id})


func release_to_queue() -> void:
	if is_terminal():
		return
	assigned_employee_id = ""
	assigned_station_id = ""
	status = Enums.RequestStatus.QUEUED


func set_priority(new_priority: int) -> Result:
	if new_priority < Enums.QueuePriority.NORMAL or new_priority > Enums.QueuePriority.VIP:
		return Result.fail(
			&"ERR_INVALID_QUEUE_PRIORITY",
			"ERR_INVALID_QUEUE_PRIORITY",
			{"priority": new_priority}
		)
	priority = new_priority
	return Result.succeed({"request_id": request_id, "priority": priority})


func advance_work(work_units: int) -> bool:
	if work_units > 0:
		remaining_work_units = maxi(0, remaining_work_units - work_units)
	return remaining_work_units <= 0


static func compare_queue_order(a: ServiceRequest, b: ServiceRequest) -> bool:
	if a.priority != b.priority:
		return a.priority > b.priority
	if a.created_at_day != b.created_at_day:
		return a.created_at_day < b.created_at_day
	if a.created_at_minute != b.created_at_minute:
		return a.created_at_minute < b.created_at_minute
	return a.request_id < b.request_id


func to_dict() -> Dictionary:
	return {
		"request_id": request_id,
		"customer_id": customer_id,
		"service_type": String(service_type),
		"priority": priority,
		"required_skill": String(required_skill),
		"estimated_work_minutes": estimated_work_minutes,
		"remaining_work_units": remaining_work_units,
		"risk_level": risk_level,
		"created_at_day": created_at_day,
		"created_at_minute": created_at_minute,
		"deadline_minute": deadline_minute,
		"status": status,
		"assigned_employee_id": assigned_employee_id,
		"assigned_station_id": assigned_station_id,
		"payload": payload.duplicate(true),
	}


static func from_dict(data: Dictionary) -> Result:
	var req := ServiceRequest.new()
	req.request_id = str(data.get("request_id", ""))
	if req.request_id.is_empty():
		return Result.fail(&"INVALID_REQUEST_ID", "ERR_INVALID_REQUEST_ID", {})
	req.customer_id = str(data.get("customer_id", ""))
	req.service_type = StringName(str(data.get("service_type", "cash_deposit")))
	req.priority = clampi(int(data.get("priority", 0)), Enums.QueuePriority.NORMAL, Enums.QueuePriority.VIP)
	req.required_skill = StringName(str(data.get("required_skill", "teller")))
	req.estimated_work_minutes = maxi(1, int(data.get("estimated_work_minutes", 6)))
	req.remaining_work_units = maxi(0, int(data.get("remaining_work_units", req.estimated_work_minutes * 100)))
	req.risk_level = maxi(0, int(data.get("risk_level", 0)))
	req.created_at_day = maxi(1, int(data.get("created_at_day", 1)))
	req.created_at_minute = maxi(0, int(data.get("created_at_minute", 540)))
	req.deadline_minute = maxi(0, int(data.get("deadline_minute", 600)))
	req.status = clampi(
		int(data.get("status", Enums.RequestStatus.QUEUED)),
		Enums.RequestStatus.QUEUED,
		Enums.RequestStatus.PENDING_APPROVAL
	)
	req.assigned_employee_id = str(data.get("assigned_employee_id", ""))
	req.assigned_station_id = str(data.get("assigned_station_id", ""))

	var raw_payload: Variant = data.get("payload", {})
	var clean_payload: Dictionary = {}
	if raw_payload is Dictionary:
		for pk: Variant in (raw_payload as Dictionary).keys():
			var pv: Variant = (raw_payload as Dictionary)[pk]
			if pv is float and is_equal_approx(float(pv), float(int(pv))):
				clean_payload[str(pk)] = int(pv)
			else:
				clean_payload[str(pk)] = pv
	req.payload = clean_payload
	return Result.succeed(req)
