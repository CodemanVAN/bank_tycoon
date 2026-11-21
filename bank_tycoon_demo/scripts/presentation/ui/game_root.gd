extends Control

## Starway Bank Main Gameplay Root Scene Controller.
## Owns SimulationHost, BankWorldContainer/BankWorld, and HUDLayer (TopBar, LeftNavigation,
## RightInspector, BottomBar, DrawerContainer, ModalContainer, DailyReportOverlay, ToastBar).

const ContentStudioStoreScript := preload("res://scripts/infrastructure/content_studio_store.gd")
const ContentStudioModalScript := preload("res://scripts/presentation/ui/modals/content_studio_modal.gd")

var _sim_host: Node = null
var _bank_world: Node = null

@onready var _top_bar: PanelContainer = $HUDLayer/TopBar
@onready var _left_nav: PanelContainer = $HUDLayer/LeftNavigation
@onready var _right_inspector: PanelContainer = $HUDLayer/RightInspector
@onready var _bottom_bar: PanelContainer = $HUDLayer/BottomBar
@onready var _drawer_container: Control = $HUDLayer/DrawerContainer
@onready var _modal_container: Control = $HUDLayer/ModalContainer
@onready var _modal_shield: Control = get_node_or_null("HUDLayer/ModalContainer/ModalShield") as Control
@onready var _daily_report_overlay: PanelContainer = $HUDLayer/DailyReportOverlay
@onready var _toast_bar: PanelContainer = $HUDLayer/ToastBar

var _drawers: Dictionary = {}
var _active_drawer_id: StringName = &""

var _loan_modal: PanelContainer = null
var _event_modal: PanelContainer = null
var _pause_modal: PanelContainer = null
var _studio_modal: PanelContainer = null
var _last_auto_refresh_frame: int = -1
var _action_cards_box: VBoxContainer = null
var _action_cards_sig: String = ""
var _action_cards_rebuild_pending: bool = false
var _selected_entity_type: StringName = &""
var _selected_entity_id: String = ""
var _pending_delete_target: Dictionary = {}
var _last_service_sfx_msec: int = 0
var _build_bar: PanelContainer = null
var _build_cat_row: HBoxContainer = null
var _build_search_input: LineEdit = null
var _build_items_row: HBoxContainer = null
var _build_selected_category: String = "all"
var _build_search_query: String = ""
var _build_selected_item: String = ""


func _enter_tree() -> void:
	_sim_host = get_node_or_null("SimulationHost")
	var wc: Node = get_node_or_null("WorldHost")
	if wc != null:
		_bank_world = wc.get_node_or_null("BankWorld")


func _ready() -> void:
	var shared_theme: Theme = StarwayTheme.build()
	theme = shared_theme
	var hud_layer: Node = get_node_or_null("HUDLayer")
	if hud_layer != null:
		for child in hud_layer.get_children():
			if child is Control:
				(child as Control).theme = shared_theme
	if _sim_host == null:
		_sim_host = get_node_or_null("SimulationHost")
	if _bank_world == null:
		var wc: Node = get_node_or_null("WorldHost")
		if wc != null:
			_bank_world = wc.get_node_or_null("BankWorld")

	_collect_drawers_and_modals()
	if _right_inspector != null:
		_right_inspector.visible = false
	_setup_right_action_cards(hud_layer, shared_theme)
	_setup_build_catalog_bar(hud_layer, shared_theme)
	_bind_runtime_session()
	_wire_signals()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	_sync_modal_shield()
	refresh_all()


func _collect_drawers_and_modals() -> void:
	if _drawer_container != null:
		_drawers[&"overview"] = _drawer_container.get_node_or_null("OverviewDrawer")
		_drawers[&"finance"] = _drawer_container.get_node_or_null("FinanceDrawer")
		_drawers[&"employees"] = _drawer_container.get_node_or_null("EmployeesDrawer")
		_drawers[&"departments"] = _drawer_container.get_node_or_null("DepartmentsDrawer")
		_drawers[&"policies"] = _drawer_container.get_node_or_null("PoliciesDrawer")
		_drawers[&"events"] = _drawer_container.get_node_or_null("EventsDrawer")

	if _modal_container != null:
		_loan_modal = _modal_container.get_node_or_null("LoanApprovalModal") as PanelContainer
		_event_modal = _modal_container.get_node_or_null("EventModal") as PanelContainer
		_pause_modal = _modal_container.get_node_or_null("PauseSaveSettingsModal") as PanelContainer
		_studio_modal = _modal_container.get_node_or_null("ContentStudioModal") as PanelContainer
		if _studio_modal == null:
			_studio_modal = ContentStudioModalScript.new() as PanelContainer
			_studio_modal.name = "ContentStudioModal"
			_studio_modal.set_anchors_preset(Control.PRESET_CENTER)
			_studio_modal.offset_left = -460.0
			_studio_modal.offset_top = -290.0
			_studio_modal.offset_right = 460.0
			_studio_modal.offset_bottom = 290.0
			_studio_modal.visible = false
			_modal_container.add_child(_studio_modal)


func _bind_runtime_session() -> void:
	var sess: Node = get_node_or_null("/root/GameSession")
	var bs: Variant = sess.get("bank_state") if sess != null else null
	if bs == null and sess != null and sess.has_method("start_new_game"):
		# Start a real session (sets is_active, emits session_started) instead of silently
		# fabricating a half-started bank state that could still be written to a save slot.
		bs = sess.call("start_new_game", "Starway Bank", 20261121)
	if bs == null:
		push_error("[GameRoot] No bank_state available and GameSession.start_new_game failed; HUD stays unbound.")
		return

	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
	if _sim_host != null and _sim_host.has_method("bind_session"):
		_sim_host.call("bind_session", bs, defs)

	# bind_session() rebuilds the DomainEventBus (simulation_host.gd), so the
	# event_published connection has to be re-established after every rebind
	# (initial boot and every save-game reload). is_connected guard = idempotent.
	_wire_event_bus()

	if _bank_world != null and _bank_world.has_method("bind_runtime"):
		_bank_world.call("bind_runtime", _sim_host)

	for ui_node in [_top_bar, _right_inspector, _bottom_bar, _daily_report_overlay, _loan_modal, _event_modal, _pause_modal]:
		if ui_node != null and ui_node.has_method("bind"):
			ui_node.call("bind", _sim_host)

	for did: StringName in _drawers.keys():
		var dnode: Node = _drawers[did] as Node
		if dnode != null and dnode.has_method("bind"):
			dnode.call("bind", _sim_host)


func _wire_event_bus() -> void:
	if _sim_host == null:
		return
	var eb: Variant = _sim_host.get("event_bus")
	if eb is Object and (eb as Object).has_signal("event_published"):
		var cb_ev := Callable(self, &"_on_domain_event_published")
		if not (eb as Object).is_connected("event_published", cb_ev):
			(eb as Object).connect("event_published", cb_ev)


func _wire_signals() -> void:
	if _sim_host != null:
		if _sim_host.has_signal("snapshot_changed"):
			var cb_snap := Callable(self, &"_on_snapshot_changed")
			if not _sim_host.is_connected("snapshot_changed", cb_snap):
				_sim_host.connect("snapshot_changed", cb_snap)
		_wire_event_bus()

	if _bank_world != null and _bank_world.has_signal("entity_selected"):
		var cb_sel := Callable(self, &"_on_world_entity_selected")
		if not _bank_world.is_connected("entity_selected", cb_sel):
			_bank_world.connect("entity_selected", cb_sel)

	if _bank_world != null and _bank_world.has_signal("department_placement_confirmed"):
		var cb_place := Callable(self, &"_on_department_placement_confirmed")
		if not _bank_world.is_connected("department_placement_confirmed", cb_place):
			_bank_world.connect("department_placement_confirmed", cb_place)
	if _bank_world != null and _bank_world.has_signal("department_placement_cancelled"):
		var cb_cancel := Callable(self, &"_on_department_placement_cancelled")
		if not _bank_world.is_connected("department_placement_cancelled", cb_cancel):
			_bank_world.connect("department_placement_cancelled", cb_cancel)
	if _bank_world != null and _bank_world.has_signal("layout_move_requested"):
		var cb_lm := Callable(self, &"_on_layout_move_requested")
		if not _bank_world.is_connected("layout_move_requested", cb_lm):
			_bank_world.connect("layout_move_requested", cb_lm)
	if _bank_world != null and _bank_world.has_signal("layout_build_requested"):
		var cb_lb := Callable(self, &"_on_layout_build_requested")
		if not _bank_world.is_connected("layout_build_requested", cb_lb):
			_bank_world.connect("layout_build_requested", cb_lb)
	if _bank_world != null and _bank_world.has_signal("layout_delete_requested"):
		var cb_ld := Callable(self, &"_on_layout_delete_requested")
		if not _bank_world.is_connected("layout_delete_requested", cb_ld):
			_bank_world.connect("layout_delete_requested", cb_ld)
	if _bank_world != null and _bank_world.has_signal("layout_mode_changed"):
		var cb_lc := Callable(self, &"_on_layout_mode_changed")
		if not _bank_world.is_connected("layout_mode_changed", cb_lc):
			_bank_world.connect("layout_mode_changed", cb_lc)

	if _top_bar != null:
		_top_bar.connect("command_executed", _on_command_executed)
		_top_bar.connect("save_settings_requested", open_pause_modal)
		_top_bar.connect("daily_report_requested", _open_latest_daily_report)

	if _left_nav != null:
		_left_nav.connect("drawer_selected", toggle_drawer)
		_left_nav.connect("settings_requested", open_pause_modal)

	if _right_inspector != null:
		_right_inspector.connect("command_executed", _on_command_executed)
		_right_inspector.connect("loan_modal_requested", func() -> void: open_loan_modal(""))
		_right_inspector.connect("event_modal_requested", func() -> void: open_event_modal(""))

	if _bottom_bar != null:
		_bottom_bar.connect("loan_modal_requested", func() -> void: open_loan_modal(""))
		_bottom_bar.connect("event_modal_requested", func() -> void: open_event_modal(""))
		_bottom_bar.connect("zoom_step_requested", _on_zoom_step_requested)
		if _bottom_bar.has_signal("layout_mode_toggled"):
			_bottom_bar.connect("layout_mode_toggled", _on_layout_mode_toggled)
		if _bottom_bar.has_signal("content_studio_requested"):
			_bottom_bar.connect("content_studio_requested", open_content_studio)

	for did: StringName in _drawers.keys():
		var dnode: Node = _drawers[did] as Node
		if dnode == null:
			continue
		if dnode.has_signal("close_requested"):
			dnode.connect("close_requested", close_drawer)
		if dnode.has_signal("command_executed"):
			dnode.connect("command_executed", _on_command_executed)
		if dnode.has_signal("navigate_requested"):
			dnode.connect("navigate_requested", open_drawer)
		if dnode.has_signal("placement_requested"):
			dnode.connect("placement_requested", _on_department_placement_requested)
		if dnode.has_signal("move_requested"):
			dnode.connect("move_requested", _on_department_move_requested)

	if _loan_modal != null and _loan_modal.has_signal("command_executed"):
		_loan_modal.connect("command_executed", _on_command_executed)
	if _event_modal != null and _event_modal.has_signal("command_executed"):
		_event_modal.connect("command_executed", _on_command_executed)
	if _pause_modal != null:
		if _pause_modal.has_signal("toast_requested"):
			_pause_modal.connect("toast_requested", show_toast)
		if _pause_modal.has_signal("state_reloaded"):
			_pause_modal.connect("state_reloaded", func() -> void:
				_bind_runtime_session()
				refresh_all()
			)

	if _daily_report_overlay != null and _daily_report_overlay.has_signal("next_day_requested"):
		_daily_report_overlay.connect("next_day_requested", _on_next_day_requested)

	if _studio_modal != null:
		if _studio_modal.has_signal("content_changed"):
			_studio_modal.connect("content_changed", _on_studio_content_changed)
		if _studio_modal.has_signal("test_event_requested"):
			_studio_modal.connect("test_event_requested", _on_studio_test_event)
		if _studio_modal.has_signal("test_dialogue_requested"):
			_studio_modal.connect("test_dialogue_requested", _on_studio_test_dialogue)

	# ModalShield blocks clicks outside an open modal. Hook visibility_changed (not
	# just the `closed` signal) so every close path - close button, open_pause_modal
	# toggle, or a direct visible = false - re-opens mouse picking for the HUD.
	for modal_node in [_loan_modal, _event_modal, _pause_modal, _studio_modal, _daily_report_overlay]:
		var mctl: Control = modal_node as Control
		if mctl == null:
			continue
		var cb_vis := Callable(self, &"_sync_modal_shield")
		if not mctl.is_connected("visibility_changed", cb_vis):
			mctl.connect("visibility_changed", cb_vis)


func _any_modal_open() -> bool:
	for modal_node in [_loan_modal, _event_modal, _pause_modal, _studio_modal, _daily_report_overlay]:
		if not is_instance_valid(modal_node):
			continue
		var mctl: Control = modal_node as Control
		if mctl != null and mctl.visible:
			return true
	return false


func open_content_studio() -> void:
	if _studio_modal == null:
		return
	if _studio_modal.visible:
		_studio_modal.visible = false
	else:
		_studio_modal.call("open_studio", _sim_host)
	_sync_modal_shield()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var kev: InputEventKey = event as InputEventKey
		if kev.pressed and not kev.echo and kev.keycode == KEY_F9:
			open_content_studio()
			get_viewport().set_input_as_handled()


func _on_studio_content_changed() -> void:
	if _sim_host != null and _sim_host.has_method("reload_content_defs"):
		var merged_defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
		_sim_host.call("reload_content_defs", merged_defs)
	_refresh_build_catalog_items()
	_action_cards_sig = ""
	refresh_all()


func _on_studio_test_event(event_id: String) -> void:
	_on_studio_content_changed()
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd != null and cmd is Object and (cmd as Object).has_method("trigger_event_by_id"):
		var res: Variant = (cmd as Object).call("trigger_event_by_id", event_id)
		if res is Result and (res as Result).ok:
			if _studio_modal != null:
				_studio_modal.visible = false
			_action_cards_sig = ""
			refresh_all()
			show_toast("UI_STUDIO_EVENT_TRIGGERED", {}, Enums.EventSeverity.INFO)


func _on_studio_test_dialogue(text: String, category: String) -> void:
	if _studio_modal != null:
		_studio_modal.visible = false
	if _bank_world != null and _bank_world.has_method("show_test_dialogue"):
		_bank_world.call("show_test_dialogue", text, category)
	show_toast("UI_STUDIO_DIALOGUE_TRIGGERED", {}, Enums.EventSeverity.INFO)


func _sync_modal_shield() -> void:
	if _modal_shield == null or not is_instance_valid(_modal_shield):
		return
	_modal_shield.visible = _any_modal_open()


func open_drawer(drawer_id: StringName) -> void:
	_cancel_placement_if_active()
	_active_drawer_id = drawer_id
	for did: StringName in _drawers.keys():
		var dnode: Control = _drawers[did] as Control
		if dnode != null:
			dnode.visible = (did == drawer_id)
			if dnode.visible and dnode.has_method("refresh"):
				dnode.call("refresh")
	if _left_nav != null and _left_nav.has_method("set_active_drawer"):
		_left_nav.call("set_active_drawer", _active_drawer_id)


func close_drawer() -> void:
	_active_drawer_id = &""
	for did: StringName in _drawers.keys():
		var dnode: Control = _drawers[did] as Control
		if dnode != null:
			dnode.visible = false
	if _left_nav != null and _left_nav.has_method("set_active_drawer"):
		_left_nav.call("set_active_drawer", &"")


func toggle_drawer(drawer_id: StringName) -> void:
	if _active_drawer_id == drawer_id:
		close_drawer()
	else:
		open_drawer(drawer_id)


func open_loan_modal(approval_id: String = "") -> void:
	if _loan_modal != null and _loan_modal.has_method("open_with"):
		_loan_modal.call("open_with", {"approval_id": approval_id})


func open_event_modal(event_instance_id: String = "") -> void:
	if _event_modal != null and _event_modal.has_method("open_with"):
		_event_modal.call("open_with", {"event_instance_id": event_instance_id})


func open_pause_modal() -> void:
	if _pause_modal != null:
		_pause_modal.visible = not _pause_modal.visible
		if _pause_modal.visible and _pause_modal.has_method("refresh"):
			_pause_modal.call("refresh")


func show_toast(key: String, params: Dictionary = {}, severity: int = Enums.EventSeverity.INFO) -> void:
	if _toast_bar != null and _toast_bar.has_method("show_toast"):
		_toast_bar.call("show_toast", key, params, severity)


func _open_latest_daily_report() -> void:
	if _daily_report_overlay == null or _sim_host == null:
		return
	var bs: BankState = _sim_host.get("bank_state") as BankState
	var rep: Dictionary = {}
	if bs != null and not bs.daily_reports.is_empty():
		rep = bs.daily_reports.back() as Dictionary
	if _daily_report_overlay.has_method("show_report"):
		_daily_report_overlay.call("show_report", rep)


func _on_next_day_requested() -> void:
	if _daily_report_overlay != null:
		_daily_report_overlay.visible = false
	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	# Only call advance_to_next_day if we are still in SETTLED/OPEN/CLOSING; if already in PRE_OPEN
	# (e.g. triggered via TopBar early close or advance_to_next_month), simply enter PRE_OPEN preparation!
	if bs == null or bs.day_phase != Enums.DayPhase.PRE_OPEN:
		var advance_res: Variant = null
		if _sim_host != null:
			var cmd: Variant = _sim_host.get("command_service")
			if cmd != null and (cmd as Object).has_method("advance_to_next_day"):
				advance_res = (cmd as Object).call("advance_to_next_day")
		if advance_res is Result and not (advance_res as Result).ok:
			var adv_err: Result = advance_res as Result
			show_toast(_result_error_key(adv_err), adv_err.error_params, Enums.EventSeverity.CRITICAL)
			refresh_all()
			return

	var save_res: Variant = null
	var sess: Node = get_node_or_null("/root/GameSession")
	if sess != null and sess.has_method("save_to_slot"):
		save_res = sess.call("save_to_slot", "autosave")
	if save_res is Result and not (save_res as Result).ok:
		var save_err: Result = save_res as Result
		show_toast(_result_error_key(save_err), save_err.error_params, Enums.EventSeverity.CRITICAL)
	else:
		show_toast("UI_TOAST_AUTOSAVE_OK", {}, Enums.EventSeverity.INFO)
	refresh_all()


func _result_error_key(res: Result) -> String:
	if res == null:
		return "ERR_SAVE_WRITE_FAILED"
	if not res.error_key.is_empty():
		return res.error_key
	if not res.error_code.is_empty():
		return "ERR_" + String(res.error_code)
	return "ERR_SAVE_WRITE_FAILED"


func _on_world_entity_selected(entity_type: StringName, entity_id: String) -> void:
	if _right_inspector != null and _right_inspector.has_method("show_entity"):
		_right_inspector.call("show_entity", entity_type, entity_id)
	_selected_entity_type = entity_type
	_selected_entity_id = entity_id
	_action_cards_sig = ""
	_refresh_right_action_cards()


func _cancel_placement_if_active() -> void:
	if _bank_world == null or not _bank_world.has_method("is_department_placement_active"):
		return
	if bool(_bank_world.call("is_department_placement_active")):
		_bank_world.call("cancel_department_placement")


func _on_department_placement_requested(dept_id: String) -> void:
	if _bank_world == null or not _bank_world.has_method("begin_department_placement"):
		return
	# Reveal the lobby so the player can pick the plot.
	close_drawer()
	if bool(_bank_world.call("begin_department_placement", dept_id)):
		show_toast("UI_DEPT_PLACE_PROMPT", {}, Enums.EventSeverity.INFO)
	else:
		show_toast("ERR_DEPT_PLOT_INVALID", {}, Enums.EventSeverity.WARNING)


func _on_department_placement_confirmed(dept_id: String, room: Rect2i) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd == null or not (cmd as Object).has_method("create_department"):
		return
	var res: Variant = (cmd as Object).call("create_department", dept_id, room.position, room.size)
	if _toast_bar != null and _toast_bar.has_method("show_command_result"):
		_toast_bar.call("show_command_result", res, "UI_NAV_DEPARTMENTS")
	refresh_all()


func _on_department_placement_cancelled() -> void:
	show_toast("UI_DEPT_PLACE_CANCELLED", {}, Enums.EventSeverity.INFO)


func _on_layout_mode_toggled() -> void:
	if _bank_world == null or not _bank_world.has_method("set_layout_mode"):
		return
	var was_active: bool = bool(_bank_world.call("is_layout_mode_active"))
	if not was_active:
		close_drawer()
	_bank_world.call("set_layout_mode", not was_active)
	if not was_active:
		show_toast("UI_LAYOUT_MODE_HINT", {}, Enums.EventSeverity.INFO)


func _on_layout_mode_changed(active: bool) -> void:
	if _bottom_bar != null and _bottom_bar.has_method("set_layout_mode_active"):
		_bottom_bar.call("set_layout_mode_active", active)
	if not active and not _pending_delete_target.is_empty():
		_pending_delete_target.clear()
		_action_cards_sig = ""
		_refresh_right_action_cards()
	if _build_bar != null:
		_build_bar.visible = active
		if active:
			_refresh_build_catalog_bar()


func _setup_build_catalog_bar(hud_layer: Node, shared_theme: Theme) -> void:
	if hud_layer == null or _build_bar != null:
		return
	_build_bar = PanelContainer.new()
	_build_bar.name = "BuildCatalogBar"
	_build_bar.theme = shared_theme
	_build_bar.theme_type_variation = &"PanelCard"
	_build_bar.visible = false
	_build_bar.anchor_left = 0.0
	_build_bar.anchor_right = 1.0
	_build_bar.anchor_top = 1.0
	_build_bar.anchor_bottom = 1.0
	_build_bar.offset_left = 84.0
	_build_bar.offset_right = -16.0
	_build_bar.offset_top = -188.0
	_build_bar.offset_bottom = -70.0
	hud_layer.add_child(_build_bar)

	var outer_v := VBoxContainer.new()
	outer_v.add_theme_constant_override("separation", 6)
	_build_bar.add_child(outer_v)

	# Top toolbar: Move tool + Category Filter Tabs + Search Box (The Sims style)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	outer_v.add_child(toolbar)

	_build_cat_row = HBoxContainer.new()
	_build_cat_row.add_theme_constant_override("separation", 5)
	_build_cat_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_build_cat_row)

	_build_search_input = LineEdit.new()
	_build_search_input.name = "BuildSearchInput"
	_build_search_input.custom_minimum_size = Vector2(200.0, 26.0)
	_build_search_input.clear_button_enabled = true
	_build_search_input.text_changed.connect(_on_build_search_changed)
	toolbar.add_child(_build_search_input)

	# Bottom horizontal scrollable strip of thumbnail + text item cards
	var scroll := ScrollContainer.new()
	scroll.name = "BuildItemsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer_v.add_child(scroll)

	_build_items_row = HBoxContainer.new()
	_build_items_row.name = "BuildItemsRow"
	_build_items_row.add_theme_constant_override("separation", 8)
	scroll.add_child(_build_items_row)

	_refresh_build_catalog_bar()


func _on_build_search_changed(new_text: String) -> void:
	_build_search_query = new_text.strip_edges().to_lower()
	_refresh_build_catalog_items()


func _refresh_build_catalog_bar() -> void:
	if _build_cat_row == null:
		return
	if _build_search_input != null:
		_build_search_input.placeholder_text = UiI18n.tr_key("UI_BUILD_SEARCH_PLACEHOLDER")
	UiListRefresh.clear_children(_build_cat_row)

	var move_btn := Button.new()
	move_btn.theme_type_variation = &"ButtonGold"
	move_btn.text = UiI18n.tr_key("UI_BUILD_MODE_MOVE")
	move_btn.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_build_selected_item = ""
		if _bank_world != null and _bank_world.has_method("set_layout_mode"):
			_bank_world.call("set_layout_mode", true)
		_refresh_build_catalog_items()
	)
	_build_cat_row.add_child(move_btn)

	var del_btn := Button.new()
	del_btn.theme_type_variation = &"ButtonDanger"
	del_btn.text = UiI18n.tr_key("UI_BUILD_MODE_DELETE")
	del_btn.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_build_selected_item = ""
		if _bank_world != null and _bank_world.has_method("begin_delete_mode"):
			_bank_world.call("begin_delete_mode")
		show_toast("UI_BUILD_DELETE_HINT", {}, Enums.EventSeverity.WARNING)
		_refresh_build_catalog_items()
	)
	_build_cat_row.add_child(del_btn)

	var cats: Array[Dictionary] = [
		{"id": "all", "key": "UI_BUILD_CAT_ALL"},
		{"id": "counters", "key": "UI_BUILD_CAT_COUNTERS"},
		{"id": "facilities", "key": "UI_BUILD_CAT_FACILITIES"},
		{"id": "decor", "key": "UI_BUILD_CAT_DECOR"},
	]
	for cat_def: Dictionary in cats:
		var cid: String = str(cat_def["id"])
		var cbtn := Button.new()
		cbtn.text = UiI18n.tr_key(str(cat_def["key"]))
		if cid == _build_selected_category:
			cbtn.theme_type_variation = &"ButtonPrimary"
		var cid_copy: String = cid
		cbtn.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_build_selected_category = cid_copy
			_refresh_build_catalog_bar()
		)
		_build_cat_row.add_child(cbtn)

	_refresh_build_catalog_items()


func _refresh_build_catalog_items() -> void:
	if _build_items_row == null:
		return
	UiListRefresh.clear_children(_build_items_row)

	var eff_catalog: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
	var ordered_keys: Array[String] = [
		"teller", "loan_desk", "atm", "sofa",
		"coffee_bar", "aquarium", "gold_bull", "bookshelf", "plant",
	]
	for ck: Variant in eff_catalog.keys():
		var csk: String = str(ck)
		if not ordered_keys.has(csk):
			ordered_keys.append(csk)
	for item_type: String in ordered_keys:
		if not eff_catalog.has(item_type):
			continue
		var spec: Dictionary = eff_catalog[item_type] as Dictionary
		var cat: String = str(spec.get("category", "decor"))
		if _build_selected_category != "all" and cat != _build_selected_category:
			continue
		var custom_name: String = str(spec.get("name", "")).strip_edges()
		var raw_name: String = custom_name if not custom_name.is_empty() else UiI18n.tr_key(str(spec.get("label_key", item_type)))
		var clean_name: String = raw_name.trim_prefix("+").strip_edges()
		if not _build_search_query.is_empty():
			var haystack: String = (clean_name + " " + item_type + " " + cat).to_lower()
			if not haystack.contains(_build_search_query):
				continue

		var cost_txt: String = FormatService.format_money_compact(int(spec.get("cost_minor", 0)), "CNY", false)
		var card_btn := Button.new()
		card_btn.name = "BuildCard_%s" % item_type
		card_btn.custom_minimum_size = Vector2(108.0, 74.0)
		card_btn.focus_mode = Control.FOCUS_NONE
		var is_sel: bool = (_build_selected_item == item_type)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.24, 0.44, 0.96) if is_sel else Color(0.04, 0.13, 0.26, 0.92)
		sb.border_color = Color("#FFC857") if is_sel else Color("#1F6FEB")
		sb.set_border_width_all(2 if is_sel else 1)
		sb.set_corner_radius_all(6)
		card_btn.add_theme_stylebox_override("normal", sb)
		var sb_hover: StyleBoxFlat = sb.duplicate() as StyleBoxFlat
		sb_hover.bg_color = Color(0.09, 0.26, 0.48, 0.98)
		sb_hover.border_color = Color("#00C6FF")
		card_btn.add_theme_stylebox_override("hover", sb_hover)

		var cv := VBoxContainer.new()
		cv.set_anchors_preset(Control.PRESET_FULL_RECT)
		cv.offset_left = 4.0
		cv.offset_right = -4.0
		cv.offset_top = 4.0
		cv.offset_bottom = -4.0
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 2)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_btn.add_child(cv)

		var tex_path: String = str(spec.get("tex_path", spec.get("texture", "")))
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(36.0, 34.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
			icon.texture = load(tex_path) as Texture2D
		cv.add_child(icon)

		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = "%s\n%s" % [clean_name, cost_txt]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color("#F5F8FF"))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(lbl)

		var itype_copy: String = item_type
		card_btn.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			_build_selected_item = itype_copy
			if _bank_world != null and _bank_world.has_method("begin_build_item"):
				_bank_world.call("begin_build_item", itype_copy)
			_refresh_build_catalog_items()
		)
		_build_items_row.add_child(card_btn)


func _on_layout_build_requested(item_type: String, target_cell: Vector2i) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd == null or not (cmd is Object):
		return
	var eff_cat: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
	var spec: Dictionary = eff_cat.get(item_type, {}) as Dictionary
	var res: Variant = null
	if str(spec.get("kind", "")) == "station":
		res = (cmd as Object).call("build_station", item_type, target_cell)
	else:
		res = (cmd as Object).call("build_lobby_prop", item_type, target_cell)
	if res is Result:
		if (res as Result).ok:
			UiI18n.play_sfx("sfx_cash_chime")
			show_toast("UI_BUILD_SUCCESS", {}, Enums.EventSeverity.INFO)
		else:
			var err_r: Result = res as Result
			show_toast(_result_error_key(err_r), err_r.error_params, Enums.EventSeverity.WARNING)
	refresh_all()


func _on_layout_delete_requested(kind: StringName, item_id: String) -> void:
	if item_id.is_empty():
		return
	UiI18n.play_sfx("sfx_ui_click")
	_pending_delete_target = {
		"kind": kind,
		"id": item_id,
	}
	_action_cards_sig = ""
	_refresh_right_action_cards()


func _confirm_pending_delete() -> void:
	if _pending_delete_target.is_empty():
		return
	var kind: StringName = _pending_delete_target.get("kind", &"") as StringName
	var item_id: String = str(_pending_delete_target.get("id", ""))
	_pending_delete_target.clear()
	if _sim_host == null or item_id.is_empty():
		_action_cards_sig = ""
		_refresh_right_action_cards()
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd == null or not (cmd is Object):
		return
	var res: Variant = null
	match String(kind):
		"station":
			res = (cmd as Object).call("delete_station", item_id)
		"prop":
			res = (cmd as Object).call("delete_lobby_prop", item_id)
		"department":
			res = (cmd as Object).call("demolish_department", item_id)
	if res is Result:
		if (res as Result).ok:
			UiI18n.play_sfx("sfx_ui_click")
			show_toast("UI_BUILD_DELETE_OK", {}, Enums.EventSeverity.INFO)
			if _selected_entity_id == item_id:
				_selected_entity_type = &""
				_selected_entity_id = ""
		else:
			var err_r: Result = res as Result
			show_toast(_result_error_key(err_r), err_r.error_params, Enums.EventSeverity.WARNING)
	_action_cards_sig = ""
	refresh_all()


func _on_department_move_requested(dept_id: String) -> void:
	if _bank_world == null or not _bank_world.has_method("begin_move_department"):
		return
	close_drawer()
	_bank_world.call("begin_move_department", dept_id)
	show_toast("UI_LAYOUT_MOVE_DEPT_HINT", {}, Enums.EventSeverity.INFO)


func _on_layout_move_requested(kind: StringName, item_id: String, target_cell: Vector2i) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd == null or not (cmd is Object):
		return
	var res: Variant = null
	match String(kind):
		"station":
			res = (cmd as Object).call("move_station", item_id, target_cell)
		"prop":
			res = (cmd as Object).call("move_lobby_prop", item_id, target_cell)
		"department":
			res = (cmd as Object).call("move_department", item_id, target_cell)
	if res is Result:
		if (res as Result).ok:
			UiI18n.play_sfx("sfx_ui_click")
			show_toast("UI_LAYOUT_MOVE_OK", {}, Enums.EventSeverity.INFO)
		else:
			var err_r: Result = res as Result
			show_toast(_result_error_key(err_r), err_r.error_params, Enums.EventSeverity.WARNING)
	refresh_all()


func _on_zoom_step_requested(step: int) -> void:
	if _bank_world != null and _bank_world.has_method("set_camera_zoom_step"):
		_bank_world.call("set_camera_zoom_step", step)


func _on_command_executed(res: Variant, action_key: String) -> void:
	if _toast_bar != null and _toast_bar.has_method("show_command_result"):
		_toast_bar.call("show_command_result", res, action_key)
	refresh_all()


func _setup_right_action_cards(hud_layer: Node, shared_theme: Theme) -> void:
	if hud_layer == null or _action_cards_box != null:
		return
	_action_cards_box = VBoxContainer.new()
	_action_cards_box.name = "RightActionCards"
	_action_cards_box.theme = shared_theme
	_action_cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_cards_box.anchor_left = 1.0
	_action_cards_box.anchor_right = 1.0
	_action_cards_box.anchor_top = 0.0
	_action_cards_box.anchor_bottom = 0.0
	_action_cards_box.offset_left = -364.0
	_action_cards_box.offset_right = -12.0
	_action_cards_box.offset_top = 64.0
	_action_cards_box.offset_bottom = 644.0
	_action_cards_box.add_theme_constant_override("separation", 8)
	hud_layer.add_child(_action_cards_box)


func _on_action_cards_button_up() -> void:
	if not _action_cards_rebuild_pending:
		return
	_action_cards_rebuild_pending = false
	_refresh_right_action_cards.call_deferred()


func _refresh_right_action_cards() -> void:
	if _action_cards_box == null or not is_instance_valid(_action_cards_box):
		return
	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var active_evs: Array = bs.active_events if bs != null else []
	var pending_loans: Array = bs.pending_loan_approvals if bs != null else []
	var pending_resigns: Array = bs.pending_resignations if bs != null else []
	var dept_svc := DepartmentService.new()
	var exact_unlocked: bool = dept_svc.is_capability_unlocked(bs, "exact_credit_score") if bs != null else false
	var lc: String = UiI18n.get_locale()
	var ccy: String = bs.currency_code if bs != null else "CNY"

	var sig_parts: Array = [
		lc, ccy, exact_unlocked, active_evs.size(), pending_loans.size(), pending_resigns.size(),
		str(_pending_delete_target.get("kind", "")), str(_pending_delete_target.get("id", "")),
		String(_selected_entity_type), _selected_entity_id,
	]
	if bs != null and not _selected_entity_id.is_empty():
		match String(_selected_entity_type):
			"customer":
				var c_sig: Variant = bs.active_customers.get(_selected_entity_id, null)
				if c_sig is CustomerInstance:
					var cs: CustomerInstance = c_sig as CustomerInstance
					sig_parts.append("C:%d:%d:%d:%d:%s" % [cs.state, cs.patience_remaining, cs.dissatisfaction, cs.wait_minutes, cs.browsing_prop_id])
			"employee":
				var e_sig: Variant = bs.employees.get(_selected_entity_id, null)
				if e_sig is EmployeeInstance:
					var es: EmployeeInstance = e_sig as EmployeeInstance
					sig_parts.append("EM:%d:%d:%d:%s:%s" % [es.state, es.fatigue, es.training_count, es.assigned_station_id, ",".join(es.traits)])
			"station":
				var s_sig: Variant = bs.stations.get(_selected_entity_id, null)
				if s_sig is Dictionary:
					var sd: Dictionary = s_sig as Dictionary
					sig_parts.append("S:%s:%s" % [str(sd.get("is_open", true)), str(sd.get("assigned_employee_id", ""))])
			"prop":
				sig_parts.append("P:%s" % str(bs.lobby_props.has(_selected_entity_id)))
	var ev_shown: int = 0
	for raw_ev: Variant in active_evs:
		if ev_shown >= 2:
			break
		if raw_ev is Dictionary:
			var inst: Dictionary = raw_ev as Dictionary
			var rem_m: int = int(inst.get("remaining_minutes", BalanceConfig.DEFAULT_EVENT_TIMEOUT_MINUTES))
			sig_parts.append("E:%s:%s:%d" % [str(inst.get("instance_id", inst.get("id", ""))), str(inst.get("event_id", "")), rem_m])
			ev_shown += 1
	var ln_shown: int = 0
	for raw_app: Variant in pending_loans:
		if ln_shown >= 2:
			break
		if raw_app is Dictionary:
			var app: Dictionary = raw_app as Dictionary
			sig_parts.append("L:%s:%d:%d:%d:%d:%s" % [
				str(app.get("approval_id", app.get("id", ""))),
				int(app.get("principal_minor", 0)),
				int(app.get("annual_rate_bps", 0)),
				int(app.get("term_days", 0)),
				int(app.get("credit_score", 0)),
				str(app.get("risk_grade", "")),
			])
			ln_shown += 1

	var new_sig: String = UiListRefresh.signature(sig_parts)
	if new_sig == _action_cards_sig:
		return
	if UiListRefresh.any_button_held(_action_cards_box):
		_action_cards_rebuild_pending = true
		return
	_action_cards_sig = new_sig
	UiListRefresh.clear_children(_action_cards_box)

	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
	var opt_letters: Array[String] = ["A", "B", "C", "D"]

	# 0a) Pending Delete Confirmation Card (red border + explicit Confirm / Cancel buttons)
	if not _pending_delete_target.is_empty() and bs != null:
		var dcard: PanelContainer = _build_delete_confirm_card(_pending_delete_target, bs)
		if dcard != null:
			_action_cards_box.add_child(dcard)

	# 0b) Selected World Entity Inspection Card (Customer / Employee / Station / Decor Prop)
	if not _selected_entity_id.is_empty() and bs != null:
		var ecard: PanelContainer = _build_entity_inspection_card(_selected_entity_type, _selected_entity_id, bs, defs, ccy)
		if ecard != null:
			_action_cards_box.add_child(ecard)

	# 0c) Pending Employee Resignation Warning Cards
	if bs != null and not pending_resigns.is_empty():
		for raw_pr: Variant in pending_resigns:
			if raw_pr is Dictionary:
				var rcard: PanelContainer = _build_resignation_card(raw_pr as Dictionary, bs, ccy)
				if rcard != null:
					_action_cards_box.add_child(rcard)
				break

	# 1) Inline Random Event Decision Cards (up to 2)
	var ev_count: int = 0
	for raw_ev: Variant in active_evs:
		if ev_count >= 2:
			break
		if not (raw_ev is Dictionary):
			continue
		var inst: Dictionary = raw_ev as Dictionary
		var inst_id: String = str(inst.get("instance_id", inst.get("id", "")))
		var ev_id: String = str(inst.get("event_id", ""))
		var edef: Dictionary = EventEngine._find_event_def(ev_id, defs)
		var meta: Dictionary = inst.get("metadata", {}) as Dictionary if inst.get("metadata") is Dictionary else {}
		var chain_id: String = str(edef.get("chain_id", ""))
		var source_ev: String = str(meta.get("source_event_id", ""))

		var card := _make_action_card_panel("InlineEventCard_%s" % inst_id, Color("#00C6FF"))
		_action_cards_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 5)
		card.add_child(cv)

		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 6)
		cv.add_child(hdr)

		var badge := Label.new()
		badge.add_theme_font_size_override("font_size", 11)
		if not source_ev.is_empty():
			badge.add_theme_color_override("font_color", Color("#FFC857"))
			badge.text = UiI18n.tr_key("UI_EVENT_CHAIN_FOLLOWUP")
		elif not chain_id.is_empty():
			badge.add_theme_color_override("font_color", Color("#FFC857"))
			badge.text = UiI18n.tr_key("UI_EVENT_CHAIN_ARC")
		else:
			badge.add_theme_color_override("font_color", Color("#00C6FF"))
			badge.text = UiI18n.tr_key("UI_CARD_EVENT_BADGE")
		hdr.add_child(badge)

		var tl := Label.new()
		tl.theme_type_variation = &"LabelTitle"
		tl.add_theme_font_size_override("font_size", 13)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.text = UiI18n.tr_key(str(edef.get("title_key", ev_id)))
		hdr.add_child(tl)

		var rem_mins: int = maxi(0, int(inst.get("remaining_minutes", BalanceConfig.DEFAULT_EVENT_TIMEOUT_MINUTES)))
		var timer_l := Label.new()
		timer_l.add_theme_font_size_override("font_size", 11)
		var hrs: int = rem_mins / 60
		var mins: int = rem_mins % 60
		if hrs > 0:
			timer_l.text = UiI18n.tr_key("UI_EVENT_TIMER_HM", {"h": hrs, "m": mins})
		else:
			timer_l.text = UiI18n.tr_key("UI_EVENT_TIMER_M", {"m": mins})
		if rem_mins <= 20:
			timer_l.add_theme_color_override("font_color", Color("#FF6B6B"))
		elif rem_mins <= 60:
			timer_l.add_theme_color_override("font_color", Color("#FFC857"))
		else:
			timer_l.add_theme_color_override("font_color", Color("#7FD8FF"))
		hdr.add_child(timer_l)

		var dl := Label.new()
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.add_theme_font_size_override("font_size", 11)
		dl.add_theme_color_override("font_color", Color("#D8E6FF"))
		dl.text = UiI18n.tr_key(str(edef.get("description_key", "")))
		cv.add_child(dl)

		var opts: Array = edef.get("options", []) as Array
		for oidx: int in range(opts.size()):
			var raw_opt: Variant = opts[oidx]
			if not (raw_opt is Dictionary):
				continue
			var odef: Dictionary = raw_opt as Dictionary
			var oid: String = str(odef.get("id", ""))
			var prefix: String = opt_letters[oidx] if oidx < opt_letters.size() else str(oidx + 1)

			var obtn := Button.new()
			obtn.theme_type_variation = &"ButtonPrimary"
			obtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			obtn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			obtn.add_theme_font_size_override("font_size", 12)
			obtn.text = "%s. %s" % [prefix, UiI18n.tr_key(str(odef.get("label_key", oid)))]
			var inst_copy: String = inst_id
			var oid_copy: String = oid
			obtn.pressed.connect(func() -> void:
				UiI18n.play_sfx("sfx_ui_click")
				_exec_inline_event_option(inst_copy, oid_copy)
			)
			cv.add_child(obtn)

			var previews: Array[Dictionary] = EventEngine.get_option_outcomes_preview(ev_id, odef)
			for item: Dictionary in previews:
				var pl := Label.new()
				pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				pl.add_theme_font_size_override("font_size", 11)
				var sentiment: String = str(item.get("sentiment", "mixed"))
				if sentiment == "positive":
					pl.add_theme_color_override("font_color", Color("#35C978"))
				elif sentiment == "negative":
					pl.add_theme_color_override("font_color", Color("#FF6B6B"))
				else:
					pl.add_theme_color_override("font_color", Color("#FFC857"))
				pl.text = "  " + _format_inline_outcome_preview(item, defs)
				cv.add_child(pl)

		ev_count += 1

	# 2) Inline Loan Approval Cards (up to 2)
	var ln_count: int = 0
	for raw_app: Variant in pending_loans:
		if ln_count >= 2:
			break
		if not (raw_app is Dictionary):
			continue
		var app: Dictionary = raw_app as Dictionary
		var aid: String = str(app.get("approval_id", app.get("id", "")))
		var cust_type: String = str(app.get("customer_type", "borrower"))
		var principal: int = int(app.get("principal_minor", 600_000))
		var rate_bps: int = int(app.get("annual_rate_bps", bs.loan_base_rate_bps if bs != null else 650))
		var term_days: int = int(app.get("term_days", 30))
		var score: int = int(app.get("credit_score", 68))
		var grade: String = str(app.get("risk_grade", "B"))
		var pd_bps: int = int(app.get("estimated_pd_bps", 300))

		var card := _make_action_card_panel("InlineLoanCard_%s" % aid, Color("#FFC857"))
		_action_cards_box.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 5)
		card.add_child(cv)

		var hdr := HBoxContainer.new()
		hdr.add_theme_constant_override("separation", 6)
		cv.add_child(hdr)

		var title_l := Label.new()
		title_l.theme_type_variation = &"LabelTitle"
		title_l.add_theme_font_size_override("font_size", 13)
		title_l.add_theme_color_override("font_color", Color("#FFC857"))
		title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b_name: String = str(app.get("borrower_name", ""))
		if b_name.is_empty():
			b_name = LoanInstance.generate_borrower_name(str(app.get("customer_id", aid)), cust_type)
		title_l.text = "%s · %s (%s)" % [UiI18n.tr_key("UI_CARD_LOAN_TITLE"), b_name, UiI18n.tr_customer_type(cust_type)]
		hdr.add_child(title_l)

		var terms_l := Label.new()
		terms_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		terms_l.add_theme_font_size_override("font_size", 12)
		terms_l.text = UiI18n.tr_key("UI_LOAN_TERMS", {
			"principal": FormatService.format_money_compact(principal, ccy, false),
			"rate": FormatService.format_bps(rate_bps),
			"days": term_days,
		})
		cv.add_child(terms_l)

		var risk_l := Label.new()
		risk_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		risk_l.add_theme_font_size_override("font_size", 11)
		risk_l.add_theme_color_override("font_color", Color("#BBD2F5"))
		if exact_unlocked:
			risk_l.text = UiI18n.tr_key("UI_LOAN_RISK_EXACT", {
				"score": score,
				"grade": grade,
				"pd": FormatService.format_bps(pd_bps),
			})
		else:
			var band_lo: int = int(floor(float(score) / 10.0) * 10.0)
			risk_l.text = UiI18n.tr_key("UI_LOAN_RISK_BAND", {
				"band": "%d-%d" % [band_lo, mini(100, band_lo + 10)],
				"grade": grade,
				"pd": FormatService.format_bps(pd_bps),
			})
		cv.add_child(risk_l)

		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 8)
		cv.add_child(btn_row)

		var aid_copy: String = aid
		var btn_ok := Button.new()
		btn_ok.theme_type_variation = &"ButtonPrimary"
		var sb_ok := StyleBoxFlat.new()
		sb_ok.bg_color = Color("#1F9D55")
		sb_ok.border_color = Color("#35C978")
		sb_ok.set_border_width_all(1)
		sb_ok.set_corner_radius_all(5)
		sb_ok.content_margin_top = 4
		sb_ok.content_margin_bottom = 4
		btn_ok.add_theme_stylebox_override("normal", sb_ok)
		var sb_ok_h: StyleBoxFlat = sb_ok.duplicate() as StyleBoxFlat
		sb_ok_h.bg_color = Color("#28B463")
		btn_ok.add_theme_stylebox_override("hover", sb_ok_h)
		btn_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_ok.text = UiI18n.tr_key("UI_LOAN_BTN_APPROVE")
		btn_ok.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_loan_approve")
			_exec_inline_loan_decision(aid_copy, true)
		)
		btn_row.add_child(btn_ok)

		var btn_no := Button.new()
		btn_no.theme_type_variation = &"ButtonDanger"
		btn_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_no.text = UiI18n.tr_key("UI_LOAN_BTN_REJECT")
		btn_no.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_loan_reject")
			_exec_inline_loan_decision(aid_copy, false)
		)
		btn_row.add_child(btn_no)

		ln_count += 1

	UiListRefresh.watch_tree(_action_cards_box, _on_action_cards_button_up)


func _make_action_card_panel(card_name: String, accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = card_name
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.13, 0.25, 0.95)
	sb.border_color = accent
	sb.border_width_left = 4
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	return card


func _build_delete_confirm_card(target: Dictionary, bs: BankState) -> PanelContainer:
	var kind: String = str(target.get("kind", ""))
	var item_id: String = str(target.get("id", ""))
	var display_name: String = item_id
	if kind == "station" and bs.stations.has(item_id):
		var st: Dictionary = bs.stations[item_id] as Dictionary
		var st_type: String = str(st.get("station_type", "teller"))
		display_name = "%s (%s)" % [UiI18n.tr_key("UI_BUILD_ITEM_LOAN_DESK" if st_type == "loan_desk" else "UI_BUILD_ITEM_TELLER").trim_prefix("+"), item_id]
	elif kind == "prop" and bs.lobby_props.has(item_id):
		var pr: Dictionary = bs.lobby_props[item_id] as Dictionary
		var pt: String = str(pr.get("prop_type", "plant"))
		display_name = _prop_display_name(pt)
	elif kind == "department":
		display_name = UiI18n.tr_key(_dept_name_key_for_card(item_id))

	var card := _make_action_card_panel("DeleteConfirmCard", Color("#FF3B30"))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)

	var tl := Label.new()
	tl.theme_type_variation = &"LabelTitle"
	tl.add_theme_font_size_override("font_size", 13)
	tl.add_theme_color_override("font_color", Color("#FF6B6B"))
	tl.text = UiI18n.tr_key("UI_DELETE_CONFIRM_TITLE")
	cv.add_child(tl)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 12)
	body.text = UiI18n.tr_key("UI_DELETE_CONFIRM_BODY", {"name": display_name})
	cv.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	cv.add_child(row)

	var btn_yes := Button.new()
	btn_yes.name = "BtnConfirmDelete"
	btn_yes.theme_type_variation = &"ButtonDanger"
	btn_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_yes.text = UiI18n.tr_key("UI_DELETE_CONFIRM_YES")
	btn_yes.pressed.connect(func() -> void:
		_confirm_pending_delete()
	)
	row.add_child(btn_yes)

	var btn_no := Button.new()
	btn_no.name = "BtnCancelDelete"
	btn_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_no.text = UiI18n.tr_key("UI_DELETE_CONFIRM_NO")
	btn_no.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_pending_delete_target.clear()
		_action_cards_sig = ""
		_refresh_right_action_cards()
	)
	row.add_child(btn_no)
	return card


func _build_entity_inspection_card(
	entity_type: StringName,
	entity_id: String,
	bs: BankState,
	defs: Dictionary,
	ccy: String
) -> PanelContainer:
	var accent: Color = Color("#00C6FF")
	var icon_tex: Texture2D = null
	var title_text: String = ""
	var sub_text: String = ""
	var body_lines: Array[String] = []
	var bars: Array[Dictionary] = []
	var tag_texts: Array[String] = []
	var extra_action: Dictionary = {}

	match String(entity_type):
		"customer":
			if not bs.active_customers.has(entity_id):
				return null
			var cust: CustomerInstance = bs.active_customers[entity_id] as CustomerInstance
			if cust == null:
				return null
			accent = Color("#35C978")
			icon_tex = UiI18n.load_avatar(cust.avatar_id)
			title_text = "%s · %s" % [UiI18n.tr_customer_type(cust.customer_type), UiI18n.tr_cust_state(cust.state)]
			var req_srv: String = ""
			var req_amt: int = 0
			var is_complex: bool = false
			var is_atm: bool = false
			for rq: ServiceRequest in bs.service_requests:
				if rq != null and rq.request_id == cust.active_request_id:
					req_srv = String(rq.service_type)
					req_amt = int(rq.payload.get("principal_minor", 0)) if req_srv == "personal_loan_application" else int(rq.payload.get("amount_minor", 0))
					is_complex = bool(rq.payload.get("is_complex_case", false))
					is_atm = not str(rq.payload.get("atm_mode", "")).is_empty()
					break
			var srv_name: String = UiI18n.tr_service_type(req_srv) if not req_srv.is_empty() else "-"
			if req_amt > 0:
				sub_text = "%s · %s" % [srv_name, FormatService.format_money_compact(req_amt, ccy, false)]
			else:
				sub_text = srv_name
			if is_complex:
				tag_texts.append(UiI18n.tr_key("UI_CARD_TAG_COMPLEX"))
			if is_atm:
				tag_texts.append(UiI18n.tr_key("UI_CARD_TAG_ATM"))
			if not cust.browsing_prop_id.is_empty() and bs.lobby_props.has(cust.browsing_prop_id):
				var bp: Dictionary = bs.lobby_props[cust.browsing_prop_id] as Dictionary
				tag_texts.append(UiI18n.tr_key("UI_CARD_TAG_BROWSING", {"prop": _prop_display_name(str(bp.get("prop_type", "fountain")))}))
			var hist_score: int = int(cust.credit_profile.get("history_score", 70))
			body_lines.append(UiI18n.tr_key("UI_CARD_CUST_META", {"wait": cust.wait_minutes, "score": hist_score}))
			var pat_pct: int = clampi(int(round(float(cust.patience_remaining) * 100.0 / float(maxi(1, cust.patience_max)))), 0, 100)
			bars.append({
				"label": UiI18n.tr_key("UI_CARD_CUST_PATIENCE", {"cur": cust.patience_remaining, "max": cust.patience_max}),
				"value": pat_pct,
				"color": Color("#35C978") if pat_pct > 45 else Color("#FFC857"),
			})
			bars.append({
				"label": UiI18n.tr_key("UI_CARD_CUST_DISSAT", {"val": cust.dissatisfaction}),
				"value": cust.dissatisfaction,
				"color": Color("#FF4D4F") if cust.dissatisfaction >= 60 else Color("#FFC857"),
			})
		"employee":
			if not bs.employees.has(entity_id):
				return null
			var emp: EmployeeInstance = bs.employees[entity_id] as EmployeeInstance
			if emp == null:
				return null
			accent = Color("#00C6FF")
			icon_tex = UiI18n.load_avatar(emp.avatar_id)
			title_text = "%s · %s · Lv.%d" % [UiI18n.tr_person_name(emp.name_key), UiI18n.tr_role(emp.role_id), emp.level]
			sub_text = "%s %d · %s · %s" % [
				UiI18n.tr_key("UI_EMP_STAT_CAP_SHORT"), emp.get_stat_cap(),
				UiI18n.tr_emp_state(emp.state),
				FormatService.format_money_compact(emp.daily_salary_minor, ccy, false),
			]
			var eff_a: Dictionary = emp.get_effective_attributes(defs)
			body_lines.append("%s %d  ·  %s %d  ·  %s %d" % [
				UiI18n.tr_key("UI_RADAR_PROF"), int(eff_a["professionalism"]),
				UiI18n.tr_key("UI_RADAR_EFF"), int(eff_a["efficiency"]),
				UiI18n.tr_key("UI_RADAR_SOC"), int(eff_a["sociability"]),
			])
			body_lines.append("%s %d  ·  %s %d  ·  %s %d" % [
				UiI18n.tr_key("UI_RADAR_RISK"), int(eff_a["risk_awareness"]),
				UiI18n.tr_key("UI_RADAR_MGMT"), int(eff_a["management"]),
				UiI18n.tr_key("UI_RADAR_LOYAL"), int(eff_a["loyalty"]),
			])
			for tid: String in emp.traits:
				var raw_ts: Variant = defs.get("traits", [])
				var tlabel: String = tid
				if raw_ts is Array:
					for rt: Variant in (raw_ts as Array):
						if rt is Dictionary and str((rt as Dictionary).get("id", "")) == tid:
							tlabel = UiI18n.tr_key(str((rt as Dictionary).get("name_key", tid)))
							break
				tag_texts.append(tlabel)
			bars.append({
				"label": UiI18n.tr_key("UI_INSPECTOR_EMP_FATIGUE", {"fatigue": emp.fatigue}),
				"value": emp.fatigue,
				"color": Color("#FF4D4F") if emp.fatigue >= 70 else Color("#00C6FF"),
			})
		"station":
			if not bs.stations.has(entity_id):
				return null
			var st: Dictionary = bs.stations[entity_id] as Dictionary
			accent = Color("#FFC857")
			var st_type: String = str(st.get("station_type", "teller"))
			var tex_p: String = "res://assets/environment/prop_desk_loan.png" if st_type == "loan_desk" else "res://assets/environment/prop_counter_teller.png"
			if ResourceLoader.exists(tex_p):
				icon_tex = load(tex_p) as Texture2D
			title_text = "%s (%s)" % [UiI18n.tr_key("UI_BUILD_ITEM_LOAN_DESK" if st_type == "loan_desk" else "UI_BUILD_ITEM_TELLER").trim_prefix("+"), entity_id]
			var is_open: bool = bool(st.get("is_open", true))
			var emp_id: String = str(st.get("assigned_employee_id", ""))
			var emp_name: String = UiI18n.tr_key("UI_EMP_POST_UNASSIGNED")
			if not emp_id.is_empty() and bs.employees.has(emp_id):
				emp_name = UiI18n.tr_person_name((bs.employees[emp_id] as EmployeeInstance).name_key)
			sub_text = "%s · %s" % [UiI18n.tr_key("UI_STATION_OPEN" if is_open else "UI_STATION_CLOSED"), emp_name]
			body_lines.append(UiI18n.tr_key("UI_CARD_STATION_EFFECT_LOAN" if st_type == "loan_desk" else "UI_CARD_STATION_EFFECT_TELLER"))
			extra_action = {
				"label": UiI18n.tr_key("UI_STATION_BTN_CLOSE" if is_open else "UI_STATION_BTN_OPEN"),
				"method": "toggle_station_open",
				"args": [entity_id],
			}
		"prop":
			if not bs.lobby_props.has(entity_id):
				return null
			var pr: Dictionary = bs.lobby_props[entity_id] as Dictionary
			var pt: String = str(pr.get("prop_type", "plant"))
			var eff_pcat: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
			var pspec: Dictionary = eff_pcat.get(pt, {}) as Dictionary
			var is_lux: bool = ContentStudioStoreScript.is_luxury_prop(pt)
			accent = Color("#FFC857") if is_lux else Color("#7FD8FF")
			var ptex_path: String = ""
			if not pspec.is_empty():
				ptex_path = str(pspec.get("tex_path", pspec.get("texture", "")))
			elif pt == "fountain":
				ptex_path = "res://assets/environment/prop_fountain_sheet.png"
			if not ptex_path.is_empty() and ResourceLoader.exists(ptex_path):
				icon_tex = load(ptex_path) as Texture2D
			title_text = _prop_display_name(pt)
			if is_lux:
				sub_text = UiI18n.tr_key("UI_BUILD_CAT_DECOR")
			else:
				sub_text = UiI18n.tr_key("UI_BUILD_CAT_FACILITIES")
			var custom_lore: String = str(pspec.get("lore", "")).strip_edges()
			var custom_stats: String = str(pspec.get("stats", "")).strip_edges()
			if not custom_lore.is_empty():
				body_lines.append(custom_lore)
			else:
				body_lines.append(UiI18n.tr_key("UI_PROP_LORE_" + pt.to_upper()))
			if not custom_stats.is_empty():
				body_lines.append(custom_stats)
			else:
				body_lines.append(UiI18n.tr_key("UI_PROP_STATS_" + pt.to_upper()))
		_:
			return null

	var card := _make_action_card_panel("EntityDetailCard_%s" % entity_id, accent)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 5)
	card.add_child(cv)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	cv.add_child(hdr)

	if icon_tex != null:
		var ic := TextureRect.new()
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.custom_minimum_size = Vector2(36.0, 36.0)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture = icon_tex
		hdr.add_child(ic)

	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 1)
	hdr.add_child(tv)

	var tl := Label.new()
	tl.theme_type_variation = &"LabelTitle"
	tl.add_theme_font_size_override("font_size", 13)
	tl.text = title_text
	tv.add_child(tl)

	if not sub_text.is_empty():
		var sl := Label.new()
		sl.theme_type_variation = &"LabelMuted"
		sl.add_theme_font_size_override("font_size", 11)
		sl.text = sub_text
		tv.add_child(sl)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(26.0, 26.0)
	close_btn.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		_selected_entity_type = &""
		_selected_entity_id = ""
		_action_cards_sig = ""
		_refresh_right_action_cards()
	)
	hdr.add_child(close_btn)

	if not tag_texts.is_empty():
		var tflow := HFlowContainer.new()
		tflow.add_theme_constant_override("h_separation", 4)
		tflow.add_theme_constant_override("v_separation", 4)
		for tt: String in tag_texts:
			var tp := PanelContainer.new()
			var tsb := StyleBoxFlat.new()
			tsb.bg_color = Color(0.10, 0.22, 0.38, 0.92)
			tsb.border_color = Color("#FFC857")
			tsb.set_border_width_all(1)
			tsb.set_corner_radius_all(4)
			tsb.content_margin_left = 5
			tsb.content_margin_right = 5
			tsb.content_margin_top = 1
			tsb.content_margin_bottom = 1
			tp.add_theme_stylebox_override("panel", tsb)
			var tlbl := Label.new()
			tlbl.add_theme_font_size_override("font_size", 11)
			tlbl.add_theme_color_override("font_color", Color("#FFE082"))
			tlbl.text = tt
			tp.add_child(tlbl)
			tflow.add_child(tp)
		cv.add_child(tflow)

	for bline: String in body_lines:
		var bl := Label.new()
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.add_theme_font_size_override("font_size", 12)
		bl.add_theme_color_override("font_color", Color("#DCE8FF"))
		bl.text = bline
		cv.add_child(bl)

	for binfo: Dictionary in bars:
		var blbl := Label.new()
		blbl.add_theme_font_size_override("font_size", 11)
		blbl.add_theme_color_override("font_color", Color("#BBD2F5"))
		blbl.text = str(binfo["label"])
		cv.add_child(blbl)
		var pb := ProgressBar.new()
		pb.min_value = 0.0
		pb.max_value = 100.0
		pb.value = float(binfo["value"])
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0.0, 8.0)
		var pfill := StyleBoxFlat.new()
		pfill.bg_color = binfo["color"] as Color
		pfill.set_corner_radius_all(3)
		pb.add_theme_stylebox_override("fill", pfill)
		cv.add_child(pb)

	if not extra_action.is_empty():
		var abtn := Button.new()
		abtn.theme_type_variation = &"ButtonPrimary"
		abtn.text = str(extra_action["label"])
		var mname: String = str(extra_action["method"])
		var margs: Array = extra_action["args"] as Array
		abtn.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_ui_click")
			if _sim_host != null:
				var cmd: Variant = _sim_host.get("command_service")
				if cmd != null and (cmd as Object).has_method(mname):
					var r: Variant = (cmd as Object).callv(mname, margs)
					_on_command_executed(r, "UI_INSPECTOR_TITLE")
		)
		cv.add_child(abtn)

	return card


func _build_resignation_card(entry: Dictionary, bs: BankState, ccy: String) -> PanelContainer:
	var eid: String = str(entry.get("employee_id", ""))
	if eid.is_empty() or not bs.employees.has(eid):
		return null
	var emp: EmployeeInstance = bs.employees[eid] as EmployeeInstance
	if emp == null:
		return null

	var card := _make_action_card_panel("ResignationCard_%s" % eid, Color("#FF5C5C"))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	card.add_child(cv)

	var tl := Label.new()
	tl.theme_type_variation = &"LabelTitle"
	tl.add_theme_font_size_override("font_size", 13)
	tl.add_theme_color_override("font_color", Color("#FF6B6B"))
	tl.text = UiI18n.tr_key("UI_RESIGN_CARD_TITLE", {"name": UiI18n.tr_person_name(emp.name_key)})
	cv.add_child(tl)

	var dl := Label.new()
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.add_theme_font_size_override("font_size", 11)
	dl.text = UiI18n.tr_key("UI_RESIGN_CARD_BODY", {
		"fatigue": emp.fatigue,
		"loyalty": int(entry.get("loyalty", emp.loyalty)),
	})
	cv.add_child(dl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	cv.add_child(row)

	var eid_copy: String = eid
	var btn_keep := Button.new()
	btn_keep.theme_type_variation = &"ButtonGold"
	btn_keep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_keep.text = UiI18n.tr_key("UI_RESIGN_BTN_RETAIN", {
		"cost": FormatService.format_money_compact(BalanceConfig.EMPLOYEE_RETAIN_BONUS_MINOR, ccy, false),
	})
	btn_keep.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_cash_chime")
		if _sim_host != null:
			var cmd: Variant = _sim_host.get("command_service")
			if cmd != null and (cmd as Object).has_method("resolve_employee_resignation"):
				var r: Variant = (cmd as Object).call("resolve_employee_resignation", eid_copy, "retain")
				_on_command_executed(r, "UI_RESIGN_RETAIN_OK")
	)
	row.add_child(btn_keep)

	var btn_let := Button.new()
	btn_let.theme_type_variation = &"ButtonDanger"
	btn_let.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_let.text = UiI18n.tr_key("UI_RESIGN_BTN_ACCEPT")
	btn_let.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		if _sim_host != null:
			var cmd: Variant = _sim_host.get("command_service")
			if cmd != null and (cmd as Object).has_method("resolve_employee_resignation"):
				var r: Variant = (cmd as Object).call("resolve_employee_resignation", eid_copy, "accept")
				_on_command_executed(r, "UI_RESIGN_ACCEPT_DONE")
	)
	row.add_child(btn_let)
	return card


func _prop_display_name(prop_type: String) -> String:
	var eff_cat: Dictionary = ContentStudioStoreScript.get_effective_build_catalog()
	if eff_cat.has(prop_type):
		var spec: Dictionary = eff_cat[prop_type] as Dictionary
		var cname: String = str(spec.get("name", "")).strip_edges()
		if not cname.is_empty():
			return cname
		return UiI18n.tr_key(str(spec.get("label_key", prop_type))).trim_prefix("+").strip_edges()
	if prop_type == "fountain":
		return UiI18n.tr_key("UI_PROP_NAME_FOUNTAIN")
	return prop_type


func _dept_name_key_for_card(dept_id: String) -> String:
	match dept_id:
		"core:department.operations":
			return "WORLD_DEPT_OPS_SHORT"
		"core:department.hr":
			return "WORLD_DEPT_HR_SHORT"
		"core:department.credit":
			return "WORLD_DEPT_CREDIT_SHORT"
		"core:department.risk":
			return "WORLD_DEPT_RISK_SHORT"
		_:
			return dept_id


func _format_inline_outcome_preview(item: Dictionary, defs: Dictionary) -> String:
	var pct: int = int(item.get("probability_pct", 100))
	var sentiment: String = str(item.get("sentiment", "mixed"))
	var tag_key: String = "UI_EVENT_SENTIMENT_MIXED"
	if sentiment == "positive":
		tag_key = "UI_EVENT_SENTIMENT_POS"
	elif sentiment == "negative":
		tag_key = "UI_EVENT_SENTIMENT_NEG"
	var header: String = "[%d%% %s]" % [pct, UiI18n.tr_key(tag_key)]
	var parts: Array[String] = []
	var impacts: Dictionary = item.get("domain_impacts", {}) as Dictionary
	var cash_d: int = int(impacts.get("cash_delta_minor", 0))
	if cash_d != 0:
		parts.append(UiI18n.tr_key("UI_EVENT_EFF_CASH", {
			"val": FormatService.format_money_compact(cash_d, "CNY", true)
		}))
	var sat_d: int = int(impacts.get("satisfaction_delta", 0))
	if sat_d != 0:
		parts.append(UiI18n.tr_key("UI_EVENT_EFF_SAT", {"val": ("%+d" % sat_d)}))
	var sp_d: int = int(impacts.get("strategy_points_delta", 0))
	if sp_d != 0:
		parts.append(UiI18n.tr_key("UI_EVENT_EFF_SP", {"val": ("%+d" % sp_d)}))
	var effs: Array = item.get("effects", []) as Array
	for raw_e in effs:
		if not (raw_e is Dictionary):
			continue
		var eff: Dictionary = raw_e as Dictionary
		var target: String = str(eff.get("target", ""))
		var val: int = int(eff.get("value", 0))
		if val == 0:
			continue
		match target:
			"bank.reputation_points":
				parts.append(UiI18n.tr_key("UI_EVENT_EFF_REP", {"val": ("%+d" % val)}))
			"customer.deposit_growth_bps":
				parts.append(UiI18n.tr_key("UI_EVENT_EFF_DEP", {"val": ("%+d%%" % (val / 100))}))
			"loan.default_risk_bps":
				parts.append(UiI18n.tr_key("UI_EVENT_EFF_RISK", {"val": ("%+d%%" % (val / 100))}))
			"staff.productivity_bps":
				parts.append(UiI18n.tr_key("UI_EVENT_EFF_PROD", {"val": ("%+d%%" % (val / 100))}))
			"service.teller_duration_bps":
				parts.append(UiI18n.tr_key("UI_EVENT_EFF_SPEED", {"val": ("%+d%%" % (-val / 100))}))
			"liquidity.required_buffer_bps":
				parts.append(UiI18n.tr_key("UI_EVENT_EFF_LIQ", {"val": ("%+d%%" % (val / 100))}))
	var next_id: String = str(item.get("next_event_id", ""))
	if not next_id.is_empty():
		var next_def: Dictionary = EventEngine._find_event_def(next_id, defs)
		var next_title: String = UiI18n.tr_key(str(next_def.get("title_key", next_id))) if not next_def.is_empty() else next_id
		parts.append(UiI18n.tr_key("UI_EVENT_EFF_CHAIN", {"next": next_title}))
	if parts.is_empty():
		var lkey: String = str(item.get("label_key", ""))
		return "%s %s" % [header, UiI18n.tr_key(lkey)] if not lkey.is_empty() else header
	return "%s %s" % [header, " / ".join(parts)]


func _exec_inline_event_option(inst_id: String, option_id: String) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd == null or not (cmd as Object).has_method("resolve_event_option"):
		return
	var r: Variant = (cmd as Object).call("resolve_event_option", inst_id, option_id)
	if r is Result and (r as Result).ok and (r as Result).data is Dictionary:
		var rd: Dictionary = (r as Result).data as Dictionary
		var out_key: String = str(rd.get("outcome_label_key", ""))
		var out_pct: int = int(rd.get("outcome_probability_pct", 100))
		var out_sent: String = str(rd.get("outcome_sentiment", "mixed"))
		if not out_key.is_empty():
			var sev: int = Enums.EventSeverity.WARNING if out_sent == "negative" else Enums.EventSeverity.INFO
			show_toast("UI_EVENT_RESULT_BANNER", {"pct": out_pct, "outcome": UiI18n.tr_key(out_key)}, sev)
			refresh_all()
			return
	_on_command_executed(r, "UI_EVENT_MODAL_TITLE")


func _exec_inline_loan_decision(approval_id: String, approve: bool) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd == null:
		return
	var method_name: String = "approve_loan" if approve else "reject_loan"
	var action_key: String = "UI_LOAN_BTN_APPROVE" if approve else "UI_LOAN_BTN_REJECT"
	if (cmd as Object).has_method(method_name):
		var r: Variant = (cmd as Object).call(method_name, approval_id)
		_on_command_executed(r, action_key)


func _on_domain_event_published(event_type: StringName, payload: Dictionary) -> void:
	var now_ms: int = Time.get_ticks_msec()
	match String(event_type):
		"DailySettlementCompleted", "daily_settlement_completed":
			UiI18n.play_sfx("sfx_day_complete")
			var rep: Variant = payload.get("report", {})
			if rep is Dictionary and _daily_report_overlay != null and _daily_report_overlay.has_method("show_report"):
				_daily_report_overlay.call("show_report", rep as Dictionary)
		"ServiceCompleted", "service_completed":
			if now_ms - _last_service_sfx_msec >= 320:
				_last_service_sfx_msec = now_ms
				UiI18n.play_sfx("sfx_cash_chime")
		"LobbyManagerAction":
			if str(payload.get("action", "")) == "atm_guide" and now_ms - _last_service_sfx_msec >= 320:
				_last_service_sfx_msec = now_ms
				UiI18n.play_sfx("sfx_cash_chime")
		"LoanApprovalRequested", "loan_approval_requested":
			UiI18n.play_sfx("sfx_event_alert")
		"EventTriggered", "event_triggered":
			UiI18n.play_sfx("sfx_event_alert")
		"EmployeeResignationRequested":
			UiI18n.play_sfx("sfx_event_alert")
		"CustomerAngryComplaint":
			show_toast("UI_TOAST_ANGRY_COMPLAINT", {}, Enums.EventSeverity.WARNING)
		"EventExpired", "event_expired":
			var exp_ev_id: String = str(payload.get("event_id", ""))
			var followup_id: String = str(payload.get("followup_event_id", ""))
			var defs_exp: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
			var exp_def: Dictionary = EventEngine._find_event_def(exp_ev_id, defs_exp)
			var exp_title: String = UiI18n.tr_key(str(exp_def.get("title_key", exp_ev_id))) if not exp_def.is_empty() else exp_ev_id
			if not followup_id.is_empty():
				show_toast("UI_EVENT_EXPIRED_FOLLOWUP_TOAST", {"title": exp_title}, Enums.EventSeverity.WARNING)
			else:
				show_toast("UI_EVENT_EXPIRED_TOAST", {"title": exp_title}, Enums.EventSeverity.INFO)
	_request_auto_refresh()


func _on_snapshot_changed() -> void:
	_request_auto_refresh()


func _request_auto_refresh() -> void:
	var cur_frame: int = Engine.get_process_frames()
	if cur_frame == _last_auto_refresh_frame:
		return
	_last_auto_refresh_frame = cur_frame
	refresh_all()


func _on_locale_changed(_new_locale: String) -> void:
	_action_cards_sig = ""
	_refresh_build_catalog_bar()
	refresh_all()


func refresh_all() -> void:
	for node in [_top_bar, _left_nav, _right_inspector, _bottom_bar]:
		if node != null and node.has_method("refresh"):
			node.call("refresh")
	_refresh_right_action_cards()
	for modal_node in [_daily_report_overlay, _loan_modal, _event_modal, _pause_modal]:
		if modal_node != null and modal_node.visible and modal_node.has_method("refresh"):
			modal_node.call("refresh")
	for did: StringName in _drawers.keys():
		var dnode: Control = _drawers[did] as Control
		if dnode != null and dnode.visible and dnode.has_method("refresh"):
			dnode.call("refresh")
