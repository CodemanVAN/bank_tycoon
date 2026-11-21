extends PanelContainer

## Floating Toast notification bar for command feedback, warnings, and errors.

var _lbl_message: Label = null
var _last_key: String = "UI_BOTTOM_LOG_READY"
var _last_params: Dictionary = {}
var _last_severity: int = Enums.EventSeverity.INFO
var _hide_timer: float = 0.0


func _ready() -> void:
	theme_type_variation = &"PanelHeader"
	visible = false
	_lbl_message = Label.new()
	_lbl_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_lbl_message)
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	_refresh_text()


func _process(delta: float) -> void:
	if visible and _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			visible = false


func show_toast(key: String, params: Dictionary = {}, severity: int = Enums.EventSeverity.INFO, duration: float = 3.2) -> void:
	_last_key = key
	_last_params = params.duplicate(true)
	_last_severity = severity
	_hide_timer = duration
	visible = true
	_refresh_text()


func show_command_result(res: Variant, action_label_key: String = "UI_NAV_OVERVIEW") -> void:
	if res is Result:
		var r: Result = res as Result
		if r.ok:
			UiI18n.play_sfx("sfx_ui_select")
			show_toast("UI_TOAST_CMD_OK", {"action": UiI18n.tr_key(action_label_key)}, Enums.EventSeverity.INFO)
		else:
			UiI18n.play_sfx("sfx_ui_error")
			var err_k: String = r.error_key if not r.error_key.is_empty() else ("ERR_" + String(r.error_code))
			show_toast(err_k, r.error_params, Enums.EventSeverity.CRITICAL, 4.0)


func _on_locale_changed(_new_locale: String) -> void:
	_refresh_text()


func _refresh_text() -> void:
	if _lbl_message == null:
		return
	_lbl_message.text = UiI18n.tr_key(_last_key, _last_params)
	match _last_severity:
		Enums.EventSeverity.CRITICAL:
			_lbl_message.add_theme_color_override("font_color", StarwayTheme.RED_500)
		Enums.EventSeverity.WARNING:
			_lbl_message.add_theme_color_override("font_color", StarwayTheme.GOLD_500)
		_:
			_lbl_message.add_theme_color_override("font_color", StarwayTheme.GREEN_500)
