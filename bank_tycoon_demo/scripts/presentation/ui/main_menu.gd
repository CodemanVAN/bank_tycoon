extends Control

## M1 minimal bootable MainMenu baseline.
## M6 will expand this into the full Starway Tech-Blue MainMenu scene.

@onready var _status_label: Label = $StatusLabel


func _ready() -> void:
	_verify_baseline_services()
	if _status_label != null:
		_status_label.text = LocalizationService.tr_key("UI_MAIN_MENU_TITLE")


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
