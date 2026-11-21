class_name PixelCamera2D
extends Camera2D

## Pixel-perfect Camera2D with strict integer zoom steps (1x, 2x, 3x) and rounded panning.

const MIN_ZOOM_STEP: int = 1
const MAX_ZOOM_STEP: int = 3
const DEFAULT_CENTER: Vector2 = Vector2(604.0, 338.0)
const PAN_SPEED_PX: float = 220.0
const PAN_BOUNDS: Rect2 = Rect2(110.0, 55.0, 920.0, 570.0)

var zoom_step: int = 2
var _dragging: bool = false
var _pan_accum: Vector2 = DEFAULT_CENTER


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	zoom_step = 2
	zoom = Vector2(2.0, 2.0)
	position = DEFAULT_CENTER.round()
	_pan_accum = position


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_zoom_step(zoom_step)
	focus_world_position(position)


func set_zoom_step(step: int) -> void:
	zoom_step = clampi(step, MIN_ZOOM_STEP, MAX_ZOOM_STEP)
	var z: float = float(zoom_step)
	zoom = Vector2(z, z)


func get_zoom_step() -> int:
	return zoom_step


func focus_world_position(pos: Vector2) -> void:
	var clamped := Vector2(
		clampf(pos.x, PAN_BOUNDS.position.x, PAN_BOUNDS.end.x),
		clampf(pos.y, PAN_BOUNDS.position.y, PAN_BOUNDS.end.y)
	)
	_pan_accum = clamped
	position = clamped.round()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				set_zoom_step(zoom_step + 1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				set_zoom_step(zoom_step - 1)
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var delta_world: Vector2 = mm.relative / float(maxi(1, zoom_step))
		focus_world_position(_pan_accum - delta_world)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		var step_vec: Vector2 = dir.normalized() * (PAN_SPEED_PX / float(maxi(1, zoom_step))) * delta
		focus_world_position(_pan_accum + step_vec)
