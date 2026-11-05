class_name PoseLabFigure
extends Node2D
## One figure in the pose lab, held in a pose: the real body -- a Player or a
## duel Fighter -- frozen, with its state written from PoseCatalogue every
## frame, so the shipping art draws it exactly as play would.
##
## A real body rather than a mannequin (FigurePreview) because the lab's whole
## question is whether what play draws reads, and FighterArt reads its blade
## off the simulation's rects: only a Fighter has those. Neither body is ever
## stepped. A Player's physics is switched off and a Fighter has none of its
## own (the match steps it), so nothing here moves anything, and nothing
## reaches a simulation: the lab's sparring floor is PoseLabSpar.
##
## ## Playing and frozen
##
## Playing runs the state's clock round its `span` -- a thrust from wind-up to
## recovery and again, a run cycle -- by display time: this is presentation,
## like the art's own breathing. Frozen holds the catalogue's moment, lets the
## cloth settle on it for SETTLE frames, and then stops the art drawing anew,
## so the frame on screen is one frame and can be looked at.

enum Body { PRINCE, FIGHTER }

## Long enough for the cloth lag and the squash spring to settle on a pose,
## as tests/character_poses.gd waits.
const SETTLE := 14
## Frames into a pose before the dust it asks for is raised.
const EFFECT_LEAD := 3
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighter.tscn")

var body_kind := Body.FIGHTER
var pose: Dictionary = {}
var playing := true
## Whether the airborne offset of a pose is kept: the 1:1 figure rises off the
## floor for a jump, the enlarged inset keeps its feet on its sill.
var lifted := true

var _body: Node2D
var _clock := 0.0
var _settle := 0
var _fire_in := -1
var _last_loop := 0


## The body now in the frame: a Player or a Fighter.
func body() -> Node2D:
	return _body


func player() -> Player:
	return _body as Player


func fighter() -> Fighter:
	return _body as Fighter


func art() -> PlayerArt:
	if _body == null:
		return null
	return _body.get_node_or_null(^"FighterArt" if _body is Fighter else ^"PlayerArt") \
		as PlayerArt


## Swaps the body for one of `kind`, dressed in `look` (and the duel `seat`'s
## colours for a fighter). The body is built afresh on a change of kind, so
## the art's cloth and its idle start clean.
func dress(kind: Body, look: CharacterLook, seat: int) -> void:
	if _body == null or kind != body_kind:
		if _body != null:
			remove_child(_body)
			_body.free()
		body_kind = kind
		_body = (PLAYER_SCENE if kind == Body.PRINCE else FIGHTER_SCENE).instantiate()
		_body.name = "Body"
		add_child(_body)
		if _body is Player:
			(_body as Player).set_physics_process(false)
		else:
			(_body as Fighter).setup(seat, null)
			(_body as Fighter).respawn_at(Vector2.ZERO, 1)
	if _body is Fighter:
		(_body as Fighter).id = seat
		FighterArt.dress(_body as Fighter, seat, look)
	else:
		look.dress(art())
	_wake()


## Holds `entry`, a PoseCatalogue row of this figure's kind, from its start.
func show_pose(entry: Dictionary) -> void:
	pose = entry
	_clock = 0.0
	_last_loop = 0
	_fire_in = EFFECT_LEAD
	var fx := _body.get_node_or_null(^"PlayerFx") if _body != null else null
	if fx != null and fx.has_method("reset"):
		fx.call("reset")
	_wake()
	pin()


func set_playing(on: bool) -> void:
	playing = on
	_clock = 0.0
	_wake()
	pin()


## Writes the pose into the body for the moment the clock is at. True if every
## field took.
func pin() -> bool:
	if _body == null or pose.is_empty():
		return false
	var feet := Vector2.ZERO
	if _body is Player:
		var entry := pose
		if not lifted:
			entry = pose.duplicate()
			entry.erase("offset")
		var ok := PoseCatalogue.pin_player(_body as Player, entry, feet, _prince_time())
		var idle := (_body as Player).get_node_or_null(^"PlayerArt/IdleArt") as IdleArt
		if idle != null:
			idle.pin(int(pose.get("bit", IdleArt.Bit.NONE)) as IdleArt.Bit, _bit_time())
		return ok
	if lifted:
		feet = pose.get("offset", Vector2.ZERO)
	return PoseCatalogue.pin_fighter(_body as Fighter, pose, feet, _fighter_frame())


## The prince's clock: the moment, or round the state's span.
func _prince_time() -> float:
	if not playing or pose.has("bit"):
		return float(pose.get("t", 0.0))
	return fmod(_clock, float(pose.get("span", PoseCatalogue.PRINCE_SPAN)))


func _bit_time() -> float:
	if not playing:
		return float(pose.get("bit_t", 0.0))
	return fmod(_clock, float(pose.get("span", PoseCatalogue.PRINCE_SPAN)))


## The fighter's frame: 1 on entering a state, as the simulation counts.
func _fighter_frame() -> int:
	if not playing:
		return int(pose.get("frame", 1))
	var span := maxi(1, int(pose.get("span", PoseCatalogue.FIGHTER_SPAN)))
	return 1 + int(_clock * 60.0) % span


func _process(delta: float) -> void:
	if _body == null or pose.is_empty():
		return
	if playing:
		_clock += delta
		var loop := int(_clock / _span_seconds())
		if loop != _last_loop:
			_last_loop = loop
			_fire_in = EFFECT_LEAD
	pin()
	if _fire_in >= 0:
		_fire_in -= 1
		if _fire_in < 0:
			_fire()
	if _settle > 0:
		_settle -= 1
		if _settle == 0 and not playing:
			_set_art_running(false)


func _span_seconds() -> float:
	if _body is Fighter:
		return float(pose.get("span", PoseCatalogue.FIGHTER_SPAN)) / 60.0
	return maxf(0.05, float(pose.get("span", PoseCatalogue.PRINCE_SPAN)))


## Raises the signals a prince pose asks for -- a landing's dust, a hurt's
## flash -- so the moment looks as it does in play.
func _fire() -> void:
	if not (_body is Player):
		return
	for spec: Array in pose.get("emit", [] as Array):
		_body.callv("emit_signal", spec)


## Lets the art draw again for a while: on a new pose, a new look, a switch
## between playing and frozen.
func _wake() -> void:
	_settle = SETTLE
	_set_art_running(true)


func _set_art_running(on: bool) -> void:
	var drawn := art()
	if drawn == null:
		return
	drawn.set_process(on)
	if drawn.idle_art != null:
		drawn.idle_art.set_process(on)
	drawn.queue_redraw()


## Whether the figure is held still on one frame now. For a test.
func is_still() -> bool:
	var drawn := art()
	return drawn != null and not drawn.is_processing()
