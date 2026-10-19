class_name FunTime
extends RefCounted
## Fun time: when the clock on the wall (local system time, 12-hour, the hour
## without a leading zero) reads as a palindrome (1:21, 10:01, 12:21) or as
## digits counting up by one (1:23, 3:45, 12:34), it's a fun time for the rest
## of that minute. Every living ship gets a Droid that orbits it; at the end of
## the minute it bursts into exp pickups, one for every REWARD_EVERY s it
## stayed alive (REWARD_MAX at most: alive the whole minute). Shot down, or its
## ship lost, it bursts early into the exp it had earned.
## Host only (Game._physics_process calls update): the host's clock decides,
## it names the droids and keeps their hp, and every peer sees them by rpc.
## Each ship gets one droid per fun minute, however often it respawns.
## The clock and the seconds count are Callables, so tests can set the time.

const REWARD_EVERY := 20.0  # s alive per exp
const REWARD_MAX := 3
const GRACE := 0.5  # s: a droid alive the whole minute counts a hair under 60 s
const HIT_COOLDOWN := 0.3  # host: s after a hit a droid ignores more reports

## False in the test suite (pre_run.gd): the real clock then never reads a fun
## time, so other tests don't get droids at 1:23. Tests set `clock` instead.
static var real_clock := true

## {hour (0-23), minute} now.
var clock: Callable = func() -> Dictionary:
	return Time.get_time_dict_from_system() if real_clock else {"hour": 0, "minute": 0}
## A steady seconds count, for how long each droid lived.
var seconds: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0
var minute := -1  # the fun minute on now (hour * 60 + minute), or -1
var count := 0  # names droids uniquely
var _had := {}  # peer id -> true: got its droid this fun minute
var _born := {}  # droid name -> `seconds` when it came out
var _last_hit := {}  # droid name -> `seconds` of its last hit


## 1-12 for an hour of 0-23 (0 and 12 are both 12).
static func hour12(hour24: int) -> int:
	var h := posmod(hour24, 12)
	return 12 if h == 0 else h


## The clock's digits, H:MM without the colon: "121" for 1:21, "1221" for 12:21.
static func clock_digits(hour24: int, mins: int) -> String:
	return "%d%02d" % [hour12(hour24), mins]


## A palindrome, or every digit one more than the last (not counting down).
static func is_fun_time(hour24: int, mins: int) -> bool:
	var d := clock_digits(hour24, mins)
	if d == d.reverse():
		return true
	for i in range(1, d.length()):
		if d.unicode_at(i) != d.unicode_at(i - 1) + 1:
			return false
	return true


## Exp a droid bursts into after `alive` s.
static func reward_for(alive: float) -> int:
	return clampi(floori((alive + GRACE) / REWARD_EVERY), 0, REWARD_MAX)


## A new run: no fun minute on yet (one still going starts again on the next
## update, with droids for everyone).
func reset() -> void:
	minute = -1
	_had.clear()
	_born.clear()
	_last_hit.clear()


## Host, every physics frame: ends a fun minute that's over (every droid
## bursts), starts one that's begun, gives a droid to every living ship that
## hasn't had one this minute, and bursts any whose ship is lost or gone.
func update(game: Node) -> void:
	var t: Dictionary = clock.call()
	var h := int(t.get("hour", 0))
	var m := int(t.get("minute", 0))
	var now := h * 60 + m
	if minute != -1 and now != minute:
		finish(game)
	if not is_fun_time(h, m):
		return
	if minute != now:
		minute = now
		_had.clear()
	var have := {}
	for d in game.droids():
		have[d.peer] = true
	for p in game.players.get_children():
		if p.is_queued_for_deletion() or not p.is_alive() or _had.has(p.peer_id) or have.has(p.peer_id):
			continue
		_had[p.peer_id] = true
		count += 1
		var droid_name := "Droid%d" % count
		_born[droid_name] = seconds.call()
		game.spawn_droid.rpc(p.peer_id, droid_name)
	for d in game.droids():
		var p: Node = game.players.get_node_or_null(str(d.peer))
		if p == null or p.is_queued_for_deletion() or not p.is_alive():
			pop(game, d)


## Host: the fun minute is over; every droid bursts into what it earned.
func finish(game: Node) -> void:
	for d in game.droids():
		pop(game, d)
	minute = -1
	_had.clear()


## Host: how long droid `d` has been out.
func alive_for(d: Node) -> float:
	var now: float = seconds.call()
	return now - float(_born.get(String(d.name), now - d.age()))


## Host: droid `d` bursts into the exp it earned.
func pop(game: Node, d: Node) -> void:
	var n := String(d.name)
	game.pop_droid(n, reward_for(alive_for(d)))
	_born.erase(n)
	_last_hit.erase(n)


## Host: something hit droid `d`; it wears down, then bursts.
func hit(game: Node, d: Node) -> void:
	var n := String(d.name)
	var now: float = seconds.call()
	if _last_hit.has(n) and now - float(_last_hit[n]) < HIT_COOLDOWN:
		return
	_last_hit[n] = now
	d.hp -= 1
	if d.hp > 0:
		game.flash_droid.rpc(n)
		return
	pop(game, d)
