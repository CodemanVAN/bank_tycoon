extends Node

## Save service API placeholder. Atomic JSON persistence is specified in docs/07.

const SAVE_VERSION: int = 1

func get_slot_path(slot_id: String) -> String:
    var safe_slot_id: String = slot_id.strip_edges().replace("/", "_").replace("\\", "_")
    return "user://saves/%s.json" % safe_slot_id
