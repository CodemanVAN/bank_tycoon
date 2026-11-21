extends PanelContainer

## Bank Doctrine & Strategic Policy Tree Drawer (Conservative vs Aggressive mutually exclusive branches).

signal close_requested()
signal command_executed(res: Variant, action_key: String)

var _sim_host: Node = null
var _lbl_title: Label = null
var _lbl_subtitle: Label = null
var _lbl_points: Label = null
var _btn_close: Button = null
var _lbl_cons_hdr: Label = null
var _cons_box: VBoxContainer = null
var _lbl_aggr_hdr: Label = null
var _aggr_box: VBoxContainer = null


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
	hdr.add_theme_constant_override("separation", 12)
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

	_lbl_points = Label.new()
	_lbl_points.theme_type_variation = &"LabelGold"
	hdr.add_child(_lbl_points)

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

	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	scroll.add_child(cols)

	# Left Column: Conservative Doctrine
	var cons_col := VBoxContainer.new()
	cons_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cons_col.add_theme_constant_override("separation", 8)
	cols.add_child(cons_col)

	_lbl_cons_hdr = Label.new()
	_lbl_cons_hdr.theme_type_variation = &"LabelTitle"
	cons_col.add_child(_lbl_cons_hdr)

	_cons_box = VBoxContainer.new()
	_cons_box.add_theme_constant_override("separation", 8)
	cons_col.add_child(_cons_box)

	# Right Column: Aggressive Growth Doctrine
	var aggr_col := VBoxContainer.new()
	aggr_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aggr_col.add_theme_constant_override("separation", 8)
	cols.add_child(aggr_col)

	_lbl_aggr_hdr = Label.new()
	_lbl_aggr_hdr.theme_type_variation = &"LabelTitle"
	aggr_col.add_child(_lbl_aggr_hdr)

	_aggr_box = VBoxContainer.new()
	_aggr_box.add_theme_constant_override("separation", 8)
	aggr_col.add_child(_aggr_box)


func refresh() -> void:
	if _lbl_title == null:
		return

	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var sp: int = bs.strategy_points if bs != null else 10

	_lbl_title.text = UiI18n.tr_key("UI_DRAWER_POLICIES_TITLE")
	_lbl_subtitle.text = UiI18n.tr_key("UI_DRAWER_POLICIES_SUBTITLE")
	_lbl_points.text = UiI18n.tr_key("UI_POLICY_POINTS", {"points": sp})
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")
	_lbl_cons_hdr.text = UiI18n.tr_key("UI_POLICY_BRANCH_CONSERVATIVE")
	_lbl_aggr_hdr.text = UiI18n.tr_key("UI_POLICY_BRANCH_AGGRESSIVE")

	for c in _cons_box.get_children():
		_cons_box.remove_child(c)
		c.free()
	for c in _aggr_box.get_children():
		_aggr_box.remove_child(c)
		c.free()

	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
	var policies: Array = defs.get("policies", []) as Array
	var name_by_id: Dictionary = {}
	for raw_p in policies:
		if raw_p is Dictionary:
			var pd: Dictionary = raw_p as Dictionary
			name_by_id[str(pd.get("id", ""))] = str(pd.get("name_key", ""))

	for raw_p in policies:
		if not (raw_p is Dictionary):
			continue
		var pdef: Dictionary = raw_p as Dictionary
		var pid: String = str(pdef.get("id", ""))
		var branch: String = PolicyService._infer_doctrine_branch(pid, pdef)
		var target_box: VBoxContainer = _aggr_box if branch == "aggressive" else _cons_box
		_build_policy_card(target_box, bs, pdef, name_by_id)


func _build_policy_card(parent: Node, bs: BankState, pdef: Dictionary, name_by_id: Dictionary) -> void:
	var pid: String = str(pdef.get("id", ""))
	var cost: int = int(pdef.get("cost_strategy_points", 3))
	var adopted: bool = bs != null and bs.adopted_policies.has(pid)

	var card := PanelContainer.new()
	card.theme_type_variation = &"PanelCard"
	parent.add_child(card)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 5)
	card.add_child(cv)

	var title_l := Label.new()
	title_l.theme_type_variation = &"LabelTitle"
	title_l.text = UiI18n.tr_key(str(pdef.get("name_key", pid)))
	cv.add_child(title_l)

	var desc_l := Label.new()
	desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_l.theme_type_variation = &"LabelMuted"
	desc_l.text = UiI18n.tr_key(str(pdef.get("description_key", "")))
	cv.add_child(desc_l)

	var prereqs: Array = pdef.get("prerequisites", []) as Array
	var pre_lbl := Label.new()
	if prereqs.is_empty():
		pre_lbl.text = UiI18n.tr_key("UI_POLICY_PREREQ_NONE")
	else:
		var pre_id: String = str(prereqs[0])
		var pre_name_key: String = str(name_by_id.get(pre_id, pre_id))
		pre_lbl.text = UiI18n.tr_key("UI_POLICY_PREREQ", {"prereq": UiI18n.tr_key(pre_name_key)})
	cv.add_child(pre_lbl)

	var btn := Button.new()
	if adopted:
		btn.text = UiI18n.tr_key("UI_POLICY_ADOPTED")
		btn.disabled = true
	else:
		btn.theme_type_variation = &"ButtonPrimary"
		btn.text = UiI18n.tr_key("UI_POLICY_BTN_ADOPT", {"cost": cost})
		btn.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_exec_cmd("adopt_policy", [pid], "UI_POLICY_BTN_ADOPT")
		)
	cv.add_child(btn)


func _exec_cmd(method_name: String, args: Array, action_key: String) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd != null and (cmd as Object).has_method(method_name):
		var r: Variant = (cmd as Object).callv(method_name, args)
		if r is Result and (r as Result).ok:
			UiI18n.play_sfx("sfx_upgrade_success")
		command_executed.emit(r, action_key)
		refresh()
