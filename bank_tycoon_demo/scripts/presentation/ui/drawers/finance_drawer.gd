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
var _lbl_repay_header: Label = null
var _repay_mode_row: HBoxContainer = null
var _lbl_repay_hint: Label = null

var _lbl_chart_header: Label = null
var _lbl_chart_legend: Label = null
var _chart: FinanceChart = null
var _lbl_loans_header: Label = null
var _loans_list_box: VBoxContainer = null
var _loans_rebuild_pending: bool = false

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

	rv.add_child(HSeparator.new())

	_lbl_repay_header = Label.new()
	_lbl_repay_header.theme_type_variation = &"LabelTitle"
	rv.add_child(_lbl_repay_header)

	_repay_mode_row = HBoxContainer.new()
	_repay_mode_row.add_theme_constant_override("separation", 6)
	rv.add_child(_repay_mode_row)

	_lbl_repay_hint = Label.new()
	_lbl_repay_hint.theme_type_variation = &"LabelMuted"
	_lbl_repay_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_repay_hint.add_theme_font_size_override("font_size", 11)
	rv.add_child(_lbl_repay_hint)

	# Right Column: Custom _draw() Finance Trend Chart + Loan Portfolio & Bad Debt Write-Off Ledger
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 10)
	body_cols.add_child(right_col)

	var chart_card := PanelContainer.new()
	chart_card.theme_type_variation = &"PanelCard"
	chart_card.custom_minimum_size = Vector2(0.0, 210.0)
	right_col.add_child(chart_card)

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

	var loans_card := PanelContainer.new()
	loans_card.name = "LoanPortfolioCard"
	loans_card.theme_type_variation = &"PanelCard"
	loans_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(loans_card)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	loans_card.add_child(lv)

	_lbl_loans_header = Label.new()
	_lbl_loans_header.theme_type_variation = &"LabelTitle"
	lv.add_child(_lbl_loans_header)

	var lscroll := ScrollContainer.new()
	lscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(lscroll)

	_loans_list_box = VBoxContainer.new()
	_loans_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loans_list_box.add_theme_constant_override("separation", 6)
	lscroll.add_child(_loans_list_box)


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

	UiListRefresh.clear_children(_bs_rows_box)

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

	# Populate Loan Repayment Mode Selector (default equal_installment; policy unlocks interest_first & principal_first)
	if _repay_mode_row != null and _lbl_repay_header != null:
		_lbl_repay_header.text = UiI18n.tr_key("UI_FINANCE_REPAY_MODE_HEADER")
		var unlocked_flex: bool = bs != null and bs.adopted_policies.has("core:policy.flexible_repayment")
		var cur_mode: String = bs.loan_repayment_mode if bs != null else "equal_installment"
		_lbl_repay_hint.text = UiI18n.tr_key("UI_FINANCE_REPAY_UNLOCKED_HINT" if unlocked_flex else "UI_FINANCE_REPAY_LOCKED_HINT")
		UiListRefresh.clear_children(_repay_mode_row)
		for m_pair in [
			["equal_installment", "UI_REPAY_MODE_EQUAL"],
			["interest_first", "UI_REPAY_MODE_INT_FIRST"],
			["principal_first", "UI_REPAY_MODE_PRIN_FIRST"],
		]:
			var mid: String = m_pair[0]
			var mb := Button.new()
			mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mb.add_theme_font_size_override("font_size", 11)
			mb.text = UiI18n.tr_key(m_pair[1])
			if mid == cur_mode:
				mb.theme_type_variation = &"ButtonPrimary"
			if mid != "equal_installment" and not unlocked_flex:
				mb.disabled = true
			var mid_copy: String = mid
			mb.pressed.connect(func() -> void:
				UiI18n.play_sfx("sfx_ui_click")
				if _sim_host != null:
					var cmd: Variant = _sim_host.get("command_service")
					if cmd != null and (cmd as Object).has_method("set_loan_repayment_mode"):
						var r: Variant = (cmd as Object).call("set_loan_repayment_mode", mid_copy)
						command_executed.emit(r, "UI_FINANCE_REPAY_MODE_HEADER")
						refresh.call_deferred()
			)
			_repay_mode_row.add_child(mb)

	# Populate Loan Portfolio Ledger (borrower identity, daily repayment progress, & bad-debt write-off)
	_refresh_loan_portfolio(bs, ccy)


func _refresh_loan_portfolio(bs: BankState, ccy: String) -> void:
	if _loans_list_box == null or _lbl_loans_header == null:
		return
	var loan_ids: Array[String] = []
	if bs != null:
		for lid_v: Variant in bs.loans.keys():
			loan_ids.append(str(lid_v))
		loan_ids.sort()
	_lbl_loans_header.text = UiI18n.tr_key("UI_FINANCE_LOAN_LEDGER_HEADER", {"count": loan_ids.size()})

	if UiListRefresh.any_button_held(_loans_list_box):
		_loans_rebuild_pending = true
		return
	UiListRefresh.clear_children(_loans_list_box)

	if loan_ids.is_empty():
		var el := Label.new()
		el.theme_type_variation = &"LabelMuted"
		el.add_theme_font_size_override("font_size", 12)
		el.text = UiI18n.tr_key("UI_FINANCE_LOAN_LEDGER_EMPTY")
		_loans_list_box.add_child(el)
		return

	for lid: String in loan_ids:
		var ln: LoanInstance = bs.loans[lid] as LoanInstance
		if ln == null:
			continue
		var row_card := PanelContainer.new()
		var rsb := StyleBoxFlat.new()
		var is_overdue: bool = (ln.is_npl() or ln.days_past_due > 0) and ln.principal_outstanding > 0
		rsb.bg_color = Color(0.22, 0.08, 0.10, 0.90) if is_overdue else Color(0.05, 0.14, 0.26, 0.90)
		rsb.border_color = Color("#FF5C5C") if is_overdue else Color("#1F6FEB")
		rsb.set_border_width_all(1)
		rsb.set_corner_radius_all(5)
		rsb.content_margin_left = 8
		rsb.content_margin_right = 8
		rsb.content_margin_top = 6
		rsb.content_margin_bottom = 6
		row_card.add_theme_stylebox_override("panel", rsb)
		_loans_list_box.add_child(row_card)

		var rv := VBoxContainer.new()
		rv.add_theme_constant_override("separation", 3)
		row_card.add_child(rv)

		var top_h := HBoxContainer.new()
		top_h.add_theme_constant_override("separation", 6)
		rv.add_child(top_h)

		var bname: String = ln.borrower_name if not ln.borrower_name.is_empty() else LoanInstance.generate_borrower_name(ln.customer_id, ln.customer_type)
		var bl := Label.new()
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bl.add_theme_font_size_override("font_size", 12)
		bl.text = "%s (%s) · %s级 · %s" % [
			bname,
			UiI18n.tr_customer_type(ln.customer_type),
			ln.get_risk_grade_code(),
			FormatService.format_bps(ln.annual_rate_bps),
		]
		top_h.add_child(bl)

		var st_lbl := Label.new()
		st_lbl.add_theme_font_size_override("font_size", 11)
		if ln.status == Enums.LoanStatus.REPAID:
			st_lbl.add_theme_color_override("font_color", Color("#35C978"))
			st_lbl.text = UiI18n.tr_key("UI_LOAN_STATUS_REPAID")
		elif ln.status == Enums.LoanStatus.WRITTEN_OFF:
			st_lbl.add_theme_color_override("font_color", Color("#FF9999"))
			st_lbl.text = UiI18n.tr_key("UI_LOAN_STATUS_WRITTEN_OFF")
		elif is_overdue:
			st_lbl.add_theme_color_override("font_color", Color("#FF5C5C"))
			st_lbl.text = UiI18n.tr_key("UI_LOAN_STATUS_OVERDUE", {"days": maxi(1, ln.days_past_due)})
		else:
			st_lbl.add_theme_color_override("font_color", Color("#7FD8FF"))
			st_lbl.text = UiI18n.tr_key("UI_LOAN_STATUS_ACTIVE")
		top_h.add_child(st_lbl)

		var det := Label.new()
		det.add_theme_font_size_override("font_size", 11)
		det.add_theme_color_override("font_color", Color("#BBD2F5"))
		det.text = UiI18n.tr_key("UI_FINANCE_LOAN_REPAY_LINE", {
			"repaid": FormatService.format_money_compact(ln.total_principal_repaid_minor, ccy, false),
			"orig": FormatService.format_money_compact(ln.principal_original, ccy, false),
			"interest": FormatService.format_money_compact(ln.total_interest_paid_minor, ccy, false),
			"elapsed": mini(ln.days_elapsed, ln.term_days),
			"term": ln.term_days,
		})
		rv.add_child(det)

		var prog_row := HBoxContainer.new()
		prog_row.add_theme_constant_override("separation", 6)
		rv.add_child(prog_row)

		var pb := ProgressBar.new()
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.custom_minimum_size = Vector2(0.0, 7.0)
		pb.min_value = 0.0
		pb.max_value = float(maxi(1, ln.principal_original))
		pb.value = float(ln.total_principal_repaid_minor)
		pb.show_percentage = false
		var pfill := StyleBoxFlat.new()
		pfill.bg_color = Color("#FF5C5C") if is_overdue else Color("#35C978")
		pfill.set_corner_radius_all(3)
		pb.add_theme_stylebox_override("fill", pfill)
		prog_row.add_child(pb)

		if is_overdue:
			var wbtn := Button.new()
			wbtn.theme_type_variation = &"ButtonDanger"
			wbtn.add_theme_font_size_override("font_size", 11)
			wbtn.text = UiI18n.tr_key("UI_LOAN_BTN_WRITEOFF")
			var lid_copy: String = lid
			wbtn.pressed.connect(func() -> void:
				UiI18n.play_sfx("sfx_ui_click")
				if _sim_host != null:
					var cmd: Variant = _sim_host.get("command_service")
					if cmd != null and (cmd as Object).has_method("write_off_bad_loan"):
						var r: Variant = (cmd as Object).call("write_off_bad_loan", lid_copy)
						command_executed.emit(r, "UI_LOAN_WRITEOFF_OK")
						refresh.call_deferred()
			)
			prog_row.add_child(wbtn)

	UiListRefresh.watch_tree(_loans_list_box, func() -> void:
		if _loans_rebuild_pending:
			_loans_rebuild_pending = false
			refresh.call_deferred()
	)


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
