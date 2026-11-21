extends Node

## 4-level fallback LocalizationService (Mod current -> Vanilla current -> EN fallback -> raw key).

signal locale_changed(new_locale: String)

const SUPPORTED_LOCALES: Array[String] = ["zh_CN", "en", "ja"]
const MODULE_ORDER: Array[String] = ["core", "sim", "world", "hud", "panels"]

var _locale: String = "zh_CN"
var _loaded_vanilla: bool = false
var _vanilla: Dictionary = {
	"zh_CN": {},
	"en": {},
	"ja": {},
}
var _vanilla_keys: Dictionary = {}
var _mod_translations: Dictionary = {
	"zh_CN": {},
	"en": {},
	"ja": {},
}
var _mod_key_owners: Dictionary = {}
var _warned_missing_keys: Dictionary = {}


func _ready() -> void:
	reload_vanilla_translations()


func get_available_locales() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_LOCALES)


func get_locale() -> String:
	return _locale


func set_locale(locale: String) -> void:
	if locale.is_empty() or not SUPPORTED_LOCALES.has(locale):
		return
	if not _loaded_vanilla:
		reload_vanilla_translations()
	_locale = locale
	locale_changed.emit(_locale)


func reload_vanilla_translations() -> void:
	_vanilla = {
		"zh_CN": {},
		"en": {},
		"ja": {},
	}
	_vanilla_keys.clear()

	for lc in SUPPORTED_LOCALES:
		var merged_path: String = "res://localization/%s.json" % lc
		_load_json_into_table(merged_path, _vanilla[lc] as Dictionary)
		for mod_name in MODULE_ORDER:
			var frag_path: String = "res://localization/%s.%s.json" % [mod_name, lc]
			_load_json_into_table(frag_path, _vanilla[lc] as Dictionary)

	var da: DirAccess = DirAccess.open("res://localization")
	if da != null:
		da.list_dir_begin()
		var fname: String = da.get_next()
		while fname != "":
			if not da.current_is_dir():
				for lc in SUPPORTED_LOCALES:
					var suffix: String = ".%s.json" % lc
					if fname.ends_with(suffix):
						_load_json_into_table("res://localization/" + fname, _vanilla[lc] as Dictionary)
			fname = da.get_next()
		da.list_dir_end()

	for lc in SUPPORTED_LOCALES:
		var tbl: Dictionary = _vanilla[lc] as Dictionary
		for k: Variant in tbl.keys():
			_vanilla_keys[str(k)] = true

	_loaded_vanilla = true


func _load_json_into_table(res_path: String, target_table: Dictionary) -> void:
	if not FileAccess.file_exists(res_path):
		return
	var f: FileAccess = FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		return
	var raw_text: String = f.get_as_text()
	f.close()
	if raw_text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		var d: Dictionary = parsed as Dictionary
		for k: Variant in d.keys():
			target_table[str(k)] = str(d[k])


func tr_key(key: String, params: Dictionary = {}) -> String:
	if not _loaded_vanilla:
		reload_vanilla_translations()
	if key.is_empty():
		return ""

	var resolved: String = ""
	var found: bool = false

	# Level 1: Current locale Mod translation
	var mod_cur: Dictionary = _mod_translations.get(_locale, {}) as Dictionary
	if mod_cur.has(key):
		resolved = str(mod_cur[key])
		found = true

	# Level 2: Current locale Vanilla translation
	if not found:
		var van_cur: Dictionary = _vanilla.get(_locale, {}) as Dictionary
		if van_cur.has(key):
			resolved = str(van_cur[key])
			found = true

	# Level 3: English fallback (Mod en -> Vanilla en)
	if not found:
		var mod_en: Dictionary = _mod_translations.get("en", {}) as Dictionary
		if mod_en.has(key):
			resolved = str(mod_en[key])
			found = true
		else:
			var van_en: Dictionary = _vanilla.get("en", {}) as Dictionary
			if van_en.has(key):
				resolved = str(van_en[key])
				found = true

	# Level 4: Missing key -> return raw key and record once
	if not found:
		if not _warned_missing_keys.has(key):
			_warned_missing_keys[key] = true
		resolved = key

	if params.is_empty():
		return resolved

	var formatted: String = resolved
	for param_key: Variant in params.keys():
		formatted = formatted.replace("{%s}" % str(param_key), str(params[param_key]))
	return formatted


func register_mod_translations(mod_id: String, locale: String, entries: Dictionary) -> void:
	if not _loaded_vanilla:
		reload_vanilla_translations()
	var clean_mod_id: String = mod_id.strip_edges()
	var clean_locale: String = locale.strip_edges()
	if clean_mod_id.is_empty() or clean_locale.is_empty() or entries.is_empty():
		return
	if not _mod_translations.has(clean_locale):
		_mod_translations[clean_locale] = {}

	var target_table: Dictionary = _mod_translations[clean_locale] as Dictionary
	var required_prefix: String = clean_mod_id + ":"

	for raw_k: Variant in entries.keys():
		var k: String = str(raw_k)
		if _vanilla_keys.has(k):
			continue
		if not k.begins_with(required_prefix):
			continue
		if _mod_key_owners.has(k) and str(_mod_key_owners[k]) != clean_mod_id:
			continue
		_mod_key_owners[k] = clean_mod_id
		target_table[k] = str(entries[raw_k])


func clear_mod_translations() -> void:
	for lc: Variant in _mod_translations.keys():
		if _mod_translations[lc] is Dictionary:
			(_mod_translations[lc] as Dictionary).clear()
	_mod_key_owners.clear()
