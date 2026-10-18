extends RefCounted
## A level (levels/<slug>.json, made in tools/level-designer): enemy groups
## placed on a timeline. Each event:
##   time   when the group enters (seconds from the start)
##   type   "weaver", "diver", "striker", "tank" or "orbiter"
##   lane   0..8, where it enters; 0 = left edge of the screen, 8 = right
##   count  ships in the group
##   dir    initial sideways direction (divers); -1 mirrors an obstacle
## Obstacle events (type "obstacle") also name a `piece` from
## assets/obstacles/pieces.json; count is a tile piece's segments or a
## cluster's copies (see Obstacle).
## Parsing is lenient: bad events are skipped and numbers clamped, so a level
## saved by an older designer still plays.

const EnemyScript := preload("res://scripts/enemy.gd")
const ObstacleScript := preload("res://scripts/obstacle.gd")
const OBSTACLE := -1  # event type for obstacles (enemy types are >= 0)
const DIR := "res://levels"
const LANES := 9
const MAX_COUNT := 7
const EDGE := 20.0  # same margin as random waves
const TYPES := {"weaver": EnemyScript.WEAVER, "diver": EnemyScript.DIVER, "striker": EnemyScript.STRIKER,
	"tank": EnemyScript.TANK, "orbiter": EnemyScript.ORBITER}

var name := ""
var length := 1.0  # seconds
var repeat := true
var events: Array[Dictionary] = []  # {time, type (enemy enum or OBSTACLE), lane, count, dir[, piece]}, sorted by time


## First level file by name, or "" if there are none.
static func first_level_path() -> String:
	if not DirAccess.dir_exists_absolute(DIR):
		return ""
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f): return f.ends_with(".json"))
	files.sort()
	return DIR + "/" + files[0] if not files.is_empty() else ""


## The level at `path`, or null if it's missing or not a level.
static func load_file(path: String) -> RefCounted:
	if path == "" or not FileAccess.file_exists(path):
		return null
	return parse(FileAccess.get_file_as_string(path))


static func parse(text: String) -> RefCounted:
	var json := JSON.new()
	if json.parse(text) != OK:  # (JSON.parse_string would log an engine error)
		return null
	var data = json.data
	if not data is Dictionary or not data.get("events") is Array:
		return null
	var l = new()
	l.name = str(data.get("name", ""))
	l.length = clampf(_num(data.get("length"), 0.0), 0.0, 1800.0)
	if l.length < 1.0:
		return null
	l.repeat = data.get("repeat", true) == true
	for e in data.events:
		if not e is Dictionary:
			continue
		var obstacle: bool = e.get("type") == "obstacle"
		if obstacle and not ObstacleScript.placeable(str(e.get("piece", ""))):
			continue
		if not obstacle and not TYPES.has(e.get("type")):
			continue
		var time := _num(e.get("time"), -1.0)
		if time < 0.0 or time >= l.length:
			continue
		var ev := {
			"time": time,
			"type": OBSTACLE if obstacle else TYPES[e.type],
			"lane": clampi(int(_num(e.get("lane"), 4)), 0, LANES - 1),
			"count": clampi(int(_num(e.get("count"), 1)), 1, MAX_COUNT),
			"dir": -1.0 if _num(e.get("dir"), 1.0) < 0.0 else 1.0,
		}
		if obstacle:
			ev.piece = str(e.piece)
		l.events.append(ev)
	l.events.sort_custom(func(a, b): return a.time < b.time)
	return l


static func _num(v, fallback: float) -> float:
	return float(v) if (v is float or v is int) else fallback


## True once a non-repeating level has played through.
func finished(t: float) -> bool:
	return not repeat and t >= length


## Events due in [from, to) seconds, counting repeats when the level loops.
func events_between(from: float, to: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var first := int(floorf(from / length)) if repeat else 0
	var last := int(floorf(to / length)) if repeat else 0
	for k in range(first, last + 1):
		for e in events:
			var at: float = e.time + k * length
			if at >= from and at < to:
				out.append(e)
	return out


## Group center x for an event: lane 0..8 spread across the screen, kept far
## enough from the edges that the whole group fits.
static func center_x(e: Dictionary, width: float) -> float:
	var margin := EnemyScript.group_half_width(e.type, e.count) + EDGE
	if margin * 2.0 >= width:
		return width / 2.0
	return lerpf(margin, width - margin, float(e.lane) / (LANES - 1))
