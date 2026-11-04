class_name CampaignProgress
extends RefCounted
## What the player has done in The Last Light, persisted to user://progress.cfg.
##
## How many entries are open, and for each one played: cleared or not, the
## best time, and the most relics and secrets found in one run, with the
## totals they were out of. Entries unlock in Campaign's order, one clear at a
## time; a restart or a death changes none of that, only a clear does.
##
## And the run in progress: the last torch reached in an entry not yet left
## by its door, so that CONTINUE picks a chapter up where the player was
## rather than at its start -- on a phone a session ends when a call comes
## in, not when a chapter does. Its cell, the wires latched when it was taken
## and the clock then; Game.resume_at() refuses one the level no longer
## proves. A clear forgets it, and so does starting the entry from its own
## row or from RESTART CHAPTER: those are new runs (CampaignGame).
##
## ## The file
##
##     [campaign]
##     unlocked=2
##
##     [sun_terrace]
##     cleared=true
##     best_time=62.4
##     relics=4
##     relics_total=6
##     secrets=1
##     secrets_total=3
##
##     [aqueduct]
##     torch=Vector2i(41, 9)
##     torch_latched=PackedStringArray("1")
##     torch_time=95.2
##
## Sections are entry ids, not positions, so a chapter added or moved in the
## catalogue moves nobody's record. Reading is forgiving to the field, as the
## wardrobe's is: a missing or broken file, a missing section, or a value of
## the wrong type is the default for exactly that field and nothing else -- a
## best time that does not parse loses the best time, not the relics found
## beside it. What cannot be true is mended rather than believed: an entry
## after a cleared one is open, whatever `unlocked` says, and a count is never
## below zero or above its total.

const PATH := "user://progress.cfg"
const META := "campaign"
## A best time no run has set.
const NO_TIME := -1.0

var path := UserData.at(PATH)
var _unlocked := 1
## id -> {cleared, best_time, relics, relics_total, secrets, secrets_total}
var _records: Dictionary = {}
## id -> {cell: Vector2i, latched: PackedStringArray, time: float}: the last
## torch reached in a run not yet finished.
var _torches: Dictionary = {}


## The saved progress at `at`, or a fresh campaign if nothing there is usable.
static func open(at: String = "") -> CampaignProgress:
	var progress := CampaignProgress.new()
	progress.path = at if at != "" else UserData.at(PATH)
	progress.load_from_disk()
	return progress


## False when there was no usable file; every field is its default then.
func load_from_disk() -> bool:
	_unlocked = 1
	_records.clear()
	_torches.clear()
	var file := ConfigFile.new()
	if file.load(path) != OK:
		return false
	_unlocked = maxi(1, _int(file.get_value(META, "unlocked", 1), 1))
	for index: int in Campaign.count():
		var id := String(Campaign.entry(index)["id"])
		if not file.has_section(id):
			continue
		var record := _blank()
		record["cleared"] = _bool(file.get_value(id, "cleared", false))
		record["best_time"] = _time(file.get_value(id, "best_time", NO_TIME))
		record["relics_total"] = maxi(0, _int(file.get_value(id, "relics_total", 0), 0))
		record["relics"] = clampi(_int(file.get_value(id, "relics", 0), 0), 0,
			int(record["relics_total"]))
		record["secrets_total"] = maxi(0, _int(file.get_value(id, "secrets_total", 0), 0))
		record["secrets"] = clampi(_int(file.get_value(id, "secrets", 0), 0), 0,
			int(record["secrets_total"]))
		_records[id] = record
		if bool(record["cleared"]):
			_unlocked = maxi(_unlocked, index + 2)
		var cell: Variant = file.get_value(id, "torch", Vector2.ZERO)
		if typeof(cell) == TYPE_VECTOR2I:
			var latched: Variant = file.get_value(id, "torch_latched", PackedStringArray())
			_torches[id] = {
				"cell": cell,
				"latched": latched if typeof(latched) == TYPE_PACKED_STRING_ARRAY
					else PackedStringArray(),
				"time": maxf(0.0, _time(file.get_value(id, "torch_time", 0.0))),
			}
	return true


func save() -> Error:
	var file := ConfigFile.new()
	file.set_value(META, "unlocked", _unlocked)
	for id: String in _records:
		var record: Dictionary = _records[id]
		for key: String in record:
			file.set_value(id, key, record[key])
	for id: String in _torches:
		var torch: Dictionary = _torches[id]
		file.set_value(id, "torch", torch["cell"])
		file.set_value(id, "torch_latched", torch["latched"])
		file.set_value(id, "torch_time", torch["time"])
	return file.save(path)


## How many entries are open, from the first.
func unlocked() -> int:
	return clampi(_unlocked, 1, maxi(1, Campaign.count()))


func is_unlocked(index: int) -> bool:
	return index >= 0 and index < unlocked()


## Open and built: what can be played now.
func is_playable(index: int) -> bool:
	return is_unlocked(index) and Campaign.is_built(index)


## Entry `id`'s record, as a copy; the defaults for one never played.
func record_of(id: String) -> Dictionary:
	return (_records.get(id, _blank()) as Dictionary).duplicate()


func is_cleared(id: String) -> bool:
	return bool(record_of(id)["cleared"])


## A clear of entry `index` in `seconds`, with what was found. Keeps the best
## of each -- the shortest time, the most relics, the most secrets -- opens
## the next entry, and answers what this run improved: `{first, time,
## relics, secrets}`. Saving is the caller's, so a test can look first.
func record_clear(index: int, seconds: float, relics: int, relics_total: int,
		secrets: int, secrets_total: int) -> Dictionary:
	var id := String(Campaign.entry(index).get("id", ""))
	var improved := {"first": false, "time": false, "relics": false, "secrets": false}
	if id == "":
		return improved
	var record := record_of(id)
	improved["first"] = not bool(record["cleared"])
	record["cleared"] = true
	var best := float(record["best_time"])
	if best < 0.0 or seconds < best:
		record["best_time"] = seconds
		improved["time"] = true
	record["relics_total"] = relics_total
	if relics > int(record["relics"]):
		improved["relics"] = true
		record["relics"] = relics
	record["secrets_total"] = secrets_total
	if secrets > int(record["secrets"]):
		improved["secrets"] = true
		record["secrets"] = secrets
	_records[id] = record
	_unlocked = maxi(_unlocked, index + 2)
	# Out by the door: there is no run left to pick up.
	_torches.erase(id)
	return improved


## The last torch reached in entry `index`'s unfinished run, as
## `{cell, latched, time}`; empty when there is none.
func torch_of(index: int) -> Dictionary:
	var id := String(Campaign.entry(index).get("id", ""))
	return (_torches.get(id, {}) as Dictionary).duplicate()


## A torch reached at `cell` in entry `index`, with the channels `latched`
## then and the clock at `seconds`. Saving is the caller's.
func set_torch(index: int, cell: Vector2i, latched: PackedStringArray, seconds: float) -> void:
	var id := String(Campaign.entry(index).get("id", ""))
	if id != "":
		_torches[id] = {"cell": cell, "latched": latched, "time": maxf(0.0, seconds)}


## Forgets entry `index`'s torch. True if there was one, so a caller saves
## only when something changed.
func clear_torch(index: int) -> bool:
	return _torches.erase(String(Campaign.entry(index).get("id", "")))


## Where CONTINUE goes: the first entry that can be played and has not been
## cleared; once everything built is cleared, the last one that can be
## played. Never past what is built.
func continue_index() -> int:
	var last := 0
	for index: int in Campaign.count():
		if not is_playable(index):
			continue
		if not is_cleared(String(Campaign.entry(index)["id"])):
			return index
		last = index
	return last


static func _blank() -> Dictionary:
	return {
		"cleared": false, "best_time": NO_TIME,
		"relics": 0, "relics_total": 0, "secrets": 0, "secrets_total": 0,
	}


static func _int(value: Variant, fallback: int) -> int:
	return int(value) if typeof(value) == TYPE_INT else fallback


static func _bool(value: Variant) -> bool:
	return bool(value) if typeof(value) == TYPE_BOOL else false


## A best time is a positive number of seconds, or none.
static func _time(value: Variant) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return NO_TIME
	var seconds := float(value)
	return seconds if seconds > 0.0 else NO_TIME
