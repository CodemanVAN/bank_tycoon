class_name StarwayTheme
extends RefCounted

## Starway Bank "Modern Tech Blue" UI theme (ADR-005).
## Tokens mirror art/02_tokens/design_tokens.css. Presentation-only; no game state here.
## Owner: hud worker. Other UI code should use these constants + type variations instead of
## hard-coding colors.

# --- Color tokens (design_tokens.css) ---
const BG_0: Color = Color("#081B36")        # Deep Space Navy - global base
const BG_1: Color = Color("#0B2D5B")        # Night Panel - panels / drawers
const BG_2: Color = Color("#263D5C")        # Slate - secondary containers
const BLUE_500: Color = Color("#1F6FEB")    # Tech Blue - primary buttons
const BLUE_400: Color = Color("#2D9CFF")    # Electric Blue - borders / focus
const CYAN_500: Color = Color("#00C6FF")    # Cyan Glow - highlights
const ICE_100: Color = Color("#BFE8FF")     # Ice Blue - light text
const WHITE: Color = Color("#F5F8FF")       # Cloud White - high-contrast text
const STEEL_500: Color = Color("#526B8D")   # Steel Blue - disabled / muted
const GOLD_500: Color = Color("#FFC857")    # Finance Gold - money / rewards
const GREEN_500: Color = Color("#35C978")   # Growth Green - positive
const RED_500: Color = Color("#E74C3C")     # Alert Coral - risk / loss
const VIOLET_500: Color = Color("#9B8CFF")  # Info Violet - special events

const PANEL_ALPHA: float = 0.92
const BORDER_COLOR: Color = Color(0.47, 0.745, 1.0, 0.48)  # rgba(120,190,255,.48)
const SHADOW_COLOR: Color = Color(0.0, 0.03, 0.094, 0.38)

const RADIUS_SM: int = 6
const RADIUS_MD: int = 10
const RADIUS_LG: int = 14

const FONT_SIZE_SMALL: int = 12
const FONT_SIZE_BODY: int = 14
const FONT_SIZE_VALUE: int = 16
const FONT_SIZE_TITLE: int = 18
const FONT_SIZE_HERO: int = 28

# --- Layout tokens (1280x720 logical canvas) ---
const TOP_BAR_HEIGHT: int = 56
const LEFT_NAV_WIDTH: int = 76
const RIGHT_INSPECTOR_WIDTH: int = 300
const BOTTOM_BAR_HEIGHT: int = 64

const UI_FONT_NAMES: PackedStringArray = [
	"Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC",
	"Noto Sans SC", "Yu Gothic UI", "Meiryo", "Segoe UI", "sans-serif",
]
const NUMERIC_FONT_NAMES: PackedStringArray = [
	"Bahnschrift", "Segoe UI", "Arial", "Microsoft YaHei UI", "sans-serif",
]


static func ui_font() -> Font:
	var f := SystemFont.new()
	f.font_names = UI_FONT_NAMES
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	return f


static func numeric_font() -> Font:
	var f := SystemFont.new()
	f.font_names = NUMERIC_FONT_NAMES
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return f


static func make_panel_style(
	bg: Color = BG_1,
	alpha: float = PANEL_ALPHA,
	radius: int = RADIUS_MD,
	border: Color = BORDER_COLOR,
	border_width: int = 1,
	padding: int = 10
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(bg.r, bg.g, bg.b, alpha)
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(padding)
	sb.shadow_color = SHADOW_COLOR
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb


static func make_button_style(bg: Color, border: Color, radius: int = RADIUS_SM) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.anti_aliasing = true
	return sb


## Returns the shared Theme. Apply it once on the root Control of each scene.
static func build() -> Theme:
	var t := Theme.new()
	t.default_font = ui_font()
	t.default_font_size = FONT_SIZE_BODY

	# Panels
	t.set_stylebox("panel", "Panel", make_panel_style())
	t.set_stylebox("panel", "PanelContainer", make_panel_style())
	_add_panel_variation(t, "PanelCard", make_panel_style(BG_2, 0.85, RADIUS_MD, BORDER_COLOR, 1, 10))
	_add_panel_variation(t, "PanelHeader", make_panel_style(BG_0, 0.96, RADIUS_SM, BORDER_COLOR, 1, 8))
	_add_panel_variation(t, "PanelLarge", make_panel_style(BG_1, 0.95, RADIUS_LG, BLUE_400, 1, 14))
	_add_panel_variation(t, "PanelBar", make_panel_style(BG_0, 0.94, 0, BORDER_COLOR, 1, 6))

	# Labels
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	_add_label_variation(t, "LabelTitle", ICE_100, FONT_SIZE_TITLE)
	_add_label_variation(t, "LabelHero", WHITE, FONT_SIZE_HERO)
	_add_label_variation(t, "LabelMuted", Color(ICE_100, 0.7), FONT_SIZE_SMALL)
	_add_label_variation(t, "LabelGold", GOLD_500, FONT_SIZE_VALUE)
	_add_label_variation(t, "LabelPositive", GREEN_500, FONT_SIZE_BODY)
	_add_label_variation(t, "LabelNegative", RED_500, FONT_SIZE_BODY)
	_add_label_variation(t, "LabelValue", WHITE, FONT_SIZE_VALUE)
	t.set_font("font", "LabelValue", numeric_font())
	t.set_font("font", "LabelGold", numeric_font())

	# Buttons (default = secondary steel-blue)
	t.set_stylebox("normal", "Button", make_button_style(BG_2, BORDER_COLOR))
	t.set_stylebox("hover", "Button", make_button_style(BG_2.lightened(0.12), CYAN_500))
	t.set_stylebox("pressed", "Button", make_button_style(BG_1, CYAN_500))
	t.set_stylebox("focus", "Button", make_button_style(Color(0, 0, 0, 0), CYAN_500))
	t.set_stylebox("disabled", "Button", make_button_style(Color(BG_2, 0.5), Color(STEEL_500, 0.5)))
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", WHITE)
	t.set_color("font_pressed_color", "Button", CYAN_500)
	t.set_color("font_disabled_color", "Button", STEEL_500)
	_add_button_variation(t, "ButtonPrimary", BLUE_500, BLUE_400)
	_add_button_variation(t, "ButtonDanger", RED_500.darkened(0.15), RED_500)
	_add_button_variation(t, "ButtonGold", GOLD_500.darkened(0.35), GOLD_500)
	_add_button_variation(t, "ButtonGhost", Color(0, 0, 0, 0), BORDER_COLOR)

	# Inputs / ranges / lists
	t.set_stylebox("normal", "LineEdit", make_button_style(BG_0, BORDER_COLOR))
	t.set_stylebox("focus", "LineEdit", make_button_style(BG_0, CYAN_500))
	t.set_color("font_color", "LineEdit", WHITE)
	t.set_stylebox("slider", "HSlider", make_button_style(BG_2, BORDER_COLOR, 3))
	t.set_stylebox("grabber_area", "HSlider", make_button_style(BLUE_500, BLUE_400, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", make_button_style(BLUE_400, CYAN_500, 3))
	var bg_prog := make_button_style(BG_0, BORDER_COLOR, 3)
	bg_prog.set_content_margin_all(0)
	var fill_prog := make_button_style(BLUE_400, BLUE_400, 3)
	fill_prog.set_content_margin_all(0)
	t.set_stylebox("background", "ProgressBar", bg_prog)
	t.set_stylebox("fill", "ProgressBar", fill_prog)
	t.set_color("font_color", "ProgressBar", WHITE)
	t.set_stylebox("panel", "TooltipPanel", make_panel_style(BG_0, 0.97, RADIUS_SM, BLUE_400, 1, 8))
	t.set_color("font_color", "TooltipLabel", WHITE)
	t.set_stylebox("panel", "PopupMenu", make_panel_style(BG_1, 0.98, RADIUS_SM, BLUE_400, 1, 6))
	t.set_stylebox("normal", "OptionButton", make_button_style(BG_2, BORDER_COLOR))
	t.set_stylebox("hover", "OptionButton", make_button_style(BG_2.lightened(0.12), CYAN_500))
	t.set_stylebox("pressed", "OptionButton", make_button_style(BG_1, CYAN_500))
	t.set_color("font_color", "OptionButton", WHITE)
	t.set_stylebox("tab_selected", "TabContainer", make_button_style(BLUE_500, BLUE_400))
	t.set_stylebox("tab_unselected", "TabContainer", make_button_style(BG_2, BORDER_COLOR))
	t.set_stylebox("tab_hovered", "TabContainer", make_button_style(BG_2.lightened(0.1), CYAN_500))
	t.set_stylebox("panel", "TabContainer", make_panel_style(BG_1, 0.0, RADIUS_SM, Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", WHITE)
	t.set_color("font_color", "RichTextLabel", WHITE)
	t.set_color("default_color", "RichTextLabel", WHITE)
	var sep := StyleBoxLine.new()
	sep.color = BORDER_COLOR
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)

	return t


static func _add_panel_variation(t: Theme, name: StringName, sb: StyleBox) -> void:
	t.set_type_variation(name, "PanelContainer")
	t.set_stylebox("panel", name, sb)


static func _add_label_variation(t: Theme, name: StringName, color: Color, size: int) -> void:
	t.set_type_variation(name, "Label")
	t.set_color("font_color", name, color)
	t.set_font_size("font_size", name, size)


static func _add_button_variation(t: Theme, name: StringName, bg: Color, border: Color) -> void:
	t.set_type_variation(name, "Button")
	t.set_stylebox("normal", name, make_button_style(bg, border))
	t.set_stylebox("hover", name, make_button_style(bg.lightened(0.15), CYAN_500))
	t.set_stylebox("pressed", name, make_button_style(bg.darkened(0.15), CYAN_500))
	t.set_stylebox("disabled", name, make_button_style(Color(bg, 0.35), Color(border, 0.35)))
	t.set_color("font_color", name, WHITE)
	t.set_color("font_hover_color", name, WHITE)


## Semantic color for signed money / deltas (never rely on color alone - pair with +/- text).
static func delta_color(value: int) -> Color:
	if value > 0:
		return GREEN_500
	if value < 0:
		return RED_500
	return ICE_100


static func build_theme() -> Theme:
	return build()


static func create_theme() -> Theme:
	return build()


func get_theme() -> Theme:
	return StarwayTheme.build()

