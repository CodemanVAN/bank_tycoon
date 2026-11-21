extends PanelContainer

## Random Event Decision Modal with Event Chain Indicator & Probabilistic Outcome Preview.

signal closed()
signal command_executed(res: Variant, action_key: String)

var _sim_host: Node = null
var _focus_instance_id: String = ""
var _lbl_title: Label = null
var _btn_close: Button = null
var _list_box: VBoxContainer = null
var _last_outcome_banner: Label = null

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
	_focus_instance_id = str(data.get("event_instance_id", ""))
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

	_last_outcome_banner = Label.new()
	_last_outcome_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_last_outcome_banner.visible = false
	root_v.add_child(_last_outcome_banner)

	root_v.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_v.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_list_box)


func refresh() -> void:
	if _lbl_title == null:
		return

	_lbl_title.text = UiI18n.tr_key("UI_EVENT_MODAL_TITLE")
	_btn_close.text = UiI18n.tr_key("UI_COMMON_CLOSE")

	if UiListRefresh.any_button_held(_list_box):
		_rebuild_pending = true
		return
	UiListRefresh.clear_children(_list_box)

	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var active_evs: Array = bs.active_events if bs != null else []
	var defs: Dictionary = UiI18n.get_effective_content_defs(_sim_host)

	if active_evs.is_empty():
		var empty_l := Label.new()
		empty_l.theme_type_variation = &"LabelMuted"
		empty_l.text = UiI18n.tr_key("UI_EVENT_EMPTY")
		_list_box.add_child(empty_l)
		return

	for raw_ev in active_evs:
		if not (raw_ev is Dictionary):
			continue
		var inst: Dictionary = raw_ev as Dictionary
		var inst_id: String = str(inst.get("instance_id", inst.get("id", "")))
		var ev_id: String = str(inst.get("event_id", ""))
		var edef: Dictionary = EventEngine._find_event_def(ev_id, defs)
		var meta: Dictionary = inst.get("metadata", {}) as Dictionary if inst.get("metadata") is Dictionary else {}
		var chain_id: String = str(edef.get("chain_id", ""))
		var source_ev: String = str(meta.get("source_event_id", ""))

		var card := PanelContainer.new()
		card.theme_type_variation = &"PanelCard"
		_list_box.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)

		var title_row := HBoxContainer.new()
		title_row.add_theme_constant_override("separation", 8)
		cv.add_child(title_row)

		var tl := Label.new()
		tl.theme_type_variation = &"LabelTitle"
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.text = UiI18n.tr_key(str(edef.get("title_key", ev_id)))
		title_row.add_child(tl)

		if not source_ev.is_empty() or not chain_id.is_empty():
			var chain_badge := Label.new()
			chain_badge.theme_type_variation = &"LabelGold"
			chain_badge.text = UiI18n.tr_key("UI_EVENT_CHAIN_FOLLOWUP") if not source_ev.is_empty() else UiI18n.tr_key("UI_EVENT_CHAIN_ARC")
			title_row.add_child(chain_badge)

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
			var opt_box := VBoxContainer.new()
			opt_box.add_theme_constant_override("separation", 4)
			cv.add_child(opt_box)

			var obtn := Button.new()
			obtn.theme_type_variation = &"ButtonPrimary"
			obtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			obtn.text = UiI18n.tr_key(str(odef.get("label_key", oid)))
			var inst_copy: String = inst_id
			var oid_copy: String = oid
			obtn.pressed.connect(func() -> void:
				UiI18n.play_sfx("sfx_ui_click")
				_exec_cmd("resolve_event_option", [inst_copy, oid_copy], "UI_EVENT_MODAL_TITLE")
			)
			opt_box.add_child(obtn)

			# Probabilistic outcome preview box (visible under option + emphasized on hover)
			var preview_panel := PanelContainer.new()
			var p_style := StyleBoxFlat.new()
			p_style.bg_color = Color(0.03, 0.10, 0.21, 0.78)
			p_style.border_color = Color("#1F6FEB")
			p_style.set_border_width_all(1)
			p_style.set_corner_radius_all(4)
			p_style.content_margin_left = 8
			p_style.content_margin_right = 8
			p_style.content_margin_top = 4
			p_style.content_margin_bottom = 4
			preview_panel.add_theme_stylebox_override("panel", p_style)
			opt_box.add_child(preview_panel)

			var pv := VBoxContainer.new()
			pv.add_theme_constant_override("separation", 2)
			preview_panel.add_child(pv)

			var previews: Array[Dictionary] = EventEngine.get_option_outcomes_preview(ev_id, odef)
			for item: Dictionary in previews:
				var line := Label.new()
				line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				line.add_theme_font_size_override("font_size", 12)
				var sentiment: String = str(item.get("sentiment", "mixed"))
				if sentiment == "positive":
					line.add_theme_color_override("font_color", Color("#35C978"))
				elif sentiment == "negative":
					line.add_theme_color_override("font_color", Color("#E74C3C"))
				else:
					line.add_theme_color_override("font_color", Color("#FFC857"))
				line.text = _format_outcome_preview(item, defs)
				pv.add_child(line)

			obtn.mouse_entered.connect(func() -> void:
				p_style.border_color = Color("#00C6FF")
				p_style.bg_color = Color(0.05, 0.16, 0.32, 0.94)
			)
			obtn.mouse_exited.connect(func() -> void:
				p_style.border_color = Color("#1F6FEB")
				p_style.bg_color = Color(0.03, 0.10, 0.21, 0.78)
			)

	UiListRefresh.watch_tree(_list_box, _on_list_button_up)


func _format_outcome_preview(item: Dictionary, defs: Dictionary) -> String:
	var pct: int = int(item.get("probability_pct", 100))
	var sentiment: String = str(item.get("sentiment", "mixed"))
	var tag_key: String = "UI_EVENT_SENTIMENT_MIXED"
	if sentiment == "positive":
		tag_key = "UI_EVENT_SENTIMENT_POS"
	elif sentiment == "negative":
		tag_key = "UI_EVENT_SENTIMENT_NEG"
	var header: String = "[%d%% %s]" % [pct, UiI18n.tr_key(tag_key)]
	var lkey: String = str(item.get("label_key", ""))
	if not lkey.is_empty():
		header += " " + UiI18n.tr_key(lkey)

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
		return header
	return "%s: %s" % [header, " / ".join(parts)]


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
		if r is Result and (r as Result).ok and (r as Result).data is Dictionary and _last_outcome_banner != null:
			var rd: Dictionary = (r as Result).data as Dictionary
			var out_key: String = str(rd.get("outcome_label_key", ""))
			var out_pct: int = int(rd.get("outcome_probability_pct", 100))
			var out_sent: String = str(rd.get("outcome_sentiment", "mixed"))
			if not out_key.is_empty():
				_last_outcome_banner.text = UiI18n.tr_key("UI_EVENT_RESULT_BANNER", {
					"pct": out_pct,
					"outcome": UiI18n.tr_key(out_key),
				})
				if out_sent == "positive":
					_last_outcome_banner.add_theme_color_override("font_color", Color("#35C978"))
				elif out_sent == "negative":
					_last_outcome_banner.add_theme_color_override("font_color", Color("#E74C3C"))
				else:
					_last_outcome_banner.add_theme_color_override("font_color", Color("#FFC857"))
				_last_outcome_banner.visible = true
		command_executed.emit(r, action_key)
		refresh.call_deferred()
