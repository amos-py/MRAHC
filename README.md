# MHRAC – rocket jump

A 2D rocket-jumping platformer in Godot 4.2. The movement and rocket-jump
numbers are taken from the Source-engine / TF2 movement code (Valve's public
SDK). The game reimplements those rules in GDScript and projects them onto a
side view.

Open the project in Godot 4.2+ and press **F5**. The main scene is
`scenes/rocket_jump.tscn`. The old `scenes/world.tscn` and `scripts/Player.gd`
are untouched.

## Controls

| Key | Action |
| --- | --- |
| A / D (or arrows) | Run |
| Space (or mouse wheel down) | Jump |
| Ctrl / S | Crouch |
| Left mouse | Fire rocket (aim with the mouse) |
| R | Reload (it also reloads automatically) |
| Q / Backspace | Back to the last checkpoint |
| Enter | Restart the run |
| F3 | Debug overlay (hitbox, velocity, ground state) |

Rocket jump: **jump + crouch + shoot at your feet on the same moment.**

## Mechanics

1 unit = 1 pixel. The simulation runs at a fixed 66.67 ticks per second.

| | |
| --- | --- |
| Gravity | 800 |
| Run speed | 240 (backpedal 216, crouch-walk 80) |
| Ground accel / friction / stop speed | 10 / 4 / 100 |
| Air accel / air speed cap | 10 / 30 (only 25% control while drifting up below 250 u/s) |
| Jump | 289 up (about 50 high, about 72 when crouch-jumping) |
| Bunny hop | Jump must be re-pressed. Jumping caps speed at 288 |
| Hitbox | 48 x 82, crouched 48 x 62. Crouching in the air lifts your feet 20 |
| Crouch rules | No jumping while fully crouched, 2 air crouches per jump |
| Step height | 18 |
| Health / fall damage | 200. Landing faster than 650 hurts |
| Rocket | Speed 1100, damage 90, self-blast radius 121, edge damage 50% |
| Fire / clip / reload | 0.8 s, 4 rockets, 0.92 s for the first then 0.8 s each |
| Self-blast in the air | 60% damage, push = damage × 10 |
| Self-blast on the ground | Full damage, push = damage × 5 |
| Crouched | Push × 82/55 (about 1.5×). All pushes are capped at 1000 |

A perfect crouched rocket jump goes about 600 high for about 47 health. An
uncrouched one goes about 375. Shooting the ground without jumping first goes
about 120 and costs about 90 health.

## Code

`scripts/rocketjump/`

- `rj_constants.gd` – every tuning number above.
- `rj_player.gd` – movement loop, crouching, weapon, self-blast.
- `tile_world.gd` – swept-box collision against the TileMap's tiles.
- `course.gd` – level layout, checkpoints, spikes, finish, camera, tick loop.
- `rocket.gd`, `explosion_fx.gd`, `hud.gd` – projectile, effect and UI.

The course is built from the rectangles in `COURSE_SOLIDS` (tile coordinates,
16 px tiles). If you paint tiles into the scene's TileMap yourself, the game
uses those instead. In that case, move `COURSE_CHECKPOINTS`, `COURSE_SPIKES`
and `COURSE_GOAL` to match your layout.
