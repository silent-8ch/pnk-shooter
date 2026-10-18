class_name HighScores
extends RefCounted
## Log of finished runs on this device (user://high_scores.json), best first:
## furthest stage, then score. Each entry: {score, stage, players, date}.

const PATH := "user://high_scores.json"
const MAX_ENTRIES := 100

static var path := PATH  # tests point this elsewhere


## Logs a run and returns its rank (1 = best), or 0 if it didn't make the log.
static func add(entry: Dictionary) -> int:
	var all := load_all()
	var e := {"score": int(entry.get("score", 0)), "stage": int(entry.get("stage", 1)),
		"players": Array(entry.get("players", [])).map(func(n): return str(n)),
		"date": str(entry.get("date", ""))}
	all.append(e)
	all.sort_custom(_better)
	var rank := all.find(e) + 1
	if all.size() > MAX_ENTRIES:
		all.resize(MAX_ENTRIES)
		if rank > MAX_ENTRIES:
			rank = 0
	_save(all)
	return rank


## The best `n` runs.
static func top(n: int) -> Array:
	return load_all().slice(0, n)


## Every logged run, best first. A missing or broken file is an empty log.
static func load_all() -> Array:
	if not FileAccess.file_exists(path):
		return []
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return []
	var data: Variant = json.data
	if not data is Array:
		return []
	var out: Array = (data as Array).filter(func(e): return e is Dictionary and e.has("score") and e.has("stage"))
	for e in out:
		e.score = int(e.score)
		e.stage = int(e.stage)
	out.sort_custom(_better)
	return out


static func clear() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if a.stage != b.stage:
		return a.stage > b.stage
	return a.score > b.score


## Writes to a temp file first, so a crash mid-write never loses the log.
static func _save(all: Array) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(all, "  "))
	f.close()
	DirAccess.rename_absolute(tmp, path)
