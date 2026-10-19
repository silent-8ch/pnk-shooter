class_name ShipPanel
extends Control
## The ship's systems, in small LCARS popups (see LCARS and Systems). During
## play only a SHIP pill shows, bottom left above the ActionBar (bottom right
## for right-handed controls, see Settings, popups too), with the
## reactor bars spare and the exp to spend; it glows while there's something
## the exp can buy. Tapping it opens the systems popup: a row per system
## (plus the reactor and the hull) with its power. Tapping a row opens that
## system's popup: power - and +, an UPGRADE (or INSTALL) pill for more
## capacity, and what belongs to it (guns under WEAPONS, drones under DRONES,
## armor and spare ships under HULL), each with its own buy pill. BACK goes
## up a level; tapping SHIP again or anywhere outside closes it all. The game
## carries on underneath. Touches are read directly like the ActionBar;
## PointerControls ignores touches here, and while a popup is open any tap
## that isn't on the ActionBar belongs to it.

const MARGIN := 8.0
const TAB_SIZE := Vector2(170, 40)
const GLOW_RATE := 1.5  # glows per second while something's affordable
const WIDTH := 300.0
const ROW := 34.0
const GAP := 6.0
const MOUSE_INDEX := -2
const SYSTEMS_PAGE := &"systems"
## Rows of the systems popup, top to bottom.
const ROWS: Array[StringName] = [&"reactor", &"shields", &"engines", &"weapons", &"drones", &"medbay", &"piloting", &"hull"]
const COLORS := {
	&"reactor": LCARS.ORANGE, &"shields": LCARS.BLUE, &"engines": LCARS.PEACH, &"weapons": LCARS.RED,
	&"drones": LCARS.LAVENDER, &"medbay": LCARS.TAN, &"piloting": LCARS.BLUE, &"hull": LCARS.PEACH,
}
const NAMES := {&"reactor": "REACTOR", &"hull": "HULL"}
const ABOUT := {
	&"reactor": "POWER FOR EVERY SYSTEM",
	&"shields": "1 FRONT  2 REAR  3 FAST RECHARGE",
	&"engines": "MORE SPEED PER BAR",
	&"weapons": "BARS FOR ARMED GUNS",
	&"drones": "A BAR PER DRONE, OPTIONS FIRST",
	&"medbay": "1 REPAIR KITS  2 HEAL NEARBY  3 FAST KITS",
	&"piloting": "1 AUTOPILOT  2 BEACON",
	&"hull": "ARMOR AND SPARE SHIPS",
}
## The Systems section listed under each popup.
const SECTIONS := {&"weapons": "WEAPONS", &"drones": "DRONES", &"hull": "HULL"}

var page := &""  # &"" closed, SYSTEMS_PAGE, or the row it's showing


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_active() -> bool:
	return visible and get_parent().visible


func is_open() -> bool:
	return page != &""


func close() -> void:
	page = &""
	queue_redraw()


func tab_rect() -> Rect2:
	var bottom := get_viewport_rect().size.y - ActionBar.BAR_HEIGHT - MARGIN
	return Rect2(Vector2(_left(TAB_SIZE.x), bottom - TAB_SIZE.y), TAB_SIZE)


## The left edge of something `width` wide against the near side.
func _left(width: float) -> float:
	return MARGIN if Settings.left_handed else get_viewport_rect().size.x - MARGIN - width


## The open popup, sized to its rows, sitting on top of the tab.
func popup_rect() -> Rect2:
	var rows := _row_count()
	var h := LCARS.TOP_BAR + 12.0 + rows * (ROW + GAP) + 12.0
	return Rect2(Vector2(_left(WIDTH), tab_rect().position.y - GAP - h), Vector2(WIDTH, h))


func _content() -> Rect2:
	var r := popup_rect()
	return Rect2(r.position + Vector2(LCARS.ELBOW + 8.0, LCARS.TOP_BAR + 12.0), Vector2(r.size.x - LCARS.ELBOW - 16.0, r.size.y))


func _row_rect(i: int) -> Rect2:
	var c := _content()
	return Rect2(c.position + Vector2(0, i * (ROW + GAP)), Vector2(c.size.x, ROW))


func _row_count() -> int:
	if page == SYSTEMS_PAGE:
		return ROWS.size()
	var n := 3  # BACK + about, POWER (or level), UPGRADE
	if SECTIONS.has(page):
		n += _items().size()
	return n


## Systems items listed under the open popup.
func _items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for it in Systems.ITEMS:
		if it.section == SECTIONS.get(page, "") and not it.get("system", false):
			out.append(it)
	return out


## Every tappable pill on screen now: {rect, action, id}. Drawing and taps
## both go by this list.
func buttons() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"rect": tab_rect(), "action": &"tab", "id": &""}]
	if page == SYSTEMS_PAGE:
		for i in ROWS.size():
			out.append({"rect": _row_rect(i), "action": &"open", "id": ROWS[i]})
	elif is_open():
		var top := _row_rect(0)
		out.append({"rect": Rect2(top.position, Vector2(70, ROW)), "action": &"back", "id": &""})
		if Systems.is_system(page):
			var pr := _row_rect(1)
			out.append({"rect": Rect2(Vector2(pr.end.x - 96, pr.position.y), Vector2(44, ROW)), "action": &"power_down", "id": page})
			out.append({"rect": Rect2(Vector2(pr.end.x - 46, pr.position.y), Vector2(44, ROW)), "action": &"power_up", "id": page})
		if page != &"hull":
			out.append({"rect": _row_rect(2), "action": &"buy", "id": page})
		var items := _items()
		for i in items.size():
			var r := _row_rect(3 + i)
			out.append({"rect": Rect2(Vector2(r.end.x - 86, r.position.y), Vector2(86, ROW)), "action": &"buy", "id": items[i].id})
	return out


## The pill under `canvas_pos`, or {}.
func button_at(canvas_pos: Vector2) -> Dictionary:
	for b in buttons():
		if b.rect.has_point(canvas_pos):
			return b
	return {}


## True if a screen position belongs to the panel (so it isn't a move tap):
## the tab, or anywhere off the ActionBar while a popup is open.
func contains(screen_pos: Vector2) -> bool:
	if not is_active():
		return false
	var at := _to_canvas(screen_pos)
	if tab_rect().has_point(at):
		return true
	return is_open() and at.y < get_viewport_rect().size.y - ActionBar.BAR_HEIGHT


func _to_canvas(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _local_player() -> Node:
	var game := get_tree().get_first_node_in_group("game") if is_inside_tree() else null
	return game.local_player() if game else null


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
	get_viewport().set_input_as_handled()
	tap(_to_canvas(pos))


## A tap at `canvas_pos` (already known to be ours).
func tap(canvas_pos: Vector2) -> void:
	var b := button_at(canvas_pos)
	if b.is_empty():
		if not popup_rect().has_point(canvas_pos):
			close()  # outside: put it away
		return
	var game := get_tree().get_first_node_in_group("game")
	var live: bool = game == null or game.input_enabled
	var p := _local_player()
	match b.action:
		&"tab":
			page = &"" if is_open() else SYSTEMS_PAGE
		&"open":
			page = b.id
		&"back":
			page = SYSTEMS_PAGE
		&"power_up":
			if p and live:
				p.add_power(b.id)
		&"power_down":
			if p and live:
				p.remove_power(b.id)
		&"buy":
			if p and live:
				p.buy_upgrade(b.id)
	queue_redraw()


func _process(_delta: float) -> void:
	if is_active():
		queue_redraw()


func _draw() -> void:
	var p := _local_player()
	if p == null:
		return
	var font := get_theme_default_font()
	var tab := tab_rect()
	var c := LCARS.ORANGE if is_open() else LCARS.PEACH
	if not is_open() and can_buy_something(p):
		c = LCARS.PEACH.lerp(Color.WHITE, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * GLOW_RATE))
	LCARS.pill(self, tab, c)
	LCARS.label(self, Rect2(tab.position, Vector2(tab.size.x * 0.5, tab.size.y)), "SHIP  %d" % p.power_spare(), font, LCARS.BLACK, 16, HORIZONTAL_ALIGNMENT_LEFT)
	LCARS.label(self, Rect2(tab.position + Vector2(tab.size.x * 0.45, 0), Vector2(tab.size.x * 0.55, tab.size.y)), "EXP %d" % p.exp_balance, font, LCARS.BLACK, 14, HORIZONTAL_ALIGNMENT_RIGHT)
	if page == SYSTEMS_PAGE:
		_draw_systems(p, font)
	elif is_open():
		_draw_system(p, font)


## Whether `p`'s exp can buy anything now.
static func can_buy_something(p: Node) -> bool:
	for it in Systems.ITEMS:
		if p.can_afford(it.id):
			return true
	return false


func _draw_systems(p: Node, font: Font) -> void:
	LCARS.panel(self, popup_rect(), LCARS.ORANGE, "SYSTEMS  EXP %d" % p.exp_balance, font)
	for i in ROWS.size():
		var id := ROWS[i]
		var r := _row_rect(i)
		var c: Color = COLORS[id]
		var have: bool = id == &"reactor" or id == &"hull" or p.levels.get(id, 0) > 0
		if have:
			LCARS.pill(self, r, c)
		else:
			LCARS.pill_outline(self, r, c)
		var text_color := LCARS.BLACK if have else c
		LCARS.label(self, Rect2(r.position, Vector2(120, r.size.y)), _name(id), font, text_color, 14, HORIZONTAL_ALIGNMENT_LEFT)
		var at := Vector2(r.position.x + 128, r.position.y + 10)
		if id == &"reactor":
			LCARS.pips(self, at, p.reactor(), p.power_spare(), LCARS.BLACK, Vector2(7, 14), 2.0)
		elif Systems.is_system(id) and have:
			LCARS.pips(self, at, p.levels.get(id, 0), p.power_of(id), LCARS.BLACK)
		elif not have:
			LCARS.label(self, Rect2(at.x - 8, r.position.y, 120, r.size.y), "NOT INSTALLED", font, c, 11, HORIZONTAL_ALIGNMENT_LEFT)


func _draw_system(p: Node, font: Font) -> void:
	var c: Color = COLORS.get(page, LCARS.ORANGE)
	LCARS.panel(self, popup_rect(), c, _name(page), font)
	for b in buttons():
		if b.action == &"back":
			LCARS.pill(self, b.rect, LCARS.LAVENDER)
			LCARS.label(self, b.rect, "BACK", font, LCARS.BLACK, 13)
	var top := _row_rect(0)
	LCARS.label(self, Rect2(top.position + Vector2(74, 0), top.size - Vector2(74, 0)), ABOUT.get(page, ""), font, c, 11, HORIZONTAL_ALIGNMENT_LEFT)
	var row := _row_rect(1)
	if Systems.is_system(page):
		LCARS.label(self, Rect2(row.position, Vector2(70, ROW)), "POWER", font, c, 13, HORIZONTAL_ALIGNMENT_LEFT)
		LCARS.pips(self, row.position + Vector2(76, 10), p.levels.get(page, 0), p.power_of(page), c)
		for b in buttons():
			if b.action == &"power_down" or b.action == &"power_up":
				var ok: bool = p.power_of(page) > 0 if b.action == &"power_down" else p.power_of(page) < p.levels.get(page, 0) and p.power_spare() > 0
				LCARS.pill(self, b.rect, c if ok else LCARS.DIM)
				LCARS.label(self, b.rect, "-" if b.action == &"power_down" else "+", font, LCARS.BLACK, 20)
	elif page == &"reactor":
		LCARS.label(self, Rect2(row.position, Vector2(70, ROW)), "BARS", font, c, 13, HORIZONTAL_ALIGNMENT_LEFT)
		LCARS.pips(self, row.position + Vector2(76, 10), p.reactor(), p.power_spare(), c, Vector2(7, 14), 2.0)
		LCARS.label(self, Rect2(row.position, row.size), "%d SPARE" % p.power_spare(), font, c, 12, HORIZONTAL_ALIGNMENT_RIGHT)
	for b in buttons():
		if b.action != &"buy":
			continue
		if b.id == page:
			_draw_buy(p, font, b.rect, page, c, "INSTALL" if p.levels.get(page, 0) == 0 else "UPGRADE")
		else:
			var it := Systems.item(b.id)
			var r := Rect2(Vector2(row.position.x, b.rect.position.y), Vector2(row.size.x - 92, ROW))
			var label: String = it.label + ("  %dP" % it.power if it.get("power", 0) > 0 else "")
			LCARS.label(self, Rect2(r.position, Vector2(r.size.x, 18)), label, font, c, 12, HORIZONTAL_ALIGNMENT_LEFT)
			LCARS.pips(self, r.position + Vector2(10, 21), it.max, p.levels.get(b.id, 0), c, Vector2(8, 8), 2.0)
			_draw_buy(p, font, b.rect, b.id, c, "BUY" if p.levels.get(b.id, 0) == 0 else "+")


## A buy pill: lit with its price when affordable, dim otherwise, MAX at the top.
func _draw_buy(p: Node, font: Font, r: Rect2, id: StringName, c: Color, verb: String) -> void:
	var level: int = p.levels.get(id, 0)
	if level >= Systems.max_level(id):
		LCARS.pill_outline(self, r, c)
		LCARS.label(self, r, "MAX", font, c, 13)
		return
	LCARS.pill(self, r, c if p.can_afford(id) else LCARS.DIM)
	LCARS.label(self, r, "%s %d" % [verb, p.price(id)], font, LCARS.BLACK if p.can_afford(id) else c, 13)


static func _name(id: StringName) -> String:
	if NAMES.has(id):
		return NAMES[id]
	return Systems.item(id).get("label", String(id).to_upper())
