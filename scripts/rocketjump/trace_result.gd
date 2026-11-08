## Result of a swept-box or line trace (see tile_world.gd).
extends RefCounted

var fraction := 1.0          ## 0..1, how much of the move was completed.
var end_pos := Vector2.ZERO  ## Where the box stopped.
var normal := Vector2.ZERO   ## Normal of the surface hit (zero if nothing).
var start_solid := false     ## The box started inside something.


func did_hit() -> bool:
	return fraction < 1.0 or start_solid
