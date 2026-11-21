extends PanelContainer

## End-of-Day Financial Settlement Report Overlay (res://scenes/ui/daily_report_overlay.tscn).

signal next_day_requested()

var _sim_host: Node = null
var _current_report: Dictionary = {}

var _lbl_title: Label = null
var _lbl_subtitle: Label = null
var _lbl_pnl_header: Label = null
var _pnl_rows_box: VBoxContainer = null
var _lbl_bs_header: Label = null
var _bs_rows_box: VBoxContainer = null
var _lbl_drivers_header: Label = null
var _drivers_box: VBoxContainer = null
var _btn_next_day: Button = null


func _ready() -> void:
	theme = StarwayTheme.build()
	theme_type_variation = &"PanelLarge"
	_build_ui_if_needed()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func bind(p_sim_host: Node) -> void:
	_sim_host = p_sim_host
	refresh()


func show_report(report: Dictionary) -> void:
	_current_report = report.duplicate(true)
	visible = true
	refresh()


func _on_locale_changed(_new_locale: String) -> void:
	refresh()


func _build_ui_if_needed() -> void:
	if _lbl_title != null:
		return

	var existing_root: Node = get_node_or_null("RootVBox")
	if existing_root != null:
		remove_child(existing_root)
		existing_root.free()

	var root_v := VBoxContainer.new()
	root_v.name = "RootVBox"
	root_v.add_theme_constant_override("separation", 10)
	add_child(root_v)

	_lbl_title = Label.new()
	_lbl_title.theme_type_variation = &"LabelTitle"
	root_v.add_child(_lbl_title)

	_lbl_subtitle = Label.new()
	_lbl_subtitle.theme_type_variation = &"LabelMuted"
	root_v.add_child(_lbl_subtitle)

	root_v.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(cols)

	# Left Column: P&L Breakdown
	var left_card := PanelContainer.new()
	left_card.theme_type_variation = &"PanelCard"
	left_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left_card)

	var left_v := VBoxContainer.new()
	left_v.add_theme_constant_override("separation", 6)
	left_card.add_child(left_v)

	_lbl_pnl_header = Label.new()
	_lbl_pnl_header.theme_type_variation = &"LabelTitle"
	left_v.add_child(_lbl_pnl_header)

	_pnl_rows_box = VBoxContainer.new()
	_pnl_rows_box.add_theme_constant_override("separation", 4)
	left_v.add_child(_pnl_rows_box)

	# Right Column: Balance Sheet & Risk Metrics
	var right_card := PanelContainer.new()
	right_card.theme_type_variation = &"PanelCard"
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right_card)

	var right_v := VBoxContainer.new()
	right_v.add_theme_constant_override("separation", 6)
	right_card.add_child(right_v)

	_lbl_bs_header = Label.new()
	_lbl_bs_header.theme_type_variation = &"LabelTitle"
	right_v.add_child(_lbl_bs_header)

	_bs_rows_box = VBoxContainer.new()
	_bs_rows_box.add_theme_constant_override("separation", 4)
	right_v.add_child(_bs_rows_box)

	right_v.add_child(HSeparator.new())

	_lbl_drivers_header = Label.new()
	_lbl_drivers_header.theme_type_variation = &"LabelTitle"
	right_v.add_child(_lbl_drivers_header)

	_drivers_box = VBoxContainer.new()
	_drivers_box.add_theme_constant_override("separation", 4)
	right_v.add_child(_drivers_box)

	# Bottom action bar
	var act_row := HBoxContainer.new()
	act_row.alignment = BoxContainer.ALIGNMENT_END
	root_v.add_child(act_row)

	_btn_next_day = Button.new()
	_btn_next_day.theme_type_variation = &"ButtonGold"
	_btn_next_day.custom_minimum_size = Vector2(240, 40)
	_btn_next_day.pressed.connect(_on_next_day_pressed)
	act_row.add_child(_btn_next_day)


func refresh() -> void:
	_build_ui_if_needed()
	var rep: Dictionary = _current_report
	if rep.is_empty() and _sim_host != null:
		var bs: Variant = _sim_host.get("bank_state")
		if bs is BankState and not (bs as BankState).daily_reports.is_empty():
			rep = (bs as BankState).daily_reports.back() as Dictionary

	var day_num: int = int(rep.get("day", 1))
	var lc: String = UiI18n.get_locale()
	_lbl_title.text = UiI18n.tr_key("UI_REPORT_TITLE", {"day": day_num})
	_lbl_subtitle.text = UiI18n.tr_key("UI_REPORT_SUBTITLE")
	_lbl_pnl_header.text = UiI18n.tr_key("UI_REPORT_PNL_HEADER")
	_lbl_bs_header.text = UiI18n.tr_key("UI_REPORT_BS_HEADER")
	_lbl_drivers_header.text = UiI18n.tr_key("UI_REPORT_DRIVERS_HEADER")
	_btn_next_day.text = UiI18n.tr_key("UI_REPORT_BTN_NEXT_DAY")

	_clear_box(_pnl_rows_box)
	_add_kv_row(_pnl_rows_box, UiI18n.tr_key("UI_REPORT_LOAN_INT_INC"), FormatService.format_money(int(rep.get("loan_interest_income", 0)), "CNY", true, lc), StarwayTheme.GREEN_500)
	_add_kv_row(_pnl_rows_box, UiI18n.tr_key("UI_REPORT_FEE_INC"), FormatService.format_money(int(rep.get("fee_income", 0)), "CNY", true, lc), StarwayTheme.GREEN_500)
	_add_kv_row(_pnl_rows_box, UiI18n.tr_key("UI_REPORT_DEP_INT_EXP"), FormatService.format_money(-int(rep.get("deposit_interest_expense", 0)), "CNY", true, lc), StarwayTheme.RED_500)
	_add_kv_row(_pnl_rows_box, UiI18n.tr_key("UI_REPORT_STAFF_COST"), FormatService.format_money(-int(rep.get("staff_cost", 0)), "CNY", true, lc), StarwayTheme.RED_500)
	_add_kv_row(_pnl_rows_box, UiI18n.tr_key("UI_REPORT_FACILITY_COST"), FormatService.format_money(-int(rep.get("facility_cost", 0)), "CNY", true, lc), StarwayTheme.RED_500)
	_add_kv_row(_pnl_rows_box, UiI18n.tr_key("UI_REPORT_DEPT_COST"), FormatService.format_money(-int(rep.get("department_cost", 0)), "CNY", true, lc), StarwayTheme.RED_500)
	_add_kv_row(_pnl_rows_box, UiI18n.tr_key("UI_REPORT_CREDIT_LOSS"), FormatService.format_money(-int(rep.get("credit_loss_expense", 0)), "CNY", true, lc), StarwayTheme.RED_500)
	_add_kv_row(_pnl_rows_box, UiI18n.tr_key("UI_REPORT_EVENT_EXP"), FormatService.format_money(-int(rep.get("event_expense", 0)), "CNY", true, lc), StarwayTheme.RED_500)
	_pnl_rows_box.add_child(HSeparator.new())
	var net_p: int = int(rep.get("net_profit", 0))
	_add_kv_row(_pnl_rows_box, UiI18n.tr_key("UI_REPORT_NET_PROFIT"), FormatService.format_money(net_p, "CNY", true, lc), StarwayTheme.delta_color(net_p))

	_clear_box(_bs_rows_box)
	_add_kv_row(_bs_rows_box, UiI18n.tr_key("UI_FINANCE_CASH"), FormatService.format_money(int(rep.get("cash_reserves", 20_000_000)), "CNY", false, lc), StarwayTheme.GOLD_500)
	_add_kv_row(_bs_rows_box, UiI18n.tr_key("UI_FINANCE_LOANS"), FormatService.format_money(int(rep.get("loan_principal_outstanding", 0)), "CNY", false, lc), StarwayTheme.ICE_100)
	_add_kv_row(_bs_rows_box, UiI18n.tr_key("UI_FINANCE_DEPOSITS"), FormatService.format_money(int(rep.get("customer_deposits", 0)), "CNY", false, lc), StarwayTheme.ICE_100)
	_add_kv_row(_bs_rows_box, UiI18n.tr_key("UI_FINANCE_RETAINED"), FormatService.format_money(int(rep.get("retained_earnings", 0)), "CNY", true, lc), StarwayTheme.delta_color(int(rep.get("retained_earnings", 0))))
	var liq_status: int = int(rep.get("liquidity_status", Enums.LiquidityStatus.SAFE))
	_add_kv_row(_bs_rows_box, UiI18n.tr_key("UI_INSPECTOR_LIQUIDITY"), UiI18n.tr_liquidity_status(liq_status), StarwayTheme.GREEN_500 if liq_status == Enums.LiquidityStatus.SAFE else StarwayTheme.RED_500)
	var npl_bps: int = int(round(float(rep.get("npl_ratio", 0.0)) * 10000.0))
	_add_kv_row(_bs_rows_box, UiI18n.tr_key("UI_INSPECTOR_NPL"), FormatService.format_bps(npl_bps), StarwayTheme.ICE_100)
	_add_kv_row(_bs_rows_box, UiI18n.tr_key("UI_TOPBAR_SATISFACTION"), "%d / 100" % int(rep.get("satisfaction", 75)), StarwayTheme.ICE_100)
	_add_kv_row(_bs_rows_box, UiI18n.tr_key("UI_TOPBAR_REPUTATION"), "%d / 100" % int(rep.get("reputation", 50)), StarwayTheme.ICE_100)

	_clear_box(_drivers_box)
	var dkeys: Array = rep.get("driver_keys", ["REPORT_DRIVER_PAYROLL_COST"]) as Array
	if dkeys.is_empty():
		dkeys = ["REPORT_DRIVER_PAYROLL_COST"]
	for dk in dkeys:
		var dlbl := Label.new()
		dlbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dlbl.text = "• " + UiI18n.tr_key(str(dk))
		_drivers_box.add_child(dlbl)


static func _clear_box(box: Node) -> void:
	if box == null:
		return
	for c in box.get_children():
		box.remove_child(c)
		c.free()


static func _add_kv_row(parent: Node, label_txt: String, val_txt: String, val_color: Color) -> void:
	var row := HBoxContainer.new()
	var k := Label.new()
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.text = label_txt
	row.add_child(k)

	var v := Label.new()
	v.theme_type_variation = &"LabelValue"
	v.add_theme_color_override("font_color", val_color)
	v.text = val_txt
	row.add_child(v)
	parent.add_child(row)


func _on_next_day_pressed() -> void:
	UiI18n.play_sfx("sfx_day_complete")
	visible = false
	next_day_requested.emit()
