class_name Depth
## Fake 3D: everything comes at the players out of one vanishing point near the
## top of the screen (VANISH_X, VANISH_Y). Things are smallest there and grow
## toward REF_Y (the player line, where scale is 1 and nothing changes), and keep
## growing below it.
##
## Enemies move in flat "world" coordinates (same units as the old 2D arena) and
## are projected: world y is eased so they creep out of the point and speed up as
## they come close, and world x spreads out from VANISH_X in proportion to the
## distance below it, so each enemy flies a straight ray out of the point.

const VANISH_Y := 160.0  # screen y of the vanishing point
const VANISH_X := 270.0  # screen x of the vanishing point
const REF_Y := 840.0  # screen y where scale = 1 (the player line)
const MIN_SCALE := 0.1  # scale at the vanishing point
const WORLD_START := -40.0  # world y that sits on the vanishing point (enemy spawn)
const EASE := 1.6  # >1: far things move slower on screen, near ones faster
const LOG_K := 30.0  # size curve: higher grows faster out of the point, then flattens


## 0 at the vanishing point, 1 at the player line, linear in screen y.
static func progress(y: float) -> float:
	return maxf(0.0, (y - VANISH_Y) / (REF_Y - VANISH_Y))


## Size multiplier for something drawn at screen y. Logarithmic: things grow
## quickly just out of the point and are near full size for most of the screen.
static func scale_at(y: float) -> float:
	var curve := log(1.0 + LOG_K * progress(y)) / log(1.0 + LOG_K)
	return lerpf(MIN_SCALE, 1.0, curve)


## Sideways spread from VANISH_X at screen y: linear, so paths are straight rays.
static func spread_at(y: float) -> float:
	return progress(y)


## Screen y for a world y; world REF_Y maps to screen REF_Y.
static func screen_y(world_y: float) -> float:
	var u := maxf(0.0, (world_y - WORLD_START) / (REF_Y - WORLD_START))
	return VANISH_Y + (REF_Y - VANISH_Y) * pow(u, EASE)


## Screen position for a world position.
static func project(world: Vector2) -> Vector2:
	var y := screen_y(world.y)
	return Vector2(VANISH_X + (world.x - VANISH_X) * spread_at(y), y)
