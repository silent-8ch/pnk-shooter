class_name PowerMeter
extends Control
## Upgrade shop down the right edge, just above the ActionBar. Exp is the
## currency: the header shows the local player's balance, and tapping any slot
## buys that slot's next level if the balance covers its price. Each slot shows
## its next price (`cost` x the level being bought, so prices climb), or MAX.
## Affordable slots are lit. The upgrades themselves live on the player (see
## Player.buy_upgrade).
## The last slot, TIER II, takes TIER_CHARGES buys; then the meter switches to
## tier II and every upgrade can go further (`max` is per tier, the last entry
## carrying on; DOUBLE 2 = triple shot, SHIELD 2 = a second shield behind you).
## In tier II the same slot, now TIER III, takes TIER_CHARGES more; then it goes
## away and the meter adds the four party ROLES. Buying one picks your role for
## good (the others disappear): DPS, TANK, HEALER or MODIFIER (see Player).
## A slot's `role` entry raises its tier III max for that role only.
## Touches are read directly like the ActionBar; PointerControls ignores them.

const SLOTS: Array[Dictionary] = [
	{"id": &"speed", "cost": 1, "label": "SPEED", "max": [3, 6], "role": {&"modifier": 8}},
	{"id": &"rapid", "cost": 2, "label": "RAPID", "max": [3, 6], "role": {&"dps": 9}},
	{"id": &"double", "cost": 3, "label": "DOUBLE", "label2": "TRIPLE", "label3": "SPREAD", "max": [1, 2], "role": {&"dps": 3}},
	{"id": &"option", "cost": 4, "label": "OPTION", "max": [2, 3], "role": {&"modifier": 4}},
	{"id": &"shield", "cost": 3, "label": "SHIELD", "max": [1, 2]},
	{"id": &"armor", "cost": 3, "label": "ARMOR", "max": [1, 2], "role": {&"tank": 4}},  # +1 max hp per level
	{"id": &"rescue", "cost": 3, "label": "RESCUE", "max": [1, 1]},  # unlocks the RESCUE button
	{"id": &"repair", "cost": 3, "label": "REPAIR", "max": [1, 1]},  # unlocks the REPAIR button
	{"id": &"missile", "cost": 4, "label": "MISSILE", "max": [3, 6], "role": {&"dps": 9}},  # unlocks the MISSILE button; each level adds a missile per salvo
	{"id": &"auto", "cost": 4, "label": "AUTOCAN", "max": [1, 2]},  # unlocks the AUTO button; 2 = fires twice as fast
	{"id": &"beacon", "cost": 2, "label": "BEACON", "max": [1, 1]},  # friendly beacon: other players' autocannons and missiles skip you
	{"id": &"beam", "cost": 6, "label": "BEAM", "max": [0, 3], "role": {&"dps": 5}},  # tier II: unlocks BEAM; levels thicken and lengthen it
	{"id": &"ship", "cost": 6, "label": "+SHIP", "max": [0, 3]},  # tier II: a spare ship for the party (Game.spares)
	{"id": &"tier", "cost": 4, "label": "TIER II", "label2": "TIER III", "max": [3, 6, 0]},  # charges (counted from the start); gone in tier III
	{"id": &"dps", "cost": 8, "label": "DPS", "max": [0, 0, 1], "pick": true},
	{"id": &"tank", "cost": 8, "label": "TANK", "max": [0, 0, 1], "pick": true},
	{"id": &"healer", "cost": 8, "label": "HEALER", "max": [0, 0, 1], "pick": true},
	{"id": &"modifier", "cost": 8, "label": "MODIFIER", "max": [0, 0, 1], "pick": true},
]
const ROLES: Array[StringName] = [&"dps", &"tank", &"healer", &"modifier"]
const ROLE_COLORS := {&"dps": Color("ff5a5a"), &"tank": Color("5aa8ff"), &"healer": Color("6dff7a"), &"modifier": Color("ffd45a")}
const TIER_CHARGES := 3
const TIER2_COLOR := Color("c08dff")
const TIER3_COLOR := Color("ffb347")
const SLOT_SIZE := Vector2(76, 48)
const GAP := 6.0
const MARGIN := 8.0
const COUNT_HEIGHT := 28.0  # exp balance above the slots
const LIT_COLOR := Color("ffd45a")
const MOUSE_INDEX := -2


## The slots shown in `tier` (1-3) for a ship with `role` (&"" = none picked yet), top to bottom.
static func slots_for(tier: int, role := &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in SLOTS:
		if max_level(s.id, tier, role) > 0:
			out.append(s)
	return out


## Index of `id` among the slots shown in `tier`, or -1.
static func slot_index(id: StringName, tier := 1, role := &"") -> int:
	var shown := slots_for(tier, role)
	for i in shown.size():
		if shown[i].id == id:
			return i
	return -1


## Highest level of `id` in `tier` for a ship with `role`. Once a role is
## picked, the other roles can't be bought.
static func max_level(id: StringName, tier: int, role := &"") -> int:
	for s in SLOTS:
		if s.id == id:
			if s.get("pick", false) and role != &"" and role != id:
				return 0
			if tier >= 3 and s.has("role") and s.role.has(role):
				return s.role[role]
			var m: Array = s.max
			return m[mini(clampi(tier, 1, 3), m.size()) - 1]
	return 0


## Exp the next level of `id` costs, given the `level` already bought:
## its base cost times the level being bought.
static func price(id: StringName, level: int) -> int:
	for s in SLOTS:
		if s.id == id:
			return s.cost * (level + 1)
	return 0


## Slot label for `tier`: tier II names the next step where it differs.
static func label_for(s: Dictionary, tier: int, level: int) -> String:
	if tier >= 3 and s.has("label3") and level >= 2:
		return s.label3
	if tier >= 2 and s.has("label2") and level >= 1:
		return s.label2
	return s.label


func _tier() -> int:
	var p := _local_player()
	return p.tier if p else 1


func _role() -> StringName:
	var p := _local_player()
	return p.role() if p else &""


func _shown() -> Array[Dictionary]:
	return slots_for(_tier(), _role())


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_active() -> bool:
	return visible and get_parent().visible


## The whole meter (balance header plus slots), in canvas coordinates.
func meter_rect() -> Rect2:
	var n := _shown().size()
	var top := slot_rect(0).position.y - COUNT_HEIGHT
	return Rect2(Vector2(slot_rect(0).position.x, top), Vector2(SLOT_SIZE.x, slot_rect(n - 1).end.y - top))


## Slot i of the current tier's slots; the column grows up from above the ActionBar.
## Slots shrink (never grow) so a long column still fits under the header.
func slot_rect(i: int) -> Rect2:
	var n := _shown().size()
	var size := get_viewport_rect().size
	var bottom := size.y - ActionBar.BAR_HEIGHT - MARGIN
	var h := minf(SLOT_SIZE.y, (bottom - COUNT_HEIGHT - MARGIN) / maxi(n, 1) - GAP)
	var y := bottom - (n - i) * (h + GAP) + GAP
	return Rect2(Vector2(size.x - MARGIN - SLOT_SIZE.x, y), Vector2(SLOT_SIZE.x, h))


## True if a screen position falls on the meter (so it isn't a move tap).
func contains(screen_pos: Vector2) -> bool:
	return is_active() and meter_rect().has_point(_to_canvas(screen_pos))


## Index of the current tier's slot under `canvas_pos`, or -1 (the header and
## gaps hit no slot).
func slot_at(canvas_pos: Vector2) -> int:
	for i in _shown().size():
		if slot_rect(i).has_point(canvas_pos):
			return i
	return -1


func _to_canvas(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _local_player() -> Node:
	var game := get_tree().get_first_node_in_group("game")
	return game.local_player() if game else null


func _accepting_input() -> bool:
	if not is_active():
		return false
	var game := get_tree().get_first_node_in_group("game")
	return game == null or game.input_enabled


func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	else:
		return
	if not contains(pos):
		return
	get_viewport().set_input_as_handled()  # header taps too, so they aren't move taps
	if not _accepting_input():
		return
	var i := slot_at(_to_canvas(pos))
	var p := _local_player()
	if p and i >= 0:
		p.buy_upgrade(_shown()[i].id)


func _process(_delta: float) -> void:
	if is_active():
		queue_redraw()


func _draw() -> void:
	var p := _local_player()
	var font := get_theme_default_font()
	var tier := _tier()
	var count := "EXP %d" % (p.exp_balance if p else 0)
	if tier >= 2:
		count += "  " + "I".repeat(mini(tier, 3))
	var top := meter_rect().position
	var frame := TIER3_COLOR if tier >= 3 else TIER2_COLOR if tier >= 2 else Color.WHITE
	_draw_centered(font, count, Rect2(top, Vector2(SLOT_SIZE.x, COUNT_HEIGHT)), 16, frame)
	var shown := _shown()
	for i in shown.size():
		var s: Dictionary = shown[i]
		var r := slot_rect(i)
		var lit: bool = p != null and p.can_afford(s.id)
		var maxed: bool = p != null and not p.can_upgrade(s.id)
		var fill := Color(LIT_COLOR, 0.85) if lit else Color(0.1, 0.12, 0.2, 0.55)
		var edge: Color = ROLE_COLORS.get(s.id, frame)
		draw_rect(r, fill)
		draw_rect(r, Color(LIT_COLOR if lit else edge, 0.9), false, 2.0)
		var text_color := Color.BLACK if lit else Color(1, 1, 1, 0.35 if maxed else 0.9)
		var level: int = p.level(s.id) if p else 0
		_draw_centered(font, label_for(s, tier, level), Rect2(r.position + Vector2(0, 6), Vector2(r.size.x, r.size.y - 16)), 14, text_color)
		var pips := max_level(s.id, tier, _role())
		var step := minf(12.0, (r.size.x - 12.0) / pips)
		for k in pips:  # level pips
			var pip := Rect2(r.position + Vector2(6 + k * step, r.size.y - 12), Vector2(step - 4, 5))
			draw_rect(pip, text_color if k < level else Color(text_color, 0.25))
		var tag := "MAX" if maxed else str(price(s.id, level))
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, r.position + Vector2(r.size.x - tw - 4, 12), tag,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, text_color)  # next price, top right


func _draw_centered(font: Font, text: String, r: Rect2, fs: int, c: Color) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, r.position + Vector2((r.size.x - tw) / 2.0, r.size.y / 2.0 + fs / 3.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
