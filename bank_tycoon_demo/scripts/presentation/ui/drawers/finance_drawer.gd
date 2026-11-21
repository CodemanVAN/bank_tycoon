extends PanelContainer

## Finance & Balance Sheet Drawer (includes custom _draw() FinanceChart and Interest Rate sliders).

signal close_requested()
signal command_executed(res: Variant, action_key: String)

var _sim_host: Node = null
var _lbl_title: Label = null
var _lbl_subtitle: Label = null
var _btn_close: Button = null

var _lbl_bs_header: Label = null
var _bs_rows_box: VBoxContainer = null
var _lbl_balance_badge: Label = null

var _lbl_rates_header: Label = null
var _lbl_dep_rate: Label = null
var _slider_dep_rate: HSlider = null
var _lbl_loan_rate: Label = null
var _slider_loan_rate: HSlider = null
var _btn_apply_rates: Button = null

var _lbl_chart_header: Label = null
var _lbl_chart_legend: Label = null
var _chart: FinanceChart = null

var _pending_dep_bps: int = BalanceConfig.DEFAULT_DEPOSIT_RATE_BPS
var _pending_loan_bps: int = BalanceConfig.DEFAULT_LOAN_BASE_RATE_BPS


func _ready() -> void:
	theme_type_variation = &"PanelLarge"
	_build_ui()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func bind(p_sim_host: Node) -> void:
	_sim_host = p_sim_host
	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	if bs != null:
		_pending_dep_bps = bs.deposit_rate_bps
		_pending_loan_bps = bs.loan_base_rate_bps
		if _slider_dep_rate != null:
			_slider_dep_rate.set_value_no_signal(float(_pending_dep_bps))
		if _slider_loan_rate != null:
			_slider_loan_rate.set_value_no_signal(float(_pending_loan_bps))
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

	var body_cols := HBoxContainer.new()
	body_cols.add_theme_constant_override("separation", 14)
	body_cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(body_cols)

	# Left Column: Balance Sheet & Interest Rates
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 10)
	body_cols.add_child(left_col)

	var bs_card := PanelContainer.new()
	bs_card.theme_type_variation = &"PanelCard"
	left_col.add_child(bs_card)

	var bs_v := VBoxContainer.new()
	bs_v.add_theme_constant_override("separation", 4)
	bs_card.add_child(bs_v)

	_lbl_bs_header = Label.new()
	_lbl_bs_header.theme_type_variation = &"LabelTitle"
	bs_v.add_child(_lbl_bs_header)

	_bs_rows_box = VBoxContainer.new()
	_bs_rows_box.add_theme_constant_override("separation", 4)
	bs_v.add_child(_bs_rows_box)

	_lbl_balance_badge = Label.new()
	bs_v.add_child(_lbl_balance_badge)

	var rates_card := PanelContainer.new()
	rates_card.theme_type_variation = &"PanelCard"
	left_col.add_child(rates_card)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	rates_card.add_child(rv)

	_lbl_rates_header = Label.new()
	_lbl_rates_header.theme_type_variation = &"LabelTitle"
	rv.add_child(_lbl_rates_header)

	_lbl_dep_rate = Label.new()
	rv.add_child(_lbl_dep_rate)

	_slider_dep_rate = HSlider.new()
	_slider_dep_rate.min_value = float(BalanceConfig.MIN_DEPOSIT_RATE_BPS)
	_slider_dep_rate.max_value = float(BalanceConfig.MAX_DEPOSIT_RATE_BPS)
	_slider_dep_rate.step = 25.0
	_slider_dep_rate.value = float(_pending_dep_bps)
	_slider_dep_rate.value_changed.connect(func(v: float) -> void:
		_pending_dep_bps = int(round(v))
		_lbl_dep_rate.text = UiI18n.tr_key("UI_FINANCE_DEPOSIT_RATE", {"rate": FormatService.format_bps(_pending_dep_bps)})
	)
	rv.add_child(_slider_dep_rate)

	_lbl_loan_rate = Label.new()
	rv.add_child(_lbl_loan_rate)

	_slider_loan_rate = HSlider.new()
	_slider_loan_rate.min_value = float(BalanceConfig.MIN_LOAN_RATE_BPS)
	_slider_loan_rate.max_value = float(BalanceConfig.MAX_LOAN_RATE_BPS)
	_slider_loan_rate.step = 25.0
	_slider_loan_rate.value = float(_pending_loan_bps)
	_slider_loan_rate.value_changed.connect(func(v: float) -> void:
		_pending_loan_bps = int(round(v))
		_lbl_loan_rate.text = UiI18n.tr_key("UI_FINANCE_LOAN_RATE", {"rate": FormatService.format_bps(_pending_loan_bps)})
	)
	rv.add_child(_slider_loan_rate)

	_btn_apply_rates = Button.new()
	_btn_apply_rates.theme_type_variation = &"ButtonPrimary"
	_btn_apply_rates.pressed.connect(_on_apply_rates_pressed)
	rv.add_child(_btn_apply_rates)

	# Right Column: Custom _draw() Finance Trend Chart
	var chart_card := PanelContainer.new()
	chart_card.theme_type_variation = &"PanelCard"
	chart_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_cols.add_child(chart_card)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	chart_card.add_child(cv)

	_lbl_chart_header = Label.new()
	_lbl_chart_header.theme_type_variation = &"LabelTitle"
	cv.add_child(_lbl_chart_header)

	_lbl_chart_legend = Label.new()
	_lbl_chart_legend.theme_type_variation = &"LabelMuted"
	cv.add_child(_lbl_chart_legend)

	_chart = FinanceChart.new()
	_chart.name = "FinanceTrendChart"
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(_chart)


func refresh() -> void:
	if _lbl_title == null:
		return

	_lbl_title.text = UiI18n.tr_key("UI_DRAWER_FINANCE_TITLE")
	_lbl_subtitle.text = UiI18n.tr_key("UI_DRAWER_FINANCE_SUBTITLE")
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")
	_lbl_bs_header.text = UiI18n.tr_key("UI_FINANCE_BS_HEADER")
	_lbl_rates_header.text = UiI18n.tr_key("UI_FINANCE_RATES_HEADER")
	_btn_apply_rates.text = UiI18n.tr_key("UI_FINANCE_BTN_APPLY_RATES")
	_lbl_chart_header.text = UiI18n.tr_key("UI_FINANCE_CHART_HEADER")
	_lbl_chart_legend.text = UiI18n.tr_key("UI_FINANCE_CHART_LEGEND")

	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var lc: String = UiI18n.get_locale()
	var ccy: String = bs.currency_code if bs != null else "CNY"

	_lbl_dep_rate.text = UiI18n.tr_key("UI_FINANCE_DEPOSIT_RATE", {"rate": FormatService.format_bps(_pending_dep_bps)})
	_lbl_loan_rate.text = UiI18n.tr_key("UI_FINANCE_LOAN_RATE", {"rate": FormatService.format_bps(_pending_loan_bps)})

	for c in _bs_rows_box.get_children():
		_bs_rows_box.remove_child(c)
		c.free()

	var snap_bs: Dictionary = bs.ledger.get_balance_sheet_snapshot() if (bs != null and bs.ledger != null) else {
		"assets": 20_000_000,
		"liabilities": 0,
		"equity": 20_000_000,
		"net_income": 0,
		"is_balanced": true,
		"accounts": {
			"cash_reserves": 20_000_000,
			"loan_principal_outstanding": 0,
			"customer_deposits": 0,
			"equity_capital": 20_000_000,
			"retained_earnings": 0,
		},
	}
	var accts: Dictionary = snap_bs.get("accounts", {}) as Dictionary
	_add_bs_row(UiI18n.tr_key("UI_FINANCE_CASH"), FormatService.format_money(int(accts.get("cash_reserves", 20_000_000)), ccy, false, lc), StarwayTheme.GOLD_500)
	_add_bs_row(UiI18n.tr_key("UI_FINANCE_LOANS"), FormatService.format_money(int(accts.get("loan_principal_outstanding", 0)), ccy, false, lc), StarwayTheme.ICE_100)
	_add_bs_row(UiI18n.tr_key("UI_FINANCE_DEPOSITS"), FormatService.format_money(int(accts.get("customer_deposits", 0)), ccy, false, lc), StarwayTheme.ICE_100)
	_add_bs_row(UiI18n.tr_key("UI_FINANCE_EQUITY_CAP"), FormatService.format_money(int(accts.get("equity_capital", 20_000_000)), ccy, false, lc), StarwayTheme.ICE_100)
	var ret_val: int = int(accts.get("retained_earnings", 0)) + int(snap_bs.get("net_income", 0))
	_add_bs_row(UiI18n.tr_key("UI_FINANCE_RETAINED"), FormatService.format_money(ret_val, ccy, true, lc), StarwayTheme.delta_color(ret_val))

	var is_bal: bool = bool(snap_bs.get("is_balanced", true))
	_lbl_balance_badge.text = UiI18n.tr_key("UI_FINANCE_BALANCED" if is_bal else "UI_FINANCE_UNBALANCED")
	_lbl_balance_badge.add_theme_color_override("font_color", StarwayTheme.GREEN_500 if is_bal else StarwayTheme.RED_500)

	# Populate chart points
	var pts: Array[Dictionary] = []
	if bs != null:
		for rep in bs.daily_reports:
			var inc: int = int(rep.get("loan_interest_income", 0)) + int(rep.get("fee_income", 0))
			var exp_val: int = int(rep.get("deposit_interest_expense", 0)) + int(rep.get("operating_expense", 0)) + int(rep.get("credit_loss_expense", 0)) + int(rep.get("event_expense", 0))
			pts.append({
				"day": int(rep.get("day", 1)),
				"income": inc,
				"expense": exp_val,
				"net": int(rep.get("net_profit", inc - exp_val)),
			})
	if _chart != null:
		_chart.set_series(pts)


func _add_bs_row(label_txt: String, val_txt: String, col: Color) -> void:
	var row := HBoxContainer.new()
	var k := Label.new()
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.text = label_txt
	row.add_child(k)

	var v := Label.new()
	v.theme_type_variation = &"LabelValue"
	v.add_theme_color_override("font_color", col)
	v.text = val_txt
	row.add_child(v)
	_bs_rows_box.add_child(row)


func _on_apply_rates_pressed() -> void:
	UiI18n.play_sfx("sfx_ui_click")
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd != null and (cmd as Object).has_method("set_interest_rates"):
		var r: Variant = (cmd as Object).call("set_interest_rates", _pending_dep_bps, _pending_loan_bps)
		command_executed.emit(r, "UI_FINANCE_BTN_APPLY_RATES")
		refresh()
