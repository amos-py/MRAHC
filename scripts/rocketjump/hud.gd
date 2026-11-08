## On-screen info: health, rockets, speed, timer, messages and the crosshair.
## Laid out in the project's 640x360 base resolution.
extends CanvasLayer

const RJ := preload("res://scripts/rocketjump/rj_constants.gd")

const W := 640.0
const H := 360.0

var _health_label: Label
var _ammo_label: Label
var _speed_label: Label
var _timer_label: Label
var _checkpoint_label: Label
var _message_label: Label
var _hint_label: Label
var _debug_label: Label
var _bars: Node2D
var _crosshair: Node2D

var _player: Node
var _message_time := 0.0
var show_debug := false


func _ready() -> void:
	layer = 10
	_bars = Node2D.new()
	_bars.draw.connect(_draw_bars)
	add_child(_bars)

	_health_label = _make_label(Vector2(12, H - 42), 22, HORIZONTAL_ALIGNMENT_LEFT, 160)
	_ammo_label = _make_label(Vector2(W - 172, H - 42), 22, HORIZONTAL_ALIGNMENT_RIGHT, 160)
	_speed_label = _make_label(Vector2(10, 6), 12, HORIZONTAL_ALIGNMENT_LEFT, 260)
	_timer_label = _make_label(Vector2(W * 0.5 - 100, 6), 18, HORIZONTAL_ALIGNMENT_CENTER, 200)
	_checkpoint_label = _make_label(Vector2(W - 210, 6), 12, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	_message_label = _make_label(Vector2(0, 92), 20, HORIZONTAL_ALIGNMENT_CENTER, W)
	_hint_label = _make_label(Vector2(0, H - 18), 9, HORIZONTAL_ALIGNMENT_CENTER, W)
	_hint_label.text = "A/D move · SPACE jump · CTRL/S crouch · LMB fire · R reload · Q checkpoint · ENTER restart · F3 debug"
	_debug_label = _make_label(Vector2(10, 40), 10, HORIZONTAL_ALIGNMENT_LEFT, 300)
	_debug_label.visible = false

	_crosshair = Node2D.new()
	_crosshair.draw.connect(_draw_crosshair)
	add_child(_crosshair)


func _make_label(pos: Vector2, font_size: int, align: HorizontalAlignment, width: float) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, font_size + 8)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	l.add_theme_color_override("font_outline_color", Color.WHITE)
	l.add_theme_constant_override("outline_size", maxi(3, font_size / 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func bind_player(p: Node) -> void:
	_player = p


func show_message(text: String, seconds := 2.5) -> void:
	_message_label.text = text
	_message_time = seconds


func refresh(delta: float, run_time: float, running: bool, checkpoint: int, checkpoint_count: int, best: float) -> void:
	_crosshair.position = _crosshair.get_global_mouse_position()
	_crosshair.queue_redraw()
	if _player == null:
		return

	_health_label.text = "%d" % ceili(_player.health)
	_ammo_label.text = "%d / %d" % [_player.clip, RJ.CLIP_SIZE]

	var v: Vector2 = _player.velocity
	_speed_label.text = "speed %4d   vertical %+5d" % [roundi(absf(v.x)), roundi(-v.y)]

	var t := _format_time(run_time)
	if best > 0.0:
		t += "   (best %s)" % _format_time(best)
	_timer_label.text = t
	_timer_label.modulate = Color(1, 1, 1) if running else Color(0.2, 0.6, 0.2)

	_checkpoint_label.text = "checkpoint %d / %d" % [checkpoint, checkpoint_count]

	if _message_time > 0.0:
		_message_time -= delta
		_message_label.modulate.a = clampf(_message_time * 2.0, 0.0, 1.0)
	else:
		_message_label.text = ""

	_debug_label.visible = show_debug
	if show_debug:
		_debug_label.text = "on ground: %s\ncrouched: %s (transition %s)\nair crouches used: %d\nair control: %.2fx\nfall speed: %d\nlast damage: %.1f" % [
			_player.on_ground, _player.ducked, _player.ducking, _player.air_duck_count,
			_player.surface_friction, roundi(_player.fall_velocity), _player.last_damage]

	_bars.queue_redraw()


static func _format_time(t: float) -> String:
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%06.3f" % [m, s]


func _draw_bars() -> void:
	if _player == null:
		return
	# Health bar
	var frac := clampf(_player.health / RJ.MAX_HEALTH, 0.0, 1.0)
	var hb := Rect2(12, H - 16, 120, 6)
	_bars.draw_rect(hb, Color(1, 1, 1, 0.8))
	var col := Color(0.2, 0.7, 0.25) if frac > 0.5 else (Color(0.95, 0.65, 0.1) if frac > 0.25 else Color(0.9, 0.15, 0.1))
	_bars.draw_rect(Rect2(hb.position, Vector2(hb.size.x * frac, hb.size.y)), col)
	_bars.draw_rect(hb, Color.BLACK, false, 1.0)

	# Rocket pips + reload progress
	for i in RJ.CLIP_SIZE:
		var r := Rect2(W - 12 - (RJ.CLIP_SIZE - i) * 16, H - 16, 12, 6)
		var filled: bool = i < _player.clip
		_bars.draw_rect(r, Color(0.9, 0.35, 0.1) if filled else Color(1, 1, 1, 0.8))
		if not filled and i == _player.clip and _player.reloading:
			var p: float = _player.reload_progress()
			_bars.draw_rect(Rect2(r.position, Vector2(r.size.x * p, r.size.y)), Color(0.9, 0.35, 0.1, 0.5))
		_bars.draw_rect(r, Color.BLACK, false, 1.0)


func _draw_crosshair() -> void:
	var c := Color.BLACK
	_crosshair.draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 20, Color.WHITE, 3.0)
	_crosshair.draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 20, c, 1.2)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_crosshair.draw_line(d * 9.0, d * 14.0, Color.WHITE, 3.0)
		_crosshair.draw_line(d * 9.0, d * 14.0, c, 1.2)
