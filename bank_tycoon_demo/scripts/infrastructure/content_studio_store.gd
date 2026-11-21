class_name ContentStudioStore
extends RefCounted

## Data-driven persistence & live runtime merge store for the In-Game Content Studio / Console.
## Stores player-authored traits, events, buildable decor/facilities, and live NPC dialogues
## in user://custom_content.json (pure JSON data, zero script eval).

const STORE_PATH: String = "user://custom_content.json"
const PRESET_PROP_TEXTURES: Array[Dictionary] = [
	{"label": "华尔街金牛", "path": "res://assets/environment/prop_gold_bull.png", "offset": Vector2(0.0, -10.0)},
	{"label": "咖啡吧台", "path": "res://assets/environment/prop_coffee_bar.png", "offset": Vector2(0.0, -10.0)},
	{"label": "景观水族箱", "path": "res://assets/environment/prop_aquarium.png", "offset": Vector2(0.0, -10.0)},
	{"label": "金融书报架", "path": "res://assets/environment/prop_bookshelf.png", "offset": Vector2(0.0, -10.0)},
	{"label": "室内绿植", "path": "res://assets/environment/prop_plant.png", "offset": Vector2(0.0, -8.0)},
	{"label": "等候沙发", "path": "res://assets/environment/prop_sofa.png", "offset": Vector2(0.0, -8.0)},
	{"label": "ATM 机", "path": "res://assets/environment/prop_atm.png", "offset": Vector2(0.0, -12.0)},
	{"label": "现金柜台", "path": "res://assets/environment/prop_counter_teller.png", "offset": Vector2(0.0, -10.0)},
	{"label": "信贷专柜", "path": "res://assets/environment/prop_desk_loan.png", "offset": Vector2(0.0, -8.0)},
]

static var _loaded: bool = false
static var _data: Dictionary = {}


static func _empty_data() -> Dictionary:
	return {
		"save_version": 1,
		"custom_traits": [],
		"deleted_trait_ids": [],
		"custom_events": [],
		"deleted_event_ids": [],
		"custom_props": {},
		"deleted_prop_ids": [],
		"custom_dialogues": [],
	}


static func get_data() -> Dictionary:
	if not _loaded:
		load_from_disk()
	return _data


static func load_from_disk() -> Dictionary:
	_loaded = true
	_data = _empty_data()
	if not FileAccess.file_exists(STORE_PATH):
		return _data
	var f: FileAccess = FileAccess.open(STORE_PATH, FileAccess.READ)
	if f == null:
		return _data
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		var pd: Dictionary = parsed as Dictionary
		for k: String in _data.keys():
			if pd.has(k):
				_data[k] = pd[k]
	return _data


static func save_to_disk() -> bool:
	if not _loaded:
		load_from_disk()
	var f: FileAccess = FileAccess.open(STORE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_data, "\t"))
	f.close()
	return true


static func reset_all() -> void:
	_loaded = true
	_data = _empty_data()
	save_to_disk()


# ---------------------------------------------------------------------------
# CRUD: Employee Traits
# ---------------------------------------------------------------------------

static func upsert_trait(entry: Dictionary) -> void:
	var d: Dictionary = get_data()
	var tid: String = str(entry.get("id", "")).strip_edges()
	if tid.is_empty():
		return
	var del_arr: Array = d["deleted_trait_ids"] as Array
	del_arr.erase(tid)
	var arr: Array = d["custom_traits"] as Array
	for i in range(arr.size()):
		if arr[i] is Dictionary and str((arr[i] as Dictionary).get("id", "")) == tid:
			arr[i] = entry.duplicate(true)
			save_to_disk()
			return
	arr.append(entry.duplicate(true))
	save_to_disk()


static func delete_trait(tid: String) -> void:
	var d: Dictionary = get_data()
	var arr: Array = d["custom_traits"] as Array
	for i in range(arr.size() - 1, -1, -1):
		if arr[i] is Dictionary and str((arr[i] as Dictionary).get("id", "")) == tid:
			arr.remove_at(i)
	var del_arr: Array = d["deleted_trait_ids"] as Array
	if not del_arr.has(tid):
		del_arr.append(tid)
	save_to_disk()


# ---------------------------------------------------------------------------
# CRUD: Random Events
# ---------------------------------------------------------------------------

static func upsert_event(entry: Dictionary) -> void:
	var d: Dictionary = get_data()
	var eid: String = str(entry.get("id", "")).strip_edges()
	if eid.is_empty():
		return
	var del_arr: Array = d["deleted_event_ids"] as Array
	del_arr.erase(eid)
	var arr: Array = d["custom_events"] as Array
	for i in range(arr.size()):
		if arr[i] is Dictionary and str((arr[i] as Dictionary).get("id", "")) == eid:
			arr[i] = entry.duplicate(true)
			save_to_disk()
			return
	arr.append(entry.duplicate(true))
	save_to_disk()


static func delete_event(eid: String) -> void:
	var d: Dictionary = get_data()
	var arr: Array = d["custom_events"] as Array
	for i in range(arr.size() - 1, -1, -1):
		if arr[i] is Dictionary and str((arr[i] as Dictionary).get("id", "")) == eid:
			arr.remove_at(i)
	var del_arr: Array = d["deleted_event_ids"] as Array
	if not del_arr.has(eid):
		del_arr.append(eid)
	save_to_disk()


# ---------------------------------------------------------------------------
# CRUD: Buildable Decor & Facilities
# ---------------------------------------------------------------------------

static func upsert_prop(prop_type: String, entry: Dictionary) -> void:
	var d: Dictionary = get_data()
	var pt: String = prop_type.strip_edges().to_lower()
	if pt.is_empty():
		return
	var del_arr: Array = d["deleted_prop_ids"] as Array
	del_arr.erase(pt)
	var cp: Dictionary = d["custom_props"] as Dictionary
	cp[pt] = entry.duplicate(true)
	save_to_disk()


static func delete_prop(prop_type: String) -> void:
	var d: Dictionary = get_data()
	var pt: String = prop_type.strip_edges().to_lower()
	var cp: Dictionary = d["custom_props"] as Dictionary
	cp.erase(pt)
	var del_arr: Array = d["deleted_prop_ids"] as Array
	if not del_arr.has(pt):
		del_arr.append(pt)
	save_to_disk()


# ---------------------------------------------------------------------------
# CRUD: Live NPC / Employee Dialogues
# ---------------------------------------------------------------------------

static func upsert_dialogue(entry: Dictionary) -> void:
	var d: Dictionary = get_data()
	var did: String = str(entry.get("id", "")).strip_edges()
	if did.is_empty():
		return
	var arr: Array = d["custom_dialogues"] as Array
	for i in range(arr.size()):
		if arr[i] is Dictionary and str((arr[i] as Dictionary).get("id", "")) == did:
			arr[i] = entry.duplicate(true)
			save_to_disk()
			return
	arr.append(entry.duplicate(true))
	save_to_disk()


static func delete_dialogue(did: String) -> void:
	var d: Dictionary = get_data()
	var arr: Array = d["custom_dialogues"] as Array
	for i in range(arr.size() - 1, -1, -1):
		if arr[i] is Dictionary and str((arr[i] as Dictionary).get("id", "")) == did:
			arr.remove_at(i)
	save_to_disk()


static func get_dialogues_for_category(category: String) -> Array[Dictionary]:
	var d: Dictionary = get_data()
	var out: Array[Dictionary] = []
	var arr: Variant = d.get("custom_dialogues", [])
	if arr is Array:
		for item: Variant in (arr as Array):
			if item is Dictionary and str((item as Dictionary).get("category", "")) == category:
				out.append(item as Dictionary)
	return out


# ---------------------------------------------------------------------------
# Live Runtime Merge Helpers
# ---------------------------------------------------------------------------

static func merge_into_content_defs(base_defs: Dictionary) -> Dictionary:
	var d: Dictionary = get_data()
	var merged: Dictionary = base_defs.duplicate(false)

	# 1. Traits
	var del_t: Array = d.get("deleted_trait_ids", []) as Array
	var cust_t: Array = d.get("custom_traits", []) as Array
	var cust_t_map: Dictionary = {}
	for ct: Variant in cust_t:
		if ct is Dictionary:
			cust_t_map[str((ct as Dictionary).get("id", ""))] = ct
	var traits_out: Array = []
	var seen_t: Dictionary = {}
	var base_traits: Variant = base_defs.get("traits", [])
	if base_traits is Array:
		for bt: Variant in (base_traits as Array):
			if bt is Dictionary:
				var bid: String = str((bt as Dictionary).get("id", ""))
				if del_t.has(bid):
					continue
				if cust_t_map.has(bid):
					traits_out.append(cust_t_map[bid])
				else:
					traits_out.append(bt)
				seen_t[bid] = true
	for ct2: Variant in cust_t:
		if ct2 is Dictionary:
			var cid: String = str((ct2 as Dictionary).get("id", ""))
			if not cid.is_empty() and not seen_t.has(cid):
				traits_out.append(ct2)
	merged["traits"] = traits_out

	# 2. Events
	var del_e: Array = d.get("deleted_event_ids", []) as Array
	var cust_e: Array = d.get("custom_events", []) as Array
	var cust_e_map: Dictionary = {}
	for ce: Variant in cust_e:
		if ce is Dictionary:
			cust_e_map[str((ce as Dictionary).get("id", ""))] = ce
	var events_out: Array = []
	var seen_e: Dictionary = {}
	var base_events: Variant = base_defs.get("events", [])
	if base_events is Array:
		for be: Variant in (base_events as Array):
			if be is Dictionary:
				var beid: String = str((be as Dictionary).get("id", ""))
				if del_e.has(beid):
					continue
				if cust_e_map.has(beid):
					events_out.append(cust_e_map[beid])
				else:
					events_out.append(be)
				seen_e[beid] = true
	for ce2: Variant in cust_e:
		if ce2 is Dictionary:
			var ceid: String = str((ce2 as Dictionary).get("id", ""))
			if not ceid.is_empty() and not seen_e.has(ceid):
				events_out.append(ce2)
	merged["events"] = events_out

	return merged


static func get_effective_build_catalog() -> Dictionary:
	var d: Dictionary = get_data()
	var del_p: Array = d.get("deleted_prop_ids", []) as Array
	var cust_p: Dictionary = d.get("custom_props", {}) as Dictionary
	var out: Dictionary = {}
	for k: Variant in BalanceConfig.BUILD_CATALOG.keys():
		var sk: String = str(k)
		if del_p.has(sk):
			continue
		out[sk] = (BalanceConfig.BUILD_CATALOG[sk] as Dictionary).duplicate(true)
	for ck: Variant in cust_p.keys():
		var csk: String = str(ck)
		if del_p.has(csk):
			continue
		var entry: Dictionary = (cust_p[ck] as Dictionary).duplicate(true)
		var off_raw: Variant = entry.get("offset", Vector2(0.0, -10.0))
		if off_raw is Array and (off_raw as Array).size() >= 2:
			entry["offset"] = Vector2(float((off_raw as Array)[0]), float((off_raw as Array)[1]))
		elif not (off_raw is Vector2):
			entry["offset"] = Vector2(0.0, -10.0)
		out[csk] = entry
	return out


static func is_luxury_prop(prop_type: String) -> bool:
	if BalanceConfig.LUXURY_DECOR_TYPES.has(prop_type):
		return true
	var cat: Dictionary = get_effective_build_catalog()
	if cat.has(prop_type):
		return str((cat[prop_type] as Dictionary).get("category", "")) == "decor"
	return false
