extends Area2D
## Escape pod an enemy ship deploys when it's shot down: a small copy of that
## ship (option sized relative to it) with a green beacon that flashes, which
## drifts slowly off the nearest side of the screen. The beacon is a dot on the
## pod plus a PointLight2D that lights nearby ships (Ships.LIGHT_MASK) as it
## flashes. Only a player's search-and-rescue drone can pick it up (see Player).
## Shots and blasts destroy it with a very small explosion (Game.destroy_pod). Local on every peer, like Pickup; the host decides
## who rescued it (Game.request_rescue).
## A player's pod (owner_peer != 0) is dropped when that player dies: a small
## copy of their ship with a beacon in their color. It drifts sideways off the
## screen very slowly and takes PLAYER_HP damage to destroy (the host keeps its
## hp). Any ship touching it, or any rescue drone, saves it, and its owner gets
## back the upgrades they died with (Player.recover_upgrades). Every shot hits
## it, its owner's included, and it flashes white when hit.
## Any pod that blows up leaves two tiny astronauts (astronaut = true) where it
## was (Game.destroy_pod). They tumble away slowly, bullets and blasts pass
## through them, and only a rescue drone can pick them up. A player's pod's
## astronauts carry its upgrades (stash): saving either one gives them back.
## A ship's tail of rescued pods also spills out as astronauts when the ship is
## lost (Game.release_astronauts), so no one rescued is ever lost.
## An enemy's astronaut nobody rescues within CLEANUP_AFTER s is fetched by a
## neutral cleanup bot (Game.send_cleanup_bot). A player's astronauts never
## leave the screen: they bounce off its edges until someone saves them.

const EnemyScript := preload("res://scripts/enemy.gd")
const SCALE := 0.5  # relative to the enemy ship (Player.OPTION_SCALE)
const SPEED := 35.0  # px/s
const DRIFT := Vector2(0.8, 0.6)  # sideways (toward the nearest edge) and down
const FLASH_RATE := 2.5  # beacon flashes per second
const FLASH_ON := 0.3  # fraction of each flash the beacon is lit
const GREEN := Color(0.35, 1.0, 0.45)
const BEACON_RADIUS := 2.5
const LIGHT_SIZE := 96
const OFFSCREEN := 40.0
const RADIUS := 8.0
const BURST_HEIGHT := 20.0  # its explosion: very small
const PLAYER_SCALE := 0.5  # a player's pod, relative to their ship (Player.OPTION_SCALE)
const PLAYER_SPEED := 20.0  # px/s: very slow
const FLASH_TIME := 0.08  # white flash when hit
const PLAYER_HP := 20.0  # laser hits to destroy a player's pod
const BLAST_RADIUS := 18.0
const SpriteEffect := preload("res://scripts/sprite_effect.gd")
const WreckScript := preload("res://scripts/wreck.gd")
const BURST_SOUND := preload("res://assets/sfx/explosion.tres")
const ASTRONAUT := -2  # a tail entry (Player.tail) for a rescued astronaut
const CLEANUP_AFTER := 8.0  # s an enemy's astronaut waits before a cleanup bot comes for it
const ARENA_HEIGHT := 960.0
const BOUNCE_MARGIN := 16.0  # px a player's astronaut stays inside the screen
const ASTRONAUT_SPEED := 18.0  # px/s: tumbling slowly away
const ASTRONAUT_SPREAD := 0.6  # radians each side of the pod's heading
const ASTRONAUT_GAP := 5.0  # px each side of where the pod blew up
const ASTRONAUT_SPIN := 1.5  # radians per second
## Suit (w) and visor (v), a pixel per character.
const ASTRONAUT_ART := [
	"..www..",
	".wwwww.",
	".wvvvw.",
	".wvvvw.",
	".wwwww.",
	"wwwwwww",
	"w.www.w",
	"..w.w..",
	"..w.w..",
]
const SUIT := Color(0.95, 0.95, 0.92)
const VISOR := Color(0.25, 0.45, 0.9)

var type := EnemyScript.WEAVER
var taken := false  # claimed by a drone or destroyed; gone on every peer once the host says so
var from_wreck := ""  # the wreck that launched it, which doesn't hit it
var velocity := Vector2.ZERO
var owner_peer := 0  # a player's pod: whose upgrades it carries; 0 = an enemy's
var ship := 0  # a player's pod: their ship and palette
var palette := 0
var beacon_color := GREEN
var astronaut := false  # left over from a pod that blew up: indestructible, drones only
var stash := ""  # an astronaut of a player's pod: the pod its owner's upgrades were stashed under
var hp := PLAYER_HP  # host: damage left, for a player's pod
var body := Sprite2D.new()
var beacon := PointLight2D.new()
static var _light_tex: GradientTexture2D
static var _astronaut_tex: ImageTexture
var _age := 0.0
var _claimed := false  # local: already asked the host for it
var _flash := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # bullets; drones and wrecks find pods by distance
	if is_player_pod():
		collision_mask |= 1  # ships touch it to save it
	if astronaut:
		collision_mask = 0  # bullets pass through; only drones take it
		monitoring = false
	monitorable = false
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = RADIUS
	add_child(shape)
	area_entered.connect(_on_area_entered)
	add_to_group("escape_pod")
	if astronaut:
		body.texture = astronaut_texture()
	elif is_player_pod():
		body.texture = Ships.get_lit_texture(ship, palette)
		body.scale = Ships.get_scale(ship, palette) * PLAYER_SCALE
	else:
		var tex := Ships.get_lit_enemy_texture(EnemyScript.TYPES[clampi(type, 0, EnemyScript.TYPES.size() - 1)].ship)
		body.texture = tex
		body.scale = Ships.scale_for(tex, EnemyScript.HEIGHT) * SCALE
		body.flip_v = true
	body.light_mask = Ships.LIGHT_MASK  # lit by its own beacon
	body.show_behind_parent = true  # beacon dot on top
	add_child(body)
	beacon.color = beacon_color
	beacon.energy = 1.4
	beacon.range_item_cull_mask = Ships.LIGHT_MASK
	beacon.texture = _light_texture()
	beacon.height = 20.0
	beacon.enabled = not astronaut
	add_child(beacon)
	if astronaut:
		return  # its velocity is set by whoever let it out
	var side := -1.0 if position.x < EnemyScript.ARENA_WIDTH / 2.0 else 1.0
	if is_player_pod():  # straight sideways, so it never sinks under the buttons
		velocity = Vector2(side * PLAYER_SPEED, 0.0)
	else:
		velocity = Vector2(DRIFT.x * side, DRIFT.y).normalized() * SPEED


func is_player_pod() -> bool:
	return owner_peer != 0


## How long it's been out (local).
func age() -> float:
	return _age


## Host: an enemy's astronaut left long enough for a cleanup bot.
func needs_cleanup() -> bool:
	return astronaut and not is_player_pod() and not taken and _age >= CLEANUP_AFTER


## A player's astronaut: kept on screen, above the button bar, bouncing off the edges.
func _bounce() -> void:
	var area := Rect2(BOUNCE_MARGIN, BOUNCE_MARGIN, EnemyScript.ARENA_WIDTH - BOUNCE_MARGIN * 2.0,
		ARENA_HEIGHT - ActionBar.BAR_HEIGHT - BOUNCE_MARGIN * 2.0)
	if position.x < area.position.x or position.x > area.end.x:
		velocity.x = absf(velocity.x) * (1.0 if position.x < area.position.x else -1.0)
	if position.y < area.position.y or position.y > area.end.y:
		velocity.y = absf(velocity.y) * (1.0 if position.y < area.position.y else -1.0)
	position = position.clamp(area.position, area.end)


func _process(delta: float) -> void:
	_age += delta
	position += velocity * delta
	if astronaut:
		body.rotation += ASTRONAUT_SPIN * delta
	if _flash > 0.0:
		_flash -= delta
		body.modulate = Color(3, 3, 3) if _flash > 0.0 else Color.WHITE
	var on := beacon_on() and not astronaut
	if on != beacon.enabled:
		beacon.enabled = on
		queue_redraw()
	if astronaut and is_player_pod():
		_bounce()
	elif position.x < -OFFSCREEN or position.x > EnemyScript.ARENA_WIDTH + OFFSCREEN or position.y > EnemyScript.EXIT_Y:
		queue_free()
		return
	if is_player_pod() and monitoring:
		claim_from(get_overlapping_areas())


## A player's pod: the local ship, if it's touching, asks the host to save it.
## Polled rather than on area_entered, so a ship already on it when it
## respawns still counts.
func claim_from(areas: Array) -> void:
	if taken or _claimed or astronaut or multiplayer.multiplayer_peer == null:
		return
	for a in areas:
		if a.is_in_group("player") and a.is_local() and not a.ai and a.is_alive():
			var game := get_tree().get_first_node_in_group("game")
			if game:
				_claimed = true
				game.request_rescue.rpc_id(1, String(name), false)
			return


## Took damage without being destroyed (every peer, from Game.flash_pod).
func flash() -> void:
	_flash = FLASH_TIME
	body.modulate = Color(3, 3, 3)


## The two astronauts this pod leaves when it blows up: name, position and
## velocity of each, the same on every peer.
func astronauts() -> Array[Dictionary]:
	var heading := velocity.normalized() if velocity != Vector2.ZERO else Vector2.DOWN
	var out: Array[Dictionary] = []
	for side in [-1.0, 1.0]:
		var dir := heading.rotated(side * ASTRONAUT_SPREAD)
		out.append({
			"name": "%s_%s" % [name, "A" if side < 0.0 else "B"],
			"position": position + dir.orthogonal() * side * -ASTRONAUT_GAP,
			"velocity": dir * ASTRONAUT_SPEED,
		})
	return out


## A tiny spacesuit, drawn from ASTRONAUT_ART.
static func astronaut_texture() -> ImageTexture:
	if _astronaut_tex == null:
		var rows: Array = ASTRONAUT_ART
		var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
		for y in rows.size():
			for x in rows[y].length():
				match rows[y][x]:
					"w": img.set_pixel(x, y, SUIT)
					"v": img.set_pixel(x, y, VISOR)
		_astronaut_tex = ImageTexture.create_from_image(img)
	return _astronaut_tex


func beacon_on() -> bool:
	return fmod(_age * FLASH_RATE, 1.0) < FLASH_ON


static func _light_texture() -> GradientTexture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
		_light_tex = GradientTexture2D.new()
		_light_tex.gradient = g
		_light_tex.width = LIGHT_SIZE
		_light_tex.height = LIGHT_SIZE
		_light_tex.fill = GradientTexture2D.FILL_RADIAL
		_light_tex.fill_from = Vector2(0.5, 0.5)
		_light_tex.fill_to = Vector2(1, 0.5)
	return _light_tex


## The beacon: a bright green dot with a soft halo, only while lit. An
## astronaut has no beacon.
func _draw() -> void:
	if astronaut or not beacon_on():
		return
	draw_circle(Vector2.ZERO, BEACON_RADIUS * 3.0, Color(beacon_color, 0.25))
	draw_circle(Vector2.ZERO, BEACON_RADIUS, beacon_color.lerp(Color.WHITE, 0.6))


## Every peer removes a bullet that hits; only the shooter's copy reports it.
func _on_area_entered(area: Area2D) -> void:
	if taken or astronaut or multiplayer.multiplayer_peer == null or not area.is_in_group("bullet") or area.is_heal():
		return
	area.queue_free()
	Sparks.at_hit(self, area.position, area.direction, area.color, 5)
	if area.is_mine():
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.report(&"report_pod_hit", [String(name), area.damage()])
			if area.shooter == multiplayer.get_unique_id():
				DamageNumber.on(self, self, area.damage())


## Blows up with a very small explosion (every peer, from Game.destroy_pod).
## The effect goes in `effects` since the pod itself is freed.
func burst(effects: Node) -> void:
	SpriteEffect.spawn(effects, position, SpriteEffect.explosion_frames(WreckScript.FIRE_RAMPS[0]), BURST_HEIGHT)
	var sound := AudioStreamPlayer.new()
	sound.stream = BURST_SOUND
	sound.volume_db = -10.0
	sound.pitch_scale = 1.6
	sound.finished.connect(sound.queue_free)
	effects.add_child(sound)
	sound.play()
