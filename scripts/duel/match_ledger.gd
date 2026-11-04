class_name MatchLedger
extends RefCounted
## What the scene has been told about a match, against what the match now says
## happened -- and the difference between the two, settled once per correction.
##
## WHY A LEDGER AND NOT JUST A FLAG
## An online client steps a frame on its own guess, shows what happened, and
## then, when the host's snapshot lands, rewinds and steps the same frames again.
## `DuelSim.replaying` stops the second pass from ringing a kill a second time.
## That is necessary and not enough: a correction can CHANGE what happened. The
## kill the client predicted may not be in the host's history at all, or the
## host's history may hold a kill the client never predicted. A flag can only
## stay quiet. Blood on the floor is a record of who died where, and a record
## has to end up matching the history that is now true, so something has to
## compare the two. This does, and nothing else: it holds no simulation state,
## it is not in the snapshot or the checksum, and nothing it decides goes back
## into a step.
##
## THE RULE (docs/netplay.md, "Corrected outcomes", argues for it)
##   held      what the timeline now contains: every presentable event of every
##             frame stepped so far, rewritten whenever a frame is stepped again.
##   told      what the scene has been told.
##   settle()  matches the two. An event and its match are the same kind about
##             the same seat, at most SAME_BEAT frames apart.
##     - held, never told: TELL it. The beat is late, and is rung anyway.
##     - told and held, but at another frame or place: REVISE it, silently.
##     - told, and the timeline has run SAME_BEAT frames past it without
##       producing it: RETRACT it. Before that it may yet be revised.
##
## THE STATE OUTRANKS THE REPLAY, FOR WHETHER AND WHEN SOMEONE DIED
## The timeline is only as good as the frames the client could step again. When
## a run of the host's input is missing -- snapshots lost on an unreliable link
## -- the client loads the host's state without being able to replay the frames
## behind it, and what the timeline holds for those frames is a stale guess. The
## state itself is not a guess: a fallen fighter's respawn timer says exactly
## which frame they fell on, on both peers. So settle() takes that as evidence
## (DuelMatch computes it) and, inside the window the timers cover, makes the
## timeline agree with it: a death the timers deny is struck out, and a death
## they report that the timeline lacks is put in, at the place the player was
## shown if there was one, and where the body lies if not. The replay still
## says WHERE, when it could be run; only it knows that.
##
## SAME_BEAT is what makes a correction that moves a kill by a few frames a
## revision rather than a retraction and a second kill with a second beat. Half
## a second is more than any correction moves one exchange and less than any two
## real events of one kind about one seat can be apart: a fighter is down for
## two seconds before it can die or respawn again, initiative can only come back
## to a seat after the other one has respawned and died, and a second catch
## needs the thrower to re-arm and throw again.

## Frames within which two events of one kind about one seat are one event.
const SAME_BEAT := 30
## How far back the ledger remembers. Older events are settled for good: no
## correction reaches them, because NetSession keeps two seconds of history
## (NetSession.HISTORY) and this is twice that.
const HORIZON := 240

## The kinds the scene is told about, and which field names the seat or thing
## each one is about. Every other kind in DuelMatch.events is simulation detail.
const SUBJECT := {
	"died": "victim",
	"respawned": "slot",
	"initiative": "leader",
	"zone": "index",
	"catch": "by",
	"consumed": "winner",
	"over": "winner",
}

## frame -> Array[Dictionary]: the presentable events the timeline holds there.
var _held := {}
## Every event the scene has been told and not had retracted, oldest first.
var _told: Array[Dictionary] = []
## Order of arrival, so two events on one frame are told in the order they
## happened: the initiative before the death that won it, as the HUD expects.
var _arrivals := 0


func clear() -> void:
	_held.clear()
	_told.clear()
	_arrivals = 0


static func presentable(event: Dictionary) -> bool:
	return SUBJECT.has(String(event.get("kind", "")))


## What frame `frame` now holds. Replaces whatever an earlier pass recorded for
## it: a frame stepped again is the same frame, and only its latest outcome is
## the timeline's.
func record(frame: int, events: Array[Dictionary]) -> void:
	_held.erase(frame)
	for event: Dictionary in events:
		note(frame, event)


## One more event on a frame already stepped. For a death reported from outside
## a step, which the next record() would otherwise overwrite.
func note(frame: int, event: Dictionary) -> void:
	if not presentable(event):
		return
	var entry := event.duplicate()
	entry["frame"] = frame
	entry["order"] = _arrivals
	_arrivals += 1
	if not _held.has(frame):
		_held[frame] = []
	(_held[frame] as Array).append(entry)


## The match was put back to `frame`: whatever the timeline held from there on
## has not happened yet, and will be recorded again as it is stepped.
func rewind(frame: int) -> void:
	for at: int in _held.keys():
		if at >= frame:
			_held.erase(at)


## Matches told against held, as of `now` (the next frame to be stepped), and
## returns what changed: {told: [...], revised: [[was, now], ...], retracted:
## [...]}, each in frame order. Applies it, too: after this the ledger counts
## everything returned under `told` as told.
##
## `evidence` is what the state says about deaths since frame `since`, one
## entry per seat: {} for a fighter that has not fallen since, or {frame, at}
## for one that has, `at` being where the body lies now. Empty for none.
func settle(now: int, evidence: Dictionary = {}) -> Dictionary:
	_forget_before(now - HORIZON)
	if not evidence.is_empty():
		_weigh(int(evidence["since"]), evidence["seats"] as Array)
	var held: Array[Dictionary] = []
	for at: int in _held.keys():
		for event: Dictionary in _held[at]:
			held.append(event)
	held.sort_custom(_earlier)

	var taken := {}
	var kept: Array[Dictionary] = []
	var revised: Array = []
	var retracted: Array[Dictionary] = []
	for told: Dictionary in _told:
		var twin := _twin_of(told, held, taken)
		if twin >= 0:
			taken[twin] = true
			var current: Dictionary = held[twin]
			if not _same(told, current):
				revised.append([told, current])
			kept.append(current)
		elif now - int(told["frame"]) > SAME_BEAT:
			retracted.append(told)
		else:
			kept.append(told) # not yet: the timeline may still produce it

	var fresh: Array[Dictionary] = []
	for i: int in held.size():
		if not taken.has(i):
			fresh.append(held[i])
			kept.append(held[i])
	kept.sort_custom(_earlier)
	_told = kept
	return {"told": fresh, "revised": revised, "retracted": retracted}


## Makes the timeline's deaths from `since` on agree with the state's. See the
## class docstring.
func _weigh(since: int, seats: Array) -> void:
	for victim: int in seats.size():
		var down: Dictionary = seats[victim]
		if not down.is_empty() and int(down["frame"]) < since:
			down = {} # fell before the window: nothing inside it
		var stale: Array[Dictionary] = []
		for at: int in _held.keys():
			if at < since:
				continue
			for event: Dictionary in _held[at]:
				if event["kind"] == "died" and int(event["victim"]) == victim:
					stale.append(event)
		if not down.is_empty() and stale.size() == 1 \
				and int(stale[0]["frame"]) == int(down["frame"]):
			continue # the timeline already says what the state says
		for event: Dictionary in stale:
			(_held[int(event["frame"])] as Array).erase(event)
		if down.is_empty():
			continue
		var frame := int(down["frame"])
		var shown := _nearest_death(_told, victim, frame)
		if shown.is_empty():
			shown = _nearest_death(stale, victim, frame)
		note(frame, {
			"kind": "died", "victim": victim,
			"killer": int(shown.get("killer", -1)),
			"at": shown.get("at", down["at"]),
			"blow": int(shown.get("blow", 0)),
		})


## The death of `victim` nearest `frame` within SAME_BEAT, or {}.
static func _nearest_death(events: Array[Dictionary], victim: int, frame: int) -> Dictionary:
	var best := {}
	var best_gap := SAME_BEAT + 1
	for event: Dictionary in events:
		if event["kind"] != "died" or int(event["victim"]) != victim:
			continue
		var gap := absi(int(event["frame"]) - frame)
		if gap < best_gap:
			best = event
			best_gap = gap
	return best


## How many events the scene currently stands told of. For the tests.
func told_count() -> int:
	return _told.size()


## The nearest untaken held event that is the same event as `told`, or -1.
func _twin_of(told: Dictionary, held: Array[Dictionary], taken: Dictionary) -> int:
	var best := -1
	var best_gap := SAME_BEAT + 1
	for i: int in held.size():
		if taken.has(i):
			continue
		var candidate: Dictionary = held[i]
		if candidate["kind"] != told["kind"] or _subject(candidate) != _subject(told):
			continue
		var gap := absi(int(candidate["frame"]) - int(told["frame"]))
		if gap < best_gap:
			best = i
			best_gap = gap
	return best


func _forget_before(frame: int) -> void:
	for at: int in _held.keys():
		if at < frame:
			_held.erase(at)
	var kept: Array[Dictionary] = []
	for told: Dictionary in _told:
		if int(told["frame"]) >= frame:
			kept.append(told)
	_told = kept


static func _subject(event: Dictionary) -> int:
	return int(event.get(SUBJECT[event["kind"]], -1))


## Whether a told event still says what the timeline says. Frame and place: a
## death moved by a correction is the same death, but its blood belongs where
## the host says it fell.
static func _same(a: Dictionary, b: Dictionary) -> bool:
	return int(a["frame"]) == int(b["frame"]) and a.get("at") == b.get("at")


static func _earlier(a: Dictionary, b: Dictionary) -> bool:
	if int(a["frame"]) != int(b["frame"]):
		return int(a["frame"]) < int(b["frame"])
	return int(a["order"]) < int(b["order"])
