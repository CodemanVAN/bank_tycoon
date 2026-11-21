class_name BankWorld
extends Node2D

## 2.5D Isometric Bank Lobby World presentation root (18x12 IsoGrid, Y-Sorted props/stations/actors, PixelCamera2D).

signal entity_selected(entity_type: StringName, entity_id: String)

const FOUNTAIN_CELL: Vector2i = Vector2i(9, 7)
const ENTRANCE_CELL: Vector2i = Vector2i(8, 11)
const BREAK_CELL: Vector2i = Vector2i(3, 8)
const FOUNTAIN_FPS: float = 5.0

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

const STATIC_SOLID_CELLS: Array[Vector2i] = [
	Vector2i(9, 7),
	Vector2i(3, 8),
	Vector2i(14, 8),
	Vector2i(1, 1),
	Vector2i(16, 1),
	Vector2i(1, 10),
	Vector2i(16, 10),
	Vector2i(1, 5),
	Vector2i(1, 7),
	Vector2i(2, 2),
	Vector2i(5, 2),
	Vector2i(12, 2),
	Vector2i(15, 2),
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
var _departments_container: Node2D = null
var _stations_container: Node2D = null
var _actors_container: Node2D = null
var _effects_layer: Node2D = null
var _camera: PixelCamera2D = null
var _fountain_sprite: Sprite2D = null

var _fountain_timer: float = 0.0
var _fountain_frame: int = 0
var _static_built: bool = false

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
	_sync_departments(bs_obj)
	_sync_stations(bs_obj)
	_sync_employees(bs_obj)
	_sync_customers(bs_obj)
	_update_selection_highlights()


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

	# 1. Build 18x12 Isometric Floor Layer
	for y in range(IsoGrid.GRID_HEIGHT):
		for x in range(IsoGrid.GRID_WIDTH):
			var cell := Vector2i(x, y)
			var spr := Sprite2D.new()
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.centered = true
			spr.position = iso_grid.grid_to_screen(cell).round()

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

	# 2. Build North & West Architectural Cutaway Walls + Logo Backdrop + Glass Facade
	var tex_wall_back: Texture2D = _load_tex("res://assets/environment/wall_section_back.png")
	var tex_wall_logo: Texture2D = _load_tex("res://assets/environment/wall_logo_backdrop.png")
	var tex_wall_glass: Texture2D = _load_tex("res://assets/environment/wall_glass_facade.png")
	var tex_vault: Texture2D = _load_tex("res://assets/environment/prop_vault_door.png")

	for x in range(0, IsoGrid.GRID_WIDTH, 2):
		if x == 8 or x == 14:
			continue
		var w_spr := Sprite2D.new()
		w_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		w_spr.texture = tex_wall_back
		w_spr.centered = true
		w_spr.offset = Vector2(0.0, -22.0)
		w_spr.position = iso_grid.grid_to_screen(Vector2i(x, 0)).round()
		_wall_layer.add_child(w_spr)

	for y in range(2, IsoGrid.GRID_HEIGHT, 2):
		var w_spr := Sprite2D.new()
		w_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		w_spr.texture = tex_wall_back
		w_spr.centered = true
		w_spr.offset = Vector2(0.0, -22.0)
		w_spr.position = iso_grid.grid_to_screen(Vector2i(0, y)).round()
		_wall_layer.add_child(w_spr)

	# Central Starway emblem backdrop on north wall
	var logo_spr := Sprite2D.new()
	logo_spr.name = "StarwayLogoBackdrop"
	logo_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo_spr.texture = tex_wall_logo
	logo_spr.centered = true
	logo_spr.offset = Vector2(0.0, -24.0)
	logo_spr.position = iso_grid.grid_to_screen(Vector2i(8, 0)).round()
	_wall_layer.add_child(logo_spr)

	# Vault door in north-east high-security wing
	var vault_spr := Sprite2D.new()
	vault_spr.name = "VaultDoorProp"
	vault_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vault_spr.texture = tex_vault
	vault_spr.centered = true
	vault_spr.offset = Vector2(0.0, -22.0)
	vault_spr.position = iso_grid.grid_to_screen(Vector2i(14, 0)).round()
	_wall_layer.add_child(vault_spr)

	# South entrance glass facade segments
	for gx in [2, 5, 12, 15]:
		var g_spr := Sprite2D.new()
		g_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		g_spr.texture = tex_wall_glass
		g_spr.centered = true
		g_spr.offset = Vector2(0.0, -18.0)
		g_spr.modulate = Color(1.0, 1.0, 1.0, 0.55)
		g_spr.position = iso_grid.grid_to_screen(Vector2i(gx, 11)).round()
		_wall_layer.add_child(g_spr)

	# 3. Build Y-Sorted Lobby Props (Animated Fountain, Sofas, Queue Posts, Plants, ATMs)
	_fountain_sprite = Sprite2D.new()
	_fountain_sprite.name = "StarwayFountain"
	_fountain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fountain_sprite.texture = _load_tex("res://assets/environment/prop_fountain_sheet.png")
	_fountain_sprite.centered = true
	_fountain_sprite.hframes = 4
	_fountain_sprite.vframes = 1
	_fountain_sprite.offset = Vector2(0.0, -14.0)
	_fountain_sprite.position = iso_grid.grid_to_screen(FOUNTAIN_CELL).round()
	_props_container.add_child(_fountain_sprite)

	_add_prop_sprite("res://assets/environment/prop_sofa.png", Vector2i(3, 8), Vector2(0.0, -8.0))
	_add_prop_sprite("res://assets/environment/prop_sofa.png", Vector2i(14, 8), Vector2(0.0, -8.0))

	for qcell in [Vector2i(4, 6), Vector2i(6, 6), Vector2i(8, 6), Vector2i(11, 6)]:
		_add_prop_sprite("res://assets/environment/prop_queue_post.png", qcell, Vector2(0.0, -8.0))

	for pcell in [Vector2i(1, 1), Vector2i(16, 1), Vector2i(1, 10), Vector2i(16, 10), Vector2i(10, 4)]:
		_add_prop_sprite("res://assets/environment/prop_plant.png", pcell, Vector2(0.0, -12.0))

	for acell in [Vector2i(1, 5), Vector2i(1, 7)]:
		_add_prop_sprite("res://assets/environment/prop_atm.png", acell, Vector2(0.0, -14.0))

	# 4. Build 4 Department Visual Zones
	_build_department_zones()
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


func _build_department_zones() -> void:
	_dept_nodes.clear()
	var tex_desk: Texture2D = _load_tex("res://assets/environment/prop_desk_office.png")
	var tex_banner: Texture2D = _load_tex("res://assets/environment/prop_dept_banner.png")

	for dept_id: String in DEPT_ZONES.keys():
		var cfg: Dictionary = DEPT_ZONES[dept_id] as Dictionary
		var cell: Vector2i = cfg["cell"] as Vector2i
		var root := Node2D.new()
		root.name = "DeptZone_" + dept_id.replace("core:department.", "")
		root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		root.position = iso_grid.grid_to_screen(cell).round()

		var desk := Sprite2D.new()
		desk.name = "OfficeDesk"
		desk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		desk.texture = tex_desk
		desk.centered = true
		desk.offset = Vector2(0.0, -9.0)
		root.add_child(desk)

		var banner := Sprite2D.new()
		banner.name = "DeptBanner"
		banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		banner.texture = tex_banner
		banner.centered = true
		banner.offset = Vector2(15.0, -15.0)
		root.add_child(banner)

		var badge := Label.new()
		badge.name = "LevelBadge"
		badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.position = Vector2(-24.0, -34.0)
		badge.size = Vector2(64.0, 14.0)
		badge.scale = Vector2(0.75, 0.75)
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", cfg["accent"] as Color)
		root.add_child(badge)

		_departments_container.add_child(root)
		_dept_nodes[dept_id] = {
			"root": root,
			"desk": desk,
			"banner": banner,
			"badge": badge,
			"short_key": str(cfg["short_key"]),
			"level": 0,
		}


func _sync_navigation_solids(bs_obj: Object) -> void:
	iso_grid.clear_solids()
	for cell in STATIC_SOLID_CELLS:
		iso_grid.set_solid(cell, true)
	var raw_stations: Variant = bs_obj.get("stations")
	if raw_stations is Dictionary:
		var st_dict: Dictionary = raw_stations as Dictionary
		for sid: Variant in st_dict.keys():
			var st: Variant = st_dict[sid]
			if st is Dictionary:
				var gp: Variant = (st as Dictionary).get("grid_pos", Vector2i.ZERO)
				if gp is Vector2i:
					iso_grid.set_solid(gp as Vector2i, true)


func _sync_departments(bs_obj: Object) -> void:
	var raw_depts: Variant = bs_obj.get("departments")
	var depts_dict: Dictionary = raw_depts as Dictionary if raw_depts is Dictionary else {}

	for dept_id: String in _dept_nodes.keys():
		var info: Dictionary = _dept_nodes[dept_id] as Dictionary
		var desk: Sprite2D = info["desk"] as Sprite2D
		var banner: Sprite2D = info["banner"] as Sprite2D
		var badge: Label = info["badge"] as Label
		var short_key: String = str(info["short_key"])

		var lvl: int = 0
		if depts_dict.has(dept_id):
			var d_entry: Variant = depts_dict[dept_id]
			if d_entry is Dictionary:
				lvl = maxi(1, int((d_entry as Dictionary).get("level", 1)))
			elif d_entry is Object:
				lvl = maxi(1, int((d_entry as Object).get("level")))

		info["level"] = lvl
		if lvl > 0:
			desk.modulate = Color(1.0, 1.0, 1.0, 1.0)
			banner.visible = true
			badge.visible = true
			var dept_name: String = _tr(short_key)
			var lvl_str: String = _tr("WORLD_DEPT_LEVEL_BADGE", {"level": lvl})
			badge.text = "%s %s" % [dept_name, lvl_str]
		else:
			desk.modulate = Color(0.52, 0.6, 0.72, 0.42)
			banner.visible = false
			badge.visible = false


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
			if allow_fx and DEPT_ZONES.has(did):
				var cell: Vector2i = (DEPT_ZONES[did] as Dictionary)["cell"] as Vector2i
				var pos: Vector2 = iso_grid.grid_to_screen(cell)
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
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var click_world: Vector2 = get_global_mouse_position()
			if _try_pick_entity_at(click_world):
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

	# If click is inside the isometric grid floor but missed entities, clear selection
	var clicked_cell: Vector2i = iso_grid.screen_to_grid(world_pos)
	if iso_grid.is_in_bounds(clicked_cell):
		focus_entity(&"", "")
		return true

	return false


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _draw() -> void:
	# Deep Space Navy surrounding backdrop and architectural podium border beneath the 18x12 iso floor
	draw_rect(Rect2(-400.0, -300.0, 2200.0, 1600.0), Color("#081B36"), true)

	if iso_grid == null:
		return

	var top_pt: Vector2 = iso_grid.grid_to_screen(Vector2i(0, 0)) + Vector2(0.0, -10.0)
	var right_pt: Vector2 = iso_grid.grid_to_screen(Vector2i(IsoGrid.GRID_WIDTH - 1, 0)) + Vector2(18.0, 0.0)
	var bottom_pt: Vector2 = iso_grid.grid_to_screen(Vector2i(IsoGrid.GRID_WIDTH - 1, IsoGrid.GRID_HEIGHT - 1)) + Vector2(0.0, 12.0)
	var left_pt: Vector2 = iso_grid.grid_to_screen(Vector2i(0, IsoGrid.GRID_HEIGHT - 1)) + Vector2(-18.0, 0.0)

	# Podium slab thickness under south-west & south-east edges
	var slab_pts := PackedVector2Array([
		left_pt,
		bottom_pt,
		right_pt,
		right_pt + Vector2(0.0, 10.0),
		bottom_pt + Vector2(0.0, 10.0),
		left_pt + Vector2(0.0, 10.0),
	])
	draw_colored_polygon(slab_pts, Color("#0B2D5B"))

	var rim_line := PackedVector2Array([
		left_pt,
		bottom_pt,
		right_pt,
	])
	draw_polyline(rim_line, Color("#1F6FEB"), 1.5, false)
	draw_line(top_pt, right_pt, Color("#263D5C"), 1.0)
	draw_line(top_pt, left_pt, Color("#263D5C"), 1.0)
