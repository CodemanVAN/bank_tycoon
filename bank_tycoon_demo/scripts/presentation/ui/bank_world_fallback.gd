extends Node2D

## UI-side fallback BankWorld used ONLY when res://scenes/world/bank_world.tscn
## is not yet present during parallel build. Replaced automatically by GameRoot._enter_tree()
## when res://scenes/world/bank_world.tscn exists.

signal entity_selected(entity_type: StringName, entity_id: String)

var _sim_host: Variant = null
var _zoom_step: int = 1
var _camera: Camera2D = null
var _selected_type: StringName = &""
var _selected_id: String = ""


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	y_sort_enabled = true


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	y_sort_enabled = true
	if _camera == null:
		_camera = Camera2D.new()
		_camera.name = "PixelCamera2D"
		_camera.position = Vector2(528, 356)
		_camera.zoom = Vector2(1.0, 1.0)
		add_child(_camera)
	queue_redraw()


func bind_runtime(sim_host: Variant) -> void:
	_sim_host = sim_host
	queue_redraw()


func focus_entity(entity_type: StringName, entity_id: String) -> void:
	_selected_type = entity_type
	_selected_id = entity_id
	entity_selected.emit(entity_type, entity_id)
	queue_redraw()


func select_entity(entity_type: StringName, entity_id: String) -> void:
	_selected_type = entity_type
	_selected_id = entity_id
	entity_selected.emit(entity_type, entity_id)
	queue_redraw()


func set_camera_zoom_step(step: int) -> void:
	_zoom_step = clampi(step, 1, 3)
	if _camera != null:
		_camera.zoom = Vector2(float(_zoom_step), float(_zoom_step))
