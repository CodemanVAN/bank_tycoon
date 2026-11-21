class_name ActorView
extends Node2D

## Visual Node2D representation of an employee or customer with 4x4 sprite sheet animation and path interpolation.

const ANIM_ROW_IDLE: int = 0
const ANIM_ROW_WALK: int = 1
const ANIM_ROW_WORK: int = 2
const ANIM_ROW_TALK: int = 3
const ANIM_FPS: float = 6.0
const WALK_SPEED_PX: float = 82.0

const COLOR_CYAN_GLOW: Color = Color("#00C6FF")
const COLOR_GREEN: Color = Color("#35C978")
const COLOR_GOLD: Color = Color("#FFC857")
const COLOR_RED: Color = Color("#E74C3C")
const COLOR_NAVY_BG: Color = Color(0.031, 0.106, 0.212, 0.9)
const COLOR_OUTLINE: Color = Color("#10203B")

const FALLBACK_EMP_TEX: String = "res://assets/characters/emp_teller_f.png"
const FALLBACK_CUST_TEX: String = "res://assets/characters/cust_regular.png"

var actor_kind: StringName = &"employee"
var actor_id: String = ""
var avatar_id: String = "emp_teller_f"
var grid_pos: Vector2i = Vector2i.ZERO
var target_grid_pos: Vector2i = Vector2i.ZERO
var actor_state: int = 0
var is_selected: bool = false

# Status bar ratios (0.0 .. 1.0)
var patience_ratio: float = 1.0
var fatigue_ratio: float = 0.0

var _sprite: Sprite2D = null
var _loaded_avatar: String = ""
var _anim_row: int = ANIM_ROW_IDLE
var _anim_col: int = 0
var _anim_timer: float = 0.0
var _waypoints: Array[Vector2] = []


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_sprite()
	_refresh_sprite_texture()
	_update_anim_row()


func configure_employee(emp: Variant, screen_pos: Vector2) -> void:
	actor_kind = &"employee"
	if emp is Object:
		var obj: Object = emp as Object
		actor_id = str(obj.get("id"))
		avatar_id = str(obj.get("avatar_id"))
		var gp: Variant = obj.get("grid_pos")
		if gp is Vector2i:
			grid_pos = gp as Vector2i
		var tgp: Variant = obj.get("target_grid_pos")
		if tgp is Vector2i:
			target_grid_pos = tgp as Vector2i
		actor_state = int(obj.get("state"))
		fatigue_ratio = clampf(float(int(obj.get("fatigue"))) / 100.0, 0.0, 1.0)
	_ensure_sprite()
	_refresh_sprite_texture()
	if _waypoints.is_empty() and position == Vector2.ZERO:
		position = screen_pos.round()
	_update_anim_row()
	queue_redraw()


func configure_customer(cust: Variant, screen_pos: Vector2) -> void:
	actor_kind = &"customer"
	if cust is Object:
		var obj: Object = cust as Object
		actor_id = str(obj.get("id"))
		avatar_id = str(obj.get("avatar_id"))
		var gp: Variant = obj.get("grid_pos")
		if gp is Vector2i:
			grid_pos = gp as Vector2i
		var tgp: Variant = obj.get("target_grid_pos")
		if tgp is Vector2i:
			target_grid_pos = tgp as Vector2i
		actor_state = int(obj.get("state"))
		var p_max: int = maxi(1, int(obj.get("patience_max")))
		var p_rem: int = clampi(int(obj.get("patience_remaining")), 0, p_max)
		patience_ratio = clampf(float(p_rem) / float(p_max), 0.0, 1.0)
	_ensure_sprite()
	_refresh_sprite_texture()
	if _waypoints.is_empty() and position == Vector2.ZERO:
		position = screen_pos.round()
	_update_anim_row()
	queue_redraw()


func set_screen_path(points: Array[Vector2]) -> void:
	_waypoints.clear()
	for pt in points:
		var rpt: Vector2 = pt.round()
		if rpt.distance_to(position) > 1.0:
			_waypoints.append(rpt)
	_update_anim_row()


func snap_to_screen(screen_pos: Vector2) -> void:
	_waypoints.clear()
	position = screen_pos.round()
	_update_anim_row()


func set_selected(selected: bool) -> void:
	if is_selected != selected:
		is_selected = selected
		queue_redraw()


func get_hit_rect() -> Rect2:
	return Rect2(-12.0, -30.0, 24.0, 32.0)


func _ensure_sprite() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "CharacterSprite"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.centered = true
		_sprite.hframes = 4
		_sprite.vframes = 4
		_sprite.offset = Vector2(0.0, -14.0)
		add_child(_sprite)


func _refresh_sprite_texture() -> void:
	if _sprite == null:
		return
	var desired: String = avatar_id.strip_edges()
	if desired.is_empty():
		desired = "emp_teller_f" if actor_kind == &"employee" else "cust_regular"
	if _loaded_avatar == desired and _sprite.texture != null:
		return
	_loaded_avatar = desired
	var candidate_path: String = "res://assets/characters/%s.png" % desired
	if not ResourceLoader.exists(candidate_path):
		candidate_path = FALLBACK_EMP_TEX if actor_kind == &"employee" else FALLBACK_CUST_TEX
	if ResourceLoader.exists(candidate_path):
		_sprite.texture = load(candidate_path) as Texture2D


func _update_anim_row() -> void:
	var new_row: int = ANIM_ROW_IDLE
	if not _waypoints.is_empty():
		new_row = ANIM_ROW_WALK
	elif actor_kind == &"employee":
		match actor_state:
			Enums.EmployeeState.MOVING:
				new_row = ANIM_ROW_WALK
			Enums.EmployeeState.WORKING, Enums.EmployeeState.OVERLOADED:
				new_row = ANIM_ROW_WORK
			_:
				new_row = ANIM_ROW_IDLE
	else:
		match actor_state:
			Enums.CustomerState.SPAWNING, Enums.CustomerState.FINDING_SERVICE, Enums.CustomerState.LEAVING:
				new_row = ANIM_ROW_WALK
			Enums.CustomerState.IN_SERVICE:
				new_row = ANIM_ROW_TALK
			_:
				new_row = ANIM_ROW_IDLE

	if new_row != _anim_row:
		_anim_row = new_row
		_anim_col = 0
	if _sprite != null:
		_sprite.frame_coords = Vector2i(_anim_col, _anim_row)


func _process(delta: float) -> void:
	# Path interpolation
	if not _waypoints.is_empty():
		var next_pt: Vector2 = _waypoints[0]
		var to_next: Vector2 = next_pt - position
		var dist: float = to_next.length()
		var step: float = WALK_SPEED_PX * delta
		if _sprite != null and absf(to_next.x) > 0.5:
			_sprite.flip_h = (to_next.x < 0.0)
		if dist <= step or dist <= 0.5:
			position = next_pt.round()
			_waypoints.remove_at(0)
			if _waypoints.is_empty():
				_update_anim_row()
		else:
			position = (position + to_next.normalized() * step).round()

	# Sprite frame cycling (~6 FPS)
	_anim_timer += delta
	var frame_interval: float = 1.0 / ANIM_FPS
	if _anim_timer >= frame_interval:
		_anim_timer = fmod(_anim_timer, frame_interval)
		_anim_col = (_anim_col + 1) % 4
		if _sprite != null:
			_sprite.frame_coords = Vector2i(_anim_col, _anim_row)


func _draw() -> void:
	# Foot ground shadow
	var shadow_pts := PackedVector2Array([
		Vector2(0.0, -3.0),
		Vector2(7.0, 0.0),
		Vector2(0.0, 3.0),
		Vector2(-7.0, 0.0),
	])
	draw_colored_polygon(shadow_pts, Color(0.0, 0.04, 0.1, 0.32))

	# Selection cyan ring
	if is_selected:
		var sel_ring := PackedVector2Array([
			Vector2(0.0, -6.0),
			Vector2(12.0, 0.0),
			Vector2(0.0, 6.0),
			Vector2(-12.0, 0.0),
			Vector2(0.0, -6.0),
		])
		var sel_fill := PackedVector2Array([
			Vector2(0.0, -5.0),
			Vector2(10.0, 0.0),
			Vector2(0.0, 5.0),
			Vector2(-10.0, 0.0),
		])
		draw_colored_polygon(sel_fill, Color(0.0, 0.776, 1.0, 0.25))
		draw_polyline(sel_ring, COLOR_CYAN_GLOW, 1.5, false)

	# Overhead status bubble / bar
	if actor_kind == &"customer":
		if actor_state == Enums.CustomerState.WAITING or actor_state == Enums.CustomerState.FINDING_SERVICE:
			var bar_bg := Rect2(-9.0, -33.0, 18.0, 4.0)
			draw_rect(bar_bg, COLOR_NAVY_BG, true)
			draw_rect(bar_bg, COLOR_OUTLINE, false, 1.0)
			var fill_w: float = roundf(16.0 * patience_ratio)
			var bar_col: Color = COLOR_GREEN
			if patience_ratio <= 0.28:
				bar_col = COLOR_RED
			elif patience_ratio <= 0.58:
				bar_col = COLOR_GOLD
			if fill_w > 0.0:
				draw_rect(Rect2(-8.0, -32.0, fill_w, 2.0), bar_col, true)
		elif actor_state == Enums.CustomerState.IN_SERVICE:
			var bub := Rect2(-7.0, -35.0, 14.0, 6.0)
			draw_rect(bub, COLOR_NAVY_BG, true)
			draw_rect(bub, COLOR_CYAN_GLOW, false, 1.0)
			draw_rect(Rect2(-4.0, -33.0, 2.0, 2.0), COLOR_CYAN_GLOW, true)
			draw_rect(Rect2(-1.0, -33.0, 2.0, 2.0), COLOR_GOLD, true)
			draw_rect(Rect2(2.0, -33.0, 2.0, 2.0), COLOR_CYAN_GLOW, true)
	else:
		# Employee overhead indicator
		if actor_state == Enums.EmployeeState.WORKING:
			var work_bub := Rect2(-8.0, -34.0, 16.0, 4.0)
			draw_rect(work_bub, COLOR_NAVY_BG, true)
			draw_rect(Rect2(-7.0, -33.0, 14.0, 2.0), COLOR_CYAN_GLOW, true)
		elif actor_state == Enums.EmployeeState.OVERLOADED or fatigue_ratio >= 0.8:
			var warn_bub := Rect2(-8.0, -34.0, 16.0, 4.0)
			draw_rect(warn_bub, COLOR_NAVY_BG, true)
			draw_rect(Rect2(-7.0, -33.0, 14.0, 2.0), COLOR_RED, true)
		elif actor_state == Enums.EmployeeState.BREAK:
			var rest_bub := Rect2(-8.0, -34.0, 16.0, 4.0)
			draw_rect(rest_bub, COLOR_NAVY_BG, true)
			draw_rect(Rect2(-7.0, -33.0, 14.0, 2.0), COLOR_GREEN, true)
