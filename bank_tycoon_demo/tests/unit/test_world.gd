extends SceneTree

## Headless unit test suite for Milestone M5 (2.5D Isometric Bank Lobby World presentation layer).

static var _total: int = 0
static var _passed: int = 0
static var _failed: int = 0
static var _errors: Array[String] = []


class MockSimHost extends Node:
	signal snapshot_changed()
	var bank_state: BankState = null
	var event_bus: Variant = null


func _initialize() -> void:
	var summary: Dictionary = run_all()
	var passed_count: int = int(summary.get("passed", 0))
	var failed_count: int = int(summary.get("failed", 0))
	var total_count: int = int(summary.get("total", 0))
	print("[M5_WORLD_UNIT] Summary: %d/%d passed, %d failed" % [passed_count, total_count, failed_count])
	quit(0 if (failed_count == 0 and total_count > 0) else 1)


static func _check(cond: bool, msg: String) -> void:
	_total += 1
	if cond:
		_passed += 1
	else:
		_failed += 1
		_errors.append(msg)
		print("[M5_WORLD_UNIT] FAIL: %s" % msg)


static func _check_eq(actual: Variant, expected: Variant, msg: String) -> void:
	_total += 1
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		var detail: String = "%s (expected=%s, actual=%s)" % [msg, str(expected), str(actual)]
		_errors.append(detail)
		print("[M5_WORLD_UNIT] FAIL: %s" % detail)


static func _run_case(name: String, fn: Callable) -> void:
	var fail_before: int = _failed
	fn.call()
	if _failed == fail_before:
		print("[M5_WORLD_UNIT] PASS: %s" % name)


static func run_all() -> Dictionary:
	_total = 0
	_passed = 0
	_failed = 0
	_errors.clear()

	_run_case("iso_grid_dimensions_and_coordinate_roundtrip", _test_iso_grid_coords)
	_run_case("iso_grid_pathfinding_oob_and_surrounded_boundaries", _test_iso_grid_navigation)
	_run_case("pixel_camera_2d_integer_zoom_and_rounding", _test_pixel_camera)
	_run_case("service_station_and_actor_views", _test_station_and_actor_views)
	_run_case("bank_world_scene_nearest_ysort_runtime_and_selection", _test_bank_world_scene)

	return {
		"total": _total,
		"passed": _passed,
		"failed": _failed,
		"errors": _errors.duplicate(),
	}


static func _test_iso_grid_coords() -> void:
	var grid := IsoGrid.new()
	_check_eq(IsoGrid.GRID_WIDTH, 18, "IsoGrid width must be 18")
	_check_eq(IsoGrid.GRID_HEIGHT, 12, "IsoGrid height must be 12")
	_check_eq(IsoGrid.TILE_WIDTH, 32, "IsoGrid tile width must be 32")
	_check_eq(IsoGrid.TILE_HEIGHT, 20, "IsoGrid tile height must be 20")

	for y in range(IsoGrid.GRID_HEIGHT):
		for x in range(IsoGrid.GRID_WIDTH):
			var c := Vector2i(x, y)
			_check(grid.is_in_bounds(c), "Cell (%d,%d) in bounds" % [x, y])
			var screen_pos: Vector2 = grid.grid_to_screen(c)
			var back: Vector2i = grid.screen_to_grid(screen_pos)
			_check_eq(back, c, "Roundtrip grid_to_screen -> screen_to_grid for (%d,%d)" % [x, y])

	# The lobby is 18x12, but the buildable site extends by SITE_MARGIN so departments
	# can be constructed outside the current floor plan.
	_check(grid.is_in_bounds(Vector2i(-1, 0)), "(-1,0) inside the buildable site")
	_check(grid.is_in_bounds(Vector2i(0, -1)), "(0,-1) inside the buildable site")
	_check(grid.is_in_bounds(Vector2i(18, 0)), "(18,0) inside the buildable site")
	_check(grid.is_in_bounds(Vector2i(0, 12)), "(0,12) inside the buildable site")
	var margin: int = IsoGrid.SITE_MARGIN
	_check(not grid.is_in_bounds(Vector2i(-margin - 1, 0)), "Beyond west margin is out of bounds")
	_check(not grid.is_in_bounds(Vector2i(IsoGrid.GRID_WIDTH + margin, 0)), "Beyond east margin is out of bounds")
	_check(not grid.is_in_bounds(Vector2i(0, IsoGrid.GRID_HEIGHT + margin)), "Beyond south margin is out of bounds")


static func _test_iso_grid_navigation() -> void:
	var grid := IsoGrid.new()
	var path: Array[Vector2i] = grid.find_path(Vector2i(1, 1), Vector2i(4, 3))
	_check(path.size() >= 6, "Manhattan path from (1,1) to (4,3) has >= 6 points")
	_check_eq(path[0], Vector2i(1, 1), "Path starts at (1,1)")
	_check_eq(path[path.size() - 1], Vector2i(4, 3), "Path ends at (4,3)")

	for i in range(1, path.size()):
		var diff: Vector2i = path[i] - path[i - 1]
		var manhattan: int = absi(diff.x) + absi(diff.y)
		_check_eq(manhattan, 1, "Step %d is strictly 4-directional (no diagonals)" % i)

	# Paths may enter the expansion margin (free land until a room is built there).
	var expand_path: Array[Vector2i] = grid.find_path(Vector2i(1, 1), Vector2i(-1, -1))
	_check(not expand_path.is_empty(), "Path into the expansion margin exists")

	# Out-of-bounds checks (outside the whole site, not just the lobby)
	for mname in ["find_path", "compute_path", "get_grid_path"]:
		var oob1: Array[Vector2i] = grid.call(mname, Vector2i(1, 1), Vector2i(-7, -7))
		_check(oob1.is_empty(), "%s OOB (-7,-7) returns empty array" % mname)
		var oob2: Array[Vector2i] = grid.call(mname, Vector2i(1, 1), Vector2i(24, 18))
		_check(oob2.is_empty(), "%s OOB (24,18) returns empty array" % mname)
		var oob3: Array[Vector2i] = grid.call(mname, Vector2i(-7, 0), Vector2i(2, 2))
		_check(oob3.is_empty(), "%s OOB start (-7,0) returns empty array" % mname)

	# Surrounded target cell (5,5)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if not (dx == 0 and dy == 0):
				grid.set_solid(Vector2i(5 + dx, 5 + dy), true)
	_check(grid.is_solid(Vector2i(4, 5)), "Neighbor (4,5) marked solid")
	_check(not grid.is_solid(Vector2i(5, 5)), "Center (5,5) itself is not solid")
	var blocked_path: Array[Vector2i] = grid.find_path(Vector2i(1, 1), Vector2i(5, 5))
	_check(blocked_path.is_empty(), "Surrounded cell (5,5) must return empty path")

	# Direct solid destination
	grid.set_cell_solid(Vector2i(2, 2), true)
	var solid_dest: Array[Vector2i] = grid.compute_path(Vector2i(1, 1), Vector2i(2, 2))
	_check(solid_dest.is_empty(), "Solid destination cell (2,2) returns empty path")


static func _test_pixel_camera() -> void:
	var cam := PixelCamera2D.new()
	_check_eq(cam.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "PixelCamera2D uses TEXTURE_FILTER_NEAREST")
	_check_eq(cam.zoom, Vector2(2.0, 2.0), "Default PixelCamera2D zoom is 2x")

	for step in [1, 2, 3]:
		cam.set_zoom_step(step)
		_check_eq(cam.zoom, Vector2(float(step), float(step)), "Valid zoom step %d" % step)

	for bad_step in [0, -5, 4, 99]:
		cam.set_zoom_step(bad_step)
		_check(cam.zoom.x >= 1.0 and cam.zoom.x <= 3.0, "Zoom clamped in [1,3] for %d" % bad_step)
		_check_eq(cam.zoom.x, float(int(cam.zoom.x)), "Zoom strictly integer for %d" % bad_step)
		_check_eq(cam.zoom.x, cam.zoom.y, "Zoom X == Y for %d" % bad_step)

	cam.focus_world_position(Vector2(512.7, 333.2))
	_check_eq(cam.position, Vector2(513.0, 333.0), "focus_world_position rounds to integer pixels")
	cam.free()


static func _test_station_and_actor_views() -> void:
	var st_view := ServiceStationView.new()
	st_view.configure({
		"station_id": "teller_1",
		"station_type": "teller",
		"is_open": true,
		"assigned_employee_id": "emp_0001",
		"grid_pos": Vector2i(4, 4),
	}, Vector2(500.4, 294.2), 1)
	_check_eq(st_view.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "ServiceStationView uses NEAREST filter")
	_check_eq(st_view.position, Vector2(500.0, 294.0), "ServiceStationView rounds position")
	st_view.set_selected(true)
	_check(st_view.is_selected, "ServiceStationView selection state updated")
	st_view.free()

	var bs: BankState = BankState.create_starter_branch("ActorTest", 20261121)
	var emp_ids: Array = bs.employees.keys()
	_check(emp_ids.size() >= 2, "Starter branch has >= 2 employees")
	var first_emp: EmployeeInstance = bs.employees[emp_ids[0]] as EmployeeInstance

	var act_view := ActorView.new()
	act_view.configure_employee(first_emp, Vector2(480.0, 260.0))
	_check_eq(act_view.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "ActorView uses NEAREST filter")
	_check_eq(act_view.actor_kind, &"employee", "ActorView configured as employee")
	act_view.set_screen_path([Vector2(496.0, 268.0), Vector2(512.0, 276.0)])
	act_view._process(0.1)
	act_view.free()


static func _test_bank_world_scene() -> void:
	var packed: PackedScene = load("res://scenes/world/bank_world.tscn") as PackedScene
	_check(packed != null, "bank_world.tscn loads as PackedScene")
	if packed == null:
		return

	var world: BankWorld = packed.instantiate() as BankWorld
	_check(world != null, "bank_world.tscn instantiates as BankWorld")
	if world == null:
		return

	world._ready()
	_check_eq(world.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "BankWorld root uses TEXTURE_FILTER_NEAREST")
	_check(world.has_signal("entity_selected"), "BankWorld has entity_selected signal")
	_check(world.has_method("bind_runtime"), "BankWorld has bind_runtime")
	_check(world.has_method("focus_entity"), "BankWorld has focus_entity")
	_check(world.has_method("select_entity"), "BankWorld has select_entity")
	_check(world.has_method("set_camera_zoom_step"), "BankWorld has set_camera_zoom_step")

	var ysort: Node2D = world.get_node_or_null("YSortedLayer") as Node2D
	_check(ysort != null and ysort.y_sort_enabled, "BankWorld YSortedLayer has y_sort_enabled = true")

	var cam: Camera2D = world.get_node_or_null("Camera2D") as Camera2D
	_check(cam != null, "BankWorld contains Camera2D")

	var mock_host := MockSimHost.new()
	var bs: BankState = BankState.create_starter_branch("Starway Unit", 20261121)
	bs.departments["core:department.operations"] = {
		"id": "core:department.operations",
		"level": 2,
		"created_day": 1,
		"daily_cost_minor": 5000,
		"staff_ids": [],
	}
	var cust := CustomerInstance.new()
	cust.id = "cust_0001"
	cust.customer_type = "vip"
	cust.avatar_id = "cust_vip"
	cust.state = Enums.CustomerState.WAITING
	cust.patience_max = 40
	cust.patience_remaining = 30
	bs.active_customers[cust.id] = cust

	mock_host.bank_state = bs
	world.bind_runtime(mock_host)

	# Verify camera zoom steps
	for step in [1, 2, 3]:
		world.set_camera_zoom_step(step)
		_check_eq(cam.zoom, Vector2(float(step), float(step)), "BankWorld zoom step %d" % step)
	for bad_step in [0, -3, 5]:
		world.set_camera_zoom_step(bad_step)
		_check(cam.zoom.x >= 1.0 and cam.zoom.x <= 3.0, "BankWorld invalid zoom step %d clamped" % bad_step)

	# Verify selection & signal emission
	var events: Array[Dictionary] = []
	world.entity_selected.connect(func(etype: StringName, eid: String) -> void:
		events.append({"type": etype, "id": eid})
	)

	world.focus_entity(&"station", "teller_1")
	_check_eq(events.size(), 1, "focus_entity on valid station emits entity_selected")
	if not events.is_empty():
		_check_eq(events[0]["type"], &"station", "Emitted type is station")
		_check_eq(events[0]["id"], "teller_1", "Emitted id is teller_1")

	# Unknown entity must be ignored without crash or spurious emission
	world.focus_entity(&"employee", "nonexistent_999")
	world.focus_entity(&"unknown_type", "1")
	_check_eq(events.size(), 1, "Unknown entity focus does not emit spurious selection")

	# Clear selection
	world.focus_entity(&"", "")
	_check_eq(events.size(), 2, "Empty focus_entity emits cleared selection")
	_check_eq(events[1]["id"], "", "Cleared selection has empty id")

	# Domain event floating effect & fountain animation tick
	world._on_domain_event(&"service_completed", {
		"station_id": "teller_1",
		"amount_minor": 150000,
		"fee_minor": 1500,
	})
	world._process(0.25)

	world.free()
	mock_host.free()
