## Rocket-jumping player.
##
## Movement runs on a fixed 66.67 Hz tick driven by the course (see course.gd)
## and follows the classic Source movement loop:
##   ground check -> crouch -> half gravity -> jump -> friction + walk / air move
##   -> ground check -> half gravity -> fall damage
## The node's position is only the interpolated *visual* position; the real
## simulation state is `origin` (bottom-centre of the hitbox) and `velocity`.
extends Node2D

const RJ := preload("res://scripts/rocketjump/rj_constants.gd")
const TileWorld := preload("res://scripts/rocketjump/tile_world.gd")
const TraceResult := preload("res://scripts/rocketjump/trace_result.gd")

const IDLE_FRAMES := [
	preload("res://art/Characters/skulkerIdle/skulkerIdle1.png"),
	preload("res://art/Characters/skulkerIdle/skulkerIdle2.png"),
	preload("res://art/Characters/skulkerIdle/skulkerIdle3.png"),
	preload("res://art/Characters/skulkerIdle/skulkerIdle4.png"),
]
const WALK_FRAMES := [
	preload("res://art/Characters/skulkerWalk/skulkerWalk1.png"),
	preload("res://art/Characters/skulkerWalk/skulkerWalk2.png"),
	preload("res://art/Characters/skulkerWalk/skulkerWalk3.png"),
	preload("res://art/Characters/skulkerWalk/skulkerWalk4.png"),
	preload("res://art/Characters/skulkerWalk/skulkerWalk5.png"),
	preload("res://art/Characters/skulkerWalk/skulkerWalk6.png"),
	preload("res://art/Characters/skulkerWalk/skulkerWalk7.png"),
	preload("res://art/Characters/skulkerWalk/skulkerWalk8.png"),
]
const JUMP_FRAMES := [
	preload("res://art/Characters/skulkerJump/skulkerJump1.png"),
	preload("res://art/Characters/skulkerJump/skulkerJump2.png"),
	preload("res://art/Characters/skulkerJump/skulkerJump3.png"),
]
const FALL_FRAMES := [
	preload("res://art/Characters/skulkerFall/skulkerFall1.png"),
	preload("res://art/Characters/skulkerFall/skulkerFall2.png"),
]
## The figure in the 32x32 frames is 30 px tall; scale it to the 82 u hull.
const SPRITE_SCALE := RJ.HULL_HEIGHT / 30.0

signal died(reason: String)
signal fired

var world: TileWorld
var course: Node   # Provides spawn_rocket(); set by the course.

# --- Simulation state --------------------------------------------------------
var origin := Vector2.ZERO
var prev_origin := Vector2.ZERO
var velocity := Vector2.ZERO
var on_ground := false
var surface_friction := 1.0
var fall_velocity := 0.0
var sim_time := 0.0

var ducked := false          ## Using the crouched hull.
var ducking := false         ## In a crouch/uncrouch transition.
var duck_time_ms := 0.0      ## Counts down from 1000 during transitions.
var air_duck_count := 0
var duck_lockout_until := 0.0
var _speed_cropped := false

var aim_dir := Vector2.RIGHT
var facing := 1

var health := RJ.MAX_HEALTH
var clip := RJ.CLIP_SIZE
var next_attack_time := 0.0
var reloading := false
var reload_done_time := 0.0
var reload_started_time := 0.0

# Buttons as they were on the previous tick (a jump needs a fresh press).
var _jump_last := false
var _duck_last := false
# Presses that happened between ticks, so quick taps are never lost.
var _jump_latch := false
var _duck_latch := false
var _fire_latch := false
var _reload_latch := false

var debug_draw := false
var last_damage := 0.0
var last_damage_time := -10.0

var _sprite: AnimatedSprite2D
var _launcher: Node2D
var _hurt_flash := 0.0


func _ready() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _build_frames()
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_sprite.play("Idle")

	_launcher = Node2D.new()
	_launcher.z_index = 1
	_launcher.draw.connect(_draw_launcher)
	add_child(_launcher)


func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	var anims := [
		["Idle", IDLE_FRAMES, 7.0, true],
		["Walk", WALK_FRAMES, 12.0, true],
		["Jump", JUMP_FRAMES, 10.0, false],
		["Fall", FALL_FRAMES, 5.0, true],
	]
	for a in anims:
		frames.add_animation(a[0])
		frames.set_animation_speed(a[0], a[2])
		frames.set_animation_loop(a[0], a[3])
		for tex in a[1]:
			frames.add_frame(a[0], tex)
	return frames


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Jump"):
		_jump_latch = true
	if event.is_action_pressed("Crouch"):
		_duck_latch = true
	if event.is_action_pressed("Fire"):
		_fire_latch = true
	if event.is_action_pressed("Reload"):
		_reload_latch = true


# =============================================================================
# Hull helpers
# =============================================================================

func hull_height() -> float:
	return RJ.DUCK_HULL_HEIGHT if ducked else RJ.HULL_HEIGHT


func hull_mins() -> Vector2:
	return Vector2(-RJ.HULL_HALF_WIDTH, -hull_height())


func hull_maxs() -> Vector2:
	return Vector2(RJ.HULL_HALF_WIDTH, 0.0)


func hull_rect() -> Rect2:
	return Rect2(origin + hull_mins(), Vector2(RJ.HULL_HALF_WIDTH * 2.0, hull_height()))


func eye_position() -> Vector2:
	return origin + Vector2(0.0, -(RJ.DUCK_VIEW_HEIGHT if ducked else RJ.VIEW_HEIGHT))


func world_center() -> Vector2:
	return origin + Vector2(0.0, -hull_height() * 0.5)


func _trace_hull(from: Vector2, to: Vector2) -> TraceResult:
	return world.trace_box(from, to, hull_mins(), hull_maxs())


# =============================================================================
# Spawning
# =============================================================================

func respawn(at: Vector2) -> void:
	origin = at
	prev_origin = at
	velocity = Vector2.ZERO
	ducked = false
	ducking = false
	duck_time_ms = 0.0
	air_duck_count = 0
	fall_velocity = 0.0
	on_ground = false
	health = RJ.MAX_HEALTH
	clip = RJ.CLIP_SIZE
	reloading = false
	next_attack_time = sim_time
	_jump_last = true    # Don't jump instantly if the key is still held.
	_categorize_position()


func resupply() -> void:
	health = RJ.MAX_HEALTH
	if clip < RJ.CLIP_SIZE:
		clip = RJ.CLIP_SIZE
		reloading = false


# =============================================================================
# Fixed tick
# =============================================================================

func sim_tick() -> void:
	sim_time += RJ.TICK
	prev_origin = origin
	_update_aim()

	var move_dir := signf(Input.get_axis("Left", "Right"))
	var jump_btn := Input.is_action_pressed("Jump") or _jump_latch
	var duck_btn := Input.is_action_pressed("Crouch") or _duck_latch
	var fire_btn := Input.is_action_pressed("Fire") or _fire_latch
	var reload_btn := Input.is_action_pressed("Reload") or _reload_latch
	_jump_latch = false
	_duck_latch = false
	_fire_latch = false
	_reload_latch = false

	_player_move(move_dir, jump_btn, duck_btn)
	_weapon_frame(fire_btn, reload_btn)


func _update_aim() -> void:
	var to_mouse := get_global_mouse_position() - eye_position()
	if to_mouse.length_squared() > 1.0:
		aim_dir = to_mouse.normalized()
	if absf(aim_dir.x) > 0.001:
		facing = 1 if aim_dir.x > 0.0 else -1


func _player_move(move_dir: float, jump_btn: bool, duck_btn: bool) -> void:
	duck_time_ms = maxf(0.0, duck_time_ms - RJ.TICK * 1000.0)

	# Being launched upward fast enough always takes you off the ground.
	if -velocity.y > RJ.LEAVE_GROUND_SPEED:
		_set_ground(false)
	if not on_ground:
		fall_velocity = velocity.y

	_duck(duck_btn)
	_full_walk_move(move_dir, jump_btn)
	_jump_last = jump_btn


func _full_walk_move(move_dir: float, jump_btn: bool) -> void:
	_start_gravity()

	if jump_btn:
		_check_jump_button()

	_check_velocity()

	# Wish speed: keys give full speed, crouching on the ground gives a third.
	var wish_speed := RJ.MAX_SPEED if move_dir != 0.0 else 0.0
	if _speed_cropped:
		wish_speed *= RJ.DUCK_SPEED_FRACTION

	if on_ground:
		velocity.y = 0.0
		_friction()
		_walk_move(move_dir, wish_speed)
	else:
		_air_move(move_dir, wish_speed)

	_categorize_position()
	_finish_gravity()
	if on_ground:
		velocity.y = 0.0
	_check_falling()
	_check_velocity()


func _start_gravity() -> void:
	velocity.y += RJ.GRAVITY * 0.5 * RJ.TICK
	_check_velocity()


func _finish_gravity() -> void:
	velocity.y += RJ.GRAVITY * 0.5 * RJ.TICK
	_check_velocity()


func _check_velocity() -> void:
	velocity.x = clampf(velocity.x, -RJ.MAX_VELOCITY, RJ.MAX_VELOCITY)
	velocity.y = clampf(velocity.y, -RJ.MAX_VELOCITY, RJ.MAX_VELOCITY)


func _check_jump_button() -> void:
	if ducked:
		return  # No jumping while fully crouched.
	if _jump_last:
		return  # Must release and press again.
	if not on_ground:
		return

	# Jumping cannot carry more than 1.2x run speed.
	var max_scaled := RJ.BUNNYHOP_MAX_FACTOR * RJ.MAX_SPEED
	var spd := velocity.length()
	if spd > max_scaled:
		velocity *= max_scaled / spd

	_set_ground(false)
	if ducking:
		velocity.y = -RJ.JUMP_SPEED
	else:
		velocity.y -= RJ.JUMP_SPEED
	_finish_gravity()


func _friction() -> void:
	var speed := velocity.length()
	if speed < 0.1:
		return
	var drop := 0.0
	if on_ground:
		var control := maxf(speed, RJ.STOP_SPEED)
		drop = control * RJ.FRICTION * surface_friction * RJ.TICK
	var new_speed := maxf(speed - drop, 0.0)
	if new_speed != speed:
		velocity *= new_speed / speed


func _accelerate(wish_dir: float, wish_speed: float, accel: float) -> void:
	var current := velocity.x * wish_dir
	var add := wish_speed - current
	if add <= 0.0:
		return
	var accel_speed := minf(accel * RJ.TICK * wish_speed * surface_friction, add)
	velocity.x += accel_speed * wish_dir


func _air_accelerate(wish_dir: float, wish_speed: float, accel: float) -> void:
	var wish_capped := minf(wish_speed, RJ.AIR_SPEED_CAP)
	var current := velocity.x * wish_dir
	var add := wish_capped - current
	if add <= 0.0:
		return
	var accel_speed := minf(accel * wish_speed * RJ.TICK * surface_friction, add)
	velocity.x += accel_speed * wish_dir


func _walk_move(move_dir: float, wish_speed: float) -> void:
	velocity.y = 0.0
	if move_dir != 0.0:
		_accelerate(move_dir, wish_speed, RJ.ACCELERATE)

	# Hard cap at run speed while grounded.
	if absf(velocity.x) > RJ.MAX_SPEED:
		velocity.x = signf(velocity.x) * RJ.MAX_SPEED

	# Moving away from where you aim is capped at 90%.
	if absf(velocity.x) > RJ.BACKPEDAL_MIN_SPEED and velocity.x * facing < 0.0:
		var max_back := RJ.MAX_SPEED * RJ.BACKPEDAL_FRACTION
		if absf(velocity.x) > max_back:
			velocity.x = -facing * max_back

	if absf(velocity.x) < 1.0:
		velocity = Vector2.ZERO
		return

	var dest := origin + Vector2(velocity.x * RJ.TICK, 0.0)
	var tr := _trace_hull(origin, dest)
	if tr.fraction == 1.0 and not tr.start_solid:
		origin = tr.end_pos
		return
	_step_move()


## Try the move both flat and lifted by STEP_SIZE; keep whichever got further.
func _step_move() -> void:
	var start_pos := origin
	var start_vel := velocity

	_try_player_move()
	var down_pos := origin
	var down_vel := velocity

	origin = start_pos
	velocity = start_vel

	var tr := _trace_hull(origin, origin + Vector2(0.0, -(RJ.STEP_SIZE + RJ.DIST_EPSILON)))
	if not tr.start_solid:
		origin = tr.end_pos

	_try_player_move()

	tr = _trace_hull(origin, origin + Vector2(0.0, RJ.STEP_SIZE + RJ.DIST_EPSILON))
	if -tr.normal.y < RJ.GROUND_NORMAL_MIN:
		origin = down_pos
		velocity = down_vel
		return
	if not tr.start_solid:
		origin = tr.end_pos

	var down_dist := absf(down_pos.x - start_pos.x)
	var up_dist := absf(origin.x - start_pos.x)
	if down_dist > up_dist:
		origin = down_pos
		velocity = down_vel
	else:
		velocity.y = down_vel.y


func _air_move(move_dir: float, wish_speed: float) -> void:
	if move_dir != 0.0:
		_air_accelerate(move_dir, wish_speed, RJ.AIR_ACCELERATE)
	_try_player_move()


static func _clip_velocity(v: Vector2, n: Vector2) -> Vector2:
	var out := v - n * v.dot(n)
	var adjust := out.dot(n)
	if adjust < 0.0:
		out -= n * adjust
	return out


## Slide along whatever we hit, up to 4 times per tick.
func _try_player_move() -> void:
	var original_velocity := velocity
	var primal_velocity := velocity
	var time_left := RJ.TICK
	var all_fraction := 0.0
	var planes: Array[Vector2] = []

	for _bump in 4:
		if velocity == Vector2.ZERO:
			break
		var end := origin + velocity * time_left
		var tr := _trace_hull(origin, end)
		all_fraction += tr.fraction

		if tr.start_solid:
			velocity = Vector2.ZERO
			return

		if tr.fraction > 0.0:
			origin = tr.end_pos
			original_velocity = velocity
			planes.clear()

		if tr.fraction == 1.0:
			break

		time_left -= time_left * tr.fraction

		if planes.size() >= 5:
			velocity = Vector2.ZERO
			break
		planes.append(tr.normal)

		if planes.size() == 1 and not on_ground:
			velocity = _clip_velocity(original_velocity, planes[0])
			original_velocity = velocity
		else:
			var found := false
			for i in planes.size():
				velocity = _clip_velocity(original_velocity, planes[i])
				var ok := true
				for j in planes.size():
					if j != i and velocity.dot(planes[j]) < 0.0:
						ok = false
						break
				if ok:
					found = true
					break
			if not found:
				# Wedged into a corner: in 2D there is no crease to slide along.
				velocity = Vector2.ZERO
				break
			if velocity.dot(primal_velocity) <= 0.0:
				velocity = Vector2.ZERO
				break

	if all_fraction == 0.0:
		velocity = Vector2.ZERO


func _set_ground(grounded: bool) -> void:
	if grounded:
		if not on_ground:
			air_duck_count = 0
		velocity.y = 0.0
	on_ground = grounded


func _categorize_position() -> void:
	surface_friction = 1.0
	if -velocity.y > RJ.LEAVE_GROUND_SPEED:
		_set_ground(false)
		return

	var end := origin + Vector2(0.0, 2.0)
	var snap_down := false
	if on_ground:
		end.y += RJ.STEP_SIZE
		snap_down = true

	var tr := _trace_hull(origin, end)
	var in_air := false
	if -tr.normal.y < RJ.GROUND_NORMAL_MIN:
		in_air = true
		# Air control is weaker while drifting upward slowly.
		if -velocity.y > 0.0:
			surface_friction = RJ.AIR_FRICTION_RISING
	elif snap_down and not tr.start_solid and tr.fraction > 0.0 and tr.fraction < 1.0:
		if absf(origin.y - tr.end_pos.y) > 0.5 * RJ.COORD_RESOLUTION:
			origin.y = tr.end_pos.y
	_set_ground(not in_air)


func _check_falling() -> void:
	if not on_ground or fall_velocity <= 0.0:
		return
	if fall_velocity > RJ.SAFE_FALL_SPEED:
		var dmg := 5.0 * (fall_velocity / 300.0) * (RJ.MAX_HEALTH / 100.0)
		dmg *= randf_range(0.8, 1.2)
		take_damage(dmg, "fall")
	fall_velocity = 0.0


# =============================================================================
# Crouching
# =============================================================================

func _duck(duck_btn: bool) -> void:
	# Things that suppress the crouch button.
	if on_ground and sim_time < duck_lockout_until:
		duck_btn = false
	if ducked and ducking:
		duck_btn = false  # Must finish standing up before crouching again.
	if not on_ground and air_duck_count >= RJ.MAX_AIR_DUCKS:
		duck_btn = false

	var pressed := duck_btn and not _duck_last
	var released := _duck_last and not duck_btn
	_duck_last = duck_btn

	_speed_cropped = ducked and on_ground

	if duck_btn or ducking or ducked:
		if duck_btn:
			_on_duck(pressed)
		else:
			_on_unduck(released)


func _on_duck(pressed: bool) -> void:
	if pressed and not ducked:
		duck_time_ms = 1000.0
		ducking = true
	if ducking:
		var secs := (1000.0 - duck_time_ms) * 0.001
		if secs > RJ.TIME_TO_DUCK or ducked or not on_ground:
			_finish_duck()


func _on_unduck(released: bool) -> void:
	if released:
		duck_lockout_until = sim_time + RJ.DUCK_REPEAT_DELAY
		if not on_ground:
			air_duck_count += 1
		if ducked:
			duck_time_ms = 1000.0
		elif ducking:
			# Convert partial crouch progress into stand-up progress.
			var elapsed := 1000.0 - duck_time_ms
			var frac := elapsed / (1000.0 * RJ.TIME_TO_DUCK)
			duck_time_ms = 1000.0 - 1000.0 * RJ.TIME_TO_UNDUCK + frac * 1000.0 * RJ.TIME_TO_UNDUCK

	if _can_unduck():
		if ducking or ducked:
			var secs := (1000.0 - duck_time_ms) * 0.001
			if secs > RJ.TIME_TO_UNDUCK or not on_ground:
				_finish_unduck()
			else:
				ducking = true
	elif duck_time_ms != 1000.0:
		# No room to stand: stay crouched.
		duck_time_ms = 1000.0
		ducked = true
		ducking = false


func _finish_duck() -> void:
	if ducked:
		return
	ducked = true
	ducking = false
	if not on_ground:
		# Crouching in mid-air pulls your feet up instead of lowering your head.
		origin.y -= RJ.HULL_HEIGHT - RJ.DUCK_HULL_HEIGHT
	_categorize_position()


func _can_unduck() -> bool:
	var stand_mins := Vector2(-RJ.HULL_HALF_WIDTH, -RJ.HULL_HEIGHT)
	var stand_maxs := Vector2(RJ.HULL_HALF_WIDTH, 0.0)
	var new_origin := origin
	if not on_ground:
		new_origin.y += RJ.HULL_HEIGHT - RJ.DUCK_HULL_HEIGHT
	var tr := world.trace_box(origin, new_origin, stand_mins, stand_maxs)
	return not tr.start_solid and tr.fraction == 1.0


func _finish_unduck() -> void:
	if not on_ground:
		origin.y += RJ.HULL_HEIGHT - RJ.DUCK_HULL_HEIGHT
	ducked = false
	ducking = false
	duck_time_ms = 0.0
	_categorize_position()


# =============================================================================
# Rocket launcher
# =============================================================================

func _weapon_frame(fire_btn: bool, reload_btn: bool) -> void:
	if reloading and sim_time >= reload_done_time:
		clip += 1
		if clip < RJ.CLIP_SIZE:
			reload_started_time = sim_time
			reload_done_time = sim_time + RJ.RELOAD_EACH
		else:
			reloading = false

	if fire_btn and clip > 0 and sim_time >= next_attack_time:
		reloading = false
		_fire_rocket()
		clip -= 1
		next_attack_time = sim_time + RJ.FIRE_INTERVAL
		return

	# Auto-reload whenever we're not shooting (or are out of rockets).
	var wants_reload := reload_btn or not fire_btn or clip == 0
	if wants_reload and not reloading and clip < RJ.CLIP_SIZE and sim_time >= next_attack_time:
		reloading = true
		reload_started_time = sim_time
		reload_done_time = sim_time + RJ.RELOAD_FIRST


func reload_progress() -> float:
	if not reloading:
		return 0.0
	var total := reload_done_time - reload_started_time
	return clampf((sim_time - reload_started_time) / maxf(total, 0.001), 0.0, 1.0)


func _fire_rocket() -> void:
	var eye := eye_position()
	var fwd := aim_dir
	# "Up" relative to the view, mirrored with the facing direction.
	var up := Vector2(fwd.y, -fwd.x) if facing > 0 else Vector2(-fwd.y, fwd.x)
	var up_offset := RJ.ROCKET_SPAWN_UP_DUCKED if ducked else RJ.ROCKET_SPAWN_UP
	var spawn := eye + fwd * RJ.ROCKET_SPAWN_FORWARD + up * up_offset

	# Aim the rocket at whatever the crosshair ray hits.
	var far_point := eye + fwd * RJ.AIM_TRACE_LENGTH
	var aim_tr := world.trace_line(eye, far_point)
	var target := aim_tr.end_pos if aim_tr.fraction > 0.1 else far_point
	var dir := (target - spawn).normalized()
	if dir == Vector2.ZERO:
		dir = fwd

	# Point-blank into a wall: the rocket bursts right there.
	var spawn_tr := world.trace_line(eye, spawn)
	if spawn_tr.did_hit():
		course.explode(spawn_tr.end_pos + spawn_tr.normal * 1.0)
	else:
		course.spawn_rocket(spawn, dir * RJ.ROCKET_SPEED)
	fired.emit()


## Blast from our own rocket: damage falls off with distance and the push
## depends on whether we are airborne and crouched.
func apply_self_blast(blast_pos: Vector2) -> void:
	var rect := hull_rect()
	var nearest := blast_pos.clamp(rect.position, rect.end)
	if blast_pos.distance_to(nearest) > RJ.ROCKET_SELF_RADIUS:
		return
	# The blast has to be able to "see" us.
	if world.trace_line(blast_pos, eye_position()).did_hit():
		return

	var center := world_center()
	var dist := minf(blast_pos.distance_to(center), blast_pos.distance_to(origin))
	var dmg := remap(clampf(dist, 0.0, RJ.ROCKET_SELF_RADIUS), 0.0, RJ.ROCKET_SELF_RADIUS,
			RJ.ROCKET_DAMAGE, RJ.ROCKET_DAMAGE * RJ.ROCKET_FALLOFF)

	var force_scale := RJ.SELF_FORCE_SCALE_GROUND
	if not on_ground:
		dmg *= RJ.SELF_DAMAGE_SCALE_AIR
		force_scale = RJ.SELF_FORCE_SCALE_AIR

	var size_height := RJ.DUCK_FORCE_HULL_HEIGHT if ducked else RJ.HULL_HEIGHT
	var size_volume := (RJ.HULL_HALF_WIDTH * 2.0) * (RJ.HULL_HALF_WIDTH * 2.0) * size_height
	var force := minf(RJ.FORCE_CAP, dmg * (RJ.FORCE_REFERENCE_VOLUME / size_volume) * force_scale)

	var dir := (blast_pos + Vector2(0.0, RJ.BLAST_DIR_DROP) - center).normalized()
	velocity -= dir * force
	_check_velocity()
	air_duck_count = 0
	take_damage(dmg, "rocket")


func take_damage(amount: float, reason: String) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health -= amount
	last_damage = amount
	last_damage_time = sim_time
	_hurt_flash = 1.0
	if health <= 0.0:
		health = 0.0
		died.emit(reason)


# =============================================================================
# Visuals
# =============================================================================

func update_visual(alpha: float, delta: float) -> void:
	position = prev_origin.lerp(origin, alpha)

	var sy := SPRITE_SCALE * (hull_height() / RJ.HULL_HEIGHT)
	_sprite.scale = Vector2(SPRITE_SCALE, sy)
	_sprite.position = Vector2(0.0, -16.0 * sy)
	_sprite.flip_h = facing < 0

	var anim := "Idle"
	if on_ground:
		if absf(velocity.x) > 20.0:
			anim = "Walk"
			_sprite.speed_scale = clampf(absf(velocity.x) / RJ.MAX_SPEED, 0.3, 1.2)
		else:
			_sprite.speed_scale = 1.0
	else:
		anim = "Jump" if velocity.y < 0.0 else "Fall"
		_sprite.speed_scale = 1.0
	if _sprite.animation != anim:
		_sprite.play(anim)

	_hurt_flash = maxf(0.0, _hurt_flash - delta * 4.0)
	_sprite.modulate = Color(1.0, 1.0 - 0.6 * _hurt_flash, 1.0 - 0.6 * _hurt_flash)

	var eye_off := (RJ.DUCK_VIEW_HEIGHT if ducked else RJ.VIEW_HEIGHT) - 10.0
	_launcher.position = Vector2(0.0, -eye_off)
	_launcher.rotation = aim_dir.angle()
	_launcher.scale = Vector2(1.0, -1.0 if facing < 0 else 1.0)
	_launcher.queue_redraw()

	if debug_draw:
		queue_redraw()


func _draw_launcher() -> void:
	var outline := Color.BLACK
	var body := Color(0.22, 0.24, 0.26)
	_launcher.draw_rect(Rect2(-16.0, -6.0, 46.0, 12.0), body)
	_launcher.draw_rect(Rect2(-16.0, -6.0, 46.0, 12.0), outline, false, 2.0)
	_launcher.draw_rect(Rect2(26.0, -8.0, 8.0, 16.0), body)
	_launcher.draw_rect(Rect2(26.0, -8.0, 8.0, 16.0), outline, false, 2.0)
	_launcher.draw_rect(Rect2(-6.0, -6.0, 6.0, 12.0), Color.WHITE)
	_launcher.draw_rect(Rect2(-2.0, 6.0, 6.0, 8.0), outline)


func _draw() -> void:
	if not debug_draw:
		return
	var local_origin := origin - position
	var r := Rect2(local_origin + hull_mins(), Vector2(RJ.HULL_HALF_WIDTH * 2.0, hull_height()))
	draw_rect(r, Color(0.1, 0.6, 1.0), false, 1.0)
	draw_line(r.get_center(), r.get_center() + velocity * 0.1, Color(1.0, 0.3, 0.1), 2.0)
	draw_circle(eye_position() - position, 3.0, Color(0.1, 0.6, 1.0))
