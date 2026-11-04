class_name ChannelBus
extends RefCounted
## The wiring between a level's mechanisms: channels that are on or off.
##
## A trigger presses a channel and releases it; a receiver acts when the
## channel changes. What a press *means* is the channel's, not the
## trigger's, so a plate is just a plate and the level text says what its
## wire does (docs/world.md, "Directives and wiring"):
##
##     ;! channel 1 latch       on with the first press, for good
##     ;! channel 2 hold 4.0    on while pressed, then 4.0 s more
##     ;! channel 4 beat 0      a clock: on for the first half of each
##     ;! channel 5 beat 50     period (100 frames unless period=), phased
##
## A channel with no line is **momentary**: on while anything presses it, so
## two plates on one wire are an OR and lifting a foot off one does not drop
## the gate the other holds. Channels are named in the level -- a digit for a
## mason's mark, any word for a `channel=` parameter.
##
## ## The clock is the physics step
##
## `step()` is called once per playing physics frame by Game, and is all the
## time this bus knows: a hold counts down in frames and a beat is
## `frame - phase` modulo its period, so a blade on a beat cuts on the same
## physics frame on every device, whatever the display does, and never on
## the music's clock, which drifts. A hitstop or a pause stops Game stepping
## it, exactly as they stop the entities.
##
## `changed` fires on edges only, synchronously, in the step that caused
## them -- so a gate changes its collision on the frame its plate went down,
## before the prince's own step, the same order every frame.
##
## Game makes a new bus whenever the mechanisms are put back as authored (a
## restart, a checkpoint respawn), so one on its way out never hears the next.
## A respawn's bus keeps what the old one latched and nothing else: a trap
## resets, a deed does not (for_level(), and Game._respawn() for why).

signal changed(channel: StringName, on: bool)

enum Mode { MOMENTARY, LATCH, HOLD, BEAT }

## Physics frames this bus has been stepped: the beat clock.
var frame := 0

## channel -> {mode: Mode, frames: int, phase: int, period: int}
var _modes: Dictionary = {}
## channel -> {source instance id: true}
var _pressed: Dictionary = {}
## channel -> true
var _latched: Dictionary = {}
## channel -> frames a released hold has still to run
var _left: Dictionary = {}


## A bus with every channel the level's `;! channel` lines describe, all of
## them off -- except, for a checkpoint respawn, what `kept` (the bus being
## replaced) had latched. A press held, a hold running and a beat's phase are
## not carried: the respawn is the level as authored plus its deeds.
static func for_level(level: AsciiLevel, kept: ChannelBus = null) -> ChannelBus:
	var bus := ChannelBus.new()
	if level != null:
		for channel: String in level.channels:
			bus.configure(StringName(channel), level.channels[channel])
	if kept != null:
		bus._latched = kept._latched.duplicate()
	return bus


## `spec` as AsciiLevel.channels holds it: `{mode, seconds, phase, period}`.
func configure(channel: StringName, spec: Dictionary) -> void:
	var mode := Mode.MOMENTARY
	match String(spec.get("mode", "momentary")):
		"latch":
			mode = Mode.LATCH
		"hold":
			mode = Mode.HOLD
		"beat":
			mode = Mode.BEAT
	_modes[channel] = {
		"mode": mode,
		"frames": roundi(float(spec.get("seconds", 0.0)) * 60.0),
		"phase": int(spec.get("phase", 0)),
		"period": maxi(1, int(spec.get("period", 100))),
	}


func mode_of(channel: StringName) -> Mode:
	return int((_modes.get(channel, {}) as Dictionary).get("mode", Mode.MOMENTARY)) as Mode


func is_on(channel: StringName) -> bool:
	if _latched.has(channel):
		return true
	if mode_of(channel) == Mode.BEAT:
		return _beat_on(channel, frame)
	if _pressed.has(channel) and not (_pressed[channel] as Dictionary).is_empty():
		return true
	return int(_left.get(channel, 0)) > 0


## `source` presses `channel`: what that does is the channel's mode.
func press(channel: StringName, source: Object) -> void:
	var was := is_on(channel)
	if mode_of(channel) == Mode.LATCH:
		_latched[channel] = true
	else:
		if not _pressed.has(channel):
			_pressed[channel] = {}
		(_pressed[channel] as Dictionary)[source.get_instance_id()] = true
		_left.erase(channel)
	_edge(channel, was)


## `source` lets go. A hold starts its count when the last source does.
func release(channel: StringName, source: Object) -> void:
	if not _pressed.has(channel):
		return
	var held := _pressed[channel] as Dictionary
	if not held.has(source.get_instance_id()):
		return
	var was := is_on(channel)
	held.erase(source.get_instance_id())
	if held.is_empty() and mode_of(channel) == Mode.HOLD:
		_left[channel] = int((_modes[channel] as Dictionary)["frames"])
	_edge(channel, was)


## A bus with `channels` latched and nothing else: the deeds of a run saved
## at a torch (CampaignProgress), for for_level() to keep as a respawn keeps
## them. Whatever a level does not declare is the caller's to leave out.
static func of_latches(channels: PackedStringArray) -> ChannelBus:
	var bus := ChannelBus.new()
	for channel: String in channels:
		bus._latched[StringName(channel)] = true
	return bus


## The channels latched for good, sorted: what a saved checkpoint keeps.
func latched() -> PackedStringArray:
	var out := PackedStringArray()
	for channel: StringName in _latched:
		out.append(String(channel))
	out.sort()
	return out


## On for good, whatever the channel's mode: the deed that cannot be undone.
func latch(channel: StringName) -> void:
	var was := is_on(channel)
	_latched[channel] = true
	_edge(channel, was)


## One physics frame: holds count down, beats turn.
func step() -> void:
	frame += 1
	for channel: StringName in _left.keys():
		var was := is_on(channel)
		_left[channel] = int(_left[channel]) - 1
		if int(_left[channel]) <= 0:
			_left.erase(channel)
		_edge(channel, was)
	for channel: StringName in _modes:
		if mode_of(channel) == Mode.BEAT and not _latched.has(channel):
			var was := _beat_on(channel, frame - 1)
			if was != _beat_on(channel, frame):
				changed.emit(channel, not was)


## Frames into the current period of a beat channel, phase applied: a blade
## cuts when this comes round to its moment.
func beat(channel: StringName) -> int:
	var spec := _modes.get(channel, {}) as Dictionary
	return posmod(frame - int(spec.get("phase", 0)), int(spec.get("period", 100)))


## Frames a released hold on `channel` has left; 0 when none is running.
func hold_left(channel: StringName) -> int:
	return int(_left.get(channel, 0))


## The channels that are on, sorted, for a test or a debug readout.
func on_channels() -> Array[StringName]:
	var seen := {}
	for channel: StringName in _latched:
		seen[channel] = true
	for channel: StringName in _pressed:
		if is_on(channel):
			seen[channel] = true
	for channel: StringName in _left:
		seen[channel] = true
	for channel: StringName in _modes:
		if is_on(channel):
			seen[channel] = true
	var out: Array[StringName] = []
	for channel: StringName in seen:
		out.append(channel)
	out.sort()
	return out


func _beat_on(channel: StringName, at_frame: int) -> bool:
	var spec := _modes[channel] as Dictionary
	var period := int(spec["period"])
	return posmod(at_frame - int(spec["phase"]), period) < period / 2


func _edge(channel: StringName, was: bool) -> void:
	var now := is_on(channel)
	if now != was:
		changed.emit(channel, now)
