class_name FinanceChart
extends Control

## Custom Control._draw() daily revenue, expense, and net profit chart (Starway Modern Tech-Blue).

var _points: Array[Dictionary] = []


func _ready() -> void:
	custom_minimum_size = Vector2(360, 170)


func set_series(points: Array[Dictionary]) -> void:
	_points = points.duplicate(true)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x < 40.0 or rect.size.y < 40.0:
		return

	# Chart frame & background
	draw_rect(rect, StarwayTheme.BG_0, true)
	draw_rect(rect, StarwayTheme.BORDER_COLOR, false, 1.0)

	var pad_left: float = 16.0
	var pad_right: float = 16.0
	var pad_top: float = 20.0
	var pad_bottom: float = 24.0
	var plot := Rect2(
		pad_left,
		pad_top,
		maxf(10.0, rect.size.x - pad_left - pad_right),
		maxf(10.0, rect.size.y - pad_top - pad_bottom)
	)

	# Horizontal grid lines
	for i in range(5):
		var gy: float = plot.position.y + (plot.size.y * float(i) / 4.0)
		draw_line(
			Vector2(plot.position.x, gy),
			Vector2(plot.end.x, gy),
			Color(StarwayTheme.STEEL_500.r, StarwayTheme.STEEL_500.g, StarwayTheme.STEEL_500.b, 0.28),
			1.0
		)

	var data: Array[Dictionary] = _points
	if data.is_empty():
		data = [
			{"day": 1, "income": 15000, "expense": 20000, "net": -5000},
		]

	var max_abs: int = 50_000
	for pt in data:
		max_abs = maxi(max_abs, absi(int(pt.get("income", 0))))
		max_abs = maxi(max_abs, absi(int(pt.get("expense", 0))))
		max_abs = maxi(max_abs, absi(int(pt.get("net", 0))))

	var mid_y: float = plot.position.y + plot.size.y * 0.55
	var scale_h: float = plot.size.y * 0.42
	draw_line(
		Vector2(plot.position.x, mid_y),
		Vector2(plot.end.x, mid_y),
		Color(StarwayTheme.BLUE_400.r, StarwayTheme.BLUE_400.g, StarwayTheme.BLUE_400.b, 0.5),
		1.0
	)

	var count: int = data.size()
	var step_x: float = plot.size.x / float(maxi(1, count))
	var income_pts := PackedVector2Array()
	var expense_pts := PackedVector2Array()

	var fnt: Font = StarwayTheme.numeric_font()
	for i in range(count):
		var item: Dictionary = data[i]
		var cx: float = plot.position.x + step_x * (float(i) + 0.5)
		var inc_v: float = float(int(item.get("income", 0))) / float(max_abs)
		var exp_v: float = float(int(item.get("expense", 0))) / float(max_abs)
		var net_v: float = float(int(item.get("net", 0))) / float(max_abs)

		# Net profit bar
		var bar_w: float = clampf(step_x * 0.36, 6.0, 24.0)
		var net_y: float = mid_y - net_v * scale_h
		var bar_top: float = minf(mid_y, net_y)
		var bar_h: float = maxf(2.0, absf(net_y - mid_y))
		var bar_col: Color = StarwayTheme.GREEN_500 if net_v >= 0.0 else StarwayTheme.RED_500
		draw_rect(Rect2(cx - bar_w * 0.5, bar_top, bar_w, bar_h), Color(bar_col.r, bar_col.g, bar_col.b, 0.65), true)

		var inc_pt := Vector2(cx, mid_y - inc_v * scale_h)
		var exp_pt := Vector2(cx, mid_y - exp_v * scale_h)
		income_pts.append(inc_pt)
		expense_pts.append(exp_pt)

		draw_circle(inc_pt, 3.0, StarwayTheme.CYAN_500)
		draw_circle(exp_pt, 3.0, StarwayTheme.GOLD_500)

		if fnt != null:
			var day_lbl: String = "D%d" % int(item.get("day", i + 1))
			draw_string(fnt, Vector2(cx - 10.0, rect.size.y - 6.0), day_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, StarwayTheme.ICE_100)

	if income_pts.size() >= 2:
		draw_polyline(income_pts, StarwayTheme.CYAN_500, 2.0, true)
	if expense_pts.size() >= 2:
		draw_polyline(expense_pts, StarwayTheme.GOLD_500, 2.0, true)
