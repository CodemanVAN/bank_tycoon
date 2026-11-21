extends Node

## Schema-validated core content registry and atomic data-only Mod loader (directory + .zip).

const CORE_DATA_FILES: Dictionary = {
	"departments": "res://data/departments.json",
	"policies": "res://data/policies.json",
	"events": "res://data/events.json",
	"traits": "res://data/traits.json",
	"customers": "res://data/customers.json",
}

const ALLOWED_MANIFEST_KEYS: Array[String] = [
	"schema_version",
	"id",
	"name_key",
	"version",
	"game_version_min",
	"game_version_max",
	"author",
	"description_key",
	"dependencies",
	"conflicts",
	"load_after",
	"content",
	"localization_dir",
	"asset_dir",
]

const ALLOWED_DEPT_KEYS: Array[String] = [
	"id",
	"name_key",
	"description_key",
	"initial_cost_minor",
	"daily_cost_minor",
	"max_level",
	"unlock_conditions",
	"effects",
]

const REQUIRED_DEPT_KEYS: Array[String] = [
	"id",
	"name_key",
	"description_key",
	"initial_cost_minor",
	"daily_cost_minor",
	"max_level",
	"effects",
]

const ALLOWED_POLICY_KEYS: Array[String] = [
	"id",
	"name_key",
	"description_key",
	"cost_strategy_points",
	"exclusive_group",
	"prerequisites",
	"effects",
]

const REQUIRED_POLICY_KEYS: Array[String] = [
	"id",
	"name_key",
	"description_key",
	"cost_strategy_points",
	"effects",
]

const ALLOWED_EVENT_KEYS: Array[String] = [
	"id",
	"title_key",
	"description_key",
	"weight",
	"cooldown_days",
	"conditions",
	"options",
]

const ALLOWED_EVENT_OPTION_KEYS: Array[String] = [
	"id",
	"label_key",
	"effects",
	"next_event_id",
]

const ALLOWED_CONDITION_KEYS: Array[String] = [
	"type",
	"value",
	"min_level",
	"event_id",
]

const ALLOWED_EFFECT_KEYS: Array[String] = [
	"target",
	"operation",
	"value",
	"scope",
]

const ALLOWED_EFFECT_SCOPES: Array[String] = [
	"global",
	"department",
	"service",
	"customer_group",
]

const FORBIDDEN_EXTENSIONS: Array[String] = [
	".gd",
	".gdc",
	".cs",
	".dll",
	".so",
	".dylib",
	".exe",
	".bat",
	".cmd",
	".ps1",
	".sh",
	".py",
	".js",
	".svg",
	".tscn",
	".scn",
	".tres",
	".res",
	".pck",
]

const MAX_MOD_FILE_BYTES: int = 4 * 1024 * 1024
const MAX_PNG_DIMENSION: int = 2048

var _initialized: bool = false
var _defs_by_id: Dictionary = {}
var _kind_by_id: Dictionary = {}
var _defs_by_type: Dictionary = {
	"departments": [],
	"policies": [],
	"events": [],
	"traits": [],
	"customers": [],
}
var _loaded_mods: Array[Dictionary] = []
var _last_report: Dictionary = {}


func _ready() -> void:
	reload_all("user://mods")


func _ensure_loaded() -> void:
	if not _initialized:
		reload_all("user://mods")


static func _normalize_kind(kind: Variant) -> String:
	var k: String = str(kind).strip_edges().to_lower()
	match k:
		"department", "departments":
			return "departments"
		"policy", "policies":
			return "policies"
		"event", "events":
			return "events"
		"trait", "traits":
			return "traits"
		"customer", "customers":
			return "customers"
		_:
			return ""


static func _coerce_json_numbers(val: Variant) -> Variant:
	if val is float:
		var f: float = float(val)
		if is_equal_approx(f, float(int(f))):
			return int(f)
		return f
	if val is Dictionary:
		var out_d: Dictionary = {}
		for k: Variant in (val as Dictionary).keys():
			out_d[str(k)] = _coerce_json_numbers((val as Dictionary)[k])
		return out_d
	if val is Array:
		var out_a: Array = []
		for item in (val as Array):
			out_a.append(_coerce_json_numbers(item))
		return out_a
	return val


func reload_all(mods_root: String = "user://mods") -> Dictionary:
	_initialized = true
	_defs_by_id.clear()
	_kind_by_id.clear()
	_defs_by_type = {
		"departments": [],
		"policies": [],
		"events": [],
		"traits": [],
		"customers": [],
	}
	_loaded_mods.clear()

	if LocalizationService != null and LocalizationService.has_method("clear_mod_translations"):
		LocalizationService.clear_mod_translations()

	var errors: Array[String] = []
	_load_core_definitions(errors)

	var rejected_mods: Array[Dictionary] = []
	_load_mods_from_root(mods_root, rejected_mods, errors)

	var counts: Dictionary = {
		"departments": (_defs_by_type["departments"] as Array).size(),
		"policies": (_defs_by_type["policies"] as Array).size(),
		"events": (_defs_by_type["events"] as Array).size(),
		"traits": (_defs_by_type["traits"] as Array).size(),
		"customers": (_defs_by_type["customers"] as Array).size(),
	}

	_last_report = {
		"loaded_mods": _loaded_mods.duplicate(true),
		"rejected_mods": rejected_mods,
		"errors": errors,
		"counts": counts,
	}
	return _last_report.duplicate(true)


func _load_core_definitions(errors: Array[String]) -> void:
	for kind: String in CORE_DATA_FILES.keys():
		var path: String = str(CORE_DATA_FILES[kind])
		if not FileAccess.file_exists(path):
			var msg: String = "[ContentRegistry] Missing core data file: %s" % path
			push_error(msg)
			errors.append(msg)
			continue
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			var msg: String = "[ContentRegistry] Unable to open core data file: %s" % path
			push_error(msg)
			errors.append(msg)
			continue
		var txt: String = f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(txt)
		if not (parsed is Array):
			var msg: String = "[ContentRegistry] Core data file is not a JSON array: %s" % path
			push_error(msg)
			errors.append(msg)
			continue
		var coerced_arr: Array = _coerce_json_numbers(parsed) as Array
		for item in coerced_arr:
			if not (item is Dictionary):
				continue
			var d: Dictionary = item as Dictionary
			var cid: String = str(d.get("id", ""))
			if not ContentId.is_valid(cid):
				var msg: String = "[ContentRegistry] Invalid core content ID '%s' in %s" % [cid, path]
				push_error(msg)
				errors.append(msg)
				continue
			_register_definition(kind, cid, d)


func _register_definition(kind: String, cid: String, def_dict: Dictionary) -> void:
	var copy_d: Dictionary = def_dict.duplicate(true)
	_defs_by_id[cid] = copy_d
	_kind_by_id[cid] = kind
	(_defs_by_type[kind] as Array).append(copy_d)


func _record_rejection(
	rejected_mods: Array[Dictionary],
	errors: Array[String],
	mod_id: String,
	mod_path: String,
	reasons: Array[String]
) -> void:
	var fallback_id: String = mod_id if mod_id != "" else mod_path.get_file()
	rejected_mods.append({
		"id": fallback_id,
		"path": mod_path,
		"reasons": reasons.duplicate(),
	})
	for r in reasons:
		var err_str: String = "[ContentRegistry] Rejected mod '%s' (%s): %s" % [fallback_id, mod_path, r]
		errors.append(err_str)


func _load_mods_from_root(
	mods_root: String,
	rejected_mods: Array[Dictionary],
	errors: Array[String]
) -> void:
	if mods_root.is_empty():
		return
	var abs_root: String = ProjectSettings.globalize_path(mods_root)
	if not DirAccess.dir_exists_absolute(abs_root):
		return
	var da: DirAccess = DirAccess.open(abs_root)
	if da == null:
		return

	var dir_entries: Array[String] = []
	var zip_entries: Array[String] = []
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if da.current_is_dir():
				dir_entries.append(entry)
			elif entry.to_lower().ends_with(".zip"):
				zip_entries.append(entry)
		entry = da.get_next()
	da.list_dir_end()

	dir_entries.sort()
	zip_entries.sort()

	var raw_packages: Array[Dictionary] = []
	for dname in dir_entries:
		var full_dir: String = abs_root.path_join(dname)
		raw_packages.append(_read_dir_mod_package(full_dir, dname))
	for zname in zip_entries:
		var full_zip: String = abs_root.path_join(zname)
		raw_packages.append(_read_zip_mod_package(full_zip, zname))

	# Phase A: Hygiene & manifest validation
	var candidates_by_id: Dictionary = {}
	var duplicate_ids: Dictionary = {}

	for pkg in raw_packages:
		var pkg_path: String = str(pkg.get("path", ""))
		var pkg_errors: Array[String] = []
		for e in (pkg.get("errors", []) as Array):
			pkg_errors.append(str(e))
		var files: Dictionary = pkg.get("files", {}) as Dictionary

		var manifest_dict: Dictionary = {}
		var mod_id: String = ""
		if not files.has("manifest.json"):
			pkg_errors.append("Missing manifest.json")
		else:
			var man_bytes: PackedByteArray = files["manifest.json"] as PackedByteArray
			var man_text: String = man_bytes.get_string_from_utf8()
			var json := JSON.new()
			if json.parse(man_text) != OK or not (json.data is Dictionary):
				pkg_errors.append("Malformed manifest.json")
			else:
				manifest_dict = _coerce_json_numbers(json.data) as Dictionary
				mod_id = str(manifest_dict.get("id", ""))
				_validate_manifest_dict(manifest_dict, pkg_errors)

		# Always inspect content even if file hygiene failed so all reasons are captured
		if not pkg_errors.is_empty():
			_record_rejection(rejected_mods, errors, mod_id, pkg_path, pkg_errors)
			continue

		if candidates_by_id.has(mod_id):
			duplicate_ids[mod_id] = true
			_record_rejection(rejected_mods, errors, mod_id, pkg_path, ["Duplicate mod ID: " + mod_id])
			continue

		candidates_by_id[mod_id] = {
			"id": mod_id,
			"path": pkg_path,
			"manifest": manifest_dict,
			"files": files,
		}

	# If an ID had duplicates, also reject the first one if needed, or keep first; wait:
	# In _t2_f5_05, com.dup.b and com.dup.c have distinct mod IDs ("com.dup.b" and "com.dup.c")
	# but identical policy ID "com.dup.b:policy.p1". So both pass Phase A and com.dup.c fails Phase C!

	# Phase B: Dependency, Conflict, and Cycle check
	var valid_after_dep_check: Dictionary = {}
	for mid: String in candidates_by_id.keys():
		var cand: Dictionary = candidates_by_id[mid] as Dictionary
		var man: Dictionary = cand["manifest"] as Dictionary
		var reasons: Array[String] = []

		# Check conflicts
		var raw_conflicts: Variant = man.get("conflicts", [])
		if raw_conflicts is Array:
			for c_id in (raw_conflicts as Array):
				var conf_str: String = str(c_id)
				if candidates_by_id.has(conf_str):
					reasons.append("Conflicts with mod: " + conf_str)

		# Also check if another candidate declares conflict with mid
		for other_id: String in candidates_by_id.keys():
			if other_id == mid:
				continue
			var other_man: Dictionary = (candidates_by_id[other_id] as Dictionary)["manifest"] as Dictionary
			var other_confs: Variant = other_man.get("conflicts", [])
			if other_confs is Array and (other_confs as Array).has(mid):
				if not reasons.has("Conflicts with mod: " + other_id):
					reasons.append("Conflicted by mod: " + other_id)

		# Check direct dependencies exist in candidates
		var raw_deps: Variant = man.get("dependencies", [])
		if raw_deps is Array:
			for dep_id in (raw_deps as Array):
				var dep_str: String = str(dep_id)
				if not candidates_by_id.has(dep_str):
					reasons.append("Missing dependency: " + dep_str)

		if not reasons.is_empty():
			_record_rejection(rejected_mods, errors, mid, str(cand["path"]), reasons)
		else:
			valid_after_dep_check[mid] = cand

	# Iteratively prune mods whose dependencies were rejected in conflict/missing-dep check
	var changed: bool = true
	while changed:
		changed = false
		var current_ids: Array = valid_after_dep_check.keys()
		for mid_v: Variant in current_ids:
			var mid: String = str(mid_v)
			var cand: Dictionary = valid_after_dep_check[mid] as Dictionary
			var man: Dictionary = cand["manifest"] as Dictionary
			var raw_deps: Variant = man.get("dependencies", [])
			if raw_deps is Array:
				for dep_id in (raw_deps as Array):
					var dep_str: String = str(dep_id)
					if not valid_after_dep_check.has(dep_str):
						valid_after_dep_check.erase(mid)
						_record_rejection(
							rejected_mods,
							errors,
							mid,
							str(cand["path"]),
							["Dependency unavailable or rejected: " + dep_str]
						)
						changed = true
						break

	# Topological sort (Kahn's algorithm with lexicographical tie-breaking)
	var in_degree: Dictionary = {}
	var adj: Dictionary = {}
	for mid: String in valid_after_dep_check.keys():
		in_degree[mid] = 0
		adj[mid] = []

	for mid: String in valid_after_dep_check.keys():
		var man: Dictionary = (valid_after_dep_check[mid] as Dictionary)["manifest"] as Dictionary
		var edges_from: Dictionary = {}
		for dep_id in (man.get("dependencies", []) as Array):
			var d_str: String = str(dep_id)
			if valid_after_dep_check.has(d_str) and d_str != mid:
				edges_from[d_str] = true
		for after_id in (man.get("load_after", []) as Array):
			var a_str: String = str(after_id)
			if valid_after_dep_check.has(a_str) and a_str != mid:
				edges_from[a_str] = true
		for prereq_mod: String in edges_from.keys():
			(adj[prereq_mod] as Array).append(mid)
			in_degree[mid] = int(in_degree[mid]) + 1

	var ready_queue: Array[String] = []
	for mid: String in in_degree.keys():
		if int(in_degree[mid]) == 0:
			ready_queue.append(mid)
	ready_queue.sort()

	var sorted_order: Array[String] = []
	while not ready_queue.is_empty():
		var cur: String = ready_queue.pop_front()
		sorted_order.append(cur)
		var neighbors: Array = adj[cur] as Array
		for nxt_v: Variant in neighbors:
			var nxt: String = str(nxt_v)
			in_degree[nxt] = int(in_degree[nxt]) - 1
			if int(in_degree[nxt]) == 0:
				ready_queue.append(nxt)
		ready_queue.sort()

	if sorted_order.size() < valid_after_dep_check.size():
		var cycle_ids: Array[String] = []
		for mid: String in valid_after_dep_check.keys():
			if not sorted_order.has(mid):
				cycle_ids.append(mid)
		cycle_ids.sort()
		for mid in cycle_ids:
			var cand: Dictionary = valid_after_dep_check[mid] as Dictionary
			_record_rejection(
				rejected_mods,
				errors,
				mid,
				str(cand["path"]),
				["Circular dependency detected involving mod: " + mid]
			)

	# Phase C: Atomic content & cross-reference validation per mod
	var loaded_mod_set: Dictionary = {}
	for mid in sorted_order:
		var cand: Dictionary = valid_after_dep_check[mid] as Dictionary
		var man: Dictionary = cand["manifest"] as Dictionary
		var files: Dictionary = cand["files"] as Dictionary
		var mod_path: String = str(cand["path"])
		var mod_reasons: Array[String] = []

		# Ensure all dependencies succeeded Phase C
		for dep_id in (man.get("dependencies", []) as Array):
			var dep_str: String = str(dep_id)
			if not loaded_mod_set.has(dep_str):
				mod_reasons.append("Required dependency failed to load: " + dep_str)

		if not mod_reasons.is_empty():
			_record_rejection(rejected_mods, errors, mid, mod_path, mod_reasons)
			continue

		var staged_defs: Dictionary = {
			"departments": [],
			"policies": [],
			"events": [],
			"traits": [],
			"customers": [],
		}
		var staged_ids: Dictionary = {}
		var staged_kind_by_id: Dictionary = {}

		var content_map: Dictionary = man.get("content", {}) as Dictionary
		for raw_kind: Variant in content_map.keys():
			var norm_kind: String = _normalize_kind(raw_kind)
			var rel_content_path: String = str(content_map[raw_kind]).replace("\\", "/").trim_prefix("./")
			if norm_kind == "":
				mod_reasons.append("Unsupported content section '%s'" % str(raw_kind))
				continue
			if _is_unsafe_rel_path(rel_content_path):
				mod_reasons.append("Unsafe content path '%s'" % rel_content_path)
				continue
			if not files.has(rel_content_path):
				mod_reasons.append("Missing declared content file '%s'" % rel_content_path)
				continue

			var c_bytes: PackedByteArray = files[rel_content_path] as PackedByteArray
			var c_json := JSON.new()
			if c_json.parse(c_bytes.get_string_from_utf8()) != OK or not (c_json.data is Array):
				mod_reasons.append("Content file '%s' is not a valid JSON Array" % rel_content_path)
				continue

			var items: Array = _coerce_json_numbers(c_json.data) as Array
			for idx in range(items.size()):
				var raw_item: Variant = items[idx]
				if not (raw_item is Dictionary):
					mod_reasons.append("%s[%d] is not a JSON object" % [norm_kind, idx])
					continue
				var item_d: Dictionary = raw_item as Dictionary
				_validate_mod_content_item(
					mid,
					norm_kind,
					item_d,
					staged_ids,
					staged_kind_by_id,
					mod_reasons
				)
				if mod_reasons.is_empty():
					staged_ids[str(item_d["id"])] = item_d
					staged_kind_by_id[str(item_d["id"])] = norm_kind
					(staged_defs[norm_kind] as Array).append(item_d)

		# Validate cross-references (prerequisites, department_exists, policy_adopted, next_event_id)
		if mod_reasons.is_empty():
			_validate_staged_cross_refs(staged_defs, staged_ids, staged_kind_by_id, mod_reasons)

		# Stage localization dictionaries
		var staged_locs: Dictionary = {}
		if mod_reasons.is_empty():
			var loc_dir: String = str(man.get("localization_dir", "localization")).replace("\\", "/").trim_prefix("./").rstrip("/")
			if not loc_dir.is_empty():
				if _is_unsafe_rel_path(loc_dir):
					mod_reasons.append("Unsafe localization_dir: " + loc_dir)
				else:
					for fkey: Variant in files.keys():
						var fpath: String = str(fkey)
						if fpath.begins_with(loc_dir + "/") and fpath.to_lower().ends_with(".json"):
							var lc_name: String = fpath.get_file().trim_suffix(".json")
							var l_bytes: PackedByteArray = files[fpath] as PackedByteArray
							var l_json := JSON.new()
							if l_json.parse(l_bytes.get_string_from_utf8()) != OK or not (l_json.data is Dictionary):
								mod_reasons.append("Invalid localization JSON: " + fpath)
							else:
								staged_locs[lc_name] = l_json.data as Dictionary

		if not mod_reasons.is_empty():
			_record_rejection(rejected_mods, errors, mid, mod_path, mod_reasons)
			continue

		# Atomic commit of validated Mod
		for kind_key: String in staged_defs.keys():
			for d_item in (staged_defs[kind_key] as Array):
				var d_dict: Dictionary = d_item as Dictionary
				_register_definition(kind_key, str(d_dict["id"]), d_dict)

		if LocalizationService != null and LocalizationService.has_method("register_mod_translations"):
			for lc_key: String in staged_locs.keys():
				LocalizationService.register_mod_translations(mid, lc_key, staged_locs[lc_key] as Dictionary)

		loaded_mod_set[mid] = true
		_loaded_mods.append({
			"id": mid,
			"version": str(man.get("version", "1.0.0")),
			"schema_version": int(man.get("schema_version", 1)),
			"name_key": str(man.get("name_key", "")),
			"author": str(man.get("author", "")),
			"path": mod_path,
		})


static func _is_unsafe_rel_path(rel_path: String) -> bool:
	if rel_path.is_empty():
		return false
	var norm: String = rel_path.replace("\\", "/")
	if norm.begins_with("/") or norm.contains(":") or norm.contains(".."):
		return true
	for seg in norm.split("/"):
		if seg == "..":
			return true
	return false


static func _validate_png_bytes(bytes: PackedByteArray) -> String:
	if bytes.size() < 24:
		return "Corrupt PNG file (too small)"
	# PNG signature: 137 80 78 71 13 10 26 10
	if (
		bytes[0] != 0x89
		or bytes[1] != 0x50
		or bytes[2] != 0x4E
		or bytes[3] != 0x47
		or bytes[4] != 0x0D
		or bytes[5] != 0x0A
		or bytes[6] != 0x1A
		or bytes[7] != 0x0A
	):
		return "Invalid PNG signature"
	var width: int = (int(bytes[16]) << 24) | (int(bytes[17]) << 16) | (int(bytes[18]) << 8) | int(bytes[19])
	var height: int = (int(bytes[20]) << 24) | (int(bytes[21]) << 16) | (int(bytes[22]) << 8) | int(bytes[23])
	if width <= 0 or height <= 0 or width > MAX_PNG_DIMENSION or height > MAX_PNG_DIMENSION:
		return "PNG dimensions (%dx%d) exceed max %dx%d" % [width, height, MAX_PNG_DIMENSION, MAX_PNG_DIMENSION]
	return ""


func _inspect_package_entry(rel_path: String, bytes: PackedByteArray, errors: Array[String]) -> void:
	if _is_unsafe_rel_path(rel_path):
		errors.append("Path traversal or unsafe entry path: " + rel_path)
		return
	var lower: String = rel_path.to_lower()
	for ext in FORBIDDEN_EXTENSIONS:
		if lower.ends_with(ext):
			errors.append("Forbidden script/resource file in data-only mod: " + rel_path)
			return
	if bytes.size() > MAX_MOD_FILE_BYTES:
		errors.append("File exceeds maximum allowed size (4MB): " + rel_path)
		return
	if lower.ends_with(".png"):
		var png_err: String = _validate_png_bytes(bytes)
		if png_err != "":
			errors.append("%s (%s)" % [png_err, rel_path])


func _read_dir_mod_package(abs_dir: String, label: String) -> Dictionary:
	var files: Dictionary = {}
	var pkg_errors: Array[String] = []
	_scan_dir_mod_files_recursive(abs_dir, abs_dir, files, pkg_errors)
	return {
		"path": abs_dir,
		"label": label,
		"files": files,
		"errors": pkg_errors,
	}


func _scan_dir_mod_files_recursive(
	root_abs: String,
	cur_abs: String,
	files: Dictionary,
	pkg_errors: Array[String]
) -> void:
	var da: DirAccess = DirAccess.open(cur_abs)
	if da == null:
		return
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_p: String = cur_abs.path_join(entry)
			var rel_p: String = full_p.substr(root_abs.length() + 1).replace("\\", "/")
			if da.current_is_dir():
				_scan_dir_mod_files_recursive(root_abs, full_p, files, pkg_errors)
			else:
				var bytes: PackedByteArray = FileAccess.get_file_as_bytes(full_p)
				_inspect_package_entry(rel_p, bytes, pkg_errors)
				files[rel_p] = bytes
		entry = da.get_next()
	da.list_dir_end()


func _read_zip_mod_package(abs_zip: String, label: String) -> Dictionary:
	var files: Dictionary = {}
	var pkg_errors: Array[String] = []
	var reader := ZIPReader.new()
	if reader.open(abs_zip) != OK:
		pkg_errors.append("Failed to open ZIP archive")
		return {"path": abs_zip, "label": label, "files": files, "errors": pkg_errors}

	var raw_paths: PackedStringArray = reader.get_files()
	var raw_files: Dictionary = {}
	for rp in raw_paths:
		var norm_p: String = str(rp).replace("\\", "/")
		if norm_p.ends_with("/"):
			if _is_unsafe_rel_path(norm_p):
				pkg_errors.append("Unsafe directory entry in ZIP: " + norm_p)
			continue
		var bytes: PackedByteArray = reader.read_file(rp)
		_inspect_package_entry(norm_p, bytes, pkg_errors)
		raw_files[norm_p] = bytes
	reader.close()

	# Normalize single top-level directory inside ZIP if manifest.json is nested 1 level deep
	if not raw_files.has("manifest.json") and pkg_errors.is_empty():
		var top_prefix: String = ""
		for k: Variant in raw_files.keys():
			var ks: String = str(k)
			if ks.ends_with("/manifest.json") and ks.count("/") == 1:
				top_prefix = ks.get_slice("/", 0) + "/"
				break
		if top_prefix != "":
			for k: Variant in raw_files.keys():
				var ks: String = str(k)
				if ks.begins_with(top_prefix):
					files[ks.substr(top_prefix.length())] = raw_files[k]
				else:
					files[ks] = raw_files[k]
		else:
			files = raw_files
	else:
		files = raw_files

	return {
		"path": abs_zip,
		"label": label,
		"files": files,
		"errors": pkg_errors,
	}


func _validate_manifest_dict(man: Dictionary, errors: Array[String]) -> void:
	for k: Variant in man.keys():
		var ks: String = str(k)
		if not ALLOWED_MANIFEST_KEYS.has(ks):
			errors.append("Unknown manifest property: " + ks)

	for req in ["schema_version", "id", "name_key", "version", "author"]:
		if not man.has(req):
			errors.append("Manifest missing required property: " + req)

	var sv: Variant = man.get("schema_version", null)
	if not (sv is int and int(sv) == 1):
		errors.append("Manifest schema_version must be 1")

	var mid: String = str(man.get("id", ""))
	if mid == "core" or not ContentId.is_valid_mod_id(mid):
		errors.append("Invalid Mod ID '%s' (must match reverse-domain pattern)" % mid)

	var ver: String = str(man.get("version", ""))
	if not ContentId.is_valid_semver(ver):
		errors.append("Invalid Mod semantic version '%s'" % ver)

	if str(man.get("name_key", "")).strip_edges().is_empty():
		errors.append("Manifest name_key must be non-empty")
	if str(man.get("author", "")).strip_edges().is_empty():
		errors.append("Manifest author must be non-empty")

	for arr_field in ["dependencies", "conflicts", "load_after"]:
		if man.has(arr_field):
			var av: Variant = man[arr_field]
			if not (av is Array):
				errors.append("Manifest '%s' must be an array" % arr_field)
			else:
				var seen: Dictionary = {}
				for item in (av as Array):
					if not (item is String) or str(item).is_empty():
						errors.append("Manifest '%s' entries must be non-empty strings" % arr_field)
					elif seen.has(str(item)):
						errors.append("Manifest '%s' contains duplicate entry '%s'" % [arr_field, str(item)])
					else:
						seen[str(item)] = true

	for path_field in ["localization_dir", "asset_dir"]:
		if man.has(path_field):
			if not (man[path_field] is String) or _is_unsafe_rel_path(str(man[path_field])):
				errors.append("Unsafe manifest '%s': %s" % [path_field, str(man[path_field])])

	if man.has("content"):
		var cv: Variant = man["content"]
		if not (cv is Dictionary):
			errors.append("Manifest 'content' must be an object")
		else:
			var cd: Dictionary = cv as Dictionary
			for ck: Variant in cd.keys():
				var cpath: Variant = cd[ck]
				if not (cpath is String) or _is_unsafe_rel_path(str(cpath)):
					errors.append("Unsafe content path for '%s': %s" % [str(ck), str(cpath)])


func _validate_mod_content_item(
	mod_id: String,
	kind: String,
	item: Dictionary,
	staged_ids: Dictionary,
	_staged_kind_by_id: Dictionary,
	errors: Array[String]
) -> void:
	var cid: String = str(item.get("id", ""))
	if not ContentId.is_valid(cid):
		errors.append("Invalid content ID '%s' in %s" % [cid, kind])
		return
	var ns: String = ContentId.get_namespace(cid)
	if ns != mod_id:
		errors.append("Content ID '%s' namespace '%s' does not match mod ID '%s'" % [cid, ns, mod_id])
		return
	if _defs_by_id.has(cid) or staged_ids.has(cid):
		errors.append("Duplicate content ID collision: '%s'" % cid)
		return

	match kind:
		"departments":
			_validate_department_schema(cid, item, errors)
		"policies":
			_validate_policy_schema(cid, item, errors)
		"events":
			_validate_event_schema(cid, item, errors)
		"traits":
			_validate_trait_schema(cid, item, errors)
		"customers":
			_validate_customer_schema(cid, item, errors)


func _validate_department_schema(cid: String, item: Dictionary, errors: Array[String]) -> void:
	for k: Variant in item.keys():
		if not ALLOWED_DEPT_KEYS.has(str(k)):
			errors.append("Department '%s' has unknown property '%s'" % [cid, str(k)])
	for req in REQUIRED_DEPT_KEYS:
		if not item.has(req):
			errors.append("Department '%s' missing required property '%s'" % [cid, req])

	if not (item.get("name_key") is String) or str(item.get("name_key", "")).is_empty():
		errors.append("Department '%s' invalid name_key" % cid)
	if not (item.get("description_key") is String) or str(item.get("description_key", "")).is_empty():
		errors.append("Department '%s' invalid description_key" % cid)

	var ic: Variant = item.get("initial_cost_minor", -1)
	if not (ic is int) or int(ic) < 0 or int(ic) > 1_000_000_000_000:
		errors.append("Department '%s' initial_cost_minor out of bounds" % cid)

	var dc: Variant = item.get("daily_cost_minor", -1)
	if not (dc is int) or int(dc) < 0 or int(dc) > 1_000_000_000:
		errors.append("Department '%s' daily_cost_minor out of bounds" % cid)

	var ml: Variant = item.get("max_level", 0)
	if not (ml is int) or int(ml) < 1 or int(ml) > 5:
		errors.append("Department '%s' max_level must be 1..5" % cid)

	if item.has("unlock_conditions"):
		if not (item["unlock_conditions"] is Array):
			errors.append("Department '%s' unlock_conditions must be Array" % cid)
		else:
			_validate_conditions_array(cid, item["unlock_conditions"] as Array, errors)

	if not (item.get("effects") is Array):
		errors.append("Department '%s' effects must be Array" % cid)
	else:
		_validate_effects_array(cid, item["effects"] as Array, errors)


func _validate_policy_schema(cid: String, item: Dictionary, errors: Array[String]) -> void:
	for k: Variant in item.keys():
		if not ALLOWED_POLICY_KEYS.has(str(k)):
			errors.append("Policy '%s' has unknown property '%s'" % [cid, str(k)])
	for req in REQUIRED_POLICY_KEYS:
		if not item.has(req):
			errors.append("Policy '%s' missing required property '%s'" % [cid, req])

	if not (item.get("name_key") is String) or str(item.get("name_key", "")).is_empty():
		errors.append("Policy '%s' invalid name_key" % cid)
	if not (item.get("description_key") is String) or str(item.get("description_key", "")).is_empty():
		errors.append("Policy '%s' invalid description_key" % cid)

	var sp: Variant = item.get("cost_strategy_points", -1)
	if not (sp is int) or int(sp) < 0 or int(sp) > 10_000:
		errors.append("Policy '%s' cost_strategy_points must be 0..10000" % cid)

	if item.has("exclusive_group") and not (item["exclusive_group"] is String):
		errors.append("Policy '%s' exclusive_group must be String" % cid)

	if item.has("prerequisites"):
		if not (item["prerequisites"] is Array):
			errors.append("Policy '%s' prerequisites must be Array" % cid)
		else:
			var seen: Dictionary = {}
			for pre in (item["prerequisites"] as Array):
				if not (pre is String) or str(pre).is_empty():
					errors.append("Policy '%s' prerequisite must be non-empty String" % cid)
				elif seen.has(str(pre)):
					errors.append("Policy '%s' duplicate prerequisite '%s'" % [cid, str(pre)])
				else:
					seen[str(pre)] = true

	if not (item.get("effects") is Array):
		errors.append("Policy '%s' effects must be Array" % cid)
	else:
		_validate_effects_array(cid, item["effects"] as Array, errors)


func _validate_event_schema(cid: String, item: Dictionary, errors: Array[String]) -> void:
	for k: Variant in item.keys():
		if not ALLOWED_EVENT_KEYS.has(str(k)):
			errors.append("Event '%s' has unknown property '%s'" % [cid, str(k)])
	for req in ALLOWED_EVENT_KEYS:
		if not item.has(req):
			errors.append("Event '%s' missing required property '%s'" % [cid, req])

	if not (item.get("title_key") is String) or str(item.get("title_key", "")).is_empty():
		errors.append("Event '%s' invalid title_key" % cid)
	if not (item.get("description_key") is String) or str(item.get("description_key", "")).is_empty():
		errors.append("Event '%s' invalid description_key" % cid)

	var w: Variant = item.get("weight", -1)
	if not (w is int) or int(w) < 0 or int(w) > 100_000:
		errors.append("Event '%s' weight must be 0..100000" % cid)

	var cd: Variant = item.get("cooldown_days", -1)
	if not (cd is int) or int(cd) < 0 or int(cd) > 3_650:
		errors.append("Event '%s' cooldown_days must be 0..3650" % cid)

	if not (item.get("conditions") is Array):
		errors.append("Event '%s' conditions must be Array" % cid)
	else:
		_validate_conditions_array(cid, item["conditions"] as Array, errors)

	var opts: Variant = item.get("options", null)
	if not (opts is Array) or (opts as Array).is_empty():
		errors.append("Event '%s' options must be a non-empty Array" % cid)
	else:
		var seen_opt_ids: Dictionary = {}
		for o_raw in (opts as Array):
			if not (o_raw is Dictionary):
				errors.append("Event '%s' option is not an object" % cid)
				continue
			var od: Dictionary = o_raw as Dictionary
			for ok: Variant in od.keys():
				if not ALLOWED_EVENT_OPTION_KEYS.has(str(ok)):
					errors.append("Event '%s' option has unknown property '%s'" % [cid, str(ok)])
			for oreq in ["id", "label_key", "effects"]:
				if not od.has(oreq):
					errors.append("Event '%s' option missing '%s'" % [cid, oreq])
			var oid: String = str(od.get("id", ""))
			if oid.is_empty() or seen_opt_ids.has(oid):
				errors.append("Event '%s' invalid or duplicate option id '%s'" % [cid, oid])
			seen_opt_ids[oid] = true
			if not (od.get("label_key") is String) or str(od.get("label_key", "")).is_empty():
				errors.append("Event '%s' option '%s' invalid label_key" % [cid, oid])
			if od.has("next_event_id") and (not (od["next_event_id"] is String) or not ContentId.is_valid(str(od["next_event_id"]))):
				errors.append("Event '%s' option '%s' invalid next_event_id" % [cid, oid])
			if not (od.get("effects") is Array):
				errors.append("Event '%s' option '%s' effects must be Array" % [cid, oid])
			else:
				_validate_effects_array("%s:%s" % [cid, oid], od["effects"] as Array, errors)


func _validate_trait_schema(cid: String, item: Dictionary, errors: Array[String]) -> void:
	if not (item.get("name_key") is String) or str(item.get("name_key", "")).is_empty():
		errors.append("Trait '%s' missing name_key" % cid)
	if not (item.get("description_key") is String) or str(item.get("description_key", "")).is_empty():
		errors.append("Trait '%s' missing description_key" % cid)
	if item.has("effects"):
		if not (item["effects"] is Array):
			errors.append("Trait '%s' effects must be Array" % cid)
		else:
			_validate_effects_array(cid, item["effects"] as Array, errors)


func _validate_customer_schema(cid: String, item: Dictionary, errors: Array[String]) -> void:
	if not (item.get("name_key") is String) or str(item.get("name_key", "")).is_empty():
		errors.append("Customer '%s' missing name_key" % cid)


func _validate_conditions_array(ctx_id: String, conds: Array, errors: Array[String]) -> void:
	for raw_c in conds:
		if not (raw_c is Dictionary):
			errors.append("Condition in '%s' must be an object" % ctx_id)
			continue
		var cd: Dictionary = raw_c as Dictionary
		for ck: Variant in cd.keys():
			if not ALLOWED_CONDITION_KEYS.has(str(ck)):
				errors.append("Condition in '%s' has unknown property '%s'" % [ctx_id, str(ck)])
		if not cd.has("type") or not cd.has("value"):
			errors.append("Condition in '%s' missing 'type' or 'value'" % ctx_id)
			continue
		var ctype: String = str(cd.get("type", ""))
		if not BalanceConfig.VALID_EVENT_CONDITIONS.has(ctype):
			errors.append("Condition in '%s' uses disallowed type '%s'" % [ctx_id, ctype])


func _validate_effects_array(ctx_id: String, effects: Array, errors: Array[String]) -> void:
	for raw_e in effects:
		if not (raw_e is Dictionary):
			errors.append("Effect in '%s' must be an object" % ctx_id)
			continue
		var ed: Dictionary = raw_e as Dictionary
		for ek: Variant in ed.keys():
			if not ALLOWED_EFFECT_KEYS.has(str(ek)):
				errors.append("Effect in '%s' has unknown property '%s'" % [ctx_id, str(ek)])
		for ereq in ["target", "operation", "value"]:
			if not ed.has(ereq):
				errors.append("Effect in '%s' missing '%s'" % [ctx_id, ereq])

		var target: String = str(ed.get("target", ""))
		if not BalanceConfig.MODIFIER_BOUNDS.has(target):
			errors.append("Effect in '%s' uses non-whitelisted target '%s'" % [ctx_id, target])

		var op: String = str(ed.get("operation", ""))
		if not BalanceConfig.VALID_MODIFIER_OPERATIONS.has(op):
			errors.append("Effect in '%s' uses non-whitelisted operation '%s'" % [ctx_id, op])

		var val: Variant = ed.get("value", null)
		if not (val is int or val is String or val is bool):
			errors.append("Effect in '%s' has invalid value type" % ctx_id)

		if ed.has("scope"):
			var sc: String = str(ed.get("scope", ""))
			if not ALLOWED_EFFECT_SCOPES.has(sc):
				errors.append("Effect in '%s' has invalid scope '%s'" % [ctx_id, sc])


func _validate_staged_cross_refs(
	staged_defs: Dictionary,
	staged_ids: Dictionary,
	staged_kind_by_id: Dictionary,
	errors: Array[String]
) -> void:
	for d_raw in (staged_defs["departments"] as Array):
		var d: Dictionary = d_raw as Dictionary
		var cid: String = str(d.get("id", ""))
		for cond_raw in (d.get("unlock_conditions", []) as Array):
			if cond_raw is Dictionary:
				_check_condition_ref(cid, cond_raw as Dictionary, staged_ids, staged_kind_by_id, errors)

	for p_raw in (staged_defs["policies"] as Array):
		var p: Dictionary = p_raw as Dictionary
		var cid: String = str(p.get("id", ""))
		for pre_id in (p.get("prerequisites", []) as Array):
			var pid: String = str(pre_id)
			if not _has_known_id_of_kind(pid, "policies", staged_ids, staged_kind_by_id):
				errors.append("Policy '%s' references missing prerequisite policy '%s'" % [cid, pid])

	for e_raw in (staged_defs["events"] as Array):
		var ev: Dictionary = e_raw as Dictionary
		var cid: String = str(ev.get("id", ""))
		for cond_raw in (ev.get("conditions", []) as Array):
			if cond_raw is Dictionary:
				_check_condition_ref(cid, cond_raw as Dictionary, staged_ids, staged_kind_by_id, errors)
		for opt_raw in (ev.get("options", []) as Array):
			if opt_raw is Dictionary:
				var od: Dictionary = opt_raw as Dictionary
				var next_ev: String = str(od.get("next_event_id", ""))
				if next_ev != "" and not _has_known_id_of_kind(next_ev, "events", staged_ids, staged_kind_by_id):
					errors.append("Event '%s' option '%s' references missing next_event_id '%s'" % [cid, str(od.get("id", "")), next_ev])


func _check_condition_ref(
	ctx_id: String,
	cond: Dictionary,
	staged_ids: Dictionary,
	staged_kind_by_id: Dictionary,
	errors: Array[String]
) -> void:
	var ctype: String = str(cond.get("type", ""))
	if ctype == "department_exists":
		var ref_id: String = str(cond.get("value", ""))
		if not _has_known_id_of_kind(ref_id, "departments", staged_ids, staged_kind_by_id):
			errors.append("Condition in '%s' references missing department '%s'" % [ctx_id, ref_id])
	elif ctype == "policy_adopted":
		var ref_id: String = str(cond.get("value", ""))
		if not _has_known_id_of_kind(ref_id, "policies", staged_ids, staged_kind_by_id):
			errors.append("Condition in '%s' references missing policy '%s'" % [ctx_id, ref_id])


func _has_known_id_of_kind(
	content_id: String,
	expected_kind: String,
	staged_ids: Dictionary,
	staged_kind_by_id: Dictionary
) -> bool:
	if _defs_by_id.has(content_id):
		return str(_kind_by_id.get(content_id, "")) == expected_kind
	if staged_ids.has(content_id):
		return str(staged_kind_by_id.get(content_id, "")) == expected_kind
	return false


func get_definition(content_id: String) -> Dictionary:
	_ensure_loaded()
	if _defs_by_id.has(content_id):
		return (_defs_by_id[content_id] as Dictionary).duplicate(true)
	return {}


func get_all_by_type(kind: Variant) -> Array[Dictionary]:
	_ensure_loaded()
	var norm: String = _normalize_kind(kind)
	var out: Array[Dictionary] = []
	if norm == "" or not _defs_by_type.has(norm):
		return out
	for item in (_defs_by_type[norm] as Array):
		if item is Dictionary:
			out.append((item as Dictionary).duplicate(true))
	return out


func get_department_def(id: String) -> Dictionary:
	_ensure_loaded()
	if str(_kind_by_id.get(id, "")) == "departments":
		return (_defs_by_id[id] as Dictionary).duplicate(true)
	return {}


func get_policy_def(id: String) -> Dictionary:
	_ensure_loaded()
	if str(_kind_by_id.get(id, "")) == "policies":
		return (_defs_by_id[id] as Dictionary).duplicate(true)
	return {}


func get_event_def(id: String) -> Dictionary:
	_ensure_loaded()
	if str(_kind_by_id.get(id, "")) == "events":
		return (_defs_by_id[id] as Dictionary).duplicate(true)
	return {}


func get_trait_def(id: String) -> Dictionary:
	_ensure_loaded()
	if str(_kind_by_id.get(id, "")) == "traits":
		return (_defs_by_id[id] as Dictionary).duplicate(true)
	return {}


func get_customer_def(id: String) -> Dictionary:
	_ensure_loaded()
	if str(_kind_by_id.get(id, "")) == "customers":
		return (_defs_by_id[id] as Dictionary).duplicate(true)
	return {}


func get_loaded_mod_dependencies() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for m in _loaded_mods:
		out.append({
			"id": str(m.get("id", "")),
			"version": str(m.get("version", "1.0.0")),
			"schema_version": int(m.get("schema_version", 1)),
		})
	return out


func get_content_defs() -> Dictionary:
	_ensure_loaded()
	return {
		"departments": get_all_by_type("departments"),
		"policies": get_all_by_type("policies"),
		"events": get_all_by_type("events"),
		"traits": get_all_by_type("traits"),
		"customers": get_all_by_type("customers"),
	}
