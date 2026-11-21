extends Node

## Session-level state only. Domain systems will be added in dedicated tasks.

var is_session_active: bool = false
var current_day: int = 1
var world_seed: int = 0

func start_new_session(seed_value: int) -> void:
    is_session_active = true
    current_day = 1
    world_seed = seed_value

func end_session() -> void:
    is_session_active = false
