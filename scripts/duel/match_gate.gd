class_name GateArt
extends Node2D
## The endpoint: a horseshoe arch with a crowd packed into it.
##
## Nidhogg's endpoint is a worm that eats the winner. docs/art-direction.md says
## this is a sun-bleached Moorish city at low sun, so the city's own equivalent
## is the one thing a city does to someone who has won something: the crowd at
## the gate takes them. They are lifted off their feet, carried through the arch
## and are gone — consumed by the place rather than by an animal, and the match
## is over on an image that belongs to this world instead of to another game's.
##
## Drawn, not modelled: a mass of overlapping silhouettes at near-black against
## the gate's shade, with raised arms over them. Per the art direction that is a
## FOREGROUND element — darker than the mid-ground, close to silhouette — and
## the deep arch is the only place on the strip where the hard gold light does
## not reach. The crowd shifts, never travels: this is a plane of depth, not a
## character.

const TILE := ZoneStrip.TILE

## How far the crowd fills out from the gate's mouth.
const SPAN := 46.0
const HEADS := 11
const LIFT := 26.0

## Which way the gate faces: -1 for the west gate, +1 for the east.
var facing: int = -1
## 0 to 1 while a winner is being carried through.
var consuming: float = 0.0

var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _heads: Array[Vector3] = []


func setup(at: Vector2, which_way: int, seed_value: int) -> void:
	position = at
	facing = -1 if which_way < 0 else 1
	_rng.seed = seed_value
	_heads.clear()
	for i: int in HEADS:
		# x out from the mouth, y up from the floor, and a bob phase.
		_heads.append(Vector3(
			_rng.randf_range(-0.1, 1.0) * SPAN * float(facing),
			_rng.randf_range(-19.0, -5.0),
			_rng.randf_range(0.0, TAU)
		))
	z_index = 2 # foreground: the crowd occludes a fighter standing in the gate


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var out := float(facing)

	# The shade of the arch behind them, so the silhouettes have something to be
	# silhouettes against.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, -72.0),
		Vector2(out * SPAN * 0.7, -62.0), Vector2(out * SPAN * 0.7, 0.0),
	]), Palette.with_alpha(Palette.INK, 0.55))

	for head: Vector3 in _heads:
		var bob := sin(_time * 2.4 + head.z) * 1.6 + consuming * sin(_time * 9.0) * 2.5
		var at := Vector2(head.x, head.y + bob)
		# Shoulders and head as one blob: at this size a crowd is texture.
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(-3.4, 19.0), at + Vector2(-2.6, -2.0),
			at + Vector2(2.6, -2.0), at + Vector2(3.4, 19.0),
		]), Palette.INK)
		draw_circle(at + Vector2(0.0, -3.6), 2.9, Palette.INK)
		# One arm up per head, raised further while they have someone to carry.
		var reach := 7.0 + consuming * 7.0
		draw_line(
			at + Vector2(1.6, 1.0),
			at + Vector2(1.6 + out * 2.0, 1.0 - reach),
			Palette.INK, 1.6
		)

	if consuming <= 0.0:
		return

	# The winner, held over their heads and going in. Drawn here rather than by
	# the fighter because by now they are the crowd's, not their own.
	var carried := Vector2(
		out * SPAN * 0.25 * consuming, -LIFT - 10.0 * consuming
	)
	var fade := clampf(1.0 - consuming, 0.0, 1.0)
	draw_colored_polygon(PackedVector2Array([
		carried + Vector2(-7.0, 3.0), carried + Vector2(-5.0, -3.0),
		carried + Vector2(7.0, -2.0), carried + Vector2(6.0, 4.0),
	]), Palette.with_alpha(Palette.CLOTH, fade * 0.9))
	draw_circle(carried + Vector2(0.0, -6.0), 3.2,
		Palette.with_alpha(Palette.PAPER, fade))
