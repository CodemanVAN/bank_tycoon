extends PanelContainer

## Random Event Decision Modal.

signal closed()
signal command_executed(res: Variant, action_key: String)

var _sim_host: Node = null
var _focus_instance_id: String = ""
var _lbl_title: Label = null
var _btn_close: Button = null
var _list_box: VBoxContainer = null


func _ready() -> void:
	theme_type_variation = &"PanelLarge"
	_build_ui()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func bind(p_sim_host: Node) -> void:
	_sim_host = p_sim_host
	refresh()


func open_with(data: Dictionary = {}) -> void:
	_focus_instance_id = str(data.get("event_instance_id", ""))
	visible = true
	refresh()


func _on_locale_changed(_new_locale: String) -> void:
	refresh()


func _build_ui() -> void:
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	add_child(root_v)

	var hdr := HBoxContainer.new()
	root_v.add_child(hdr)

	_lbl_title = Label.new()
	_lbl_title.theme_type_variation = &"LabelTitle"
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(_lbl_title)

	_btn_close = Button.new()
	_btn_close.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		visible = false
		closed.emit()
	)
	hdr.add_child(_btn_close)

	root_v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)


func refresh() -> void:
	if _lbl_title == null:
		return

	_lbl_title.text = UiI18n.tr_key("UI_EVENT_MODAL_TITLE")
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")

	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.free()

	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var active_evs: Array = bs.active_events if bs != null else []
	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)

	if active_evs.is_empty():
		var empty_l := Label.new()
		empty_l.theme_type_variation = &"LabelMuted"
		empty_l.text = UiI18n.tr_key("UI_EVENT_EMPTY")
		_list_box.add_child(empty_l)
		return

	for raw_ev in active_evs:
		if not (raw_ev is Dictionary):
			continue
		var inst: Dictionary = raw_ev as Dictionary
		var inst_id: String = str(inst.get("instance_id", inst.get("id", "")))
		var ev_id: String = str(inst.get("event_id", ""))
		var edef: Dictionary = EventEngine._find_event_def(ev_id, defs)

		var card := PanelContainer.new()
		card.theme_type_variation = &"PanelCard"
		_list_box.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)

		var tl := Label.new()
		tl.theme_type_variation = &"LabelTitle"
		tl.text = UiI18n.tr_key(str(edef.get("title_key", ev_id)))
		cv.add_child(tl)

		var dl := Label.new()
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.text = UiI18n.tr_key(str(edef.get("description_key", "")))
		cv.add_child(dl)

		var opts: Array = edef.get("options", []) as Array
		for raw_opt in opts:
			if not (raw_opt is Dictionary):
				continue
			var odef: Dictionary = raw_opt as Dictionary
			var oid: String = str(odef.get("id", ""))
			var obtn := Button.new()
			obtn.theme_type_variation = &"ButtonPrimary"
			obtn.text = UiI18n.tr_key(str(odef.get("label_key", oid)))
			var inst_copy: String = inst_id
			var oid_copy: String = oid
			obtn.pressed.connect(func() -> void:
				UiI18n.play_sfx("sfx_ui_click")
				_exec_cmd("resolve_event_option", [inst_copy, oid_copy], "UI_EVENT_MODAL_TITLE")
			)
			cv.add_child(obtn)


func _exec_cmd(method_name: String, args: Array, action_key: String) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd != null and (cmd as Object).has_method(method_name):
		var r: Variant = (cmd as Object).callv(method_name, args)
		command_executed.emit(r, action_key)
		refresh()
