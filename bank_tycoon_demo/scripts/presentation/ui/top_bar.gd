extends PanelContainer

## Starway Bank Top HUD Bar: Core KPIs, Clock/Phase, Speed Controls, and Day Action Button.

signal command_executed(res: Variant, action_key: String)
signal save_settings_requested()
signal daily_report_requested()

var _sim_host: Node = null

var _lbl_bank_name: Label = null
var _lbl_cash_caption: Label = null
var _lbl_cash_val: Label = null
var _lbl_profit_caption: Label = null
var _lbl_profit_val: Label = null
var _lbl_sat_caption: Label = null
var _lbl_sat_val: Label = null
var _lbl_emp_caption: Label = null
var _lbl_emp_val: Label = null
var _lbl_day: Label = null
var _lbl_time: Label = null
var _lbl_phase: Label = null

var _btn_speed_0: Button = null
var _btn_speed_1: Button = null
var _btn_speed_2: Button = null
var _btn_speed_3: Button = null
var _btn_day_action: Button = null
var _btn_settings: Button = null


func _ready() -> void:
	theme_type_variation = &"PanelBar"
	_build_ui()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func bind(p_sim_host: Node) -> void:
	_sim_host = p_sim_host
	refresh()


func _on_locale_changed(_new_locale: String) -> void:
	refresh()


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# Brand emblem + name
	var emblem := TextureRect.new()
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emblem.custom_minimum_size = Vector2(28, 28)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.texture = UiI18n.load_icon("icon_starway_emblem")
	row.add_child(emblem)

	_lbl_bank_name = Label.new()
	_lbl_bank_name.theme_type_variation = &"LabelTitle"
	row.add_child(_lbl_bank_name)

	row.add_child(VSeparator.new())

	# KPI block: Cash
	var cash_box := _make_kpi_box(row, "icon_coin")
	_lbl_cash_caption = cash_box["caption"] as Label
	_lbl_cash_val = cash_box["value"] as Label
	_lbl_cash_val.theme_type_variation = &"LabelGold"

	# KPI block: Est Daily Net Profit
	var profit_box := _make_kpi_box(row, "icon_finance")
	_lbl_profit_caption = profit_box["caption"] as Label
	_lbl_profit_val = profit_box["value"] as Label

	# KPI block: Satisfaction
	var sat_box := _make_kpi_box(row, "icon_satisfaction")
	_lbl_sat_caption = sat_box["caption"] as Label
	_lbl_sat_val = sat_box["value"] as Label

	# KPI block: Employees
	var emp_box := _make_kpi_box(row, "icon_employees")
	_lbl_emp_caption = emp_box["caption"] as Label
	_lbl_emp_val = emp_box["value"] as Label

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# Clock & Phase
	var clock_box := VBoxContainer.new()
	clock_box.add_theme_constant_override("separation", 1)
	row.add_child(clock_box)

	var dt_row := HBoxContainer.new()
	dt_row.add_theme_constant_override("separation", 8)
	clock_box.add_child(dt_row)

	_lbl_day = Label.new()
	_lbl_day.theme_type_variation = &"LabelValue"
	dt_row.add_child(_lbl_day)

	_lbl_time = Label.new()
	_lbl_time.theme_type_variation = &"LabelValue"
	dt_row.add_child(_lbl_time)

	_lbl_phase = Label.new()
	_lbl_phase.theme_type_variation = &"LabelMuted"
	clock_box.add_child(_lbl_phase)

	# Speed buttons 0x / 1x / 2x / 3x
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	row.add_child(speed_row)

	_btn_speed_0 = _make_speed_btn(speed_row, 0, "icon_pause")
	_btn_speed_1 = _make_speed_btn(speed_row, 1, "icon_speed_1x")
	_btn_speed_2 = _make_speed_btn(speed_row, 2, "icon_speed_2x")
	_btn_speed_3 = _make_speed_btn(speed_row, 3, "icon_speed_3x")

	# Primary day action button
	_btn_day_action = Button.new()
	_btn_day_action.theme_type_variation = &"ButtonPrimary"
	_btn_day_action.pressed.connect(_on_day_action_pressed)
	row.add_child(_btn_day_action)

	# Save / Settings button
	_btn_settings = Button.new()
	_btn_settings.icon = UiI18n.load_icon("icon_settings")
	_btn_settings.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		save_settings_requested.emit()
	)
	row.add_child(_btn_settings)


func _make_kpi_box(parent: Node, icon_name: String) -> Dictionary:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	parent.add_child(hb)

	var ic := TextureRect.new()
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.custom_minimum_size = Vector2(18, 18)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture = UiI18n.load_icon(icon_name)
	hb.add_child(ic)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	hb.add_child(vb)

	var cap := Label.new()
	cap.theme_type_variation = &"LabelMuted"
	vb.add_child(cap)

	var val := Label.new()
	val.theme_type_variation = &"LabelValue"
	vb.add_child(val)
	return {"caption": cap, "value": val}


func _make_speed_btn(parent: Node, speed_val: int, icon_name: String) -> Button:
	var b := Button.new()
	b.icon = UiI18n.load_icon(icon_name)
	var toast_key: String = _speed_toast_key(speed_val)
	b.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		if _sim_host == null:
			push_warning("[TopBar] speed %d pressed before SimulationHost was bound; input ignored." % speed_val)
			return
		var cmd: Variant = _sim_host.get("command_service")
		if cmd == null or not (cmd as Object).has_method("set_speed"):
			push_warning("[TopBar] speed %d pressed but command_service.set_speed is unavailable; input ignored." % speed_val)
			return
		var r: Variant = (cmd as Object).call("set_speed", speed_val)
		command_executed.emit(r, toast_key)
		refresh()
	)
	parent.add_child(b)
	return b


func _speed_toast_key(speed_val: int) -> String:
	match speed_val:
		0:
			return "UI_TOPBAR_SPEED_PAUSE"
		1:
			return "UI_TOPBAR_SPEED_1X"
		2:
			return "UI_TOPBAR_SPEED_2X"
		3:
			return "UI_TOPBAR_SPEED_3X"
		_:
			return "UI_TOPBAR_SPEED_1X"


func refresh() -> void:
	if _lbl_bank_name == null:
		return

	var snap: Dictionary = {}
	if _sim_host != null and _sim_host.has_method("get_snapshot"):
		snap = _sim_host.call("get_snapshot") as Dictionary
	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null

	var lc: String = UiI18n.get_locale()
	var ccy: String = bs.currency_code if bs != null else "CNY"

	_lbl_bank_name.text = UiI18n.tr_key("UI_TOPBAR_BANK_NAME")
	_lbl_cash_caption.text = UiI18n.tr_key("UI_TOPBAR_CASH")
	_lbl_profit_caption.text = UiI18n.tr_key("UI_TOPBAR_TODAY_PROFIT")
	_lbl_sat_caption.text = UiI18n.tr_key("UI_TOPBAR_SATISFACTION")
	_lbl_emp_caption.text = UiI18n.tr_key("UI_TOPBAR_EMPLOYEES")

	var cash_minor: int = int(snap.get("cash_minor", 20_000_000))
	var profit_minor: int = int(snap.get("today_profit_minor", 0))
	var sat: int = int(snap.get("satisfaction", 75))
	var emp_cnt: int = int(snap.get("employee_count", 2))
	var day_num: int = int(snap.get("day", 1))
	var minute_val: int = int(snap.get("minute", 540))
	var phase_val: int = int(snap.get("phase", Enums.DayPhase.PRE_OPEN))
	var speed_val: int = int(snap.get("speed", 1))

	_lbl_cash_val.text = FormatService.format_money(cash_minor, ccy, false, lc)
	_lbl_profit_val.text = FormatService.format_money(profit_minor, ccy, true, lc)
	_lbl_profit_val.add_theme_color_override("font_color", StarwayTheme.delta_color(profit_minor))
	_lbl_sat_val.text = "%d%%" % sat
	_lbl_emp_val.text = str(emp_cnt)

	_lbl_day.text = UiI18n.tr_key("UI_TOPBAR_DAY", {"day": day_num})
	_lbl_time.text = FormatService.format_time(minute_val)
	_lbl_phase.text = UiI18n.tr_phase(phase_val)

	_btn_speed_0.text = UiI18n.tr_key("UI_TOPBAR_SPEED_PAUSE")
	_btn_speed_1.text = UiI18n.tr_key("UI_TOPBAR_SPEED_1X")
	_btn_speed_2.text = UiI18n.tr_key("UI_TOPBAR_SPEED_2X")
	_btn_speed_3.text = UiI18n.tr_key("UI_TOPBAR_SPEED_3X")

	_btn_speed_0.theme_type_variation = &"ButtonPrimary" if speed_val == 0 else &""
	_btn_speed_1.theme_type_variation = &"ButtonPrimary" if speed_val == 1 else &""
	_btn_speed_2.theme_type_variation = &"ButtonPrimary" if speed_val == 2 else &""
	_btn_speed_3.theme_type_variation = &"ButtonPrimary" if speed_val == 3 else &""

	match phase_val:
		Enums.DayPhase.PRE_OPEN:
			_btn_day_action.text = UiI18n.tr_key("UI_TOPBAR_ACTION_OPEN_BRANCH")
			_btn_day_action.theme_type_variation = &"ButtonPrimary"
		Enums.DayPhase.SETTLED:
			_btn_day_action.text = UiI18n.tr_key("UI_TOPBAR_ACTION_NEXT_DAY")
			_btn_day_action.theme_type_variation = &"ButtonGold"
		_:
			_btn_day_action.text = UiI18n.tr_key("UI_TOPBAR_ACTION_NEXT_DAY")
			_btn_day_action.theme_type_variation = &"ButtonPrimary"

	_btn_settings.text = UiI18n.tr_key("UI_TOPBAR_BTN_SAVE_SETTINGS")


func _on_day_action_pressed() -> void:
	UiI18n.play_sfx("sfx_ui_click")
	if _sim_host == null:
		push_warning("[TopBar] day action pressed before SimulationHost was bound; input ignored.")
		return
	var cmd: Variant = _sim_host.get("command_service")
	var bs: BankState = _sim_host.get("bank_state") as BankState
	if cmd == null or bs == null:
		push_warning("[TopBar] day action pressed but command_service/bank_state is unavailable; input ignored.")
		return
	if bs.day_phase == Enums.DayPhase.PRE_OPEN:
		var r: Variant = (cmd as Object).call("open_branch_for_day")
		command_executed.emit(r, "UI_TOPBAR_ACTION_OPEN_BRANCH")
	elif bs.day_phase == Enums.DayPhase.SETTLED:
		daily_report_requested.emit()
	else:
		var r2: Variant = (cmd as Object).call("advance_to_next_day")
		command_executed.emit(r2, "UI_TOPBAR_ACTION_NEXT_DAY")
	refresh()
