class_name ContentStudioModal
extends PanelContainer

## In-Game Content Studio / Developer Console Modal.
## Lets players live-author, edit, and delete Employee Traits, Random Events,
## Buildable Decor/Facilities, and Live NPC/Employee Dialogues without code.

signal closed()
signal content_changed()
signal test_event_requested(event_id: String)
signal test_dialogue_requested(text: String, category: String)

const ContentStudioStoreScript := preload("res://scripts/infrastructure/content_studio_store.gd")

const COL_BG_PANEL: Color = StarwayTheme.BG_1
const COL_BORDER: Color = StarwayTheme.BORDER_COLOR
const COL_TEXT_PRIMARY: Color = StarwayTheme.WHITE
const COL_TEXT_SECONDARY: Color = StarwayTheme.ICE_100
const COL_PRIMARY: Color = StarwayTheme.BLUE_500
const COL_PRIMARY_HOVER: Color = StarwayTheme.BLUE_400
const COL_SUCCESS: Color = StarwayTheme.GREEN_500
const COL_DANGER: Color = StarwayTheme.RED_500
const COL_TEAL: Color = StarwayTheme.CYAN_500


static func _make_panel(bg: Color, border: Color, border_w: int = 1, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func _style_btn(btn: Button, bg: Color, fg: Color, border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", sb)
	var hsb: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	hsb.bg_color = bg.lightened(0.12)
	btn.add_theme_stylebox_override("hover", hsb)
	var psb: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
	psb.bg_color = bg.darkened(0.12)
	btn.add_theme_stylebox_override("pressed", psb)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)

var _active_tab: String = "traits"
var _sim_host: Node = null
var _selected_id: String = ""

var _tab_buttons: Dictionary = {}
var _list_box: VBoxContainer = null
var _list_count_lbl: Label = null
var _editor_box: VBoxContainer = null
var _status_lbl: Label = null

# Editor input references (rebuilt per tab)
var _inputs: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(920, 580)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override(
		"panel",
		_make_panel(COL_BG_PANEL, COL_BORDER, 2, 10)
	)
	_build_ui()


func open_studio(sim_host: Node) -> void:
	_sim_host = sim_host
	visible = true
	_switch_tab(_active_tab)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 2)
	header.add_child(title_col)

	var title_lbl := Label.new()
	title_lbl.text = UiI18n.tr_key("UI_STUDIO_TITLE")
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
	title_col.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = UiI18n.tr_key("UI_STUDIO_SUBTITLE")
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", COL_TEXT_SECONDARY)
	title_col.add_child(sub_lbl)

	var btn_reset := Button.new()
	btn_reset.text = UiI18n.tr_key("UI_STUDIO_RESET_ALL")
	btn_reset.custom_minimum_size = Vector2(126, 30)
	_style_btn(btn_reset, Color("#243348"), COL_TEXT_SECONDARY, Color("#3B5578"))
	btn_reset.pressed.connect(_on_reset_all_pressed)
	header.add_child(btn_reset)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(34, 30)
	_style_btn(btn_close, Color("#2A2230"), COL_DANGER, COL_DANGER)
	btn_close.pressed.connect(func() -> void:
		visible = false
		closed.emit()
	)
	header.add_child(btn_close)

	# Tab Bar
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	root.add_child(tab_bar)

	var tabs: Array[Dictionary] = [
		{"id": "traits", "label": UiI18n.tr_key("UI_STUDIO_TAB_TRAITS")},
		{"id": "events", "label": UiI18n.tr_key("UI_STUDIO_TAB_EVENTS")},
		{"id": "props", "label": UiI18n.tr_key("UI_STUDIO_TAB_PROPS")},
		{"id": "dialogues", "label": UiI18n.tr_key("UI_STUDIO_TAB_DIALOGUES")},
	]
	for t: Dictionary in tabs:
		var tid: String = str(t["id"])
		var tb := Button.new()
		tb.text = str(t["label"])
		tb.custom_minimum_size = Vector2(150, 32)
		tb.pressed.connect(func() -> void:
			_switch_tab(tid)
		)
		tab_bar.add_child(tb)
		_tab_buttons[tid] = tb

	# Main split body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	# Left pane: Item list
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(280, 0)
	left_panel.add_theme_stylebox_override(
		"panel",
		_make_panel(Color("#0F1A2B"), COL_BORDER, 1, 8)
	)
	body.add_child(left_panel)

	var left_vb := VBoxContainer.new()
	left_vb.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vb)

	var left_top := HBoxContainer.new()
	left_top.add_theme_constant_override("separation", 6)
	left_vb.add_child(left_top)

	_list_count_lbl = Label.new()
	_list_count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_count_lbl.add_theme_font_size_override("font_size", 12)
	_list_count_lbl.add_theme_color_override("font_color", COL_TEXT_SECONDARY)
	left_top.add_child(_list_count_lbl)

	var btn_new := Button.new()
	btn_new.text = UiI18n.tr_key("UI_STUDIO_NEW_ITEM")
	btn_new.custom_minimum_size = Vector2(96, 26)
	_style_btn(btn_new, COL_PRIMARY, COL_TEXT_PRIMARY, COL_PRIMARY_HOVER)
	btn_new.pressed.connect(_on_new_item_pressed)
	left_top.add_child(btn_new)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vb.add_child(list_scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 5)
	list_scroll.add_child(_list_box)

	# Right pane: Editor
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override(
		"panel",
		_make_panel(Color("#122036"), COL_BORDER, 1, 8)
	)
	body.add_child(right_panel)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(right_scroll)

	_editor_box = VBoxContainer.new()
	_editor_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor_box.add_theme_constant_override("separation", 8)
	right_scroll.add_child(_editor_box)

	# Footer status line
	_status_lbl = Label.new()
	_status_lbl.text = UiI18n.tr_key("UI_STUDIO_STATUS_READY")
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.add_theme_color_override("font_color", COL_TEAL)
	root.add_child(_status_lbl)


func _switch_tab(tab_id: String) -> void:
	_active_tab = tab_id
	_selected_id = ""
	for k: Variant in _tab_buttons.keys():
		var sk: String = str(k)
		var btn: Button = _tab_buttons[sk] as Button
		if sk == _active_tab:
			_style_btn(btn, COL_PRIMARY, COL_TEXT_PRIMARY, COL_PRIMARY_HOVER)
		else:
			_style_btn(btn, Color("#182538"), COL_TEXT_SECONDARY, Color("#2E4463"))
	_rebuild_list()
	_rebuild_editor()


func _set_status(msg: String, is_err: bool = false) -> void:
	if _status_lbl != null:
		_status_lbl.text = msg
		_status_lbl.add_theme_color_override("font_color", COL_DANGER if is_err else COL_TEAL)


func _clear_container(c: Node) -> void:
	if c == null:
		return
	for ch: Node in c.get_children():
		ch.queue_free()


func _add_field_row(parent: VBoxContainer, label_text: String, ctrl: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(118, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", COL_TEXT_SECONDARY)
	row.add_child(lbl)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ctrl)


func _rebuild_list() -> void:
	_clear_container(_list_box)
	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
	var items: Array[Dictionary] = []

	match _active_tab:
		"traits":
			var arr: Array = defs.get("traits", []) as Array
			for t: Variant in arr:
				if t is Dictionary:
					var td: Dictionary = t as Dictionary
					var tid: String = str(td.get("id", ""))
					var polarity: String = str(td.get("polarity", "positive"))
					var tag: String = "▲" if polarity == "positive" else "▼"
					items.append({"id": tid, "title": "%s %s" % [tag, UiI18n.tr_key(str(td.get("name_key", tid)))], "data": td})
		"events":
			var arr: Array = defs.get("events", []) as Array
			for e: Variant in arr:
				if e is Dictionary:
					var ed: Dictionary = e as Dictionary
					var eid: String = str(ed.get("id", ""))
					items.append({"id": eid, "title": UiI18n.tr_key(str(ed.get("title_key", eid))), "data": ed})
		"props":
			var cat: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
			for pk: Variant in cat.keys():
				var psk: String = str(pk)
				var pd: Dictionary = cat[psk] as Dictionary
				var pname: String = str(pd.get("name", psk))
				var cost_yuan: int = int(pd.get("cost_minor", 0)) / 100
				items.append({"id": psk, "title": "%s (¥%d)" % [pname, cost_yuan], "data": pd})
		"dialogues":
			var d: Dictionary = ContentStudioStoreScript.get_data()
			var arr: Array = d.get("custom_dialogues", []) as Array
			for dlg: Variant in arr:
				if dlg is Dictionary:
					var dd: Dictionary = dlg as Dictionary
					var did: String = str(dd.get("id", ""))
					var cat_lbl: String = _dialogue_cat_label(str(dd.get("category", "emp_slack")))
					var txt: String = str(dd.get("text", ""))
					if txt.length() > 16:
						txt = txt.substr(0, 16) + "…"
					items.append({"id": did, "title": "[%s] %s" % [cat_lbl, txt], "data": dd})

	_list_count_lbl.text = "共 %d 项" % items.size()

	if _selected_id.is_empty() and not items.is_empty():
		_selected_id = str(items[0]["id"])

	for item: Dictionary in items:
		var iid: String = str(item["id"])
		var btn := Button.new()
		btn.text = str(item["title"])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 30)
		var is_sel: bool = (iid == _selected_id)
		_style_btn(
			btn,
			Color("#1D3B60") if is_sel else Color("#152336"),
			COL_TEXT_PRIMARY if is_sel else COL_TEXT_SECONDARY,
			COL_PRIMARY if is_sel else Color("#283E5C")
		)
		btn.pressed.connect(func() -> void:
			_selected_id = iid
			_rebuild_list()
			_rebuild_editor()
		)
		_list_box.add_child(btn)


func _on_new_item_pressed() -> void:
	_selected_id = "__NEW__"
	_rebuild_list()
	_rebuild_editor()
	_set_status("正在创建新条目，填写后点击「保存并实时生效」。")


func _rebuild_editor() -> void:
	_clear_container(_editor_box)
	_inputs.clear()
	match _active_tab:
		"traits":
			_build_trait_editor()
		"events":
			_build_event_editor()
		"props":
			_build_prop_editor()
		"dialogues":
			_build_dialogue_editor()


# ---------------------------------------------------------------------------
# TAB 1: Employee Traits Editor
# ---------------------------------------------------------------------------

func _build_trait_editor() -> void:
	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
	var cur: Dictionary = {}
	if _selected_id != "__NEW__" and not _selected_id.is_empty():
		for t: Variant in (defs.get("traits", []) as Array):
			if t is Dictionary and str((t as Dictionary).get("id", "")) == _selected_id:
				cur = t as Dictionary
				break

	var is_new: bool = cur.is_empty()
	var hdr := Label.new()
	hdr.text = "新增员工标签" if is_new else ("编辑员工标签 · %s" % str(cur.get("id", "")))
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
	_editor_box.add_child(hdr)

	var le_id := LineEdit.new()
	le_id.placeholder_text = "例如: custom:trait.rainmaker"
	le_id.text = "custom:trait.%d" % (Time.get_ticks_msec() % 100000) if is_new else str(cur.get("id", ""))
	_add_field_row(_editor_box, "标签 ID:", le_id)
	_inputs["id"] = le_id

	var le_name := LineEdit.new()
	le_name.placeholder_text = "例如: 金牌大客户经理"
	le_name.text = "" if is_new else UiI18n.tr_key(str(cur.get("name_key", "")))
	_add_field_row(_editor_box, "标签名称:", le_name)
	_inputs["name"] = le_name

	var opt_pol := OptionButton.new()
	opt_pol.add_item("正向特质 (Positive)", 0)
	opt_pol.add_item("负面特质 (Negative)", 1)
	opt_pol.selected = 1 if str(cur.get("polarity", "positive")) == "negative" else 0
	_add_field_row(_editor_box, "标签极性:", opt_pol)
	_inputs["polarity"] = opt_pol

	var bonuses: Dictionary = cur.get("attribute_bonuses", cur.get("bonuses", {})) as Dictionary
	var stat_defs: Array[Dictionary] = [
		{"key": "professionalism", "label": "专业素养加成"},
		{"key": "efficiency", "label": "办理效率加成"},
		{"key": "risk_awareness", "label": "风控意识加成"},
		{"key": "sociability", "label": "社交沟通加成"},
		{"key": "management", "label": "管理领导加成"},
		{"key": "loyalty", "label": "忠诚度加成"},
	]
	for sd: Dictionary in stat_defs:
		var sk: String = str(sd["key"])
		var sb := SpinBox.new()
		sb.min_value = -50
		sb.max_value = 50
		sb.step = 1
		sb.value = int(bonuses.get(sk, 0))
		_add_field_row(_editor_box, str(sd["label"]) + ":", sb)
		_inputs["bonus_" + sk] = sb

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	_editor_box.add_child(act_row)

	var btn_save := Button.new()
	btn_save.text = "保存并实时生效"
	btn_save.custom_minimum_size = Vector2(140, 32)
	_style_btn(btn_save, COL_SUCCESS, Color("#0A1510"), COL_SUCCESS)
	btn_save.pressed.connect(_save_trait)
	act_row.add_child(btn_save)

	if not is_new:
		var btn_del := Button.new()
		btn_del.text = "删除此标签"
		btn_del.custom_minimum_size = Vector2(110, 32)
		_style_btn(btn_del, Color("#3B1C24"), COL_DANGER, COL_DANGER)
		btn_del.pressed.connect(func() -> void:
			var tid: String = str(cur.get("id", ""))
			ContentStudioStoreScript.delete_trait(tid)
			_selected_id = ""
			_notify_changed("已删除标签: %s" % tid)
		)
		act_row.add_child(btn_del)


func _save_trait() -> void:
	var tid: String = (_inputs["id"] as LineEdit).text.strip_edges()
	var tname: String = (_inputs["name"] as LineEdit).text.strip_edges()
	if tid.is_empty() or tname.is_empty():
		_set_status("标签 ID 和名称不能为空。", true)
		return
	var pol: String = "negative" if (_inputs["polarity"] as OptionButton).selected == 1 else "positive"
	var bonuses: Dictionary = {}
	for sk: String in ["professionalism", "efficiency", "risk_awareness", "sociability", "management", "loyalty"]:
		var val: int = int((_inputs["bonus_" + sk] as SpinBox).value)
		if val != 0:
			bonuses[sk] = val
	var entry: Dictionary = {
		"id": tid,
		"name_key": "RAW:" + tname,
		"polarity": pol,
		"attribute_bonuses": bonuses,
	}
	ContentStudioStoreScript.upsert_trait(entry)
	_selected_id = tid
	_notify_changed("已保存员工标签「%s」，招聘与培训刷新立即生效！" % tname)


# ---------------------------------------------------------------------------
# TAB 2: Random Events Editor
# ---------------------------------------------------------------------------

func _build_event_editor() -> void:
	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
	var cur: Dictionary = {}
	if _selected_id != "__NEW__" and not _selected_id.is_empty():
		for e: Variant in (defs.get("events", []) as Array):
			if e is Dictionary and str((e as Dictionary).get("id", "")) == _selected_id:
				cur = e as Dictionary
				break

	var is_new: bool = cur.is_empty()
	var hdr := Label.new()
	hdr.text = "新增随机事件" if is_new else ("编辑随机事件 · %s" % str(cur.get("id", "")))
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
	_editor_box.add_child(hdr)

	var le_id := LineEdit.new()
	le_id.text = "custom:event.%d" % (Time.get_ticks_msec() % 100000) if is_new else str(cur.get("id", ""))
	_add_field_row(_editor_box, "事件 ID:", le_id)
	_inputs["id"] = le_id

	var le_title := LineEdit.new()
	le_title.placeholder_text = "例如: 金融科技峰会嘉宾来访"
	le_title.text = "" if is_new else UiI18n.tr_key(str(cur.get("title_key", "")))
	_add_field_row(_editor_box, "事件标题:", le_title)
	_inputs["title"] = le_title

	var te_desc := TextEdit.new()
	te_desc.custom_minimum_size = Vector2(0, 64)
	te_desc.placeholder_text = "输入事件背景描述..."
	te_desc.text = "" if is_new else UiI18n.tr_key(str(cur.get("description_key", "")))
	_add_field_row(_editor_box, "事件描述:", te_desc)
	_inputs["desc"] = te_desc

	var sb_exp := SpinBox.new()
	sb_exp.min_value = 30
	sb_exp.max_value = 480
	sb_exp.step = 10
	sb_exp.value = int(cur.get("expire_minutes", 120))
	_add_field_row(_editor_box, "超时时限(分钟):", sb_exp)
	_inputs["expire_minutes"] = sb_exp

	var opts: Array = cur.get("options", []) as Array
	var opt_a: Dictionary = opts[0] as Dictionary if opts.size() >= 1 and opts[0] is Dictionary else {}
	var opt_b: Dictionary = opts[1] as Dictionary if opts.size() >= 2 and opts[1] is Dictionary else {}

	var le_oa := LineEdit.new()
	le_oa.placeholder_text = "例如: 热情接待并举办专场推介"
	le_oa.text = "" if is_new else UiI18n.tr_key(str(opt_a.get("label_key", "")))
	_add_field_row(_editor_box, "选项 A 文案:", le_oa)
	_inputs["opt_a_label"] = le_oa

	var sb_oa_cash := SpinBox.new()
	sb_oa_cash.min_value = -500000
	sb_oa_cash.max_value = 500000
	sb_oa_cash.step = 100
	sb_oa_cash.value = int(opt_a.get("cash_delta_minor", 0)) / 100
	_add_field_row(_editor_box, "选项 A 现金(元):", sb_oa_cash)
	_inputs["opt_a_cash"] = sb_oa_cash

	var sb_oa_sat := SpinBox.new()
	sb_oa_sat.min_value = -20
	sb_oa_sat.max_value = 20
	sb_oa_sat.value = int(opt_a.get("satisfaction_delta", 3 if is_new else 0))
	_add_field_row(_editor_box, "选项 A 满意度:", sb_oa_sat)
	_inputs["opt_a_sat"] = sb_oa_sat

	var sb_oa_aw := SpinBox.new()
	sb_oa_aw.min_value = -20
	sb_oa_aw.max_value = 30
	sb_oa_aw.value = int(opt_a.get("awareness_delta", 5 if is_new else 0))
	_add_field_row(_editor_box, "选项 A 知名度:", sb_oa_aw)
	_inputs["opt_a_aw"] = sb_oa_aw

	var le_ob := LineEdit.new()
	le_ob.placeholder_text = "例如: 礼貌婉拒，专注日常柜面业务"
	le_ob.text = "" if is_new else UiI18n.tr_key(str(opt_b.get("label_key", "")))
	_add_field_row(_editor_box, "选项 B 文案:", le_ob)
	_inputs["opt_b_label"] = le_ob

	var sb_ob_cash := SpinBox.new()
	sb_ob_cash.min_value = -500000
	sb_ob_cash.max_value = 500000
	sb_ob_cash.step = 100
	sb_ob_cash.value = int(opt_b.get("cash_delta_minor", 0)) / 100
	_add_field_row(_editor_box, "选项 B 现金(元):", sb_ob_cash)
	_inputs["opt_b_cash"] = sb_ob_cash

	var sb_ob_sat := SpinBox.new()
	sb_ob_sat.min_value = -20
	sb_ob_sat.max_value = 20
	sb_ob_sat.value = int(opt_b.get("satisfaction_delta", 0))
	_add_field_row(_editor_box, "选项 B 满意度:", sb_ob_sat)
	_inputs["opt_b_sat"] = sb_ob_sat

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	_editor_box.add_child(act_row)

	var btn_save := Button.new()
	btn_save.text = "保存并实时生效"
	btn_save.custom_minimum_size = Vector2(140, 32)
	_style_btn(btn_save, COL_SUCCESS, Color("#0A1510"), COL_SUCCESS)
	btn_save.pressed.connect(_save_event)
	act_row.add_child(btn_save)

	var btn_test := Button.new()
	btn_test.text = "立即触发测试"
	btn_test.custom_minimum_size = Vector2(120, 32)
	_style_btn(btn_test, COL_PRIMARY, COL_TEXT_PRIMARY, COL_PRIMARY_HOVER)
	btn_test.pressed.connect(func() -> void:
		var eid: String = _save_event()
		if not eid.is_empty():
			test_event_requested.emit(eid)
	)
	act_row.add_child(btn_test)

	if not is_new:
		var btn_del := Button.new()
		btn_del.text = "删除此事件"
		btn_del.custom_minimum_size = Vector2(105, 32)
		_style_btn(btn_del, Color("#3B1C24"), COL_DANGER, COL_DANGER)
		btn_del.pressed.connect(func() -> void:
			var eid: String = str(cur.get("id", ""))
			ContentStudioStoreScript.delete_event(eid)
			_selected_id = ""
			_notify_changed("已删除随机事件: %s" % eid)
		)
		act_row.add_child(btn_del)


func _save_event() -> String:
	var eid: String = (_inputs["id"] as LineEdit).text.strip_edges()
	var title: String = (_inputs["title"] as LineEdit).text.strip_edges()
	var desc: String = (_inputs["desc"] as TextEdit).text.strip_edges()
	var oa_lbl: String = (_inputs["opt_a_label"] as LineEdit).text.strip_edges()
	var ob_lbl: String = (_inputs["opt_b_label"] as LineEdit).text.strip_edges()
	if eid.is_empty() or title.is_empty() or oa_lbl.is_empty():
		_set_status("事件 ID、标题和选项 A 文案不能为空。", true)
		return ""
	var options: Array[Dictionary] = [
		{
			"id": "opt_a",
			"label_key": "RAW:" + oa_lbl,
			"cash_delta_minor": int((_inputs["opt_a_cash"] as SpinBox).value) * 100,
			"satisfaction_delta": int((_inputs["opt_a_sat"] as SpinBox).value),
			"awareness_delta": int((_inputs["opt_a_aw"] as SpinBox).value),
			"effects": [],
		}
	]
	if not ob_lbl.is_empty():
		options.append({
			"id": "opt_b",
			"label_key": "RAW:" + ob_lbl,
			"cash_delta_minor": int((_inputs["opt_b_cash"] as SpinBox).value) * 100,
			"satisfaction_delta": int((_inputs["opt_b_sat"] as SpinBox).value),
			"effects": [],
		})
	var entry: Dictionary = {
		"id": eid,
		"title_key": "RAW:" + title,
		"description_key": "RAW:" + (desc if not desc.is_empty() else title),
		"weight": 15,
		"cooldown_days": 3,
		"expire_minutes": int((_inputs["expire_minutes"] as SpinBox).value),
		"conditions": [],
		"options": options,
	}
	ContentStudioStoreScript.upsert_event(entry)
	_selected_id = eid
	_notify_changed("已保存随机事件「%s」，已热加载到事件池！" % title)
	return eid


# ---------------------------------------------------------------------------
# TAB 3: Buildable Decor & Facilities Editor
# ---------------------------------------------------------------------------

func _build_prop_editor() -> void:
	var cat: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
	var cur: Dictionary = {}
	if _selected_id != "__NEW__" and cat.has(_selected_id):
		cur = cat[_selected_id] as Dictionary

	var is_new: bool = cur.is_empty()
	var hdr := Label.new()
	hdr.text = "新增装饰 / 设施" if is_new else ("编辑装饰 / 设施 · %s" % _selected_id)
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
	_editor_box.add_child(hdr)

	var le_id := LineEdit.new()
	le_id.placeholder_text = "例如: jade_statue (英文小写标识)"
	le_id.text = "custom_decor_%d" % (Time.get_ticks_msec() % 10000) if is_new else _selected_id
	_add_field_row(_editor_box, "物品类型 ID:", le_id)
	_inputs["id"] = le_id

	var le_name := LineEdit.new()
	le_name.placeholder_text = "例如: 招财玉貔貅"
	le_name.text = "" if is_new else str(cur.get("name", ""))
	_add_field_row(_editor_box, "显示名称:", le_name)
	_inputs["name"] = le_name

	var opt_cat := OptionButton.new()
	opt_cat.add_item("豪华装饰 (decor · 客户等待时随机逛览)", 0)
	opt_cat.add_item("功能设施 (facilities)", 1)
	opt_cat.add_item("业务柜台 (counters)", 2)
	var cat_str: String = str(cur.get("category", "decor"))
	opt_cat.selected = 1 if cat_str == "facilities" else (2 if cat_str == "counters" else 0)
	_add_field_row(_editor_box, "建造分类:", opt_cat)
	_inputs["category"] = opt_cat

	var sb_cost := SpinBox.new()
	sb_cost.min_value = 0
	sb_cost.max_value = 500000
	sb_cost.step = 50
	sb_cost.value = int(cur.get("cost_minor", 120000)) / 100
	_add_field_row(_editor_box, "建造成本(元):", sb_cost)
	_inputs["cost"] = sb_cost

	var opt_tex := OptionButton.new()
	var cur_tex: String = str(cur.get("tex_path", cur.get("texture", ContentStudioStoreScript.PRESET_PROP_TEXTURES[0]["path"])))
	var sel_idx: int = 0
	for i in range(ContentStudioStoreScript.PRESET_PROP_TEXTURES.size()):
		var pt: Dictionary = ContentStudioStoreScript.PRESET_PROP_TEXTURES[i]
		opt_tex.add_item(str(pt["label"]), i)
		if str(pt["path"]) == cur_tex:
			sel_idx = i
	opt_tex.selected = sel_idx
	_add_field_row(_editor_box, "预设像素贴图:", opt_tex)
	_inputs["texture_preset"] = opt_tex

	var le_lore := TextEdit.new()
	le_lore.custom_minimum_size = Vector2(0, 58)
	le_lore.placeholder_text = "点击该物品时右侧卡片展示的背景说明..."
	le_lore.text = str(cur.get("lore", "玩家通过内容工坊定制的银行专属装饰品，彰显独特格调。"))
	_add_field_row(_editor_box, "物品背景说明:", le_lore)
	_inputs["lore"] = le_lore

	var le_stats := LineEdit.new()
	le_stats.placeholder_text = "例如: 满意度+3/次 · 降低等待焦躁"
	le_stats.text = str(cur.get("stats", "豪华装饰：客户等候时可随机逛览，缓解焦躁并提升满意度"))
	_add_field_row(_editor_box, "属性效果说明:", le_stats)
	_inputs["stats"] = le_stats

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	_editor_box.add_child(act_row)

	var btn_save := Button.new()
	btn_save.text = "保存并加入建造目录"
	btn_save.custom_minimum_size = Vector2(160, 32)
	_style_btn(btn_save, COL_SUCCESS, Color("#0A1510"), COL_SUCCESS)
	btn_save.pressed.connect(_save_prop)
	act_row.add_child(btn_save)

	if not is_new:
		var btn_del := Button.new()
		btn_del.text = "从目录移除"
		btn_del.custom_minimum_size = Vector2(110, 32)
		_style_btn(btn_del, Color("#3B1C24"), COL_DANGER, COL_DANGER)
		btn_del.pressed.connect(func() -> void:
			var pid: String = _selected_id
			ContentStudioStoreScript.delete_prop(pid)
			_selected_id = ""
			_notify_changed("已从建造目录移除: %s" % pid)
		)
		act_row.add_child(btn_del)


func _save_prop() -> void:
	var pid: String = (_inputs["id"] as LineEdit).text.strip_edges().to_lower().replace(" ", "_")
	var pname: String = (_inputs["name"] as LineEdit).text.strip_edges()
	if pid.is_empty() or pname.is_empty():
		_set_status("物品类型 ID 和名称不能为空。", true)
		return
	var cat_idx: int = (_inputs["category"] as OptionButton).selected
	var cat_str: String = "decor" if cat_idx == 0 else ("facilities" if cat_idx == 1 else "counters")
	var tex_idx: int = clampi((_inputs["texture_preset"] as OptionButton).selected, 0, ContentStudioStoreScript.PRESET_PROP_TEXTURES.size() - 1)
	var preset: Dictionary = ContentStudioStoreScript.PRESET_PROP_TEXTURES[tex_idx]
	var off: Vector2 = preset["offset"] as Vector2
	var entry: Dictionary = {
		"name": pname,
		"category": cat_str,
		"cost_minor": int((_inputs["cost"] as SpinBox).value) * 100,
		"kind": "station" if cat_str == "counters" else "prop",
		"station_type": "teller_counter" if cat_str == "counters" else "",
		"tex_path": str(preset["path"]),
		"texture": str(preset["path"]),
		"offset": [off.x, off.y],
		"lore": (_inputs["lore"] as TextEdit).text.strip_edges(),
		"stats": (_inputs["stats"] as LineEdit).text.strip_edges(),
	}
	ContentStudioStoreScript.upsert_prop(pid, entry)
	_selected_id = pid
	_notify_changed("已保存「%s」，打开建造目录即可直接购买并摆放！" % pname)


# ---------------------------------------------------------------------------
# TAB 4: Live NPC / Employee Dialogues Editor
# ---------------------------------------------------------------------------

func _dialogue_cat_label(cat: String) -> String:
	match cat:
		"emp_slack":
			return "员工摸鱼闲聊"
		"emp_tired":
			return "员工疲惫吐槽"
		"cust_decor":
			return "客户欣赏装饰"
		"cust_serve":
			return "客户办理感言"
		"lm_guide":
			return "大堂经理引导"
		_:
			return cat


func _build_dialogue_editor() -> void:
	var d: Dictionary = ContentStudioStoreScript.get_data()
	var cur: Dictionary = {}
	if _selected_id != "__NEW__" and not _selected_id.is_empty():
		for item: Variant in (d.get("custom_dialogues", []) as Array):
			if item is Dictionary and str((item as Dictionary).get("id", "")) == _selected_id:
				cur = item as Dictionary
				break

	var is_new: bool = cur.is_empty()
	var hdr := Label.new()
	hdr.text = "新增实时 NPC / 员工对话" if is_new else ("编辑实时对话 · %s" % str(cur.get("id", "")))
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", COL_TEXT_PRIMARY)
	_editor_box.add_child(hdr)

	var tip := Label.new()
	tip.text = "新增的对话会立即注入游戏实时气泡池，在对应场景触发时于大厅头顶弹出显示。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", COL_TEAL)
	_editor_box.add_child(tip)

	var le_id := LineEdit.new()
	le_id.text = "dlg_%d" % (Time.get_ticks_msec() % 100000) if is_new else str(cur.get("id", ""))
	_add_field_row(_editor_box, "对话 ID:", le_id)
	_inputs["id"] = le_id

	var cats: Array[String] = ["emp_slack", "emp_tired", "cust_decor", "cust_serve", "lm_guide"]
	var opt_cat := OptionButton.new()
	var cur_cat: String = str(cur.get("category", "emp_slack"))
	var sel_c: int = 0
	for i in range(cats.size()):
		opt_cat.add_item(_dialogue_cat_label(cats[i]), i)
		if cats[i] == cur_cat:
			sel_c = i
	opt_cat.selected = sel_c
	_add_field_row(_editor_box, "触发场景:", opt_cat)
	_inputs["category"] = opt_cat
	_inputs["cat_keys"] = cats

	var le_text := LineEdit.new()
	le_text.placeholder_text = "例如: 星海银行的服务简直五星级，明天把定期也转过来！"
	le_text.text = "" if is_new else str(cur.get("text", ""))
	_add_field_row(_editor_box, "气泡对话内容:", le_text)
	_inputs["text"] = le_text

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	_editor_box.add_child(act_row)

	var btn_save := Button.new()
	btn_save.text = "保存并实时生效"
	btn_save.custom_minimum_size = Vector2(140, 32)
	_style_btn(btn_save, COL_SUCCESS, Color("#0A1510"), COL_SUCCESS)
	btn_save.pressed.connect(_save_dialogue)
	act_row.add_child(btn_save)

	var btn_test := Button.new()
	btn_test.text = "立即气泡测试"
	btn_test.custom_minimum_size = Vector2(120, 32)
	_style_btn(btn_test, COL_PRIMARY, COL_TEXT_PRIMARY, COL_PRIMARY_HOVER)
	btn_test.pressed.connect(func() -> void:
		var txt: String = (_inputs["text"] as LineEdit).text.strip_edges()
		if txt.is_empty():
			_set_status("请先输入气泡对话内容再测试。", true)
			return
		_save_dialogue()
		var cidx: int = (_inputs["category"] as OptionButton).selected
		var cat_k: String = str((_inputs["cat_keys"] as Array)[cidx])
		test_dialogue_requested.emit(txt, cat_k)
	)
	act_row.add_child(btn_test)

	if not is_new:
		var btn_del := Button.new()
		btn_del.text = "删除此对话"
		btn_del.custom_minimum_size = Vector2(105, 32)
		_style_btn(btn_del, Color("#3B1C24"), COL_DANGER, COL_DANGER)
		btn_del.pressed.connect(func() -> void:
			var did: String = str(cur.get("id", ""))
			ContentStudioStoreScript.delete_dialogue(did)
			_selected_id = ""
			_notify_changed("已删除自定义对话: %s" % did)
		)
		act_row.add_child(btn_del)


func _save_dialogue() -> void:
	var did: String = (_inputs["id"] as LineEdit).text.strip_edges()
	var txt: String = (_inputs["text"] as LineEdit).text.strip_edges()
	if did.is_empty() or txt.is_empty():
		_set_status("对话 ID 和对话内容不能为空。", true)
		return
	var cidx: int = (_inputs["category"] as OptionButton).selected
	var cat_k: String = str((_inputs["cat_keys"] as Array)[cidx])
	ContentStudioStoreScript.upsert_dialogue({
		"id": did,
		"category": cat_k,
		"text": txt,
	})
	_selected_id = did
	_notify_changed("已保存实时对话，游戏中将按「%s」场景自动弹出！" % _dialogue_cat_label(cat_k))


func _on_reset_all_pressed() -> void:
	ContentStudioStoreScript.reset_all()
	_selected_id = ""
	_notify_changed("已重置全部自定义内容，恢复默认配置。")


func _notify_changed(msg: String) -> void:
	_rebuild_list()
	_rebuild_editor()
	_set_status(msg)
	content_changed.emit()
