class_name IdleArt
extends Node2D
## What the prince does when he is left alone: an escalating ladder of fidgets
## and bits, played on the figure's own pose and drawn over it.
##
## ## The ladder
##
## Standing still with nothing pressed starts a clock, `still`. Nothing happens
## for FIDGET_AFTER seconds — a player who has stopped to look at a gap must not
## be interrupted by a performance. Then a **fidget**, short and small: a glance
## over the shoulder, a tug at the sash. Then at BIT_AFTER a **bit**, long
## enough to have a beginning, a middle and a punchline, chosen pseudo-randomly
## from LONG and never the same one twice in a row, followed every CYCLE
## seconds by another, with a fidget in each gap. The full table is in
## docs/character.md.
##
## ## Why it cannot touch the game
##
## This node never writes to the Player. It reads `state`, `input` and the
## guards around it, it keeps its own clock in `_process` — never
## `_physics_process`, so there is no frame on which it could run between two
## simulation steps — and its only outputs are a pose dictionary handed back to
## PlayerArt and some polygons on its own canvas. The body, the collision
## shape and every simulated number are exactly what they would be without it;
## tests/unit/test_idle_art.gd plays the same inputs with and without it and
## compares the simulation frame by frame.
##
## Cancelling needs no special path for the same reason. The art node reads
## the state that `_physics_process` just wrote, and Godot runs every physics
## step of a frame before any `_process`, so the frame on which a button goes
## down is the frame on which `is_calm()` goes false and the bit is dropped.
## Nothing is buffered, nothing is eaten, and a press while sitting cross-legged
## is a press while standing.
##
## ## Who does not get one
##
## **Not near a guard.** A guard within GUARD_NEAR, or one that is raising,
## cutting or recovering anywhere, holds the clock at zero: the prince does not
## clown in front of somebody who can kill him, and a player who sees him doze
## would read the guard as harmless.
##
## **Not in the duel.** FighterArt overrides `PlayerArt._bind()`, so this node
## is never attached to a duellist, and that is the intent rather than an
## accident. A duellist standing still is in a stance, and the stance is the
## information: FighterArt draws the sword exactly where the simulation's blade
## rect is and keeps the body inside the hurtbox, so a fighter who sat down or
## tossed his sword would be drawn lying about both. And the two peers of an
## online duel would each pick a different bit, since this clock is not part of
## the snapshot.
##
## ## How a bit is written
##
## A bit is a TRACKS entry: keyframes of pose overrides on the bit's own clock,
## eased between with smoothstep, every field a key leaves out taken from the
## figure's resting pose. So the poses are made of the same fields as every
## other state, drawn by the same rig in whatever cloth the figure is wearing:
## a recoloured or redrawn figure idles without a change here. `_flourish()`
## adds what keyframes cannot say (a tapping foot, a sleeper's breath), and
## `_draw()` adds the props — a fly, a sword in the air, a sleeper's "z" — in
## Palette colours that belong to the world rather than to the figure.

enum Bit { NONE, GLANCE, SASH, SIT, JUGGLE, SWAT, DOZE, TAP }

## Quiet seconds before the first fidget.
const FIDGET_AFTER := 4.0
## Between fidgets, until the bits start.
const FIDGET_EVERY := 4.0
## Quiet seconds before the first bit.
const BIT_AFTER := 12.0
## One bit, then rest, then a fidget, then the next bit.
const CYCLE := 11.0
## Where in a cycle the fidget falls, after the longest bit has finished.
const CYCLE_FIDGET_AT := 8.0

const SUBTLE: Array[Bit] = [Bit.GLANCE, Bit.SASH]
const LONG: Array[Bit] = [Bit.SIT, Bit.JUGGLE, Bit.SWAT, Bit.DOZE, Bit.TAP]

const LENGTH := {
	Bit.GLANCE: 1.6,
	Bit.SASH: 1.5,
	Bit.SIT: 6.0,
	Bit.JUGGLE: 4.6,
	Bit.SWAT: 4.8,
	Bit.DOZE: 7.0,
	Bit.TAP: 3.8,
}

## How close a guard may be, either way, before the prince stays alert: 13
## tiles across and 6 up or down. The camera comes to rest centred on a
## standing prince (docs/feel.md), and a 180-unit frame is at most 400 wide on
## a 20:9 phone, so this is "anywhere a guard could be in the same frame", plus
## half a guard. If the player can see a guard, so can the prince.
const GUARD_NEAR := Vector2(208.0, 96.0)

## --- the bits' beats, in seconds on each bit's own clock -------------------

const SIT_SWORD_DOWN := 0.57
const SIT_SWORD_UP := 5.33
## The sword lies on the floor in front of him, in forward space.
const SIT_SWORD_AT := Vector2(4.5, -0.8)

const JUGGLE_TOSS := 0.52
const JUGGLE_CATCH := 1.2
const JUGGLE_TOSS_HIGH := 1.57
const JUGGLE_FUMBLE := 2.55
const JUGGLE_SNATCH := 3.07
const JUGGLE_APEX := 12.0
const JUGGLE_APEX_HIGH := 22.0

const SWAT_FLY_DARTS := 1.47
const SWAT_FLY_RISES := 2.2
const SWAT_FLY_LANDS := 2.75
const SWAT_FLY_ESCAPES := 3.47
const SWAT_FLY_GONE := 4.5

const DOZE_Z_FROM := 1.2
const DOZE_Z_UNTIL := 4.8
const DOZE_Z_EVERY := 0.8
const DOZE_Z_LIFE := 1.5
## Waking pops every "z" still in the air.
const DOZE_STARTLE := 4.95

const TAP_FROM := 0.45
const TAP_UNTIL := 2.55
const TAP_HZ := 3.0

## Poses a track holds or returns to.
const SEATED := {
	"sink": 6.0, "squash": 0.86, "lean": -0.2, "stance": 1.9, "knee": 0.6,
	"hem_lift": -1.2, "hem_spread": 3.4, "hood_tilt": 0.05,
	"arm_a": 0.9, "arm_a_len": 4.6, "arm_b": 0.7, "arm_b_len": 4.6,
	"cloak_sweep": 1.4, "cloak_rise": -0.6, "cloak_flare": 1.4, "blade": INF,
}
const YAWN := {
	"sink": 6.0, "squash": 0.92, "lean": -0.6, "stance": 1.9, "knee": 0.6,
	"hem_lift": -1.2, "hem_spread": 3.4, "hood_tilt": -0.42, "glint": 0.0,
	"arm_a": -1.35, "arm_a_len": 6.8, "arm_b": -1.75, "arm_b_len": 6.6,
	"cloak_sweep": 1.4, "cloak_rise": -0.2, "cloak_flare": 1.4, "blade": INF,
}
const NODDING := {
	"sink": 6.0, "squash": 0.86, "lean": 0.2, "stance": 1.9, "knee": 0.6,
	"hem_lift": -1.2, "hem_spread": 3.4, "hood_tilt": 0.42, "glint": 0.2,
	"arm_a": 0.9, "arm_a_len": 4.6, "arm_b": 0.7, "arm_b_len": 4.6,
	"cloak_sweep": 1.4, "cloak_rise": -0.6, "cloak_flare": 1.4, "blade": INF,
}
const HAND_UP := {"arm_a": -0.4, "arm_a_len": 6.2, "blade": INF, "hood_tilt": -0.3}
const HAND_HIGH := {"arm_a": -0.6, "arm_a_len": 6.4, "blade": INF, "hood_tilt": -0.45,
	"lean": 0.2}
const LUNGE := {
	"arm_a": 1.25, "arm_a_len": 7.4, "blade": INF, "lean": 3.6, "sink": 3.0,
	"stride": 2.0, "stance": 1.4, "knee": 1.0, "hood_tilt": 0.55, "hem_lift": 1.2,
	"cloak_sweep": 2.0, "cloak_rise": 1.0,
}
const SNATCHED := {
	"arm_a": 1.25, "arm_a_len": 7.4, "blade": 1.55, "lean": 3.6, "sink": 3.0,
	"stride": 2.0, "stance": 1.4, "knee": 1.0, "hood_tilt": 0.55, "hem_lift": 1.2,
	"cloak_sweep": 2.0, "cloak_rise": 1.0,
}
const BONK := {
	"arm_a": -1.65, "arm_a_len": 4.0, "squash": 0.93, "hood_tilt": 0.5, "sink": 0.6,
	"glint": 0.0, "blade": -2.0,
}
const ASLEEP := {
	"blade": 1.57, "arm_a": 1.15, "arm_a_len": 7.0, "arm_b": 1.0, "arm_b_len": 6.6,
	"lean": 1.4, "sink": 0.6, "hood_tilt": 0.45, "glint": 0.0, "stance": 1.0,
	"cloak_sweep": 0.3,
}
const SAGGED := {
	"blade": 1.57, "arm_a": 1.15, "arm_a_len": 7.0, "arm_b": 1.0, "arm_b_len": 6.6,
	"lean": 2.0, "sink": 1.2, "hood_tilt": 0.6, "glint": 0.0, "stance": 1.0,
	"cloak_sweep": 0.3,
}
const STARTLED := {
	"squash": 1.1, "bob": -1.6, "lean": -0.6, "hood_tilt": -0.35, "glint": 1.0,
	"arm_a": 1.15, "arm_a_len": 7.0, "arm_b": -0.7, "arm_b_len": 6.4, "blade": 1.3,
	"cloak_rise": 2.2, "cloak_flare": 1.4, "stance": 1.3,
}
const AKIMBO := {
	"hood_face": 0.3, "twist": 1.1, "lean": 0.0, "stance": 1.1, "hem_lift": 1.6,
	"arm_a": 0.85, "arm_a_len": 4.6, "arm_b": 2.25, "arm_b_len": 4.6,
	"blade": 1.75, "hood_tilt": -0.04, "cloak_sweep": 0.3,
}
const SIGH := {
	"hood_face": 0.3, "twist": 1.0, "lean": 0.3, "stance": 1.1, "sink": 0.4,
	"arm_a": 0.85, "arm_a_len": 4.6, "arm_b": 2.25, "arm_b_len": 4.6,
	"blade": 1.75, "hood_tilt": 0.3, "squash": 0.965, "cloak_sweep": 0.3,
}

## Keyframes: [seconds, overrides]. A field missing from a key is the resting
## pose's. INF on `blade` hides the sword in the hand while a prop stands in
## for it, and is held rather than eased, so the hand-off is on one frame.
const TRACKS := {
	Bit.GLANCE: [
		[0.0, {}],
		[0.3, {"hood_face": -1.0, "lean": 0.1, "twist": 0.86, "cloak_sweep": 0.2}],
		[0.95, {"hood_face": -1.0, "lean": 0.1, "twist": 0.86, "hood_tilt": 0.12}],
		[1.3, {"hood_face": 1.0, "hood_tilt": -0.04}],
		[1.6, {}],
	],
	Bit.SASH: [
		[0.0, {}],
		[0.3, {"arm_a": 1.18, "arm_a_len": 5.0, "hood_tilt": 0.32, "lean": 0.8, "blade": 2.0}],
		[0.55, {"arm_a": 0.95, "arm_a_len": 5.9, "hood_tilt": 0.34, "lean": 0.6,
			"squash": 0.985, "blade": 2.0}],
		[0.75, {"arm_a": 1.18, "arm_a_len": 5.0, "hood_tilt": 0.3, "lean": 0.8, "blade": 2.0}],
		[0.95, {"arm_a": 0.95, "arm_a_len": 5.9, "hood_tilt": 0.34, "lean": 0.6,
			"squash": 0.985, "blade": 2.0}],
		[1.2, {"hood_tilt": -0.08, "squash": 1.015, "lean": 0.2}],
		[1.5, {}],
	],
	Bit.SIT: [
		[0.0, {}],
		[0.3, {"sink": 2.5, "squash": 0.95, "lean": 1.8, "hood_tilt": 0.3, "arm_a": 1.2,
			"arm_a_len": 7.0, "blade": 0.3}],
		[0.55, {"sink": 4.5, "squash": 0.9, "lean": 1.2, "hood_tilt": 0.25, "arm_a": 1.25,
			"arm_a_len": 7.0, "blade": 0.0, "stance": 1.5, "hem_spread": 1.8}],
		[SIT_SWORD_DOWN, {"sink": 4.5, "squash": 0.9, "lean": 1.2, "hood_tilt": 0.25,
			"arm_a": 1.25, "arm_a_len": 7.0, "blade": INF, "stance": 1.5, "hem_spread": 1.8}],
		[0.9, SEATED],
		[1.9, SEATED],
		[2.3, YAWN],
		[3.2, YAWN],
		[3.6, SEATED],
		[4.2, NODDING],
		[4.5, SEATED],
		[5.0, SEATED],
		[5.31, {"sink": 4.5, "squash": 0.9, "lean": 1.6, "hood_tilt": 0.3, "arm_a": 1.2,
			"arm_a_len": 7.0, "blade": INF, "stance": 1.5}],
		[SIT_SWORD_UP, {"sink": 4.5, "squash": 0.9, "lean": 1.6, "hood_tilt": 0.3,
			"arm_a": 1.2, "arm_a_len": 7.0, "blade": 0.1, "stance": 1.5}],
		[6.0, {}],
	],
	Bit.JUGGLE: [
		[0.0, {}],
		[0.35, {"arm_a": 0.35, "arm_a_len": 5.6, "blade": -1.25, "lean": 0.6}],
		[0.5, {"arm_a": 0.05, "arm_a_len": 6.0, "blade": -1.35, "hood_tilt": -0.15}],
		[JUGGLE_TOSS, HAND_UP],
		[JUGGLE_CATCH, HAND_UP],
		[1.22, {"arm_a": -0.2, "blade": -1.35, "hood_tilt": -0.2}],
		[1.4, {"arm_a": 0.15, "arm_a_len": 5.8, "blade": -1.3, "hood_tilt": -0.1,
			"squash": 0.98}],
		[1.55, {"arm_a": -0.1, "blade": -1.4, "hood_tilt": -0.2}],
		[JUGGLE_TOSS_HIGH, HAND_HIGH],
		[JUGGLE_FUMBLE, HAND_HIGH],
		[2.57, {"arm_a": -0.2, "arm_a_len": 6.6, "blade": INF, "hood_tilt": -0.2,
			"lean": 1.2}],
		[3.05, LUNGE],
		[JUGGLE_SNATCH, SNATCHED],
		[3.6, SNATCHED],
		[3.95, {"hood_face": 0.3, "lean": 0.4, "blade": 2.2, "hood_tilt": 0.1}],
		[4.3, {"hood_face": 0.3, "blade": 2.3}],
		[4.6, {}],
	],
	Bit.SWAT: [
		[0.0, {}],
		[1.3, {"arm_a": 1.3, "lean": 0.7}],
		[1.36, {"arm_a": 1.55, "arm_a_len": 6.4, "lean": 0.9}],
		[1.46, {"arm_a": -1.2, "arm_a_len": 6.8, "lean": 1.4, "stride": 0.8,
			"blade": -0.6, "cloak_sweep": 1.2}],
		[1.56, {"arm_a": 0.4, "arm_a_len": 6.6, "lean": 1.6, "stride": 0.8, "blade": 0.9}],
		[1.95, {"arm_a": 1.2, "lean": 0.6}],
		[2.1, {"arm_a": 1.6, "arm_a_len": 6.4, "twist": 0.8, "lean": 0.0}],
		[2.2, {"arm_a": -2.2, "arm_a_len": 6.6, "twist": 0.8, "lean": -0.6, "blade": -2.4,
			"cloak_sweep": -0.6}],
		[2.32, {"arm_a": -2.6, "arm_a_len": 6.2, "twist": 0.8, "lean": -0.4, "blade": -2.9}],
		[2.75, {}],
		[3.3, {"arm_a": 1.3}],
		[3.42, {"arm_a": -0.9, "arm_a_len": 5.4}],
		[3.5, BONK],
		[3.8, {"arm_a": -1.65, "arm_a_len": 4.0, "squash": 0.97, "hood_tilt": 0.3,
			"glint": 0.0, "blade": -2.0}],
		[4.25, {"hood_tilt": -0.3, "lean": 0.9}],
		[4.8, {}],
	],
	Bit.DOZE: [
		[0.0, {}],
		[0.6, {"blade": 1.57, "arm_a": 1.15, "arm_a_len": 7.0, "arm_b": 1.0, "arm_b_len": 6.6,
			"lean": 1.4, "sink": 0.6, "hood_tilt": 0.2, "glint": 0.5, "stance": 1.0}],
		[DOZE_Z_FROM, ASLEEP],
		[DOZE_Z_UNTIL, SAGGED],
		[4.9, SAGGED],
		[5.0, STARTLED],
		[5.25, {"hood_face": -1.0, "lean": 0.2, "arm_a": 1.3, "blade": 2.0}],
		[5.6, {"hood_face": -1.0, "lean": 0.2, "arm_a": 1.3, "blade": 2.0}],
		[5.85, {"hood_face": 1.0, "lean": 0.6, "hood_tilt": 0.05}],
		[6.15, {"hood_face": 0.3, "hood_tilt": 0.05}],
		[6.6, {"hood_face": 0.3}],
		[7.0, {}],
	],
	Bit.TAP: [
		[0.0, {}],
		[0.35, AKIMBO],
		[TAP_UNTIL, AKIMBO],
		[2.85, SIGH],
		[3.3, SIGH],
		[3.8, {}],
	],
}

## Sounds, through GameAudio only, as [seconds, voice, options]. Small and
## dry: the cloth and a little steel. There is no yawn: the catalogue has no
## voice for one, and a synthesised yawn is a different piece of work.
const CUES := {
	Bit.GLANCE: [[0.2, &"cloth", {"volume_db": -14.0, "pitch": 1.2}]],
	Bit.SASH: [
		[0.55, &"cloth", {"volume_db": -12.0, "pitch": 1.3}],
		[0.95, &"cloth", {"volume_db": -12.0, "pitch": 1.4}],
	],
	Bit.SIT: [
		[0.5, &"cloth", {"volume_db": -6.0, "pitch": 0.8}],
		[2.2, &"cloth", {"volume_db": -10.0, "pitch": 1.1}],
		[5.3, &"cloth", {"volume_db": -6.0, "pitch": 0.9}],
	],
	Bit.JUGGLE: [
		[0.5, &"cloth", {"volume_db": -12.0, "pitch": 1.4}],
		[1.22, &"sword_hit", {"volume_db": -20.0, "pitch": 1.9}],
		[1.57, &"cloth", {"volume_db": -12.0, "pitch": 1.3}],
		[2.57, &"sword_hit", {"volume_db": -12.0, "pitch": 1.6}],
		[2.7, &"cloth", {"volume_db": -6.0, "pitch": 1.0}],
		[3.07, &"sword_hit", {"volume_db": -18.0, "pitch": 1.3}],
	],
	Bit.SWAT: [
		[1.46, &"cloth", {"volume_db": -6.0, "pitch": 1.5}],
		[2.2, &"cloth", {"volume_db": -6.0, "pitch": 1.6}],
		[3.5, &"land_soft", {"volume_db": -12.0, "pitch": 1.5}],
	],
	Bit.DOZE: [
		[5.0, &"cloth", {"volume_db": -2.0, "pitch": 1.3}],
		[5.02, &"sword_hit", {"volume_db": -18.0, "pitch": 1.9}],
	],
	Bit.TAP: [
		[0.617, &"step_walk", {"volume_db": -12.0, "pitch": 1.25}],
		[0.95, &"step_walk", {"volume_db": -12.0, "pitch": 1.25}],
		[1.283, &"step_walk", {"volume_db": -12.0, "pitch": 1.25}],
		[1.617, &"step_walk", {"volume_db": -12.0, "pitch": 1.25}],
		[1.95, &"step_walk", {"volume_db": -12.0, "pitch": 1.25}],
		[2.283, &"step_walk", {"volume_db": -12.0, "pitch": 1.25}],
	],
}

## Seconds of calm so far: standing, nothing pressed, no guard about.
var still: float = 0.0
## Picks the bits. Re-hashed at the start of every quiet spell, so two spells
## do not tell the same jokes in the same order.
var spell_seed: int = 0
## What is playing, and how far into it.
var bit: Bit = Bit.NONE
var bit_time: float = 0.0

var _player: Player
var _art: PlayerArt
var _clock: float = 0.0
var _pinned := false
var _drawn := false
var _cycle_seen := -1
var _cycle_bit: Bit = Bit.NONE


## Gives `art` an idle. Called from PlayerArt._bind() for the prince only.
static func attach(art: PlayerArt, player: Player) -> IdleArt:
	var idle := IdleArt.new()
	idle.name = "IdleArt"
	idle._art = art
	idle._player = player
	art.add_child(idle)
	return idle


func _init() -> void:
	spell_seed = absi(hash(get_instance_id()))


## True when the prince may idle: standing, not a button down, no guard about.
## IDLE is named and nothing else is, so a state added later -- the air slash,
## the plunge and the parry were -- is never calm without anyone listing it.
static func is_calm(player: Player) -> bool:
	if player == null or player.state != Player.State.IDLE:
		return false
	if player.input != null and player.input.to_bits() != 0:
		return false
	return not guard_near(player)


## A live guard inside GUARD_NEAR, or one that is raising, cutting or
## recovering anywhere at all.
static func guard_near(player: Node2D) -> bool:
	if not player.is_inside_tree():
		return false
	for node: Node in player.get_tree().get_nodes_in_group(Patrol.GROUP):
		var guard := node as Patrol
		if guard == null or not guard.is_alive():
			continue
		match guard.state:
			Patrol.State.WINDUP, Patrol.State.STRIKE, Patrol.State.RECOVER:
				return true
		var gap := (guard.global_position - player.global_position).abs()
		if gap.x <= GUARD_NEAR.x and gap.y <= GUARD_NEAR.y:
			return true
	return false


## Holds `which` at `at` seconds for good. The pose renderer uses it, so a
## frame can be taken of any moment of any bit.
func pin(which: Bit, at: float) -> void:
	_pinned = true
	bit = which
	bit_time = at
	still = BIT_AFTER


func _process(delta: float) -> void:
	_clock += delta
	if not _pinned:
		advance(delta, is_calm(_player))
	# Redraw while something is up, and once more after, to clear the props.
	if bit != Bit.NONE or _drawn:
		queue_redraw()


## One frame of the clock. Anything but calm drops the bit on this frame.
func advance(delta: float, calm: bool) -> void:
	if not calm:
		still = 0.0
		bit = Bit.NONE
		bit_time = 0.0
		return
	if still == 0.0:
		spell_seed = absi(hash([spell_seed, 0x9e3779b9]))
		_cycle_seen = -1
	var was := bit
	var was_time := bit_time
	still += delta
	_schedule()
	if bit != Bit.NONE:
		_cue_between(was_time if was == bit else -1.0, bit_time)


## --- the ladder ------------------------------------------------------------

func _schedule() -> void:
	bit = Bit.NONE
	bit_time = 0.0
	if still < FIDGET_AFTER:
		return
	if still < BIT_AFTER:
		var since := still - FIDGET_AFTER
		var slot := floori(since / FIDGET_EVERY)
		_play(SUBTLE[posmod(slot + spell_seed, SUBTLE.size())], since - slot * FIDGET_EVERY)
		return
	var into := still - BIT_AFTER
	var cycle := floori(into / CYCLE)
	var t := into - cycle * CYCLE
	var main := long_bit(cycle)
	if t < float(LENGTH[main]):
		_play(main, t)
	elif t >= CYCLE_FIDGET_AT:
		_play(SUBTLE[posmod(cycle + spell_seed + 1, SUBTLE.size())], t - CYCLE_FIDGET_AT)


func _play(which: Bit, t: float) -> void:
	if t < float(LENGTH[which]):
		bit = which
		bit_time = t


## The bit for the `cycle`th long slot of this quiet spell. Never the one
## before it: each pick skips over the last one, so a spell cannot open with
## the same joke twice.
func long_bit(cycle: int) -> Bit:
	if cycle == _cycle_seen:
		return _cycle_bit
	var pick := -1
	for n: int in cycle + 1:
		var roll := absi(hash([spell_seed, n]))
		if pick < 0:
			pick = roll % LONG.size()
		else:
			pick = (pick + 1 + roll % (LONG.size() - 1)) % LONG.size()
	_cycle_seen = cycle
	_cycle_bit = LONG[pick]
	return _cycle_bit


func _cue_between(from: float, to: float) -> void:
	for cue: Array in CUES.get(bit, []):
		var at := float(cue[0])
		if at > from and at <= to:
			GameAudio.cue(cue[1] as StringName, cue[2] as Dictionary)


## --- the pose ----------------------------------------------------------------

## The figure's pose with the current bit laid over `base`, PlayerArt's resting
## pose. `base` itself when nothing is playing.
func pose(base: Dictionary) -> Dictionary:
	if bit == Bit.NONE:
		return base
	var out := base.duplicate()
	_sample(TRACKS[bit] as Array, bit_time, base, out)
	_flourish(out)
	return out


func _sample(track: Array, t: float, base: Dictionary, out: Dictionary) -> void:
	var last := track.size() - 1
	var i := 0
	while i < last and float(track[i + 1][0]) <= t:
		i += 1
	var a: Dictionary = track[i][1]
	if i == last:
		for field: String in a:
			out[field] = a[field]
		return
	var b: Dictionary = track[i + 1][1]
	var t0 := float(track[i][0])
	var w := smoothstep(0.0, 1.0, (t - t0) / maxf(0.001, float(track[i + 1][0]) - t0))
	for field: String in _fields(a, b):
		var va := float(a.get(field, base[field]))
		var vb := float(b.get(field, base[field]))
		# A hidden sword is held until the next key, never eased into.
		out[field] = va if is_inf(va) or is_inf(vb) else lerpf(va, vb, w)


func _fields(a: Dictionary, b: Dictionary) -> Array:
	var fields := a.keys()
	for field: String in b:
		if not a.has(field):
			fields.append(field)
	return fields


## What keyframes cannot say.
func _flourish(out: Dictionary) -> void:
	var t := bit_time
	match bit:
		Bit.TAP:
			if t >= TAP_FROM and t < TAP_UNTIL:
				var tap := maxf(0.0, sin(TAU * TAP_HZ * (t - TAP_FROM)))
				out["knee"] = float(out["knee"]) + tap * 1.8
				out["stride"] = float(out["stride"]) + tap * 0.6
				out["hood_tilt"] = float(out["hood_tilt"]) + tap * 0.04
		Bit.DOZE:
			if t >= DOZE_Z_FROM and t < DOZE_Z_UNTIL:
				var breath := sin((t - DOZE_Z_FROM) * 2.2)
				out["squash"] = float(out["squash"]) + breath * 0.02
				out["hood_tilt"] = float(out["hood_tilt"]) + breath * 0.06
		Bit.SIT:
			if t >= 2.3 and t < 3.2:
				out["arm_a"] = float(out["arm_a"]) + sin(t * 40.0) * 0.05
		Bit.SWAT:
			if t < SWAT_FLY_LANDS:
				var fly := _fly(t)
				out["hood_face"] = clampf(fly.x / 2.0, -1.0, 1.0)
				out["hood_tilt"] = clampf(fly.y / 10.0, -0.45, 0.25)
			elif t < SWAT_FLY_ESCAPES:
				out["hood_tilt"] = -0.42


## --- props -----------------------------------------------------------------

func _draw() -> void:
	_drawn = bit != Bit.NONE
	if _art == null or bit == Bit.NONE:
		return
	var t := bit_time
	match bit:
		Bit.SIT:
			if t >= SIT_SWORD_DOWN and t < SIT_SWORD_UP:
				_draw_sword(_fwd(SIT_SWORD_AT), 0.0)
		Bit.JUGGLE:
			_draw_juggle(t)
		Bit.SWAT:
			if t < SWAT_FLY_GONE:
				_draw_fly(_art._head + _fwd(_fly(t)))
		Bit.DOZE:
			_draw_sleep(t)


## Forward space to this node's space: the art's mirror for `facing`.
func _fwd(p: Vector2) -> Vector2:
	return Vector2(p.x * _art._f, p.y)


## The sword off the hand: tossed once and caught, tossed higher, glanced off
## the fingers and snatched a hand's breadth off the floor. Each flight is an
## offset from wherever the hand is now, zero at both ends, so the throw leaves
## the hand and the catch lands in it whatever the arm is doing in between.
func _draw_juggle(t: float) -> void:
	var offset := Vector2.ZERO
	var angle := 0.0
	if t >= JUGGLE_TOSS and t < JUGGLE_CATCH:
		var u := (t - JUGGLE_TOSS) / (JUGGLE_CATCH - JUGGLE_TOSS)
		offset = Vector2(0.6 * sin(PI * u), -4.0 * JUGGLE_APEX * u * (1.0 - u))
		angle = -1.35 + TAU * u
	elif t >= JUGGLE_TOSS_HIGH and t < JUGGLE_FUMBLE:
		var u := (t - JUGGLE_TOSS_HIGH) / (JUGGLE_FUMBLE - JUGGLE_TOSS_HIGH)
		offset = Vector2(sin(PI * u), -4.0 * JUGGLE_APEX_HIGH * u * (1.0 - u))
		angle = -1.4 + TAU * 2.0 * u
	elif t >= JUGGLE_FUMBLE and t < JUGGLE_SNATCH:
		# Off the fingers: a pop forward and up, then down with the lunge.
		var u := (t - JUGGLE_FUMBLE) / (JUGGLE_SNATCH - JUGGLE_FUMBLE)
		offset = Vector2(5.0 * sin(PI * u), -5.0 * sin(PI * u))
		angle = lerpf(-1.4, 1.55 + TAU, u)
	else:
		return
	var dir := Vector2(cos(angle) * _art._f, sin(angle))
	_draw_sword(_art._hand_front + _fwd(offset) + dir * 1.2, angle)


## The prince's sword, drawn from its hilt along `angle` in forward space: the
## same planes and colours as PlayerArt._draw_weapon(), without the hand.
func _draw_sword(hilt: Vector2, angle: float) -> void:
	var dir := Vector2(cos(angle) * _art._f, sin(angle))
	var side := Vector2(-dir.y, dir.x)
	var tip := hilt + dir * 9.0
	draw_colored_polygon(PackedVector2Array([
		hilt + side * 0.9, tip + side * 0.25, tip - side * 0.25, hilt - side * 0.9,
	]), Palette.STEEL)
	draw_colored_polygon(PackedVector2Array([
		hilt + side * 0.9, tip + side * 0.25, tip, hilt + side * 0.1,
	]), Palette.STEEL_DARK)
	draw_colored_polygon(PackedVector2Array([
		hilt + side * 2.0 - dir * 0.5, hilt + side * 2.0 + dir * 0.5,
		hilt - side * 2.0 + dir * 0.5, hilt - side * 2.0 - dir * 0.5,
	]), Palette.LIGHT_WARM)


## Where the fly is, from the centre of the hood, in forward space. In front of
## the face, then behind the head after the first swat, then over it after the
## second, then sitting on the crest of the hood, then away.
func _fly(t: float) -> Vector2:
	var phase := 0
	var starts: Array[float] = [0.0, SWAT_FLY_DARTS, SWAT_FLY_RISES, SWAT_FLY_LANDS,
		SWAT_FLY_ESCAPES]
	while phase < starts.size() - 1 and t >= starts[phase + 1]:
		phase += 1
	var here := _fly_phase(phase, t)
	var since := t - starts[phase]
	if phase > 0 and since < 0.1:
		return _fly_phase(phase - 1, t).lerp(here, since / 0.1)
	return here


func _fly_phase(phase: int, t: float) -> Vector2:
	match phase:
		0:
			var buzz := Vector2(4.5 + 2.5 * sin(t * 7.3), -2.5 + 2.0 * sin(t * 11.7 + 1.0))
			return Vector2(16.0, -12.0).lerp(buzz, smoothstep(0.0, 0.5, t))
		1:
			return Vector2(-5.0 + 1.5 * sin(t * 9.0), -3.0 + 1.5 * sin(t * 13.0))
		2:
			return Vector2(1.5 * sin(t * 8.0), -8.0 + 1.2 * sin(t * 12.0))
		3:
			return Vector2(0.8, -PlayerArt.HOOD_HH - 1.0)
	var away := t - SWAT_FLY_ESCAPES
	return Vector2(0.8 + away * 12.0 + sin(t * 17.0), -PlayerArt.HOOD_HH - 1.0 - away * 26.0)


## Body ink, and wings that flicker. One pixel is a fly; two is a bird.
func _draw_fly(at: Vector2) -> void:
	draw_rect(Rect2(at.x - 0.6, at.y - 0.6, 1.2, 1.2), Palette.INK)
	if int(_clock * 40.0) % 2 == 0:
		draw_rect(Rect2(at.x - 1.2, at.y - 1.4, 2.4, 0.7), Palette.with_alpha(Palette.PAPER, 0.7))


## The sleeper's "z"s: one every DOZE_Z_EVERY, drifting up and forward from
## the hood and fading, each a little bigger than the last.
func _draw_sleep(t: float) -> void:
	if t >= DOZE_STARTLE:
		return
	var from := _art._head + _fwd(Vector2(2.0, -3.5))
	var n := 0
	var born := DOZE_Z_FROM
	while born < DOZE_Z_UNTIL:
		var age := (t - born) / DOZE_Z_LIFE
		if age >= 0.0 and age < 1.0:
			var drift := _fwd(Vector2(3.0 * age + sin(age * 5.0) * 0.8, -9.0 * age))
			var size := 2.2 + 0.6 * float(n % 3)
			_draw_z(from + drift, size, 1.0 - age * age)
		born += DOZE_Z_EVERY
		n += 1


func _draw_z(at: Vector2, size: float, alpha: float) -> void:
	var c := Palette.with_alpha(Palette.PAPER, alpha)
	var stroke := 0.7
	draw_rect(Rect2(at.x, at.y, size, stroke), c)
	draw_rect(Rect2(at.x, at.y + size - stroke, size, stroke), c)
	draw_colored_polygon(PackedVector2Array([
		Vector2(at.x + size - stroke, at.y + stroke), Vector2(at.x + size, at.y + stroke),
		Vector2(at.x + stroke, at.y + size - stroke), Vector2(at.x, at.y + size - stroke),
	]), c)
