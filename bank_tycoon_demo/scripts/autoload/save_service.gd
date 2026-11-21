extends Node

## M1 baseline stub for SaveService.
## M1 stub: Result/BankState parameters and returns are typed as Variant until M2 defines them;
## M3 will restore strict BankState/Result types and implement atomic save_version=1 persistence.

const SAVE_VERSION: int = 1


func save_slot(_slot_id: String, _bank_state: Variant, _metadata: Dictionary = {}) -> Variant:
	return null


func load_slot(_slot_id: String) -> Variant:
	return null


func list_slots() -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	return empty


func delete_slot(_slot_id: String) -> Variant:
	return null


func get_slot_path(slot_id: String) -> String:
	var safe_slot_id: String = slot_id.replace("/", "_").replace("\\", "_").replace("..", "_")
	if safe_slot_id.is_empty():
		safe_slot_id = "autosave"
	return "user://saves/%s.json" % safe_slot_id
