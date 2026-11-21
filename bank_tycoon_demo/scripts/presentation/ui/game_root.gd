extends Control

## Starway Bank Main Gameplay Root Scene Controller.
## Owns SimulationHost, BankWorldContainer/BankWorld, and HUDLayer (TopBar, LeftNavigation,
## RightInspector, BottomBar, DrawerContainer, ModalContainer, DailyReportOverlay, ToastBar).

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
var _last_auto_refresh_frame: int = -1


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

	# ModalShield blocks clicks outside an open modal. Hook visibility_changed (not
	# just the `closed` signal) so every close path - close button, open_pause_modal
	# toggle, or a direct visible = false - re-opens mouse picking for the HUD.
	for modal_node in [_loan_modal, _event_modal, _pause_modal, _daily_report_overlay]:
		var mctl: Control = modal_node as Control
		if mctl == null:
			continue
		var cb_vis := Callable(self, &"_sync_modal_shield")
		if not mctl.is_connected("visibility_changed", cb_vis):
			mctl.connect("visibility_changed", cb_vis)


func _any_modal_open() -> bool:
	for modal_node in [_loan_modal, _event_modal, _pause_modal, _daily_report_overlay]:
		if not is_instance_valid(modal_node):
			continue
		var mctl: Control = modal_node as Control
		if mctl != null and mctl.visible:
			return true
	return false


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


func _on_zoom_step_requested(step: int) -> void:
	if _bank_world != null and _bank_world.has_method("set_camera_zoom_step"):
		_bank_world.call("set_camera_zoom_step", step)


func _on_command_executed(res: Variant, action_key: String) -> void:
	if _toast_bar != null and _toast_bar.has_method("show_command_result"):
		_toast_bar.call("show_command_result", res, action_key)
	refresh_all()


func _on_domain_event_published(event_type: StringName, payload: Dictionary) -> void:
	var cur_frame: int = Engine.get_process_frames()
	match String(event_type):
		"daily_settlement_completed":
			UiI18n.play_sfx("sfx_day_complete")
			var rep: Variant = payload.get("report", {})
			if rep is Dictionary and _daily_report_overlay != null and _daily_report_overlay.has_method("show_report"):
				_daily_report_overlay.call("show_report", rep as Dictionary)
		"service_completed":
			if cur_frame != _last_auto_refresh_frame:
				if int(payload.get("fee_minor", 0)) > 0 or int(payload.get("amount_minor", 0)) > 0:
					UiI18n.play_sfx("sfx_cash_chime")
		"event_triggered":
			UiI18n.play_sfx("sfx_event_alert")
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
	refresh_all()


func refresh_all() -> void:
	for node in [_top_bar, _left_nav, _right_inspector, _bottom_bar]:
		if node != null and node.has_method("refresh"):
			node.call("refresh")
	for modal_node in [_daily_report_overlay, _loan_modal, _event_modal, _pause_modal]:
		if modal_node != null and modal_node.visible and modal_node.has_method("refresh"):
			modal_node.call("refresh")
	for did: StringName in _drawers.keys():
		var dnode: Control = _drawers[did] as Control
		if dnode != null and dnode.visible and dnode.has_method("refresh"):
			dnode.call("refresh")
