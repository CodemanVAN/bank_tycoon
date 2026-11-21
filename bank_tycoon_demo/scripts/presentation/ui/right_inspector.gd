extends PanelContainer

## Starway Bank Right Live Inspector:
## Uses an in-place pooled Label/Button layout so rapid synchronous refreshes
## (e.g. locale switching or multi-day batch simulation) never allocate or free
## Container nodes mid-frame.

signal command_executed(res: Variant, action_key: String)
signal loan_modal_requested()
signal event_modal_requested()

const LABEL_POOL_SIZE: int = 24
const BUTTON_POOL_SIZE: int = 18

var _sim_host: Node = null
var _selected_type: StringName = &""
var _selected_id: String = ""

var _lbl_header: Label = null
var _btn_back: Button = null
var _portrait: TextureRect = null
var _content_box: VBoxContainer = null

var _label_pool: Array[Label] = []
var _button_pool: Array[Button] = []
var _button_actions: Array[Callable] = []
var _used_labels: int = 0
var _used_buttons: int = 0


func _ready() -> void:
	_build_ui()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func bind(p_sim_host: Node) -> void:
	_sim_host = p_sim_host
	if _lbl_header != null:
		refresh()


func show_entity(entity_type: StringName, entity_id: String) -> void:
	_selected_type = entity_type
	_selected_id = entity_id
	refresh()


func clear_selection() -> void:
	_selected_type = &""
	_selected_id = ""
	refresh()


func _on_locale_changed(_new_locale: String) -> void:
	refresh()


func _build_ui() -> void:
	if _lbl_header != null:
		return
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 8)
	add_child(root_v)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	root_v.add_child(top_row)

	_lbl_header = Label.new()
	_lbl_header.theme_type_variation = &"LabelTitle"
	_lbl_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_lbl_header)

	_btn_back = Button.new()
	_btn_back.visible = false
	_btn_back.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		clear_selection()
	)
	top_row.add_child(_btn_back)

	root_v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	_content_box = VBoxContainer.new()
	_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_content_box)

	_portrait = TextureRect.new()
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.custom_minimum_size = Vector2(40, 40)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.visible = false
	_content_box.add_child(_portrait)

	for i in range(LABEL_POOL_SIZE):
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.visible = false
		_content_box.add_child(l)
		_label_pool.append(l)

	for i in range(BUTTON_POOL_SIZE):
		var b := Button.new()
		b.visible = false
		var idx_copy: int = i
		_button_actions.append(Callable())
		b.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			if idx_copy < _button_actions.size() and _button_actions[idx_copy].is_valid():
				_button_actions[idx_copy].call()
		)
		_content_box.add_child(b)
		_button_pool.append(b)


func _reset_pool() -> void:
	_used_labels = 0
	_used_buttons = 0
	if _portrait != null:
		_portrait.visible = false
	for l in _label_pool:
		l.visible = false
		l.text = ""
	for i in range(_button_pool.size()):
		_button_pool[i].visible = false
		_button_pool[i].text = ""
		_button_actions[i] = Callable()


func _push_label(txt: String, variation: StringName = &"") -> Label:
	if _used_labels >= _label_pool.size():
		return null
	var l: Label = _label_pool[_used_labels]
	_used_labels += 1
	l.theme_type_variation = variation
	l.text = txt
	l.visible = true
	return l


func _push_button(txt: String, action: Callable, variation: StringName = &"") -> Button:
	if _used_buttons >= _button_pool.size():
		return null
	var idx: int = _used_buttons
	_used_buttons += 1
	var b: Button = _button_pool[idx]
	b.theme_type_variation = variation
	b.text = txt
	b.visible = true
	_button_actions[idx] = action
	return b


func refresh() -> void:
	if _lbl_header == null or _content_box == null:
		return
	_reset_pool()

	_btn_back.text = UiI18n.tr_key("UI_INSPECTOR_BTN_BACK_OVERVIEW")
	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null

	if _selected_type == &"station" and bs != null and bs.stations.has(_selected_id):
		_lbl_header.text = UiI18n.tr_key("UI_INSPECTOR_TITLE_STATION")
		_btn_back.visible = true
		_build_station_view(bs, _selected_id)
	elif _selected_type == &"employee" and bs != null and bs.employees.has(_selected_id):
		_lbl_header.text = UiI18n.tr_key("UI_INSPECTOR_TITLE_EMPLOYEE")
		_btn_back.visible = true
		_build_employee_view(bs, _selected_id)
	elif _selected_type == &"customer" and bs != null and bs.active_customers.has(_selected_id):
		_lbl_header.text = UiI18n.tr_key("UI_INSPECTOR_TITLE_CUSTOMER")
		_btn_back.visible = true
		_build_customer_view(bs, _selected_id)
	else:
		_lbl_header.text = UiI18n.tr_key("UI_INSPECTOR_TITLE_OVERVIEW")
		_btn_back.visible = false
		_build_overview_view(bs)


func _build_overview_view(bs: BankState) -> void:
	var snap: Dictionary = {}
	if _sim_host != null and _sim_host.has_method("get_snapshot"):
		snap = _sim_host.call("get_snapshot") as Dictionary

	var liq_status: int = int(snap.get("liquidity_status", Enums.LiquidityStatus.SAFE))
	_push_label("%s: %s" % [UiI18n.tr_key("UI_INSPECTOR_LIQUIDITY"), UiI18n.tr_liquidity_status(liq_status)])

	var npl_bps: int = int(snap.get("npl_ratio_bps", 0))
	_push_label("%s: %s" % [UiI18n.tr_key("UI_INSPECTOR_NPL"), FormatService.format_bps(npl_bps)])

	_push_label(UiI18n.tr_key("UI_INSPECTOR_ALERTS_HEADER"), &"LabelTitle")
	var pending_loans: int = bs.pending_loan_approvals.size() if bs != null else 0
	_push_button(
		UiI18n.tr_key("UI_INSPECTOR_PENDING_LOANS", {"count": pending_loans}),
		func() -> void: loan_modal_requested.emit()
	)
	var active_evs: int = bs.active_events.size() if bs != null else 0
	_push_button(
		UiI18n.tr_key("UI_INSPECTOR_ACTIVE_EVENTS", {"count": active_evs}),
		func() -> void: event_modal_requested.emit()
	)

	_push_label(UiI18n.tr_key("UI_INSPECTOR_STATIONS_HEADER"), &"LabelTitle")
	if bs != null:
		var st_ids: Array[String] = []
		for sid: Variant in bs.stations.keys():
			st_ids.append(str(sid))
		st_ids.sort()
		for sid in st_ids:
			var st: Dictionary = bs.stations[sid] as Dictionary
			var is_open: bool = bool(st.get("is_open", true))
			_push_label("%s (%s)" % [sid, UiI18n.tr_key("UI_INSPECTOR_STATION_OPEN" if is_open else "UI_INSPECTOR_STATION_CLOSED")])
			var target_sid: String = sid
			_push_button(
				"%s [%s]" % [UiI18n.tr_key("UI_INSPECTOR_BTN_TOGGLE_STATION"), sid],
				func() -> void: _exec_cmd("toggle_station_open", [target_sid], "UI_INSPECTOR_BTN_TOGGLE_STATION")
			)

	var reqs: Array = bs.service_requests if bs != null else []
	_push_label(UiI18n.tr_key("UI_INSPECTOR_QUEUE_HEADER", {"count": reqs.size()}), &"LabelTitle")
	if reqs.is_empty():
		_push_label(UiI18n.tr_key("UI_INSPECTOR_QUEUE_EMPTY"), &"LabelMuted")
	else:
		var shown: int = 0
		for raw_req in reqs:
			if shown >= 3:
				break
			var req: ServiceRequest = raw_req as ServiceRequest
			if req == null:
				continue
			shown += 1
			_push_label("%s · %s" % [UiI18n.tr_service_type(String(req.service_type)), UiI18n.tr_priority(req.priority)])
			var req_id_copy: String = req.request_id
			_push_button(
				"%s -> %s" % [req_id_copy, UiI18n.tr_priority(Enums.QueuePriority.VIP)],
				func() -> void: _exec_cmd("set_queue_priority", [req_id_copy, Enums.QueuePriority.VIP], "UI_INSPECTOR_CUST_PRIORITY")
			)


func _build_station_view(bs: BankState, station_id: String) -> void:
	var st: Dictionary = bs.stations[station_id] as Dictionary
	var is_open: bool = bool(st.get("is_open", true))
	var emp_id: String = str(st.get("assigned_employee_id", ""))
	var staff_name: String = UiI18n.tr_key("UI_INSPECTOR_STATION_UNSTAFFED")
	if emp_id != "" and bs.employees.has(emp_id):
		var emp: EmployeeInstance = bs.employees[emp_id] as EmployeeInstance
		staff_name = UiI18n.tr_person_name(emp.name_key)

	_push_label(UiI18n.tr_key("UI_INSPECTOR_STATION_ID", {"id": station_id}))
	_push_label(UiI18n.tr_key("UI_INSPECTOR_STATION_TYPE", {"type": str(st.get("station_type", "teller"))}))
	_push_label(UiI18n.tr_key("UI_INSPECTOR_STATION_STATUS", {
		"status": UiI18n.tr_key("UI_INSPECTOR_STATION_OPEN" if is_open else "UI_INSPECTOR_STATION_CLOSED")
	}))
	_push_label(UiI18n.tr_key("UI_INSPECTOR_STATION_STAFF", {"name": staff_name}))

	_push_button(
		UiI18n.tr_key("UI_INSPECTOR_BTN_TOGGLE_STATION"),
		func() -> void: _exec_cmd("toggle_station_open", [station_id], "UI_INSPECTOR_BTN_TOGGLE_STATION"),
		&"ButtonPrimary"
	)

	_push_label(UiI18n.tr_key("UI_INSPECTOR_ASSIGN_STAFF_HEADER"), &"LabelTitle")
	for eid: Variant in bs.employees.keys():
		var e: EmployeeInstance = bs.employees[eid] as EmployeeInstance
		if e == null:
			continue
		var target_eid: String = e.id
		_push_button(
			UiI18n.tr_key("UI_INSPECTOR_ASSIGN_TO", {"name": UiI18n.tr_person_name(e.name_key)}),
			func() -> void: _exec_cmd("assign_employee_to_station", [target_eid, station_id], "UI_INSPECTOR_ASSIGN_STAFF_HEADER")
		)


func _build_employee_view(bs: BankState, emp_id: String) -> void:
	var emp: EmployeeInstance = bs.employees[emp_id] as EmployeeInstance
	if emp == null:
		return

	if _portrait != null:
		_portrait.texture = UiI18n.load_avatar(emp.avatar_id)
		_portrait.visible = true

	_push_label(UiI18n.tr_person_name(emp.name_key), &"LabelTitle")
	_push_label(UiI18n.tr_key("UI_INSPECTOR_EMP_ROLE", {"role": UiI18n.tr_role(emp.role_id)}))
	_push_label(UiI18n.tr_key("UI_INSPECTOR_EMP_STATE", {"state": UiI18n.tr_emp_state(emp.state)}))
	_push_label(UiI18n.tr_key("UI_INSPECTOR_EMP_FATIGUE", {"fatigue": emp.fatigue}))
	_push_label(UiI18n.tr_key("UI_INSPECTOR_EMP_ADAPTATION", {"days": emp.adaptation_days_remaining}))
	_push_label(UiI18n.tr_key("UI_INSPECTOR_EMP_SALARY", {
		"salary": FormatService.format_money(emp.daily_salary_minor, bs.currency_code, false, UiI18n.get_locale())
	}))
	_push_label(UiI18n.tr_key("UI_INSPECTOR_EMP_STATION", {
		"station": emp.assigned_station_id if not emp.assigned_station_id.is_empty() else UiI18n.tr_key("UI_INSPECTOR_STATION_UNSTAFFED")
	}))
	_push_label("%s · %s · %s · %s · %s · %s · %s" % [
		UiI18n.tr_key("UI_EMP_ATTR_PROF", {"val": emp.professionalism}),
		UiI18n.tr_key("UI_EMP_ATTR_EFF", {"val": emp.efficiency}),
		UiI18n.tr_key("UI_EMP_ATTR_SOC", {"val": emp.sociability}),
		UiI18n.tr_key("UI_EMP_ATTR_RISK", {"val": emp.risk_awareness}),
		UiI18n.tr_key("UI_EMP_ATTR_MGMT", {"val": emp.management}),
		UiI18n.tr_key("UI_EMP_ATTR_LOY", {"val": emp.loyalty}),
		UiI18n.tr_key("UI_EMP_ATTR_POT", {"val": emp.potential}),
	])

	_push_button(
		UiI18n.tr_key("UI_INSPECTOR_BTN_TRAIN"),
		func() -> void: _exec_cmd("train_employee", [emp_id], "UI_INSPECTOR_BTN_TRAIN"),
		&"ButtonPrimary"
	)
	_push_button(
		UiI18n.tr_key("UI_INSPECTOR_BTN_REST"),
		func() -> void: _exec_cmd("rest_employee", [emp_id], "UI_INSPECTOR_BTN_REST")
	)
	_push_button(
		UiI18n.tr_key("UI_INSPECTOR_BTN_FIRE"),
		func() -> void: _exec_cmd("fire_employee", [emp_id], "UI_INSPECTOR_BTN_FIRE"),
		&"ButtonDanger"
	)


func _build_customer_view(bs: BankState, cust_id: String) -> void:
	var cust: CustomerInstance = bs.active_customers[cust_id] as CustomerInstance
	if cust == null:
		return

	if _portrait != null:
		_portrait.texture = UiI18n.load_avatar(cust.avatar_id)
		_portrait.visible = true

	_push_label(UiI18n.tr_customer_type(cust.customer_type), &"LabelTitle")
	_push_label(UiI18n.tr_key("UI_INSPECTOR_CUST_PATIENCE", {
		"cur": cust.patience_remaining,
		"max": cust.patience_max,
	}))

	for req in bs.service_requests:
		if req.customer_id == cust_id:
			_push_label(UiI18n.tr_key("UI_INSPECTOR_CUST_SERVICE", {
				"service": UiI18n.tr_service_type(String(req.service_type))
			}))
			var amt: int = int(req.payload.get("amount_minor", req.payload.get("principal_minor", 0)))
			_push_label(UiI18n.tr_key("UI_INSPECTOR_CUST_AMOUNT", {
				"amount": FormatService.format_money(amt, bs.currency_code, false, UiI18n.get_locale())
			}))
			_push_label(UiI18n.tr_key("UI_INSPECTOR_CUST_PRIORITY", {
				"priority": UiI18n.tr_priority(req.priority)
			}))
			for p_val in [Enums.QueuePriority.NORMAL, Enums.QueuePriority.PRIORITY, Enums.QueuePriority.VIP]:
				var req_id_copy: String = req.request_id
				var p_copy: int = p_val
				_push_button(
					UiI18n.tr_priority(p_val),
					func() -> void: _exec_cmd("set_queue_priority", [req_id_copy, p_copy], "UI_INSPECTOR_CUST_PRIORITY")
				)
			break


func _exec_cmd(method_name: String, args: Array, action_key: String) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd != null and (cmd as Object).has_method(method_name):
		var r: Variant = (cmd as Object).callv(method_name, args)
		command_executed.emit(r, action_key)
		refresh()
