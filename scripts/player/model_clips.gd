class_name ModelClips
extends RefCounted
## A rigged model's own animation clips, played back on the simulation's
## clock (scripts/player/rigged_costume.gd).
##
## ## Why the clip and not the rig, where there is a clip
##
## The rig's poses are drawn for a 22-pixel figure in flat planes: a knee is a
## point and an elbow is half-way down the arm. A clip the owner made for the
## model moves a whole body -- the weight shift of an idle, the heel strike of
## a walk -- and on a textured body that is the difference between a figure
## and a puppet. So where the model has a clip for what the body is doing, the
## clip is drawn; where it has none (a turn, a parry, every duel stance), the
## rig poses it, as it did before the model had clips. The hitbox, the tuning
## and the sword the game fights with stay the rig's either way: a clip is
## presentation, and RiggedCostume pins the clip's hips to the rig's hip so the
## picture never leaves the body.
##
## ## The clock
##
## A clip is never played: the AnimationPlayer is switched to manual
## processing and *sampled* (`sample()`) at a time worked out from the state
## and what the simulation says about it (`pick()`). The engine's own clock
## would make a replay, a rollback or the other phone draw a different frame of
## the same moment.
##
## ## Timing: the game's durations, never the clip's
##
## Tripo cannot make a clip shorter than a second, and the game's moves are
## shorter than that: a strike is a quarter of a second. So the clip is fitted
## to the game, never the game to the clip, and every duration below is read
## from Tuning, so a retuned move retimes its clip with it:
##
## - **A loop** (idle, crouch, fall, hang, ladder) plays at its own length and
##   wraps. Walk and run are *paced*: their phase runs at the body's speed over
##   the speed the clip's stride was made for (WALK_SPEED, RUN_SPEED), so a
##   foot does not skate at a slower or faster run.
## - **A one-shot with a game duration** is stretched over it, whatever its
##   own length: the attack over ATTACK_TIME, so the stab lands on the game's
##   strike; the climb over CLIMB_UP_TIME; the stagger over HURT_TIME; the
##   landing over LAND_RECOVER_TIME.
## - **The jump follows the velocity, not the clock**: while the body rises,
##   the clip's progress is how much of JUMP_SPEED has been spent, so a short
##   hop and a full jump both reach the top of the clip at the top of the arc;
##   once it falls, the JUMP state draws the fall clip.
## - **Anything else** plays once at its own speed and holds its last frame:
##   a death stays down.
##
## A clip that is mostly standing still around one useful second -- Tripo's
## five-second stab, its jump and its flip -- has a `WINDOWS` entry, and only
## that window of it is used.
##
## ## Names
##
## Tripo names a clip by the prompt it was made from ("Relaxed heroic stance_
## sword lowered in right hand_ gentle brea", punctuation turned to `_`), a
## later export may name it "idle". `NAMES` accepts either: each id lists the
## start of its prompt first and the clean id after, compared in lower case
## with `_` read as a space. Clips the table does not name are not played.

## How a clip is timed when it has no game duration: looped, held on its last
## frame, or following the jump's rise.
const LOOP := -1.0
const HOLD := 0.0
const RISE := -2.0
## Player.State key -> [clip id, timing, pace]: timing is LOOP, HOLD, RISE or
## the state's duration in seconds, which the whole clip is stretched over;
## pace, for a loop, is the speed in px/s the clip's cadence was made for, or
## 0 to play it at its own speed.
const PLAYER := {
	"IDLE": ["idle", LOOP, 0.0],
	"WALK": ["walk", LOOP, Tuning.WALK_SPEED],
	"RUN": ["run", LOOP, Tuning.RUN_SPEED],
	"CROUCH": ["crouch", LOOP, 0.0],
	"JUMP": ["jump", RISE, 0.0],
	"FALL": ["fall", LOOP, 0.0],
	"LAND": ["land", Tuning.LAND_RECOVER_TIME, 0.0],
	"HANG": ["hang", LOOP, 0.0],
	"LADDER": ["ladder", LOOP, 0.0],
	"CLIMB_UP": ["climb_up", Tuning.CLIMB_UP_TIME, 0.0],
	"ATTACK": ["attack", Tuning.ATTACK_TIME, 0.0],
	"HURT": ["hurt", Tuning.HURT_TIME, 0.0],
	"DEAD": ["death", HOLD, 0.0],
}
## Fighter.State key -> [clip id, timing, pace]. Only the death: every other
## duel state holds the sword, and the duel's sword is the blade rect the
## simulation parries with (FighterArt._draw_weapon), so the arm has to be the
## rig's, which puts the hand on that rect.
const FIGHTER := {"DEAD": ["death", HOLD, 0.0]}
## Clip id -> the names it may carry: the start of the prompt Tripo made it
## from, then the clean id. Land, hang and ladder have only clean ids: the
## owner's file has no such clips, so those states are the rig's until one
## does -- and a hang or a ladder clip has to put its hands where the rig's
## grip is, which a clip made without the level cannot know.
const NAMES := {
	"idle": ["relaxed heroic stance", "idle"],
	"walk": ["confident walk", "walk"],
	"run": ["fast run", "run"],
	"crouch": ["deep crouch", "crouch"],
	"jump": ["take-off and rising", "jump"],
	"fall": ["falling", "fall"],
	"land": ["land"],
	"hang": ["hang"],
	"ladder": ["ladder"],
	"climb_up": ["pull up from hanging", "climb_up", "climb"],
	"attack": ["mit dem schwert zustechen", "attack", "thrust"],
	"hurt": ["hit reaction", "hurt"],
	"death": ["collapses backward", "death"],
}
## The useful second of a long clip, [start, end] in its own seconds, by the
## same names: read off where the hand and the hips move in the owner's
## five-second stab (the draw, the thrust and the return), her jump and her
## flip. The rest of each is standing still.
const WINDOWS := {
	"mit dem schwert zustechen": Vector2(1.0, 2.25),
	"springen": Vector2(1.25, 2.5),
	"flip": Vector2(0.25, 3.5),
}

var _player: AnimationPlayer
## Clip id -> the animation's name in the player.
var _clips := {}
## Clip id -> the part of the animation used, [start, end] in its seconds.
var _windows := {}


func _init(player: AnimationPlayer) -> void:
	_player = player
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_player.active = true
	_clips = match_names(_player.get_animation_list())
	for id: String in _clips:
		var name: String = _clips[id]
		_windows[id] = Vector2(0.0, _player.get_animation(name).length)
		for start: String in WINDOWS:
			if _named(name, start):
				_windows[id] = WINDOWS[start]


## Clip id -> animation name, for the names a file has.
static func match_names(names: PackedStringArray) -> Dictionary:
	var out := {}
	for id: String in NAMES:
		for wanted: String in NAMES[id] as Array:
			for name: String in names:
				if _named(name, wanted):
					out[id] = name
					break
			if out.has(id):
				break
	return out


## Whether an animation's name is `wanted` or starts with it as a word.
static func _named(name: String, wanted: String) -> bool:
	var plain := name.get_slice("/", name.get_slice_count("/") - 1)
	plain = plain.to_lower().replace("_", " ").strip_edges()
	return plain == wanted or plain.begins_with(wanted + " ")


## What the body under `art` is doing: the figure ("player" or "fighter"),
## its state's name, how long the simulation says the state has lasted, its
## velocity, and whether the feet are on the floor. Simulation time, never
## the frame clock.
static func moment(art: PlayerArt) -> Dictionary:
	if art is FighterArt:
		var fighter := (art as FighterArt)._fighter
		return {
			"figure": "fighter", "state": Fighter.State.keys()[fighter.state],
			"time": float(fighter.state_frame) / 60.0, "velocity": fighter.velocity,
			"grounded": art._grounded(),
		}
	return {
		"figure": "player", "state": Player.State.keys()[art._player.state],
		"time": art._player.state_time, "velocity": art._player.velocity,
		"grounded": art._grounded(),
	}


## The clip ids this model has.
func ids() -> Array:
	return _clips.keys()


## The player the clips are sampled through, for a test.
func player() -> AnimationPlayer:
	return _player


## The part of a clip that is used, [start, end] in its own seconds.
func window(id: String) -> Vector2:
	return _windows[id]


## The clip for a moment (`moment()`) and the time into it, as
## [clip id, seconds]; [] when the model has no clip for it.
func pick(moment: Dictionary) -> Array:
	var table: Dictionary = FIGHTER if moment["figure"] == "fighter" else PLAYER
	if not table.has(moment["state"]):
		return []
	var entry: Array = table[moment["state"]]
	var velocity: Vector2 = moment["velocity"]
	if entry[1] == RISE and velocity.y >= 0.0:
		entry = PLAYER["FALL"]
	var id: String = entry[0]
	if not _clips.has(id):
		return []
	var span: Vector2 = _windows[id]
	var length := span.y - span.x
	var time: float = moment["time"]
	var timing: float = entry[1]
	var share := 0.0
	if timing == LOOP:
		var pace: float = entry[2]
		var rate := 1.0 if pace <= 0.0 else absf(velocity.x) / pace
		share = fposmod(time * rate, length) / length
	elif timing == RISE:
		share = clampf(1.0 + velocity.y / Tuning.JUMP_SPEED, 0.0, 1.0)
	elif timing > 0.0:
		share = clampf(time / timing, 0.0, 1.0)
	else:
		share = clampf(time / length, 0.0, 1.0)
	return [id, span.x + share * length]


## Poses the skeleton as the clip has it at `seconds`, now.
func sample(id: String, seconds: float) -> void:
	var name: String = _clips[id]
	if _player.current_animation != name:
		_player.current_animation = name
	_player.seek(seconds, true)
