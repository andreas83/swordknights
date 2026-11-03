class_name ChannelBus
extends RefCounted
## The wiring between a level's mechanisms: named channels that are on or off.
##
## A trigger turns a channel on; a receiver listening to it does whatever on
## means for it. Channels are named in the level text -- a plate and a gate
## declared with the same `channel=` are wired (docs/world.md, "Directives and
## wiring") -- so wiring is data an author edits, never code.
##
## ## Two ways to be on
##
## - **Held.** A source holds the channel while something is true -- a plate
##   with weight on it -- and releases it after. The channel is on while any
##   source holds it: two plates on one channel are an OR, and lifting one
##   foot off one of them does not shut the gate the other is holding.
## - **Latched.** On for good, until the bus is reset: the lever that stays
##   thrown, the plate that clicks and stays down.
##
## `changed` fires on edges only, off to on and on to off, synchronously, in
## the physics step that caused it. A receiver therefore changes its collision
## on the same frame its trigger was pressed, before the character's own step
## -- the same order every frame, which is what makes it deterministic.
##
## ## Resetting
##
## Game makes a new bus whenever the level's mechanisms are put back as
## authored -- a restart, a checkpoint respawn -- rather than resetting this
## one, so a mechanism on its way out can never hear a channel the new ones
## raise. See Game._respawn() for why a respawn puts them back at all.

## A channel went on or off.
signal changed(channel: StringName, on: bool)

## channel -> {source instance id: true}
var _holders: Dictionary = {}
## channel -> true
var _latched: Dictionary = {}


func is_on(channel: StringName) -> bool:
	if _latched.has(channel):
		return true
	return _holders.has(channel) and not (_holders[channel] as Dictionary).is_empty()


## `source` holds `channel` on until it releases it.
func hold(channel: StringName, source: Object) -> void:
	var was := is_on(channel)
	if not _holders.has(channel):
		_holders[channel] = {}
	(_holders[channel] as Dictionary)[source.get_instance_id()] = true
	_edge(channel, was)


func release(channel: StringName, source: Object) -> void:
	if not _holders.has(channel):
		return
	var was := is_on(channel)
	(_holders[channel] as Dictionary).erase(source.get_instance_id())
	_edge(channel, was)


## `channel` is on for good.
func latch(channel: StringName) -> void:
	var was := is_on(channel)
	_latched[channel] = true
	_edge(channel, was)


## The channels that are on, sorted, for a test or a debug readout.
func on_channels() -> Array[StringName]:
	var out: Array[StringName] = []
	for channel: StringName in _latched:
		out.append(channel)
	for channel: StringName in _holders:
		if is_on(channel) and not out.has(channel):
			out.append(channel)
	out.sort()
	return out


func _edge(channel: StringName, was: bool) -> void:
	var now := is_on(channel)
	if now != was:
		changed.emit(channel, now)
