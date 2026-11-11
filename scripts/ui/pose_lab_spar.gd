class_name PoseLabSpar
extends Node2D
## The pose lab's TRY page: the player's fighter against a training dummy, on
## the real duel simulation, with nothing else of a match around it.
##
## One frame is the duel's frame, in the duel's order -- both inputs, both
## simulations, then DuelCombat.resolve() -- stepped once per physics tick,
## which is 60 Hz and fixed. There is no match: no window, no initiative, no
## countdown, no netplay. A death is put right after RESPAWN_FRAMES by putting
## both back on their marks, which is what a sparring floor is for.
##
## The dummy is driven the only way a fighter can be driven, with input bits:
## its stance is held with up, nothing or down, its duck with down and WALK,
## and, when it is told to, it thrusts at that height every THRUST_EVERY
## frames, so the player can find out whether his thumb's LOW turns a LOW
## thrust or whether it was a duck that died to it. Its one liberty is that it
## turns to face the player between frames, as a dummy on a pivot does; a
## fighter turns only by running, and a dummy that ran would not stay put.
## NONE is the dummy with no sword at all: nothing is up to turn a blade.
##
## What happened is read from the events DuelCombat returns, plus which of
## the two was in the live frames of a thrust before the blades were
## resolved: a clash is a CLASH when both were thrusting and a PARRY when one
## was standing in a guard, and the events alone cannot say which. That read
## and the words for it are `describe()`, a pure function a test drives.
## Presentation reads this node; nothing here is drawn.

enum Dummy { NONE, HIGH, MID, LOW, DUCK }

const DUMMY_NAMES: Array[String] = ["NONE", "HIGH", "MID", "LOW", "DUCK"]
const DT := DuelRules.DT
## A second on the floor, then both back on their marks.
const RESPAWN_FRAMES := 60
## How often a thrusting dummy thrusts: once a second and a quarter, time to
## settle a guard between them.
const THRUST_EVERY := 75
## How far from the player the dummy stands: well inside a thrust's reach, so
## a thrust from a standstill meets it, as the fighter's own tests stand them.
const DUMMY_GAP := 20.0
const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighter.tscn")
## Seats: the player is the crimson one.
const YOU := 0
const DUMMY := 1

var you: Fighter
var dummy: Fighter
var dummy_stance := Dummy.MID
var dummy_thrusts := false
## Frames stepped since the floor was built.
var frame := 0
## The last thing that happened: {word, detail, frame}, empty before anything.
var last: Dictionary = {}
## How many frames the player's posture has been held unchanged.
var held := 0

var _stage: PoseLabStage
var _marks: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _down_for: Array[int] = [0, 0]
## Whether each fighter's current thrust has met anything yet.
var _thrust_met: Array[bool] = [false, false]
var _was_thrusting: Array[bool] = [false, false]
var _last_posture := -1


## Builds the two fighters on `stage`'s strip, dressed in `looks`.
func build(stage: PoseLabStage, looks: Array[CharacterLook]) -> void:
	_stage = stage
	for old: Fighter in [you, dummy]:
		if old != null:
			remove_child(old)
			old.free()
	you = _spawn(YOU, looks[YOU])
	dummy = _spawn(DUMMY, looks[DUMMY])
	place()


## Both on their marks: the player on the strip's first, the dummy a thrust's
## reach in front.
func place() -> void:
	_marks[YOU] = _stage.mark(YOU)
	_marks[DUMMY] = _stage.stand_at(_marks[YOU].x + DUMMY_GAP)
	you.respawn_at(_marks[YOU], 1)
	dummy.respawn_at(_marks[DUMMY], -1)
	_down_for = [0, 0]
	_thrust_met = [false, false]
	_was_thrusting = [false, false]
	held = 0
	_last_posture = -1
	_arm_dummy()


func set_dummy(stance: Dummy) -> void:
	dummy_stance = stance
	_arm_dummy()


## The dummy holds its sword for every stance but NONE, and for NONE lets go
## of it at its feet: no blade up, nothing to turn a thrust.
func _arm_dummy() -> void:
	if dummy_stance == Dummy.NONE:
		if dummy.blade.is_held():
			dummy.blade.drop(dummy.tuning.hand_position(dummy.position, dummy.facing,
				dummy.stance), dummy.stance, -dummy.facing, dummy.tuning)
	elif not dummy.blade.is_held():
		dummy.blade.hold()


## The bits the dummy holds this frame.
static func dummy_bits(stance: Dummy, thrust: bool) -> int:
	var bits := 0
	match stance:
		Dummy.HIGH:
			bits = PlayerInput.BIT_UP
		Dummy.LOW:
			bits = PlayerInput.BIT_DOWN
		Dummy.DUCK:
			bits = PlayerInput.BIT_DOWN | PlayerInput.BIT_WALK
	if thrust and stance != Dummy.NONE:
		bits |= PlayerInput.BIT_ATTACK
	return bits


## One duel frame with `your_bits` as the player's byte. Call it from a
## physics frame: the fighters move against the physics space.
func step(your_bits: int) -> void:
	frame += 1
	if dummy.is_alive() and dummy.is_free():
		var toward := signi(int(you.position.x - dummy.position.x))
		if toward != 0:
			dummy.facing = toward
	var thrust := dummy_thrusts and frame % THRUST_EVERY == 0
	you.input.apply_bits(your_bits)
	dummy.input.apply_bits(dummy_bits(dummy_stance, thrust))
	you.simulate(DT)
	dummy.simulate(DT)
	var attacking: Array[bool] = [you.is_attacking(), dummy.is_attacking()]
	var thrusting: Array[bool] = [you.state == Fighter.State.THRUSTING,
		dummy.state == Fighter.State.THRUSTING]
	var events := DuelCombat.resolve(you, dummy)
	_note(events, attacking, thrusting)
	_count_held()
	_respawn()


## Turns a frame's events into the readout's line, and notices a thrust that
## ran out having met nothing. `thrusting` is, per seat, whether the fighter
## was in a thrust before the blades were resolved.
func _note(events: Array[Dictionary], attacking: Array[bool], thrusting: Array[bool]) -> void:
	var said := describe(events, attacking)
	if not said.is_empty():
		said["frame"] = frame
		last = said
	for seat: int in 2:
		var fighter := you if seat == YOU else dummy
		if thrusting[seat]:
			if not _was_thrusting[seat] or fighter.state_frame == 1:
				_thrust_met[seat] = false
			if not said.is_empty():
				_thrust_met[seat] = true
		elif _was_thrusting[seat] and not _thrust_met[seat]:
			last = miss(seat)
			last["frame"] = frame
			_thrust_met[seat] = true
		_was_thrusting[seat] = thrusting[seat]


## What one frame's events mean, in the readout's words: `{word, detail}`, or
## {} for a frame where nothing happened. `attacking` is, per seat, whether
## that fighter was in the live frames of a thrust before the blades were
## resolved -- the one thing the events do not carry.
static func describe(events: Array[Dictionary], attacking: Array[bool]) -> Dictionary:
	for kind: String in ["disarm", "clash", "kill", "knockdown", "deflect", "catch"]:
		for event: Dictionary in events:
			if String(event.get("kind", "")) == kind:
				return _words(event, attacking)
	return {}


static func _words(event: Dictionary, attacking: Array[bool]) -> Dictionary:
	match String(event["kind"]):
		"disarm":
			if int(event["victim"]) == YOU:
				return {"word": "DISARMED", "detail": "THE DUMMY'S GUARD TOOK YOUR SWORD"}
			return {"word": "DISARM", "detail": "YOUR GUARD TOOK THE DUMMY'S SWORD"}
		"clash":
			if attacking[YOU] and attacking[DUMMY]:
				return {"word": "CLASH", "detail": "BOTH THRUSTS MET"}
			if attacking[YOU]:
				return {"word": "PARRIED", "detail": "THE DUMMY'S GUARD TURNED YOUR THRUST"}
			return {"word": "PARRY", "detail": "YOUR GUARD TURNED THE THRUST"}
		"kill":
			if int(event["victim"]) == DUMMY:
				return {"word": "KILL", "detail": "YOU CUT THE DUMMY DOWN"}
			return {"word": "KILLED", "detail": "THE DUMMY CUT YOU DOWN"}
		"knockdown":
			if int(event["victim"]) == DUMMY:
				return {"word": "KNOCKDOWN", "detail": "YOU PUT THE DUMMY DOWN"}
			return {"word": "KNOCKED DOWN", "detail": "THE DUMMY PUT YOU DOWN"}
		"deflect":
			return {"word": "DEFLECT", "detail": "A THRUST BATTED THE SWORD AWAY"}
		"catch":
			return {"word": "CATCH", "detail": "THE SWORD WAS TAKEN OUT OF THE AIR"}
	return {}


## A thrust by `seat` that ran out having met nothing.
static func miss(seat: int) -> Dictionary:
	if seat == YOU:
		return {"word": "MISS", "detail": "YOUR THRUST MET NOTHING"}
	return {"word": "MISSED YOU", "detail": "THE DUMMY'S THRUST MET NOTHING"}


func _count_held() -> void:
	var now := you.posture()
	held = held + 1 if now == _last_posture else 0
	_last_posture = now


## A second after a death, or at once after a fall off the world, both go
## back on their marks.
func _respawn() -> void:
	var floor_y := _stage.strip.world_size().y
	for seat: int in 2:
		var fighter := you if seat == YOU else dummy
		var fell := fighter.position.y > floor_y
		_down_for[seat] = _down_for[seat] + 1 if not fighter.is_alive() else 0
		if fell or _down_for[seat] > RESPAWN_FRAMES:
			place()
			return


func _spawn(seat: int, look: CharacterLook) -> Fighter:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	fighter.name = "You" if seat == YOU else "Dummy"
	add_child(fighter)
	fighter.setup(seat, null)
	fighter.world = _stage.strip
	if fighter.world != _stage.strip:
		push_error("the sparring fighter refused the strip as its world")
	var art := FighterArt.dress(fighter, seat, look)
	art.add_to_group(MatchDusk.LIT)
	return fighter


## The readout's words for a fighter: its state, and the posture the combat
## matrix sees -- which is the one that tells a LOW guard from a duck.
static func state_name(fighter: Fighter) -> String:
	return String(Fighter.State.keys()[fighter.state]).replace("_", " ")


static func posture_name(fighter: Fighter) -> String:
	if not fighter.is_armed():
		return "NO SWORD" if fighter.posture() != DuelTuning.DUCKED else "DUCKED"
	return PoseCatalogue.stance_name(fighter.posture())


## What the stick and buttons hold this frame, as words.
static func bits_name(bits: int) -> String:
	var parts := PackedStringArray()
	for pair: Array in [
		[PlayerInput.BIT_LEFT, "LEFT"], [PlayerInput.BIT_RIGHT, "RIGHT"],
		[PlayerInput.BIT_UP, "UP"], [PlayerInput.BIT_DOWN, "DOWN"],
		[PlayerInput.BIT_WALK, "WALK"], [PlayerInput.BIT_JUMP, "JUMP"],
		[PlayerInput.BIT_ATTACK, "SWORD"], [PlayerInput.BIT_THROW, "THROW"],
	]:
		if bits & int(pair[0]) != 0:
			parts.append(String(pair[1]))
	return " + ".join(parts) if not parts.is_empty() else "NOTHING"
