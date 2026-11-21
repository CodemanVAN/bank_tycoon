class_name EmployeeRadarChart
extends Control

## 6-Axis Radar Chart visualizing an employee's operational attributes (0..100).

var _labels: Array[String] = ["专业", "效率", "社交", "风控", "管理", "忠诚"]
var _values: Array[int] = [50, 50, 50, 50, 50, 50]
var _boosted: Array[bool] = [false, false, false, false, false, false]


func _init() -> void:
	custom_minimum_size = Vector2(256.0, 156.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_axes(labels: Array, values: Array, boosted: Array = []) -> void:
	_labels.clear()
	for l: Variant in labels:
		_labels.append(str(l))
	_values.clear()
	for v: Variant in values:
		_values.append(int(v))
	_boosted.clear()
	for b: Variant in boosted:
		_boosted.append(bool(b))
	queue_redraw()


func _draw() -> void:
	var n: int = mini(_labels.size(), _values.size())
	if n < 3:
		return

	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x * 0.27, size.y * 0.34)
	if radius < 18.0:
		return

	# Concentric polygon grid rings (33%, 66%, 100%)
	for ring_idx in range(1, 4):
		var frac: float = float(ring_idx) / 3.0
		var ring_pts := PackedVector2Array()
		for i in range(n):
			var ang: float = -PI * 0.5 + TAU * float(i) / float(n)
			ring_pts.append(center + Vector2(cos(ang), sin(ang)) * (radius * frac))
		ring_pts.append(ring_pts[0])
		var ring_col: Color = Color(0.24, 0.45, 0.72, 0.55 if ring_idx == 3 else 0.32)
		draw_polyline(ring_pts, ring_col, 1.0, true)

	# Radial axes
	for i in range(n):
		var ang: float = -PI * 0.5 + TAU * float(i) / float(n)
		var outer: Vector2 = center + Vector2(cos(ang), sin(ang)) * radius
		draw_line(center, outer, Color(0.24, 0.45, 0.72, 0.35), 1.0, true)

	# Value polygon
	var val_pts := PackedVector2Array()
	for i in range(n):
		var ang: float = -PI * 0.5 + TAU * float(i) / float(n)
		var v: float = clampf(float(_values[i]) / 100.0, 0.08, 1.0)
		val_pts.append(center + Vector2(cos(ang), sin(ang)) * (radius * v))

	draw_colored_polygon(val_pts, Color(0.0, 0.78, 1.0, 0.30))
	var outline_pts := PackedVector2Array(val_pts)
	outline_pts.append(val_pts[0])
	draw_polyline(outline_pts, Color("#00C6FF"), 2.0, true)

	# Vertex dots & axis labels
	var font: Font = ThemeDB.fallback_font
	var fsize: int = 11
	for i in range(n):
		var is_boosted: bool = i < _boosted.size() and _boosted[i]
		draw_circle(val_pts[i], 3.0, Color("#FFC857") if is_boosted else Color("#00E5FF"))

		var ang: float = -PI * 0.5 + TAU * float(i) / float(n)
		var dir := Vector2(cos(ang), sin(ang))
		var label_pos: Vector2 = center + dir * (radius + 14.0)
		var txt: String = "%s %d" % [_labels[i], _values[i]]
		var tsize: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)

		var draw_x: float = label_pos.x - tsize.x * 0.5
		if dir.x > 0.35:
			draw_x = label_pos.x - 4.0
		elif dir.x < -0.35:
			draw_x = label_pos.x - tsize.x + 4.0
		var draw_y: float = label_pos.y + tsize.y * 0.32
		if dir.y < -0.7:
			draw_y = label_pos.y + 2.0
		elif dir.y > 0.7:
			draw_y = label_pos.y + tsize.y * 0.65

		draw_x = clampf(draw_x, 2.0, maxf(2.0, size.x - tsize.x - 2.0))
		draw_y = clampf(draw_y, float(fsize), size.y - 2.0)

		var lcol: Color = Color("#FFC857") if is_boosted else Color("#DCE8FF")
		draw_string(font, Vector2(draw_x, draw_y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, lcol)
