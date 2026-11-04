extends GutTest
## An iron grate (`h`, scripts/mechanisms/hatch.gd) lets the light through,
## as it is drawn doing: a beam passes it, a bolt flies through it, and the
## proof traces it the same way the game does.
##
## Its cell is a one-way floor in the grid -- that is how it is walked on,
## dropped and plunged through -- and a floor stops light, so before
## SunField.stops_light_at() asked what the cell is made of, the one cell in
## the game drawn as bars the sun falls through was a cell that stopped every
## beam and bolt, while a portcullis's bars let them by.

const GAME_SCENE := "res://scenes/game.tscn"

## A mirror in the afternoon sun, facing up as every mirror starts, under a
## roof with a grate in it straight above. Nothing above the roof but sky.
const ROOM := """; Grate Room



     ###h###



  @     x     D
################
################
"""

const MIRROR := Vector2i(8, 7)
const GRATE := Vector2i(8, 3)

var _game: Game


func _play() -> void:
	var data := AsciiLevel.new()
	data.parse(ROOM)
	assert_eq(data.problems, PackedStringArray(), "the room parses clean")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	await wait_physics_frames(4)


func test_the_grate_is_a_floor_that_does_not_stop_light() -> void:
	var data := AsciiLevel.new()
	data.parse(ROOM)
	assert_eq(data.kind_at(GRATE.x, GRATE.y), Tiles.Kind.PLATFORM, "walked on as a floor")
	assert_true(SunField.is_grate(data, GRATE), "and known for a grate by its glyph")
	assert_false(SunField.stops_light_at(data, GRATE, Tiles.Kind.PLATFORM),
		"which the light goes through")
	assert_true(SunField.stops_light_at(data, GRATE + Vector2i.LEFT, Tiles.Kind.SOLID),
		"while the stone beside it stops it")
	var proof := SunProof.blocks(data, [], {})
	assert_false(bool(proof.call(GRATE)), "and the proof reads it the same way")
	assert_true(bool(proof.call(GRATE + Vector2i.RIGHT)), "stone for stone")


func test_a_beam_goes_up_through_the_grate_to_the_sky() -> void:
	await _play()
	var light := SunField.light_of(_game.level)
	assert_true((light["lit"] as Dictionary).has(MIRROR), "the mirror is in the sun")
	var through := false
	for beam: Dictionary in light["beams"]:
		var cells: Array = beam["cells"]
		if cells.has(GRATE + Vector2i.UP):
			through = true
	assert_true(through, "its beam carries on past the grate")
	assert_false((light["struck"] as Dictionary).has(GRATE), "and does not end on it")


func test_a_bolt_flies_down_through_the_grate() -> void:
	await _play()
	var start := _game.level.entity_world_position(GRATE + Vector2i.UP * 2)
	var bolt := Sunbolt.make(start - Vector2(0.0, 8.0), Vector2.DOWN)
	bolt.level = _game.level
	_game.get_node("Entities").add_child(bolt)
	var ref: WeakRef = weakref(bolt)
	# Two tiles to the grate and one past it: 48 px at 2.5 px a frame.
	await wait_physics_frames(22)
	assert_not_null(ref.get_ref(), "the bolt is still flying")
	if ref.get_ref() != null:
		var below := _game.level.cell_of((ref.get_ref() as Sunbolt).global_position)
		assert_gt(below.y, GRATE.y, "on the far side of the grate")
