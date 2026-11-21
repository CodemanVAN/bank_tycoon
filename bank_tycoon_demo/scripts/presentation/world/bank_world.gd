class_name BankWorld
extends Node2D

## 2.5D Isometric Bank Lobby World presentation root (18x12 IsoGrid, Y-Sorted props/stations/actors, PixelCamera2D).

signal entity_selected(entity_type: StringName, entity_id: String)
signal department_placement_confirmed(dept_id: String, room: Rect2i)
signal department_placement_cancelled()
signal layout_move_requested(kind: StringName, item_id: String, target_cell: Vector2i)
signal layout_build_requested(item_type: String, target_cell: Vector2i)
signal layout_delete_requested(kind: StringName, item_id: String)
signal layout_mode_changed(active: bool)

const ContentStudioStoreScript := preload("res://scripts/infrastructure/content_studio_store.gd")

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
var _prop_views: Dictionary = {}
var _employee_views: Dictionary = {}
var _customer_views: Dictionary = {}
var _leaving_customer_views: Array[ActorView] = []
var _customer_exit_reasons: Dictionary = {}
var _pending_arrival_speech: Dictionary = {}
var _ambient_chatter_timer: float = 0.0
var _ambient_chatter_seq: int = 0
var _sofa_complained_cids: Dictionary = {}
var _lobby_mgr_target_cells: Dictionary = {}
var _pending_counter_dialogue: Dictionary = {}
var _dept_nodes: Dictionary = {}
var _floating_effects: Array[Dictionary] = []

# Kairosoft-style Build / Layout Rearrange Mode
var _layout_mode_active: bool = false
var _layout_delete_mode: bool = false
var _layout_held_kind: StringName = &""
var _layout_held_id: String = ""
var _layout_held_size: Vector2i = Vector2i.ONE
var _layout_hover_cell: Vector2i = Vector2i(-99, -99)
var _layout_ghost: Node2D = null

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
	_clear_leaving_customers()
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
		"WORLD_SPEECH_CUST_ENTER_DEPOSIT": "您好，我想存一笔钱",
		"WORLD_SPEECH_CUST_ENTER_WITHDRAW": "请问取款在哪排队？",
		"WORLD_SPEECH_CUST_ENTER_TRANSFER": "麻烦办一笔转账",
		"WORLD_SPEECH_CUST_ENTER_LOAN": "我想咨询一下贷款",
		"WORLD_SPEECH_CUST_ENTER_MEETING": "预约了贵宾理财洽谈",
		"WORLD_SPEECH_CUST_ENTER_COMPLAINT": "这笔业务有点问题…",
		"WORLD_SPEECH_CUST_SERVING": "好的，这是我的证件",
		"WORLD_SPEECH_CUST_THANKS": "谢谢，效率真不错！",
		"WORLD_SPEECH_CUST_TIMEOUT": "等太久了，改天再来…",
		"WORLD_SPEECH_EMP_GREET": "您好！请问办理什么业务？",
		"WORLD_SPEECH_EMP_LOAN": "请稍候，马上为您初审",
		"WORLD_SPEECH_EMP_DONE": "手续已办妥，祝您愉快！",
		"WORLD_SPEECH_EMP_COMPLEX": "复杂疑难单，请稍等仔细核验",
		"WORLD_SPEECH_CUST_COMPLEX": "这笔跨行业务有点复杂，麻烦查下",
		"WORLD_SPEECH_CUST_SOFA": "排队太久了，先去沙发坐会儿…",
		"WORLD_SPEECH_EMP_TIRED_1": "好累啊，连轴转太久了…",
		"WORLD_SPEECH_EMP_TIRED_2": "真想休个假喘口气…",
		"WORLD_SPEECH_EMP_SLACK_1": "趁现在人少，摸会儿鱼聊聊天~",
		"WORLD_SPEECH_EMP_SLACK_2": "中午打算一起吃什么呀？",
		"WORLD_SPEECH_LM_ATM": "小额存取请跟我去 ATM 快速办理！",
		"WORLD_SPEECH_LM_SOOTHE": "让您久等了，马上为您安排窗口！",
		"WORLD_SPEECH_LM_COMPLAINT": "别着急，我立刻帮您妥善解决！",
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
		"WORLD_SPEECH_CUST_ENTER_DEPOSIT": "I'd like to make a deposit.",
		"WORLD_SPEECH_CUST_ENTER_WITHDRAW": "Where do I queue to withdraw?",
		"WORLD_SPEECH_CUST_ENTER_TRANSFER": "Need a quick wire transfer.",
		"WORLD_SPEECH_CUST_ENTER_LOAN": "I'd like to apply for a loan.",
		"WORLD_SPEECH_CUST_ENTER_MEETING": "Here for a VIP consultation.",
		"WORLD_SPEECH_CUST_ENTER_COMPLAINT": "I have an issue to resolve...",
		"WORLD_SPEECH_CUST_SERVING": "Sure, here is my ID.",
		"WORLD_SPEECH_CUST_THANKS": "Thanks, great service!",
		"WORLD_SPEECH_CUST_TIMEOUT": "Too long a wait, I'm leaving...",
		"WORLD_SPEECH_EMP_GREET": "Welcome! How can I help?",
		"WORLD_SPEECH_EMP_LOAN": "Reviewing your loan file now.",
		"WORLD_SPEECH_EMP_DONE": "All set! Have a great day!",
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
		"WORLD_SPEECH_CUST_ENTER_DEPOSIT": "預金をお願いしたいです",
		"WORLD_SPEECH_CUST_ENTER_WITHDRAW": "引き出しの列はこちらですか？",
		"WORLD_SPEECH_CUST_ENTER_TRANSFER": "振込の手続きをお願いします",
		"WORLD_SPEECH_CUST_ENTER_LOAN": "融資の相談に来ました",
		"WORLD_SPEECH_CUST_ENTER_MEETING": "VIP相談の予約があります",
		"WORLD_SPEECH_CUST_ENTER_COMPLAINT": "少し確認したい件が…",
		"WORLD_SPEECH_CUST_SERVING": "はい、身分証です",
		"WORLD_SPEECH_CUST_THANKS": "ありがとう、助かりました！",
		"WORLD_SPEECH_CUST_TIMEOUT": "待ちすぎたので帰ります…",
		"WORLD_SPEECH_EMP_GREET": "いらっしゃいませ！ご用件は？",
		"WORLD_SPEECH_EMP_LOAN": "ただいま審査いたします",
		"WORLD_SPEECH_EMP_DONE": "手続き完了です、またどうぞ！",
	},
}


func _tr(key: String, params: Dictionary = {}) -> String:
	if key.begins_with("RAW:"):
		return key.substr(4)
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
	_sync_props(bs_obj)
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


var _pre_placement_zoom: int = 0


func begin_department_placement(dept_id: String) -> bool:
	if dept_id.is_empty():
		return false
	_ensure_scene_hierarchy()
	_build_static_environment()
	_ensure_placement_ghost()
	if _placement_ghost == null:
		return false
	if _camera != null and _camera.get_zoom_step() > 1:
		_pre_placement_zoom = _camera.get_zoom_step()
		_camera.set_zoom_step(1)
	else:
		_pre_placement_zoom = 0
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
	if _pre_placement_zoom > 0 and _camera != null:
		_camera.set_zoom_step(_pre_placement_zoom)
		_pre_placement_zoom = 0


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
			_ghost_label.position = top_pos + Vector2(-100.0, -38.0)
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

	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			var tile := Polygon2D.new()
			tile.polygon = PackedVector2Array([
				Vector2(-16.0, -10.0), Vector2(16.0, -10.0), Vector2(16.0, 10.0), Vector2(-16.0, 10.0),
			])
			tile.color = Color(col.r, col.g, col.b, 0.30)
			tile.position = iso_grid.grid_to_screen(cell).round()
			_ghost_tiles.add_child(tile)

			var edge := Line2D.new()
			edge.points = PackedVector2Array([
				Vector2(-16.0, -10.0), Vector2(16.0, -10.0), Vector2(16.0, 10.0), Vector2(-16.0, 10.0), Vector2(-16.0, -10.0),
			])
			edge.width = 1.0
			edge.default_color = Color(col.r, col.g, col.b, 0.70)
			edge.position = tile.position
			_ghost_tiles.add_child(edge)
			if cell == door_cell:
				var opening_tile := Polygon2D.new()
				opening_tile.polygon = PackedVector2Array([
					Vector2(-12.0, -7.0), Vector2(12.0, -7.0), Vector2(12.0, 7.0), Vector2(-12.0, 7.0),
				])
				opening_tile.color = Color("#FFC857") if valid else Color(col.r, col.g, col.b, 0.55)
				opening_tile.position = tile.position
				_ghost_tiles.add_child(opening_tile)

	# Preview the actual room shell (orthogonal back wall + cutaway side trim + desk),
	# so the player sees the result before committing.
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		var cell_n := Vector2i(x, rect.position.y)
		if cell_n != door_cell:
			var wall := Sprite2D.new()
			wall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			wall.texture = tex_wall
			wall.centered = true
			wall.offset = Vector2(0.0, -34.0)
			wall.modulate = tint
			wall.position = iso_grid.grid_to_screen(cell_n).round()
			_ghost_tiles.add_child(wall)
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		var cell_w := Vector2i(rect.position.x, y)
		if cell_w != door_cell:
			var side_w := ColorRect.new()
			side_w.color = Color(col.r, col.g, col.b, 0.65)
			side_w.size = Vector2(4.0, float(IsoGrid.TILE_HEIGHT))
			side_w.position = iso_grid.grid_to_screen(cell_w).round() + Vector2(-IsoGrid.HALF_TILE_W, -IsoGrid.HALF_TILE_H)
			_ghost_tiles.add_child(side_w)
		var cell_e := Vector2i(rect.position.x + rect.size.x - 1, y)
		if cell_e != door_cell:
			var side_e := ColorRect.new()
			side_e.color = Color(col.r, col.g, col.b, 0.65)
			side_e.size = Vector2(4.0, float(IsoGrid.TILE_HEIGHT))
			side_e.position = iso_grid.grid_to_screen(cell_e).round() + Vector2(IsoGrid.HALF_TILE_W - 4.0, -IsoGrid.HALF_TILE_H)
			_ghost_tiles.add_child(side_e)

	var desk := Sprite2D.new()
	desk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	desk.texture = tex_desk
	desk.centered = true
	desk.offset = Vector2(0.0, -9.0)
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
	_ysort_layer.z_index = 1

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

	# 1. Build 18x12 Orthogonal Top-Down Floor Layer
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

	# 2. Logo backdrop / vault door sit flush on the straight horizontal north wall.
	var tex_wall_logo: Texture2D = _load_tex("res://assets/environment/wall_logo_backdrop.png")
	var tex_vault: Texture2D = _load_tex("res://assets/environment/prop_vault_door.png")

	var logo_spr := Sprite2D.new()
	logo_spr.name = "StarwayLogoBackdrop"
	logo_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo_spr.texture = tex_wall_logo
	logo_spr.centered = true
	logo_spr.offset = Vector2(16.0, -34.0)
	logo_spr.position = iso_grid.grid_to_screen(Vector2i(8, 0)).round()
	logo_spr.z_index = 2
	_wall_layer.add_child(logo_spr)

	var vault_spr := Sprite2D.new()
	vault_spr.name = "VaultDoorProp"
	vault_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vault_spr.texture = tex_vault
	vault_spr.centered = true
	vault_spr.offset = Vector2(0.0, -34.0)
	vault_spr.position = iso_grid.grid_to_screen(Vector2i(14, 0)).round()
	vault_spr.z_index = 2
	_wall_layer.add_child(vault_spr)

	# 3. Lobby props (fountain, sofas, queue posts, plants, ATMs) are synced dynamically
	# from BankState.lobby_props by _sync_props() so players can rearrange them in Layout Mode.
	queue_redraw()


func _sync_props(bs_obj: Object) -> void:
	if _props_container == null:
		return
	var raw_props: Variant = bs_obj.get("lobby_props")
	var prop_dict: Dictionary = raw_props as Dictionary if (raw_props is Dictionary and not (raw_props as Dictionary).is_empty()) else BankState.default_lobby_props()

	var seen: Dictionary = {}
	for pid_v: Variant in prop_dict.keys():
		var pid: String = str(pid_v)
		var pr: Variant = prop_dict[pid_v]
		if not (pr is Dictionary):
			continue
		var prd: Dictionary = pr as Dictionary
		seen[pid] = true
		var ptype: String = str(prd.get("prop_type", "plant"))
		var gp: Vector2i = Vector2i(1, 1)
		var raw_gp: Variant = prd.get("grid_pos", gp)
		if raw_gp is Vector2i:
			gp = raw_gp as Vector2i
		elif raw_gp is Array and (raw_gp as Array).size() >= 2:
			gp = Vector2i(int((raw_gp as Array)[0]), int((raw_gp as Array)[1]))

		var spr: Sprite2D = _prop_views.get(pid, null) as Sprite2D
		if spr == null:
			spr = Sprite2D.new()
			spr.name = "Prop_" + pid
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.centered = true
			match ptype:
				"fountain":
					spr.texture = _load_tex("res://assets/environment/prop_fountain_sheet.png")
					spr.hframes = 4
					spr.vframes = 1
					spr.offset = Vector2(0.0, -14.0)
					_fountain_sprite = spr
				"sofa":
					spr.texture = _load_tex("res://assets/environment/prop_sofa.png")
					spr.offset = Vector2(0.0, -8.0)
				"atm":
					spr.texture = _load_tex("res://assets/environment/prop_atm.png")
					spr.offset = Vector2(0.0, -14.0)
				"queue_post":
					spr.texture = _load_tex("res://assets/environment/prop_queue_post.png")
					spr.offset = Vector2(0.0, -8.0)
				"coffee_bar":
					spr.texture = _load_tex("res://assets/environment/prop_coffee_bar.png")
					spr.offset = Vector2(0.0, -10.0)
				"aquarium":
					spr.texture = _load_tex("res://assets/environment/prop_aquarium.png")
					spr.offset = Vector2(0.0, -12.0)
				"gold_bull":
					spr.texture = _load_tex("res://assets/environment/prop_gold_bull.png")
					spr.offset = Vector2(0.0, -10.0)
				"bookshelf":
					spr.texture = _load_tex("res://assets/environment/prop_bookshelf.png")
					spr.offset = Vector2(0.0, -12.0)
				_:
					var eff_cat: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
					if eff_cat.has(ptype):
						var cspec: Dictionary = eff_cat[ptype] as Dictionary
						var ctex: String = str(cspec.get("tex_path", cspec.get("texture", "res://assets/environment/prop_plant.png")))
						spr.texture = _load_tex(ctex)
						spr.offset = cspec.get("offset", Vector2(0.0, -10.0)) as Vector2
					else:
						spr.texture = _load_tex("res://assets/environment/prop_plant.png")
						spr.offset = Vector2(0.0, -12.0)
			_props_container.add_child(spr)
			_prop_views[pid] = spr
		spr.position = iso_grid.grid_to_screen(gp).round()

	for old_pid: String in _prop_views.keys().duplicate():
		if not seen.has(old_pid):
			var old_s: Node = _prop_views[old_pid] as Node
			_prop_views.erase(old_pid)
			if old_s == _fountain_sprite:
				_fountain_sprite = null
			if old_s != null:
				if old_s.get_parent() != null:
					old_s.get_parent().remove_child(old_s)
				old_s.free()


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
	root.y_sort_enabled = true
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
			tile.z_index = -1
			tile.modulate = Color(1.0, 1.0, 1.0, 1.0) if cell != door_cell else Color(1.15, 1.1, 0.85, 1.0)
			tile.position = iso_grid.grid_to_screen(cell).round() - root.position
			root.add_child(tile)

	# Auto-generated door at the connection with the existing building.
	if rect.has_point(door_cell):
		var door_pos: Vector2 = iso_grid.grid_to_screen(door_cell).round() - root.position
		var door_mark := Polygon2D.new()
		door_mark.name = "DoorMark"
		door_mark.z_index = -1
		door_mark.polygon = PackedVector2Array([
			Vector2(-13.0, -8.0), Vector2(13.0, -8.0), Vector2(13.0, 8.0), Vector2(-13.0, 8.0),
		])
		door_mark.color = Color(1.0, 0.78, 0.34, 0.55)
		door_mark.position = door_pos
		root.add_child(door_mark)
		var door_frame := Line2D.new()
		door_frame.name = "DoorFrame"
		door_frame.z_index = -1
		door_frame.points = PackedVector2Array([
			Vector2(-13.0, -8.0), Vector2(13.0, -8.0), Vector2(13.0, 8.0), Vector2(-13.0, 8.0), Vector2(-13.0, -8.0),
		])
		door_frame.width = 1.5
		door_frame.default_color = Color("#FFC857")
		door_frame.position = door_pos
		root.add_child(door_frame)

	var sign_anchor := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y)
	var sign_pos: Vector2 = iso_grid.grid_to_screen(sign_anchor).round() - root.position + Vector2(-64.0, -50.0)
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
	desk.offset = Vector2(0.0, -9.0)
	# Place desk 5px in front of the middle cell so the department specialist stands visibly behind it
	desk.position = iso_grid.grid_to_screen(desk_cell).round() - root.position + Vector2(0.0, 5.0)
	root.add_child(desk)

	var banner := Sprite2D.new()
	banner.name = "DeptBanner"
	banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	banner.texture = tex_banner
	banner.centered = true
	banner.offset = Vector2(15.0, -15.0)
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
	badge.position = iso_grid.grid_to_screen(Vector2i(rect.position.x, rect.position.y)).round() - root.position + Vector2(-48.0, -34.0)
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
		Vector2(-16.0, -10.0), Vector2(16.0, -10.0), Vector2(16.0, 10.0), Vector2(-16.0, 10.0),
	])
	mat.color = Color(accent.r, accent.g, accent.b, 0.16)
	root.add_child(mat)

	var desk := Sprite2D.new()
	desk.name = "OfficeDesk"
	desk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	desk.texture = _load_tex("res://assets/environment/prop_desk_office.png")
	desk.centered = true
	desk.offset = Vector2(0.0, -9.0)
	root.add_child(desk)

	var banner := Sprite2D.new()
	banner.name = "DeptBanner"
	banner.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	banner.texture = _load_tex("res://assets/environment/prop_dept_banner.png")
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
		var cell_pos: Vector2 = iso_grid.grid_to_screen(c).round()
		var has_north_wall: bool = not built.has(Vector2i(c.x, c.y - 1))
		# North-facing orthogonal back wall (32x48 sits flush along tile top edge y = -10).
		if has_north_wall:
			var wall := Sprite2D.new()
			wall.name = "ExtWallN_%d_%d" % [c.x, c.y]
			wall.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			wall.texture = tex_wall
			wall.centered = true
			wall.offset = Vector2(0.0, -34.0)
			wall.position = cell_pos
			_exterior_walls.add_child(wall)
		# West-facing cutaway side wall when the cell to the left is empty land.
		if not built.has(Vector2i(c.x - 1, c.y)):
			var wall_w := _make_side_wall_strip("ExtWallW_%d_%d" % [c.x, c.y], cell_pos, true, has_north_wall)
			_exterior_walls.add_child(wall_w)
		# East-facing cutaway side wall when the cell to the right is empty land.
		if not built.has(Vector2i(c.x + 1, c.y)):
			var wall_e := _make_side_wall_strip("ExtWallE_%d_%d" % [c.x, c.y], cell_pos, false, has_north_wall)
			_exterior_walls.add_child(wall_e)


func _make_side_wall_strip(node_name: String, cell_pos: Vector2, is_west: bool, extend_to_north_wall: bool) -> Node2D:
	var root := Node2D.new()
	root.name = node_name
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.position = cell_pos

	var strip_w: float = 5.0
	var x_left: float = -IsoGrid.HALF_TILE_W if is_west else (IsoGrid.HALF_TILE_W - strip_w)
	var y_top: float = -58.0 if extend_to_north_wall else -IsoGrid.HALF_TILE_H
	var total_h: float = IsoGrid.HALF_TILE_H - y_top

	# Dark architectural outline backing
	var border := ColorRect.new()
	border.color = Color("#132A4A")
	border.position = Vector2(x_left, y_top)
	border.size = Vector2(strip_w, total_h)
	root.add_child(border)

	# Cutaway wall cap (slate architectural cross-section)
	var body := ColorRect.new()
	body.color = Color("#263D5C")
	body.position = Vector2(x_left + 1.0, y_top + 1.0)
	body.size = Vector2(strip_w - 2.0, total_h - 1.0)
	root.add_child(body)

	# Inner highlight edge facing the room
	var trim := ColorRect.new()
	trim.color = Color("#3D72B4")
	trim.position = Vector2(x_left + (strip_w - 2.0 if is_west else 1.0), y_top + 1.0)
	trim.size = Vector2(1.0, total_h - 1.0)
	root.add_child(trim)

	return root


func _sync_navigation_solids(bs_obj: Object) -> void:
	iso_grid.clear_solids()
	var raw_props: Variant = bs_obj.get("lobby_props")
	if raw_props is Dictionary and not (raw_props as Dictionary).is_empty():
		for pid_v: Variant in (raw_props as Dictionary).keys():
			var pr: Variant = (raw_props as Dictionary)[pid_v]
			if pr is Dictionary and bool((pr as Dictionary).get("solid", false)):
				var pgp: Variant = (pr as Dictionary).get("grid_pos", null)
				if pgp is Vector2i:
					iso_grid.set_solid(pgp as Vector2i, true)
	else:
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
	size = Vector2i(maxi(1, size.x), maxi(1, size.y))
	if size.x <= 1 and size.y <= 1 and (cell.x < 0 or cell.y < 0):
		return Rect2i()
	return Rect2i(cell, size)


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
	var claimed_cells: Dictionary = {}
	var emp_idx: int = 0
	var spd: float = clampf(float(int(bs_obj.get("speed_multiplier"))), 1.0, 3.0)
	var sorted_eids: Array[String] = []
	for eid_v: Variant in emp_dict.keys():
		sorted_eids.append(str(eid_v))
	sorted_eids.sort()

	for eid in sorted_eids:
		var emp: Variant = emp_dict[eid]
		if not (emp is Object):
			continue
		seen[eid] = true
		var emp_obj: Object = emp as Object
		var desired_cell: Vector2i = _resolve_employee_cell(emp_obj, st_dict, bs_obj, emp_idx)
		# Guarantee two employees never share the exact same tile
		var safety_try: int = 0
		while claimed_cells.has(desired_cell) and safety_try < 6:
			desired_cell = iso_grid.clamp_to_bounds(desired_cell + Vector2i(1, 0))
			safety_try += 1
		claimed_cells[desired_cell] = true
		emp_idx += 1
		var desired_screen: Vector2 = iso_grid.grid_to_screen(desired_cell)

		var view: ActorView = _employee_views.get(eid, null) as ActorView
		if view == null:
			view = ActorView.new()
			view.name = "Emp_" + eid
			_actors_container.add_child(view)
			_employee_views[eid] = view
			view.speed_scale = spd
			view.configure_employee(emp_obj, desired_screen)
			view.grid_pos = desired_cell
			view.snap_to_screen(desired_screen)
		else:
			var prev_cell: Vector2i = view.grid_pos
			view.speed_scale = spd
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


func _resolve_employee_cell(emp_obj: Object, st_dict: Dictionary, bs_obj: Object = null, emp_idx: int = 0) -> Vector2i:
	var st_state: int = int(emp_obj.get("state"))
	if st_state == Enums.EmployeeState.BREAK:
		return BREAK_CELL
	# 1. Department specialist works inside their department room
	var dept_id: String = str(emp_obj.get("department_id"))
	if not dept_id.is_empty() and bs_obj != null:
		var depts: Variant = bs_obj.get("departments")
		if depts is Dictionary and (depts as Dictionary).has(dept_id):
			var d_rect: Rect2i = _read_dept_rect((depts as Dictionary)[dept_id])
			if d_rect.size.x >= 2 or d_rect.size.y >= 2:
				return iso_grid.clamp_to_bounds(Vector2i(d_rect.position.x + d_rect.size.x / 2, d_rect.position.y + d_rect.size.y / 2))
			return _fallback_dept_cell(dept_id)
	# 2. Lobby Manager patrols the main hall (ATMs, queue, welcome carpet)
	var role_id: String = str(emp_obj.get("role_id"))
	if role_id == "lobby_manager":
		var eid: String = str(emp_obj.get("id"))
		if _lobby_mgr_target_cells.has(eid):
			return _lobby_mgr_target_cells[eid] as Vector2i
		var cur_min: int = int(bs_obj.get("current_minute_of_day")) if bs_obj != null else 0
		var patrol_pts: Array[Vector2i] = [Vector2i(8, 8), Vector2i(2, 6), Vector2i(6, 7), Vector2i(11, 7)]
		return patrol_pts[(cur_min / 6 + emp_idx) % patrol_pts.size()]
	# 3. Actively serving a request: always stand directly behind that station's counter
	var task_id: String = str(emp_obj.get("current_request_id"))
	if not task_id.is_empty() and bs_obj != null:
		var reqs: Variant = bs_obj.get("service_requests")
		if reqs is Array:
			for req_v: Variant in (reqs as Array):
				if req_v is Object and str((req_v as Object).get("request_id")) == task_id:
					var active_st_id: String = str((req_v as Object).get("assigned_station_id"))
					if not active_st_id.is_empty() and st_dict.has(active_st_id):
						var st_a: Variant = st_dict[active_st_id]
						if st_a is Dictionary:
							var gp_a: Variant = (st_a as Dictionary).get("grid_pos", Vector2i(4, 4))
							if gp_a is Vector2i:
								return iso_grid.clamp_to_bounds((gp_a as Vector2i) + Vector2i(0, -1))
	# 4. Assigned station: stand behind their counter
	var assigned_st: String = str(emp_obj.get("assigned_station_id"))
	if not assigned_st.is_empty() and st_dict.has(assigned_st):
		var st: Variant = st_dict[assigned_st]
		if st is Dictionary:
			var gp: Variant = (st as Dictionary).get("grid_pos", Vector2i(4, 4))
			if gp is Vector2i:
				return iso_grid.clamp_to_bounds((gp as Vector2i) + Vector2i(0, -1))
	# 5. Unassigned idle employees stay in the back-office behind the counters
	return Vector2i(3 + (emp_idx % 6) * 2, 2)


func _sync_customers(bs_obj: Object) -> void:
	var raw_custs: Variant = bs_obj.get("active_customers")
	if not (raw_custs is Dictionary):
		return
	var cust_dict: Dictionary = raw_custs as Dictionary
	var raw_stations: Variant = bs_obj.get("stations")
	var st_dict: Dictionary = raw_stations as Dictionary if raw_stations is Dictionary else {}
	var day_phase: int = int(bs_obj.get("day_phase"))
	var allow_walk_lifecycle: bool = (day_phase == Enums.DayPhase.OPEN or day_phase == Enums.DayPhase.CLOSING)

	var sorted_cids: Array[String] = []
	for cid_v: Variant in cust_dict.keys():
		sorted_cids.append(str(cid_v))
	# Process IN_SERVICE customers first so they reserve their counter front, then WAITING in arrival order
	sorted_cids.sort_custom(func(a: String, b: String) -> bool:
		var ca: Variant = cust_dict.get(a, null)
		var cb: Variant = cust_dict.get(b, null)
		var sa: int = int((ca as Object).get("state")) if ca is Object else 0
		var sb: int = int((cb as Object).get("state")) if cb is Object else 0
		var a_srv: int = 0 if sa == Enums.CustomerState.IN_SERVICE else 1
		var b_srv: int = 0 if sb == Enums.CustomerState.IN_SERVICE else 1
		if a_srv != b_srv:
			return a_srv < b_srv
		var ma: int = int((ca as Object).get("arrival_minute")) if ca is Object else 0
		var mb: int = int((cb as Object).get("arrival_minute")) if cb is Object else 0
		if ma != mb:
			return ma < mb
		return a < b
	)

	var seen: Dictionary = {}
	var wait_idx: int = 0
	var used_cells: Dictionary = {}
	var used_sofas: Array[Vector2i] = []
	var sofa_seats: Array[Vector2i] = [Vector2i(3, 8), Vector2i(14, 8)]
	var spd: float = clampf(float(int(bs_obj.get("speed_multiplier"))), 1.0, 3.0)
	for cid in sorted_cids:
		var cust: Variant = cust_dict[cid]
		if not (cust is Object):
			continue
		seen[cid] = true
		var cust_obj: Object = cust as Object
		var cstate: int = int(cust_obj.get("state"))
		var p_max: int = maxi(1, int(cust_obj.get("patience_max")))
		var p_rem: int = int(cust_obj.get("patience_remaining"))
		var p_ratio: float = float(p_rem) / float(p_max)

		var desired_cell: Vector2i = _resolve_customer_cell(cust_obj, st_dict, wait_idx, bs_obj, used_cells)
		var sitting_sofa: bool = false
		if cstate == Enums.CustomerState.WAITING and p_ratio < 0.65 and str(cust_obj.get("browsing_prop_id")).is_empty():
			for s_cell in sofa_seats:
				if not used_sofas.has(s_cell) and not used_cells.has(s_cell):
					desired_cell = s_cell
					used_sofas.append(s_cell)
					sitting_sofa = true
					break
		used_cells[desired_cell] = true
		if cstate == Enums.CustomerState.WAITING or cstate == Enums.CustomerState.FINDING_SERVICE:
			wait_idx += 1
		var desired_screen: Vector2 = iso_grid.grid_to_screen(desired_cell)

		var view: ActorView = _customer_views.get(cid, null) as ActorView
		if view == null:
			view = ActorView.new()
			view.name = "Cust_" + cid
			_actors_container.add_child(view)
			_customer_views[cid] = view
			view.speed_scale = spd
			# New customers always walk in from the main lobby entrance door (no premature speech).
			var spawn_cell: Vector2i = ENTRANCE_CELL if allow_walk_lifecycle else desired_cell
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
			_pending_arrival_speech.erase(cid)
		else:
			var prev_cell: Vector2i = view.grid_pos
			view.speed_scale = spd
			view.configure_customer(cust_obj, desired_screen)
			view.grid_pos = desired_cell
			if prev_cell != desired_cell:
				var cell_path: Array[Vector2i] = iso_grid.find_path_or_adjacent(prev_cell, desired_cell)
				var screen_pts: Array[Vector2] = []
				for c in cell_path:
					screen_pts.append(iso_grid.grid_to_screen(c))
				screen_pts.append(desired_screen)
				view.set_screen_path(screen_pts)
			if sitting_sofa and not _sofa_complained_cids.has(cid):
				_sofa_complained_cids[cid] = true
				view.show_speech(_tr("WORLD_SPEECH_CUST_SOFA"), 2.4, Color("#FFC857"))

	for old_id: String in _customer_views.keys().duplicate():
		if not seen.has(old_id):
			var old_v: ActorView = _customer_views[old_id] as ActorView
			_customer_views.erase(old_id)
			var exit_reason: String = str(_customer_exit_reasons.get(old_id, "completed"))
			_customer_exit_reasons.erase(old_id)
			if old_v == null:
				continue
			if allow_walk_lifecycle and _leaving_customer_views.size() < 12:
				var cur_cell: Vector2i = iso_grid.screen_to_grid(old_v.position)
				if not iso_grid.is_in_bounds(cur_cell):
					cur_cell = old_v.grid_pos
				old_v.actor_state = Enums.CustomerState.LEAVING
				old_v.grid_pos = ENTRANCE_CELL
				var exit_path: Array[Vector2i] = iso_grid.find_path_or_adjacent(cur_cell, ENTRANCE_CELL)
				var exit_pts: Array[Vector2] = []
				for ec in exit_path:
					exit_pts.append(iso_grid.grid_to_screen(ec))
				exit_pts.append(iso_grid.grid_to_screen(ENTRANCE_CELL))
				old_v.set_screen_path(exit_pts)
				if exit_reason == "angry_complaint":
					old_v.show_speech(_tr("WORLD_SPEECH_CUST_ANGRY_LEAVE"), 2.8, Color("#FF4D4F"))
				elif exit_reason == "timeout":
					old_v.show_speech(_tr("WORLD_SPEECH_CUST_TIMEOUT"), 2.2, Color("#E74C3C"))
				else:
					old_v.show_speech(_tr("WORLD_SPEECH_CUST_THANKS"), 2.2, Color("#35C978"))
				_leaving_customer_views.append(old_v)
			else:
				if old_v.get_parent() != null:
					old_v.get_parent().remove_child(old_v)
				old_v.free()


func _clear_leaving_customers() -> void:
	for lv in _leaving_customer_views:
		if lv != null and is_instance_valid(lv):
			if lv.get_parent() != null:
				lv.get_parent().remove_child(lv)
			lv.free()
	_leaving_customer_views.clear()
	_customer_exit_reasons.clear()


func _resolve_customer_cell(
	cust_obj: Object,
	st_dict: Dictionary,
	wait_idx: int,
	bs_obj: Object = null,
	used_cells: Dictionary = {}
) -> Vector2i:
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

	# Waiting customer randomly browsing luxury decor walks over to admire it
	if cstate == Enums.CustomerState.WAITING and bs_obj != null:
		var browse_pid: String = str(cust_obj.get("browsing_prop_id"))
		if not browse_pid.is_empty():
			var raw_bp: Variant = bs_obj.get("lobby_props")
			if raw_bp is Dictionary and (raw_bp as Dictionary).has(browse_pid):
				var bpr: Variant = (raw_bp as Dictionary)[browse_pid]
				if bpr is Dictionary and (bpr as Dictionary).get("grid_pos", null) is Vector2i:
					var bgp: Vector2i = (bpr as Dictionary)["grid_pos"] as Vector2i
					for off_b: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
						var bc: Vector2i = iso_grid.clamp_to_bounds(bgp + off_b)
						if not used_cells.has(bc):
							return bc

	# Direct pathfinding: ATM self-service customers queue neatly in front of ATMs without stacking
	var srv_str: String = ""
	var is_atm_routed: bool = false
	var busy_stations: Dictionary = {}
	if bs_obj != null:
		var req_id: String = str(cust_obj.get("active_request_id"))
		var reqs: Variant = bs_obj.get("service_requests")
		if reqs is Array:
			for r_v: Variant in (reqs as Array):
				if r_v is Object:
					var ro: Object = r_v as Object
					var rst: int = int(ro.get("status"))
					if rst == Enums.RequestStatus.IN_PROGRESS or rst == Enums.RequestStatus.ASSIGNED:
						var ast: String = str(ro.get("assigned_station_id"))
						if not ast.is_empty():
							busy_stations[ast] = true
					if str(ro.get("request_id")) == req_id:
						srv_str = str(ro.get("service_type"))
						var pl: Variant = ro.get("payload")
						if pl is Dictionary and str((pl as Dictionary).get("atm_mode", "")) != "":
							is_atm_routed = true

	if is_atm_routed and bs_obj != null:
		var atm_queue_cells: Array[Vector2i] = []
		var raw_p: Variant = bs_obj.get("lobby_props")
		if raw_p is Dictionary:
			var pids_sorted: Array[String] = []
			for pid_v: Variant in (raw_p as Dictionary).keys():
				pids_sorted.append(str(pid_v))
			pids_sorted.sort()
			for step_x: int in [1, 2, 3]:
				for pid_s: String in pids_sorted:
					var pr: Variant = (raw_p as Dictionary)[pid_s]
					if pr is Dictionary and str((pr as Dictionary).get("prop_type", "")) == "atm":
						var agp: Variant = (pr as Dictionary).get("grid_pos", null)
						if agp is Vector2i:
							atm_queue_cells.append(iso_grid.clamp_to_bounds((agp as Vector2i) + Vector2i(step_x, 0)))
		for ac: Vector2i in atm_queue_cells:
			if not used_cells.has(ac):
				return ac

	if not srv_str.is_empty():
		var st_ids: Array[String] = []
		for k: Variant in st_dict.keys():
			st_ids.append(str(k))
		st_ids.sort()
		# First try free matching counter front cells (step_y = 1), then neat single-file queue behind them (step_y = 2, 3, 4)
		for step_y: int in [1, 2, 3, 4]:
			for sid in st_ids:
				if step_y == 1 and busy_stations.has(sid):
					continue
				var st_v: Variant = st_dict[sid]
				if not (st_v is Dictionary):
					continue
				var std: Dictionary = st_v as Dictionary
				if not bool(std.get("is_open", false)):
					continue
				var allowed: Variant = std.get("allowed_services", [])
				if allowed is Array and not (allowed as Array).is_empty() and not (allowed as Array).has(srv_str):
					continue
				var gp_free: Variant = std.get("grid_pos", null)
				if gp_free is Vector2i:
					var cand_cell: Vector2i = iso_grid.clamp_to_bounds((gp_free as Vector2i) + Vector2i(0, step_y))
					if not used_cells.has(cand_cell):
						return cand_cell

		if srv_str == "personal_loan_application" or srv_str == "business_meeting" or srv_str == "wealth_advisory":
			var loan_q: Array[Vector2i] = [
				Vector2i(11, 6), Vector2i(11, 7), Vector2i(11, 8), Vector2i(10, 8), Vector2i(12, 8),
			]
			for lq: Vector2i in loan_q:
				if not used_cells.has(lq):
					return lq

	var fallback_q: Array[Vector2i] = [
		Vector2i(4, 6), Vector2i(6, 6), Vector2i(8, 6),
		Vector2i(4, 7), Vector2i(6, 7), Vector2i(8, 7),
		Vector2i(5, 7), Vector2i(7, 7), Vector2i(5, 8), Vector2i(7, 8),
		Vector2i(6, 8), Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8),
	]
	for fq: Vector2i in fallback_q:
		if not used_cells.has(fq):
			return fq
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
		"CustomerArrived", "customer_arrived":
			# Do not pop a speech bubble at the entrance door; wait until the customer reaches a counter.
			pass
		"ServiceStarted", "service_started":
			var emp_s: String = str(payload.get("employee_id", ""))
			var cid_s: String = str(payload.get("customer_id", ""))
			var srv_s: String = str(payload.get("service_type", ""))
			var is_complex: bool = bool(payload.get("is_complex_case", false))
			var emp_key: String = "WORLD_SPEECH_EMP_COMPLEX" if is_complex else ("WORLD_SPEECH_EMP_LOAN" if srv_s == "personal_loan_application" else "WORLD_SPEECH_EMP_GREET")
			var cust_key: String = "WORLD_SPEECH_CUST_COMPLEX" if is_complex else _customer_arrival_speech_key(srv_s)
			# Defer both speech bubbles until the customer physically reaches the counter front
			if not cid_s.is_empty():
				_pending_counter_dialogue[cid_s] = {
					"employee_id": emp_s,
					"emp_key": emp_key,
					"cust_key": cust_key,
				}
		"AtmServiceStarted", "atm_service_started":
			var cid_a: String = str(payload.get("customer_id", ""))
			var srv_a: String = str(payload.get("service_type", ""))
			if not cid_a.is_empty():
				_pending_counter_dialogue[cid_a] = {
					"employee_id": "",
					"emp_key": "",
					"cust_key": "WORLD_SPEECH_CUST_ATM_WITHDRAW" if srv_a == "cash_withdrawal" else "WORLD_SPEECH_CUST_ATM",
				}
		"CustomerBrowsedDecor":
			var cid_b: String = str(payload.get("customer_id", ""))
			var ptype_b: String = str(payload.get("prop_type", "fountain"))
			if not cid_b.is_empty():
				var custom_decor_dlgs: Array[Dictionary] = ContentStudioStoreScript.get_dialogues_for_category("cust_decor")
				var dkey: String = "WORLD_SPEECH_CUST_DECOR_COFFEE" if ptype_b == "coffee_bar" else ("WORLD_SPEECH_CUST_DECOR_BULL" if ptype_b == "gold_bull" else "WORLD_SPEECH_CUST_DECOR_GENERIC")
				if not custom_decor_dlgs.is_empty():
					var pick_d: Dictionary = custom_decor_dlgs[_ambient_chatter_seq % custom_decor_dlgs.size()]
					_ambient_chatter_seq += 1
					dkey = "RAW:" + str(pick_d.get("text", ""))
				_pending_counter_dialogue[cid_b] = {
					"employee_id": "",
					"emp_key": "",
					"cust_key": dkey,
				}
		"CustomerAngryComplaint":
			var cid_ang: String = str(payload.get("customer_id", ""))
			if not cid_ang.is_empty():
				_customer_exit_reasons[cid_ang] = "angry_complaint"
				if _customer_views.has(cid_ang):
					var av_ang: ActorView = _customer_views[cid_ang] as ActorView
					if av_ang != null and allow_fx:
						_spawn_floating_text(av_ang.position + Vector2(0.0, -24.0), _tr("WORLD_FX_ANGRY_COMPLAINT"), Color("#FF4D4F"))
		"LobbyManagerAction":
			var lm_id: String = str(payload.get("employee_id", ""))
			var lm_act: String = str(payload.get("action", "soothe"))
			var lm_cid: String = str(payload.get("customer_id", ""))
			if lm_act == "atm_guide":
				_lobby_mgr_target_cells[lm_id] = Vector2i(3, 6)
				if _customer_views.has(lm_cid):
					var cv_g: ActorView = _customer_views[lm_cid] as ActorView
					if cv_g != null:
						cv_g.show_speech(_tr("WORLD_SPEECH_CUST_GUIDED_ATM"), 2.2, Color("#7FD8FF"))
			elif lm_act == "soothe" or lm_act == "resolve_complaint":
				_lobby_mgr_target_cells[lm_id] = Vector2i(7, 7)
			if _employee_views.has(lm_id):
				var lm_v: ActorView = _employee_views[lm_id] as ActorView
				if lm_v != null:
					var lm_key: String = "WORLD_SPEECH_LM_SOOTHE"
					if lm_act == "atm_guide":
						lm_key = "WORLD_SPEECH_LM_ATM"
					elif lm_act == "resolve_complaint":
						lm_key = "WORLD_SPEECH_LM_COMPLAINT"
					var lm_txt: String = _pick_custom_dialogue("lm_guide", _tr(lm_key))
					lm_v.show_speech(lm_txt, 2.6, Color("#FFC857"))
		"ServiceCompleted", "service_completed":
			var cid_c: String = str(payload.get("customer_id", ""))
			if not cid_c.is_empty():
				_customer_exit_reasons[cid_c] = "completed"
			var emp_c: String = str(payload.get("employee_id", ""))
			if _employee_views.has(emp_c):
				var ev_c: ActorView = _employee_views[emp_c] as ActorView
				if ev_c != null:
					ev_c.show_speech(_tr("WORLD_SPEECH_EMP_DONE"), 2.0, Color("#35C978"))
			if not allow_fx:
				return
			var st_id: String = str(payload.get("station_id", ""))
			var srv_done: String = str(payload.get("service_type", ""))
			var via_atm: bool = bool(payload.get("via_atm", false))
			var pos: Vector2 = iso_grid.grid_to_screen(Vector2i(2, 6) if via_atm else Vector2i(6, 4))
			if _station_views.has(st_id):
				pos = (_station_views[st_id] as ServiceStationView).position
			var fee_minor: int = int(payload.get("fee_minor", 0))
			var amount_minor: int = int(payload.get("amount_minor", 0))
			var display_val: int = fee_minor if fee_minor > 0 else amount_minor
			var text: String = ""
			var fx_col: Color = Color("#FFD166")
			if srv_done == "cash_deposit" and amount_minor > 0:
				var m_dep: String = FormatService.format_money_compact(amount_minor, "CNY", false)
				text = _tr("WORLD_FX_DEPOSIT_DONE", {"amount": m_dep})
				fx_col = Color("#2ECC71")
			elif srv_done == "cash_withdrawal" and amount_minor > 0:
				var m_wd: String = FormatService.format_money_compact(amount_minor, "CNY", false)
				text = _tr("WORLD_FX_WITHDRAW_DONE", {"amount": m_wd})
				fx_col = Color("#FF9F43")
			elif display_val > 0:
				var money_str: String = FormatService.format_money_compact(display_val, "CNY", true)
				text = _tr("WORLD_FX_SERVICE_DONE", {"amount": money_str})
				fx_col = Color("#FFD166")
			else:
				text = _tr("WORLD_FX_SATISFACTION_UP")
				fx_col = Color("#00C6FF")
			_spawn_floating_text(pos + Vector2(0.0, -34.0), text, fx_col)
		"CustomerLeftUnserved", "customer_left_unserved":
			var cid: String = str(payload.get("customer_id", ""))
			if not cid.is_empty():
				_customer_exit_reasons[cid] = "timeout"
			if not allow_fx:
				return
			var pos: Vector2 = iso_grid.grid_to_screen(ENTRANCE_CELL)
			if _customer_views.has(cid):
				pos = (_customer_views[cid] as ActorView).position
			_spawn_floating_text(pos + Vector2(0.0, -28.0), _tr("WORLD_FX_CUSTOMER_LEFT"), Color("#E74C3C"))
		"LoanApproved", "loan_approved":
			if allow_fx:
				var pos: Vector2 = iso_grid.grid_to_screen(Vector2i(11, 4))
				_spawn_floating_text(pos + Vector2(0.0, -34.0), _tr("WORLD_FX_LOAN_APPROVED"), Color("#35C978"))
		"LoanRejected", "loan_rejected":
			if allow_fx:
				var pos: Vector2 = iso_grid.grid_to_screen(Vector2i(11, 4))
				_spawn_floating_text(pos + Vector2(0.0, -34.0), _tr("WORLD_FX_LOAN_REJECTED"), Color("#E74C3C"))
		"DepartmentCreated", "DepartmentUpgraded", "department_created", "department_upgraded":
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
		"state_reloaded", "DailySettlementCompleted":
			_clear_leaving_customers()
			if cur_frame != _last_auto_world_frame:
				_last_auto_world_frame = cur_frame
				refresh_world()
		"DepartmentMoved", "LayoutChanged", "DepartmentDemolished", "EmployeeFired", "EmployeeAssigned", "employee_hired", "employee_fired", "employee_assigned", "station_toggled":
			if cur_frame != _last_auto_world_frame:
				_last_auto_world_frame = cur_frame
				refresh_world()


func _customer_arrival_speech_key(service_type: String) -> String:
	match service_type:
		"cash_withdrawal":
			return "WORLD_SPEECH_CUST_ENTER_WITHDRAW"
		"transfer":
			return "WORLD_SPEECH_CUST_ENTER_TRANSFER"
		"account_opening":
			return "WORLD_SPEECH_CUST_ENTER_ACCOUNT"
		"wealth_advisory":
			return "WORLD_SPEECH_CUST_ENTER_WEALTH"
		"personal_loan_application":
			return "WORLD_SPEECH_CUST_ENTER_LOAN"
		"business_meeting":
			return "WORLD_SPEECH_CUST_ENTER_MEETING"
		"complaint":
			return "WORLD_SPEECH_CUST_ENTER_COMPLAINT"
		_:
			return "WORLD_SPEECH_CUST_ENTER_DEPOSIT"


func _spawn_floating_text(world_pos: Vector2, text: String, color: Color) -> void:
	if _effects_layer == null:
		return
	var lbl := Label.new()
	lbl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	lbl.text = text
	lbl.position = (world_pos - Vector2(54.0, 10.0)).round()
	lbl.size = Vector2(108.0, 20.0)
	lbl.scale = Vector2(0.85, 0.85)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color("#081B36"))
	lbl.add_theme_constant_override("outline_size", 4)
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

	# Clean up leaving customers once they have walked out the entrance door
	if not _leaving_customer_views.is_empty():
		var lidx: int = _leaving_customer_views.size() - 1
		while lidx >= 0:
			var lv: ActorView = _leaving_customer_views[lidx]
			if lv == null or not is_instance_valid(lv):
				_leaving_customer_views.remove_at(lidx)
			elif not lv.is_walking():
				_leaving_customer_views.remove_at(lidx)
				if lv.get_parent() != null:
					lv.get_parent().remove_child(lv)
				lv.queue_free()
			lidx -= 1

	# Fire deferred counter dialogue bubbles ONLY once the customer has physically arrived at the counter
	if not _pending_counter_dialogue.is_empty():
		for cid_d: String in _pending_counter_dialogue.keys().duplicate():
			if not _customer_views.has(cid_d):
				_pending_counter_dialogue.erase(cid_d)
				continue
			var cv_d: ActorView = _customer_views[cid_d] as ActorView
			if cv_d == null:
				_pending_counter_dialogue.erase(cid_d)
				continue
			if not cv_d.is_walking():
				var info_d: Dictionary = _pending_counter_dialogue[cid_d] as Dictionary
				_pending_counter_dialogue.erase(cid_d)
				cv_d.show_speech(_tr(str(info_d.get("cust_key", "WORLD_SPEECH_CUST_SERVING"))), 2.4, Color("#00C6FF"))
				var eid_d: String = str(info_d.get("employee_id", ""))
				if _employee_views.has(eid_d):
					var ev_d: ActorView = _employee_views[eid_d] as ActorView
					if ev_d != null:
						ev_d.show_speech(_tr(str(info_d.get("emp_key", "WORLD_SPEECH_EMP_GREET"))), 2.5, Color("#FFC857"))

	# Ambient employee life: high-fatigue complaints & idle colleague chatting/slacking
	_ambient_chatter_timer += delta
	if _ambient_chatter_timer >= 4.5:
		_ambient_chatter_timer = 0.0
		_tick_ambient_employee_chatter()

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


func _tick_ambient_employee_chatter() -> void:
	var bs: Variant = _get_bank_state()
	if bs == null or not (bs is Object):
		return
	var bs_obj: Object = bs as Object
	var phase: int = int(bs_obj.get("day_phase"))
	if phase != Enums.DayPhase.OPEN:
		return
	var emps: Variant = bs_obj.get("employees")
	if not (emps is Dictionary) or (emps as Dictionary).is_empty():
		return
	var emp_dict: Dictionary = emps as Dictionary
	var eids: Array[String] = []
	for k: Variant in emp_dict.keys():
		eids.append(str(k))
	eids.sort()
	_ambient_chatter_seq += 1

	# 1. High-fatigue complaint takes priority
	for eid in eids:
		var ev_obj: Variant = emp_dict[eid]
		if not (ev_obj is Object):
			continue
		var fat: int = int((ev_obj as Object).get("fatigue"))
		var st: int = int((ev_obj as Object).get("state"))
		if (fat >= 65 or st == Enums.EmployeeState.OVERLOADED) and _employee_views.has(eid):
			var view: ActorView = _employee_views[eid] as ActorView
			if view != null and not view.has_active_speech():
				var tkey: String = "WORLD_SPEECH_EMP_TIRED_1" if (_ambient_chatter_seq % 2 == 0) else "WORLD_SPEECH_EMP_TIRED_2"
				view.show_speech(_pick_custom_dialogue("emp_tired", _tr(tkey)), 2.5, Color("#E74C3C"))
				return

	# 2. Idle & relaxed colleague chat / slacking
	var idle_eids: Array[String] = []
	for eid in eids:
		var ev_obj2: Variant = emp_dict[eid]
		if not (ev_obj2 is Object):
			continue
		var st2: int = int((ev_obj2 as Object).get("state"))
		var fat2: int = int((ev_obj2 as Object).get("fatigue"))
		if st2 == Enums.EmployeeState.AVAILABLE and fat2 < 50 and _employee_views.has(eid):
			var view2: ActorView = _employee_views[eid] as ActorView
			if view2 != null and not view2.has_active_speech():
				idle_eids.append(eid)
	if not idle_eids.is_empty():
		var pick_id: String = idle_eids[_ambient_chatter_seq % idle_eids.size()]
		var pick_view: ActorView = _employee_views[pick_id] as ActorView
		if pick_view != null:
			var skey: String = "WORLD_SPEECH_EMP_SLACK_1" if (_ambient_chatter_seq % 2 == 0) else "WORLD_SPEECH_EMP_SLACK_2"
			pick_view.show_speech(_pick_custom_dialogue("emp_slack", _tr(skey)), 2.4, Color("#9BB5D6"))


func _pick_custom_dialogue(category: String, fallback: String) -> String:
	var list: Array[Dictionary] = ContentStudioStoreScript.get_dialogues_for_category(category)
	if list.is_empty():
		return fallback
	var pick: Dictionary = list[_ambient_chatter_seq % list.size()]
	var txt: String = str(pick.get("text", "")).strip_edges()
	return txt if not txt.is_empty() else fallback


func show_test_dialogue(text: String, category: String = "") -> bool:
	if text.strip_edges().is_empty():
		return false
	if category.begins_with("cust_"):
		for cid_v: Variant in _customer_views.keys():
			var cv: ActorView = _customer_views[cid_v] as ActorView
			if cv != null:
				cv.show_speech(text, 3.8, Color("#56CCF2"))
				return true
	for eid_v: Variant in _employee_views.keys():
		var ev: ActorView = _employee_views[eid_v] as ActorView
		if ev != null:
			ev.show_speech(text, 3.8, Color("#FFC857"))
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if is_department_placement_active():
		if _handle_placement_input(event):
			return
	if _layout_mode_active:
		if _handle_layout_input(event):
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

	# Check lobby props (luxury decor, ATMs, plants, sofas, fountain, etc.) with generous hitbox + grid fallback
	var best_prop_id: String = ""
	var best_prop_y: float = -INF
	for pid: String in _prop_views.keys():
		var pv: Sprite2D = _prop_views[pid] as Sprite2D
		if pv != null and Rect2(-24.0, -36.0, 48.0, 48.0).has_point(world_pos - pv.position):
			if pv.position.y >= best_prop_y:
				best_prop_y = pv.position.y
				best_prop_id = pid

	var clicked_cell: Vector2i = iso_grid.screen_to_grid(world_pos)
	if best_prop_id.is_empty():
		var bs_pick: Variant = _get_bank_state()
		if bs_pick is Object:
			var raw_lp: Variant = (bs_pick as Object).get("lobby_props")
			if raw_lp is Dictionary:
				for pid_g: Variant in (raw_lp as Dictionary).keys():
					var pr_g: Variant = (raw_lp as Dictionary)[pid_g]
					if pr_g is Dictionary and (pr_g as Dictionary).get("grid_pos", null) == clicked_cell:
						best_prop_id = str(pid_g)
						break

	if not best_prop_id.is_empty():
		select_entity(&"prop", best_prop_id)
		return true

	# If click is inside the isometric grid floor but missed entities, clear selection
	if iso_grid.is_in_bounds(clicked_cell):
		select_entity(&"", "")
		return true

	return false


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _draw() -> void:
	# Deep Space Navy surrounding backdrop and orthogonal architectural podium beneath the 18x12 floor
	draw_rect(Rect2(-400.0, -300.0, 2200.0, 1600.0), Color("#081B36"), true)

	if iso_grid == null:
		return

	var tl: Vector2 = iso_grid.grid_to_screen(Vector2i(0, 0)) + Vector2(-IsoGrid.HALF_TILE_W, -IsoGrid.HALF_TILE_H)
	var br: Vector2 = iso_grid.grid_to_screen(Vector2i(IsoGrid.GRID_WIDTH - 1, IsoGrid.GRID_HEIGHT - 1)) + Vector2(IsoGrid.HALF_TILE_W, IsoGrid.HALF_TILE_H)
	var lobby_w: float = br.x - tl.x
	var lobby_h: float = br.y - tl.y

	# Orthogonal architectural foundation slab below the south cutaway edge
	draw_rect(Rect2(tl.x - 2.0, br.y, lobby_w + 4.0, 12.0), Color("#0B2D5B"), true)
	draw_rect(Rect2(tl.x - 2.0, br.y + 10.0, lobby_w + 4.0, 2.0), Color("#051226"), true)

	# Outer rim border around the lobby footprint
	draw_rect(Rect2(tl.x - 1.0, tl.y - 1.0, lobby_w + 2.0, lobby_h + 2.0), Color("#263D5C"), false, 1.5)
	draw_line(Vector2(tl.x, br.y), Vector2(br.x, br.y), Color("#1F6FEB"), 2.0)

	# Glowing Starway entrance threshold strip at x = 7..10 on the south edge
	var ent_left: float = iso_grid.grid_to_screen(Vector2i(7, IsoGrid.GRID_HEIGHT - 1)).x - IsoGrid.HALF_TILE_W
	var ent_right: float = iso_grid.grid_to_screen(Vector2i(10, IsoGrid.GRID_HEIGHT - 1)).x + IsoGrid.HALF_TILE_W
	draw_rect(Rect2(ent_left, br.y - 1.0, ent_right - ent_left, 4.0), Color("#00C6FF"), true)

	# Subtle cyan architectural grid overlay in Layout Mode, or warning RED in Delete Mode
	if _layout_mode_active:
		var grid_col := Color(0.95, 0.25, 0.25, 0.36) if _layout_delete_mode else Color(0.0, 0.776, 1.0, 0.28)
		for gx in range(IsoGrid.GRID_WIDTH + 1):
			var lx: float = tl.x + float(gx) * float(IsoGrid.TILE_WIDTH)
			draw_line(Vector2(lx, tl.y), Vector2(lx, br.y), grid_col, 1.0)
		for gy in range(IsoGrid.GRID_HEIGHT + 1):
			var ly: float = tl.y + float(gy) * float(IsoGrid.TILE_HEIGHT)
			draw_line(Vector2(tl.x, ly), Vector2(br.x, ly), grid_col, 1.0)


# ---------------------------------------------------------------------------
# Kairosoft-style Build / Layout Rearrange Mode (Stations, Props, Departments)
# ---------------------------------------------------------------------------

func is_layout_mode_active() -> bool:
	return _layout_mode_active


func set_layout_mode(active: bool) -> void:
	if active and is_department_placement_active():
		cancel_department_placement()
	_layout_mode_active = active
	_layout_delete_mode = false
	if not active:
		_clear_layout_held()
	queue_redraw()
	layout_mode_changed.emit(_layout_mode_active)


func begin_delete_mode() -> void:
	set_layout_mode(true)
	_clear_layout_held()
	_layout_delete_mode = true
	queue_redraw()


func begin_move_department(dept_id: String) -> void:
	if dept_id.is_empty():
		return
	var bs: Variant = _get_bank_state()
	if not (bs is Object):
		return
	var depts: Variant = (bs as Object).get("departments")
	if not (depts is Dictionary) or not (depts as Dictionary).has(dept_id):
		return
	var cur_rect: Rect2i = _read_dept_rect((depts as Dictionary)[dept_id])
	set_layout_mode(true)
	if _camera != null and _camera.get_zoom_step() > 1:
		_camera.set_zoom_step(1)
	_layout_held_kind = &"department"
	_layout_held_id = dept_id
	_layout_held_size = cur_rect.size if cur_rect.size.x > 0 else Vector2i(3, 3)
	_layout_hover_cell = cur_rect.position
	_update_layout_ghost()


func begin_build_item(item_type: String) -> void:
	var catalog: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
	if not catalog.has(item_type):
		return
	var spec: Dictionary = catalog[item_type] as Dictionary
	var kind_str: String = str(spec.get("kind", "prop"))
	set_layout_mode(true)
	_layout_held_kind = &"build_station" if kind_str == "station" else &"build_prop"
	_layout_held_id = item_type
	_layout_held_size = Vector2i.ONE
	_layout_hover_cell = Vector2i(8, 5)
	_update_layout_ghost()


func _clear_layout_held() -> void:
	_layout_held_kind = &""
	_layout_held_id = ""
	_layout_held_size = Vector2i.ONE
	if _layout_ghost != null and is_instance_valid(_layout_ghost):
		for ch in _layout_ghost.get_children():
			_layout_ghost.remove_child(ch)
			ch.queue_free()
		_layout_ghost.visible = false


func _ensure_layout_ghost() -> void:
	if _layout_ghost != null and is_instance_valid(_layout_ghost):
		return
	if _ysort_layer == null:
		return
	_layout_ghost = Node2D.new()
	_layout_ghost.name = "LayoutMoveGhost"
	_layout_ghost.z_index = 110
	_layout_ghost.visible = false
	_ysort_layer.add_child(_layout_ghost)


func _is_valid_layout_target(cell: Vector2i) -> bool:
	if iso_grid == null:
		return false
	if _layout_held_kind == &"department":
		var rect := Rect2i(cell, _layout_held_size)
		if not iso_grid.is_in_bounds(rect.position) or not iso_grid.is_in_bounds(rect.end - Vector2i.ONE):
			return false
		# Must not overlap lobby or other departments, and must touch built area
		if LOBBY_RECT.intersects(rect):
			return false
		var bs: Variant = _get_bank_state()
		if bs is Object:
			var depts: Variant = (bs as Object).get("departments")
			if depts is Dictionary:
				for did_v: Variant in (depts as Dictionary).keys():
					if str(did_v) == _layout_held_id:
						continue
					var other_r: Rect2i = _read_dept_rect((depts as Dictionary)[did_v])
					if other_r.size.x > 0 and other_r.intersects(rect):
						return false
		var counts: Dictionary = _built_neighbours(rect)
		for side: Variant in counts.keys():
			if int(counts[side]) > 0:
				return true
		return false
	elif _layout_held_kind == &"station" or _layout_held_kind == &"build_station":
		return cell.x >= 1 and cell.x <= 16 and cell.y >= 2 and cell.y <= 10
	elif _layout_held_kind == &"prop" or _layout_held_kind == &"build_prop":
		return cell.x >= 1 and cell.x <= 16 and cell.y >= 1 and cell.y <= 10
	return false


func _update_layout_ghost() -> void:
	_ensure_layout_ghost()
	if _layout_ghost == null or _layout_held_id.is_empty():
		return
	for ch in _layout_ghost.get_children():
		_layout_ghost.remove_child(ch)
		ch.queue_free()
	var valid: bool = _is_valid_layout_target(_layout_hover_cell)
	var col: Color = Color("#35C978") if valid else Color("#E74C3C")
	var w: int = _layout_held_size.x
	var h: int = _layout_held_size.y
	for dy in range(h):
		for dx in range(w):
			var c := _layout_hover_cell + Vector2i(dx, dy)
			var p := Polygon2D.new()
			p.polygon = PackedVector2Array([
				Vector2(-16.0, -10.0), Vector2(16.0, -10.0), Vector2(16.0, 10.0), Vector2(-16.0, 10.0),
			])
			p.color = Color(col.r, col.g, col.b, 0.36)
			p.position = iso_grid.grid_to_screen(c).round()
			_layout_ghost.add_child(p)
			var outline := Line2D.new()
			outline.points = PackedVector2Array([
				Vector2(-16.0, -10.0), Vector2(16.0, -10.0), Vector2(16.0, 10.0), Vector2(-16.0, 10.0), Vector2(-16.0, -10.0),
			])
			outline.width = 1.5
			outline.default_color = Color(col.r, col.g, col.b, 0.85)
			outline.position = p.position
			_layout_ghost.add_child(outline)

	# Virtual sprite preview on top of the green/red footprint so the player sees the real item
	var tint := Color(0.75, 1.0, 0.85, 0.78) if valid else Color(1.0, 0.55, 0.55, 0.72)
	if _layout_held_kind == &"department":
		var tex_wall: Texture2D = _load_tex("res://assets/environment/wall_section_back.png")
		var tex_desk: Texture2D = _load_tex("res://assets/environment/prop_desk_office.png")
		for dx in range(w):
			var wn := Sprite2D.new()
			wn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			wn.texture = tex_wall
			wn.centered = true
			wn.offset = Vector2(0.0, -34.0)
			wn.modulate = tint
			wn.position = iso_grid.grid_to_screen(_layout_hover_cell + Vector2i(dx, 0)).round()
			_layout_ghost.add_child(wn)
		var dspr := Sprite2D.new()
		dspr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		dspr.texture = tex_desk
		dspr.centered = true
		dspr.offset = Vector2(0.0, -9.0)
		dspr.modulate = tint
		dspr.position = iso_grid.grid_to_screen(_layout_hover_cell + Vector2i(w / 2, h / 2)).round()
		_layout_ghost.add_child(dspr)
	else:
		var preview_info: Dictionary = _resolve_layout_preview_sprite(_layout_held_kind, _layout_held_id)
		var tex_path: String = str(preview_info.get("tex_path", ""))
		if not tex_path.is_empty():
			var spr := Sprite2D.new()
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.texture = _load_tex(tex_path)
			spr.centered = true
			spr.hframes = int(preview_info.get("hframes", 1))
			spr.vframes = 1
			spr.offset = preview_info.get("offset", Vector2(0.0, -10.0)) as Vector2
			spr.modulate = tint
			spr.position = iso_grid.grid_to_screen(_layout_hover_cell).round()
			_layout_ghost.add_child(spr)

	_layout_ghost.visible = true


func _resolve_layout_preview_sprite(kind: StringName, item_id: String) -> Dictionary:
	var eff_catalog: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
	if kind == &"build_station" or kind == &"build_prop":
		if eff_catalog.has(item_id):
			var spec: Dictionary = eff_catalog[item_id] as Dictionary
			return {
				"tex_path": str(spec.get("tex_path", spec.get("texture", ""))),
				"offset": spec.get("offset", Vector2(0.0, -10.0)),
				"hframes": 1,
			}
	elif kind == &"station":
		var is_loan: bool = item_id.begins_with("loan")
		return {
			"tex_path": "res://assets/environment/prop_desk_loan.png" if is_loan else "res://assets/environment/prop_counter_teller.png",
			"offset": Vector2(0.0, -8.0) if is_loan else Vector2(0.0, -10.0),
			"hframes": 1,
		}
	elif kind == &"prop":
		var bs: Variant = _get_bank_state()
		var ptype: String = "plant"
		if bs is Object:
			var raw_p: Variant = (bs as Object).get("lobby_props")
			if raw_p is Dictionary and (raw_p as Dictionary).has(item_id):
				ptype = str(((raw_p as Dictionary)[item_id] as Dictionary).get("prop_type", "plant"))
		if ptype == "fountain":
			return {"tex_path": "res://assets/environment/prop_fountain_sheet.png", "offset": Vector2(0.0, -14.0), "hframes": 4}
		if ptype == "queue_post":
			return {"tex_path": "res://assets/environment/prop_queue_post.png", "offset": Vector2(0.0, -8.0), "hframes": 1}
		if eff_catalog.has(ptype):
			var spec2: Dictionary = eff_catalog[ptype] as Dictionary
			return {
				"tex_path": str(spec2.get("tex_path", spec2.get("texture", ""))),
				"offset": spec2.get("offset", Vector2(0.0, -10.0)),
				"hframes": 1,
			}
	return {}


func _update_delete_hover_ghost(world_pos: Vector2, cell: Vector2i) -> void:
	_ensure_layout_ghost()
	if _layout_ghost == null:
		return
	for ch in _layout_ghost.get_children():
		_layout_ghost.remove_child(ch)
		ch.queue_free()

	var target_rect := Rect2i()
	for sid: String in _station_views.keys():
		var sv: ServiceStationView = _station_views[sid] as ServiceStationView
		if sv != null and sv.get_hit_rect().has_point(world_pos - sv.position):
			target_rect = Rect2i(sv.grid_pos, Vector2i.ONE)
			break
	if target_rect.size.x == 0:
		for pid: String in _prop_views.keys():
			var pv: Sprite2D = _prop_views[pid] as Sprite2D
			if pv != null and Rect2(-18.0, -28.0, 36.0, 36.0).has_point(world_pos - pv.position):
				target_rect = Rect2i(iso_grid.screen_to_grid(pv.position), Vector2i.ONE)
				break
	if target_rect.size.x == 0:
		for did: String in _dept_nodes.keys():
			var dinfo: Dictionary = _dept_nodes[did] as Dictionary
			var drect: Rect2i = dinfo.get("rect", Rect2i()) as Rect2i
			if drect.size.x > 0 and drect.has_point(cell):
				target_rect = drect
				break

	if target_rect.size.x <= 0:
		_layout_ghost.visible = false
		return

	var col := Color("#FF3B30")
	for dy in range(target_rect.size.y):
		for dx in range(target_rect.size.x):
			var c := target_rect.position + Vector2i(dx, dy)
			var center_p: Vector2 = iso_grid.grid_to_screen(c).round()
			var p := Polygon2D.new()
			p.polygon = PackedVector2Array([
				Vector2(-16.0, -10.0), Vector2(16.0, -10.0), Vector2(16.0, 10.0), Vector2(-16.0, 10.0),
			])
			p.color = Color(col.r, col.g, col.b, 0.48)
			p.position = center_p
			_layout_ghost.add_child(p)
			var outline := Line2D.new()
			outline.points = PackedVector2Array([
				Vector2(-16.0, -10.0), Vector2(16.0, -10.0), Vector2(16.0, 10.0), Vector2(-16.0, 10.0), Vector2(-16.0, -10.0),
			])
			outline.width = 2.0
			outline.default_color = col
			outline.position = center_p
			_layout_ghost.add_child(outline)
	# Draw a crisp red X across the center tile to unmistakably signal Delete
	var mid_p: Vector2 = iso_grid.grid_to_screen(target_rect.position + target_rect.size / 2).round()
	var x1 := Line2D.new()
	x1.points = PackedVector2Array([Vector2(-9.0, -7.0), Vector2(9.0, 7.0)])
	x1.width = 2.5
	x1.default_color = Color("#FFE5E5")
	x1.position = mid_p
	_layout_ghost.add_child(x1)
	var x2 := Line2D.new()
	x2.points = PackedVector2Array([Vector2(9.0, -7.0), Vector2(-9.0, 7.0)])
	x2.width = 2.5
	x2.default_color = Color("#FFE5E5")
	x2.position = mid_p
	_layout_ghost.add_child(x2)
	_layout_ghost.visible = true


func _handle_layout_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		if not _layout_held_id.is_empty():
			_clear_layout_held()
		else:
			set_layout_mode(false)
		_consume_input()
		return true
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var cell: Vector2i = cell_from_screen_position(mm.position)
		if _layout_delete_mode:
			var wpos: Vector2 = get_global_transform_with_canvas().affine_inverse() * mm.position
			_update_delete_hover_ghost(wpos, cell)
		elif not _layout_held_id.is_empty() and cell != _layout_hover_cell:
			_layout_hover_cell = cell
			_update_layout_ghost()
		return false
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return false
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if not _layout_held_id.is_empty():
				_clear_layout_held()
			elif _layout_delete_mode:
				_layout_delete_mode = false
				queue_redraw()
			else:
				set_layout_mode(false)
			_consume_input()
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var world_pos: Vector2 = get_global_transform_with_canvas().affine_inverse() * mb.position
			var cell: Vector2i = iso_grid.screen_to_grid(world_pos)
			if _layout_delete_mode:
				for sid: String in _station_views.keys():
					var sv: ServiceStationView = _station_views[sid] as ServiceStationView
					if sv != null and sv.get_hit_rect().has_point(world_pos - sv.position):
						layout_delete_requested.emit(&"station", sid)
						_consume_input()
						return true
				for pid: String in _prop_views.keys():
					var pv: Sprite2D = _prop_views[pid] as Sprite2D
					if pv != null and Rect2(-18.0, -28.0, 36.0, 36.0).has_point(world_pos - pv.position):
						layout_delete_requested.emit(&"prop", pid)
						_consume_input()
						return true
				for did: String in _dept_nodes.keys():
					var dinfo: Dictionary = _dept_nodes[did] as Dictionary
					var drect: Rect2i = dinfo.get("rect", Rect2i()) as Rect2i
					if drect.size.x > 0 and drect.has_point(cell):
						layout_delete_requested.emit(&"department", did)
						_consume_input()
						return true
				_consume_input()
				return true
			if _layout_held_id.is_empty():
				# Pick up station, prop, or department room under cursor
				for sid: String in _station_views.keys():
					var sv: ServiceStationView = _station_views[sid] as ServiceStationView
					if sv != null and sv.get_hit_rect().has_point(world_pos - sv.position):
						_layout_held_kind = &"station"
						_layout_held_id = sid
						_layout_held_size = Vector2i.ONE
						_layout_hover_cell = cell
						_update_layout_ghost()
						_consume_input()
						return true
				for pid: String in _prop_views.keys():
					var pv: Sprite2D = _prop_views[pid] as Sprite2D
					if pv != null and Rect2(-18.0, -28.0, 36.0, 36.0).has_point(world_pos - pv.position):
						_layout_held_kind = &"prop"
						_layout_held_id = pid
						_layout_held_size = Vector2i.ONE
						_layout_hover_cell = cell
						_update_layout_ghost()
						_consume_input()
						return true
				for did: String in _dept_nodes.keys():
					var dinfo: Dictionary = _dept_nodes[did] as Dictionary
					var drect: Rect2i = dinfo.get("rect", Rect2i()) as Rect2i
					if drect.size.x > 0 and drect.has_point(cell):
						begin_move_department(did)
						_consume_input()
						return true
			else:
				# Place currently held item (either relocate existing or build new catalog item)
				if _is_valid_layout_target(cell):
					var k: StringName = _layout_held_kind
					var iid: String = _layout_held_id
					if k == &"build_station" or k == &"build_prop":
						layout_build_requested.emit(iid, cell)
					else:
						_clear_layout_held()
						layout_move_requested.emit(k, iid, cell)
					_consume_input()
					return true
			return true
	return false
