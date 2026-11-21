extends PanelContainer

## Staff & Talent Recruitment Drawer — Horizontal Employee Cards with 6-Axis Radar Charts,
## Exclusive Ability Tags (Traits), and Dual Training (Attribute Growth + Positive Tag Refresh).

signal close_requested()
signal command_executed(res: Variant, action_key: String)

const RadarChartScript := preload("res://scripts/presentation/ui/employee_radar_chart.gd")

var _sim_host: Node = null
var _lbl_title: Label = null
var _lbl_subtitle: Label = null
var _btn_close: Button = null
var _lbl_active_hdr: Label = null
var _active_list_box: HBoxContainer = null
var _lbl_cand_hdr: Label = null
var _cand_list_box: HBoxContainer = null

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
	root_v.add_theme_constant_override("separation", 8)
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

	var outer_scroll := ScrollContainer.new()
	outer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(outer_scroll)

	var content_v := VBoxContainer.new()
	content_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_v.add_theme_constant_override("separation", 10)
	outer_scroll.add_child(content_v)

	_lbl_active_hdr = Label.new()
	_lbl_active_hdr.theme_type_variation = &"LabelTitle"
	content_v.add_child(_lbl_active_hdr)

	var active_hscroll := ScrollContainer.new()
	active_hscroll.name = "ActiveStaffHorizontalScroll"
	active_hscroll.custom_minimum_size = Vector2(0.0, 416.0)
	active_hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	active_hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_v.add_child(active_hscroll)

	_active_list_box = HBoxContainer.new()
	_active_list_box.name = "ActiveStaffCardRow"
	_active_list_box.add_theme_constant_override("separation", 12)
	active_hscroll.add_child(_active_list_box)

	content_v.add_child(HSeparator.new())

	_lbl_cand_hdr = Label.new()
	_lbl_cand_hdr.theme_type_variation = &"LabelTitle"
	content_v.add_child(_lbl_cand_hdr)

	var cand_hscroll := ScrollContainer.new()
	cand_hscroll.name = "CandidatesHorizontalScroll"
	cand_hscroll.custom_minimum_size = Vector2(0.0, 210.0)
	cand_hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cand_hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_v.add_child(cand_hscroll)

	_cand_list_box = HBoxContainer.new()
	_cand_list_box.name = "CandidatesCardRow"
	_cand_list_box.add_theme_constant_override("separation", 12)
	cand_hscroll.add_child(_cand_list_box)


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
	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
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
		_active_list_box.add_child(_build_employee_card(emp, bs, defs, ccy, lc))

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
			_cand_list_box.add_child(_build_candidate_card(cand, defs, ccy, lc))

	UiListRefresh.watch_tree(_active_list_box, _on_list_button_up)
	UiListRefresh.watch_tree(_cand_list_box, _on_list_button_up)


func _build_employee_card(
	emp: EmployeeInstance,
	bs: BankState,
	defs: Dictionary,
	ccy: String,
	lc: String
) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "EmployeeCard_%s" % emp.id
	card.theme_type_variation = &"PanelCard"
	card.custom_minimum_size = Vector2(284.0, 404.0)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)

	# 1. Header: Avatar + Name + Role/Post + Salary + Fatigue
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	cv.add_child(hdr)

	var avatar := TextureRect.new()
	avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	avatar.custom_minimum_size = Vector2(42, 42)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.texture = UiI18n.load_avatar(emp.avatar_id)
	hdr.add_child(avatar)

	var meta_v := VBoxContainer.new()
	meta_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_v.add_theme_constant_override("separation", 2)
	hdr.add_child(meta_v)

	var post_label: String = ""
	if not emp.department_id.is_empty():
		post_label = UiI18n.tr_key(_dept_short_key(emp.department_id))
	elif emp.role_id == "lobby_manager":
		post_label = UiI18n.tr_key("ROLE_LOBBY_MANAGER")
	elif not emp.assigned_station_id.is_empty():
		post_label = emp.assigned_station_id
	else:
		post_label = UiI18n.tr_key("UI_EMP_POST_UNASSIGNED")

	var name_l := Label.new()
	name_l.theme_type_variation = &"LabelTitle"
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.text = "%s · %s · Lv.%d" % [UiI18n.tr_person_name(emp.name_key), UiI18n.tr_role(emp.role_id), emp.level]
	meta_v.add_child(name_l)

	var sub_l := Label.new()
	sub_l.theme_type_variation = &"LabelMuted"
	sub_l.add_theme_font_size_override("font_size", 11)
	sub_l.text = "[%s] · %s %d · %s · %s" % [
		post_label,
		UiI18n.tr_key("UI_EMP_STAT_CAP_SHORT"),
		emp.get_stat_cap(),
		FormatService.format_money_compact(emp.daily_salary_minor, ccy, false),
		UiI18n.tr_key("UI_INSPECTOR_EMP_FATIGUE", {"fatigue": emp.fatigue}),
	]
	meta_v.add_child(sub_l)

	# 1b. Experience Progress Bar (must reach 100% XP to promote)
	var xp_req: int = emp.get_xp_required()
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	cv.add_child(xp_row)
	var xp_lbl := Label.new()
	xp_lbl.add_theme_font_size_override("font_size", 11)
	if emp.level >= BalanceConfig.EMPLOYEE_MAX_LEVEL:
		xp_lbl.add_theme_color_override("font_color", Color("#FFC857"))
		xp_lbl.text = UiI18n.tr_key("UI_EMP_XP_MAX")
	elif emp.can_promote():
		xp_lbl.add_theme_color_override("font_color", Color("#35C978"))
		xp_lbl.text = UiI18n.tr_key("UI_EMP_XP_READY", {"xp": emp.work_xp, "req": xp_req})
	else:
		xp_lbl.add_theme_color_override("font_color", Color("#7FD8FF"))
		xp_lbl.text = UiI18n.tr_key("UI_EMP_XP_PROG", {"xp": emp.work_xp, "req": xp_req})
	xp_row.add_child(xp_lbl)
	var xp_bar := ProgressBar.new()
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_bar.custom_minimum_size = Vector2(0.0, 8.0)
	xp_bar.min_value = 0.0
	xp_bar.max_value = float(maxi(1, xp_req))
	xp_bar.value = float(xp_req if emp.level >= BalanceConfig.EMPLOYEE_MAX_LEVEL else emp.work_xp)
	xp_bar.show_percentage = false
	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = Color("#FFC857") if emp.level >= BalanceConfig.EMPLOYEE_MAX_LEVEL else (Color("#35C978") if emp.can_promote() else Color("#00C6FF"))
	xp_fill.set_corner_radius_all(3)
	xp_bar.add_theme_stylebox_override("fill", xp_fill)
	xp_row.add_child(xp_bar)

	# 2. Exclusive Ability Tags (Traits) Row
	var tags_flow := HFlowContainer.new()
	tags_flow.add_theme_constant_override("h_separation", 4)
	tags_flow.add_theme_constant_override("v_separation", 4)
	cv.add_child(tags_flow)

	if emp.traits.is_empty():
		var no_tag := Label.new()
		no_tag.theme_type_variation = &"LabelMuted"
		no_tag.add_theme_font_size_override("font_size", 11)
		no_tag.text = UiI18n.tr_key("UI_EMP_NO_TRAITS")
		tags_flow.add_child(no_tag)
	else:
		for tid: String in emp.traits:
			tags_flow.add_child(_make_trait_pill(tid, defs))

	# 3. 6-Axis Capability Radar Chart
	var eff_attrs: Dictionary = emp.get_effective_attributes(defs)
	var bonuses: Dictionary = eff_attrs.get("bonuses", {}) as Dictionary
	var radar: Control = RadarChartScript.new() as Control
	radar.name = "RadarChart_%s" % emp.id
	radar.custom_minimum_size = Vector2(262.0, 148.0)
	radar.call("set_axes",
		[
			UiI18n.tr_key("UI_RADAR_PROF"),
			UiI18n.tr_key("UI_RADAR_EFF"),
			UiI18n.tr_key("UI_RADAR_SOC"),
			UiI18n.tr_key("UI_RADAR_RISK"),
			UiI18n.tr_key("UI_RADAR_MGMT"),
			UiI18n.tr_key("UI_RADAR_LOYAL"),
		],
		[
			int(eff_attrs["professionalism"]),
			int(eff_attrs["efficiency"]),
			int(eff_attrs["sociability"]),
			int(eff_attrs["risk_awareness"]),
			int(eff_attrs["management"]),
			int(eff_attrs["loyalty"]),
		],
		[
			int(bonuses.get("professionalism", 0)) > 0,
			int(bonuses.get("efficiency", 0)) > 0,
			int(bonuses.get("sociability", 0)) > 0,
			int(bonuses.get("risk_awareness", 0)) > 0,
			int(bonuses.get("management", 0)) > 0,
			int(bonuses.get("loyalty", 0)) > 0,
		]
	)
	cv.add_child(radar)

	# 4. Compact Reassignment Row (Stations + Lobby Manager + Departments)
	var assign_row := HFlowContainer.new()
	assign_row.add_theme_constant_override("h_separation", 4)
	assign_row.add_theme_constant_override("v_separation", 4)
	cv.add_child(assign_row)

	var station_ids: Array[String] = []
	for sid_v: Variant in bs.stations.keys():
		station_ids.append(str(sid_v))
	station_ids.sort()
	for sid: String in station_ids:
		var sbtn := Button.new()
		sbtn.add_theme_font_size_override("font_size", 11)
		sbtn.text = sid
		if emp.assigned_station_id == sid:
			sbtn.theme_type_variation = &"ButtonPrimary"
		var eid_copy: String = emp.id
		var sid_copy: String = sid
		sbtn.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_exec_cmd("assign_employee_to_station", [eid_copy, sid_copy], "UI_INSPECTOR_ASSIGN_STAFF_HEADER")
		)
		assign_row.add_child(sbtn)

	var lm_btn := Button.new()
	lm_btn.add_theme_font_size_override("font_size", 11)
	lm_btn.text = UiI18n.tr_key("ROLE_LOBBY_MANAGER")
	if emp.role_id == "lobby_manager" and emp.department_id.is_empty():
		lm_btn.theme_type_variation = &"ButtonGold"
	var eid_lm: String = emp.id
	lm_btn.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_exec_cmd("assign_employee_as_lobby_manager", [eid_lm], "ROLE_LOBBY_MANAGER")
	)
	assign_row.add_child(lm_btn)

	for did_v: Variant in bs.departments.keys():
		var did: String = str(did_v)
		var dbtn := Button.new()
		dbtn.add_theme_font_size_override("font_size", 11)
		dbtn.text = UiI18n.tr_key(_dept_short_key(did))
		if emp.department_id == did:
			dbtn.theme_type_variation = &"ButtonPrimary"
		var eid_d: String = emp.id
		var did_copy: String = did
		dbtn.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_exec_cmd("assign_employee_to_department", [eid_d, did_copy], "UI_DRAWER_DEPARTMENTS_TITLE")
		)
		assign_row.add_child(dbtn)

	# 5. Dual Training + Rest + Fire Action Buttons (2 rows)
	var act_row1 := HBoxContainer.new()
	act_row1.add_theme_constant_override("separation", 6)
	cv.add_child(act_row1)

	var eid_t: String = emp.id
	var btn_train := Button.new()
	btn_train.theme_type_variation = &"ButtonPrimary"
	btn_train.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_train.add_theme_font_size_override("font_size", 12)
	btn_train.text = UiI18n.tr_key("UI_EMP_BTN_TRAIN_STATS")
	btn_train.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_exec_cmd("train_employee", [eid_t], "UI_INSPECTOR_BTN_TRAIN")
	)
	act_row1.add_child(btn_train)

	var btn_trait := Button.new()
	btn_trait.theme_type_variation = &"ButtonGold"
	btn_trait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_trait.add_theme_font_size_override("font_size", 12)
	btn_trait.text = UiI18n.tr_key("UI_EMP_BTN_REFRESH_TRAIT")
	btn_trait.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_exec_cmd("refresh_employee_trait", [eid_t], "UI_EMP_BTN_REFRESH_TRAIT")
	)
	act_row1.add_child(btn_trait)

	var act_row2 := HBoxContainer.new()
	act_row2.add_theme_constant_override("separation", 6)
	cv.add_child(act_row2)

	var btn_prom := Button.new()
	btn_prom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_prom.add_theme_font_size_override("font_size", 11)
	if emp.level >= BalanceConfig.EMPLOYEE_MAX_LEVEL:
		btn_prom.disabled = true
		btn_prom.text = UiI18n.tr_key("UI_EMP_MAX_LEVEL_BTN")
	elif not emp.can_promote():
		btn_prom.disabled = true
		btn_prom.text = UiI18n.tr_key("UI_EMP_XP_LOCKED_BTN", {"xp": emp.work_xp, "req": emp.get_xp_required()})
	else:
		btn_prom.theme_type_variation = &"ButtonPrimary"
		var pcost: int = int(BalanceConfig.EMPLOYEE_PROMOTE_COSTS_MINOR.get(emp.level, 80_000))
		btn_prom.text = UiI18n.tr_key("UI_EMP_BTN_PROMOTE", {
			"lv": emp.level + 1,
			"cost": FormatService.format_money_compact(pcost, ccy, false),
		})
		btn_prom.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_cash_chime")
			_exec_cmd("promote_employee", [eid_t], "UI_EMP_PROMOTE_OK")
		)
	act_row2.add_child(btn_prom)

	var btn_rest := Button.new()
	btn_rest.add_theme_font_size_override("font_size", 11)
	btn_rest.text = UiI18n.tr_key("UI_INSPECTOR_BTN_REST")
	btn_rest.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_exec_cmd("rest_employee", [eid_t], "UI_INSPECTOR_BTN_REST")
	)
	act_row2.add_child(btn_rest)

	var btn_fire := Button.new()
	btn_fire.theme_type_variation = &"ButtonDanger"
	btn_fire.add_theme_font_size_override("font_size", 11)
	btn_fire.text = UiI18n.tr_key("UI_INSPECTOR_BTN_FIRE")
	btn_fire.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_exec_cmd("fire_employee", [eid_t], "UI_INSPECTOR_BTN_FIRE")
	)
	act_row2.add_child(btn_fire)

	return card


func _build_candidate_card(
	cand: EmployeeInstance,
	defs: Dictionary,
	ccy: String,
	lc: String
) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "CandidateCard_%s" % cand.id
	card.theme_type_variation = &"PanelCard"
	card.custom_minimum_size = Vector2(284.0, 196.0)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	cv.add_child(hdr)

	var avatar := TextureRect.new()
	avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	avatar.custom_minimum_size = Vector2(38, 38)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.texture = UiI18n.load_avatar(cand.avatar_id)
	hdr.add_child(avatar)

	var info_v := VBoxContainer.new()
	info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(info_v)

	var nl := Label.new()
	nl.theme_type_variation = &"LabelTitle"
	nl.add_theme_font_size_override("font_size", 13)
	nl.text = "%s · %s · Lv.%d (%s)" % [
		UiI18n.tr_person_name(cand.name_key),
		UiI18n.tr_role(cand.role_id),
		cand.level,
		FormatService.format_money_compact(cand.daily_salary_minor, ccy, false),
	]
	info_v.add_child(nl)

	var al := Label.new()
	al.theme_type_variation = &"LabelMuted"
	al.add_theme_font_size_override("font_size", 11)
	al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	al.text = "%s · %s · %s · %s · %s" % [
		UiI18n.tr_key("UI_EMP_ATTR_PROF", {"val": cand.professionalism}),
		UiI18n.tr_key("UI_EMP_ATTR_EFF", {"val": cand.efficiency}),
		UiI18n.tr_key("UI_EMP_ATTR_SOC", {"val": cand.sociability}),
		UiI18n.tr_key("UI_EMP_ATTR_RISK", {"val": cand.risk_awareness}),
		UiI18n.tr_key("UI_EMP_ATTR_POT", {"val": cand.potential}),
	]
	info_v.add_child(al)

	if not cand.traits.is_empty():
		var ctags := HFlowContainer.new()
		ctags.add_theme_constant_override("h_separation", 4)
		ctags.add_theme_constant_override("v_separation", 4)
		for tid: String in cand.traits:
			ctags.add_child(_make_trait_pill(tid, defs))
		cv.add_child(ctags)

	var hire_flow := HFlowContainer.new()
	hire_flow.add_theme_constant_override("h_separation", 5)
	hire_flow.add_theme_constant_override("v_separation", 5)
	cv.add_child(hire_flow)

	for r_pair in [
		["teller", "UI_EMP_BTN_HIRE_TELLER"],
		["loan_officer", "UI_EMP_BTN_HIRE_LOAN"],
		["lobby_manager", "UI_EMP_BTN_HIRE_LOBBY_MGR"],
		["analyst", "UI_EMP_BTN_HIRE_ANALYST"],
	]:
		var hbtn := Button.new()
		hbtn.theme_type_variation = &"ButtonPrimary"
		hbtn.add_theme_font_size_override("font_size", 11)
		hbtn.text = UiI18n.tr_key(r_pair[1])
		var cid_copy: String = cand.id
		var role_copy: String = r_pair[0]
		var key_copy: String = r_pair[1]
		hbtn.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_exec_cmd("hire_candidate", [cid_copy, role_copy], key_copy)
		)
		hire_flow.add_child(hbtn)

	return card


func _make_trait_pill(trait_id: String, defs: Dictionary) -> PanelContainer:
	var tdef: Dictionary = _find_trait_def(trait_id, defs)
	var is_neg: bool = str(tdef.get("polarity", "positive")) == "negative"
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.26, 0.08, 0.10, 0.94) if is_neg else Color(0.11, 0.22, 0.36, 0.94)
	sb.border_color = Color("#FF5C5C") if is_neg else Color("#FFC857")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", sb)

	var tname: String = UiI18n.tr_key(str(tdef.get("name_key", trait_id)))
	var bonus_parts: Array[String] = []
	var ab: Variant = tdef.get("attribute_bonuses", {})
	if ab is Dictionary:
		var attr_keys: Dictionary = {
			"professionalism": "UI_RADAR_PROF",
			"efficiency": "UI_RADAR_EFF",
			"sociability": "UI_RADAR_SOC",
			"risk_awareness": "UI_RADAR_RISK",
			"management": "UI_RADAR_MGMT",
			"loyalty": "UI_RADAR_LOYAL",
			"potential": "UI_RADAR_POT",
		}
		for k: Variant in (ab as Dictionary).keys():
			var sk: String = str(k)
			var v: int = int((ab as Dictionary)[k])
			if v != 0 and attr_keys.has(sk):
				bonus_parts.append("%+d%s" % [v, UiI18n.tr_key(str(attr_keys[sk]))])

	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#FF9999") if is_neg else Color("#FFE082"))
	lbl.text = "%s (%s)" % [tname, " ".join(bonus_parts)] if not bonus_parts.is_empty() else tname
	pill.add_child(lbl)
	return pill


func _find_trait_def(trait_id: String, defs: Dictionary) -> Dictionary:
	var raw_traits: Variant = defs.get("traits", [])
	if raw_traits is Array:
		for raw_t: Variant in (raw_traits as Array):
			if raw_t is Dictionary and str((raw_t as Dictionary).get("id", "")) == trait_id:
				return raw_t as Dictionary
	return {}


func _on_list_button_up() -> void:
	if not _rebuild_pending:
		return
	_rebuild_pending = false
	refresh.call_deferred()


func _dept_short_key(dept_id: String) -> String:
	match dept_id:
		"core:department.operations":
			return "WORLD_DEPT_OPS_SHORT"
		"core:department.hr":
			return "WORLD_DEPT_HR_SHORT"
		"core:department.credit":
			return "WORLD_DEPT_CREDIT_SHORT"
		"core:department.risk":
			return "WORLD_DEPT_RISK_SHORT"
		_:
			return dept_id


func _exec_cmd(method_name: String, args: Array, action_key: String) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd != null and (cmd as Object).has_method(method_name):
		var r: Variant = (cmd as Object).callv(method_name, args)
		command_executed.emit(r, action_key)
		refresh.call_deferred()
