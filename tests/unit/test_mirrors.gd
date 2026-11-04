extends GutTest
## Sun mirrors and sun-seals (docs/campaign.md, "Sun mirrors and sun-seals"):
## the light traced over the grid, a mirror turned by every sword move, a
## seal filled, drained and opened, what a respawn keeps -- played through
## the real game scene -- and the proof over them: a door opened only through
## its mirror, a door whose mirror is behind it refused, and a mirror the
## dresser shades caught.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")
const FRAME := 1.0 / 60.0

## A mirror on a floor in the afternoon sun, a sun-seal door in a wall east of
## it in the same row, and the way out beyond the door.
const ROOM := """; Mirror Room
          #
          #
          #
          #
          O
  @    x  O    D
################
################
"""

## Four mirrors in a row, each a cell apart, every one lighting the next: one
## puzzle of four.
const CROWDED := """; Crowded Room
            #
            #
            #
            #
            O
 @x x x x   O    D
##################
##################
"""

## The same room with its mirror beyond the door: the door is the way to its
## own key.
const LOCKED := """; Locked Room
          #
          #
          #
          #
          O
  @       O  x D
################
################
"""

## The room with a column dressed in where its shadow falls on the mirror,
## two tiles up the sun's lane from it
## (`|` is an authored column, docs/world.md): the bare terrain lights the
## mirror, the dressing does not.
const SHADED := """; Shaded Room
          #
          #
     |    #
     |    #
     |    O
  @  | x  O    D
################
################
"""

const MIRROR := Vector2i(7, 5)
const DOOR: Array[Vector2i] = [Vector2i(10, 4), Vector2i(10, 5)]


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func _play(text: String) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	assert_eq(data.problems, PackedStringArray(), "the room parses clean")
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(4)


func _mirror() -> SunMirror:
	for node: Node in _game.get_node("Entities").get_children():
		if node is SunMirror and not node.is_queued_for_deletion():
			return node as SunMirror
	return null


func _seal() -> SunSeal:
	for node: Node in _game.get_node("Entities").get_children():
		if node is SunSeal and not node.is_queued_for_deletion():
			return node as SunSeal
	return null


## Puts the prince's feet in `cell`, at rest, facing `facing`.
func _stand(cell: Vector2i, facing: int) -> void:
	_game.player.respawn(_game.level.entity_world_position(cell))
	_game.player.facing = facing
	await wait_physics_frames(2)


func _press(bits: int, frames: int = 1) -> void:
	_input.bits = bits
	await wait_physics_frames(frames)
	_input.bits = 0


func _door_is_shut() -> bool:
	for cell: Vector2i in DOOR:
		if _game.level.kind_at_cell(cell) != Tiles.Kind.SOLID:
			return false
	return true


## --- the light, traced ------------------------------------------------------

func _blocks(grid: Dictionary) -> Callable:
	return func(cell: Vector2i) -> bool:
		return SunField.stops_light(grid.get(cell, Tiles.Kind.EMPTY))


func test_a_beam_stops_at_stone_and_platforms_and_passes_the_rest() -> void:
	var grid := {
		Vector2i(3, 0): Tiles.Kind.LADDER, Vector2i(4, 0): Tiles.Kind.BACKDROP,
		Vector2i(5, 0): Tiles.Kind.SPIKES, Vector2i(6, 0): Tiles.Kind.WATER,
		Vector2i(8, 0): Tiles.Kind.SOLID,
	}
	var beam := SunLight.trace(Vector2i(1, 0), SunLight.Face.RIGHT, 20, 3, _blocks(grid), {})
	assert_eq(beam["ends"], SunLight.ENDS_STONE, "stone stops it")
	assert_eq(beam["end"], Vector2i(8, 0), "at the first stone in its row")
	assert_eq((beam["cells"] as Array).size(), 6, "through ladder, backdrop, spikes and water")
	grid[Vector2i(4, 0)] = Tiles.Kind.PLATFORM
	beam = SunLight.trace(Vector2i(1, 0), SunLight.Face.RIGHT, 20, 3, _blocks(grid), {})
	assert_eq(beam["end"], Vector2i(4, 0), "a one-way platform stops it too")
	beam = SunLight.trace(Vector2i(1, 2), SunLight.Face.UP, 20, 3, _blocks({}), {})
	assert_eq(beam["ends"], SunLight.ENDS_SKY, "facing up, the light goes to the sky")


func test_a_beam_into_a_mirror_lights_it_and_a_lit_mirror_is_traced_once() -> void:
	var mirrors := {
		Vector2i(1, 4): {"face": SunLight.Face.RIGHT, "turning": false, "sun": true},
		Vector2i(6, 4): {"face": SunLight.Face.LEFT, "turning": false, "sun": false},
	}
	var light := SunLight.network(mirrors, 20, 8, _blocks({}))
	assert_true((light["lit"] as Dictionary).has(Vector2i(6, 4)), "the beam lights the far mirror")
	assert_eq((light["beams"] as Array).size(), 2, "which throws its own beam, and no loop")
	mirrors[Vector2i(1, 4)]["turning"] = true
	light = SunLight.network(mirrors, 20, 8, _blocks({}))
	assert_eq((light["beams"] as Array).size(), 0, "a mirror mid-turn throws nothing")


## --- the strike ---------------------------------------------------------------

func test_a_swing_turns_a_mirror_a_quarter_once_and_its_beam_is_dark_while_it_turns() -> void:
	await _play(ROOM)
	var mirror := _mirror()
	assert_eq(mirror.face, SunLight.Face.UP, "every mirror starts facing up")
	assert_true(mirror.is_lit(), "and the sun is on it")
	await _stand(MIRROR + Vector2i.LEFT, 1)
	_input.bits = PlayerInput.BIT_ATTACK
	var turning_seen := false
	var dark_seen := false
	for _frame: int in 30:
		await wait_physics_frames(1)
		_input.bits = 0
		if mirror.is_turning():
			turning_seen = true
			dark_seen = dark_seen or (SunField.light_of(_game.level)["beams"] as Array).is_empty()
	assert_true(turning_seen, "the blade turned it")
	assert_true(dark_seen, "and no beam left it while it turned")
	assert_eq(mirror.face, SunLight.Face.RIGHT, "a quarter clockwise, once, for one swing")


## Coming down beside the disc, the slash's band -- chest to past the feet --
## crosses it.
func test_an_air_slash_turns_it_too() -> void:
	await _play(ROOM)
	var mirror := _mirror()
	var floor_y := float(MIRROR.y + 1) * Level.TILE
	_game.player.respawn(Vector2(SunLight.pivot(MIRROR).x - 12.0, floor_y - 10.0))
	_game.player.facing = 1
	await wait_physics_frames(1)
	await _press(PlayerInput.BIT_ATTACK)
	await wait_physics_frames(40)
	assert_eq(mirror.face, SunLight.Face.RIGHT, "a slash in the air turns it")


func test_a_plunge_turns_it_too() -> void:
	await _play(ROOM)
	var mirror := _mirror()
	_game.player.respawn(SunLight.pivot(MIRROR) + Vector2(0.0, -40.0))
	await wait_physics_frames(2)
	await _press(PlayerInput.BIT_DOWN | PlayerInput.BIT_ATTACK)
	await wait_physics_frames(40)
	assert_eq(mirror.face, SunLight.Face.RIGHT, "a plunge past the disc turns it")


## --- the seal -----------------------------------------------------------------

func test_a_lit_seal_fills_over_the_telegraph_then_sinks_and_stays_open() -> void:
	await _play(ROOM)
	var seal := _seal()
	assert_true(_door_is_shut(), "shut as authored")
	await _stand(MIRROR + Vector2i.LEFT, 1)
	await _press(PlayerInput.BIT_ATTACK)
	# Counted on the engine's physics clock: GUT's one-frame wait is two.
	var lit_at := -1
	var full_at := -1
	for _step: int in 120:
		await wait_physics_frames(1)
		if lit_at < 0 and seal.fill > 0.0:
			lit_at = Engine.get_physics_frames()
		if full_at < 0 and seal.fill >= 1.0:
			full_at = Engine.get_physics_frames()
	assert_gt(lit_at, 0, "the light reached it")
	assert_almost_eq(full_at - lit_at, SunSeal.FILL_FRAMES - 1, 2,
		"eight rays over the game's telegraph length")
	assert_false(_door_is_shut(), "sunk into the floor, and open")
	assert_true(_game._bus.is_on(seal.latch_channel()), "its wire latched: a deed")


func test_a_seal_drains_when_the_light_leaves() -> void:
	await _play(ROOM)
	var seal := _seal()
	var mirror := _mirror()
	await _stand(MIRROR + Vector2i.LEFT, 1)
	await _press(PlayerInput.BIT_ATTACK)
	for _frame: int in 30:
		await wait_physics_frames(1)
		if seal.fill > 0.4:
			break
	var part := seal.fill
	assert_between(part, 0.3, 0.9, "part filled")
	# The second strike sends the light down into the floor.
	await _press(PlayerInput.BIT_ATTACK)
	await wait_physics_frames(SunSeal.FILL_FRAMES + 10)
	assert_eq(mirror.face, SunLight.Face.DOWN, "turned away")
	assert_eq(seal.fill, 0.0, "and the rays drained")
	assert_true(_door_is_shut(), "still shut")


func test_a_respawn_turns_the_mirrors_back_and_keeps_the_door_open() -> void:
	await _play(ROOM)
	await _stand(MIRROR + Vector2i.LEFT, 1)
	await _press(PlayerInput.BIT_ATTACK)
	await wait_physics_frames(SunSeal.FILL_FRAMES + SunSeal.SINK_FRAMES + 20)
	assert_false(_door_is_shut(), "opened")
	DeathWatch.expect_deaths(1)
	_game.player.kill()
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	await wait_physics_frames(2)
	assert_eq(_mirror().face, SunLight.Face.UP, "a trap resets: the mirror faces up again")
	assert_false(_door_is_shut(), "a deed does not: the door stays open")
	assert_eq(_seal().phase, SunSeal.Phase.OPEN, "and is rebuilt open")


## --- the proof ----------------------------------------------------------------

func test_the_proof_opens_a_door_only_through_its_mirror() -> void:
	var room := AsciiLevel.new()
	room.parse(ROOM)
	assert_true(bool(LevelReachability.verify(room)["ok"]), "the mirror opens the way")
	var bare := AsciiLevel.new()
	bare.parse(ROOM.replace("x", " "))
	assert_false(bool(LevelReachability.verify(bare)["ok"]), "without it the door never opens")
	var audit := SunProof.audit(room)
	assert_true(bool(audit["ok"]), "and the light passes the audit: %s" % audit["reason"])
	assert_gt(int(audit["checks"]), 0, "having checked something")


func test_a_door_whose_mirror_is_behind_it_is_refused() -> void:
	var locked := AsciiLevel.new()
	locked.parse(LOCKED)
	assert_false(bool(LevelReachability.verify(locked)["ok"]),
		"the door cannot be the way to its own key")
	var audit := SunProof.audit(locked)
	assert_false(bool(audit["ok"]), "and the audit says so")
	assert_string_contains(String(audit["reason"]), "cannot be opened from anywhere it is shut")


func test_more_than_three_mirrors_to_a_puzzle_is_refused() -> void:
	var crowded := AsciiLevel.new()
	crowded.parse(CROWDED)
	var audit := SunProof.audit(crowded)
	assert_false(bool(audit["ok"]), "four mirrors that light one another are one puzzle")
	assert_string_contains(String(audit["reason"]), "the most a puzzle may have is 3")


## The bible's check on the renderer's half: every mirror the proof calls lit
## is lit in the dressed mask the player sees, and every dark one dark.
func test_the_dressed_mask_agrees_with_the_proof_in_the_room() -> void:
	await _play(ROOM)
	assert_eq(MirrorChecks.disagreements(_game), PackedStringArray(),
		"the proof and the picture agree about the sun on every mirror")


func test_a_mirror_shaded_by_dressing_is_caught() -> void:
	await _play(SHADED)
	var found := MirrorChecks.disagreements(_game)
	assert_false(found.is_empty(), "the column's shadow on the mirror is a disagreement")
	for line: String in found:
		assert_string_contains(line, str(MIRROR), "and it is that mirror's")
	assert_false(_mirror().is_lit(), "and in play the mirror is in its shadow")


## A cliff with mirror A hung at its lip and mirror B in its shade below. The
## door opens only with A turned down -- its beam lighting B -- and B turned
## east; A is struck from the clifftop and B from the floor below, and a body
## that drops to B cannot climb back. A player who drops before turning A
## has broken the puzzle for good.
const FRAGILE := """; Fragile Room
                    #
                    #
                    #
 @         x        #
###########         #
###########         #
###########         #
###########         O
###########x        O   D
##############################
##############################
"""


func test_a_puzzle_the_prince_can_leave_broken_is_refused() -> void:
	var fragile := AsciiLevel.new()
	fragile.parse(FRAGILE)
	assert_eq(fragile.problems, PackedStringArray(), "the room parses clean")
	assert_true(bool(LevelReachability.verify(fragile)["ok"]),
		"the route alone is provable: turn A from the top, drop, turn B")
	var audit := SunProof.audit(fragile)
	assert_false(bool(audit["ok"]), "but the audit refuses the puzzle")
	assert_string_contains(String(audit["reason"]), "can be left broken")


## The renderer's half of the sun check, shared with the chapter's test.
class MirrorChecks:
	## Every mirror whose sun in play, from the dressed mask, differs from the
	## proof's in any state of the doors in its lane -- said, one a line.
	static func disagreements(game: Game) -> PackedStringArray:
		var out := PackedStringArray()
		var data := game.level.data
		var light := TimeOfDay.light_of(data)
		var mask := SunShadow.last_mask
		for state: Dictionary in SunProof.sun_states(data):
			var cell: Vector2i = state["cell"]
			var at := SunLight.pivot(cell)
			var lit := mask.get_pixelv(Vector2i(at)).r < 0.5
			if lit:
				var open: Array = state["open"]
				for seal: Node in game.get_tree().get_nodes_in_group(SunField.SEALS):
					var door := seal as SunSeal
					if door.secret or open.has(door.latch_channel()):
						continue
					for lane: Vector2i in SunLight.sun_lane(at, float(light["reach"])):
						if door.cells.has(lane):
							lit = false
			if lit != bool(state["lit"]):
				out.append("mirror %s with %s open: the picture says %s, the proof %s"
					% [cell, open_list(state), lit, state["lit"]])
		return out

	static func open_list(state: Dictionary) -> String:
		return str(state["open"])
