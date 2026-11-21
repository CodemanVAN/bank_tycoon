class_name Result
extends RefCounted

## Uniform domain and command outcome container.

var ok: bool = false
var error_code: StringName = &""
var error_key: String = ""
var error_params: Dictionary = {}
var data: Variant = null


func _init(
	p_ok: bool = false,
	p_data: Variant = null,
	p_error_code: StringName = &"",
	p_error_key: String = "",
	p_error_params: Dictionary = {}
) -> void:
	ok = p_ok
	data = p_data
	error_code = p_error_code
	error_key = p_error_key
	error_params = p_error_params.duplicate(true)


static func success(p_data: Variant = null) -> Result:
	return Result.new(true, p_data, &"", "", {})


static func succeed(p_data: Variant = null) -> Result:
	return Result.new(true, p_data, &"", "", {})


static func fail(
	p_error_code: StringName,
	p_error_key: String = "",
	p_error_params: Dictionary = {},
	p_data: Variant = null
) -> Result:
	var code: StringName = p_error_code
	var key: String = p_error_key
	if code == &"" and key == "":
		code = &"UNKNOWN_ERROR"
	if key == "":
		key = "ERR_%s" % String(code)
	if code == &"":
		code = StringName(key)
	return Result.new(false, p_data, code, key, p_error_params)


func is_ok() -> bool:
	return ok


func is_err() -> bool:
	return not ok


func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"error_code": String(error_code),
		"error_key": error_key,
		"error_params": error_params.duplicate(true),
		"data": data,
	}
