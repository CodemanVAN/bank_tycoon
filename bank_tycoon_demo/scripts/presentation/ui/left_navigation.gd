extends PanelContainer

## Starway Bank Left Vertical Navigation Bar.

signal drawer_selected(drawer_id: StringName)
signal settings_requested()

var _active_drawer: StringName = &""
var _nav_buttons: Dictionary = {}

const NAV_ITEMS: Array[Dictionary] = [
	{"id": &"overview", "key": "UI_NAV_OVERVIEW", "icon": "icon_overview"},
	{"id": &"finance", "key": "UI_NAV_FINANCE", "icon": "icon_finance"},
	{"id": &"employees", "key": "UI_NAV_EMPLOYEES", "icon": "icon_employees"},
	{"id": &"departments", "key": "UI_NAV_DEPARTMENTS", "icon": "icon_departments"},
	{"id": &"policies", "key": "UI_NAV_POLICIES", "icon": "icon_policies"},
	{"id": &"events", "key": "UI_NAV_EVENTS", "icon": "icon_events"},
	{"id": &"settings", "key": "UI_NAV_SETTINGS", "icon": "icon_settings"},
]


func _ready() -> void:
	theme_type_variation = &"PanelBar"
	_build_ui()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func set_active_drawer(drawer_id: StringName) -> void:
	_active_drawer = drawer_id
	refresh()


func _on_locale_changed(_new_locale: String) -> void:
	refresh()


func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)

	for item in NAV_ITEMS:
		var nav_id: StringName = item["id"] as StringName
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(60, 56)
		btn.icon = UiI18n.load_icon(str(item["icon"]))
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			if nav_id == &"settings":
				settings_requested.emit()
			else:
				drawer_selected.emit(nav_id)
		)
		vb.add_child(btn)
		_nav_buttons[nav_id] = btn


func refresh() -> void:
	for item in NAV_ITEMS:
		var nav_id: StringName = item["id"] as StringName
		if _nav_buttons.has(nav_id):
			var btn: Button = _nav_buttons[nav_id] as Button
			btn.text = UiI18n.tr_key(str(item["key"]))
			btn.theme_type_variation = &"ButtonPrimary" if (_active_drawer == nav_id) else &""
