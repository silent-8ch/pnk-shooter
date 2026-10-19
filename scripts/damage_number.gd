class_name DamageNumber
extends Node2D
## MMO-style damage numbers for this player's hits (and the damage they
## take, in red): hit points x SCALE, so a photon hit reads 100. Hits on the
## same target within MERGE_TIME roll into one number that ticks up and
## follows it; once they stop, it floats up and fades. Local only.

const SCALE := 100.0
const MERGE_TIME := 0.35  # s of quiet before a number lets go of its target
const FLOAT_TIME := 0.8  # s it floats and fades after that
const RISE := 40.0  # px it floats up
const OFFSET := Vector2(0, -24)  # above what it's on
const FONT_SIZE := 20
const DEAL := Color("fff2b0")  # damage you deal
const HEAL := Color("7dff8a")  # healing (or strengthening) you give
const TAKE := Color("ff4a4a")  # damage you take

var target: Node2D
var amount := 0.0
var color := DEAL
var heal := false
var _quiet := 0.0  # s since the last hit added to it
var _float := -1.0  # s floating away; < 0 while it's still taking hits
var _last_pos := Vector2.ZERO


## `hits` worth on `target`, shown in `effects` (merged into its current number, if any).
static func add(effects: Node, target: Node2D, hits: float, c := DEAL, is_heal := false) -> DamageNumber:
	if effects == null or target == null or hits <= 0.0:
		return null
	for n in effects.get_children():
		if n is DamageNumber and n.target == target and n.heal == is_heal and n.color == c and n._float < 0.0:
			n.amount += hits
			n._quiet = 0.0
			return n
	var d := DamageNumber.new()
	d.target = target
	d.amount = hits
	d.color = c
	d.heal = is_heal
	d.z_index = 45
	d._last_pos = target.position
	d.position = target.position + OFFSET
	effects.add_child(d)
	return d


## Through the game's effects layer, if there's a game (`from`: any node in it).
static func on(from: Node, target: Node2D, hits: float, c := DEAL, is_heal := false) -> void:
	if from == null or not from.is_inside_tree():
		return
	var game := from.get_tree().get_first_node_in_group("game")
	if game and game.get("effects"):
		add(game.effects, target, hits, c, is_heal)


func text() -> String:
	return ("+%d" if heal else "%d") % maxi(1, roundi(amount * SCALE))


func _process(delta: float) -> void:
	if _float < 0.0:
		_quiet += delta
		if is_instance_valid(target) and target.is_inside_tree():
			_last_pos = target.position
		position = _last_pos + OFFSET
		if _quiet >= MERGE_TIME:
			_float = 0.0
	else:
		_float += delta
		if _float >= FLOAT_TIME:
			queue_free()
			return
		position = _last_pos + OFFSET + Vector2(0, -RISE * _float / FLOAT_TIME)
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var words := text()
	var a := 1.0 if _float < 0.0 else 1.0 - pow(_float / FLOAT_TIME, 2.0)
	var pop := 1.0 + 0.25 * maxf(0.0, 1.0 - _quiet / 0.12)  # swells for a moment on each hit
	var fs := int(FONT_SIZE * pop)
	var w := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2(-w / 2.0, 0)
	draw_string_outline(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, a))
	draw_string(font, at, words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, a))
