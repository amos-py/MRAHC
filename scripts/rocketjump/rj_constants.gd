## Tuning numbers for the rocket-jump movement model.
##
## 1 game unit = 1 pixel. Velocities are units/second, times are seconds.
## These reproduce classic Source-engine movement plus the rocket-jump rules
## (blast falloff, self-damage, knockback scaling) so the feel matches the
## original mechanic one-to-one, just projected onto a 2D side view.
extends RefCounted

# --- Simulation -------------------------------------------------------------
const TICK := 0.015                 ## Fixed 66.67 Hz movement tick.
const MAX_TICKS_PER_FRAME := 8      ## Avoid a spiral of death on hitches.

# --- World / movement -------------------------------------------------------
const GRAVITY := 800.0
const MAX_SPEED := 240.0            ## Run speed.
const DUCK_SPEED_FRACTION := 0.33333333 ## Crouch-walk = 80 u/s (ground only).
const BACKPEDAL_FRACTION := 0.9     ## Moving away from where you aim = 216 u/s.
const BACKPEDAL_MIN_SPEED := 100.0
const ACCELERATE := 10.0
const AIR_ACCELERATE := 10.0
const AIR_SPEED_CAP := 30.0         ## Air control can only add up to 30 u/s.
const FRICTION := 4.0
const STOP_SPEED := 100.0
const MAX_VELOCITY := 3500.0        ## Per-axis clamp.
const JUMP_SPEED := 289.0
const BUNNYHOP_MAX_FACTOR := 1.2    ## Jumping caps speed at 1.2 * MAX_SPEED.
const STEP_SIZE := 18.0             ## Walk up ledges this tall without jumping.
const GROUND_NORMAL_MIN := 0.7
const LEAVE_GROUND_SPEED := 250.0   ## Upward speed that always un-grounds you.
const AIR_FRICTION_RISING := 0.25   ## Air control multiplier while rising slowly.
const DIST_EPSILON := 0.03125       ## Gap kept between the hull and surfaces.
const COORD_RESOLUTION := 0.03125

# --- Player hull (origin = bottom centre of the box) ------------------------
const HULL_HALF_WIDTH := 24.0       ## 48 wide.
const HULL_HEIGHT := 82.0
const DUCK_HULL_HEIGHT := 62.0
const VIEW_HEIGHT := 68.0
const DUCK_VIEW_HEIGHT := 45.0
const TIME_TO_DUCK := 0.2
const TIME_TO_UNDUCK := 0.2
const DUCK_REPEAT_DELAY := 0.3      ## Ground re-crouch lockout after releasing.
const MAX_AIR_DUCKS := 2            ## Crouch releases allowed per airtime.

# --- Health -----------------------------------------------------------------
const MAX_HEALTH := 200.0
const SAFE_FALL_SPEED := 650.0

# --- Rocket launcher --------------------------------------------------------
const ROCKET_SPEED := 1100.0
const ROCKET_DAMAGE := 90.0
const ROCKET_SELF_RADIUS := 121.0   ## Radius used when the blast hits yourself.
const ROCKET_FALLOFF := 0.5         ## Damage at the edge of the radius.
const ROCKET_LIFETIME := 10.0
const SELF_DAMAGE_SCALE_AIR := 0.6  ## Own-rocket damage while airborne.
const SELF_FORCE_SCALE_AIR := 10.0
const SELF_FORCE_SCALE_GROUND := 5.0
const FORCE_REFERENCE_VOLUME := 48.0 * 48.0 * 82.0
const FORCE_CAP := 1000.0
const DUCK_FORCE_HULL_HEIGHT := 55.0 ## Crouched hull counts as 55 tall -> more push.
const BLAST_DIR_DROP := 10.0        ## Push is measured from 10 u below the blast.
const FIRE_INTERVAL := 0.8
const CLIP_SIZE := 4
const RELOAD_FIRST := 0.92
const RELOAD_EACH := 0.8
const ROCKET_SPAWN_FORWARD := 23.5
const ROCKET_SPAWN_UP := -3.0
const ROCKET_SPAWN_UP_DUCKED := 8.0
const AIM_TRACE_LENGTH := 2000.0
