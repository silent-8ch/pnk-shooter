class_name LevelKinds
extends RefCounted
## The kinds of level a stage can be. A run starts in deep space; after each
## boss the party votes between two other kinds at a fork (see Game.open_fork),
## each offered with a reward.
##   level   the level file played (looping) until the boss shows up; missing =
##           random waves of `waves`
##   waves   enemy types random waves send in
##   bg      background color
##   stars   whether the starfield shows
##   scenery the Scenery script with its look and hazards (none = plain Scenery)
##   boss_ship  the Ships.LIST ship its boss looks like
##   boss_type  the Enemy type of its boss (default BOSS; Deep Space has TETRAN)
##   music   the track that loops while it's played (see Music.set_level)

const EnemyScript := preload("res://scripts/enemy.gd")
const FIRST := "deep_space"

const KINDS := {
	"deep_space": {"name": "Deep Space", "music": "res://assets/music/neu haus inst mix ab oz.mp3",
		"color": Color("5ad1ff"), "bg": Color(0.05, 0.06, 0.12),
		"level": "res://levels/level_01.json", "stars": true, "boss_ship": 4, "boss_type": EnemyScript.TETRAN,
		"waves": [EnemyScript.WEAVER, EnemyScript.DIVER, EnemyScript.STRIKER, EnemyScript.TANK, EnemyScript.ORBITER]},
	"asteroid_belt": {"name": "Asteroid Belt", "music": "res://assets/music/asteroid b inst mix ab oz.mp3",
		"color": Color("d9a066"), "bg": Color(0.08, 0.06, 0.05),
		"level": "res://levels/asteroid_belt.json", "stars": true, "boss_ship": 3,
		"scenery": "res://scripts/scenery/asteroid_belt.gd", "waves": [EnemyScript.WEAVER, EnemyScript.TANK]},
	"starbase": {"name": "Ruined Starbase", "music": "res://assets/music/less to deceit inst mix ab oz.mp3",
		"color": Color("9aa4b5"), "bg": Color(0.06, 0.06, 0.08),
		"level": "res://levels/starbase.json", "stars": true, "boss_ship": 2,
		"scenery": "res://scripts/scenery/starbase.gd", "waves": [EnemyScript.STRIKER, EnemyScript.TANK, EnemyScript.WEAVER, EnemyScript.TURRET]},
	"orbit": {"name": "Planet Orbit", "music": "res://assets/music/ordinary inst mix ab oz.mp3",
		"color": Color("7affb5"), "bg": Color(0.03, 0.07, 0.10),
		"level": "res://levels/orbit.json", "stars": true, "boss_ship": 0,
		"scenery": "res://scripts/scenery/orbit.gd", "waves": [EnemyScript.ORBITER, EnemyScript.DIVER, EnemyScript.WEAVER]},
	"surface": {"name": "Planet Surface", "music": "res://assets/music/lynx inst mix ab oz.mp3",
		"color": Color("ff9c5a"), "bg": Color(0.12, 0.07, 0.04),
		"level": "res://levels/surface.json", "stars": false, "boss_ship": 3,
		"scenery": "res://scripts/scenery/surface.gd", "waves": [EnemyScript.TURRET, EnemyScript.TANK, EnemyScript.STRIKER, EnemyScript.DIVER]},
	"storm": {"name": "Ion Storm", "music": "res://assets/music/lady on the track 132.mp3",
		"color": Color("c08dff"), "bg": Color(0.07, 0.04, 0.11),
		"level": "res://levels/storm.json", "stars": false, "boss_ship": 1,
		"scenery": "res://scripts/scenery/storm.gd", "waves": [EnemyScript.DIVER, EnemyScript.WEAVER, EnemyScript.ORBITER]},
	"crystal_crevices": {"name": "Crystal Crevices", "music": "res://assets/music/GB3AD1300063.mp3",
		"color": Color("8de8ff"), "bg": Color(0.04, 0.09, 0.12),
		"level": "res://levels/crystal_crevices.json", "stars": false, "boss_ship": 2,
		"boss_type": EnemyScript.CRYSTAL,
		"scenery": "res://scripts/scenery/crystal_crevices.gd",
		"waves": [EnemyScript.ORBITER, EnemyScript.STRIKER, EnemyScript.TURRET, EnemyScript.WEAVER]},
}

## What a fork's gate offers besides the next kind of level. "next stage" ones
## last until the following fork.
const REWARDS := {
	"spare": "+1 spare ship",
	"repair": "Full repair",
	"exp2": "Double exp next stage",
	"upgrade": "Free upgrade for everyone",
	"score2": "Double score next stage",
}


## A new Scenery node for kind `id` (its own script if it has one and it loads).
static func make_scenery(id: String) -> Node2D:
	var path: String = info(id).get("scenery", "")
	var script: Script = load(path) if path != "" and ResourceLoader.exists(path) else null
	var s: Node2D = script.new() if script else Scenery.new()
	s.kind = id
	return s


static func is_kind(id: String) -> bool:
	return KINDS.has(id)


static func info(id: String) -> Dictionary:
	return KINDS.get(id, KINDS[FIRST])


static func music_of(id: String) -> String:
	return str(info(id).get("music", KINDS[FIRST].music))


static func name_of(id: String) -> String:
	return info(id).name


static func wave_types(id: String) -> Array:
	return info(id).waves


## The level a stage of this kind plays, or null for random waves.
static func load_level(id: String) -> RefCounted:
	return preload("res://scripts/level.gd").load_file(info(id).level)


## Two fork choices after a stage of kind `current`: different kinds (never the
## one just played), each with a different reward. [{kind, reward}, {kind, reward}]
static func fork_options(current: String, rng: RandomNumberGenerator) -> Array:
	var kinds: Array = KINDS.keys().filter(func(k): return k != current)
	var rewards: Array = REWARDS.keys()
	_shuffle(kinds, rng)
	_shuffle(rewards, rng)
	return [{"kind": kinds[0], "reward": rewards[0]}, {"kind": kinds[1], "reward": rewards[1]}]


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
