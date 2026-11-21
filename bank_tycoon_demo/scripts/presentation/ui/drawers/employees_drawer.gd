extends PanelContainer

## Staff & Talent Recruitment Drawer.

signal close_requested()
signal command_executed(res: Variant, action_key: String)

var _sim_host: Node = null
var _lbl_title: Label = null
var _lbl_subtitle: Label = null
var _btn_close: Button = null
var _lbl_active_hdr: Label = null
var _active_list_box: VBoxContainer = null
var _lbl_cand_hdr: Label = null
var _cand_list_box: VBoxContainer = null

var _rebuild_pending: bool = false


func _ready() -> void:
	theme_type_variation = &"PanelLarge"
	_build_ui()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func bind(p_sim_host: Node) -> void:
	_sim_host = p_sim_host
	refresh()


func _on_locale_changed(_new_locale: String) -> void:
	refresh()


func _build_ui() -> void:
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	add_child(root_v)

	var hdr := HBoxContainer.new()
	root_v.add_child(hdr)

	var title_v := VBoxContainer.new()
	title_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_v)

	_lbl_title = Label.new()
	_lbl_title.theme_type_variation = &"LabelTitle"
	title_v.add_child(_lbl_title)

	_lbl_subtitle = Label.new()
	_lbl_subtitle.theme_type_variation = &"LabelMuted"
	title_v.add_child(_lbl_subtitle)

	_btn_close = Button.new()
	_btn_close.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		close_requested.emit()
	)
	hdr.add_child(_btn_close)

	root_v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	var content_v := VBoxContainer.new()
	content_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_v.add_theme_constant_override("separation", 10)
	scroll.add_child(content_v)

	_lbl_active_hdr = Label.new()
	_lbl_active_hdr.theme_type_variation = &"LabelTitle"
	content_v.add_child(_lbl_active_hdr)

	_active_list_box = VBoxContainer.new()
	_active_list_box.add_theme_constant_override("separation", 6)
	content_v.add_child(_active_list_box)

	content_v.add_child(HSeparator.new())

	_lbl_cand_hdr = Label.new()
	_lbl_cand_hdr.theme_type_variation = &"LabelTitle"
	content_v.add_child(_lbl_cand_hdr)

	_cand_list_box = VBoxContainer.new()
	_cand_list_box.add_theme_constant_override("separation", 6)
	content_v.add_child(_cand_list_box)


func refresh() -> void:
	if _lbl_title == null:
		return

	_lbl_title.text = UiI18n.tr_key("UI_DRAWER_EMPLOYEES_TITLE")
	_lbl_subtitle.text = UiI18n.tr_key("UI_DRAWER_EMPLOYEES_SUBTITLE")
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")

	if UiListRefresh.any_button_held(_active_list_box) or UiListRefresh.any_button_held(_cand_list_box):
		_rebuild_pending = true
		return
	UiListRefresh.clear_children(_active_list_box)
	UiListRefresh.clear_children(_cand_list_box)

	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var lc: String = UiI18n.get_locale()
	var ccy: String = bs.currency_code if bs != null else "CNY"

	var emp_ids: Array[String] = []
	if bs != null:
		for eid: Variant in bs.employees.keys():
			emp_ids.append(str(eid))
		emp_ids.sort()

	_lbl_active_hdr.text = UiI18n.tr_key("UI_EMP_ACTIVE_HEADER", {"count": emp_ids.size()})
	for eid in emp_ids:
		var emp: EmployeeInstance = bs.employees[eid] as EmployeeInstance
		if emp == null:
			continue
		var card := PanelContainer.new()
		card.theme_type_variation = &"PanelCard"
		_active_list_box.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)

		var avatar := TextureRect.new()
		avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		avatar.custom_minimum_size = Vector2(36, 36)
		avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar.texture = UiI18n.load_avatar(emp.avatar_id)
		row.add_child(avatar)

		var info_v := VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info_v)

		var title_l := Label.new()
		title_l.text = "%s · %s · %s · %s" % [
			UiI18n.tr_person_name(emp.name_key),
			UiI18n.tr_role(emp.role_id),
			UiI18n.tr_emp_state(emp.state),
			FormatService.format_money(emp.daily_salary_minor, ccy, false, lc),
		]
		info_v.add_child(title_l)

		var sub_l := Label.new()
		sub_l.theme_type_variation = &"LabelMuted"
		sub_l.text = "%s · %s · %s · %s" % [
			UiI18n.tr_key("UI_INSPECTOR_EMP_FATIGUE", {"fatigue": emp.fatigue}),
			UiI18n.tr_key("UI_EMP_ATTR_PROF", {"val": emp.professionalism}),
			UiI18n.tr_key("UI_EMP_ATTR_EFF", {"val": emp.efficiency}),
			UiI18n.tr_key("UI_EMP_ATTR_RISK", {"val": emp.risk_awareness}),
		]
		info_v.add_child(sub_l)

		# Station assign buttons
		for sid in ["teller_1", "teller_2", "loan_1"]:
			if bs.stations.has(sid):
				var sbtn := Button.new()
				sbtn.text = sid
				var eid_copy: String = emp.id
				var sid_copy: String = sid
				sbtn.pressed.connect(func() -> void:
					UiI18n.play_sfx("sfx_ui_click")
					_exec_cmd("assign_employee_to_station", [eid_copy, sid_copy], "UI_INSPECTOR_ASSIGN_STAFF_HEADER")
				)
				row.add_child(sbtn)

		var btn_train := Button.new()
		btn_train.text = UiI18n.tr_key("UI_INSPECTOR_BTN_TRAIN")
		var eid_t: String = emp.id
		btn_train.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_exec_cmd("train_employee", [eid_t], "UI_INSPECTOR_BTN_TRAIN")
		)
		row.add_child(btn_train)

		var btn_rest := Button.new()
		btn_rest.text = UiI18n.tr_key("UI_INSPECTOR_BTN_REST")
		btn_rest.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_exec_cmd("rest_employee", [eid_t], "UI_INSPECTOR_BTN_REST")
		)
		row.add_child(btn_rest)

		var btn_fire := Button.new()
		btn_fire.theme_type_variation = &"ButtonDanger"
		btn_fire.text = UiI18n.tr_key("UI_INSPECTOR_BTN_FIRE")
		btn_fire.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_exec_cmd("fire_employee", [eid_t], "UI_INSPECTOR_BTN_FIRE")
		)
		row.add_child(btn_fire)

	var cands: Array = bs.candidates if bs != null else []
	_lbl_cand_hdr.text = UiI18n.tr_key("UI_EMP_CANDIDATES_HEADER", {"count": cands.size()})
	if cands.is_empty():
		var empty_l := Label.new()
		empty_l.theme_type_variation = &"LabelMuted"
		empty_l.text = UiI18n.tr_key("UI_EMP_CANDIDATES_EMPTY")
		_cand_list_box.add_child(empty_l)
	else:
		for raw_cand in cands:
			var cand: EmployeeInstance = raw_cand as EmployeeInstance
			if cand == null:
				continue
			var card := PanelContainer.new()
			card.theme_type_variation = &"PanelCard"
			_cand_list_box.add_child(card)

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			card.add_child(row)

			var avatar := TextureRect.new()
			avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			avatar.custom_minimum_size = Vector2(36, 36)
			avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			avatar.texture = UiI18n.load_avatar(cand.avatar_id)
			row.add_child(avatar)

			var info_v := VBoxContainer.new()
			info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info_v)

			var nl := Label.new()
			nl.text = "%s · %s (%s)" % [
				UiI18n.tr_person_name(cand.name_key),
				UiI18n.tr_role(cand.role_id),
				FormatService.format_money(cand.daily_salary_minor, ccy, false, lc),
			]
			info_v.add_child(nl)

			var al := Label.new()
			al.theme_type_variation = &"LabelMuted"
			al.text = "%s · %s · %s · %s · %s" % [
				UiI18n.tr_key("UI_EMP_ATTR_PROF", {"val": cand.professionalism}),
				UiI18n.tr_key("UI_EMP_ATTR_EFF", {"val": cand.efficiency}),
				UiI18n.tr_key("UI_EMP_ATTR_SOC", {"val": cand.sociability}),
				UiI18n.tr_key("UI_EMP_ATTR_RISK", {"val": cand.risk_awareness}),
				UiI18n.tr_key("UI_EMP_ATTR_POT", {"val": cand.potential}),
			]
			info_v.add_child(al)

			for r_pair in [
				["teller", "UI_EMP_BTN_HIRE_TELLER"],
				["loan_officer", "UI_EMP_BTN_HIRE_LOAN"],
				["analyst", "UI_EMP_BTN_HIRE_ANALYST"],
			]:
				var hbtn := Button.new()
				hbtn.theme_type_variation = &"ButtonPrimary"
				hbtn.text = UiI18n.tr_key(r_pair[1])
				var cid_copy: String = cand.id
				var role_copy: String = r_pair[0]
				var key_copy: String = r_pair[1]
				hbtn.pressed.connect(func() -> void:
					UiI18n.play_sfx("sfx_ui_click")
					_exec_cmd("hire_candidate", [cid_copy, role_copy], key_copy)
				)
				row.add_child(hbtn)

	UiListRefresh.watch_tree(_active_list_box, _on_list_button_up)
	UiListRefresh.watch_tree(_cand_list_box, _on_list_button_up)


func _on_list_button_up() -> void:
	if not _rebuild_pending:
		return
	_rebuild_pending = false
	refresh.call_deferred()


func _exec_cmd(method_name: String, args: Array, action_key: String) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd != null and (cmd as Object).has_method(method_name):
		var r: Variant = (cmd as Object).callv(method_name, args)
		command_executed.emit(r, action_key)
		refresh.call_deferred()
