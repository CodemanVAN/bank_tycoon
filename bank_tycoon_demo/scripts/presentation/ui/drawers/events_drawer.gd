extends PanelContainer

## Events & Credit Underwriting Drawer.

signal close_requested()
signal command_executed(res: Variant, action_key: String)

var _sim_host: Node = null
var _lbl_title: Label = null
var _lbl_subtitle: Label = null
var _btn_close: Button = null
var _lbl_events_hdr: Label = null
var _events_box: VBoxContainer = null
var _lbl_loans_hdr: Label = null
var _loans_box: VBoxContainer = null
var _lbl_hist_hdr: Label = null
var _hist_box: VBoxContainer = null


func _ready() -> void:
	theme_type_variation = &"PanelLarge"
	_build_ui()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func bind(p_sim_host: Node) -> void:
	_sim_host = p_sim_host
	refresh()


func _on_locale_changed(_new_locale: String) -> void:
	refresh()


func _build_ui() -> void:
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	add_child(root_v)

	var hdr := HBoxContainer.new()
	root_v.add_child(hdr)

	var title_v := VBoxContainer.new()
	title_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_v)

	_lbl_title = Label.new()
	_lbl_title.theme_type_variation = &"LabelTitle"
	title_v.add_child(_lbl_title)

	_lbl_subtitle = Label.new()
	_lbl_subtitle.theme_type_variation = &"LabelMuted"
	title_v.add_child(_lbl_subtitle)

	_btn_close = Button.new()
	_btn_close.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		close_requested.emit()
	)
	hdr.add_child(_btn_close)

	root_v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	var body_v := VBoxContainer.new()
	body_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_v.add_theme_constant_override("separation", 10)
	scroll.add_child(body_v)

	_lbl_events_hdr = Label.new()
	_lbl_events_hdr.theme_type_variation = &"LabelTitle"
	body_v.add_child(_lbl_events_hdr)

	_events_box = VBoxContainer.new()
	_events_box.add_theme_constant_override("separation", 8)
	body_v.add_child(_events_box)

	body_v.add_child(HSeparator.new())

	_lbl_loans_hdr = Label.new()
	_lbl_loans_hdr.theme_type_variation = &"LabelTitle"
	body_v.add_child(_lbl_loans_hdr)

	_loans_box = VBoxContainer.new()
	_loans_box.add_theme_constant_override("separation", 8)
	body_v.add_child(_loans_box)

	body_v.add_child(HSeparator.new())

	_lbl_hist_hdr = Label.new()
	_lbl_hist_hdr.theme_type_variation = &"LabelTitle"
	body_v.add_child(_lbl_hist_hdr)

	_hist_box = VBoxContainer.new()
	_hist_box.add_theme_constant_override("separation", 4)
	body_v.add_child(_hist_box)


func refresh() -> void:
	if _lbl_title == null:
		return

	_lbl_title.text = UiI18n.tr_key("UI_DRAWER_EVENTS_TITLE")
	_lbl_subtitle.text = UiI18n.tr_key("UI_DRAWER_EVENTS_SUBTITLE")
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")
	_lbl_events_hdr.text = UiI18n.tr_key("UI_EVENT_MODAL_TITLE")
	_lbl_loans_hdr.text = UiI18n.tr_key("UI_LOAN_MODAL_TITLE")

	for box in [_events_box, _loans_box, _hist_box]:
		UiListRefresh.clear_children(box)

	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)
	var lc: String = UiI18n.get_locale()
	var ccy: String = bs.currency_code if bs != null else "CNY"

	# Active events
	var active_evs: Array = bs.active_events if bs != null else []
	if active_evs.is_empty():
		var el := Label.new()
		el.theme_type_variation = &"LabelMuted"
		el.text = UiI18n.tr_key("UI_EVENT_EMPTY")
		_events_box.add_child(el)
	else:
		for raw_ev in active_evs:
			if not (raw_ev is Dictionary):
				continue
			var inst: Dictionary = raw_ev as Dictionary
			var inst_id: String = str(inst.get("instance_id", inst.get("id", "")))
			var ev_id: String = str(inst.get("event_id", ""))
			var edef: Dictionary = EventEngine._find_event_def(ev_id, defs)

			var card := PanelContainer.new()
			card.theme_type_variation = &"PanelCard"
			_events_box.add_child(card)
			var cv := VBoxContainer.new()
			cv.add_theme_constant_override("separation", 6)
			card.add_child(cv)

			var tl := Label.new()
			tl.theme_type_variation = &"LabelTitle"
			tl.text = UiI18n.tr_key(str(edef.get("title_key", ev_id)))
			cv.add_child(tl)

			var dl := Label.new()
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.text = UiI18n.tr_key(str(edef.get("description_key", "")))
			cv.add_child(dl)

			var opts: Array = edef.get("options", []) as Array
			for raw_opt in opts:
				if not (raw_opt is Dictionary):
					continue
				var odef: Dictionary = raw_opt as Dictionary
				var oid: String = str(odef.get("id", ""))
				var obtn := Button.new()
				obtn.theme_type_variation = &"ButtonPrimary"
				obtn.text = UiI18n.tr_key(str(odef.get("label_key", oid)))
				var inst_copy: String = inst_id
				var oid_copy: String = oid
				obtn.pressed.connect(func() -> void:
					UiI18n.play_sfx("sfx_ui_click")
					_exec_cmd("resolve_event_option", [inst_copy, oid_copy], "UI_EVENT_MODAL_TITLE")
				)
				cv.add_child(obtn)

	# Pending loan approvals
	var pending_loans: Array = bs.pending_loan_approvals if bs != null else []
	var dept_svc := DepartmentService.new()
	var exact_unlocked: bool = dept_svc.is_capability_unlocked(bs, "exact_credit_score") if bs != null else false

	if pending_loans.is_empty():
		var ll := Label.new()
		ll.theme_type_variation = &"LabelMuted"
		ll.text = UiI18n.tr_key("UI_LOAN_EMPTY")
		_loans_box.add_child(ll)
	else:
		for raw_app in pending_loans:
			if not (raw_app is Dictionary):
				continue
			var app: Dictionary = raw_app as Dictionary
			var aid: String = str(app.get("approval_id", app.get("id", "")))
			var cust_id: String = str(app.get("customer_id", "cust_01"))
			var cust_type: String = str(app.get("customer_type", "borrower"))
			var principal: int = int(app.get("principal_minor", 600_000))
			var rate_bps: int = int(app.get("annual_rate_bps", bs.loan_base_rate_bps if bs != null else 650))
			var term_days: int = int(app.get("term_days", 30))
			var score: int = int(app.get("credit_score", 68))
			var grade: String = str(app.get("risk_grade", "B"))
			var pd_bps: int = int(app.get("estimated_pd_bps", 300))

			var card := PanelContainer.new()
			card.theme_type_variation = &"PanelCard"
			_loans_box.add_child(card)
			var cv := VBoxContainer.new()
			cv.add_theme_constant_override("separation", 4)
			card.add_child(cv)

			var bl := Label.new()
			bl.theme_type_variation = &"LabelTitle"
			bl.text = UiI18n.tr_key("UI_LOAN_BORROWER", {
				"customer": cust_id,
				"type": UiI18n.tr_customer_type(cust_type),
			})
			cv.add_child(bl)

			var tl := Label.new()
			tl.text = UiI18n.tr_key("UI_LOAN_TERMS", {
				"principal": FormatService.format_money(principal, ccy, false, lc),
				"rate": FormatService.format_bps(rate_bps),
				"days": term_days,
			})
			cv.add_child(tl)

			var rl := Label.new()
			if exact_unlocked:
				rl.text = UiI18n.tr_key("UI_LOAN_RISK_EXACT", {
					"score": score,
					"grade": grade,
					"pd": FormatService.format_bps(pd_bps),
				})
			else:
				rl.text = UiI18n.tr_key("UI_LOAN_RISK_BAND", {"grade": grade})
			cv.add_child(rl)

			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 8)
			cv.add_child(btn_row)

			var btn_app := Button.new()
			btn_app.theme_type_variation = &"ButtonPrimary"
			btn_app.text = UiI18n.tr_key("UI_LOAN_BTN_APPROVE")
			var aid_copy: String = aid
			btn_app.pressed.connect(func() -> void:
				UiI18n.play_sfx("sfx_loan_approve")
				_exec_cmd("approve_loan", [aid_copy], "UI_LOAN_BTN_APPROVE")
			)
			btn_row.add_child(btn_app)

			var btn_rej := Button.new()
			btn_rej.theme_type_variation = &"ButtonDanger"
			btn_rej.text = UiI18n.tr_key("UI_LOAN_BTN_REJECT")
			btn_rej.pressed.connect(func() -> void:
				UiI18n.play_sfx("sfx_loan_reject")
				_exec_cmd("reject_loan", [aid_copy], "UI_LOAN_BTN_REJECT")
			)
			btn_row.add_child(btn_rej)

	# Event History
	var hist: Array = bs.event_history if bs != null else []
	_lbl_hist_hdr.text = UiI18n.tr_key("UI_EVENT_HISTORY_HEADER", {"count": hist.size()})
	for raw_h in hist:
		if raw_h is Dictionary:
			var hd: Dictionary = raw_h as Dictionary
			var hl := Label.new()
			hl.theme_type_variation = &"LabelMuted"
			hl.text = "• D%d · %s (%s)" % [
				int(hd.get("day", 1)),
				str(hd.get("event_id", "")),
				str(hd.get("option_id", "")),
			]
			_hist_box.add_child(hl)


func _exec_cmd(method_name: String, args: Array, action_key: String) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd != null and (cmd as Object).has_method(method_name):
		var r: Variant = (cmd as Object).callv(method_name, args)
		command_executed.emit(r, action_key)
		refresh()
