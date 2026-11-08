## A rocket: flies in a straight line at constant speed and bursts on the first
## solid tile it touches. Simulated on the course's fixed tick.
extends Node2D

const RJ := preload("res://scripts/rocketjump/rj_constants.gd")
const TileWorld := preload("res://scripts/rocketjump/tile_world.gd")

const TRAIL_LENGTH := 14

var world: TileWorld
var course: Node
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var vel := Vector2.ZERO
var life := 0.0
var alive := true
var _trail: Array[Vector2] = []


func setup(p_course: Node, p_world: TileWorld, start: Vector2, velocity: Vector2) -> void:
	course = p_course
	world = p_world
	pos = start
	prev_pos = start
	vel = velocity
	position = start
	rotation = vel.angle()


func sim_tick() -> void:
	if not alive:
		return
	prev_pos = pos
	life += RJ.TICK
	var next := pos + vel * RJ.TICK
	var tr := world.trace_line(pos, next)
	if tr.did_hit():
		alive = false
		pos = tr.end_pos
		course.explode(tr.end_pos + tr.normal * 1.0)
		course.remove_rocket(self)
		return
	pos = next
	_trail.push_front(pos)
	if _trail.size() > TRAIL_LENGTH:
		_trail.pop_back()
	if life > RJ.ROCKET_LIFETIME:
		alive = false
		course.remove_rocket(self)


func update_visual(alpha: float) -> void:
	position = prev_pos.lerp(pos, alpha)
	rotation = vel.angle()
	queue_redraw()


func _draw() -> void:
	# Smoke trail (drawn in world space, so undo our own transform).
	var inv := get_global_transform().affine_inverse()
	for i in _trail.size():
		var t := float(i) / TRAIL_LENGTH
		var c := Color(0.55, 0.55, 0.55, 0.45 * (1.0 - t))
		draw_circle(inv * _trail[i], 3.0 + 5.0 * t, c)
	# Flame
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -4), Vector2(-20, 0), Vector2(-8, 4)]),
			Color(1.0, 0.55, 0.1))
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -2), Vector2(-14, 0), Vector2(-8, 2)]),
			Color(1.0, 0.9, 0.3))
	# Body
	draw_rect(Rect2(-8, -4, 14, 8), Color(0.25, 0.27, 0.3))
	draw_colored_polygon(PackedVector2Array([Vector2(6, -4), Vector2(12, 0), Vector2(6, 4)]),
			Color(0.8, 0.15, 0.1))
	draw_rect(Rect2(-8, -4, 14, 8), Color.BLACK, false, 1.5)
