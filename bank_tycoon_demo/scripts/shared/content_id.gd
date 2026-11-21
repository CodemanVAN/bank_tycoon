class_name ContentId
extends RefCounted

## Validated namespaced identifier utilities for core and mod content.

const PATTERN: String = "^[a-z0-9_.-]+:[a-z0-9_.-]+$"
const MOD_ID_PATTERN: String = "^[a-z0-9]+(\\.[a-z0-9_-]+)+$"
const SEMVER_PATTERN: String = "^[0-9]+\\.[0-9]+\\.[0-9]+$"
const CORE_NAMESPACE: String = "core"


static func _get_id_rx() -> RegEx:
	var rx := RegEx.new()
	rx.compile(PATTERN)
	return rx


static func _get_mod_rx() -> RegEx:
	var rx := RegEx.new()
	rx.compile(MOD_ID_PATTERN)
	return rx


static func _get_semver_rx() -> RegEx:
	var rx := RegEx.new()
	rx.compile(SEMVER_PATTERN)
	return rx


static func _has_line_break_or_space(raw: String) -> bool:
	return raw.is_empty() or raw.contains("\n") or raw.contains("\r") or raw.contains(" ") or raw.contains("\t")


static func is_valid(id_str: String) -> bool:
	if _has_line_break_or_space(id_str):
		return false
	return _get_id_rx().search(id_str) != null


static func validate(id_str: String) -> Result:
	if is_valid(id_str):
		return Result.succeed(id_str)
	return Result.fail(
		&"INVALID_CONTENT_ID",
		"ERR_INVALID_CONTENT_ID",
		{"id": id_str}
	)


static func get_namespace(id_str: String) -> String:
	if not is_valid(id_str):
		return ""
	return id_str.get_slice(":", 0)


static func get_local_id(id_str: String) -> String:
	if not is_valid(id_str):
		return ""
	return id_str.get_slice(":", 1)


static func is_core(id_str: String) -> bool:
	return is_valid(id_str) and get_namespace(id_str) == CORE_NAMESPACE


static func make(ns: String, local: String) -> String:
	return "%s:%s" % [ns, local]


static func is_valid_mod_id(mod_id: String) -> bool:
	if _has_line_break_or_space(mod_id):
		return false
	return _get_mod_rx().search(mod_id) != null


static func is_valid_semver(ver: String) -> bool:
	if _has_line_break_or_space(ver):
		return false
	return _get_semver_rx().search(ver) != null
