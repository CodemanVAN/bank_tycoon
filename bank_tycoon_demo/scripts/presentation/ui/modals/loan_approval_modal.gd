extends PanelContainer

## Credit Underwriting & Loan Approval Modal.

signal closed()
signal command_executed(res: Variant, action_key: String)

var _sim_host: Node = null
var _focus_approval_id: String = ""
var _lbl_title: Label = null
var _btn_close: Button = null
var _list_box: VBoxContainer = null

var _list_signature: String = ""
var _rebuild_pending: bool = false


func _ready() -> void:
	theme_type_variation = &"PanelLarge"
	_build_ui()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func bind(p_sim_host: Node) -> void:
	_sim_host = p_sim_host
	refresh()


func open_with(data: Dictionary = {}) -> void:
	_focus_approval_id = str(data.get("approval_id", ""))
	visible = true
	refresh()


func _on_locale_changed(_new_locale: String) -> void:
	refresh()


func _build_ui() -> void:
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	add_child(root_v)

	var hdr := HBoxContainer.new()
	root_v.add_child(hdr)

	_lbl_title = Label.new()
	_lbl_title.theme_type_variation = &"LabelTitle"
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(_lbl_title)

	_btn_close = Button.new()
	_btn_close.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		visible = false
		closed.emit()
	)
	hdr.add_child(_btn_close)

	root_v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)


func refresh() -> void:
	if _lbl_title == null:
		return

	_lbl_title.text = UiI18n.tr_key("UI_LOAN_MODAL_TITLE")
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")

	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var pending: Array = bs.pending_loan_approvals if bs != null else []
	var dept_svc := DepartmentService.new()
	var exact_unlocked: bool = dept_svc.is_capability_unlocked(bs, "exact_credit_score") if bs != null else false
	var lc: String = UiI18n.get_locale()
	var ccy: String = bs.currency_code if bs != null else "CNY"

	# Only rebuild when the pending queue really changed; a rebuild between press and
	# release destroyed the pressed Button and swallowed the first click.
	var sig_parts: Array = [lc, ccy, exact_unlocked]
	for raw_app_sig: Variant in pending:
		if raw_app_sig is Dictionary:
			var app_sig: Dictionary = raw_app_sig as Dictionary
			sig_parts.append("%s:%d:%d:%d:%d:%s" % [
				str(app_sig.get("approval_id", app_sig.get("id", ""))),
				int(app_sig.get("principal_minor", 0)),
				int(app_sig.get("annual_rate_bps", 0)),
				int(app_sig.get("term_days", 0)),
				int(app_sig.get("credit_score", 0)),
				str(app_sig.get("risk_grade", "")),
			])
	var new_sig: String = UiListRefresh.signature(sig_parts)
	if new_sig == _list_signature and _list_box.get_child_count() > 0:
		return
	if UiListRefresh.any_button_held(_list_box):
		_rebuild_pending = true
		return
	_list_signature = new_sig
	UiListRefresh.clear_children(_list_box)

	if pending.is_empty():
		var empty_l := Label.new()
		empty_l.theme_type_variation = &"LabelMuted"
		empty_l.text = UiI18n.tr_key("UI_LOAN_EMPTY")
		_list_box.add_child(empty_l)
		return

	for raw_app in pending:
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
		_list_box.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 5)
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
		UiListRefresh.watch_release(btn_app, _on_list_button_up)
		btn_row.add_child(btn_app)

		var btn_rej := Button.new()
		btn_rej.theme_type_variation = &"ButtonDanger"
		btn_rej.text = UiI18n.tr_key("UI_LOAN_BTN_REJECT")
		btn_rej.pressed.connect(func() -> void:
			UiI18n.play_sfx("sfx_loan_reject")
			_exec_cmd("reject_loan", [aid_copy], "UI_LOAN_BTN_REJECT")
		)
		UiListRefresh.watch_release(btn_rej, _on_list_button_up)
		btn_row.add_child(btn_rej)


func _on_list_button_up() -> void:
	if not _rebuild_pending:
		return
	_rebuild_pending = false
	refresh.call_deferred()


func _exec_cmd(method_name: String, args: Array, action_key: String) -> void:
	if _sim_host == null:
		return
	var cmd: Variant = _sim_host.get("command_service")
	if cmd != null and (cmd as Object).has_method(method_name):
		var r: Variant = (cmd as Object).callv(method_name, args)
		command_executed.emit(r, action_key)
		refresh.call_deferred()
