## Swept-box collision against the solid cells of a TileMap.
##
## Movement does its own collision (instead of CharacterBody2D) so that sliding,
## stepping and ground checks behave exactly like the hull traces the movement
## model expects: a trace returns how far the box got (fraction), where it
## stopped, and the normal of the surface it hit.
extends RefCounted

const RJ := preload("res://scripts/rocketjump/rj_constants.gd")

const TraceResult := preload("res://scripts/rocketjump/trace_result.gd")

const INSIDE_TOLERANCE := 0.001

var tile_size := 16.0
var _solid := {}


func build_from_tilemap(tilemap: TileMap, layer := 0) -> void:
	_solid.clear()
	tile_size = float(tilemap.tile_set.tile_size.x) if tilemap.tile_set else 16.0
	for cell in tilemap.get_used_cells(layer):
		_solid[cell] = true


func is_solid_cell(cell: Vector2i) -> bool:
	return _solid.has(cell)


func is_solid_point(p: Vector2) -> bool:
	return _solid.has(Vector2i(floori(p.x / tile_size), floori(p.y / tile_size)))


## Sweep a point (line trace) from start to end.
func trace_line(start: Vector2, end: Vector2) -> TraceResult:
	return trace_box(start, end, Vector2.ZERO, Vector2.ZERO)


## Sweep an axis-aligned box. `mins`/`maxs` are the box corners relative to the
## origin (e.g. (-24,-82) and (24,0) for a standing player). The returned end
## position stays DIST_EPSILON away from whatever was hit.
func trace_box(start: Vector2, end: Vector2, mins: Vector2, maxs: Vector2) -> TraceResult:
	var tr := TraceResult.new()
	var delta := end - start

	var lo := Vector2(minf(start.x, end.x), minf(start.y, end.y)) + mins - Vector2.ONE
	var hi := Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + maxs + Vector2.ONE
	var c0 := Vector2i(floori(lo.x / tile_size), floori(lo.y / tile_size))
	var c1 := Vector2i(floori(hi.x / tile_size), floori(hi.y / tile_size))

	var best_t := 2.0
	var best_n := Vector2.ZERO
	var best_axis_len := 0.0

	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			if not _solid.has(Vector2i(cx, cy)):
				continue
			# Tile expanded by the box (Minkowski sum) -> trace the origin as a point.
			var bmin := Vector2(cx * tile_size - maxs.x, cy * tile_size - maxs.y)
			var bmax := Vector2((cx + 1) * tile_size - mins.x, (cy + 1) * tile_size - mins.y)

			if start.x > bmin.x + INSIDE_TOLERANCE and start.x < bmax.x - INSIDE_TOLERANCE \
					and start.y > bmin.y + INSIDE_TOLERANCE and start.y < bmax.y - INSIDE_TOLERANCE:
				tr.start_solid = true
				tr.fraction = 0.0
				tr.end_pos = start
				return tr

			var t_enter := -INF
			var t_exit := INF
			var n := Vector2.ZERO
			var axis_len := 0.0
			var blocked := true

			for axis in 2:
				var s: float = start[axis]
				var d: float = delta[axis]
				var lo_b: float = bmin[axis]
				var hi_b: float = bmax[axis]
				var enter := -INF
				var exit := INF
				if s <= lo_b + INSIDE_TOLERANCE:
					# On the low side of this slab (outside or touching).
					if d <= 0.0:
						blocked = false
						break
					enter = maxf((lo_b - s) / d, 0.0)
					exit = (hi_b - s) / d
				elif s >= hi_b - INSIDE_TOLERANCE:
					if d >= 0.0:
						blocked = false
						break
					enter = maxf((hi_b - s) / d, 0.0)
					exit = (lo_b - s) / d
				elif d > 0.0:
					exit = (hi_b - s) / d
				elif d < 0.0:
					exit = (lo_b - s) / d
				if enter > t_enter:
					t_enter = enter
					n = Vector2.ZERO
					n[axis] = -signf(d)
					axis_len = absf(d)
				t_exit = minf(t_exit, exit)

			if not blocked or t_enter == -INF:
				continue
			if t_enter > t_exit or t_enter > 1.0 or t_exit <= 0.0:
				continue
			if t_enter < best_t:
				best_t = t_enter
				best_n = n
				best_axis_len = axis_len

	if best_t > 1.0:
		tr.fraction = 1.0
		tr.end_pos = end
		return tr

	# Back off so we rest DIST_EPSILON in front of the surface.
	var f := best_t
	if best_axis_len > 0.0:
		f = maxf(0.0, best_t - RJ.DIST_EPSILON / best_axis_len)
	tr.fraction = f
	tr.end_pos = start + delta * f
	tr.normal = best_n
	return tr
