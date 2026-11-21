extends RefCounted

## Tier 5 E2E Suite — HUD Input Hit-Testing Regression ("HUD 顶部按钮点不动").
##
## Defect under regression
## ----------------------
## `HUDLayer/ModalContainer` and `HUDLayer/DrawerContainer` are full-screen `Control`
## nodes configured with `mouse_filter = MOUSE_FILTER_PASS`. A PASS control does NOT let
## the event fall through to a *sibling* control: Godot picks the topmost non-IGNORE
## control under the cursor and only bubbles the event up that control's PARENT chain.
## Therefore a full-screen PASS container behaves exactly like a click black hole for
## every sibling drawn below it — the whole HUD (TopBar / LeftNavigation / BottomBar /
## DrawerContainer content) became unclickable and the world area swallowed clicks.
##
## How these cases are driven
## --------------------------
## Every interaction is a REAL mouse event pair (`InputEventMouseMotion`,
## `InputEventMouseButton` press + release) pushed through `Viewport.push_input(ev, true)`
## — never a direct method call, never `signal.emit()`. Assertions only look at
## observable behaviour: `get_snapshot()` state, node visibility, and
## `gui_get_hovered_control()` (who actually received the pointer).
##
## Async rationale
## ---------------
## Container layout in Godot is deferred (`Container.queue_sort()` goes through the
## MessageQueue, flushed after `process_frame`). The synchronous Tier 1-4 runner cannot
## observe correct button rects on the very frame the scene is mounted, so this suite is
## driven frame-by-frame (`await SceneTree.process_frame`) and reports back through a
## completion callback. Tier 1-4 stay 100% synchronous and untouched.
##
## Case bodies stay independent: each one re-establishes its own preconditions through
## `_reset_ui_state()` so no case depends on the ordering of its neighbours.

const TIER: int = 5
const GAME_ROOT_SCENE: String = "res://scenes/gameplay/game_root.tscn"

## Minimum frames to settle. `process_frame` is emitted BEFORE the MessageQueue flush of
## the same frame, so a single await can still observe pre-sort rects. Two awaits
## guarantees at least one full sort/flush boundary has completed.
const SETTLE_FRAMES: int = 2

## Verifying that these cases are NOT vacuously green
## --------------------------------------------------
## These cases were validated against the real defect (not only against a green run):
## re-creating the pre-fix state — `mouse_filter = 1` / PASS on `HUDLayer/ModalContainer`
## and `HUDLayer/DrawerContainer` — makes all 8 cases fail with explicit
## `actual=ModalContainer` hit-test evidence, e.g.
##   E2E_T5_01: 实际命中 /root/GameRoot/HUDLayer/ModalContainer ... (expected=2, actual=1)
## Reproduce it by reverting the scene, then run the suite. This is intentionally NOT
## kept as a runtime switch: a switch that turns the whole tier red is a CI hazard.

var _h: RefCounted = null
var _tree: SceneTree = null
var _root: Window = null
var _game: Control = null
var _sim_host: Node = null

var _top_bar: Control = null
var _left_nav: Control = null
var _bottom_bar: Control = null
var _drawer_container: Control = null
var _modal_container: Control = null
var _loan_modal: Control = null
var _event_modal: Control = null
var _pause_modal: Control = null

var _results: Array = []
var _current_id: String = ""
var _setup_error: String = ""
var _last_click_pos: Vector2 = Vector2.ZERO
var _last_hovered: Control = null


## Entry point used by `run_e2e_tests.start_tier5_async()`. Fire-and-forget coroutine:
## results are delivered through `on_complete` (Array of harness-shaped dictionaries).
func run_suite_async(harness: RefCounted, on_complete: Callable) -> void:
	_h = harness
	_tree = harness.get("root_tree") as SceneTree
	if _tree != null:
		_root = _tree.root
	_results.clear()

	await _setup()
	if _setup_error != "":
		_begin_case("E2E_T5_00_SETUP")
		_h.fail_test("Tier 5 setup failed: %s" % _setup_error)
		_end_case()
		await _teardown()
		_h.call("_cleanup_per_test")
		on_complete.call(_results)
		return

	await _case_01_topbar_speed_buttons()
	await _case_02_topbar_day_action()
	await _case_03_topbar_settings_modal()
	await _case_04_left_nav_drawer_toggle()
	await _case_05_bottom_bar_modals()
	await _case_06_drawer_inner_button()
	await _case_07_interceptor_guard()
	await _case_08_structural_transparency_guard()
	await _case_09_dynamic_list_single_click()
	await _case_10_department_placement()
	await _case_11_world_click_reaches_entity()
	await _case_12_world_wheel_zoom()

	await _teardown()
	on_complete.call(_results)


# ---------------------------------------------------------------------------
# Mount / teardown
# ---------------------------------------------------------------------------

func _setup() -> void:
	_setup_error = ""
	if _tree == null or _root == null:
		_setup_error = "SceneTree/root unavailable"
		return

	var sess: Node = _h.call("get_autoload", "GameSession")
	if sess == null:
		_setup_error = "GameSession autoload missing"
		return
	if not sess.has_method("start_new_game"):
		_setup_error = "GameSession.start_new_game missing"
		return

	# Deterministic world: seed the exact same starter branch GameRoot falls back to,
	# so this suite is independent of whatever state Tier 1-4 left in the session.
	sess.set("bank_state", BankState.create_starter_branch("T5 Regression Bank", 20261121))

	var packed: PackedScene = load(GAME_ROOT_SCENE) as PackedScene
	if packed == null:
		_setup_error = "failed to load %s" % GAME_ROOT_SCENE
		return
	_game = packed.instantiate() as Control
	if _game == null:
		_setup_error = "GameRoot instantiate() returned null or non-Control"
		return
	# Mount directly (not through the harness) so harness per-test cleanup never frees it.
	_root.add_child(_game)
	await _settle(4)

	_sim_host = _game.get_node_or_null("SimulationHost")
	_top_bar = _resolve("HUDLayer/TopBar", "_top_bar") as Control
	_left_nav = _resolve("HUDLayer/LeftNavigation", "_left_nav") as Control
	_bottom_bar = _resolve("HUDLayer/BottomBar", "_bottom_bar") as Control
	_drawer_container = _resolve("HUDLayer/DrawerContainer", "_drawer_container") as Control
	_modal_container = _resolve("HUDLayer/ModalContainer", "_modal_container") as Control
	_loan_modal = _resolve("HUDLayer/ModalContainer/LoanApprovalModal", "_loan_modal") as Control
	_event_modal = _resolve("HUDLayer/ModalContainer/EventModal", "_event_modal") as Control
	_pause_modal = _resolve("HUDLayer/ModalContainer/PauseSaveSettingsModal", "_pause_modal") as Control

	if _sim_host == null:
		_setup_error = "GameRoot/SimulationHost missing"
		return
	if not _sim_host.has_method("get_snapshot"):
		_setup_error = "SimulationHost.get_snapshot missing"
		return
	if _top_bar == null or _left_nav == null or _bottom_bar == null:
		_setup_error = "HUD bar nodes missing (TopBar/LeftNavigation/BottomBar)"
		return
	if _drawer_container == null or _modal_container == null:
		_setup_error = "HUD full-screen containers missing (DrawerContainer/ModalContainer)"
		return
	if _loan_modal == null or _event_modal == null or _pause_modal == null:
		_setup_error = "HUD modal panels missing (LoanApprovalModal/EventModal/PauseSaveSettingsModal)"
		return

	# Freeze the simulation: without this the auto-stepping clock can move the day phase
	# between the synthetic mouse events and the assertion, which would be flaky.
	_sim_host.call("set_auto_process", false)
	await _settle(SETTLE_FRAMES)

	var game_rect: Rect2 = _game.get_global_rect()
	if game_rect.size.x < 320.0 or game_rect.size.y < 240.0:
		_setup_error = "GameRoot has degenerate rect %s — HUD hit coordinates would be meaningless" % str(game_rect)


func _teardown() -> void:
	if _game != null and is_instance_valid(_game):
		if _game.get_parent() != null:
			_game.get_parent().remove_child(_game)
		_game.free()
	_game = null
	_sim_host = null
	_top_bar = null
	_left_nav = null
	_bottom_bar = null
	_drawer_container = null
	_modal_container = null
	_loan_modal = null
	_event_modal = null
	_pause_modal = null
	await _settle(SETTLE_FRAMES)


## Resolve a HUD node by scene path, falling back to GameRoot's own handle variable so the
## suite keeps working if the fix reparents a node inside HUDLayer.
func _resolve(path_from_game: String, handle_var: String) -> Node:
	if _game == null:
		return null
	var n: Node = _game.get_node_or_null(path_from_game)
	if n == null and handle_var != "":
		n = _game.get(handle_var) as Node
	return n


# ---------------------------------------------------------------------------
# Real input plumbing
# ---------------------------------------------------------------------------

func _settle(frames: int = SETTLE_FRAMES) -> void:
	if _tree == null:
		return
	for _i in range(maxi(SETTLE_FRAMES, frames)):
		await _tree.process_frame


func _move_mouse(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	_root.push_input(ev, true)


func _press_release(pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	_root.push_input(press, true)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.button_mask = 0
	release.pressed = false
	release.position = pos
	release.global_position = pos
	_root.push_input(release, true)


## Real left click on a control: settle layout -> hover -> press -> release -> settle.
## The hit point is always the control's own `get_global_rect().get_center()`; we never
## hard-code viewport coordinates (headless viewport is 64x64 while the stretched
## canvas is 1280x1280, so any absolute guess would be wrong).
##
## `_last_hovered` records who owned the pointer at PRESS time. That is the meaningful
## "did the click reach the button" evidence: reading the hover again after the release
## is unsound, because a successful click may hide/destroy the very control that was
## clicked (e.g. a drawer close button).
func _click(control: Control) -> void:
	if control == null:
		return
	await _settle()
	_last_click_pos = control.get_global_rect().get_center()
	_move_mouse(_last_click_pos)
	await _settle()
	_last_click_pos = control.get_global_rect().get_center()
	_last_hovered = _hovered()
	_press_release(_last_click_pos)
	await _settle()


func _hovered() -> Control:
	if _root == null:
		return null
	return _root.gui_get_hovered_control()


func _hover_label(c: Control) -> String:
	if c == null:
		return "<null>"
	if not is_instance_valid(c):
		return "<freed>"
	return str(c.get_path())


# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	if _sim_host == null:
		return {}
	var snap: Variant = _sim_host.call("get_snapshot")
	return snap as Dictionary if snap is Dictionary else {}


func _bank_state() -> Variant:
	return _sim_host.get("bank_state") if _sim_host != null else null


func _speed() -> int:
	return int(_snapshot().get("speed", -1))


func _handle(owner: Node, handle_var: String) -> Button:
	if owner == null:
		return null
	var v: Variant = owner.get(handle_var)
	return v as Button


## Puts the HUD back into a clean, fully-closed state before every case.
func _reset_ui_state() -> void:
	if _game == null:
		return
	if _game.has_method("close_drawer"):
		_game.call("close_drawer")
	for modal: Variant in [_loan_modal, _event_modal, _pause_modal]:
		if modal is Control:
			(modal as Control).visible = false
	var cmd: Variant = _sim_host.get("command_service") if _sim_host != null else null
	if cmd is Object and (cmd as Object).has_method("set_speed"):
		(cmd as Object).call("set_speed", 1)
	await _settle()


# ---------------------------------------------------------------------------
# Per-case bookkeeping (mirrors E2eHarness.run_test, but tolerates coroutine bodies)
# ---------------------------------------------------------------------------

func _begin_case(test_id: String) -> void:
	_current_id = test_id
	_h.set("_assertions", 0)
	var fails: Variant = _h.get("_failures")
	if fails is Array:
		(fails as Array).clear()


func _end_case() -> void:
	var fail_list: Variant = _h.get("_failures")
	var failures: Array = fail_list as Array if fail_list is Array else []
	var assertions: int = int(_h.get("_assertions"))
	if assertions == 0 and failures.is_empty():
		failures.append("Zero assertions executed (zero-false-pass guard)")

	var parts: PackedStringArray = PackedStringArray()
	for f: Variant in failures:
		parts.append(str(f))
	var passed: bool = failures.is_empty()
	var reason: String = "; ".join(parts)
	if passed:
		print("[E2E] Tier %d | %s | PASS" % [TIER, _current_id])
	else:
		print("[E2E] Tier %d | %s | FAIL: %s" % [TIER, _current_id, reason])
	_results.append({
		"tier": "tier%d" % TIER,
		"test": _current_id,
		"passed": passed,
		"reason": reason,
		"assertions": assertions,
	})


# ---------------------------------------------------------------------------
# E2E_T5_01 — TopBar speed buttons (0x / 1x / 2x / 3x)
# ---------------------------------------------------------------------------

func _case_01_topbar_speed_buttons() -> void:
	_begin_case("E2E_T5_01")
	await _reset_ui_state()

	if not _h.assert_not_null(_top_bar, "TopBar 节点缺失，无法驱动速度按钮"):
		_end_case()
		return

	var plan: Array = [
		["_btn_speed_2", 2],
		["_btn_speed_0", 0],
		["_btn_speed_3", 3],
		["_btn_speed_1", 1],
	]
	for entry: Variant in plan:
		var handle: String = str((entry as Array)[0])
		var expected: int = int((entry as Array)[1])
		var btn: Button = _handle(_top_bar, handle)
		if not _h.assert_not_null(btn, "TopBar 速度按钮句柄 %s 缺失" % handle):
			continue

		await _click(btn)
		_h.assert_eq(
			_last_hovered,
			btn,
			"点击速度按钮 %s 时鼠标指针必须命中按钮本身（实际命中 %s，点击坐标 %s）"
			% [handle, _hover_label(_last_hovered), str(_last_click_pos)]
		)
		_h.assert_eq(_speed(), expected, "点击 %s 后 get_snapshot().speed 应为 %d（真实点击未生效）" % [handle, expected])
		var bs: Variant = _bank_state()
		if bs is Object:
			_h.assert_eq(int((bs as Object).get("speed_multiplier")), expected, "点击 %s 后 bank_state.speed_multiplier 应为 %d" % [handle, expected])

	_end_case()


# ---------------------------------------------------------------------------
# E2E_T5_02 — TopBar primary day-action button (PRE_OPEN -> OPEN)
# ---------------------------------------------------------------------------

func _case_02_topbar_day_action() -> void:
	_begin_case("E2E_T5_02")
	await _reset_ui_state()

	var btn: Button = _handle(_top_bar, "_btn_day_action")
	if not _h.assert_not_null(btn, "TopBar 主行动按钮句柄 _btn_day_action 缺失"):
		_end_case()
		return
	var bs: Variant = _bank_state()
	if not _h.assert_not_null(bs, "GameRoot 未能绑定 BankState"):
		_end_case()
		return

	var phase_before: int = int((bs as Object).get("day_phase"))
	if not _h.assert_eq(phase_before, int(Enums.DayPhase.PRE_OPEN), "前置状态：开局 day_phase 应为 PRE_OPEN"):
		_end_case()
		return
	_h.assert_false(btn.disabled, "PRE_OPEN 阶段“开始今日营业”按钮不应为 disabled")

	await _click(btn)
	_h.assert_eq(
		_last_hovered,
		btn,
		"点击主行动按钮时鼠标指针必须命中按钮本身（实际命中 %s，点击坐标 %s）"
		% [_hover_label(_last_hovered), str(_last_click_pos)]
	)
	_h.assert_eq(int((bs as Object).get("day_phase")), int(Enums.DayPhase.OPEN), "点击“开始今日营业”后 bank_state.day_phase 应变为 OPEN（真实点击未生效）")
	_h.assert_eq(int(_snapshot().get("phase", -1)), int(Enums.DayPhase.OPEN), "get_snapshot().phase 应同步为 OPEN")

	_end_case()


# ---------------------------------------------------------------------------
# E2E_T5_03 — TopBar settings button opens the pause/save/settings modal
# ---------------------------------------------------------------------------

func _case_03_topbar_settings_modal() -> void:
	_begin_case("E2E_T5_03")
	await _reset_ui_state()

	var btn: Button = _handle(_top_bar, "_btn_settings")
	if not _h.assert_not_null(btn, "TopBar 设置按钮句柄 _btn_settings 缺失"):
		_end_case()
		return
	if not _h.assert_not_null(_pause_modal, "PauseSaveSettingsModal 节点缺失"):
		_end_case()
		return

	_h.assert_false(_pause_modal.visible, "前置状态：PauseSaveSettingsModal 应为隐藏")
	await _click(btn)
	_h.assert_eq(
		_last_hovered,
		btn,
		"点击设置按钮时鼠标指针必须命中按钮本身（实际命中 %s，点击坐标 %s）"
		% [_hover_label(_last_hovered), str(_last_click_pos)]
	)
	_h.assert_true(_pause_modal.visible, "点击设置按钮后 PauseSaveSettingsModal.visible 应为 true（真实点击未生效）")

	# Reset without a second click: while a modal is open the rest of the HUD is expected
	# to stay locked (see E2E_T5_07), so re-clicking the button is not part of this case.
	_pause_modal.visible = false
	await _settle()

	_end_case()


# ---------------------------------------------------------------------------
# E2E_T5_04 — LeftNavigation drawer button opens / toggles the matching drawer
# ---------------------------------------------------------------------------

func _case_04_left_nav_drawer_toggle() -> void:
	_begin_case("E2E_T5_04")
	await _reset_ui_state()

	var nav_btn: Button = _nav_button(&"overview")
	if not _h.assert_not_null(nav_btn, "LeftNavigation 缺少 overview 抽屉按钮"):
		_end_case()
		return
	var drawer: Control = _drawer_node("OverviewDrawer")
	if not _h.assert_not_null(drawer, "DrawerContainer/OverviewDrawer 缺失"):
		_end_case()
		return

	_h.assert_false(drawer.visible, "前置状态：OverviewDrawer 应为隐藏")
	await _click(nav_btn)
	_h.assert_eq(
		_last_hovered,
		nav_btn,
		"点击左侧导航 overview 按钮时鼠标指针必须命中按钮本身（实际命中 %s，点击坐标 %s）"
		% [_hover_label(_last_hovered), str(_last_click_pos)]
	)
	_h.assert_true(drawer.visible, "点击左侧导航 overview 按钮后 OverviewDrawer.visible 应为 true（真实点击未生效）")
	_h.assert_eq(str(_game.get("_active_drawer_id")), "overview", "GameRoot._active_drawer_id 应变为 overview")

	# Toggling closed must also work: an open drawer must not lock the left nav.
	await _click(nav_btn)
	_h.assert_false(drawer.visible, "再次点击同一导航按钮应关闭抽屉（OverviewDrawer.visible 应为 false）")
	_h.assert_eq(str(_game.get("_active_drawer_id")), "", "关闭抽屉后 GameRoot._active_drawer_id 应复位为空")

	_end_case()


# ---------------------------------------------------------------------------
# E2E_T5_05 — BottomBar loan / event entry buttons open their modal
# ---------------------------------------------------------------------------

func _case_05_bottom_bar_modals() -> void:
	_begin_case("E2E_T5_05")
	await _reset_ui_state()

	var loans_btn: Button = _handle(_bottom_bar, "_btn_loans")
	var events_btn: Button = _handle(_bottom_bar, "_btn_events")
	if not _h.assert_not_null(loans_btn, "BottomBar 贷款入口按钮句柄 _btn_loans 缺失"):
		_end_case()
		return
	if not _h.assert_not_null(events_btn, "BottomBar 事件入口按钮句柄 _btn_events 缺失"):
		_end_case()
		return
	if not _h.assert_not_null(_loan_modal, "LoanApprovalModal 节点缺失"):
		_end_case()
		return
	if not _h.assert_not_null(_event_modal, "EventModal 节点缺失"):
		_end_case()
		return

	# Both entries are state-independent (never disabled); if that ever changes we fail
	# loudly instead of silently clicking a disabled control.
	var loans_enabled: bool = _h.assert_false(loans_btn.disabled, "BottomBar 贷款入口按钮不应为 disabled（否则本用例无法驱动真实点击）")
	var events_enabled: bool = _h.assert_false(events_btn.disabled, "BottomBar 事件入口按钮不应为 disabled（否则本用例无法驱动真实点击）")

	if loans_enabled:
		_h.assert_false(_loan_modal.visible, "前置状态：LoanApprovalModal 应为隐藏")
		await _click(loans_btn)
		_h.assert_eq(
			_last_hovered,
			loans_btn,
			"点击贷款入口按钮时鼠标指针必须命中按钮本身（实际命中 %s，点击坐标 %s）"
			% [_hover_label(_last_hovered), str(_last_click_pos)]
		)
		_h.assert_true(_loan_modal.visible, "点击贷款入口按钮后 LoanApprovalModal.visible 应为 true（真实点击未生效）")
		_loan_modal.visible = false
		await _settle()

	if events_enabled:
		_h.assert_false(_event_modal.visible, "前置状态：EventModal 应为隐藏")
		await _click(events_btn)
		_h.assert_eq(
			_last_hovered,
			events_btn,
			"点击事件入口按钮时鼠标指针必须命中按钮本身（实际命中 %s，点击坐标 %s）"
			% [_hover_label(_last_hovered), str(_last_click_pos)]
		)
		_h.assert_true(_event_modal.visible, "点击事件入口按钮后 EventModal.visible 应为 true（真实点击未生效）")
		_event_modal.visible = false
		await _settle()

	_end_case()


# ---------------------------------------------------------------------------
# E2E_T5_06 — a real button INSIDE DrawerContainer is clickable
# ---------------------------------------------------------------------------

func _case_06_drawer_inner_button() -> void:
	_begin_case("E2E_T5_06")
	await _reset_ui_state()

	var nav_btn: Button = _nav_button(&"overview")
	var drawer: Control = _drawer_node("OverviewDrawer")
	if not _h.assert_not_null(nav_btn, "LeftNavigation 缺少 overview 抽屉按钮"):
		_end_case()
		return
	if not _h.assert_not_null(drawer, "DrawerContainer/OverviewDrawer 缺失"):
		_end_case()
		return

	# Open the drawer through a real nav click (setup must not use method calls either
	# for the part under test).
	await _click(nav_btn)
	if not _h.assert_true(drawer.visible, "前置状态：真实点击导航按钮后 OverviewDrawer 应已打开"):
		_end_case()
		return

	var close_btn: Button = _handle(drawer, "_btn_close")
	if not _h.assert_not_null(close_btn, "OverviewDrawer 关闭按钮句柄 _btn_close 缺失"):
		_end_case()
		return
	_h.assert_true(close_btn.is_visible_in_tree(), "抽屉打开后其内部关闭按钮应在可见树中")
	_h.assert_false(close_btn.disabled, "抽屉关闭按钮不应为 disabled")

	await _click(close_btn)
	_h.assert_eq(
		_last_hovered,
		close_btn,
		"点击 DrawerContainer 内按钮时鼠标指针必须命中该按钮本身（实际命中 %s，点击坐标 %s）"
		% [_hover_label(_last_hovered), str(_last_click_pos)]
	)
	_h.assert_false(drawer.visible, "点击抽屉内关闭按钮后 OverviewDrawer.visible 应为 false（DrawerContainer 内点击不可用）")
	_h.assert_eq(str(_game.get("_active_drawer_id")), "", "关闭抽屉后 GameRoot._active_drawer_id 应复位为空")

	_end_case()


# ---------------------------------------------------------------------------
# E2E_T5_07 — interceptor guard: world stays clickable, modal still locks the HUD
# ---------------------------------------------------------------------------

func _case_07_interceptor_guard() -> void:
	_begin_case("E2E_T5_07")
	await _reset_ui_state()

	var game_rect: Rect2 = _game.get_global_rect()
	var world_probe: Vector2 = game_rect.get_center()

	# --- 7a: with no drawer / modal open, the world region must not be swallowed by
	# full-screen HUD chrome (ModalContainer / DrawerContainer).
	_move_mouse(world_probe)
	await _settle()
	var hovered_world: Control = _hovered()
	_h.assert_ne(
		hovered_world,
		_modal_container,
		"无弹窗时世界区域点击不得被 ModalContainer 拦截（实际命中 ModalContainer —— 全屏 PASS 容器仍是点击黑洞；探针坐标 %s）"
		% str(world_probe)
	)
	_h.assert_ne(
		hovered_world,
		_drawer_container,
		"无抽屉时世界区域点击不得被 DrawerContainer 拦截（实际命中 DrawerContainer；探针坐标 %s）" % str(world_probe)
	)
	_h.assert_true(
		hovered_world == null or hovered_world == _game,
		"无 HUD 面板时世界区域应命中空壳 GameRoot 或空，实际命中 %s" % _hover_label(hovered_world)
	)

	# --- 7b: while a modal is open, HUD buttons outside the modal must stay unclickable.
	var speed_2: Button = _handle(_top_bar, "_btn_speed_2")
	var speed_3: Button = _handle(_top_bar, "_btn_speed_3")
	var settings_btn: Button = _handle(_top_bar, "_btn_settings")
	if not _h.assert_not_null(speed_2, "TopBar 速度按钮句柄 _btn_speed_2 缺失"):
		_end_case()
		return
	if not _h.assert_not_null(speed_3, "TopBar 速度按钮句柄 _btn_speed_3 缺失"):
		_end_case()
		return
	if not _h.assert_not_null(settings_btn, "TopBar 设置按钮句柄 _btn_settings 缺失"):
		_end_case()
		return

	await _click(speed_2)
	if not _h.assert_eq(_speed(), 2, "前置状态：真实点击 2x 后速度应为 2"):
		_end_case()
		return

	_h.assert_false(_pause_modal.visible, "前置状态：PauseSaveSettingsModal 应为隐藏")
	await _click(settings_btn)
	if not _h.assert_true(_pause_modal.visible, "前置状态：真实点击设置按钮后暂停/设置面板应打开"):
		_end_case()
		return

	# Make the case self-validating: the blocked target must be geometrically outside the
	# modal panel, otherwise "clicked a HUD button" and "clicked the modal" are confused.
	var modal_rect: Rect2 = _pause_modal.get_global_rect()
	_h.assert_false(
		modal_rect.intersects(speed_3.get_global_rect()),
		"前置条件：被拦截目标 speed_3 必须位于模态面板之外（modal=%s, button=%s）"
		% [str(modal_rect), str(speed_3.get_global_rect())]
	)

	await _click(speed_3)
	_h.assert_ne(
		_last_hovered,
		speed_3,
		"弹窗打开时，弹窗外的 HUD 按钮不得被命中（实际命中 %s，点击坐标 %s）" % [_hover_label(_last_hovered), str(_last_click_pos)]
	)
	_h.assert_eq(_speed(), 2, "弹窗打开时，弹窗外的 HUD 点击必须被模态拦截（速度应保持 2，不得变为 3）")
	_h.assert_true(_pause_modal.visible, "弹窗打开时，弹窗外的点击不得关闭弹窗")

	_pause_modal.visible = false
	await _settle()

	_end_case()


# ---------------------------------------------------------------------------
# E2E_T5_08 — structural guard: the full-screen containers must be transparent when
# they have no visible panel inside. Implementation-agnostic: the only thing asserted is
# observable picking behaviour, so it passes for both "mouse_filter = IGNORE in the
# .tscn" and "mouse_filter toggled at runtime based on child visibility".
# ---------------------------------------------------------------------------

func _case_08_structural_transparency_guard() -> void:
	_begin_case("E2E_T5_08")
	await _reset_ui_state()

	var targets: Array = [
		["HUDLayer/ModalContainer", _modal_container],
		["HUDLayer/DrawerContainer", _drawer_container],
	]
	for entry: Variant in targets:
		var label: String = str((entry as Array)[0])
		var container: Control = (entry as Array)[1] as Control
		if not _h.assert_not_null(container, "%s 节点缺失" % label):
			continue

		_h.assert_false(_has_visible_child_panel(container), "%s 在无子面板可见时不应存在可见子面板（前置状态不干净）" % label)

		var rect: Rect2 = container.get_global_rect()
		# Guard the guard: a shrunken container would make this test meaningless.
		_h.assert_gt(
			rect.size.x * rect.size.y,
			200000.0,
			"%s 仍应是全屏级容器（rect=%s），否则该结构守卫失去意义" % [label, str(rect)]
		)

		_move_mouse(rect.get_center())
		await _settle()
		var hovered: Control = _hovered()
		_h.assert_false(
			hovered == container,
			"%s 在无子面板可见时不得作为全屏点击拦截器（mouse_filter=%d, 实际命中 %s）"
			% [label, container.mouse_filter, _hover_label(hovered)]
		)

	# Positive control: once a modal IS visible the same container must intercept again,
	# otherwise "transparent when empty" would have been implemented by breaking modals.
	_pause_modal.visible = true
	await _settle()
	var modal_center: Vector2 = _pause_modal.get_global_rect().get_center()
	_move_mouse(modal_center)
	await _settle()
	var hovered_on_modal: Control = _hovered()
	_h.assert_not_null(hovered_on_modal, "弹窗可见时弹窗区域必须仍被某个控件接收（实际为空）")
	_h.assert_true(
		hovered_on_modal == _pause_modal or _is_descendant_of(hovered_on_modal, _pause_modal),
		"弹窗可见时点击弹窗内部应命中弹窗或其子控件，实际命中 %s" % _hover_label(hovered_on_modal)
	)
	_pause_modal.visible = false
	await _settle()

	_end_case()


# ---------------------------------------------------------------------------
# E2E_T5_09 — one click is enough on snapshot-driven list buttons.
#
# Regression: drawers/modals rebuilt every row on `snapshot_changed` (a few times per
# second). A real click spans press -> release across frames; if a rebuild landed between
# them the pressed Button was freed and `pressed` never fired, so the player had to click
# 2-3 times. A tick is forced between press and release to make that window deterministic.
# ---------------------------------------------------------------------------

func _case_09_dynamic_list_single_click() -> void:
	_begin_case("E2E_T5_09")
	await _reset_ui_state()

	var bs: Variant = _bank_state()
	if not _h.assert_not_null(bs, "GameRoot 未能绑定 BankState"):
		_end_case()
		return
	var cmd: Variant = _sim_host.get("command_service")
	if not _h.assert_not_null(cmd, "command_service 缺失"):
		_end_case()
		return

	# --- 9a. loan approval: one press/tick/release must approve ---
	var pending: Array = (bs as Object).get("pending_loan_approvals") as Array
	var loans_before: int = ((bs as Object).get("loans") as Dictionary).size()
	pending.append({
		"approval_id": "t5_single_click_appr",
		"customer_id": "cust_t5",
		"customer_type": "borrower",
		"principal_minor": 600_000,
		"annual_rate_bps": 680,
		"term_days": 30,
		"credit_score": 72,
		"risk_grade": "B",
		"estimated_pd_bps": 260,
	})
	_game.call("open_loan_modal", "t5_single_click_appr")
	await _settle(3)
	if not _h.assert_true(_loan_modal.visible, "贷款审批弹窗应已打开"):
		_end_case()
		return

	var approve_btn: Button = _find_button_by_key(_loan_modal, "UI_LOAN_BTN_APPROVE")
	if not _h.assert_not_null(approve_btn, "贷款审批弹窗缺少批准按钮"):
		_end_case()
		return

	await _click_across_tick(approve_btn)
	var still_pending: bool = false
	for item: Variant in ((bs as Object).get("pending_loan_approvals") as Array):
		if item is Dictionary and str((item as Dictionary).get("approval_id", "")) == "t5_single_click_appr":
			still_pending = true
	_h.assert_false(still_pending, "单次真实点击（按压跨一次模拟 tick 后抬起）必须完成审批，不得要求重复点击")
	_h.assert_eq(
		((bs as Object).get("loans") as Dictionary).size(),
		loans_before + 1,
		"审批通过后应新增 1 笔贷款（单次点击）"
	)
	_loan_modal.visible = false
	await _settle()

	# --- 9b. department upgrade: one press/tick/release must upgrade ---
	cmd.call("create_department", "core:department.operations")
	await _settle()
	var level_before: int = _department_level("core:department.operations")
	if not _h.assert_ge(level_before, 1, "前置状态：运营部应已成立"):
		_end_case()
		return

	_game.call("open_drawer", &"departments")
	await _settle(3)
	var drawer: Control = _drawer_node("DepartmentsDrawer")
	if not _h.assert_not_null(drawer, "DepartmentsDrawer 缺失"):
		_end_case()
		return
	var upgrade_btn: Button = _find_button_by_key_prefix(drawer, "UI_DEPT_BTN_UPGRADE")
	if not _h.assert_not_null(upgrade_btn, "部门抽屉缺少升级按钮"):
		_end_case()
		return

	await _click_across_tick(upgrade_btn)
	_h.assert_eq(
		_department_level("core:department.operations"),
		level_before + 1,
		"单次真实点击（按压跨一次模拟 tick 后抬起）必须完成部门升级，不得要求重复点击"
	)

	_game.call("close_drawer")
	await _settle()
	_end_case()


func _click_across_tick(control: Control) -> void:
	if control == null:
		return
	await _settle()
	var press_pos: Vector2 = control.get_global_rect().get_center()
	_move_mouse(press_pos)
	await _settle()
	_last_click_pos = control.get_global_rect().get_center()
	_last_hovered = _hovered()
	_press_release_press_only(_last_click_pos)
	await _settle(1)
	# Force a snapshot (the old code rebuilt the whole list here and destroyed the button).
	_sim_host.call("step_simulation", 0.35)
	await _settle(1)
	_press_release_release_only(_last_click_pos)
	await _settle()


func _press_release_press_only(pos: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	_root.push_input(press, true)


func _press_release_release_only(pos: Vector2) -> void:
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	release.global_position = pos
	_root.push_input(release, true)


func _find_button_by_key(container: Node, key: String) -> Button:
	var want: String = UiI18n.tr_key(key)
	for b in _buttons_under(container):
		if b.text == want:
			return b
	return null


func _find_button_by_key_prefix(container: Node, key: String) -> Button:
	var want: String = UiI18n.tr_key(key)
	var prefix: String = want.split("{")[0]
	for b in _buttons_under(container):
		if prefix != "" and b.text.begins_with(prefix):
			return b
	return null


func _buttons_under(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n == null:
		return out
	if n is Button:
		out.append(n as Button)
	for c in n.get_children():
		out.append_array(_buttons_under(c))
	return out


func _department_level(dept_id: String) -> int:
	var bs: Variant = _bank_state()
	if bs == null:
		return 0
	var depts: Dictionary = (bs as Object).get("departments") as Dictionary
	if not depts.has(dept_id):
		return 0
	var entry: Variant = depts[dept_id]
	if entry is Object:
		return int((entry as Object).get("level"))
	return int((entry as Dictionary).get("level", 0))


# ---------------------------------------------------------------------------
# E2E_T5_10 — a department is really built where the player clicks in the lobby.
# Flow: drawer "choose plot" -> drawer closes -> world placement mode -> click a free
# tile -> department exists at that grid_pos and a room node is rendered.
# Cancel path: right click leaves no department behind.
# ---------------------------------------------------------------------------

func _case_10_department_placement() -> void:
	_begin_case("E2E_T5_10")
	await _reset_ui_state()

	var world: Node = _game.get("_bank_world") as Node
	if not _h.assert_not_null(world, "GameRoot 未持有 BankWorld"):
		_end_case()
		return
	var bs: Variant = _bank_state()
	if not _h.assert_not_null(bs, "GameRoot 未能绑定 BankState"):
		_end_case()
		return

	# --- 10a. choose a plot, then confirm it with a real lobby click ---
	var nav_btn: Button = _nav_button(&"departments")
	if not _h.assert_not_null(nav_btn, "LeftNavigation 缺少 departments 按钮"):
		_end_case()
		return
	await _click(nav_btn)
	var drawer: Control = _drawer_node("DepartmentsDrawer")
	if not _h.assert_true(drawer != null and drawer.visible, "点击导航后部门抽屉应打开"):
		_end_case()
		return

	var place_dept: String = "core:department.hr"
	var choose_btn: Button = _find_dept_card_button(drawer, place_dept, "UI_DEPT_BTN_CHOOSE_PLOT")
	if not _h.assert_not_null(choose_btn, "部门抽屉缺少“选择位置成立”按钮"):
		_end_case()
		return
	await _click(choose_btn)
	_h.assert_false(drawer.visible, "进入放置模式后抽屉应关闭，露出大厅")
	_h.assert_true(bool(world.call("is_department_placement_active")), "点击“选择位置成立”后应进入部门放置模式")

	var target_cell: Vector2i = _find_valid_plot(world, place_dept)
	if not _h.assert_true(target_cell.x >= 0, "找不到可用于放置部门的合法空地（放置校验过严？）"):
		_end_case()
		return
	var screen_pos: Vector2 = _cell_to_screen(world, target_cell)
	_move_mouse(screen_pos)
	await _settle()
	_last_hovered = _hovered()
	_press_release(screen_pos)
	await _settle(3)

	var dept_id: String = place_dept
	_h.assert_false(bool(world.call("is_department_placement_active")), "确认放置后应退出放置模式")
	_h.assert_true((bs as Object).get("departments").has(dept_id), "确认后应真正成立部门")
	if (bs as Object).get("departments").has(dept_id):
		_h.assert_eq(
			DepartmentService.get_department_grid_pos(bs as BankState, dept_id),
			target_cell,
			"部门必须记录玩家点击的格子坐标"
		)
	var dept_nodes: Dictionary = world.get("_dept_nodes") as Dictionary
	_h.assert_true(dept_nodes.has(dept_id), "世界层应为新部门生成房间节点")

	# --- 10b. right click cancels without building ---
	await _click(nav_btn)
	await _settle(2)
	var cancel_dept: String = "core:department.credit"
	var cancel_btn: Button = _find_dept_card_button(drawer, cancel_dept, "UI_DEPT_BTN_CHOOSE_PLOT")
	if cancel_btn != null:
		await _click(cancel_btn)
		_h.assert_true(bool(world.call("is_department_placement_active")), "前置状态：应再次进入放置模式")
		var cancel_pos: Vector2 = _cell_to_screen(world, _find_valid_plot(world, cancel_dept))
		var right_click := InputEventMouseButton.new()
		right_click.button_index = MOUSE_BUTTON_RIGHT
		right_click.pressed = true
		right_click.position = cancel_pos
		right_click.global_position = cancel_pos
		_root.push_input(right_click, true)
		await _settle(2)
		_h.assert_false(bool(world.call("is_department_placement_active")), "右键应取消部门放置")
		_h.assert_false((bs as Object).get("departments").has(cancel_dept), "取消放置不得成立部门")
	else:
		_h.fail_test("信贷部应仍可进入放置模式")

	_game.call("close_drawer")
	await _settle()
	_end_case()


func _find_dept_card_button(drawer: Control, dept_id: String, key: String) -> Button:
	var grid: Node = drawer.get("_dept_grid") as Node
	if grid == null:
		return null
	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
	var name_key: String = ""
	for raw: Variant in (defs.get("departments", []) as Array):
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == dept_id:
			name_key = str((raw as Dictionary).get("name_key", ""))
			break
	var want_name: String = UiI18n.tr_key(name_key) if name_key != "" else ""
	for card: Node in grid.get_children():
		var card_has_name: bool = false
		for lbl: Node in card.find_children("*", "Label", true, false):
			if (lbl as Label).text == want_name:
				card_has_name = true
				break
		if card_has_name:
			return _find_button_by_key_prefix(card, key)
	return null


func _find_valid_plot(world: Node, dept_id: String) -> Vector2i:
	var candidates: Array[Vector2i] = [
		Vector2i(2, 5), Vector2i(3, 3), Vector2i(12, 6), Vector2i(15, 5),
		Vector2i(2, 9), Vector2i(16, 3), Vector2i(4, 2), Vector2i(13, 2),
	]
	for cell: Vector2i in candidates:
		if bool(world.call("is_valid_department_plot", cell, dept_id)):
			var pos: Vector2 = _cell_to_screen(world, cell)
			if pos.x > 100.0 and pos.x < 940.0 and pos.y > 90.0 and pos.y < 1150.0:
				return cell
	return Vector2i(-1, -1)


func _cell_to_screen(world: Node, cell: Vector2i) -> Vector2:
	var world_obj: Object = world as Object
	var iso: Variant = world_obj.get("iso_grid")
	if iso == null or not (iso is Object):
		return Vector2.ZERO
	var world_pos: Variant = (iso as Object).call("grid_to_screen", cell)
	var canvas_item: CanvasItem = world as CanvasItem
	if canvas_item == null:
		return world_pos as Vector2
	return canvas_item.get_global_transform_with_canvas() * (world_pos as Vector2)


# ---------------------------------------------------------------------------
# E2E_T5_11 / T5_12 — the world layer still receives unhandled input.
# Tier 5 up to here proves GUI picking only; these two prove that a click and a wheel
# event that no Control consumed actually arrive at BankWorld / PixelCamera2D.
# ---------------------------------------------------------------------------

func _case_11_world_click_reaches_entity() -> void:
	_begin_case("E2E_T5_11")
	await _reset_ui_state()

	var world: Node = _game.get("_bank_world") as Node
	if not _h.assert_not_null(world, "GameRoot 未持有 BankWorld"):
		_end_case()
		return
	var views: Dictionary = world.get("_station_views") as Dictionary
	if not _h.assert_true(not views.is_empty(), "大厅应至少有一个柜台视图"):
		_end_case()
		return

	var sid: String = "teller_1"
	if not views.has(sid):
		var keys: Array = views.keys()
		keys.sort()
		sid = str(keys[0])
	var view: Node2D = views[sid] as Node2D
	if not _h.assert_not_null(view, "柜台视图 %s 缺失" % sid):
		_end_case()
		return
	var hit: Rect2 = view.call("get_hit_rect") as Rect2
	var screen_pos: Vector2 = (view as CanvasItem).get_global_transform_with_canvas() * hit.get_center()
	var picked: Array[Dictionary] = []
	var on_pick := func(etype: StringName, eid: String) -> void:
		picked.append({"type": etype, "id": eid})
	world.connect("entity_selected", on_pick)

	_move_mouse(screen_pos)
	await _settle()
	_press_release(screen_pos)
	await _settle(2)

	if world.is_connected("entity_selected", on_pick):
		world.disconnect("entity_selected", on_pick)

	_h.assert_ge(picked.size(), 1, "点击柜台必须到达世界层并发出 entity_selected（unhandled_input 通道）")
	if not picked.is_empty():
		_h.assert_eq(picked[0]["type"], &"station", "命中的实体类型应为 station")
		_h.assert_eq(str(picked[0]["id"]), sid, "命中的实体 id 应为 %s" % sid)
	_end_case()


func _case_12_world_wheel_zoom() -> void:
	_begin_case("E2E_T5_12")
	await _reset_ui_state()

	var world: Node = _game.get("_bank_world") as Node
	if not _h.assert_not_null(world, "GameRoot 未持有 BankWorld"):
		_end_case()
		return
	var cam: Node = world.get("_camera") as Node
	if not _h.assert_not_null(cam, "PixelCamera2D 缺失"):
		_end_case()
		return
	if not _h.require_method(cam, "get_zoom_step", "PixelCamera2D"):
		_end_case()
		return

	world.call("set_camera_zoom_step", 1)
	await _settle()
	_h.assert_eq(int(cam.call("get_zoom_step")), 1, "前置状态：相机缩放应为 1x")

	var probe: Vector2 = _cell_to_screen(world, Vector2i(2, 5))
	_move_mouse(probe)
	await _settle()
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	wheel_up.position = probe
	wheel_up.global_position = probe
	_root.push_input(wheel_up, true)
	await _settle(2)
	_h.assert_eq(int(cam.call("get_zoom_step")), 2, "滚轮向上必须到达 PixelCamera2D 并提升缩放（unhandled_input 通道）")

	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	wheel_down.position = probe
	wheel_down.global_position = probe
	_root.push_input(wheel_down, true)
	await _settle(2)
	_h.assert_eq(int(cam.call("get_zoom_step")), 1, "滚轮向下必须降低缩放")
	_end_case()


# ---------------------------------------------------------------------------
# Small shared helpers
# ---------------------------------------------------------------------------

func _nav_button(drawer_id: StringName) -> Button:
	if _left_nav == null:
		return null
	var map: Variant = _left_nav.get("_nav_buttons")
	if not (map is Dictionary):
		return null
	var v: Variant = (map as Dictionary).get(drawer_id)
	return v as Button


func _drawer_node(node_name: String) -> Control:
	if _drawer_container == null:
		return null
	return _drawer_container.get_node_or_null(node_name) as Control


func _has_visible_child_panel(container: Control) -> bool:
	for child in container.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			return true
	return false


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	if node == null or ancestor == null:
		return false
	var cur: Node = node.get_parent()
	while cur != null:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false
