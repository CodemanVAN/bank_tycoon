extends Node

## Runtime registry for validated static content definitions.
## The data loader and schema validator are intentionally deferred to backlog tasks.

var definitions: Dictionary = {}

func register_definition(content_id: String, definition: Dictionary) -> bool:
    if content_id.is_empty():
        push_error("ContentRegistry: content_id cannot be empty.")
        return false
    if definitions.has(content_id):
        push_error("ContentRegistry: duplicate content id: %s" % content_id)
        return false
    definitions[content_id] = definition.duplicate(true)
    return true

func get_definition(content_id: String) -> Dictionary:
    if not definitions.has(content_id):
        return {}
    return definitions[content_id].duplicate(true)
