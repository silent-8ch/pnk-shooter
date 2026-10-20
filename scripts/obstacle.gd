extends Area2D
## Terrain obstacle: asteroids and broken space-station pieces that scroll down
## slowly so players have to fly around them instead of sitting in one lane.
## Pieces come from assets/obstacles/pieces.json (shared with the level
## designer): size, collision shape (circle or rect), hp (0 = indestructible),
## spin, and an outline. A "tile" piece repeats side by side for `count`
## segments, with its broken-end caps at both ends, so one drawn segment makes
## a girder or hull run of any length.
##
## Art: assets/obstacles/<piece id>.png or .svg, drawn at the piece's size.
## Until a piece has art, its outline is drawn with its id on it. A piece with a
## <piece id>_normal.png beside its art (tools/bake_asteroid_normals.gd) is lit
## like the ships (lit_art, Ships.LIGHT_MASK): shaded by the sun, dimmed out of it.
##
## Solid to players: Game.resolve_obstacles pushes ships out (the owner does
## this for its own ship), and a ship pinned against the bottom of the screen is
## crushed. Blocks every bullet. Destructible pieces take shots like enemies
## (the host keeps their hp). Local on every peer: the host announces each one
## (Game.spawn_obstacle) and every peer scrolls it the same way.
## About one breakable piece in LOOT_ODDS carries an exp inside (`loot`, from
## its name, so every peer agrees): it flashes through the exp pickup's colors,
## and breaking it drops an exp pickup where it was (Game.report_obstacle_hit).

const PIECES_PATH := "res://assets/obstacles/pieces.json"
const ART_DIR := "res://assets/obstacles/"
const ARENA_HEIGHT := 960.0
const SPAWN_GAP := 10.0  # spawns this far above the top edge
const EDGE := 20.0  # lane margin, like enemy groups
const LANES := 9
const SPIN_RANGE := Vector2(0.3, 1.2)  # rad/s, for pieces that spin
const CIRCLE_FIT := 0.9  # circle collision radius vs half the piece width
const OUTLINE_COLOR := Color(0.75, 0.68, 0.6, 0.9)
const FILL_COLOR := Color(0.2, 0.18, 0.17, 0.95)
const LABEL_COLOR := Color(1, 1, 1, 0.55)
const FLASH_TIME := 0.08
const LOOT_ODDS := 6  # one breakable piece in this many carries an exp
const LOOT_TINT := 0.6  # how far its color cycle tints it
const PickupScript := preload("res://scripts/pickup.gd")
const SpriteEffect := preload("res://scripts/sprite_effect.gd")
const WreckScript := preload("res://scripts/wreck.gd")

static var _catalog: Dictionary  # id -> piece
static var _scroll_speed := 60.0

var piece_id := ""
var count := 1  # segments, for a tile piece
var mirror := false
var hp := 0.0  # host: damage left (destructible pieces)
var parts: Array[Dictionary] = []  # {piece, offset}
var spin := 0.0
var _flash := 0.0
var loot := false  # carries an exp inside (see carries_loot)
var _age := 0.0


# --- Catalog --------------------------------------------------------------------

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_load_catalog()
	return _catalog


static func _load_catalog() -> void:
	if not FileAccess.file_exists(PIECES_PATH):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(PIECES_PATH)) != OK or not json.data is Dictionary:
		return
	_scroll_speed = float(json.data.get("scroll_speed", _scroll_speed))
	for p in json.data.get("pieces", []):
		if not p is Dictionary or not p.get("id") is String:
			continue
		var size: Array = p.get("size", [32, 32])
		var outline := PackedVector2Array()
		for pt in p.get("outline", []):
			outline.append(Vector2(pt[0], pt[1]))
		_catalog[p.id] = {
			"id": p.id,
			"size": Vector2(size[0], size[1]),
			"shape": p.get("shape", "rect"),
			"hp": float(p.get("hp", 0)),
			"spin": p.get("spin", false) == true,
			"tile": p.get("tile", false) == true,
			"cap": p.get("cap", false) == true,
			"caps": p.get("caps", []),
			"outline": outline,
		}


static func scroll_speed() -> float:
	catalog()
	return _scroll_speed


static func piece(id: String) -> Dictionary:
	return catalog().get(id, {})


## True for a piece a level may place (not an end cap).
static func placeable(id: String) -> bool:
	var p := piece(id)
	return not p.is_empty() and not p.cap


## The pieces making up one obstacle, left to right: a tile piece repeats
## `count` times between its caps; anything else is a single piece.
static func layout(id: String, count: int) -> Array[Dictionary]:
	var p := piece(id)
	var out: Array[Dictionary] = []
	if p.is_empty():
		return out
	var ids: Array = [id]
	if p.tile:
		ids = []
		if p.caps.size() == 2 and catalog().has(p.caps[0]):
			ids.append(p.caps[0])
		for i in maxi(count, 1):
			ids.append(id)
		if p.caps.size() == 2 and catalog().has(p.caps[1]):
			ids.append(p.caps[1])
	var width := 0.0
	for pid in ids:
		width += piece(pid).size.x
	var x := -width / 2.0
	for pid in ids:
		var w: float = piece(pid).size.x
		out.append({"piece": pid, "offset": Vector2(x + w / 2.0, 0)})
		x += w
	return out


## Half the width of an event's obstacles: a tile run, or a cluster of copies.
static func half_width(id: String, n: int) -> float:
	var p := piece(id)
	if p.is_empty():
		return 0.0
	if p.tile:
		var w := 0.0
		for part in layout(id, n):
			w += piece(part.piece).size.x
		return w / 2.0
	return p.size.x / 2.0 + (60.0 if n > 1 else 0.0)


## Center x for an obstacle event in `lane` (0 = left edge, 8 = right).
static func center_x(id: String, n: int, lane: int, width: float) -> float:
	var margin := half_width(id, n) + EDGE
	if margin * 2.0 >= width:
		return width / 2.0
	return lerpf(margin, width - margin, float(lane) / (LANES - 1))


static func spawn_y(id: String) -> float:
	return -piece(id).get("size", Vector2.ZERO).y / 2.0 - SPAWN_GAP


static func art(id: String) -> Texture2D:
	for ext in [".png", ".svg"]:
		if ResourceLoader.exists(ART_DIR + id + ext):
			return load(ART_DIR + id + ext)
	return null


static var _lit := {}  # piece id -> CanvasTexture


## Piece `id`'s normal map, or null if it has none.
static func normal_art(id: String) -> Texture2D:
	var path := ART_DIR + id + "_normal.png"
	return load(path) if ResourceLoader.exists(path) else null


## Piece `id`'s art with its normal map (a CanvasTexture, shared), or the plain art if it
## has no normal map; null without art.
static func lit_art(id: String) -> Texture2D:
	if _lit.has(id):
		return _lit[id]
	var tex := art(id)
	var normal := normal_art(id)
	if tex and normal:
		var lit := CanvasTexture.new()
		lit.diffuse_texture = tex
		lit.normal_texture = normal
		_lit[id] = lit
		return lit
	return tex


# --- Node -----------------------------------------------------------------------

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4  # bullets; ships are pushed out by Game.resolve_obstacles
	monitorable = false
	add_to_group("obstacle")
	var p := piece(piece_id)
	if p.is_empty():
		return
	hp = p.hp
	loot = destructible() and carries_loot(String(name))
	parts = layout(piece_id, count)
	if p.spin and not p.tile:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(name))  # the same on every peer
		spin = rng.randf_range(SPIN_RANGE.x, SPIN_RANGE.y) * (1.0 if rng.randf() < 0.5 else -1.0)
	for part in parts:
		var pp := piece(part.piece)
		var shape := CollisionShape2D.new()
		if pp.shape == "circle":
			shape.shape = CircleShape2D.new()
			shape.shape.radius = pp.size.x / 2.0 * CIRCLE_FIT
		else:
			shape.shape = RectangleShape2D.new()
			shape.shape.size = pp.size
		shape.position = part.offset
		add_child(shape)
		var tex := lit_art(part.piece)
		if tex:
			var s := Sprite2D.new()
			s.texture = tex
			s.scale = pp.size / tex.get_size()
			s.position = part.offset
			s.flip_h = mirror
			if tex is CanvasTexture:
				s.light_mask = Ships.LIGHT_MASK  # lit by the sun and dimmed like the ships
			add_child(s)
			Sun.occlude(s)
	area_entered.connect(_on_area_entered)


func destructible() -> bool:
	return piece(piece_id).get("hp", 0.0) > 0.0


## Whether the obstacle named `obstacle_name` carries an exp (if it's breakable).
static func carries_loot(obstacle_name: String) -> bool:
	return posmod(hash([obstacle_name, "loot"]), LOOT_ODDS) == 0


func _process(delta: float) -> void:
	_age += delta
	position.y += scroll_speed() * delta
	rotation += spin * delta
	if _flash > 0.0:
		_flash -= delta
		modulate = Color(3, 3, 3) if _flash > 0.0 else Color.WHITE
	elif loot:
		modulate = loot_color(_age)
	if position.y > ARENA_HEIGHT + piece(piece_id).get("size", Vector2.ZERO).y + SPAWN_GAP:
		queue_free()
	queue_redraw()


## Pushes a circle (a ship at `at`, radius `r`, in the parent's space) out of
## this obstacle. Returns the new position (unchanged if it doesn't touch).
func push_out(at: Vector2, r: float) -> Vector2:
	for part in parts:
		var pp := piece(part.piece)
		var offset: Vector2 = part.offset
		var c: Vector2 = position + offset.rotated(rotation)
		if pp.shape == "circle":
			var reach: float = pp.size.x / 2.0 * CIRCLE_FIT + r
			var d: Vector2 = at - c
			if d.length() < reach:
				at = c + (d.normalized() if d.length() > 0.01 else Vector2.DOWN) * reach
		else:
			at = _push_out_of_rect(at, r, c, pp.size / 2.0)
	return at


static func _push_out_of_rect(at: Vector2, r: float, c: Vector2, half: Vector2) -> Vector2:
	var local := at - c
	var q := local.clamp(-half, half)
	if q == local:  # center inside: out along the shallowest side
		var dx := half.x - absf(local.x)
		var dy := half.y - absf(local.y)
		if dx < dy:
			return c + Vector2(signf(local.x if local.x != 0.0 else 1.0) * (half.x + r), local.y)
		return c + Vector2(local.x, signf(local.y if local.y != 0.0 else 1.0) * (half.y + r))
	var d := local - q
	if d.length() < r:
		return c + q + d.normalized() * r
	return at


func touches(at: Vector2, r: float) -> bool:
	return push_out(at, r).distance_to(at) > 0.01


## The exp pickup's color cycle at `age`, as a tint.
static func loot_color(age: float) -> Color:
	var colors := PickupScript.STAR_COLORS
	return Color.WHITE.lerp(colors[int(age * PickupScript.CYCLE_RATE) % colors.size()], LOOT_TINT)


## Took a hit without breaking (every peer, from Game.flash_obstacle).
func flash() -> void:
	_flash = FLASH_TIME
	modulate = Color(3, 3, 3)


## Breaks apart (every peer, from Game.destroy_obstacle); the effect goes in
## `effects` since the obstacle itself is freed.
func burst(effects: Node) -> void:
	var size: Vector2 = piece(piece_id).get("size", Vector2(32, 32))
	SpriteEffect.spawn(effects, position,
		SpriteEffect.explosion_frames(WreckScript.FIRE_RAMPS[1], SpriteEffect.random_set(hash(String(name)))), size.y * 1.2)


## Every peer removes a bullet that hits; only the shooter's copy reports it.
func _on_area_entered(area: Area2D) -> void:
	if multiplayer.multiplayer_peer == null or not area.is_in_group("bullet"):
		return
	area.queue_free()
	if not area.is_heal():
		Sparks.at_hit(self, area.position, area.direction, Color("ffcf7a"), 6)
	if destructible() and area.is_mine() and not area.is_heal():  # heal shots just stop
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.report(&"report_obstacle_hit", [String(name), area.damage()])
			if area.shooter == multiplayer.get_unique_id():
				DamageNumber.on(self, self, area.damage())


## Outlines (with the piece id) for parts that have no art yet.
func _draw() -> void:
	var font := ThemeDB.fallback_font
	for part in parts:
		if art(part.piece):
			continue
		var pp := piece(part.piece)
		var pts := PackedVector2Array()
		for v: Vector2 in pp.outline:
			pts.append(part.offset + Vector2(-v.x if mirror else v.x, v.y))
		if pts.size() >= 3:
			draw_colored_polygon(pts, FILL_COLOR)
			pts.append(pts[0])
			draw_polyline(pts, OUTLINE_COLOR, 1.5, true)
		var label: String = part.piece
		var fs := 9
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw < pp.size.x + 8.0:
			draw_string(font, part.offset + Vector2(-tw / 2.0, fs / 3.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, LABEL_COLOR)
