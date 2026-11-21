extends PanelContainer

## Organization & Departments Drawer (4 Core Departments + Mod Departments + Cross-Department Synergies).

signal close_requested()
signal command_executed(res: Variant, action_key: String)
signal placement_requested(dept_id: String)

var _sim_host: Node = null
var _lbl_title: Label = null
var _lbl_subtitle: Label = null
var _btn_close: Button = null
var _lbl_syn_hdr: Label = null
var _lbl_syn_hr_ops: Label = null
var _lbl_syn_cred_risk: Label = null
var _dept_grid: GridContainer = null

var _grid_signature: String = ""
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

	# Synergy Banner
	var syn_card := PanelContainer.new()
	syn_card.theme_type_variation = &"PanelCard"
	root_v.add_child(syn_card)

	var syn_v := VBoxContainer.new()
	syn_v.add_theme_constant_override("separation", 4)
	syn_card.add_child(syn_v)

	_lbl_syn_hdr = Label.new()
	_lbl_syn_hdr.theme_type_variation = &"LabelTitle"
	syn_v.add_child(_lbl_syn_hdr)

	_lbl_syn_hr_ops = Label.new()
	syn_v.add_child(_lbl_syn_hr_ops)

	_lbl_syn_cred_risk = Label.new()
	syn_v.add_child(_lbl_syn_cred_risk)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	_dept_grid = GridContainer.new()
	_dept_grid.columns = 2
	_dept_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dept_grid.add_theme_constant_override("h_separation", 12)
	_dept_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_dept_grid)


func refresh() -> void:
	if _lbl_title == null:
		return

	_lbl_title.text = UiI18n.tr_key("UI_DRAWER_DEPARTMENTS_TITLE")
	_lbl_subtitle.text = UiI18n.tr_key("UI_DRAWER_DEPARTMENTS_SUBTITLE")
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")
	_lbl_syn_hdr.text = UiI18n.tr_key("UI_DEPT_SYNERGY_HEADER")

	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var dept_svc := DepartmentService.new()
	var syn_hr_ops: bool = dept_svc.is_capability_unlocked(bs, "synergy:hr_operations") if bs != null else false
	var syn_cred_risk: bool = dept_svc.is_capability_unlocked(bs, "synergy:credit_risk") if bs != null else false

	_lbl_syn_hr_ops.text = "%s %s" % [
		UiI18n.tr_key("UI_DEPT_SYNERGY_ACTIVE" if syn_hr_ops else "UI_DEPT_SYNERGY_INACTIVE"),
		UiI18n.tr_key("UI_DEPT_SYNERGY_HR_OPS"),
	]
	_lbl_syn_hr_ops.add_theme_color_override("font_color", StarwayTheme.GREEN_500 if syn_hr_ops else StarwayTheme.ICE_100)

	_lbl_syn_cred_risk.text = "%s %s" % [
		UiI18n.tr_key("UI_DEPT_SYNERGY_ACTIVE" if syn_cred_risk else "UI_DEPT_SYNERGY_INACTIVE"),
		UiI18n.tr_key("UI_DEPT_SYNERGY_CREDIT_RISK"),
	]
	_lbl_syn_cred_risk.add_theme_color_override("font_color", StarwayTheme.GREEN_500 if syn_cred_risk else StarwayTheme.ICE_100)

	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
	var dept_defs: Array = defs.get("departments", []) as Array
	var lc: String = UiI18n.get_locale()
	var ccy: String = bs.currency_code if bs != null else "CNY"

	# Rebuilding rows on every snapshot destroyed the pressed Button between press and
	# release (the "needs several clicks" defect). Only rebuild when the structure changed,
	# and never while a row button is held.
	var sig_parts: Array = [lc, ccy]
	for raw_d in dept_defs:
		if raw_d is Dictionary:
			var ddef_sig: Dictionary = raw_d as Dictionary
			var did_sig: String = str(ddef_sig.get("id", ""))
			var lvl_sig: int = dept_svc.get_department_level(bs, did_sig) if bs != null else 0
			sig_parts.append("%s:%d:%d:%d" % [
				did_sig,
				lvl_sig,
				int(ddef_sig.get("initial_cost_minor", 0)),
				int(ddef_sig.get("daily_cost_minor", 0)),
			])
	var new_sig: String = UiListRefresh.signature(sig_parts)
	if new_sig == _grid_signature and _dept_grid.get_child_count() > 0:
		return
	if UiListRefresh.any_button_held(_dept_grid):
		_rebuild_pending = true
		return
	_grid_signature = new_sig
	UiListRefresh.clear_children(_dept_grid)

	for raw_d in dept_defs:
		if not (raw_d is Dictionary):
			continue
		var ddef: Dictionary = raw_d as Dictionary
		var dept_id: String = str(ddef.get("id", ""))
		var cur_lvl: int = dept_svc.get_department_level(bs, dept_id) if bs != null else 0
		var max_lvl: int = maxi(1, int(ddef.get("max_level", 3)))
		var init_cost: int = int(ddef.get("initial_cost_minor", 200_000))
		var daily_cost: int = int(ddef.get("daily_cost_minor", 15_000))
		var upg_cost: int = BalanceConfig.calc_department_upgrade_cost(init_cost, cur_lvl)

		var card := PanelContainer.new()
		card.theme_type_variation = &"PanelCard"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_dept_grid.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)

		var name_l := Label.new()
		name_l.theme_type_variation = &"LabelTitle"
		name_l.text = UiI18n.tr_key(str(ddef.get("name_key", dept_id)))
		cv.add_child(name_l)

		var lvl_l := Label.new()
		lvl_l.text = UiI18n.tr_key("UI_DEPT_LEVEL_FORMAT", {"level": cur_lvl, "max": max_lvl}) if cur_lvl > 0 else UiI18n.tr_key("UI_DEPT_NOT_CREATED")
		lvl_l.add_theme_color_override("font_color", StarwayTheme.CYAN_500 if cur_lvl > 0 else StarwayTheme.GOLD_500)
		cv.add_child(lvl_l)

		var desc_l := Label.new()
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_l.theme_type_variation = &"LabelMuted"
		desc_l.text = UiI18n.tr_key(str(ddef.get("description_key", "")))
		cv.add_child(desc_l)

		var cost_l := Label.new()
		cost_l.text = UiI18n.tr_key("UI_DEPT_DAILY_COST", {"cost": FormatService.format_money(daily_cost, ccy, false, lc)})
		cv.add_child(cost_l)

		# Level unlock descriptions
		var ukeys: Array = _get_dept_unlock_keys(dept_id, ddef)
		for uk in ukeys:
			var ul := Label.new()
			ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ul.text = "• " + UiI18n.tr_key(str(uk))
			cv.add_child(ul)

		var btn := Button.new()
		if cur_lvl <= 0:
			btn.theme_type_variation = &"ButtonPrimary"
			btn.text = UiI18n.tr_key("UI_DEPT_BTN_CHOOSE_PLOT", {"cost": FormatService.format_money(init_cost, ccy, false, lc)})
			btn.pressed.connect(func() -> void:
				UiI18n.play_sfx("sfx_ui_click")
				# Real construction: the player picks the plot in the lobby first.
				placement_requested.emit(dept_id)
			)
		elif cur_lvl < max_lvl:
			btn.theme_type_variation = &"ButtonGold"
			btn.text = UiI18n.tr_key("UI_DEPT_BTN_UPGRADE", {
				"next": cur_lvl + 1,
				"cost": FormatService.format_money(upg_cost, ccy, false, lc),
			})
			btn.pressed.connect(func() -> void:
				UiI18n.play_sfx("sfx_ui_click")
				_exec_cmd("upgrade_department", [dept_id], "UI_DEPT_BTN_UPGRADE")
			)
		else:
			btn.text = UiI18n.tr_key("UI_DEPT_BTN_MAX_LEVEL")
			btn.disabled = true
		UiListRefresh.watch_release(btn, _on_list_button_up)
		cv.add_child(btn)


static func _get_dept_unlock_keys(dept_id: String, ddef: Dictionary) -> Array:
	if ddef.has("unlock_keys") and ddef["unlock_keys"] is Array:
		return ddef["unlock_keys"] as Array
	match dept_id:
		"core:department.operations":
			return ["DEPT_OPERATIONS_LV1", "DEPT_OPERATIONS_LV2", "DEPT_OPERATIONS_LV3"]
		"core:department.hr":
			return ["DEPT_HR_LV1", "DEPT_HR_LV2", "DEPT_HR_LV3"]
		"core:department.credit":
			return ["DEPT_CREDIT_LV1", "DEPT_CREDIT_LV2", "DEPT_CREDIT_LV3"]
		"core:department.risk":
			return ["DEPT_RISK_LV1", "DEPT_RISK_LV2", "DEPT_RISK_LV3"]
		_:
			return []


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
		if r is Result and (r as Result).ok:
			UiI18n.play_sfx("sfx_upgrade_success")
		command_executed.emit(r, action_key)
		refresh.call_deferred()
