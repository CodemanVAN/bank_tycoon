extends Control

## Starway Bank Modern Tech-Blue Main Menu.

@onready var _title_label: Label = $CenterContainer/HeroCard/VBox/HeaderBox/TitleBox/TitleLabel
@onready var _subtitle_label: Label = $CenterContainer/HeroCard/VBox/HeaderBox/TitleBox/SubtitleLabel
@onready var _btn_new_game: Button = $CenterContainer/HeroCard/VBox/ButtonBox/NewGameButton
@onready var _btn_continue: Button = $CenterContainer/HeroCard/VBox/ButtonBox/ContinueButton
@onready var _btn_load_save: Button = $CenterContainer/HeroCard/VBox/ButtonBox/LoadSaveButton
@onready var _btn_settings: Button = $CenterContainer/HeroCard/VBox/ButtonBox/SettingsButton
@onready var _btn_quit: Button = $CenterContainer/HeroCard/VBox/ButtonBox/QuitButton
@onready var _status_label: Label = $StatusLabel

var _load_panel: PanelContainer = null
var _load_title: Label = null
var _load_slots_box: VBoxContainer = null
var _load_close_btn: Button = null

var _settings_panel: PanelContainer = null
var _settings_title: Label = null
var _lbl_locale: Label = null
var _lbl_pace: Label = null
var _btn_pace_demo: Button = null
var _btn_pace_std: Button = null
var _lbl_master: Label = null
var _slider_master: HSlider = null
var _lbl_bgm: Label = null
var _slider_bgm: HSlider = null
var _lbl_sfx: Label = null
var _slider_sfx: HSlider = null
var _chk_mute: CheckBox = null
var _settings_close_btn: Button = null


func _ready() -> void:
	theme = StarwayTheme.build()
	_verify_baseline_services()
	_build_subpanels()
	_wire_main_buttons()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	var audio_node: Node = get_node_or_null("/root/AudioService")
	if audio_node != null and audio_node.has_method("play_bgm"):
		audio_node.call("play_bgm", "bgm_starway_lobby", 0.5)
	_refresh_texts()


func _verify_baseline_services() -> void:
	var required_autoloads: PackedStringArray = PackedStringArray([
		"LocalizationService",
		"ContentRegistry",
		"AudioService",
		"SaveService",
		"GameSession",
	])
	for autoload_name: String in required_autoloads:
		if get_node_or_null("/root/%s" % autoload_name) == null:
			push_error("[MainMenu] Missing required autoload: %s" % autoload_name)

	var required_buses: PackedStringArray = PackedStringArray([
		"Master",
		"BGM",
		"SFX",
	])
	for bus_name: String in required_buses:
		if AudioServer.get_bus_index(bus_name) < 0:
			push_error("[MainMenu] Missing required audio bus: %s" % bus_name)


func _wire_main_buttons() -> void:
	if _btn_new_game != null:
		_btn_new_game.pressed.connect(_on_new_game_pressed)
	if _btn_continue != null:
		_btn_continue.pressed.connect(_on_continue_pressed)
	if _btn_load_save != null:
		_btn_load_save.pressed.connect(_on_load_save_pressed)
	if _btn_settings != null:
		_btn_settings.pressed.connect(_on_settings_pressed)
	if _btn_quit != null:
		_btn_quit.pressed.connect(_on_quit_pressed)


func _build_subpanels() -> void:
	# Load Save Overlay Card
	_load_panel = PanelContainer.new()
	_load_panel.name = "LoadSavePanel"
	_load_panel.theme_type_variation = &"PanelLarge"
	_load_panel.visible = false
	_load_panel.custom_minimum_size = Vector2(560, 360)
	_load_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_load_panel)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	_load_panel.add_child(lv)

	_load_title = Label.new()
	_load_title.theme_type_variation = &"LabelTitle"
	lv.add_child(_load_title)

	_load_slots_box = VBoxContainer.new()
	_load_slots_box.add_theme_constant_override("separation", 8)
	_load_slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(_load_slots_box)

	_load_close_btn = Button.new()
	_load_close_btn.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_load_panel.visible = false
	)
	lv.add_child(_load_close_btn)

	# Settings Overlay Card
	_settings_panel = PanelContainer.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.theme_type_variation = &"PanelLarge"
	_settings_panel.visible = false
	_settings_panel.custom_minimum_size = Vector2(520, 380)
	_settings_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_settings_panel)

	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	_settings_panel.add_child(sv)

	_settings_title = Label.new()
	_settings_title.theme_type_variation = &"LabelTitle"
	sv.add_child(_settings_title)

	# Locale row
	var loc_row := HBoxContainer.new()
	loc_row.add_theme_constant_override("separation", 8)
	sv.add_child(loc_row)
	_lbl_locale = Label.new()
	_lbl_locale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loc_row.add_child(_lbl_locale)
	for lc_pair in [["zh_CN", "简体中文"], ["en", "English"], ["ja", "日本語"]]:
		var b := Button.new()
		b.text = lc_pair[1]
		var code: String = lc_pair[0]
		b.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_apply_setting_patch({"locale": code})
			UiI18n.set_locale(code)
		)
		loc_row.add_child(b)

	# Pace row
	var pace_row := HBoxContainer.new()
	pace_row.add_theme_constant_override("separation", 8)
	sv.add_child(pace_row)
	_lbl_pace = Label.new()
	_lbl_pace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pace_row.add_child(_lbl_pace)
	_btn_pace_demo = Button.new()
	_btn_pace_demo.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_apply_setting_patch({"minute_duration_sec": 0.25})
	)
	pace_row.add_child(_btn_pace_demo)
	_btn_pace_std = Button.new()
	_btn_pace_std.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_apply_setting_patch({"minute_duration_sec": 1.0})
	)
	pace_row.add_child(_btn_pace_std)

	# Volume sliders
	_lbl_master = Label.new()
	sv.add_child(_lbl_master)
	_slider_master = _make_vol_slider(sv, "master_volume", "Master")

	_lbl_bgm = Label.new()
	sv.add_child(_lbl_bgm)
	_slider_bgm = _make_vol_slider(sv, "bgm_volume", "BGM")

	_lbl_sfx = Label.new()
	sv.add_child(_lbl_sfx)
	_slider_sfx = _make_vol_slider(sv, "sfx_volume", "SFX")

	_chk_mute = CheckBox.new()
	_chk_mute.toggled.connect(func(pressed: bool) -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_apply_setting_patch({"muted": pressed})
		var aud: Node = get_node_or_null("/root/AudioService")
		if aud != null and aud.has_method("set_muted"):
			aud.call("set_muted", pressed)
	)
	sv.add_child(_chk_mute)

	_settings_close_btn = Button.new()
	_settings_close_btn.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_settings_panel.visible = false
	)
	sv.add_child(_settings_close_btn)


func _make_vol_slider(parent: Node, setting_key: String, bus_name: String) -> HSlider:
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = 0.8
	sl.value_changed.connect(func(v: float) -> void:
		_apply_setting_patch({setting_key: v})
		var aud: Node = get_node_or_null("/root/AudioService")
		if aud != null and aud.has_method("set_bus_volume"):
			aud.call("set_bus_volume", bus_name, v)
	)
	parent.add_child(sl)
	return sl


func _apply_setting_patch(patch: Dictionary) -> void:
	var sess: Node = get_node_or_null("/root/GameSession")
	if sess != null and sess.has_method("update_settings"):
		sess.call("update_settings", patch)


func _on_locale_changed(_new_locale: String) -> void:
	_refresh_texts()


func _refresh_texts() -> void:
	if _title_label != null:
		_title_label.text = UiI18n.tr_key("UI_MAIN_MENU_TITLE")
	if _subtitle_label != null:
		_subtitle_label.text = UiI18n.tr_key("UI_MAIN_MENU_SUBTITLE")
	if _btn_new_game != null:
		_btn_new_game.text = UiI18n.tr_key("UI_MAIN_MENU_NEW_GAME")
	if _btn_continue != null:
		_btn_continue.text = UiI18n.tr_key("UI_MAIN_MENU_CONTINUE")
	if _btn_load_save != null:
		_btn_load_save.text = UiI18n.tr_key("UI_MAIN_MENU_LOAD_SAVE")
	if _btn_settings != null:
		_btn_settings.text = UiI18n.tr_key("UI_MAIN_MENU_SETTINGS")
	if _btn_quit != null:
		_btn_quit.text = UiI18n.tr_key("UI_MAIN_MENU_QUIT")
	if _status_label != null:
		_status_label.text = UiI18n.tr_key("UI_MAIN_MENU_VERSION")
	if _load_title != null:
		_load_title.text = UiI18n.tr_key("UI_SAVE_TITLE")
	if _load_close_btn != null:
		_load_close_btn.text = UiI18n.tr_key("UI_COMMON_CLOSE")
	if _settings_title != null:
		_settings_title.text = UiI18n.tr_key("UI_SETTINGS_TITLE")
	if _lbl_locale != null:
		_lbl_locale.text = UiI18n.tr_key("UI_SETTINGS_LOCALE")
	if _lbl_pace != null:
		_lbl_pace.text = UiI18n.tr_key("UI_SETTINGS_PACE")
	if _btn_pace_demo != null:
		_btn_pace_demo.text = UiI18n.tr_key("UI_SETTINGS_PACE_DEMO")
	if _btn_pace_std != null:
		_btn_pace_std.text = UiI18n.tr_key("UI_SETTINGS_PACE_STANDARD")
	if _lbl_master != null:
		_lbl_master.text = UiI18n.tr_key("UI_SETTINGS_MASTER_VOL")
	if _lbl_bgm != null:
		_lbl_bgm.text = UiI18n.tr_key("UI_SETTINGS_BGM_VOL")
	if _lbl_sfx != null:
		_lbl_sfx.text = UiI18n.tr_key("UI_SETTINGS_SFX_VOL")
	if _chk_mute != null:
		_chk_mute.text = UiI18n.tr_key("UI_SETTINGS_MUTE")
	if _settings_close_btn != null:
		_settings_close_btn.text = UiI18n.tr_key("UI_COMMON_CLOSE")
	_rebuild_save_slot_rows()


func _rebuild_save_slot_rows() -> void:
	if _load_slots_box == null:
		return
	for c in _load_slots_box.get_children():
		_load_slots_box.remove_child(c)
		c.free()

	var save_svc: Node = get_node_or_null("/root/SaveService")
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
		row.add_theme_constant_override("separation", 8)
		_load_slots_box.add_child(row)

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

		var btn_load := Button.new()
		btn_load.text = UiI18n.tr_key("UI_SAVE_BTN_LOAD")
		btn_load.disabled = not exists
		var target_slot: String = slot_id
		btn_load.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_load_slot_and_enter(target_slot)
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
			_rebuild_save_slot_rows()
		)
		row.add_child(btn_del)


func _on_new_game_pressed() -> void:
	UiI18n.play_sfx("sfx_ui_click")
	var sess: Node = get_node_or_null("/root/GameSession")
	var seed_val: int = (randi() % 900000) + 100000
	if sess != null and sess.has_method("start_new_game"):
		var res_state: Variant = sess.call("start_new_game", "Starway Bank", seed_val)
		if res_state == null and sess.get("bank_state") == null:
			sess.set("bank_state", BankState.create_starter_branch("Starway Bank", seed_val))
	_enter_game_root()


func _on_continue_pressed() -> void:
	UiI18n.play_sfx("sfx_ui_click")
	var sess: Node = get_node_or_null("/root/GameSession")
	var slot_to_load: String = "autosave"
	if sess != null and sess.has_method("get_most_recent_slot"):
		var recent: String = str(sess.call("get_most_recent_slot"))
		if not recent.is_empty():
			slot_to_load = recent
	_load_slot_and_enter(slot_to_load)


func _load_slot_and_enter(slot_id: String) -> void:
	var sess: Node = get_node_or_null("/root/GameSession")
	if sess != null and sess.has_method("load_from_slot"):
		var r: Variant = sess.call("load_from_slot", slot_id)
		if r is Result and not (r as Result).ok:
			if sess.get("bank_state") == null:
				sess.call("start_new_game", "Starway Bank", 20261121)
	_enter_game_root()


func _enter_game_root() -> void:
	if ResourceLoader.exists("res://scenes/gameplay/game_root.tscn") and get_tree() != null:
		get_tree().change_scene_to_file("res://scenes/gameplay/game_root.tscn")


func _on_load_save_pressed() -> void:
	UiI18n.play_sfx("sfx_ui_click")
	_settings_panel.visible = false
	_rebuild_save_slot_rows()
	_load_panel.visible = not _load_panel.visible


func _on_settings_pressed() -> void:
	UiI18n.play_sfx("sfx_ui_click")
	_load_panel.visible = false
	_settings_panel.visible = not _settings_panel.visible


func _on_quit_pressed() -> void:
	UiI18n.play_sfx("sfx_ui_click")
	if get_tree() != null:
		get_tree().quit()
