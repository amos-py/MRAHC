## Rocket-jump course: builds the level, runs the fixed-tick simulation,
## handles checkpoints, spikes, the finish flag, the camera and the HUD.
##
## If the TileMap child already has painted tiles, those are used as the level
## instead of the built-in course (checkpoints/spikes below then won't match,
## so edit COURSE_* to fit your own layout).
extends Node2D

const RJ := preload("res://scripts/rocketjump/rj_constants.gd")
const TileWorld := preload("res://scripts/rocketjump/tile_world.gd")
const PlayerScript := preload("res://scripts/rocketjump/rj_player.gd")
const RocketScript := preload("res://scripts/rocketjump/rocket.gd")
const ExplosionFx := preload("res://scripts/rocketjump/explosion_fx.gd")
const HudScript := preload("res://scripts/rocketjump/hud.gd")

const SAVE_PATH := "user://rocketjump.cfg"
const CAMERA_ZOOM := 0.6
const KILL_Y := 600.0

## Solid blocks in tile coordinates, inclusive: [x0, y0, x1, y1].
## Row 0 is the first row below the starting floor; negative rows are above it.
## One tile is 16 units, the player is 48 x 82 (crouched 48 x 62).
const COURSE_SOLIDS := [
	[-14, -100, -11, 5],  # left boundary
	[-10, 0, 219, 5],     # ground
	[14, -2, 19, -1],     # A: 32 tall -> plain jump (jump height ~50)
	[30, -4, 35, -1],     # B: 64 tall -> crouch-jump (~72)
	[54, -17, 69, -1],    # C: 272 tall -> any rocket jump
	[96, -17, 113, -1],   # D: across a 416 wide spike pit
	[114, -45, 127, -1],  # E: 448 above D -> crouched rocket jump (~600 max)
	[128, -85, 149, -1],  # W: 640 above E -> rocket jump + wall rocket
	[190, -63, 215, -1],  # X: finish, 640 across and 352 below W
	[216, -100, 219, 5],  # right boundary
]

## Spike strips in world units: Rect2(x, y, w, h).
const COURSE_SPIKES := [
	Rect2(1120, -20, 416, 20),
	Rect2(2400, -20, 640, 20),
]

## Checkpoint flags (feet position on top of a platform). Index 0 = start.
const COURSE_CHECKPOINTS := [
	Vector2(40, 0),
	Vector2(1040, -272),
	Vector2(1600, -272),
	Vector2(1900, -720),
	Vector2(2130, -1360),
]
const COURSE_GOAL := Vector2(3200, -1008)

const COURSE_SIGNS := [
	[Vector2(-120, -200), "A / D to run, SPACE to jump"],
	[Vector2(170, -250), "Hold CTRL or S while jumping\nto crouch-jump higher"],
	[Vector2(560, -360), "LEFT CLICK fires a rocket.\nRocket jump: JUMP + CROUCH +\nshoot at your feet, all at once"],
	[Vector2(860, -500), "Aim down and BEHIND you\nto fly across the gap"],
	[Vector2(1540, -520), "Crouched blasts push harder.\nThis one needs a crouched rocket jump"],
	[Vector2(1830, -980), "Too high for one rocket:\nrocket jump up the wall, then\nshoot it steeply below you\nas soon as you can fire again"],
	[Vector2(2060, -1620), "Long jump to the flag.\nAim down-behind at about 45 degrees"],
	[Vector2(3120, -1200), "FINISH"],
]

var world := TileWorld.new()
var tilemap: TileMap
var player: PlayerScript
var camera: Camera2D
var hud: HudScript
var props: Node2D
var backdrop: Node2D
var rocket_layer: Node2D
var fx_layer: Node2D

var rockets: Array = []
var checkpoint_index := 0
var checkpoint_reached: Array[bool] = []
var run_time := 0.0
var running := true
var finished := false
var best_time := 0.0

var _accum := 0.0
var _pending_respawn := ""
var _shake := 0.0
var _level_bounds := Rect2()


func _ready() -> void:
	_ensure_inputs()
	_setup_tilemap()
	world.build_from_tilemap(tilemap)

	backdrop = Node2D.new()
	backdrop.z_index = -10
	backdrop.draw.connect(_draw_backdrop)
	add_child(backdrop)
	move_child(backdrop, 0)

	props = Node2D.new()
	props.draw.connect(_draw_props)
	add_child(props)

	_make_signs()

	rocket_layer = Node2D.new()
	add_child(rocket_layer)

	player = PlayerScript.new()
	player.world = world
	player.course = self
	player.died.connect(_on_player_died)
	add_child(player)

	fx_layer = Node2D.new()
	fx_layer.z_index = 5
	add_child(fx_layer)

	camera = Camera2D.new()
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	add_child(camera)
	camera.make_current()

	hud = HudScript.new()
	add_child(hud)
	hud.bind_player(player)

	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_load_best()
	restart_run()


# =============================================================================
# Setup
# =============================================================================

func _ensure_inputs() -> void:
	_ensure_keys("Left", [KEY_A, KEY_LEFT])
	_ensure_keys("Right", [KEY_D, KEY_RIGHT])
	_ensure_keys("Jump", [KEY_SPACE])
	_ensure_keys("Crouch", [KEY_CTRL, KEY_S, KEY_DOWN])
	_ensure_keys("Reload", [KEY_R])
	_ensure_keys("Respawn", [KEY_Q, KEY_BACKSPACE])
	_ensure_keys("Restart", [KEY_ENTER, KEY_KP_ENTER])
	_ensure_keys("DebugInfo", [KEY_F3])
	_ensure_mouse("Fire", MOUSE_BUTTON_LEFT)
	_ensure_mouse("Jump", MOUSE_BUTTON_WHEEL_DOWN)  # Scroll-jump for bunny hops.


## Adds the action if missing and makes sure each key is bound to it.
func _ensure_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var existing := {}
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			existing[ev.physical_keycode] = true
			existing[ev.keycode] = true
	for k in keys:
		if existing.has(k):
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _ensure_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and ev.button_index == button:
			return
	var mb := InputEventMouseButton.new()
	mb.button_index = button
	InputMap.action_add_event(action, mb)


func _setup_tilemap() -> void:
	tilemap = get_node_or_null("TileMap") as TileMap
	if tilemap == null:
		tilemap = TileMap.new()
		tilemap.name = "TileMap"
		add_child(tilemap)
	tilemap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if tilemap.tile_set == null:
		tilemap.tile_set = _make_tileset()
	if tilemap.get_used_cells(0).is_empty():
		_build_course()
	var used := tilemap.get_used_rect()
	var ts := float(tilemap.tile_set.tile_size.x)
	_level_bounds = Rect2(Vector2(used.position) * ts, Vector2(used.size) * ts)


func _make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = preload("res://art/Tiles/grungeTileset.png")
	src.texture_region_size = Vector2i(16, 16)
	for y in 2:
		for x in 8:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	return ts


func _build_course() -> void:
	var cells := {}
	for r in COURSE_SOLIDS:
		for y in range(r[1], r[3] + 1):
			for x in range(r[0], r[2] + 1):
				cells[Vector2i(x, y)] = true
	for c in cells:
		var cell: Vector2i = c
		var top := not cells.has(cell + Vector2i(0, -1))
		var atlas := Vector2i(2 + posmod(cell.x, 6), 0 if top else 1)
		tilemap.set_cell(0, cell, 0, atlas)


func _make_signs() -> void:
	for s in COURSE_SIGNS:
		var l := Label.new()
		l.text = s[1]
		l.position = s[0]
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08))
		l.add_theme_color_override("font_outline_color", Color.WHITE)
		l.add_theme_constant_override("outline_size", 8)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_time = float(cfg.get_value("times", "best", 0.0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("times", "best", best_time)
	cfg.save(SAVE_PATH)


# =============================================================================
# Run control
# =============================================================================

func restart_run() -> void:
	checkpoint_index = 0
	checkpoint_reached.clear()
	for i in COURSE_CHECKPOINTS.size():
		checkpoint_reached.append(i == 0)
	run_time = 0.0
	running = true
	finished = false
	_respawn_player()
	camera.position = player.origin + Vector2(0, -60)
	camera.reset_smoothing()
	props.queue_redraw()


func _respawn_player() -> void:
	_clear_rockets()
	var spot: Vector2 = COURSE_CHECKPOINTS[checkpoint_index]
	player.respawn(spot + Vector2(0.0, -1.0))


func _clear_rockets() -> void:
	for r in rockets:
		r.queue_free()
	rockets.clear()


func _on_player_died(reason: String) -> void:
	_pending_respawn = "Splat! Mind the fall damage." if reason == "fall" else "Too many rockets to the face."


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Respawn"):
		_respawn_player()
	elif event.is_action_pressed("Restart"):
		restart_run()
	elif event.is_action_pressed("DebugInfo"):
		hud.show_debug = not hud.show_debug
		player.debug_draw = hud.show_debug
		player.queue_redraw()


# =============================================================================
# Simulation
# =============================================================================

func _process(delta: float) -> void:
	_accum += minf(delta, RJ.TICK * RJ.MAX_TICKS_PER_FRAME)
	var ticks := 0
	while _accum >= RJ.TICK and ticks < RJ.MAX_TICKS_PER_FRAME:
		_accum -= RJ.TICK
		_tick()
		ticks += 1

	var alpha := _accum / RJ.TICK
	player.update_visual(alpha, delta)
	for r in rockets:
		r.update_visual(alpha)
	_update_camera(delta)
	hud.refresh(delta, run_time, running, checkpoint_index, COURSE_CHECKPOINTS.size() - 1, best_time)


func _tick() -> void:
	if running:
		run_time += RJ.TICK
	player.sim_tick()
	for r in rockets.duplicate():
		r.sim_tick()
	_check_triggers()
	if _pending_respawn != "":
		hud.show_message(_pending_respawn)
		_pending_respawn = ""
		_respawn_player()


func spawn_rocket(at: Vector2, velocity: Vector2) -> void:
	var r := RocketScript.new()
	r.setup(self, world, at, velocity)
	rocket_layer.add_child(r)
	rockets.append(r)


func remove_rocket(r: Node) -> void:
	rockets.erase(r)
	r.queue_free()


func explode(at: Vector2) -> void:
	player.apply_self_blast(at)
	var fx := ExplosionFx.new()
	fx.position = at
	fx_layer.add_child(fx)
	var d: float = at.distance_to(player.world_center())
	_shake = maxf(_shake, clampf(1.0 - d / 600.0, 0.0, 1.0) * 6.0)


func _check_triggers() -> void:
	var box: Rect2 = player.hull_rect()

	for i in COURSE_CHECKPOINTS.size():
		var p: Vector2 = COURSE_CHECKPOINTS[i]
		var zone := Rect2(p.x - 48.0, p.y - 160.0, 96.0, 162.0)
		if not zone.intersects(box):
			continue
		player.resupply()  # Standing at a flag refills health and rockets.
		if i > checkpoint_index:
			checkpoint_index = i
			checkpoint_reached[i] = true
			hud.show_message("Checkpoint %d" % i, 1.5)
			props.queue_redraw()

	var goal_zone := Rect2(COURSE_GOAL.x - 48.0, COURSE_GOAL.y - 160.0, 96.0, 162.0)
	if not finished and goal_zone.intersects(box):
		finished = true
		running = false
		var msg := "Finished in %s!" % HudScript._format_time(run_time)
		if best_time <= 0.0 or run_time < best_time:
			best_time = run_time
			_save_best()
			msg += "  New best!"
		hud.show_message(msg + "\nPress ENTER to run it again", 6.0)
		props.queue_redraw()

	for s in COURSE_SPIKES:
		var spikes: Rect2 = s
		if spikes.intersects(box):
			_pending_respawn = "Spikes! Back to the checkpoint."
			return
	if player.origin.y > KILL_Y:
		_pending_respawn = "Out of bounds."


# =============================================================================
# Camera & drawing
# =============================================================================

func _update_camera(delta: float) -> void:
	var vp := get_viewport()
	var screen_off := vp.get_mouse_position() - vp.get_visible_rect().size * 0.5
	var look := (screen_off / CAMERA_ZOOM * 0.3).limit_length(220.0)
	var target: Vector2 = player.position + Vector2(0.0, -60.0) + look
	camera.position = camera.position.lerp(target, 1.0 - exp(-10.0 * delta))
	_shake = maxf(0.0, _shake - delta * 20.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake


func _draw_backdrop() -> void:
	var r := _level_bounds.grow(800.0)
	var step := 64.0
	var col := Color(0.0, 0.0, 0.0, 0.06)
	var x := floorf(r.position.x / step) * step
	while x < r.end.x:
		backdrop.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), col, 1.0)
		x += step
	var y := floorf(r.position.y / step) * step
	while y < r.end.y:
		backdrop.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), col, 1.0)
		y += step


func _draw_props() -> void:
	# Spikes
	for s in COURSE_SPIKES:
		var rect: Rect2 = s
		var x := rect.position.x
		while x < rect.end.x - 1.0:
			var w := minf(16.0, rect.end.x - x)
			var tri := PackedVector2Array([
				Vector2(x, rect.end.y), Vector2(x + w * 0.5, rect.position.y), Vector2(x + w, rect.end.y)])
			props.draw_colored_polygon(tri, Color.WHITE)
			props.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2]]), Color.BLACK, 2.0)
			x += 16.0

	# Checkpoint flags
	for i in range(1, COURSE_CHECKPOINTS.size()):
		var p: Vector2 = COURSE_CHECKPOINTS[i]
		var fill := Color(0.3, 0.75, 0.35) if checkpoint_reached[i] else Color.WHITE
		_draw_flag(p, fill)

	# Finish flag (checkered)
	var g := COURSE_GOAL
	props.draw_line(g, g + Vector2(0, -120), Color.BLACK, 4.0)
	for row in 3:
		for col in 5:
			var c := Color.BLACK if (row + col) % 2 == 0 else Color.WHITE
			props.draw_rect(Rect2(g.x + 2 + col * 10, g.y - 120 + row * 10, 10, 10), c)
	props.draw_rect(Rect2(g.x + 2, g.y - 120, 50, 30), Color.BLACK, false, 2.0)
	if finished:
		props.draw_circle(g + Vector2(0, -124), 6.0, Color(0.3, 0.75, 0.35))


func _draw_flag(p: Vector2, fill: Color) -> void:
	props.draw_line(p, p + Vector2(0, -110), Color.BLACK, 4.0)
	var tri := PackedVector2Array([p + Vector2(2, -110), p + Vector2(44, -96), p + Vector2(2, -82)])
	props.draw_colored_polygon(tri, fill)
	props.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color.BLACK, 2.0)
