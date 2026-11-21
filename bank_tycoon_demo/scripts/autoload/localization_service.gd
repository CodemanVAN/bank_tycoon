extends Node

## M1 baseline stub for LocalizationService.
## M3 will populate full 4-level fallback loading (zh_CN / en / ja + Mods).

signal locale_changed(new_locale: String)

var _locale: String = "zh_CN"


func get_locale() -> String:
	return _locale


func set_locale(locale: String) -> void:
	if locale.is_empty() or locale == _locale:
		return
	_locale = locale
	locale_changed.emit(_locale)


func tr_key(key: String, params: Dictionary = {}) -> String:
	if params.is_empty():
		return key
	var text: String = key
	for param_key: Variant in params.keys():
		text = text.replace("{%s}" % str(param_key), str(params[param_key]))
	return text


func register_mod_translations(_mod_id: String, _locale: String, _entries: Dictionary) -> void:
	pass


func clear_mod_translations() -> void:
	pass
