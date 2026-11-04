extends GutTest
## The owl (scripts/entities/owl.gd), held to docs/campaign.md, "The owl":
## it takes what is not standing on stone, and the move it is for is the air
## slash.
##
## What is pinned:
##
## - it never stoops at a prince on the stone, and folds for one who is back
##   on it before the spread ends;
## - the spread is the sentinel's 27 frames, through warn(), so the assist
##   widens it; the stoop is a straight dive to where he was, at 3.5 px a
##   frame, never longer than 37 frames;
## - its talons are not a blade: no parry, no backstep;
## - it acts only while the camera shows it, and dies to a blade it flies
##   through on the beat;
## - "off the stone" is one query on Player, and Game hands it to every foe;
## - a grab and an immediate mantle beat the spread, and folding takes long
##   enough that a hop and a climb straight after it are over first;
## - in the real scene, an air slash kills it.

const GAME_SCENE := "res://scenes/game.tscn"
const FRAME := 1.0 / 60.0

## A floor under an owl on a column: room to jump and to slash.
const FLOOR := """; Owl Floor
################
#              #
#              #
#       Y      #
#       |      #
#       |      #
#       |      #
#   @   |     D#
################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


## Calls `think` once per physics frame, before anything in the scene moves:
## a test's thumbs, frame-exact. An `await wait_physics_frames(1)` loop is
## not -- it can resume after several physics steps -- and the owl's timings
## are counted in single frames.
class Driver extends Node:
	var think := Callable()
	var frame := 0

	func _ready() -> void:
		process_physics_priority = -1000

	func _physics_process(_delta: float) -> void:
		frame += 1
		if think.is_valid():
			think.call(frame)


func before_each() -> void:
	Assist.reset()


func after_each() -> void:
	Assist.reset()


## An owl perched with its middle at `at`, no level, no camera: everything is
## in sight and on screen, so its decision is all that is tested.
func _owl(at: Vector2 = Vector2(200.0, 100.0)) -> Owl:
	var owl := Owl.new()
	var site := EntitySite.new()
	site.at = at + Vector2(0.0, Owl.PERCHED.y * 0.5)
	site.post = "owl@test"
	owl.place(site)
	autofree(owl)
	return owl


## A prince's body with its middle at `at`.
func _body(at: Vector2) -> Rect2:
	return Rect2(at - Vector2(Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT) * 0.5,
		Vector2(Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT))


func _tick(owl: Owl, frames: int) -> void:
	for _frame: int in frames:
		owl.tick(FRAME)


## --- the rule -------------------------------------------------------------------

func test_it_never_stoops_at_a_prince_on_the_stone() -> void:
	var owl := _owl()
	owl.target_rect = _body(owl.position + Vector2(-40.0, 60.0))
	owl.target_off_stone = false
	for _frame: int in 300:
		owl.tick(FRAME)
		assert_eq(owl.state, Owl.State.PERCH, "it watches a prince on his feet, and only watches")
		if owl.state != Owl.State.PERCH:
			return
	assert_gt(owl.look, -1.01, "with its head turned toward him")


func test_it_folds_for_a_prince_back_on_the_stone() -> void:
	var owl := _owl()
	owl.target_rect = _body(owl.position + Vector2(-40.0, 60.0))
	owl.target_off_stone = true
	owl.tick(FRAME)
	assert_eq(owl.state, Owl.State.SPREAD, "off the stone, in range: it spreads")
	_tick(owl, 20)
	owl.target_off_stone = false
	owl.tick(FRAME)
	assert_eq(owl.state, Owl.State.FOLD, "back on the stone before the end: it folds")
	_tick(owl, 60)
	assert_eq(owl.state, Owl.State.PERCH, "and watches again, having struck at nothing")


func test_the_spread_is_the_tell_and_the_assist_widens_it() -> void:
	assert_eq(_spread_frames(), 27, "the sentinel's 27 frames")
	Assist.load_saved("user://test_owl_assist.cfg")
	Assist.set_longer_warnings(true)
	assert_eq(_spread_frames(), roundi(27.0 * Assist.LONGER), "41 with the assist on")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_owl_assist.cfg"))


## Frames from the spread to the stoop, for a prince who stays in the air.
func _spread_frames() -> int:
	var owl := _owl()
	owl.target_rect = _body(owl.position + Vector2(-40.0, 60.0))
	owl.target_off_stone = true
	owl.tick(FRAME)
	var frames := 1
	while owl.state == Owl.State.SPREAD and frames < 200:
		owl.tick(FRAME)
		frames += 1
	assert_eq(owl.state, Owl.State.STOOP, "it stoops at the end")
	return frames - 1


func test_the_stoop_is_a_straight_dive_to_where_he_was() -> void:
	var owl := _owl()
	var there := owl.position + Vector2(-90.0, 85.0)
	owl.target_rect = _body(there)
	owl.target_off_stone = true
	_tick(owl, 28)
	assert_eq(owl.state, Owl.State.STOOP, "spread over, still in the air: it dives")
	assert_eq(owl.aim, there, "at his middle, where he was as the spread ended")
	owl.target_rect = _body(there + Vector2(60.0, 0.0))
	var from := owl.position
	var frames := 0
	while owl.state == Owl.State.STOOP:
		var before := owl.position
		owl.tick(FRAME)
		frames += 1
		if owl.state == Owl.State.STOOP:
			assert_almost_eq(before.distance_to(owl.position), Owl.STOOP_SPEED * FRAME, 0.01,
				"3.5 px a frame")
	assert_eq(owl.position, there, "it arrives where he was, not where he went")
	assert_almost_eq(float(frames), from.distance_to(there) / (Owl.STOOP_SPEED * FRAME), 1.0,
		"in a straight line")
	assert_lte(Owl.RANGE / (Owl.STOOP_SPEED * FRAME), 37.0, "no stoop is longer than 37 frames")
	assert_eq(owl.state, Owl.State.PULL_UP, "then it pulls up")
	assert_false(owl.is_dangerous(), "harmless as it goes")
	_tick(owl, roundi(Owl.PULL_UP_TIME / FRAME) + 1)
	assert_eq(owl.state, Owl.State.PERCH, "and is home after its 90 frames")
	assert_eq(owl.position, owl.perch)


func test_out_of_range_it_only_watches() -> void:
	var owl := _owl()
	owl.target_rect = _body(owl.position + Vector2(Owl.RANGE + 10.0, 0.0))
	owl.target_off_stone = true
	_tick(owl, 60)
	assert_eq(owl.state, Owl.State.PERCH, "eight tiles is as far as it hunts")


func test_its_talons_are_not_a_blade() -> void:
	var owl := _owl()
	owl.target_rect = _body(owl.position + Vector2(-40.0, 60.0))
	owl.target_off_stone = true
	_tick(owl, 30)
	assert_true(owl.is_dangerous(), "the talons are live in the stoop")
	var talons: FoeDanger = owl.dangers()[0]
	assert_false(talons.can_be_parried(), "a parry turns blades, and these are not one")
	assert_false(talons.evadable, "nor does a backstep slip them")
	assert_false(talons.rollable, "nor a roll pass under a body coming down on him")


func test_a_dive_kick_knocks_it_into_the_air_and_never_wounds_it() -> void:
	var owl := _owl()
	var home := owl.position
	var outcome := owl.take_blow(Foe.Blow.KICK, home.x - 20.0)
	assert_eq(outcome, Foe.Outcome.STAGGERED, "the heel rocks it; it does not ring off")
	assert_true(owl.is_alive(), "and the feet never wound")
	assert_eq(owl.state, Owl.State.PULL_UP, "off its perch, into the pull-up")
	_tick(owl, 20)
	assert_true(owl.is_flying(), "in the air: hittable")
	assert_gt(owl.position.x, home.x, "thrown away from the heel")
	assert_lt(owl.position.y, home.y, "and up, not through the stone it sat on")
	assert_eq(owl.take_blow(Foe.Blow.KICK, home.x - 20.0), Foe.Outcome.BLOCKED,
		"already going home: a second kick rings off")
	_tick(owl, roundi(Owl.PULL_UP_TIME * 60.0))
	assert_eq(owl.state, Owl.State.PERCH, "and home again")
	assert_eq(owl.position, home, "on its own perch")
	assert_eq(owl.take_blow(Foe.Blow.THROWN, home.x - 20.0), Foe.Outcome.KILLED,
		"the thrown sword is a blade, and one heart is all it has")


func test_it_acts_only_while_the_camera_shows_it() -> void:
	var owl := _owl()
	owl.set_physics_process(false)
	add_child(owl)
	var camera := Camera2D.new()
	add_child_autofree(camera)
	camera.make_current()
	camera.global_position = owl.global_position + Vector2(4000.0, 0.0)
	await wait_physics_frames(2)
	owl.target_rect = _body(owl.position + Vector2(-40.0, 60.0))
	owl.target_off_stone = true
	_tick(owl, 30)
	assert_eq(owl.state, Owl.State.PERCH, "off the screen it does nothing at all")
	camera.global_position = owl.global_position
	await wait_physics_frames(2)
	owl.tick(FRAME)
	assert_eq(owl.state, Owl.State.SPREAD, "on it, it hunts")
	remove_child(owl)


func test_the_machine_kills_it() -> void:
	var owl := _owl(Vector2(88.0, 40.0))
	owl.set_physics_process(false)
	add_child(owl)
	var bus := ChannelBus.new()
	bus.configure(&"4", {"mode": "beat", "phase": 0})
	var scythe := Scythe.new()
	var site := EntitySite.new()
	site.cells = [Vector2i(5, 4), Vector2i(5, 5)]
	site.cell = Vector2i(5, 5)
	site.at = Vector2(88.0, 96.0)
	site.params = {"channel": "4"}
	site.bus = bus
	scythe.place(site)
	add_child_autofree(scythe)
	# Into the doorway, at its middle.
	owl.target_rect = _body(Vector2(88.0, 84.0))
	owl.target_off_stone = true
	_tick(owl, 28)
	assert_eq(owl.state, Owl.State.STOOP, "diving down through the doorway")
	_tick(owl, 9)
	assert_true(owl.is_alive(), "into it while the blade rests")
	scythe.t = 2
	scythe.set(&"_armed", true)
	assert_true(scythe.cut_rect().intersects(owl.bounds()), "the cut crosses its flight")
	var down := [false]
	owl.defeated.connect(func() -> void: down[0] = true)
	owl.tick(FRAME)
	assert_false(owl.is_alive(), "the blade comes through on the beat: it is cut down")
	assert_true(down[0], "and stays down, like any foe")
	remove_child(owl)


## --- off the stone, and Game handing it over ------------------------------------

func test_off_the_stone_is_one_query_and_every_foe_is_told() -> void:
	var game := await _play(FLOOR)
	var owl := _the_owl(game)
	await wait_physics_frames(10)
	assert_false(Owl.off_the_stone(game.player), "standing on the floor: on the stone")
	assert_false(owl.target_off_stone, "and the owl is told so")
	(game.player.input as ScriptedInput).bits = PlayerInput.BIT_JUMP
	await wait_physics_frames(4)
	assert_true(Owl.off_the_stone(game.player), "in a jump: off it")
	assert_true(owl.target_off_stone, "and every foe hears it from Game, not from the Player")
	(game.player.input as ScriptedInput).bits = 0
	for state: Player.State in [Player.State.HANG, Player.State.CLIMB_UP, Player.State.LADDER]:
		game.player.state = state
		assert_true(Owl.off_the_stone(game.player), "%s is off the stone"
			% Player.State.keys()[state])
	game.player.state = Player.State.IDLE


## --- in play ----------------------------------------------------------------------

func _play(text: String) -> Game:
	var level := AsciiLevel.new()
	level.parse(text)
	assert_eq(level.problems, PackedStringArray(), "%s parses clean" % level.name)
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_source = level
	add_child_autofree(game)
	game.player.input = ScriptedInput.new()
	await wait_physics_frames(2)
	return game


func _the_owl(game: Game) -> Owl:
	for node: Node in game.get_node("Entities").get_children():
		if node is Owl:
			return node as Owl
	return null


## The bible's arithmetic, on the bird: a grab and an immediate mantle take
## HANG_HOLD_TIME and CLIMB_UP_TIME, 20 frames, under the spread's 27. Seen
## first as he takes the ledge, he is on the stone before it can stoop.
func test_a_grab_and_an_immediate_mantle_beat_the_spread() -> void:
	var climb := roundi((Tuning.HANG_HOLD_TIME + Tuning.CLIMB_UP_TIME) / FRAME)
	assert_lt(climb, 27, "20 frames of climb against 27 of spread")
	var owl := _owl()
	owl.target_rect = _body(owl.position + Vector2(-60.0, 70.0))
	owl.target_off_stone = true
	_tick(owl, climb)
	assert_eq(owl.state, Owl.State.SPREAD, "still spreading as he stands up")
	owl.target_off_stone = false
	owl.tick(FRAME)
	assert_eq(owl.state, Owl.State.FOLD, "on the stone: it folds")


## Folding takes it FOLD_TIME, and it does not spread again until it has --
## long enough that a climb begun as it folds is over before a new spread
## can end: in the Sun Well's sump the jump from the shelf takes 28 frames to
## the grab, and the grab and the mantle 20 more.
func test_a_folding_owl_does_not_spread_again_at_once() -> void:
	var climb := 28 + roundi((Tuning.HANG_HOLD_TIME + Tuning.CLIMB_UP_TIME) / FRAME)
	assert_gt(roundi(Owl.FOLD_TIME / FRAME) + 27, climb,
		"the fold and a fresh spread outlast a jump to a ledge and the mantle")
	var owl := _owl()
	owl.target_rect = _body(owl.position + Vector2(-60.0, 70.0))
	owl.target_off_stone = true
	_tick(owl, 10)
	owl.target_off_stone = false
	owl.tick(FRAME)
	assert_eq(owl.state, Owl.State.FOLD)
	owl.target_off_stone = true
	_tick(owl, roundi(Owl.FOLD_TIME / FRAME) - 2)
	assert_eq(owl.state, Owl.State.FOLD, "off the stone again, but it is still folding")
	_tick(owl, 4)
	assert_eq(owl.state, Owl.State.SPREAD, "and spreads once it has folded")


## The stoop met by the move it is for: the prince jumps into it and slashes,
## and the slash's band -- chest to below the feet, out in front -- is where
## the owl is as they close, before its talons reach his body. Played through
## the real referee: the stoop is set going at a point in front of his chest
## at the height of a jump, so the meeting is the slash's and not luck's.
func test_an_air_slash_kills_it() -> void:
	var game := await _play(FLOOR)
	var owl := _the_owl(game)
	var input := game.player.input as ScriptedInput
	await wait_physics_frames(40)
	var chest := game.player.body_rect().get_center() + Vector2(14.0, -22.0)
	var driver := Driver.new()
	driver.think = func(frame: int) -> void:
		if frame == 1:
			owl.aim = chest
			owl.state = Owl.State.STOOP
		input.bits = PlayerInput.BIT_JUMP if frame >= 8 and frame < 20 else 0
		if frame == 11:
			input.bits |= PlayerInput.BIT_ATTACK
	add_child_autofree(driver)
	for _frame: int in 60:
		await wait_physics_frames(1)
		if not owl.is_alive():
			break
	assert_false(owl.is_alive(), "the air slash cut it out of its stoop")
	assert_eq(game.player.health, Tuning.MAX_HEALTH, "before its talons reached him")
