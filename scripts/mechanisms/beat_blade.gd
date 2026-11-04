class_name BeatBlade
extends Mechanism
## A blade that keeps time: the Well's scythes and spike slots
## (docs/campaign.md, "Blades on the beat"). Each is wired to a beat channel
## (`;! channel 4 beat 0`) and cuts on physics frame 100k + its phase, every
## time, on every device -- never on the music's clock, which drifts. It is in
## time with the music anyway, because the music is 72 beats a minute and at
## 60 Hz that is exactly 50 frames a beat: a blade's 100-frame period is two
## beats, and its phase of 0 or 50 puts it on the beat or the off-beat.
##
## ## One cycle, counted from the cut
##
## `t` is frames since this blade's last cut, 0 to PERIOD - 1, read straight
## off the bus (ChannelBus.beat()), so a hitstop or a pause holds it with
## everything else and a respawn starts the count again with the bus:
##
## | t | scythe | slot |
## | --- | --- | --- |
## | 0 .. live | the cut, live | up, lethal |
## | live .. | the arm swings back, then rests | down |
## | PERIOD - tell .. PERIOD | drawn back; the ratchet ticks three times | the grille rattles |
##
## The tell is Patrol.WINDUP_TIME -- the one telegraph length the whole game
## reads as "now" -- through `warn()`, so the LONGER WARNINGS assist widens it
## exactly as it widens a sentinel's raise. It widens into the rest, which is
## the only part of the cycle that can give: the cut lands on the beat (the
## music's period is not a warning), and the cut and the opening after it keep
## their own lengths, as the assist promises (scripts/core/assist.gd). A
## blade whose tell, cut and return would not fit in one period is refused by
## the proof (BeatProof).
##
## ## Heard where it is seen
##
## Every threat is heard as well as seen: the ratchet's three ticks and the
## cut are the scythe's, the rattle and the rise the slot's -- each cued on its
## own frame of the blade's own clock. Under them, while any blade is on
## screen, the Well's escapement knocks softly on every beat: the machine
## keeping time, a pulse to run the rhythm to. It is one knock however many
## blades are in view (the bus remembers the frame it last knocked on), and it
## is the ratchet's own timbre a fifth down, so the two read as one machine.
## Off screen the machine is silent (CameraView): a cue from out of the frame
## is a sound with nothing to read it against.
##
## ## What it is to the proof
##
## A timing hazard, which the reachability search leaves out exactly as it
## leaves out a sentinel's cut: its cells are air as authored and the reach
## hook says nothing that changes them. What it files instead is its timing
## (ReachModel.note()), which BeatProof reads to prove every crossing has the
## window and the slack the bible asks for -- from the same static numbers
## this file plays, so the proof and the play cannot drift apart.
##
## ## The rest of the craft
##
## Steel is for blades and spikes and nothing else (docs/art-direction.md), so
## a blade is drawn in STEEL on ink, and its tell is a pose and a sound, never
## a colour alone. It is in the lit group: the night's grade never darkens a
## tell (WorldGrade).

## The group blades put themselves in, for whatever their cut can reach
## besides the prince -- an owl whose stoop crosses one on the beat.
const GROUP := &"beat_blades"
## Two beats at 72 BPM, in physics frames.
const PERIOD := 100
## One beat.
const BEAT := 50
## The telegraph, in seconds: the sentinel's raise, the game's "now".
const TELL := Patrol.WINDUP_TIME
const FRAME := 1.0 / 60.0
## The Well's escapement: the ratchet's voice, low and soft, unvaried so the
## pulse is a pulse.
const ESCAPEMENT := {"pitch": 0.75, "volume_db": -15.0, "vary": false}
const _KNOCKED := &"beat_blade_knocked"

## Frames since this blade's last cut.
var t := 0

var _last := -1
## False until the clock has given the blade a whole tell: a bus starts at
## frame 0 on a load and on every respawn, and a blade on phase 0 would
## otherwise cut on that frame with no warning at all. The first cut is the
## first one a tell came before.
var _armed := false


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(MatchDusk.LIT)


## --- timing, shared by play and proof -----------------------------------------

## How long the tell lasts, in frames: the sentinel's raise, through warn().
func tell_frames() -> int:
	return roundi(warn(TELL) / FRAME)


## Frames the blade is live from its cut. Each blade overrides it with its
## own static number, which is also what the proof reads (BeatProof): a static
## function is not looked up on the instance, so play asks through this one.
func live() -> int:
	return 0


## Frames after the live ones before the blade can be told again: a scythe's
## arm swinging back. Nothing for a slot, which is down as soon as it is down.
func recover() -> int:
	return 0


func is_live() -> bool:
	return _armed and t < live()


func is_telling() -> bool:
	return t >= PERIOD - tell_frames()


## 0 at the start of the tell, 1 at the cut; 0 outside the tell.
func tell_progress() -> float:
	if not is_telling():
		return 0.0
	return float(t - (PERIOD - tell_frames())) / float(tell_frames())


## What the cut reaches while it is live, in world units; empty otherwise.
func cut_rect() -> Rect2:
	return danger_rect(cells) if is_live() else Rect2()


## The rectangle the cut sweeps, whether or not it is live now: every cell of
## the run. Static, so the proof measures the same thing play does.
static func danger_rect(of_cells: Array[Vector2i]) -> Rect2:
	var out := cell_rect(of_cells[0])
	for cell: Vector2i in of_cells:
		out = out.merge(cell_rect(cell))
	return out


## --- the mechanism ------------------------------------------------------------

func _setup() -> void:
	t = _clock()
	_last = t
	_armed = false
	_apply()


## The clock, the cues on its frames, and the cut against the prince.
func meet(contact: Contact) -> void:
	_advance(_clock())
	if is_live() and contact.alive:
		_strike(contact)


## Moves the clock to `now`, giving every frame passed its due -- normally one.
func _advance(now: int) -> void:
	if now == _last:
		return
	var steps := posmod(now - _last, PERIOD)
	for _i: int in steps:
		t = (_last + 1) % PERIOD
		_last = t
		_on_frame()
	_apply()
	queue_redraw()


func _clock() -> int:
	if bus == null or channel == &"":
		return 0
	return bus.beat(channel)


## One frame of the clock: the cues that belong to it.
func _on_frame() -> void:
	var tell := tell_frames()
	if t == PERIOD - tell:
		_armed = true
	for step: int in 3:
		if t == PERIOD - tell + step * tell / 3:
			_on_tell_step(step)
	if t == 0 and _armed:
		_on_cut()
	if bus != null and bus.frame % BEAT == 0 and _on_screen():
		_knock()


## The escapement: once per beat, however many blades are on screen.
func _knock() -> void:
	if int(bus.get_meta(_KNOCKED, -1)) == bus.frame:
		return
	bus.set_meta(_KNOCKED, bus.frame)
	cue.emit(&"ladder", ESCAPEMENT)


func _on_screen() -> bool:
	return CameraView.shows(self, danger_rect(cells).grow(Mechanism.TILE))


## --- for a blade to override ------------------------------------------------

## Collision and look for the current `t`.
func _apply() -> void:
	pass


## The tell's three beats: 0, 1, 2.
func _on_tell_step(_step: int) -> void:
	pass


func _on_cut() -> void:
	pass


## The cut is live and the prince is alive: what it does to him.
func _strike(_contact: Contact) -> void:
	pass


## --- the proof ----------------------------------------------------------------

## Says nothing about passability -- a timing hazard is left out of the
## search, as a sentinel's cut is -- and files its timing for BeatProof.
static func reach(mark: Dictionary, model: ReachModel) -> void:
	model.note(&"beat", {
		"kind": String(mark["kind"]),
		"cells": mark_cells(mark),
		"channel": mark_channel(mark),
		"mark": mark.get("mark", Vector2i(-1, -1)),
	})


## Nothing without a wire: a blade with no beat has no clock.
static func wired() -> bool:
	return true
