class_name StageBar
extends Control
## The HUD's progress line, under the StatusBar and in the same console look:
## how far through this stage the party is.
##
## A stage runs on kills, not on time — the level file loops until enough
## enemies are down (Game.boss_kills_needed, which grows every stage). So the
## track fills with the kills, with a landmark diamond halfway where the ELITE
## mini boss comes in (Game.mini_boss_kills) and one at the far end for the
## boss. Passed landmarks light up; the one ahead stays dim, so a glance says
## both how far in you are and what is coming next.
##
## The count sits on the right ("18/40"), or the word for what is happening
## when the stage has stopped being about kills: ELITE or BOSS while one is up
## (kills don't count then, see Game.destroy_enemy, so the track holds its
## place), REFIT between them and PATH at the fork.

const HEIGHT := 18.0
const LABEL_WIDTH := 86.0  # px kept on the right for the count
const GAP := 8.0
const MARK := 5.0  # half the width of a landmark diamond
const FONT_SIZE := 12
const ELITE_AT := 0.5  # where the mini boss lands on the track (mini_boss_kills is half)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _game() -> Node:
	return get_tree().get_first_node_in_group("game") if is_inside_tree() else null


## The track the kills fill, left of the count.
func track_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(maxf(size.x - LABEL_WIDTH - GAP, 20.0), HEIGHT))


func label_rect() -> Rect2:
	return Rect2(Vector2(track_rect().end.x + GAP, 0.0), Vector2(LABEL_WIDTH, HEIGHT))


## What the bar shows now: how full the track is (0..1), the text on the right,
## the color both are drawn in, and whether the mini boss landmark is behind us.
func state() -> Dictionary:
	var game := _game()
	if game == null:
		return {"fill": 0.0, "text": "", "color": UiStyle.CYAN, "elite_passed": false}
	var needed: int = maxi(game.boss_kills_needed(), 1)
	var kills: int = clampi(game.kills, 0, needed)
	var fill := float(kills) / needed
	var passed: bool = kills >= game.mini_boss_kills()
	if game.fork_open():
		return {"fill": 1.0, "text": "PATH", "color": UiStyle.VIOLET, "elite_passed": true}
	if game.refit:
		return {"fill": 1.0, "text": "REFIT", "color": UiStyle.VIOLET, "elite_passed": true}
	if game.boss_alive():
		return {"fill": 1.0, "text": "BOSS", "color": UiStyle.MAGENTA, "elite_passed": true}
	if game.elite_alive():
		return {"fill": maxf(fill, ELITE_AT), "text": "ELITE", "color": UiStyle.AMBER, "elite_passed": true}
	return {"fill": fill, "text": "%d/%d" % [kills, needed], "color": UiStyle.CYAN, "elite_passed": passed}


func _draw() -> void:
	if _game() == null:
		return
	var font := get_theme_default_font()
	var s := state()
	var track := track_rect()
	UiStyle.button(self, track, UiStyle.DIM)
	var fill: float = s.fill
	if fill > 0.0:
		UiStyle.button(self, Rect2(track.position, Vector2(track.size.x * fill, track.size.y)), s.color)
	_draw_mark(track, ELITE_AT, UiStyle.AMBER, s.elite_passed)
	_draw_mark(track, 1.0, UiStyle.MAGENTA, fill >= 1.0)
	var box := label_rect()
	UiStyle.button(self, box, s.color)
	UiStyle.label(self, box, s.text, font, UiStyle.INK, FONT_SIZE)


## A landmark on the track: a diamond, solid once it's behind us and an outline
## while it's still ahead.
func _draw_mark(track: Rect2, at: float, c: Color, passed: bool) -> void:
	var x := track.position.x + track.size.x * at
	var mid := track.position.y + track.size.y / 2.0
	var pts := PackedVector2Array([
		Vector2(x, mid - track.size.y / 2.0), Vector2(x + MARK, mid),
		Vector2(x, mid + track.size.y / 2.0), Vector2(x - MARK, mid),
	])
	if passed:
		draw_colored_polygon(pts, c)
		return
	draw_colored_polygon(pts, UiStyle.GLASS)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, c, 1.5, true)
