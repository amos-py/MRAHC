## Short-lived explosion flash + smoke. Purely visual.
extends Node2D

const RJ := preload("res://scripts/rocketjump/rj_constants.gd")
const DURATION := 0.45

var _age := 0.0
var _puffs: Array[Vector3] = []   # x, y = direction * distance, z = size


func _ready() -> void:
	z_index = 5
	for i in 9:
		var a := randf() * TAU
		_puffs.append(Vector3(cos(a) * randf_range(10, 40), sin(a) * randf_range(10, 40), randf_range(10, 22)))


func _process(delta: float) -> void:
	_age += delta
	if _age >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := _age / DURATION
	var ease_out := 1.0 - pow(1.0 - t, 3.0)
	# Faint ring showing the blast radius that can push you.
	draw_arc(Vector2.ZERO, RJ.ROCKET_SELF_RADIUS * ease_out, 0.0, TAU, 48,
			Color(0.0, 0.0, 0.0, 0.25 * (1.0 - t)), 2.0)
	for p in _puffs:
		var d := Vector2(p.x, p.y) * (0.6 + ease_out)
		draw_circle(d, p.z * (0.6 + 0.8 * t), Color(0.45, 0.45, 0.45, 0.6 * (1.0 - t)))
	var r := 18.0 + 40.0 * ease_out
	draw_circle(Vector2.ZERO, r, Color(1.0, 0.55, 0.1, 0.85 * (1.0 - t)))
	draw_circle(Vector2.ZERO, r * 0.55, Color(1.0, 0.92, 0.45, 0.9 * (1.0 - t)))
