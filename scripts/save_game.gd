class_name SaveGame
extends RefCounted
## One saved solo run (Save and exit in the pause menu, CONTINUE on the title):
## the level kind, stage, score, spare ships and rewards, and the ship with
## everything on it (upgrades, power, armed guns, exp, its tail). A resumed
## run starts that stage from its beginning. Kept as plain JSON with a
## VERSION, so a newer build of the game can still read it: unknown keys are
## ignored and anything missing falls back to a fresh run's value. Cleared
## when the run ends.

const PATH := "user://save.json"
const VERSION := 1

static var path := PATH  # tests point this elsewhere


static func exists() -> bool:
	return not read().is_empty()


static func write(state: Dictionary) -> bool:
	var data := state.duplicate(true)
	data.version = VERSION
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_plain(data)))
	f.close()
	return true


## The saved run, or {} if there's none (or it can't be read).
static func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary or not parsed.has("kind"):
		return {}
	return parsed


static func clear() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## StringNames (upgrade ids) as plain strings, all the way down.
static func _plain(v: Variant) -> Variant:
	if v is StringName:
		return String(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[String(k) if k is StringName else k] = _plain(v[k])
		return out
	if v is Array:
		return v.map(func(x): return _plain(x))
	return v


## A saved {id: number} map back as {StringName: int}, keeping only ids this
## version of the game knows (Systems).
static func ids_map(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k in v:
			if not Systems.item(StringName(k)).is_empty():
				out[StringName(k)] = int(v[k])
	return out


static func ids_list(v: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if v is Array:
		for k in v:
			if not Systems.item(StringName(str(k))).is_empty():
				out.append(StringName(str(k)))
	return out
