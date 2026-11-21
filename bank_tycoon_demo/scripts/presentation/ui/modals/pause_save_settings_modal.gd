extends PanelContainer

## In-Game Save, Load, Audio, Locale, and Simulation Pace Settings Modal.

signal closed()
signal toast_requested(key: String, params: Dictionary, severity: int)
signal state_reloaded()

var _sim_host: Node = null
var _lbl_title: Label = null
var _btn_close: Button = null
var _lbl_locale: Label = null
var _lbl_pace: Label = null
var _btn_pace_demo: Button = null
var _btn_pace_std: Button = null
var _lbl_master: Label = null
var _lbl_bgm: Label = null
var _lbl_sfx: Label = null
var _chk_mute: CheckBox = null
var _lbl_save_hdr: Label = null
var _slots_box: VBoxContainer = null
var _btn_return_menu: Button = null


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

	# Language Row
	var loc_row := HBoxContainer.new()
	loc_row.add_theme_constant_override("separation", 8)
	root_v.add_child(loc_row)

	_lbl_locale = Label.new()
	_lbl_locale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loc_row.add_child(_lbl_locale)

	for lc_pair in [["zh_CN", "简体中文"], ["en", "English"], ["ja", "日本語"]]:
		var b := Button.new()
		b.text = lc_pair[1]
		var code: String = lc_pair[0]
		b.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_patch_settings({"locale": code})
			UiI18n.set_locale(code)
		)
		loc_row.add_child(b)

	# Pace Row
	var pace_row := HBoxContainer.new()
	pace_row.add_theme_constant_override("separation", 8)
	root_v.add_child(pace_row)

	_lbl_pace = Label.new()
	_lbl_pace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pace_row.add_child(_lbl_pace)

	_btn_pace_demo = Button.new()
	_btn_pace_demo.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_patch_settings({"minute_duration_sec": 0.25})
	)
	pace_row.add_child(_btn_pace_demo)

	_btn_pace_std = Button.new()
	_btn_pace_std.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_patch_settings({"minute_duration_sec": 1.0})
	)
	pace_row.add_child(_btn_pace_std)

	# Audio Row
	var aud_grid := GridContainer.new()
	aud_grid.columns = 2
	aud_grid.add_theme_constant_override("h_separation", 10)
	aud_grid.add_theme_constant_override("v_separation", 6)
	root_v.add_child(aud_grid)

	_lbl_master = Label.new()
	aud_grid.add_child(_lbl_master)
	_make_slider(aud_grid, "master_volume", "Master")

	_lbl_bgm = Label.new()
	aud_grid.add_child(_lbl_bgm)
	_make_slider(aud_grid, "bgm_volume", "BGM")

	_lbl_sfx = Label.new()
	aud_grid.add_child(_lbl_sfx)
	_make_slider(aud_grid, "sfx_volume", "SFX")

	_chk_mute = CheckBox.new()
	_chk_mute.toggled.connect(func(pressed: bool) -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_patch_settings({"muted": pressed})
		var aud: Node = get_node_or_null("/root/AudioService")
		if aud != null and aud.has_method("set_muted"):
			aud.call("set_muted", pressed)
	)
	root_v.add_child(_chk_mute)

	root_v.add_child(HSeparator.new())

	_lbl_save_hdr = Label.new()
	_lbl_save_hdr.theme_type_variation = &"LabelTitle"
	root_v.add_child(_lbl_save_hdr)

	_slots_box = VBoxContainer.new()
	_slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 6)
	root_v.add_child(_slots_box)

	_btn_return_menu = Button.new()
	_btn_return_menu.theme_type_variation = &"ButtonDanger"
	_btn_return_menu.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		if get_tree() != null and ResourceLoader.exists("res://scenes/menus/main_menu.tscn"):
			get_tree().change_scene_to_file("res://scenes/menus/main_menu.tscn")
	)
	root_v.add_child(_btn_return_menu)


func _make_slider(parent: Node, setting_key: String, bus_name: String) -> void:
	var sl := HSlider.new()
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = 0.8
	sl.value_changed.connect(func(v: float) -> void:
		_patch_settings({setting_key: v})
		var aud: Node = get_node_or_null("/root/AudioService")
		if aud != null and aud.has_method("set_bus_volume"):
			aud.call("set_bus_volume", bus_name, v)
	)
	parent.add_child(sl)


func _patch_settings(patch: Dictionary) -> void:
	var sess: Node = get_node_or_null("/root/GameSession")
	if sess != null and sess.has_method("update_settings"):
		sess.call("update_settings", patch)


func refresh() -> void:
	if _lbl_title == null:
		return

	_lbl_title.text = UiI18n.tr_key("UI_SETTINGS_TITLE")
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")
	_lbl_locale.text = UiI18n.tr_key("UI_SETTINGS_LOCALE")
	_lbl_pace.text = UiI18n.tr_key("UI_SETTINGS_PACE")
	_btn_pace_demo.text = UiI18n.tr_key("UI_SETTINGS_PACE_DEMO")
	_btn_pace_std.text = UiI18n.tr_key("UI_SETTINGS_PACE_STANDARD")
	_lbl_master.text = UiI18n.tr_key("UI_SETTINGS_MASTER_VOL")
	_lbl_bgm.text = UiI18n.tr_key("UI_SETTINGS_BGM_VOL")
	_lbl_sfx.text = UiI18n.tr_key("UI_SETTINGS_SFX_VOL")
	_chk_mute.text = UiI18n.tr_key("UI_SETTINGS_MUTE")
	_lbl_save_hdr.text = UiI18n.tr_key("UI_SAVE_TITLE")
	_btn_return_menu.text = UiI18n.tr_key("UI_SAVE_BTN_RETURN_MENU")

	UiListRefresh.clear_children(_slots_box)

	var save_svc: Node = get_node_or_null("/root/SaveService")
	var sess: Node = get_node_or_null("/root/GameSession")
	var slots_info: Dictionary = {}
	if save_svc != null and save_svc.has_method("list_slots"):
		var raw_list: Variant = save_svc.call("list_slots")
		if raw_list is Array:
			for item in (raw_list as Array):
				if item is Dictionary:
					var sd: Dictionary = item as Dictionary
					slots_info[str(sd.get("slot_id", ""))] = sd

	for slot_id in ["autosave", "slot_01", "slot_02", "slot_03"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_slots_box.add_child(row)

		var info: Dictionary = slots_info.get(slot_id, {}) as Dictionary
		var exists: bool = bool(info.get("exists", false))
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if exists:
			var cash_str: String = FormatService.format_money(int(info.get("cash_minor", 0)), "CNY", false, UiI18n.get_locale())
			lbl.text = UiI18n.tr_key("UI_SAVE_SLOT_INFO", {
				"slot": slot_id,
				"bank": str(info.get("bank_name", "Starway Bank")),
				"day": int(info.get("day", 1)),
				"cash": cash_str,
			})
		else:
			lbl.text = UiI18n.tr_key("UI_SAVE_SLOT_EMPTY", {"slot": slot_id})
		row.add_child(lbl)

		var btn_save := Button.new()
		btn_save.theme_type_variation = &"ButtonPrimary"
		btn_save.text = UiI18n.tr_key("UI_SAVE_BTN_SAVE")
		var target_slot: String = slot_id
		btn_save.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			if sess != null and sess.has_method("save_to_slot"):
				sess.call("save_to_slot", target_slot)
				toast_requested.emit("UI_TOAST_SAVE_OK", {"slot": target_slot}, Enums.EventSeverity.INFO)
			refresh()
		)
		row.add_child(btn_save)

		var btn_load := Button.new()
		btn_load.text = UiI18n.tr_key("UI_SAVE_BTN_LOAD")
		btn_load.disabled = not exists
		btn_load.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			if sess != null and sess.has_method("load_from_slot"):
				var r: Variant = sess.call("load_from_slot", target_slot)
				if r is Result and (r as Result).ok:
					toast_requested.emit("UI_TOAST_LOAD_OK", {"slot": target_slot}, Enums.EventSeverity.INFO)
					state_reloaded.emit()
			refresh()
		)
		row.add_child(btn_load)

		var btn_del := Button.new()
		btn_del.theme_type_variation = &"ButtonDanger"
		btn_del.text = UiI18n.tr_key("UI_SAVE_BTN_DELETE")
		btn_del.disabled = not exists
		btn_del.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			if save_svc != null and save_svc.has_method("delete_slot"):
				save_svc.call("delete_slot", target_slot)
			refresh()
		)
		row.add_child(btn_del)
