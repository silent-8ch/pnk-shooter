extends GutTest
## Thrusters: every ship's jets fire the way its course changes (main engine
## to push up, nose jets down, side jets left and right), worked out locally
## from how the ship moves.

const PlayerScene := preload("res://scenes/player.tscn")

var _saved_peer: MultiplayerPeer


func before_each() -> void:
	_saved_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func after_each() -> void:
	multiplayer.multiplayer_peer = _saved_peer


func test_each_push_lights_its_jet() -> void:
	assert_gt(Thrusters.jets(Vector2.UP).up, 0.9, "main engine to go up")
	assert_gt(Thrusters.jets(Vector2.DOWN).down, 0.9, "nose jets to go down")
	assert_gt(Thrusters.jets(Vector2.LEFT).left, 0.9)
	assert_gt(Thrusters.jets(Vector2.RIGHT).right, 0.9)
	assert_eq(Thrusters.jets(Vector2.UP).down, 0.0)


func test_jets_point_away_from_the_push() -> void:
	var t := Thrusters.new()
	t.radius = 20.0
	assert_eq(t.nozzle("up")[1], Vector2.DOWN, "the main engine blows down to push up")
	assert_gt(t.nozzle("left")[0].x, 0.0, "pushing left fires the right-side jet")
	t.free()


func test_speeding_up_sideways_fires_the_side_jet() -> void:
	var holder := Node2D.new()
	add_child_autofree(holder)
	var t := Thrusters.new()
	holder.add_child(t)
	t._process(1.0 / 60.0)
	for i in 10:
		holder.position.x += 4.0 * i  # speeding up to the right
		t._process(1.0 / 60.0)
	assert_gt(t.thrust.x, 0.3)
	assert_gt(Thrusters.jets(t.thrust).right, 0.3)


func test_every_ship_has_them() -> void:
	var p: Node = PlayerScene.instantiate()
	add_child_autofree(p)
	assert_true(p.has_node("Thrusters"))
	var e: Node = preload("res://scenes/enemy.tscn").instantiate()
	add_child_autofree(e)
	assert_true(e.has_node("Thrusters"))



func test_jets_draw_just_under_their_ship_not_under_the_backdrop() -> void:
	var p: Node = PlayerScene.instantiate()
	add_child_autofree(p)
	var jets: Node2D = p.get_node("Thrusters")
	assert_gte(jets.z_index, 0, "a negative z hides it behind the game's background")
	assert_true(jets.show_behind_parent)
