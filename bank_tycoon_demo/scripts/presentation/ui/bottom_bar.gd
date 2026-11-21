extends PanelContainer

## Starway Bank Bottom HUD Bar: Live Operations Feed, Loan Approval & Event Badges, Camera Zoom Controls.

signal loan_modal_requested()
signal event_modal_requested()
signal zoom_step_requested(step: int)

var _sim_host: Node = null
var _lbl_feed_title: Label = null
var _lbl_feed_text: Label = null
var _btn_loans: Button = null
var _btn_events: Button = null
var _lbl_zoom: Label = null
var _btn_zoom_1: Button = null
var _btn_zoom_2: Button = null
var _btn_zoom_3: Button = null


func _ready() -> void:
	theme_type_variation = &"PanelBar"
	_build_ui()
	UiI18n.connect_locale_changed(self, &"_on_locale_changed")
	refresh()


func bind(p_sim_host: Node) -> void:
	_sim_host = p_sim_host
	refresh()


func _on_locale_changed(_new_locale: String) -> void:
	refresh()


func _build_ui() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_lbl_feed_title = Label.new()
	_lbl_feed_title.theme_type_variation = &"LabelTitle"
	row.add_child(_lbl_feed_title)

	_lbl_feed_text = Label.new()
	_lbl_feed_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_feed_text.clip_text = true
	row.add_child(_lbl_feed_text)

	_btn_loans = Button.new()
	_btn_loans.icon = UiI18n.load_icon("icon_loan")
	_btn_loans.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		loan_modal_requested.emit()
	)
	row.add_child(_btn_loans)

	_btn_events = Button.new()
	_btn_events.icon = UiI18n.load_icon("icon_events")
	_btn_events.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		event_modal_requested.emit()
	)
	row.add_child(_btn_events)

	row.add_child(VSeparator.new())

	_lbl_zoom = Label.new()
	_lbl_zoom.theme_type_variation = &"LabelMuted"
	row.add_child(_lbl_zoom)

	_btn_zoom_1 = _make_zoom_btn(row, 1, "UI_BOTTOM_ZOOM_1X")
	_btn_zoom_2 = _make_zoom_btn(row, 2, "UI_BOTTOM_ZOOM_2X")
	_btn_zoom_3 = _make_zoom_btn(row, 3, "UI_BOTTOM_ZOOM_3X")


func _make_zoom_btn(parent: Node, step: int, key: String) -> Button:
	var b := Button.new()
	b.set_meta("label_key", key)
	b.pressed.connect(func() -> void:
		UiI18n.play_sfx("sfx_ui_click")
		zoom_step_requested.emit(step)
	)
	parent.add_child(b)
	return b


func refresh() -> void:
	if _lbl_feed_title == null:
		return

	var bs: BankState = _sim_host.get("bank_state") as BankState if _sim_host != null else null
	var loan_cnt: int = bs.pending_loan_approvals.size() if bs != null else 0
	var ev_cnt: int = bs.active_events.size() if bs != null else 0

	_lbl_feed_title.text = UiI18n.tr_key("UI_BOTTOM_LOG_TITLE")
	_lbl_feed_text.text = UiI18n.tr_key("UI_BOTTOM_LOG_READY")

	_btn_loans.text = UiI18n.tr_key("UI_BOTTOM_LOAN_BADGE", {"count": loan_cnt})
	_btn_loans.theme_type_variation = &"ButtonGold" if loan_cnt > 0 else &""

	_btn_events.text = UiI18n.tr_key("UI_BOTTOM_EVENT_BADGE", {"count": ev_cnt})
	_btn_events.theme_type_variation = &"ButtonPrimary" if ev_cnt > 0 else &""

	_lbl_zoom.text = UiI18n.tr_key("UI_BOTTOM_ZOOM_LABEL")
	_btn_zoom_1.text = UiI18n.tr_key("UI_BOTTOM_ZOOM_1X")
	_btn_zoom_2.text = UiI18n.tr_key("UI_BOTTOM_ZOOM_2X")
	_btn_zoom_3.text = UiI18n.tr_key("UI_BOTTOM_ZOOM_3X")
