extends Node

## M1 baseline stub for ContentRegistry.
## M3 will populate schema-validated core definitions and safe data-only Mod loading.


func reload_all(_mods_root: String = "user://mods") -> Dictionary:
	var loaded_mods: Array[Dictionary] = []
	var rejected_mods: Array[Dictionary] = []
	var errors: Array[String] = []
	return {
		"loaded_mods": loaded_mods,
		"rejected_mods": rejected_mods,
		"errors": errors,
		"counts": {},
	}


func get_definition(_content_id: String) -> Dictionary:
	return {}


func get_all_by_type(_kind: StringName) -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	return empty


func get_department_def(id: String) -> Dictionary:
	return get_definition(id)


func get_policy_def(id: String) -> Dictionary:
	return get_definition(id)


func get_event_def(id: String) -> Dictionary:
	return get_definition(id)


func get_trait_def(id: String) -> Dictionary:
	return get_definition(id)


func get_customer_def(id: String) -> Dictionary:
	return get_definition(id)


func get_loaded_mod_dependencies() -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	return empty
