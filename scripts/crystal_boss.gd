extends Node2D
## The Crystal Storm, Crystal Crevices' boss: the cloud itself, drawn from the
## scanned drawing (assets/crystal_storm.svg, Scan 9). One target — there are no
## parts to break off. What makes it a fight is the rain: crystal shards fall out
## of its underside the whole time, heavier the more it has been hurt, and it
## opens up with a downpour right over a player (CrystalCrevices.boss_attack).
##
## A child of its Enemy (type CRYSTAL), which hides its ship body for this. The
## cloud hangs wider than any ship, so it reads as weather rather than a craft:
## it drifts, swells and settles on its Enemy's flight time, which means every
## peer animates it the same with nothing to sync. The shards it drops are
## ordinary obstacles the host announces (Game.spawn_obstacle_at), so they fall,
## block shots and can be shot apart like any other.

const ART := preload("res://assets/crystal_storm.svg")
const WIDTH := 300.0  # px across, about half the arena
const DRIFT := 16.0  # px it sways either side
const DRIFT_RATE := 0.35  # rad/s
const SWELL := 0.04  # how much it breathes, as a fraction of its size
const SWELL_RATE := 0.8  # rad/s
const TINT := Color("9ad9ff")
const HURT_TINT := Color("ff9ad9")  # it darkens toward this as it is worn down

var enemy: Node2D  # the cloud's Enemy
var _sprite: Sprite2D


func _ready() -> void:
	enemy = get_parent()
	_sprite = Sprite2D.new()
	_sprite.name = "Cloud"
	_sprite.texture = ART
	_sprite.scale = Vector2.ONE * (WIDTH / maxf(ART.get_width(), 1.0))
	_sprite.light_mask = Ships.LIGHT_MASK
	add_child(_sprite)


func _time() -> float:
	return enemy.get("_time") if enemy else 0.0


## How far gone the cloud is, 0 (untouched) to 1 (about to break up).
func wear() -> float:
	if enemy == null or enemy.max_hp <= 0:
		return 0.0
	return clampf(1.0 - float(enemy.hp) / enemy.max_hp, 0.0, 1.0)


## How wide the cloud hangs now, in px (its hit box and where its rain starts).
func width() -> float:
	return WIDTH * _swell()


func _swell() -> float:
	return 1.0 + sin(_time() * SWELL_RATE) * SWELL


## Where the cloud's underside is, relative to the Enemy: rain starts here.
func underside() -> float:
	return ART.get_height() * _sprite.scale.y * 0.5


func _process(_delta: float) -> void:
	if _sprite == null:
		return
	var t := _time()
	_sprite.position.x = sin(t * DRIFT_RATE) * DRIFT
	var s := WIDTH / maxf(ART.get_width(), 1.0) * _swell()
	_sprite.scale = Vector2(s, s)
	_sprite.modulate = TINT.lerp(HURT_TINT, wear())
