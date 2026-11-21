class_name EmployeeDispatcher
extends RefCounted

## Deterministic queue prioritization and station-employee service pairing.


func dispatch(
	bank_state: BankState,
	event_bus: DomainEventBus = null,
	dept_service: DepartmentService = null
) -> int:
	if bank_state == null:
		return 0
	if bank_state.service_requests.is_empty() or bank_state.stations.is_empty() or bank_state.employees.is_empty():
		return 0

	var ds: DepartmentService = dept_service if dept_service != null else DepartmentService.new()
	var auto_priority: bool = ds.is_capability_unlocked(bank_state, "auto_queue_priority")

	if auto_priority:
		for req in bank_state.service_requests:
			if req != null and req.status == Enums.RequestStatus.QUEUED and req.priority == Enums.QueuePriority.NORMAL:
				var cust_v: Variant = bank_state.active_customers.get(req.customer_id, null)
				var ctype: String = (cust_v as CustomerInstance).customer_type if cust_v is CustomerInstance else ""
				var amt: int = int(req.payload.get("amount_minor", req.payload.get("principal_minor", 0)))
				if ctype == "vip":
					req.priority = Enums.QueuePriority.VIP
				elif ctype == "smb" or amt >= 250_000:
					req.priority = Enums.QueuePriority.PRIORITY

	bank_state.service_requests.sort_custom(ServiceRequest.compare_queue_order)

	# Identify busy stations
	var busy_stations: Dictionary = {}
	for req in bank_state.service_requests:
		if req == null:
			continue
		if (
			req.status == Enums.RequestStatus.IN_PROGRESS
			or req.status == Enums.RequestStatus.ASSIGNED
		) and req.assigned_station_id != "":
			busy_stations[req.assigned_station_id] = true

	var station_ids: Array[String] = []
	for sid: Variant in bank_state.stations.keys():
		station_ids.append(str(sid))
	station_ids.sort()

	var emp_ids: Array[String] = []
	for eid: Variant in bank_state.employees.keys():
		emp_ids.append(str(eid))
	emp_ids.sort()

	var dispatched_count: int = 0

	for req in bank_state.service_requests:
		if req == null or req.status != Enums.RequestStatus.QUEUED:
			continue

		var srv_str: String = String(req.service_type)
		var req_skill: String = String(req.required_skill)

		var chosen_station_id: String = ""
		var chosen_emp: EmployeeInstance = null
		var best_score: int = -999999

		for st_id in station_ids:
			if busy_stations.has(st_id):
				continue
			var st_v: Variant = bank_state.stations.get(st_id, null)
			if not (st_v is Dictionary):
				continue
			var st: Dictionary = st_v as Dictionary
			if not bool(st.get("is_open", false)):
				continue

			var allowed: Variant = st.get("allowed_services", [])
			if allowed is Array and not (allowed as Array).is_empty():
				if not (allowed as Array).has(srv_str):
					continue

			var assigned_eid: String = str(st.get("assigned_employee_id", ""))
			if assigned_eid != "":
				var emp_v: Variant = bank_state.employees.get(assigned_eid, null)
				if emp_v is EmployeeInstance:
					var emp: EmployeeInstance = emp_v as EmployeeInstance
					if emp.can_accept_task():
						var score: int = 1000 + emp.get_effective_productivity_bps() / 100
						if emp.role_id == req_skill:
							score += 500
						if score > best_score:
							best_score = score
							chosen_station_id = st_id
							chosen_emp = emp
			else:
				# Unassigned open station: find best available unassigned employee
				for eid in emp_ids:
					var emp_v2: Variant = bank_state.employees.get(eid, null)
					if not (emp_v2 is EmployeeInstance):
						continue
					var emp2: EmployeeInstance = emp_v2 as EmployeeInstance
					if not emp2.can_accept_task():
						continue
					if emp2.assigned_station_id != "" and emp2.assigned_station_id != st_id:
						continue
					var score2: int = emp2.get_effective_productivity_bps() / 100
					if emp2.role_id == req_skill:
						score2 += 500
					if score2 > best_score:
						best_score = score2
						chosen_station_id = st_id
						chosen_emp = emp2

		if chosen_station_id != "" and chosen_emp != null:
			var st_dict: Dictionary = bank_state.stations[chosen_station_id] as Dictionary
			var st_pos_v: Variant = st_dict.get("grid_pos", Vector2i.ZERO)
			var st_pos: Vector2i = st_pos_v as Vector2i if st_pos_v is Vector2i else Vector2i.ZERO

			var assign_req_res: Result = req.assign(chosen_emp.id, chosen_station_id)
			if not assign_req_res.ok:
				continue
			req.status = Enums.RequestStatus.IN_PROGRESS

			var assign_emp_res: Result = chosen_emp.assign_task(req.request_id, st_pos)
			if not assign_emp_res.ok:
				req.release_to_queue()
				continue
			chosen_emp.grid_pos = st_pos
			chosen_emp.transition_to(Enums.EmployeeState.WORKING)

			busy_stations[chosen_station_id] = true
			dispatched_count += 1

			var cust_v: Variant = bank_state.active_customers.get(req.customer_id, null)
			if cust_v is CustomerInstance:
				var cust: CustomerInstance = cust_v as CustomerInstance
				cust.assigned_station_id = chosen_station_id
				cust.target_grid_pos = st_pos
				cust.grid_pos = st_pos + Vector2i(0, 1)
				cust.transition_to(Enums.CustomerState.IN_SERVICE)

			if event_bus != null:
				event_bus.publish(
					&"ServiceStarted",
					{
						"request_id": req.request_id,
						"customer_id": req.customer_id,
						"employee_id": chosen_emp.id,
						"station_id": chosen_station_id,
						"service_type": srv_str,
					},
					bank_state.current_day,
					bank_state.current_minute_of_day
				)

	return dispatched_count
