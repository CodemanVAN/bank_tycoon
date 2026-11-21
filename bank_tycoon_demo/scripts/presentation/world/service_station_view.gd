class_name ServiceStationView
extends Node2D

## Visual Node2D representation of a bank service station (teller counter or loan desk).

const COLOR_CYAN_GLOW: Color = Color("#00C6FF")
const COLOR_OPEN_GREEN: Color = Color("#35C978")
const COLOR_OPEN_HIGHLIGHT: Color = Color("#6FE39F")
const COLOR_CLOSED_GREY: Color = Color("#526B8D")
const COLOR_STAFFED_GOLD: Color = Color("#FFC857")
const COLOR_OUTLINE_DARK: Color = Color("#10203B")
const COLOR_BADGE_BG: Color = Color(0.031, 0.106, 0.212, 0.88)
const COLOR_BADGE_BORDER: Color = Color("#263D5C")

const TEX_COUNTER_TELLER: String = "res://assets/environment/prop_counter_teller.png"
const TEX_DESK_LOAN: String = "res://assets/environment/prop_desk_loan.png"

var station_id: String = ""
var station_type: String = "teller"
var is_open: bool = true
var assigned_employee_id: String = ""
var grid_pos: Vector2i = Vector2i.ZERO
var is_selected: bool = false
var is_hovered: bool = false
var station_index: int = 1

var _sprite: Sprite2D = null
var _tag_label: Label = null
var _loaded_type: String = ""


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_nodes()
	_connect_locale_signal()
	_refresh_visuals()


func _connect_locale_signal() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var loc: Node = tree.root.get_node_or_null("LocalizationService")
		if loc != null and loc.has_signal("locale_changed"):
			if not loc.is_connected("locale_changed", _on_locale_changed):
				loc.connect("locale_changed", _on_locale_changed)


const WORLD_FALLBACK_I18N: Dictionary = {
	"zh_CN": {
		"WORLD_STATION_TELLER_TAG": "柜#{num}",
		"WORLD_STATION_LOAN_TAG": "贷#{num}",
	},
	"en": {
		"WORLD_STATION_TELLER_TAG": "T#{num}",
		"WORLD_STATION_LOAN_TAG": "L#{num}",
	},
	"ja": {
		"WORLD_STATION_TELLER_TAG": "窓#{num}",
		"WORLD_STATION_LOAN_TAG": "融#{num}",
	},
}


func _tr(key: String, params: Dictionary = {}) -> String:
	var locale: String = "zh_CN"
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var loc: Node = tree.root.get_node_or_null("LocalizationService")
		if loc != null:
			if loc.has_method("get_locale"):
				locale = str(loc.call("get_locale"))
			if loc.has_method("tr_key"):
				var res: String = str(loc.call("tr_key", key, params))
				if res != key and not res.begins_with("WORLD_"):
					return res
	var table: Dictionary = WORLD_FALLBACK_I18N.get(locale, WORLD_FALLBACK_I18N["zh_CN"]) as Dictionary
	var out: String = str(table.get(key, key))
	for k: Variant in params.keys():
		out = out.replace("{%s}" % str(k), str(params[k]))
	return out


func configure(station_data: Dictionary, screen_pos: Vector2, p_index: int = 1) -> void:
	station_id = str(station_data.get("station_id", station_id))
	station_type = str(station_data.get("station_type", "teller"))
	is_open = bool(station_data.get("is_open", true))
	assigned_employee_id = str(station_data.get("assigned_employee_id", ""))
	var raw_gp: Variant = station_data.get("grid_pos", grid_pos)
	if raw_gp is Vector2i:
		grid_pos = raw_gp as Vector2i
	elif raw_gp is Array and (raw_gp as Array).size() >= 2:
		var arr: Array = raw_gp as Array
		grid_pos = Vector2i(int(arr[0]), int(arr[1]))
	station_index = maxi(1, p_index)
	position = screen_pos.round()
	_ensure_nodes()
	_refresh_visuals()


func set_selected(selected: bool) -> void:
	if is_selected != selected:
		is_selected = selected
		_apply_label_visibility()
		queue_redraw()


func set_hovered(hovered: bool) -> void:
	if is_hovered != hovered:
		is_hovered = hovered
		_apply_label_visibility()
		queue_redraw()


## Counter tags are hidden until the player hovers the station (or selects it).
func _apply_label_visibility() -> void:
	if _tag_label != null:
		_tag_label.visible = is_hovered or is_selected


func get_hit_rect() -> Rect2:
	return Rect2(-24.0, -32.0, 48.0, 40.0)


func _ensure_nodes() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "StationSprite"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.centered = true
		add_child(_sprite)

	if _tag_label == null:
		_tag_label = Label.new()
		_tag_label.name = "TagLabel"
		_tag_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_tag_label.position = Vector2(-12.0, -35.0)
		_tag_label.size = Vector2(28.0, 12.0)
		_tag_label.scale = Vector2(0.75, 0.75)
		_tag_label.add_theme_font_size_override("font_size", 11)
		_tag_label.add_theme_color_override("font_color", Color("#F5F8FF"))
		_tag_label.visible = false
		add_child(_tag_label)


func _refresh_visuals() -> void:
	if _sprite != null:
		if _loaded_type != station_type or _sprite.texture == null:
			_loaded_type = station_type
			var tex_path: String = TEX_DESK_LOAN if station_type == "loan_desk" else TEX_COUNTER_TELLER
			if ResourceLoader.exists(tex_path):
				_sprite.texture = load(tex_path) as Texture2D
			_sprite.offset = Vector2(0.0, -8.0) if station_type == "loan_desk" else Vector2(0.0, -10.0)
		_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0) if is_open else Color(0.72, 0.77, 0.85, 0.92)

	if _tag_label != null:
		var num_str: String = _extract_station_number()
		var key: String = "WORLD_STATION_LOAN_TAG" if station_type == "loan_desk" else "WORLD_STATION_TELLER_TAG"
		_tag_label.text = _tr(key, {"num": num_str})

	queue_redraw()


func _extract_station_number() -> String:
	var parts: PackedStringArray = station_id.split("_")
	if parts.size() >= 2:
		var tail: String = parts[parts.size() - 1]
		if tail.is_valid_int():
			return tail
	return str(station_index)


func _on_locale_changed(_new_locale: String) -> void:
	_refresh_visuals()


func _draw() -> void:
	# Isometric ground shadow polygon
	var shadow_pts := PackedVector2Array([
		Vector2(0.0, -9.0),
		Vector2(20.0, 1.0),
		Vector2(0.0, 11.0),
		Vector2(-20.0, 1.0),
	])
	draw_colored_polygon(shadow_pts, Color(0.0, 0.04, 0.1, 0.28))

	# Selection cyan glow diamond
	if is_selected:
		var sel_outer := PackedVector2Array([
			Vector2(0.0, -12.0),
			Vector2(24.0, 0.0),
			Vector2(0.0, 12.0),
			Vector2(-24.0, 0.0),
			Vector2(0.0, -12.0),
		])
		var sel_fill := PackedVector2Array([
			Vector2(0.0, -11.0),
			Vector2(22.0, 0.0),
			Vector2(0.0, 11.0),
			Vector2(-22.0, 0.0),
		])
		draw_colored_polygon(sel_fill, Color(0.0, 0.776, 1.0, 0.22))
		draw_polyline(sel_outer, COLOR_CYAN_GLOW, 1.5, false)

	# Overhead status badge + tag are hover-only so room walls never clip them at rest.
	if is_hovered or is_selected:
		var pill_rect := Rect2(-18.0, -34.0, 36.0, 10.0)
		draw_rect(pill_rect, COLOR_BADGE_BG, true)
		var border_col: Color = COLOR_CYAN_GLOW if is_selected else COLOR_BADGE_BORDER
		draw_rect(pill_rect, border_col, false, 1.0)

		var led_pos := Vector2(-13.0, -29.0)
		draw_circle(led_pos, 3.0, COLOR_OUTLINE_DARK)
		var led_col: Color = COLOR_OPEN_GREEN if is_open else COLOR_CLOSED_GREY
		draw_circle(led_pos, 2.0, led_col)
		if is_open:
			draw_rect(Rect2(led_pos.x - 1.0, led_pos.y - 1.0, 1.0, 1.0), COLOR_OPEN_HIGHLIGHT, true)

		if not assigned_employee_id.is_empty():
			var staff_pos := Vector2(14.0, -29.0)
			draw_circle(staff_pos, 2.2, COLOR_OUTLINE_DARK)
			draw_circle(staff_pos, 1.4, COLOR_STAFFED_GOLD)
