class_name IsoGrid
extends RefCounted

## Axis-aligned orthographic logical grid (18x12 lobby, 32x32 square tiles) with
## AStarGrid2D 4-way navigation. The class name is kept for API/save compatibility.
## The projection is deliberately NOT 2:1 isometric any more: every sprite in this
## project (floor diamonds, wall panels, ATM/counter/sofa props, characters) is a
## front-facing rectangle, so the world uses one shared front-view square grid and the
## 32x16 diamond floor art is un-projected into 32x32 squares at render time.
## GRID_WIDTH x GRID_HEIGHT is the initial lobby; the navigable site extends SITE_MARGIN
## cells in every direction so departments can be built outside the current floor plan.

const GRID_WIDTH: int = 18
const GRID_HEIGHT: int = 12
const SITE_MARGIN: int = 6
const SITE_REGION: Rect2i = Rect2i(
	-SITE_MARGIN,
	-SITE_MARGIN,
	GRID_WIDTH + SITE_MARGIN * 2,
	GRID_HEIGHT + SITE_MARGIN * 2
)
const TILE_WIDTH: int = 32
const TILE_HEIGHT: int = 16
## Orthographic cell pitch. The diamond art is 32x16; un-projecting it yields a
## 32x32 square, so one logical cell is exactly one square tile wide and tall.
const TILE_SIZE: int = 32
const HALF_TILE_W: float = 16.0
const HALF_TILE_H: float = 8.0
## Centres the 18x12 lobby on the default camera (604, 338) at 2x zoom.
const DEFAULT_ORIGIN_OFFSET: Vector2 = Vector2(332.0, 162.0)

var origin_offset: Vector2 = DEFAULT_ORIGIN_OFFSET
var _astar: AStarGrid2D = null


func _init(p_origin_offset: Vector2 = DEFAULT_ORIGIN_OFFSET) -> void:
	origin_offset = p_origin_offset
	_astar = AStarGrid2D.new()
	_astar.region = SITE_REGION
	_astar.cell_size = Vector2(1.0, 1.0)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()


func is_in_bounds(cell: Vector2i) -> bool:
	return SITE_REGION.has_point(cell)


func is_lobby_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_WIDTH and cell.y >= 0 and cell.y < GRID_HEIGHT


func clamp_to_bounds(cell: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(cell.x, SITE_REGION.position.x, SITE_REGION.end.x - 1),
		clampi(cell.y, SITE_REGION.position.y, SITE_REGION.end.y - 1)
	)


func grid_to_screen(cell: Vector2i) -> Vector2:
	# One axis-aligned square per cell; grid_to_screen returns the CELL CENTRE.
	return Vector2(
		float(cell.x) * float(TILE_SIZE) + origin_offset.x,
		float(cell.y) * float(TILE_SIZE) + origin_offset.y
	)


func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	# Strict inverse of grid_to_screen (round-trip safe for every integer cell).
	return Vector2i(
		roundi((screen_pos.x - origin_offset.x) / float(TILE_SIZE)),
		roundi((screen_pos.y - origin_offset.y) / float(TILE_SIZE))
	)


func set_solid(cell: Vector2i, solid: bool = true) -> void:
	if not is_in_bounds(cell):
		return
	_astar.set_point_solid(cell, solid)


func set_cell_solid(cell: Vector2i, solid: bool = true) -> void:
	set_solid(cell, solid)


func is_solid(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return true
	return _astar.is_point_solid(cell)


func is_cell_solid(cell: Vector2i) -> bool:
	return is_solid(cell)


func clear_solids() -> void:
	_astar.fill_solid_region(_astar.region, false)


func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if not is_in_bounds(from_cell) or not is_in_bounds(to_cell):
		return empty
	if is_solid(from_cell) or is_solid(to_cell):
		return empty
	if from_cell == to_cell:
		var single: Array[Vector2i] = [from_cell]
		return single
	var path: Array[Vector2i] = _astar.get_id_path(from_cell, to_cell, false)
	if path.is_empty():
		return empty
	if path[path.size() - 1] != to_cell:
		return empty
	return path


func compute_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	return find_path(from_cell, to_cell)


func get_grid_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	return find_path(from_cell, to_cell)


func find_path_or_adjacent(from_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	var start: Vector2i = clamp_to_bounds(from_cell)
	if is_solid(start):
		start = _find_nearest_open_cell(start)
	var dest: Vector2i = clamp_to_bounds(target_cell)
	if is_solid(dest):
		dest = _find_nearest_open_cell(dest)
	var direct: Array[Vector2i] = find_path(start, dest)
	if not direct.is_empty():
		return direct
	var fallback: Array[Vector2i] = [start]
	if dest != start:
		fallback.append(dest)
	return fallback


func _find_nearest_open_cell(origin: Vector2i) -> Vector2i:
	if is_in_bounds(origin) and not is_solid(origin):
		return origin
	var dirs: Array[Vector2i] = [
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(1, 1),
		Vector2i(-1, 1),
		Vector2i(1, -1),
		Vector2i(-1, -1),
	]
	for radius in range(1, 5):
		for d in dirs:
			var candidate: Vector2i = origin + d * radius
			if is_in_bounds(candidate) and not is_solid(candidate):
				return candidate
	return clamp_to_bounds(origin)
