extends PanelContainer

## Executive Branch Overview Drawer.

signal close_requested()
signal command_executed(res: Variant, action_key: String)
signal navigate_requested(drawer_id: StringName)

var _sim_host: Node = null
var _lbl_title: Label = null
var _lbl_subtitle: Label = null
var _btn_close: Button = null
var _metrics_box: VBoxContainer = null
var _quick_nav_box: HBoxContainer = null


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

	_metrics_box = VBoxContainer.new()
	_metrics_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_metrics_box.add_theme_constant_override("separation", 8)
	root_v.add_child(_metrics_box)

	_quick_nav_box = HBoxContainer.new()
	_quick_nav_box.add_theme_constant_override("separation", 8)
	root_v.add_child(_quick_nav_box)


func refresh() -> void:
	if _lbl_title == null:
		return

	_lbl_title.text = UiI18n.tr_key("UI_DRAWER_OVERVIEW_TITLE")
	_lbl_subtitle.text = UiI18n.tr_key("UI_DRAWER_OVERVIEW_SUBTITLE")
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")

	UiListRefresh.clear_children(_metrics_box)

	var snap: Dictionary = {}
	if _sim_host != null and _sim_host.has_method("get_snapshot"):
		snap = _sim_host.call("get_snapshot") as Dictionary
	var lc: String = UiI18n.get_locale()

	_add_metric_row(UiI18n.tr_key("UI_FINANCE_CASH"), FormatService.format_money(int(snap.get("cash_minor", 20_000_000)), "CNY", false, lc), StarwayTheme.GOLD_500)
	_add_metric_row(UiI18n.tr_key("UI_FINANCE_LOANS"), FormatService.format_money(int(snap.get("loans_minor", 0)), "CNY", false, lc), StarwayTheme.ICE_100)
	_add_metric_row(UiI18n.tr_key("UI_FINANCE_DEPOSITS"), FormatService.format_money(int(snap.get("deposits_minor", 0)), "CNY", false, lc), StarwayTheme.ICE_100)
	var net_p: int = int(snap.get("today_profit_minor", 0))
	_add_metric_row(UiI18n.tr_key("UI_TOPBAR_TODAY_PROFIT"), FormatService.format_money(net_p, "CNY", true, lc), StarwayTheme.delta_color(net_p))
	_add_metric_row(UiI18n.tr_key("UI_TOPBAR_SATISFACTION"), "%d / 100" % int(snap.get("satisfaction", 75)), StarwayTheme.ICE_100)
	_add_metric_row(UiI18n.tr_key("UI_TOPBAR_REPUTATION"), "%d / 100" % int(snap.get("reputation", 50)), StarwayTheme.ICE_100)
	_add_metric_row(UiI18n.tr_key("UI_POLICY_POINTS", {"points": int(snap.get("strategy_points", 10))}), str(int(snap.get("strategy_points", 10))), StarwayTheme.CYAN_500)
	var liq_s: int = int(snap.get("liquidity_status", Enums.LiquidityStatus.SAFE))
	_add_metric_row(UiI18n.tr_key("UI_INSPECTOR_LIQUIDITY"), UiI18n.tr_liquidity_status(liq_s), StarwayTheme.GREEN_500 if liq_s == Enums.LiquidityStatus.SAFE else StarwayTheme.RED_500)
	_add_metric_row(UiI18n.tr_key("UI_INSPECTOR_NPL"), FormatService.format_bps(int(snap.get("npl_ratio_bps", 0))), StarwayTheme.ICE_100)

	UiListRefresh.clear_children(_quick_nav_box)

	for pair in [
		[&"finance", "UI_NAV_FINANCE"],
		[&"employees", "UI_NAV_EMPLOYEES"],
		[&"departments", "UI_NAV_DEPARTMENTS"],
		[&"policies", "UI_NAV_POLICIES"],
		[&"events", "UI_NAV_EVENTS"],
	]:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = UiI18n.tr_key(str(pair[1]))
		var target_id: StringName = pair[0] as StringName
		btn.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			navigate_requested.emit(target_id)
		)
		_quick_nav_box.add_child(btn)


func _add_metric_row(label_txt: String, val_txt: String, col: Color) -> void:
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
	_metrics_box.add_child(row)
