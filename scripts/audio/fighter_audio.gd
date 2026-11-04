class_name FighterAudio
extends Node
## Gives a duellist a voice: the thrust, the clash, the disarm, the kill.
##
## The duel had none. A phone test of it reported no sword-fighting sounds and
## no sound when someone died, and that was not a mix problem: the only cue
## anywhere in scripts/duel/ was the catch. Every other exchange -- the whole
## of what the mode is -- was silent. This node is the duel's PlayerAudio: a
## child of Fighter that reads the fighter and owns one concern, so nothing in
## the simulation reads it, it never writes to the fighter, and removing it
## leaves a silent but otherwise identical duel.
##
## ## What is heard, and from where
##
## The fighter's presentation signals -- `clashed`, `disarmed`,
## `knocked_down`, `blade_thrown` -- are already suppressed while the match
## replays a mispredicted frame, so a sound hung on them rings once per thing
## that happened. `died` is the one signal that rings through a replay,
## because the match's bookkeeping hangs on it; it is heard here only when
## the fighter is not `replaying`, exactly as FighterArt's flash is.
##
## The attacks have no signal: they are states. A thrust, a dive kick, a sweep
## and a roll are heard on the frame the fighter is first seen in them, which
## this node checks once a physics frame -- the same frame the match steps.
##
## The two seats are pitched a little apart, so with both blades in the air
## the ear can still tell whose thrust it was.
##
## ## The music
##
## A duel is two people listening for steel. While a fighter is in the tree
## the director's mood is the duel's (Mix.MOODS): the music lower and the
## drum out of it. The director lets the mood go when this node leaves.

## Seat one at the voice's own pitch, seat two a whole tone down.
const SEAT_PITCH: Array[float] = [1.0, 0.9]

## State entered -> [event, volume_db, pitch]. The attacks and the moves big
## enough to be heard; IDLE and RUNNING are silence.
const ON_ENTER := {
	Fighter.State.THRUSTING: ["sword", 0.0, 1.0],
	Fighter.State.DIVEKICK: ["jump", -2.0, 0.85],
	Fighter.State.SWEEP: ["sword", -4.0, 0.72],
	Fighter.State.POUND: ["cloth", 0.0, 0.8],
	Fighter.State.ROLLING: ["cloth", -2.0, 1.0],
	Fighter.State.SNATCH: ["cloth", -3.0, 1.2],
}

var _fighter: Fighter
var _last_state: int = -1


func _ready() -> void:
	_fighter = get_parent() as Fighter
	if _fighter == null:
		push_warning("FighterAudio expects to be a child of Fighter")
		return
	_last_state = _fighter.state
	_fighter.clashed.connect(func(_at: Vector2) -> void: _play("clash"))
	_fighter.disarmed.connect(func(_v: int, _b: int) -> void: _play("disarm"))
	_fighter.knocked_down.connect(func(_v: int) -> void: _play("guard_hit", -2.0, 0.85))
	_fighter.blade_thrown.connect(func(_t: int) -> void: _play("sword", -2.0, 0.7))
	_fighter.died.connect(_on_died)
	GameAudio.set_mood(Mix.MOOD_DUEL, self)


## Every voice this node can ask for. The test checks each one resolves.
static func event_names() -> PackedStringArray:
	var out := PackedStringArray(["clash", "disarm", "guard_hit", "sword", "kill"])
	for state: int in ON_ENTER:
		out.append(String((ON_ENTER[state] as Array)[0]))
	return out


func _physics_process(_delta: float) -> void:
	if _fighter == null:
		return
	var state: int = _fighter.state
	if state == _last_state:
		return
	_last_state = state
	if ON_ENTER.has(state):
		var row: Array = ON_ENTER[state]
		_play(String(row[0]), float(row[1]), float(row[2]))


func _on_died(_victim: int, _killer: int) -> void:
	if not _fighter.replaying:
		_play("kill")


func _play(event: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var seat := SEAT_PITCH[absi(_fighter.id) % SEAT_PITCH.size()]
	GameAudio.cue(StringName(event), {"volume_db": volume_db, "pitch": pitch * seat})
