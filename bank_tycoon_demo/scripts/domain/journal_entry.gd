class_name JournalEntry
extends RefCounted

## Immutable double-entry journal entry record.

var entry_id: int = 0
var day: int = 1
var minute: int = 0
var ref_id: String = ""
var description_key: String = ""
var lines: Array[Dictionary] = []


func _init(
	p_entry_id: int = 0,
	p_day: int = 1,
	p_minute: int = 0,
	p_ref_id: String = "",
	p_description_key: String = "",
	p_lines: Array[Dictionary] = []
) -> void:
	entry_id = p_entry_id
	day = p_day
	minute = p_minute
	ref_id = p_ref_id
	description_key = p_description_key
	lines = []
	for raw_line in p_lines:
		lines.append({
			"account": StringName(str(raw_line.get("account", ""))),
			"side": str(raw_line.get("side", "")),
			"amount_minor": int(raw_line.get("amount_minor", 0)),
		})


static func _parse_i64(val: Variant, fallback: int = 0) -> int:
	if val is int:
		return int(val)
	if val is float:
		return int(val)
	if val is String:
		var s: String = (val as String).strip_edges()
		if s.is_valid_int():
			return s.to_int()
	return fallback


func to_dict() -> Dictionary:
	var ser_lines: Array[Dictionary] = []
	for line in lines:
		ser_lines.append({
			"account": String(line.get("account", &"")),
			"side": str(line.get("side", "")),
			"amount_minor": str(int(line.get("amount_minor", 0))),
		})
	return {
		"entry_id": entry_id,
		"day": day,
		"minute": minute,
		"ref_id": ref_id,
		"description_key": description_key,
		"lines": ser_lines,
	}


static func from_dict(data: Dictionary) -> Result:
	if not data.has("lines") or not (data["lines"] is Array):
		return Result.fail(&"INVALID_JOURNAL_ENTRY", "ERR_INVALID_JOURNAL_ENTRY", {"reason": "missing_lines"})
	var raw_lines: Array = data["lines"] as Array
	var typed_lines: Array[Dictionary] = []
	for item in raw_lines:
		if not (item is Dictionary):
			return Result.fail(&"INVALID_JOURNAL_LINE", "ERR_INVALID_JOURNAL_LINE", {"reason": "line_not_dict"})
		var d: Dictionary = item as Dictionary
		typed_lines.append({
			"account": StringName(str(d.get("account", ""))),
			"side": str(d.get("side", "")),
			"amount_minor": _parse_i64(d.get("amount_minor", 0), 0),
		})
	var entry := JournalEntry.new(
		int(data.get("entry_id", 0)),
		int(data.get("day", 1)),
		int(data.get("minute", 0)),
		str(data.get("ref_id", "")),
		str(data.get("description_key", "")),
		typed_lines
	)
	return Result.succeed(entry)
