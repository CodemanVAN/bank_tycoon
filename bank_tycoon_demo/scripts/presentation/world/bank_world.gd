class_name BankWorld
extends Node2D

## Front-view (axis-aligned orthographic) Bank Lobby World presentation root.
## Every art asset in this project is a front-facing rectangle except the floor, which
## is a 32x16 isometric diamond. We un-project that diamond into a 32x32 square tile
## with an affine transform so floor, walls, props and characters share ONE projection.
## No new art assets are generated; only existing textures are re-projected.

signal entity_selected(entity_type: StringName, entity_id: String)

## Un-projection of the 32x16 diamond floor art into a 32x32 axis-aligned square.
## Inverse of the classic 2:1 iso map x=(u-v)/2, y=(u+v)/4 gives u=tx+2*ty,
## v=-tx+2*ty, so the diamond tips (16,0),(0,8),(-16,0),(0,-8) land exactly on
## the square corners (16,-16),(16,16),(-16,16),(-16,-16).
const FLOOR_X_AXIS: Vector2 = Vector2(1.0, -1.0)
const FLOOR_Y_AXIS: Vector2 = Vector2(2.0, 2.0)
signal department_placement_confirmed(dept_id: String, room: Rect2i)
signal department_placement_cancelled()

const FOUNTAIN_CELL: Vector2i = Vector2i(9, 7)
const ENTRANCE_CELL: Vector2i = Vector2i(8, 11)
const BREAK_CELL: Vector2i = Vector2i(3, 8)
const FOUNTAIN_FPS: float = 5.0

## Extra cells (besides ENTRANCE_CELL / QUEUE_WAIT_CELLS) that must stay walkable.
const PLACEMENT_EXTRA_RESERVED_CELLS: Array[Vector2i] = [
	Vector2i(8, 10),
	Vector2i(7, 10),
	Vector2i(9, 10),
]

const DEPT_ZONES: Dictionary = {
	"core:department.operations": {
		"cell": Vector2i(2, 2),
		"short_key": "WORLD_DEPT_OPS_SHORT",
		"accent": Color("#00C6FF"),
	},
	"core:department.hr": {
		"cell": Vector2i(5, 2),
		"short_key": "WORLD_DEPT_HR_SHORT",
		"accent": Color("#35C978"),
	},
	"core:department.credit": {
		"cell": Vector2i(12, 2),
		"short_key": "WORLD_DEPT_CREDIT_SHORT",
		"accent": Color("#FFC857"),
	},
	"core:department.risk": {
		"cell": Vector2i(15, 2),
		"short_key": "WORLD_DEPT_RISK_SHORT",
		"accent": Color("#9B8CFF"),
	},
}

## Only permanent architecture blocks navigation. Corner plants / ATMs / sofas are
## decorative: a department room may be built over them (they become room decor).
const STATIC_SOLID_CELLS: Array[Vector2i] = [
	Vector2i(9, 7),  # central fountain
]

const QUEUE_WAIT_CELLS: Array[Vector2i] = [
	Vector2i(4, 6),
	Vector2i(6, 6),
	Vector2i(8, 6),
	Vector2i(11, 6),
	Vector2i(5, 7),
	Vector2i(7, 7),
	Vector2i(11, 7),
	Vector2i(6, 8),
	Vector2i(8, 8),
	Vector2i(10, 8),
	Vector2i(7, 9),
	Vector2i(9, 9),
]

var iso_grid: IsoGrid = null

var _sim_host: Variant = null
var _floor_layer: Node2D = null
var _wall_layer: Node2D = null
var _ysort_layer: Node2D = null
var _props_container: Node2D = null
var _exterior_walls: Node2D = null
var _exterior_wall_signature: String = ""
var _hovered_dept_id: String = ""
var _hovered_station_id: String = ""
var _departments_container: Node2D = null
var _stations_container: Node2D = null
var _actors_container: Node2D = null
var _effects_layer: Node2D = null
var _camera: PixelCamera2D = null
var _fountain_sprite: Sprite2D = null

var _fountain_timer: float = 0.0
var _fountain_frame: int = 0
var _static_built: bool = false

# Department room construction (drag a rectangle along the hall perimeter)
const MIN_ROOM_SIZE: Vector2i = Vector2i(3, 3)
const DEFAULT_ROOM_SIZE: Vector2i = Vector2i(4, 4)
const MAX_ROOM_SIZE: Vector2i = Vector2i(5, 4)

var _placement_dept_id: String = ""
var _placement_short_key: String = ""
var _placement_anchor: Vector2i = Vector2i(-1, -1)
var _placement_rect: Rect2i = Rect2i()
var _placement_valid: bool = false
var _placement_dragging: bool = false
var _placement_ghost: Node2D = null
var _ghost_tiles: Node2D = null
var _ghost_label: Label = null

var _station_views: Dictionary = {}
var _employee_views: Dictionary = {}
var _customer_views: Dictionary = {}
var _dept_nodes: Dictionary = {}
var _floating_effects: Array[Dictionary] = []

var _selected_type: StringName = &""
var _selected_id: String = ""


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	iso_grid = IsoGrid.new()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if iso_grid == null:
		iso_grid = IsoGrid.new()
	_ensure_scene_hierarchy()
	_build_static_environment()
	_connect_locale_signal()
	refresh_world()


func _exit_tree() -> void:
	_unbind_runtime_signals()
	_sim_host = null



func _connect_locale_signal() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var loc: Node = tree.root.get_node_or_null("LocalizationService")
		if loc != null and loc.has_signal("locale_changed"):
			if not loc.is_connected("locale_changed", _on_locale_changed):
				loc.connect("locale_changed", _on_locale_changed)


const WORLD_FALLBACK_I18N: Dictionary = {
	"zh_CN": {
		"WORLD_DEPT_OPS_SHORT": "运营部",
		"WORLD_DEPT_HR_SHORT": "人事部",
		"WORLD_DEPT_CREDIT_SHORT": "信贷部",
		"WORLD_DEPT_RISK_SHORT": "风控部",
		"WORLD_DEPT_LEVEL_BADGE": "Lv.{level}",
		"WORLD_FX_SERVICE_DONE": "{amount}",
		"WORLD_FX_SATISFACTION_UP": "服务完成",
		"WORLD_FX_CUSTOMER_LEFT": "超时离开",
		"WORLD_FX_LOAN_APPROVED": "放款通过",
		"WORLD_FX_LOAN_REJECTED": "贷款拒绝",
		"WORLD_FX_DEPT_UPGRADED": "部门升级 Lv.{level}",
	},
	"en": {
		"WORLD_DEPT_OPS_SHORT": "OPS",
		"WORLD_DEPT_HR_SHORT": "HR",
		"WORLD_DEPT_CREDIT_SHORT": "CREDIT",
		"WORLD_DEPT_RISK_SHORT": "RISK",
		"WORLD_DEPT_LEVEL_BADGE": "Lv.{level}",
		"WORLD_FX_SERVICE_DONE": "{amount}",
		"WORLD_FX_SATISFACTION_UP": "Service Done",
		"WORLD_FX_CUSTOMER_LEFT": "Left Unserved",
		"WORLD_FX_LOAN_APPROVED": "Loan Approved",
		"WORLD_FX_LOAN_REJECTED": "Loan Rejected",
		"WORLD_FX_DEPT_UPGRADED": "Dept Lv.{level}",
	},
	"ja": {
		"WORLD_DEPT_OPS_SHORT": "運営",
		"WORLD_DEPT_HR_SHORT": "人事",
		"WORLD_DEPT_CREDIT_SHORT": "与信",
		"WORLD_DEPT_RISK_SHORT": "リスク",
		"WORLD_DEPT_LEVEL_BADGE": "Lv.{level}",
		"WORLD_FX_SERVICE_DONE": "{amount}",
		"WORLD_FX_SATISFACTION_UP": "対応完了",
		"WORLD_FX_CUSTOMER_LEFT": "時間切れ離脱",
		"WORLD_FX_LOAN_APPROVED": "融資承認",
		"WORLD_FX_LOAN_REJECTED": "融資却下",
		"WORLD_FX_DEPT_UPGRADED": "部門 Lv.{level}",
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


func bind_runtime(sim_host: Variant) -> void:
	_unbind_runtime_signals()
	_sim_host = sim_host
	_ensure_scene_hierarchy()
	_build_static_environment()

	if _sim_host != null and (_sim_host is Object):
		var host_obj: Object = _sim_host as Object
		if host_obj.has_signal("snapshot_changed"):
			if not host_obj.is_connected("snapshot_changed", _on_snapshot_changed):
				host_obj.connect("snapshot_changed", _on_snapshot_changed)
		var bus: Variant = host_obj.get("event_bus")
		if bus != null and (bus is Object):
			var bus_obj: Object = bus as Object
			if bus_obj.has_signal("event_published"):
				if not bus_obj.is_connected("event_published", _on_domain_event):
					bus_obj.connect("event_published", _on_domain_event)

	refresh_world()


func set_camera_zoom_step(step: int) -> void:
	_ensure_scene_hierarchy()
	if _camera != null:
		_camera.set_zoom_step(step)


func get_camera_zoom_step() -> int:
	if _camera != null:
		return _camera.get_zoom_step()
	return 2


func focus_entity(entity_type: StringName, entity_id: String) -> void:
	_ensure_scene_hierarchy()
	if entity_type == &"" or entity_id.is_empty():
		_selected_type = &""
		_selected_id = ""
		_update_selection_highlights()
		entity_selected.emit(&"", "")
		return

	refresh_world()

	var target_pos: Vector2 = Vector2.ZERO
	var found: bool = false

	match String(entity_type):
		"station":
			if _station_views.has(entity_id):
				var sv: ServiceStationView = _station_views[entity_id] as ServiceStationView
				target_pos = sv.position
				found = true
		"employee":
			if _employee_views.has(entity_id):
				var ev: ActorView = _employee_views[entity_id] as ActorView
				target_pos = ev.position
				found = true
		"customer":
			if _customer_views.has(entity_id):
				var cv: ActorView = _customer_views[entity_id] as ActorView
				target_pos = cv.position
				found = true
		_:
			found = false

	if not found:
		return

	_selected_type = entity_type
	_selected_id = entity_id
	_update_selection_highlights()
	if _camera != null:
		_camera.focus_world_position(target_pos)
	entity_selected.emit(entity_type, entity_id)


func select_entity(entity_type: StringName, entity_id: String) -> void:
	focus_entity(entity_type, entity_id)


func refresh_world() -> void:
	_ensure_scene_hierarchy()
	_build_static_environment()
	var bs: Variant = _get_bank_state()
	if bs == null or not (bs is Object):
		return
	var bs_obj: Object = bs as Object
	_sync_navigation_solids(bs_obj)
	_sync_exterior_walls(bs_obj)
	_sync_departments(bs_obj)
	_sync_stations(bs_obj)
	_sync_employees(bs_obj)
	_sync_customers(bs_obj)
	_update_selection_highlights()


# ---------------------------------------------------------------------------
# Department placement (player picks the plot in the lobby)
# ---------------------------------------------------------------------------

func is_department_placement_active() -> bool:
	return not _placement_dept_id.is_empty()


func get_placement_rect() -> Rect2i:
	return _placement_rect


func get_placement_cell() -> Vector2i:
	return _placement_rect.position


func begin_department_placement(dept_id: String) -> bool:
	if dept_id.is_empty():
		return false
	_ensure_scene_hierarchy()
	_build_static_environment()
	_ensure_placement_ghost()
	if _placement_ghost == null:
		return false
	_placement_dept_id = dept_id
	var cfg: Dictionary = DEPT_ZONES.get(dept_id, {}) as Dictionary
	_placement_short_key = str(cfg.get("short_key", dept_id))
	_placement_anchor = Vector2i(-1, -1)
	_placement_rect = Rect2i()
	_placement_valid = false
	_placement_dragging = false
	_clear_ghost_tiles()
	var default_room: Rect2i = _find_default_room()
	if default_room.size.x > 0:
		_update_placement_preview(default_room)
	else:
		_placement_ghost.visible = false
	return true


func cancel_department_placement() -> void:
	if _placement_dept_id.is_empty():
		return
	_end_department_placement()
	department_placement_cancelled.emit()


## The initial building is the lobby; departments extend the floor plan outward.
const LOBBY_RECT: Rect2i = Rect2i(0, 0, IsoGrid.GRID_WIDTH, IsoGrid.GRID_HEIGHT)


## True when `cell` already belongs to the bank floor (lobby or an existing room).
func is_built_cell(cell: Vector2i) -> bool:
	if LOBBY_RECT.has_point(cell):
		return true
	var bs: Variant = _get_bank_state()
	if bs is Object:
		var depts: Variant = (bs as Object).get("departments")
		if depts is Dictionary:
			for did: Variant in (depts as Dictionary).keys():
				var r: Rect2i = _read_dept_rect((depts as Dictionary)[did])
				if r.size.x > 0 and r.has_point(cell):
					return true
	return false


func _rect_has_built_cell(rect: Rect2i) -> bool:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if is_built_cell(Vector2i(x, y)):
				return true
	return false


## Built cells directly next to each side of the rect (used to pick the door side).
func _built_neighbours(rect: Rect2i) -> Dictionary:
	var counts: Dictionary = {&"north": 0, &"south": 0, &"west": 0, &"east": 0}
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		if is_built_cell(Vector2i(x, rect.position.y - 1)):
			counts[&"north"] = int(counts[&"north"]) + 1
		if is_built_cell(Vector2i(x, rect.position.y + rect.size.y)):
			counts[&"south"] = int(counts[&"south"]) + 1
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		if is_built_cell(Vector2i(rect.position.x - 1, y)):
			counts[&"west"] = int(counts[&"west"]) + 1
		if is_built_cell(Vector2i(rect.position.x + rect.size.x, y)):
			counts[&"east"] = int(counts[&"east"]) + 1
	return counts


## The door is auto-generated at the middle of the side touching the existing building.
func room_door_cell(rect: Rect2i) -> Vector2i:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Vector2i(-1, -1)
	var counts: Dictionary = _built_neighbours(rect)
	var best_side: StringName = &""
	var best_count: int = 0
	for side: StringName in [&"north", &"south", &"west", &"east"]:
		var c: int = int(counts.get(side, 0))
		if c > best_count:
			best_count = c
			best_side = side
	if best_side == &"":
		return Vector2i(-1, -1)
	match best_side:
		&"north":
			return Vector2i(rect.position.x + rect.size.x / 2, rect.position.y)
		&"south":
			return Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y - 1)
		&"west":
			return Vector2i(rect.position.x, rect.position.y + rect.size.y / 2)
		_:
			return Vector2i(rect.position.x + rect.size.x - 1, rect.position.y + rect.size.y / 2)


## Whole-room validation: free land inside the site, outside every built cell, and
## touching the current building so it can be connected with a door.
func is_valid_department_room(rect: Rect2i, dept_id: String = "") -> bool:
	if iso_grid == null:
		return false
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	if rect.size.x > MAX_ROOM_SIZE.x or rect.size.y > MAX_ROOM_SIZE.y:
		return false
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			if not iso_grid.is_in_bounds(cell):
				return false
			if is_built_cell(cell):
				return false
	var counts: Dictionary = _built_neighbours(rect)
	var touching: bool = false
	for side: StringName in counts.keys():
		if int(counts[side]) > 0:
			touching = true
			break
	if not touching:
		return false
	var bs: Variant = _get_bank_state()
	if bs is Object:
		if not DepartmentService.is_room_free(bs as BankState, rect, dept_id):
			return false
	return true


## Single-cell wrapper kept for tests / callers that only have a point.
func is_valid_department_plot(cell: Vector2i, dept_id: String = "") -> bool:
	return is_valid_department_room(Rect2i(cell, Vector2i.ONE), dept_id)


## Solid walls: the whole perimeter except the auto-generated door cell.
func room_wall_cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if rect.size.x <= 0 or rect.size.y <= 0:
		return out
	var door: Vector2i = room_door_cell(rect)
	var min_x: int = rect.position.x
	var max_x: int = rect.position.x + rect.size.x - 1
	var min_y: int = rect.position.y
	var max_y: int = rect.position.y + rect.size.y - 1
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var edge: bool = (x == min_x or x == max_x or y == min_y or y == max_y)
			if edge and Vector2i(x, y) != door:
				out.append(Vector2i(x, y))
	return out


func _end_department_placement() -> void:
	_placement_dept_id = ""
	_placement_short_key = ""
	_placement_anchor = Vector2i(-1, -1)
	_placement_rect = Rect2i()
	_placement_valid = false
	_placement_dragging = false
	_clear_ghost_tiles()
	if _placement_ghost != null and is_instance_valid(_placement_ghost):
		_placement_ghost.visible = false


func _confirm_department_placement(rect: Rect2i) -> void:
	var dept_id: String = _placement_dept_id
	_end_department_placement()
	department_placement_confirmed.emit(dept_id, rect)


func _normalize_room_rect(a: Vector2i, b: Vector2i) -> Rect2i:
	var min_x: int = mini(a.x, b.x)
	var max_x: int = maxi(a.x, b.x)
	var min_y: int = mini(a.y, b.y)
	var max_y: int = maxi(a.y, b.y)
	var size := Vector2i(
		clampi(max_x - min_x + 1, 1, MAX_ROOM_SIZE.x),
		clampi(max_y - min_y + 1, 1, MAX_ROOM_SIZE.y)
	)
	var origin := Vector2i(
		clampi(min_x, IsoGrid.SITE_REGION.position.x, IsoGrid.SITE_REGION.end.x - size.x),
		clampi(min_y, IsoGrid.SITE_REGION.position.y, IsoGrid.SITE_REGION.end.y - size.y)
	)
	return Rect2i(origin, size)


## A single click still builds the minimum room, centred on the clicked cell.
func _default_room_at(cell: Vector2i) -> Rect2i:
	var size: Vector2i = DEFAULT_ROOM_SIZE
	var origin := Vector2i(
		clampi(cell.x - size.x / 2, IsoGrid.SITE_REGION.position.x, IsoGrid.SITE_REGION.end.x - size.x),
		clampi(cell.y - size.y / 2, IsoGrid.SITE_REGION.position.y, IsoGrid.SITE_REGION.end.y - size.y)
	)
	return Rect2i(origin, size)


## First valid 4x4 spot around the lobby, so the player sees a real room immediately.
func _find_default_room() -> Rect2i:
	var candidates: Array[Vector2i] = [
		Vector2i(18, 2), Vector2i(18, 6), Vector2i(18, 10),
		Vector2i(-4, 2), Vector2i(-4, 6), Vector2i(-4, 10),
		Vector2i(2, -4), Vector2i(8, -4), Vector2i(12, -4),
		Vector2i(2, 12), Vector2i(8, 12), Vector2i(12, 12),
	]
	for cell: Vector2i in candidates:
		var r := Rect2i(cell, DEFAULT_ROOM_SIZE)
		if is_valid_department_room(r, _placement_dept_id):
			return r
	return Rect2i()


func _ensure_placement_ghost() -> void:
	if _placement_ghost != null and is_instance_valid(_placement_ghost):
		return
	if _ysort_layer == null:
		return
	_placement_ghost = Node2D.new()
	_placement_ghost.name = "DepartmentPlacementGhost"
	_placement_ghost.z_index = 100
	_placement_ghost.visible = false
	_ysort_layer.add_child(_placement_ghost)

	_ghost_tiles = Node2D.new()
	_ghost_tiles.name = "GhostTiles"
	_placement_ghost.add_child(_ghost_tiles)

	_ghost_label = Label.new()
	_ghost_label.name = "GhostLabel"
	_ghost_label.size = Vector2(200.0, 16.0)
	_ghost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ghost_label.add_theme_font_size_override("font_size", 11)
	_ghost_label.add_theme_color_override("font_color", Color("#FFFFFF"))
	_ghost_label.add_theme_color_override("font_outline_color", Color("#0A1420"))
	_ghost_label.add_theme_constant_override("outline_size", 3)
	_placement_ghost.add_child(_ghost_label)


func _clear_ghost_tiles() -> void:
	if _ghost_tiles == null or not is_instance_valid(_ghost_tiles):
		return
	for child in _ghost_tiles.get_children():
		_ghost_tiles.remove_child(child)
		child.queue_free()


func _update_placement_preview(rect: Rect2i) -> void:
	if _placement_dept_id.is_empty():
		return
	if _placement_ghost == null or not is_instance_valid(_placement_ghost):
		return
	if iso_grid == null:
		return
	if rect.size.x <= 0 or rect.size.y <= 0:
		_placement_ghost.visible = false
		return
	var valid: bool = is_valid_department_room(rect, _placement_dept_id)
	var changed: bool = rect != _placement_rect or valid != _placement_valid
	_placement_rect = rect
	_placement_valid = valid
	if changed:
		_rebuild_ghost_tiles(rect, valid)
		if _ghost_label != null:
			_ghost_label.text = _tr("WORLD_DEPT_PLACE_GHOST", {"name": _tr(_placement_short_key)})
			var top_pos: Vector2 = iso_grid.grid_to_screen(rect.position).round()
			# Above the 48px north wall of the previewed room.
			_ghost_label.position = top_pos + Vector2(-100.0, -76.0)
	_placement_ghost.visible = true


func _rebuild_ghost_tiles(rect: Rect2i, valid: bool) -> void:
	if _ghost_tiles == null:
		return
	_clear_ghost_tiles()
	var col: Color = Color("#35C978") if valid else Color("#E74C3C")
	var door_cell: Vector2i = room_door_cell(rect)
	var tex_wall: Texture2D = _load_tex("res://assets/environment/wall_section_back.png")
	var tex_desk: Texture2D = _load_tex("res://assets/environment/prop_desk_office.png")
	var tint: Color = Color(col.r, col.g, col.b, 0.55)

	# Square footprint matching the axis-aligned orthographic floor tiles.
	var square := PackedVector2Array([
		Vector2(-16.0, -16.0), Vector2(16.0, -16.0),
		Vector2(16.0, 16.0), Vector2(-16.0, 16.0),
	])
	var square_outline := PackedVector2Array([
		Vector2(-16.0, -16.0), Vector2(16.0, -16.0),
		Vector2(16.0, 16.0), Vector2(-16.0, 16.0), Vector2(-16.0, -16.0),
	])
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			var tile := Polygon2D.new()
			tile.polygon = square
			tile.color = Color(col.r, col.g, col.b, 0.30)
			tile.position = iso_grid.grid_to_screen(cell).round()
			_ghost_tiles.add_child(tile)

			var edge := Line2D.new()
			edge.points = square_outline
			edge.width = 1.0
			edge.default_color = Color(col.r, col.g, col.b, 0.70)
			edge.position = tile.position
			_ghost_tiles.add_child(edge)
			if cell == door_cell:
				var opening_tile := Polygon2D.new()
				opening_tile.polygon = PackedVector2Array([
					Vector2(-11.0, -11.0), Vector2(11.0, -11.0),
					Vector2(11.0, 11.0), Vector2(-11.0, 11.0),
				])
				opening_tile.color = Color("#FFC857") if valid else Color(col.r, col.g, col.b, 0.55)
				opening_tile.position = tile.position
				_ghost_tiles.add_child(opening_tile)

	# Preview the real room shell: continuous axis-aligned front walls on the
	# visible back/left edges plus an office desk, so the player sees the result.
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		var cell_n := Vector2i(x, rect.position.y)
		if cell_n != door_cell:
			var wall := Sprite2D.new()
			wall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			wall.texture = tex_wall
			wall.centered = true
			wall.offset = Vector2(0.0, -24.0)
			wall.modulate = tint
			wall.position = iso_grid.grid_to_screen(cell_n).round() + Vector2(0.0, -16.0)
			_ghost_tiles.add_child(wall)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		var cell_w := Vector2i(rect.position.x, y)
		if cell_w != door_cell:
			var wall_w := Sprite2D.new()
			wall_w.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			wall_w.texture = tex_wall
			wall_w.centered = true
			wall_w.flip_h = true
			wall_w.scale = Vector2(0.5, 1.0)
			wall_w.offset = Vector2(0.0, -24.0)
			wall_w.modulate = tint
			wall_w.position = iso_grid.grid_to_screen(cell_w).round() + Vector2(-16.0, 0.0)
			_ghost_tiles.add_child(wall_w)

	var desk := Sprite2D.new()
	desk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	desk.texture = tex_desk
	desk.centered = true
	desk.offset = Vector2(0.0, -15.0)
	desk.modulate = Color(1.0, 1.0, 1.0, 0.72)
	var desk_cell := Vector2i(
		rect.position.x + rect.size.x / 2,
		rect.position.y + rect.size.y / 2
	)
	desk.position = iso_grid.grid_to_screen(desk_cell).round()
	_ghost_tiles.add_child(desk)


## Converts a viewport-space input position to a logical grid cell (camera-aware).
func cell_from_screen_position(screen_pos: Vector2) -> Vector2i:
	if iso_grid == null:
		return Vector2i(-1, -1)
	var local_pos: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_pos
	return iso_grid.screen_to_grid(local_pos)


func _get_bank_state() -> Variant:
	if _sim_host != null and (_sim_host is Object):
		var bs: Variant = (_sim_host as Object).get("bank_state")
		if bs != null:
			return bs
	if is_inside_tree():
		var sess: Node = get_tree().root.get_node_or_null("GameSession")
		if sess != null:
			var s_bs: Variant = sess.get("bank_state")
			if s_bs != null:
				return s_bs
	return null


func _unbind_runtime_signals() -> void:
	if _sim_host != null and (_sim_host is Object):
		var host_obj: Object = _sim_host as Object
		if host_obj.has_signal("snapshot_changed") and host_obj.is_connected("snapshot_changed", _on_snapshot_changed):
			host_obj.disconnect("snapshot_changed", _on_snapshot_changed)
		var bus: Variant = host_obj.get("event_bus")
		if bus != null and (bus is Object):
			var bus_obj: Object = bus as Object
			if bus_obj.has_signal("event_published") and bus_obj.is_connected("event_published", _on_domain_event):
				bus_obj.disconnect("event_published", _on_domain_event)


func _ensure_scene_hierarchy() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_floor_layer = get_node_or_null("FloorLayer") as Node2D
	if _floor_layer == null:
		_floor_layer = Node2D.new()
		_floor_layer.name = "FloorLayer"
		add_child(_floor_layer)
	_floor_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_wall_layer = get_node_or_null("WallLayer") as Node2D
	if _wall_layer == null:
		_wall_layer = Node2D.new()
		_wall_layer.name = "WallLayer"
		add_child(_wall_layer)
	_wall_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_ysort_layer = get_node_or_null("YSortedLayer") as Node2D
	if _ysort_layer == null:
		_ysort_layer = Node2D.new()
		_ysort_layer.name = "YSortedLayer"
		add_child(_ysort_layer)
	_ysort_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ysort_layer.y_sort_enabled = true

	_props_container = _ysort_layer.get_node_or_null("PropsContainer") as Node2D
	if _props_container == null:
		_props_container = Node2D.new()
		_props_container.name = "PropsContainer"
		_ysort_layer.add_child(_props_container)
	_props_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_props_container.y_sort_enabled = true

	_exterior_walls = _ysort_layer.get_node_or_null("ExteriorWalls") as Node2D
	if _exterior_walls == null:
		_exterior_walls = Node2D.new()
		_exterior_walls.name = "ExteriorWalls"
		_ysort_layer.add_child(_exterior_walls)
	_exterior_walls.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_exterior_walls.y_sort_enabled = true

	_departments_container = _ysort_layer.get_node_or_null("DepartmentsContainer") as Node2D
	if _departments_container == null:
		_departments_container = Node2D.new()
		_departments_container.name = "DepartmentsContainer"
		_ysort_layer.add_child(_departments_container)
	_departments_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_departments_container.y_sort_enabled = true

	_stations_container = _ysort_layer.get_node_or_null("StationsContainer") as Node2D
	if _stations_container == null:
		_stations_container = Node2D.new()
		_stations_container.name = "StationsContainer"
		_ysort_layer.add_child(_stations_container)
	_stations_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stations_container.y_sort_enabled = true

	_actors_container = _ysort_layer.get_node_or_null("ActorsContainer") as Node2D
	if _actors_container == null:
		_actors_container = Node2D.new()
		_actors_container.name = "ActorsContainer"
		_ysort_layer.add_child(_actors_container)
	_actors_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_actors_container.y_sort_enabled = true

	_effects_layer = get_node_or_null("EffectsLayer") as Node2D
	if _effects_layer == null:
		_effects_layer = Node2D.new()
		_effects_layer.name = "EffectsLayer"
		add_child(_effects_layer)
	_effects_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	_camera = get_node_or_null("Camera2D") as PixelCamera2D
	if _camera == null:
		var existing_cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
		if existing_cam != null:
			existing_cam.free()
		_camera = PixelCamera2D.new()
		_camera.name = "Camera2D"
		add_child(_camera)
	_camera.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _build_static_environment() -> void:
	if _static_built:
		return
	_static_built = true

	var tex_ivory: Texture2D = _load_tex("res://assets/environment/tile_floor_ivory.png")
	var tex_wood: Texture2D = _load_tex("res://assets/environment/tile_floor_wood.png")
	var tex_carpet: Texture2D = _load_tex("res://assets/environment/tile_floor_carpet_blue.png")
	var tex_vip: Texture2D = _load_tex("res://assets/environment/tile_floor_vip.png")

	# 1. Build 18x12 axis-aligned square floor layer
	for y in range(IsoGrid.GRID_HEIGHT):
		for x in range(IsoGrid.GRID_WIDTH):
			var cell := Vector2i(x, y)
			var spr := Sprite2D.new()
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.centered = true
			# Un-project the existing 32x16 diamond art into a 32x32 axis-aligned square.
			# The transform origin is the cell centre, so adjacent squares tile seamlessly.
			spr.transform = _floor_transform(iso_grid.grid_to_screen(cell).round())

			var is_border: bool = (x == 0 or x == IsoGrid.GRID_WIDTH - 1 or y == 0 or y == IsoGrid.GRID_HEIGHT - 1)
			var is_back_office: bool = (y <= 2 and x >= 1 and x <= 16)
			var is_vip_zone: bool = (x >= 11 and x <= 15 and y >= 3 and y <= 5)
			var is_welcome_carpet: bool = (
				(x >= 7 and x <= 10 and y >= 5 and y <= 10)
				or (y == 7 and x >= 3 and x <= 14)
			)

			if is_vip_zone:
				spr.texture = tex_vip
			elif is_welcome_carpet:
				spr.texture = tex_carpet
			elif is_border or is_back_office:
				spr.texture = tex_wood
			else:
				spr.texture = tex_ivory
			_floor_layer.add_child(spr)

	# 2. Logo backdrop / vault door sit on the dynamically generated exterior wall.
	var tex_wall_logo: Texture2D = _load_tex("res://assets/environment/wall_logo_backdrop.png")
	var tex_vault: Texture2D = _load_tex("res://assets/environment/prop_vault_door.png")

	var logo_spr := Sprite2D.new()
	logo_spr.name = "StarwayLogoBackdrop"
	logo_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo_spr.texture = tex_wall_logo
	logo_spr.centered = true
	# 64x48 front panel seated on the north wall base (cell top edge).
	logo_spr.offset = Vector2(0.0, -24.0)
	logo_spr.position = iso_grid.grid_to_screen(Vector2i(8, 0)).round() + Vector2(0.0, -16.0)
	_wall_layer.add_child(logo_spr)

	var vault_spr := Sprite2D.new()
	vault_spr.name = "VaultDoorProp"
	vault_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vault_spr.texture = tex_vault
	vault_spr.centered = true
	# 40x48 front panel seated on the north wall base.
	vault_spr.offset = Vector2(0.0, -24.0)
	vault_spr.position = iso_grid.grid_to_screen(Vector2i(14, 0)).round() + Vector2(0.0, -16.0)
	_wall_layer.add_child(vault_spr)

	# 3. Build Y-Sorted Lobby Props (Animated Fountain, Sofas, Queue Posts, Plants, ATMs)
	_fountain_sprite = Sprite2D.new()
	_fountain_sprite.name = "StarwayFountain"
	_fountain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fountain_sprite.texture = _load_tex("res://assets/environment/prop_fountain_sheet.png")
	_fountain_sprite.centered = true
	_fountain_sprite.hframes = 4
	_fountain_sprite.vframes = 1
	# 48x48 front-facing fountain frame: base seated on the square tile centre.
	_fountain_sprite.offset = Vector2(0.0, -24.0)
	_fountain_sprite.position = iso_grid.grid_to_screen(FOUNTAIN_CELL).round()
	_props_container.add_child(_fountain_sprite)

	# Each prop is a front-facing rectangle; offset.y = -height/2 seats its base
	# exactly on the cell centre of the axis-aligned square grid.
	_add_prop_sprite("res://assets/environment/prop_sofa.png", Vector2i(3, 8), Vector2(0.0, -14.0))       # 40x28
	_add_prop_sprite("res://assets/environment/prop_sofa.png", Vector2i(14, 8), Vector2(0.0, -14.0))

	for qcell in [Vector2i(4, 6), Vector2i(6, 6), Vector2i(8, 6), Vector2i(11, 6)]:
		_add_prop_sprite("res://assets/environment/prop_queue_post.png", qcell, Vector2(0.0, -12.0))  # 16x24

	for pcell in [Vector2i(1, 1), Vector2i(16, 1), Vector2i(1, 10), Vector2i(16, 10), Vector2i(10, 4)]:
		_add_prop_sprite("res://assets/environment/prop_plant.png", pcell, Vector2(0.0, -16.0))      # 24x32

	for acell in [Vector2i(1, 5), Vector2i(1, 7)]:
		_add_prop_sprite("res://assets/environment/prop_atm.png", acell, Vector2(0.0, -18.0))        # 24x36

	# 4. Department rooms are spawned from BankState by _sync_departments() at the plot
	# the player chose (no fixed zones any more).
	queue_redraw()


func _add_prop_sprite(tex_path: String, cell: Vector2i, offset_px: Vector2) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.texture = _load_tex(tex_path)
	spr.centered = true
	spr.offset = offset_px
	spr.position = iso_grid.grid_to_screen(cell).round()
	_props_container.add_child(spr)
	return spr


func _create_department_room(dept_id: String, rect: Rect2i) -> void:
	var cfg: Dictionary = DEPT_ZONES.get(dept_id, {}) as Dictionary
	var accent: Color = cfg.get("accent", Color("#00C6FF"))
	var short_key: String = str(cfg.get("short_key", dept_id))
	var tex_desk: Texture2D = _load_tex("res://assets/environment/prop_desk_office.png")
	var tex_banner: Texture2D = _load_tex("res://assets/environment/prop_dept_banner.png")
	var tex_floor: Texture2D = _load_tex("res://assets/environment/tile_floor_carpet_blue.png")

	var front_center := Vector2i(
		rect.position.x + rect.size.x / 2,
		rect.position.y + rect.size.y - 1
	)
	var root := Node2D.new()
	root.name = "DeptRoom_" + dept_id.replace("core:department.", "").replace(":", "_")
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.position = iso_grid.grid_to_screen(front_center).round()

	var door_cell: Vector2i = room_door_cell(rect)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			var tile := Sprite2D.new()
			tile.name = "Floor_%d_%d" % [x, y]
			tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tile.texture = tex_floor
			tile.centered = true
			tile.modulate = Color(1.0, 1.0, 1.0, 1.0) if cell != door_cell else Color(1.15, 1.1, 0.85, 1.0)
			# Room floor uses the same un-projected square tile as the lobby.
			tile.transform = _floor_transform(iso_grid.grid_to_screen(cell).round() - root.position)
			root.add_child(tile)

	# Auto-generated door at the connection with the existing building.
	if door_cell.x >= 0:
		var door_pos: Vector2 = iso_grid.grid_to_screen(door_cell).round() - root.position
		var door_mark := Polygon2D.new()
		door_mark.name = "DoorMark"
		door_mark.polygon = PackedVector2Array([
			Vector2(-12.0, -12.0), Vector2(12.0, -12.0),
			Vector2(12.0, 12.0), Vector2(-12.0, 12.0),
		])
		door_mark.color = Color(1.0, 0.78, 0.34, 0.55)
		door_mark.position = door_pos
		root.add_child(door_mark)
		var door_frame := Line2D.new()
		door_frame.name = "DoorFrame"
		door_frame.points = PackedVector2Array([
			Vector2(-12.0, -12.0), Vector2(12.0, -12.0),
			Vector2(12.0, 12.0), Vector2(-12.0, 12.0), Vector2(-12.0, -12.0),
		])
		door_frame.width = 1.5
		door_frame.default_color = Color("#FFC857")
		door_frame.position = door_pos
		root.add_child(door_frame)

	var sign_anchor := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y)
	var sign_pos: Vector2 = iso_grid.grid_to_screen(sign_anchor).round() - root.position + Vector2(-64.0, -76.0)
	var sign_bg := ColorRect.new()
	sign_bg.name = "RoomSignBg"
	sign_bg.color = Color(0.03, 0.09, 0.16, 0.85)
	sign_bg.size = Vector2(128.0, 18.0)
	sign_bg.position = sign_pos
	root.add_child(sign_bg)
	var sign_label := Label.new()
	sign_label.name = "RoomSign"
	sign_label.text = _tr(short_key)
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sign_label.size = Vector2(128.0, 18.0)
	sign_label.position = sign_pos
	sign_label.add_theme_font_size_override("font_size", 11)
	sign_label.add_theme_color_override("font_color", accent)
	sign_label.visible = false
	root.add_child(sign_label)
	sign_bg.visible = false

	var desk_cell := Vector2i(
		rect.position.x + rect.size.x / 2,
		rect.position.y + rect.size.y / 2
	)
	var desk := Sprite2D.new()
	desk.name = "OfficeDesk"
	desk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	desk.texture = tex_desk
	desk.centered = true
	desk.offset = Vector2(0.0, -15.0)
	desk.position = iso_grid.grid_to_screen(desk_cell).round() - root.position
	root.add_child(desk)

	var banner := Sprite2D.new()
	banner.name = "DeptBanner"
	banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	banner.texture = tex_banner
	banner.centered = true
	banner.offset = Vector2(15.0, -18.0)
	banner.position = iso_grid.grid_to_screen(Vector2i(rect.position.x, rect.position.y)).round() - root.position
	root.add_child(banner)

	var badge := Label.new()
	badge.name = "LevelBadge"
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.size = Vector2(96.0, 14.0)
	badge.scale = Vector2(0.75, 0.75)
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", accent)
	badge.position = iso_grid.grid_to_screen(Vector2i(rect.position.x, rect.position.y)).round() - root.position + Vector2(-48.0, -56.0)
	badge.visible = false
	root.add_child(badge)

	_departments_container.add_child(root)
	_dept_nodes[dept_id] = {
		"root": root,
		"desk": desk,
		"banner": banner,
		"badge": badge,
		"short_key": short_key,
		"accent": accent,
		"cell": rect.position,
		"rect": rect,
		"level": 0,
		"sign_bg": sign_bg,
		"sign_label": sign_label,
	}


func _create_legacy_department_node(dept_id: String, cell: Vector2i) -> void:
	var cfg: Dictionary = DEPT_ZONES.get(dept_id, {}) as Dictionary
	var accent: Color = cfg.get("accent", Color("#00C6FF"))
	var short_key: String = str(cfg.get("short_key", dept_id))
	var root := Node2D.new()
	root.name = "DeptRoom_" + dept_id.replace("core:department.", "").replace(":", "_")
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.position = iso_grid.grid_to_screen(cell).round()

	var mat := Polygon2D.new()
	mat.name = "FloorMat"
	mat.polygon = PackedVector2Array([
		Vector2(-16.0, -16.0), Vector2(16.0, -16.0),
		Vector2(16.0, 16.0), Vector2(-16.0, 16.0),
	])
	mat.color = Color(accent.r, accent.g, accent.b, 0.16)
	root.add_child(mat)

	var desk := Sprite2D.new()
	desk.name = "OfficeDesk"
	desk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	desk.texture = _load_tex("res://assets/environment/prop_desk_office.png")
	desk.centered = true
	desk.offset = Vector2(0.0, -15.0)
	root.add_child(desk)

	var banner := Sprite2D.new()
	banner.name = "DeptBanner"
	banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	banner.texture = _load_tex("res://assets/environment/prop_dept_banner.png")
	banner.centered = true
	banner.offset = Vector2(15.0, -18.0)
	root.add_child(banner)

	var badge := Label.new()
	badge.name = "LevelBadge"
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.position = Vector2(-24.0, -46.0)
	badge.size = Vector2(64.0, 14.0)
	badge.scale = Vector2(0.75, 0.75)
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", accent)
	root.add_child(badge)

	_departments_container.add_child(root)
	_dept_nodes[dept_id] = {
		"root": root,
		"desk": desk,
		"banner": banner,
		"badge": badge,
		"short_key": short_key,
		"accent": accent,
		"cell": cell,
		"rect": Rect2i(cell, Vector2i.ONE),
		"level": 0,
	}


## Continuous cutaway walls: one 32x48 panel per built cell edge that faces empty land.
## This replaces the old "every 2nd cell" wall loop, which left gaps and floated 10px too low.
func _sync_exterior_walls(bs_obj: Object) -> void:
	if _exterior_walls == null:
		return
	var built: Dictionary = {}
	for y in range(LOBBY_RECT.position.y, LOBBY_RECT.end.y):
		for x in range(LOBBY_RECT.position.x, LOBBY_RECT.end.x):
			built[Vector2i(x, y)] = true
	var raw_depts: Variant = bs_obj.get("departments")
	if raw_depts is Dictionary:
		for did: Variant in (raw_depts as Dictionary).keys():
			var r: Rect2i = _read_dept_rect((raw_depts as Dictionary)[did])
			if r.size.x <= 0:
				continue
			for y in range(r.position.y, r.position.y + r.size.y):
				for x in range(r.position.x, r.position.x + r.size.x):
					built[Vector2i(x, y)] = true

	var key_list: Array[String] = []
	for c: Vector2i in built.keys():
		key_list.append("%d,%d" % [c.x, c.y])
	key_list.sort()
	var sig: String = "|".join(key_list)
	if sig == _exterior_wall_signature:
		return
	_exterior_wall_signature = sig

	for child in _exterior_walls.get_children():
		_exterior_walls.remove_child(child)
		child.queue_free()

	var tex_wall: Texture2D = _load_tex("res://assets/environment/wall_section_back.png")
	for c: Vector2i in built.keys():
		# North-facing wall: a 32x48 front panel seated on the cell's top edge.
		# Consecutive cells are exactly one panel width apart, so a run of north
		# walls is a continuous, gap-free wall (not a staggered iso picket fence).
		if not built.has(Vector2i(c.x, c.y - 1)):
			var wall := Sprite2D.new()
			wall.name = "ExtWallN_%d_%d" % [c.x, c.y]
			wall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			wall.texture = tex_wall
			wall.centered = true
			wall.offset = Vector2(0.0, -24.0)
			wall.position = iso_grid.grid_to_screen(c).round() + Vector2(0.0, -16.0)
			_exterior_walls.add_child(wall)
		# West-facing wall: the same front panel squeezed into a narrow vertical
		# strip on the cell's left edge, so the side boundary reads as a side wall.
		if not built.has(Vector2i(c.x - 1, c.y)):
			var wall_w := Sprite2D.new()
			wall_w.name = "ExtWallW_%d_%d" % [c.x, c.y]
			wall_w.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			wall_w.texture = tex_wall
			wall_w.centered = true
			wall_w.flip_h = true
			wall_w.scale = Vector2(0.5, 1.0)
			wall_w.offset = Vector2(0.0, -24.0)
			wall_w.position = iso_grid.grid_to_screen(c).round() + Vector2(-16.0, 0.0)
			_exterior_walls.add_child(wall_w)


func _sync_navigation_solids(bs_obj: Object) -> void:
	iso_grid.clear_solids()
	for cell in STATIC_SOLID_CELLS:
		iso_grid.set_solid(cell, true)

	# Everything outside the current floor plan is empty land: not walkable.
	var room_rects: Array[Rect2i] = []
	var raw_built_depts: Variant = bs_obj.get("departments")
	if raw_built_depts is Dictionary:
		for did_b: Variant in (raw_built_depts as Dictionary).keys():
			var r_b: Rect2i = _read_dept_rect((raw_built_depts as Dictionary)[did_b])
			if r_b.size.x > 0:
				room_rects.append(r_b)
	for y in range(IsoGrid.SITE_REGION.position.y, IsoGrid.SITE_REGION.end.y):
		for x in range(IsoGrid.SITE_REGION.position.x, IsoGrid.SITE_REGION.end.x):
			var c := Vector2i(x, y)
			if LOBBY_RECT.has_point(c):
				continue
			var in_room: bool = false
			for r: Rect2i in room_rects:
				if r.has_point(c):
					in_room = true
					break
			if not in_room:
				iso_grid.set_solid(c, true)
	var raw_stations: Variant = bs_obj.get("stations")
	if raw_stations is Dictionary:
		var st_dict: Dictionary = raw_stations as Dictionary
		for sid: Variant in st_dict.keys():
			var st: Variant = st_dict[sid]
			if st is Dictionary:
				var gp: Variant = (st as Dictionary).get("grid_pos", Vector2i.ZERO)
				if gp is Vector2i:
					iso_grid.set_solid(gp as Vector2i, true)
	var raw_depts: Variant = bs_obj.get("departments")
	if raw_depts is Dictionary:
		for did: Variant in (raw_depts as Dictionary).keys():
			var d_entry: Variant = (raw_depts as Dictionary)[did]
			var d_rect: Rect2i = _read_dept_rect(d_entry)
			if d_rect.size.x <= 0:
				d_rect = Rect2i(_fallback_dept_cell(str(did)), Vector2i.ONE)
			if d_rect.size == Vector2i.ONE:
				iso_grid.set_solid(d_rect.position, true)
			else:
				for wall_cell: Vector2i in room_wall_cells(d_rect):
					iso_grid.set_solid(wall_cell, true)


func _read_dept_cell(entry: Variant) -> Vector2i:
	if entry is Object:
		var raw_o: Variant = (entry as Object).get("grid_pos")
		if raw_o is Vector2i:
			return raw_o as Vector2i
		return Vector2i(-1, -1)
	if entry is Dictionary:
		var raw: Variant = (entry as Dictionary).get("grid_pos", null)
		if raw is Vector2i:
			return raw as Vector2i
		if raw is Array and (raw as Array).size() >= 2:
			var arr: Array = raw as Array
			return Vector2i(int(arr[0]), int(arr[1]))
		if raw is Dictionary:
			var d: Dictionary = raw as Dictionary
			return Vector2i(int(d.get("x", -1)), int(d.get("y", -1)))
	return Vector2i(-1, -1)


func _read_dept_level(entry: Variant) -> int:
	if entry is Object:
		return maxi(1, int((entry as Object).get("level")))
	if entry is Dictionary:
		return maxi(1, int((entry as Dictionary).get("level", 1)))
	return 1


func _fallback_dept_cell(dept_id: String) -> Vector2i:
	var cfg: Dictionary = DEPT_ZONES.get(dept_id, {}) as Dictionary
	var raw: Variant = cfg.get("cell", Vector2i(2, 2))
	return raw as Vector2i if raw is Vector2i else Vector2i(2, 2)


func _read_dept_rect(entry: Variant) -> Rect2i:
	var cell: Vector2i = _read_dept_cell(entry)
	if cell.x < 0 or cell.y < 0:
		return Rect2i()
	var size := Vector2i(1, 1)
	if entry is Object:
		var raw_o: Variant = (entry as Object).get("room_size")
		if raw_o is Vector2i:
			size = raw_o as Vector2i
	elif entry is Dictionary:
		var raw: Variant = (entry as Dictionary).get("room_size", null)
		if raw is Vector2i:
			size = raw as Vector2i
		elif raw is Array and (raw as Array).size() >= 2:
			var arr: Array = raw as Array
			size = Vector2i(int(arr[0]), int(arr[1]))
		elif raw is Dictionary:
			var d: Dictionary = raw as Dictionary
			size = Vector2i(int(d.get("x", 1)), int(d.get("y", 1)))
	return Rect2i(cell, Vector2i(maxi(1, size.x), maxi(1, size.y)))


func _sync_departments(bs_obj: Object) -> void:
	var raw_depts: Variant = bs_obj.get("departments")
	var depts_dict: Dictionary = raw_depts as Dictionary if raw_depts is Dictionary else {}

	for dept_id: String in _dept_nodes.keys().duplicate():
		if not depts_dict.has(dept_id):
			var stale: Dictionary = _dept_nodes[dept_id] as Dictionary
			var stale_root: Node = stale.get("root") as Node
			if stale_root != null and is_instance_valid(stale_root):
				stale_root.queue_free()
			_dept_nodes.erase(dept_id)

	for dept_id_v: Variant in depts_dict.keys():
		var dept_id: String = str(dept_id_v)
		var entry: Variant = depts_dict[dept_id]
		var lvl: int = _read_dept_level(entry)
		var rect: Rect2i = _read_dept_rect(entry)
		if rect.size.x <= 0:
			rect = Rect2i(_fallback_dept_cell(dept_id), Vector2i.ONE)

		var info: Dictionary = {}
		if _dept_nodes.has(dept_id):
			var existing: Dictionary = _dept_nodes[dept_id] as Dictionary
			var existing_rect: Rect2i = existing.get("rect", Rect2i()) as Rect2i
			if existing_rect == rect:
				info = existing
			else:
				var old_root: Node = existing.get("root") as Node
				if old_root != null and is_instance_valid(old_root):
					old_root.queue_free()
				_dept_nodes.erase(dept_id)
		if info.is_empty():
			if rect.size == Vector2i.ONE:
				_create_legacy_department_node(dept_id, rect.position)
			else:
				_create_department_room(dept_id, rect)
			info = _dept_nodes[dept_id] as Dictionary

		info["level"] = lvl
		var desk: Sprite2D = info["desk"] as Sprite2D
		var banner: Sprite2D = info["banner"] as Sprite2D
		var badge: Label = info["badge"] as Label
		var short_key: String = str(info["short_key"])
		var accent: Color = info.get("accent", Color("#00C6FF")) as Color

		desk.modulate = Color(1.0, 1.0, 1.0, 1.0)
		banner.visible = true
		badge.add_theme_color_override("font_color", accent)
		var dept_name: String = _tr(short_key)
		var lvl_str: String = _tr("WORLD_DEPT_LEVEL_BADGE", {"level": lvl})
		badge.text = "%s %s" % [dept_name, lvl_str]
	_apply_entity_labels()


func _sync_stations(bs_obj: Object) -> void:
	var raw_stations: Variant = bs_obj.get("stations")
	if not (raw_stations is Dictionary):
		return
	var st_dict: Dictionary = raw_stations as Dictionary
	var sorted_ids: Array[String] = []
	for k: Variant in st_dict.keys():
		sorted_ids.append(str(k))
	sorted_ids.sort()

	var seen: Dictionary = {}
	var idx: int = 1
	for sid in sorted_ids:
		var st_data: Variant = st_dict[sid]
		if not (st_data is Dictionary):
			continue
		seen[sid] = true
		var std: Dictionary = st_data as Dictionary
		var view: ServiceStationView = _station_views.get(sid, null) as ServiceStationView
		if view == null:
			view = ServiceStationView.new()
			view.name = "Station_" + sid
			_stations_container.add_child(view)
			_station_views[sid] = view
		var gp: Vector2i = Vector2i(4, 4)
		var raw_gp: Variant = std.get("grid_pos", gp)
		if raw_gp is Vector2i:
			gp = raw_gp as Vector2i
		elif raw_gp is Array and (raw_gp as Array).size() >= 2:
			var arr: Array = raw_gp as Array
			gp = Vector2i(int(arr[0]), int(arr[1]))
		var screen_pos: Vector2 = iso_grid.grid_to_screen(gp)
		view.configure(std, screen_pos, idx)
		idx += 1

	for old_id: String in _station_views.keys().duplicate():
		if not seen.has(old_id):
			var old_view: Node = _station_views[old_id] as Node
			_station_views.erase(old_id)
			if old_view != null:
				if old_view.get_parent() != null:
					old_view.get_parent().remove_child(old_view)
				old_view.free()


func _sync_employees(bs_obj: Object) -> void:
	var raw_emps: Variant = bs_obj.get("employees")
	if not (raw_emps is Dictionary):
		return
	var emp_dict: Dictionary = raw_emps as Dictionary
	var raw_stations: Variant = bs_obj.get("stations")
	var st_dict: Dictionary = raw_stations as Dictionary if raw_stations is Dictionary else {}

	var seen: Dictionary = {}
	for eid_v: Variant in emp_dict.keys():
		var eid: String = str(eid_v)
		var emp: Variant = emp_dict[eid_v]
		if not (emp is Object):
			continue
		seen[eid] = true
		var emp_obj: Object = emp as Object
		var desired_cell: Vector2i = _resolve_employee_cell(emp_obj, st_dict)
		var desired_screen: Vector2 = iso_grid.grid_to_screen(desired_cell)

		var view: ActorView = _employee_views.get(eid, null) as ActorView
		if view == null:
			view = ActorView.new()
			view.name = "Emp_" + eid
			_actors_container.add_child(view)
			_employee_views[eid] = view
			view.configure_employee(emp_obj, desired_screen)
			view.grid_pos = desired_cell
			view.snap_to_screen(desired_screen)
		else:
			var prev_cell: Vector2i = view.grid_pos
			view.configure_employee(emp_obj, desired_screen)
			view.grid_pos = desired_cell
			if prev_cell != desired_cell:
				var cell_path: Array[Vector2i] = iso_grid.find_path_or_adjacent(prev_cell, desired_cell)
				var screen_pts: Array[Vector2] = []
				for c in cell_path:
					screen_pts.append(iso_grid.grid_to_screen(c))
				screen_pts.append(desired_screen)
				view.set_screen_path(screen_pts)

	for old_id: String in _employee_views.keys().duplicate():
		if not seen.has(old_id):
			var old_v: Node = _employee_views[old_id] as Node
			_employee_views.erase(old_id)
			if old_v != null:
				if old_v.get_parent() != null:
					old_v.get_parent().remove_child(old_v)
				old_v.free()


func _resolve_employee_cell(emp_obj: Object, st_dict: Dictionary) -> Vector2i:
	var st_state: int = int(emp_obj.get("state"))
	if st_state == Enums.EmployeeState.BREAK:
		return BREAK_CELL
	var assigned_st: String = str(emp_obj.get("assigned_station_id"))
	if not assigned_st.is_empty() and st_dict.has(assigned_st):
		var st: Variant = st_dict[assigned_st]
		if st is Dictionary:
			var gp: Variant = (st as Dictionary).get("grid_pos", Vector2i(4, 4))
			if gp is Vector2i:
				return iso_grid.clamp_to_bounds((gp as Vector2i) + Vector2i(0, -1))
	var emp_gp: Variant = emp_obj.get("grid_pos")
	if emp_gp is Vector2i and (emp_gp as Vector2i) != Vector2i.ZERO:
		return iso_grid.clamp_to_bounds(emp_gp as Vector2i)
	return Vector2i(4, 3)


func _sync_customers(bs_obj: Object) -> void:
	var raw_custs: Variant = bs_obj.get("active_customers")
	if not (raw_custs is Dictionary):
		return
	var cust_dict: Dictionary = raw_custs as Dictionary
	var raw_stations: Variant = bs_obj.get("stations")
	var st_dict: Dictionary = raw_stations as Dictionary if raw_stations is Dictionary else {}

	var sorted_cids: Array[String] = []
	for cid_v: Variant in cust_dict.keys():
		sorted_cids.append(str(cid_v))
	sorted_cids.sort()

	var seen: Dictionary = {}
	var wait_idx: int = 0
	for cid in sorted_cids:
		var cust: Variant = cust_dict[cid]
		if not (cust is Object):
			continue
		seen[cid] = true
		var cust_obj: Object = cust as Object
		var cstate: int = int(cust_obj.get("state"))
		var desired_cell: Vector2i = _resolve_customer_cell(cust_obj, st_dict, wait_idx)
		if cstate == Enums.CustomerState.WAITING or cstate == Enums.CustomerState.FINDING_SERVICE:
			wait_idx += 1
		var desired_screen: Vector2 = iso_grid.grid_to_screen(desired_cell)

		var view: ActorView = _customer_views.get(cid, null) as ActorView
		if view == null:
			view = ActorView.new()
			view.name = "Cust_" + cid
			_actors_container.add_child(view)
			_customer_views[cid] = view
			var spawn_cell: Vector2i = ENTRANCE_CELL if cstate == Enums.CustomerState.SPAWNING else desired_cell
			var spawn_screen: Vector2 = iso_grid.grid_to_screen(spawn_cell)
			view.configure_customer(cust_obj, spawn_screen)
			view.grid_pos = desired_cell
			view.snap_to_screen(spawn_screen)
			if spawn_cell != desired_cell:
				var init_path: Array[Vector2i] = iso_grid.find_path_or_adjacent(spawn_cell, desired_cell)
				var screen_pts: Array[Vector2] = []
				for c in init_path:
					screen_pts.append(iso_grid.grid_to_screen(c))
				screen_pts.append(desired_screen)
				view.set_screen_path(screen_pts)
		else:
			var prev_cell: Vector2i = view.grid_pos
			view.configure_customer(cust_obj, desired_screen)
			view.grid_pos = desired_cell
			if prev_cell != desired_cell:
				var cell_path: Array[Vector2i] = iso_grid.find_path_or_adjacent(prev_cell, desired_cell)
				var screen_pts: Array[Vector2] = []
				for c in cell_path:
					screen_pts.append(iso_grid.grid_to_screen(c))
				screen_pts.append(desired_screen)
				view.set_screen_path(screen_pts)

	for old_id: String in _customer_views.keys().duplicate():
		if not seen.has(old_id):
			var old_v: Node = _customer_views[old_id] as Node
			_customer_views.erase(old_id)
			if old_v != null:
				if old_v.get_parent() != null:
					old_v.get_parent().remove_child(old_v)
				old_v.free()


func _resolve_customer_cell(cust_obj: Object, st_dict: Dictionary, wait_idx: int) -> Vector2i:
	var cstate: int = int(cust_obj.get("state"))
	var assigned_st: String = str(cust_obj.get("assigned_station_id"))
	if cstate == Enums.CustomerState.IN_SERVICE and not assigned_st.is_empty() and st_dict.has(assigned_st):
		var st: Variant = st_dict[assigned_st]
		if st is Dictionary:
			var gp: Variant = (st as Dictionary).get("grid_pos", Vector2i(4, 4))
			if gp is Vector2i:
				return iso_grid.clamp_to_bounds((gp as Vector2i) + Vector2i(0, 1))
	if cstate == Enums.CustomerState.LEAVING or cstate == Enums.CustomerState.COMPLETED:
		return ENTRANCE_CELL
	var cust_gp: Variant = cust_obj.get("grid_pos")
	if cust_gp is Vector2i and (cust_gp as Vector2i) != Vector2i.ZERO:
		return iso_grid.clamp_to_bounds(cust_gp as Vector2i)
	return QUEUE_WAIT_CELLS[wait_idx % QUEUE_WAIT_CELLS.size()]


## Department signs and counter tags stay hidden until the pointer is over them.
func _apply_entity_labels() -> void:
	for dept_id: String in _dept_nodes.keys():
		var info: Dictionary = _dept_nodes[dept_id] as Dictionary
		var show: bool = dept_id == _hovered_dept_id
		var sign_bg: Control = info.get("sign_bg") as Control
		var sign_label: Control = info.get("sign_label") as Control
		var badge: Control = info.get("badge") as Control
		if sign_bg != null:
			sign_bg.visible = show
		if sign_label != null:
			sign_label.visible = show
		if badge != null:
			badge.visible = show
	for sid: String in _station_views.keys():
		var view: ServiceStationView = _station_views[sid] as ServiceStationView
		if view != null:
			view.set_hovered(sid == _hovered_station_id)


func update_hover(screen_pos: Vector2) -> void:
	var dept_id: String = ""
	var station_id: String = ""
	if not is_department_placement_active() and iso_grid != null:
		var world_pos: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_pos
		var cell: Vector2i = iso_grid.screen_to_grid(world_pos)
		for did: String in _dept_nodes.keys():
			var info: Dictionary = _dept_nodes[did] as Dictionary
			var rect: Rect2i = info.get("rect", Rect2i()) as Rect2i
			if rect.size.x > 0 and rect.has_point(cell):
				dept_id = did
				break
		for sid: String in _station_views.keys():
			var view: ServiceStationView = _station_views[sid] as ServiceStationView
			if view == null:
				continue
			var local: Vector2 = world_pos - view.position
			if view.get_hit_rect().has_point(local):
				station_id = sid
				break
	if dept_id == _hovered_dept_id and station_id == _hovered_station_id:
		return
	_hovered_dept_id = dept_id
	_hovered_station_id = station_id
	_apply_entity_labels()


func _update_selection_highlights() -> void:
	for sid: String in _station_views.keys():
		var sv: ServiceStationView = _station_views[sid] as ServiceStationView
		if sv != null:
			sv.set_selected(_selected_type == &"station" and _selected_id == sid)
	for eid: String in _employee_views.keys():
		var ev: ActorView = _employee_views[eid] as ActorView
		if ev != null:
			ev.set_selected(_selected_type == &"employee" and _selected_id == eid)
	for cid: String in _customer_views.keys():
		var cv: ActorView = _customer_views[cid] as ActorView
		if cv != null:
			cv.set_selected(_selected_type == &"customer" and _selected_id == cid)


var _last_auto_world_frame: int = -1


func _on_snapshot_changed() -> void:
	var cur_frame: int = Engine.get_process_frames()
	if cur_frame == _last_auto_world_frame:
		return
	_last_auto_world_frame = cur_frame
	refresh_world()


func _on_locale_changed(_new_locale: String) -> void:
	refresh_world()


func _on_domain_event(event_type: StringName, payload: Dictionary) -> void:
	var cur_frame: int = Engine.get_process_frames()
	var allow_fx: bool = (_floating_effects.size() < 12 and cur_frame != _last_auto_world_frame)
	match String(event_type):
		"service_completed":
			if not allow_fx:
				return
			var st_id: String = str(payload.get("station_id", ""))
			var pos: Vector2 = iso_grid.grid_to_screen(Vector2i(6, 4))
			if _station_views.has(st_id):
				pos = (_station_views[st_id] as ServiceStationView).position
			var fee_minor: int = int(payload.get("fee_minor", 0))
			var amount_minor: int = int(payload.get("amount_minor", 0))
			var display_val: int = fee_minor if fee_minor > 0 else amount_minor
			var text: String = ""
			if display_val > 0:
				var money_str: String = FormatService.format_money_compact(display_val, "CNY", true)
				text = _tr("WORLD_FX_SERVICE_DONE", {"amount": money_str})
			else:
				text = _tr("WORLD_FX_SATISFACTION_UP")
			_spawn_floating_text(pos + Vector2(0.0, -32.0), text, Color("#FFC857"))
		"customer_left_unserved":
			if not allow_fx:
				return
			var cid: String = str(payload.get("customer_id", ""))
			var pos: Vector2 = iso_grid.grid_to_screen(ENTRANCE_CELL)
			if _customer_views.has(cid):
				pos = (_customer_views[cid] as ActorView).position
			_spawn_floating_text(pos + Vector2(0.0, -28.0), _tr("WORLD_FX_CUSTOMER_LEFT"), Color("#E74C3C"))
		"loan_approved":
			if allow_fx:
				var pos: Vector2 = iso_grid.grid_to_screen(Vector2i(11, 4))
				_spawn_floating_text(pos + Vector2(0.0, -34.0), _tr("WORLD_FX_LOAN_APPROVED"), Color("#35C978"))
		"loan_rejected":
			if allow_fx:
				var pos: Vector2 = iso_grid.grid_to_screen(Vector2i(11, 4))
				_spawn_floating_text(pos + Vector2(0.0, -34.0), _tr("WORLD_FX_LOAN_REJECTED"), Color("#E74C3C"))
		"department_created", "department_upgraded":
			var did: String = str(payload.get("department_id", ""))
			var lvl: int = maxi(1, int(payload.get("level", 1)))
			if allow_fx:
				var pos: Vector2 = Vector2.ZERO
				var has_pos: bool = false
				if _dept_nodes.has(did):
					var info: Dictionary = _dept_nodes[did] as Dictionary
					var dept_root: Node2D = info.get("root") as Node2D
					if dept_root != null and is_instance_valid(dept_root):
						pos = dept_root.position
						has_pos = true
				if not has_pos:
					pos = iso_grid.grid_to_screen(_fallback_dept_cell(did))
				var txt: String = _tr("WORLD_FX_DEPT_UPGRADED", {"level": lvl})
				_spawn_floating_text(pos + Vector2(0.0, -32.0), txt, Color("#00C6FF"))
			if cur_frame != _last_auto_world_frame:
				_last_auto_world_frame = cur_frame
				refresh_world()
		"employee_hired", "employee_fired", "employee_assigned", "station_toggled", "state_reloaded":
			if cur_frame != _last_auto_world_frame:
				_last_auto_world_frame = cur_frame
				refresh_world()


func _spawn_floating_text(world_pos: Vector2, text: String, color: Color) -> void:
	if _effects_layer == null:
		return
	var lbl := Label.new()
	lbl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lbl.text = text
	lbl.position = (world_pos - Vector2(36.0, 8.0)).round()
	lbl.size = Vector2(72.0, 16.0)
	lbl.scale = Vector2(0.75, 0.75)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	_effects_layer.add_child(lbl)
	_floating_effects.append({
		"node": lbl,
		"age": 0.0,
		"duration": 1.15,
		"start_pos": lbl.position,
	})


func _process(delta: float) -> void:
	# Animate central Starway fountain (4 frames)
	if _fountain_sprite != null:
		_fountain_timer += delta
		var interval: float = 1.0 / FOUNTAIN_FPS
		if _fountain_timer >= interval:
			_fountain_timer = fmod(_fountain_timer, interval)
			_fountain_frame = (_fountain_frame + 1) % 4
			_fountain_sprite.frame = _fountain_frame

	# Update floating effect labels
	if not _floating_effects.is_empty():
		var idx: int = _floating_effects.size() - 1
		while idx >= 0:
			var fx: Dictionary = _floating_effects[idx]
			var node_v: Variant = fx.get("node")
			if node_v == null or not is_instance_valid(node_v):
				_floating_effects.remove_at(idx)
				idx -= 1
				continue
			var lbl: Label = node_v as Label
			var age: float = float(fx.get("age", 0.0)) + delta
			var dur: float = maxf(0.1, float(fx.get("duration", 1.15)))
			if age >= dur:
				lbl.queue_free()
				_floating_effects.remove_at(idx)
			else:
				fx["age"] = age
				var t: float = age / dur
				var start_p: Vector2 = fx.get("start_pos", lbl.position) as Vector2
				lbl.position = (start_p + Vector2(0.0, -20.0 * t)).round()
				lbl.modulate.a = clampf(1.0 - t * t, 0.0, 1.0)
			idx -= 1


func _unhandled_input(event: InputEvent) -> void:
	if is_department_placement_active():
		if _handle_placement_input(event):
			return
	if event is InputEventMouseMotion:
		update_hover((event as InputEventMouseMotion).position)
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Use the event position (camera-aware) instead of polling the global mouse:
			# it is the authoritative position for this click and is deterministic in tests.
			var click_world: Vector2 = get_global_transform_with_canvas().affine_inverse() * mb.position
			if _try_pick_entity_at(click_world):
				var vp: Viewport = get_viewport()
				if vp != null:
					vp.set_input_as_handled()


## Returns true when the event was consumed by placement mode.
func _handle_placement_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		cancel_department_placement()
		_consume_input()
		return true
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var cursor_cell: Vector2i = cell_from_screen_position(mm.position)
		if _placement_dragging:
			_update_placement_preview(_normalize_room_rect(_placement_anchor, cursor_cell))
		elif iso_grid != null and iso_grid.is_in_bounds(cursor_cell):
			# Live preview of a default 4x4 room before the player starts dragging.
			_update_placement_preview(_default_room_at(cursor_cell))
		return false
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel_department_placement()
			_consume_input()
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var cell: Vector2i = cell_from_screen_position(mb.position)
			if mb.pressed:
				_placement_anchor = cell
				_placement_dragging = true
				_update_placement_preview(Rect2i(cell, Vector2i.ONE))
			elif _placement_dragging:
				_placement_dragging = false
				var rect: Rect2i = _normalize_room_rect(_placement_anchor, cell)
				if rect.size.x < MIN_ROOM_SIZE.x or rect.size.y < MIN_ROOM_SIZE.y:
					rect = _default_room_at(_placement_anchor)
				rect = _normalize_room_rect(rect.position, rect.position + rect.size - Vector2i.ONE)
				if is_valid_department_room(rect, _placement_dept_id):
					_confirm_department_placement(rect)
				else:
					_update_placement_preview(rect)
			_consume_input()
			return true
	return false


func _consume_input() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _try_pick_entity_at(world_pos: Vector2) -> bool:
	# Check customers & employees first (front-most by Y)
	var best_actor_type: StringName = &""
	var best_actor_id: String = ""
	var best_y: float = -INF

	for eid: String in _employee_views.keys():
		var ev: ActorView = _employee_views[eid] as ActorView
		if ev != null and ev.get_hit_rect().has_point(world_pos - ev.position):
			if ev.position.y >= best_y:
				best_y = ev.position.y
				best_actor_type = &"employee"
				best_actor_id = eid

	for cid: String in _customer_views.keys():
		var cv: ActorView = _customer_views[cid] as ActorView
		if cv != null and cv.get_hit_rect().has_point(world_pos - cv.position):
			if cv.position.y >= best_y:
				best_y = cv.position.y
				best_actor_type = &"customer"
				best_actor_id = cid

	if best_actor_type != &"":
		select_entity(best_actor_type, best_actor_id)
		return true

	# Check service stations
	var best_station_id: String = ""
	var best_station_y: float = -INF
	for sid: String in _station_views.keys():
		var sv: ServiceStationView = _station_views[sid] as ServiceStationView
		if sv != null and sv.get_hit_rect().has_point(world_pos - sv.position):
			if sv.position.y >= best_station_y:
				best_station_y = sv.position.y
				best_station_id = sid

	if not best_station_id.is_empty():
		select_entity(&"station", best_station_id)
		return true

	# If click is inside the square grid floor but missed entities, clear selection
	var clicked_cell: Vector2i = iso_grid.screen_to_grid(world_pos)
	if iso_grid.is_in_bounds(clicked_cell):
		focus_entity(&"", "")
		return true

	return false


## Pure affine re-projection of an existing diamond floor sprite; zero new assets.
func _floor_transform(pos: Vector2) -> Transform2D:
	return Transform2D(FLOOR_X_AXIS, FLOOR_Y_AXIS, pos)


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _draw() -> void:
	# Deep Space Navy backdrop + rectangular podium slab beneath the 18x12 square grid.
	draw_rect(Rect2(-400.0, -300.0, 2200.0, 1600.0), Color("#081B36"), true)

	if iso_grid == null:
		return

	var tl: Vector2 = iso_grid.grid_to_screen(Vector2i(0, 0)) + Vector2(-16.0, -16.0)
	var br: Vector2 = iso_grid.grid_to_screen(Vector2i(IsoGrid.GRID_WIDTH - 1, IsoGrid.GRID_HEIGHT - 1)) + Vector2(16.0, 16.0)
	var size: Vector2 = br - tl

	# 10px podium thickness on the south edge, 6px on the east/west edges.
	draw_rect(Rect2(tl.x, br.y, size.x, 10.0), Color("#0B2D5B"))
	draw_rect(Rect2(tl.x - 6.0, tl.y, 6.0, size.y + 10.0), Color("#0B2D5B"))
	draw_rect(Rect2(br.x, tl.y, 6.0, size.y + 10.0), Color("#0B2D5B"))
	# Bright south rim, subtle rectangular outline on the other edges.
	draw_line(Vector2(tl.x, br.y), Vector2(br.x, br.y), Color("#1F6FEB"), 1.5)
	draw_rect(Rect2(tl, size), Color("#263D5C"), false, 1.0)
