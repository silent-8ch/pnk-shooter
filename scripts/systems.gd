class_name Systems
## FTL-style ship systems. A ship has a REACTOR of power bars and a handful of
## SYSTEMS, each with a capacity (bars bought with exp) and the bars of it
## currently powered, both from the ShipPanel's popups.
## Power in use can never exceed the reactor, so a ship has to choose what to
## run. What a system does grows with its power, not with what it could hold:
##   SHIELDS   1: front shield recharges; 2: rear shield too; 3: twice as fast
##   ENGINES   +SPEED_STEP move speed per bar
##   WEAPONS   bars the armed guns draw on (each gun needs `power` of them)
##   DRONES    a pool: OPTION and RESCUE each take bars of their own (one per
##             drone), up to DRONES' level between them
##   MEDBAY    1: REPAIR kits; 2: heals ships nearby; 3: kits come back twice as fast
##   PILOTING  a pool: AUTOPILOT and BEACON a bar each, up to PILOTING's level
## A pool system (POOLS) isn't powered itself: its members are, each with
## its own - and +, drawing straight from the reactor; the pool's level caps
## how many bars they hold together.
## Guns live in WEAPONS: bought once, then levelled (LASER's levels are its
## DOUBLE and RAPID rows), and armed from the action bar. Drones are bought as
## units and run on DRONES power. Hull items are passive.
## Everything resets to START on death; the escape pod carries it back.

## Everything that can be bought, listed under its section in the ShipPanel. `cost` x the level being
## bought (counted from `start`) is its price; `max` its top level.
const ITEMS: Array[Dictionary] = [
	{"id": &"reactor", "label": "REACTOR", "section": "REACTOR", "cost": 2, "max": 16, "start": 3},
	{"id": &"shields", "label": "SHIELDS", "short": "SH", "section": "SYSTEMS", "system": true, "cost": 3, "max": 3},
	{"id": &"engines", "label": "ENGINES", "short": "EN", "section": "SYSTEMS", "system": true, "cost": 1, "max": 6, "start": 1},
	{"id": &"weapons", "label": "WEAPONS", "short": "WP", "section": "SYSTEMS", "system": true, "cost": 2, "max": 8, "start": 1},
	{"id": &"drones", "label": "DRONES", "short": "DR", "section": "SYSTEMS", "system": true, "cost": 3, "max": 7},
	{"id": &"medbay", "label": "MEDBAY", "short": "MB", "section": "SYSTEMS", "system": true, "cost": 3, "max": 3},
	{"id": &"piloting", "label": "PILOTING", "short": "PI", "section": "SYSTEMS", "system": true, "cost": 2, "max": 2},
	{"id": &"lasers", "label": "PHOTON", "section": "WEAPONS", "gun": true, "power": 1, "cost": 1, "max": 1, "start": 1},
	{"id": &"double", "label": "PHOTON DOUBLE", "section": "WEAPONS", "cost": 3, "max": 2, "needs": &"lasers"},
	{"id": &"rapid", "label": "PHOTON RAPID", "section": "WEAPONS", "cost": 2, "max": 6, "needs": &"lasers"},
	{"id": &"missile", "label": "MISSILE", "section": "WEAPONS", "gun": true, "power": 2, "cost": 4, "max": 6},
	{"id": &"auto", "label": "AUTOCAN", "section": "WEAPONS", "gun": true, "power": 1, "cost": 4, "max": 2},
	{"id": &"beam", "label": "BEAM", "section": "WEAPONS", "gun": true, "power": 3, "cost": 6, "max": 3},
	{"id": &"healbeam", "label": "HEAL BEAM", "section": "WEAPONS", "gun": true, "power": 1, "cost": 4, "max": 2, "action": &"heal"},
	{"id": &"option", "label": "OPTION", "section": "DRONES", "cost": 4, "max": 3},
	{"id": &"rescue", "label": "RESCUE", "section": "DRONES", "cost": 3, "max": 4},
	{"id": &"autopilot", "label": "AUTOPILOT", "section": "PILOTING", "builtin": true, "cost": 0, "max": 1, "start": 1},
	{"id": &"beacon", "label": "BEACON", "section": "PILOTING", "builtin": true, "cost": 0, "max": 1, "start": 1},
	{"id": &"armor", "label": "ARMOR", "section": "HULL", "cost": 3, "max": 4},
	{"id": &"ship", "label": "+SHIP", "section": "HULL", "cost": 6, "max": 3},
]
## Pool systems and the members that take their bars.
const POOLS := {&"drones": [&"option", &"rescue"], &"piloting": [&"autopilot", &"beacon"]}

## Bars powered at the start (and after a respawn), and the guns armed.
const START_POWER := {&"engines": 1, &"weapons": 1}
const START_ARMED: Array[StringName] = [&"lasers"]


static func item(id: StringName) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}


static func systems() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in ITEMS:
		if it.get("system", false):
			out.append(it)
	return out


static func guns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in ITEMS:
		if it.get("gun", false):
			out.append(it)
	return out


static func is_system(id: StringName) -> bool:
	return item(id).get("system", false)


static func is_pool(id: StringName) -> bool:
	return POOLS.has(id)


## The pool system member `id` draws its bars from, or &"".
static func pool_of(id: StringName) -> StringName:
	for pool in POOLS:
		if POOLS[pool].has(id):
			return pool
	return &""


## Comes with its pool: nothing to buy (AUTOPILOT, BEACON).
static func is_builtin(id: StringName) -> bool:
	return item(id).get("builtin", false)


static func is_gun(id: StringName) -> bool:
	return item(id).get("gun", false)


static func max_level(id: StringName) -> int:
	return item(id).get("max", 0)


static func start_level(id: StringName) -> int:
	return item(id).get("start", 0)


## Weapons bars gun `id` needs while armed.
static func gun_power(id: StringName) -> int:
	return item(id).get("power", 0)


## The action bar button of gun `id` (its own id unless it says otherwise).
static func gun_action(id: StringName) -> StringName:
	return item(id).get("action", id)


## The gun an action bar button arms, or &"".
static func gun_for_action(action: StringName) -> StringName:
	for g in guns():
		if gun_action(g.id) == action:
			return g.id
	return &""


## Exp the next level of `id` costs, given the `level` it's at now.
static func price(id: StringName, level: int) -> int:
	var it := item(id)
	if it.is_empty():
		return 0
	return it.cost * (level - it.get("start", 0) + 1)
