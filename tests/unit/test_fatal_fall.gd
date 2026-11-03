extends GutTest
## A fall of ten tiles or more kills (Tuning.FATAL_FALL_TILES): the owner's
## rule, played in the real game scene, proved by the reachability search and
## kept out of every Endless ruin.
##
## The deaths here are meant, and each test that has one says so to the death
## watch (tests/death_watch.gd) with its exact count -- the checkpoint respawn
## would otherwise bring the prince back whole and hide them, and a test that
## means a survival is failed by the watch if he dies.
##
## Each claim was seen to fail by breaking what it guards: the threshold moved
## a tile, the apex reset taken out of the hang and the ladder, the solver's
## prune removed, and the generator's drops deepened.

const DeathWatch := preload("res://tests/death_watch.gd")
const GAME_SCENE := "res://scenes/game.tscn"
const PLAYER_SCENE := preload("res://scenes/player.tscn")

## The deepest drop a level may ask for: docs/campaign.md, "No blind jumps".
const MAX_INTENDED_DROP := 5
## Headroom over the ledge, so a full jump's head never meets the sky's edge.
const LEDGE_ROW := 4
const WIDTH := 14


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput
## Every landing on this run: `{height, impact, dead}`, read on the frame of
## the landing, before the next frame moves the top of the fall.
var _landings: Array[Dictionary] = []
var _hung := false


## --- levels -------------------------------------------------------------------

## A cliff `drop` tiles high. The prince spawns on a ledge three columns wide
## at the left; the floor runs the whole width `drop` rows below it.
static func _cliff(drop: int) -> String:
	var floor_row := LEDGE_ROW + drop
	var lines := PackedStringArray(["; Cliff %d" % drop])
	for row: int in floor_row + 2:
		var line := ""
		for col: int in WIDTH:
			var cell := " "
			if row >= floor_row or (row >= LEDGE_ROW and col <= 2):
				cell = "#"
			elif row == LEDGE_ROW - 1 and col == 1:
				cell = "@"
			elif row == floor_row - 1 and col == WIDTH - 2:
				cell = "D"
			line += cell
		lines.append(line)
	return "\n".join(lines) + "\n"


## Twelve tiles down a shaft at column 3, with a notch in the shaft's right
## wall: a slot one row high, two rows under the ledge, whose floor is a lip
## the hands find on the way down. Hanging from it, the rest of the shaft is
## nine tiles.
static func _notched_shaft() -> String:
	var floor_row := LEDGE_ROW + 12
	var notch := LEDGE_ROW + 1
	var lines := PackedStringArray(["; Notched shaft"])
	for row: int in floor_row + 2:
		var line := ""
		for col: int in WIDTH:
			var cell := " "
			if row >= floor_row:
				cell = "#"
			elif col <= 2 and row >= LEDGE_ROW:
				cell = "#"
			elif col >= 4 and row != notch:
				cell = "#"
			elif row == LEDGE_ROW - 1 and col == 1:
				cell = "@"
			elif row == notch and col == WIDTH - 2:
				# Out of reach at the notch's far end: a door in the shaft
				# would end the level before the landing it is here to see.
				cell = "D"
			line += cell
		lines.append(line)
	return "\n".join(lines) + "\n"


## A ladder from the ledge's lip eight rungs down a twelve-tile well, so its
## foot hangs four tiles over the floor: climbing off the bottom is a fall
## of four tiles, after eight of ladder.
static func _ladder_well() -> String:
	var floor_row := LEDGE_ROW + 12
	var lines := PackedStringArray(["; Ladder well"])
	for row: int in floor_row + 2:
		var line := ""
		for col: int in WIDTH:
			var cell := " "
			if row >= floor_row or (row >= LEDGE_ROW and col <= 2):
				cell = "#"
			elif col == 3 and row >= LEDGE_ROW - 1 and row < LEDGE_ROW + 8:
				cell = "H"
			elif row == LEDGE_ROW - 1 and col == 2:
				cell = "@"
			elif row == floor_row - 1 and col == WIDTH - 2:
				cell = "D"
			line += cell
		lines.append(line)
	return "\n".join(lines) + "\n"


## --- the scene ----------------------------------------------------------------

func _play(text: String) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	_landings.clear()
	_hung = false
	_game.player.landed.connect(_on_landed)
	_game.player.grabbed_ledge.connect(func() -> void: _hung = true)
	await wait_physics_frames(4)


func _on_landed(impact: float) -> void:
	_landings.append({
		"height": _game.player.fall_height(),
		"impact": impact,
		"dead": not _game.player.is_alive(),
		"fallen": _game.player.is_fallen(),
	})


## Holds `bits` until a landing from at least `min_height` px, or `frames` run
## out. The landing, or an empty dictionary.
func _until_landing(bits: int, min_height: float, frames: int = 180) -> Dictionary:
	_input.bits = bits
	for _frame: int in frames:
		await wait_physics_frames(1)
		for landing: Dictionary in _landings:
			if float(landing["height"]) >= min_height:
				return landing
	return {}


func _deepest() -> float:
	var deepest := 0.0
	for landing: Dictionary in _landings:
		deepest = maxf(deepest, float(landing["height"]))
	return deepest


## --- the number -----------------------------------------------------------------

func test_the_rule_is_a_height_because_speed_cannot_tell() -> void:
	assert_eq(Tuning.fatal_fall_height(), 160.0, "ten tiles of sixteen")
	assert_lt(Tuning.terminal_fall_height(), Tuning.fatal_fall_height(),
		"a fall reaches MAX_FALL_SPEED long before ten tiles")
	assert_eq(Tuning.land_speed_after_drop(MAX_INTENDED_DROP), Tuning.land_speed_after_drop(10),
		"so the deepest intended drop and a fatal one land at the same speed")
	assert_false(Tuning.is_fatal_fall(9.0 * Tuning.TILE), "nine tiles is not ten")
	assert_true(Tuning.is_fatal_fall(10.0 * Tuning.TILE - 0.1), "ten is, to within the margin")


func test_a_full_jump_off_any_intended_drop_is_survived() -> void:
	gut.p("safe jump drop: %d tiles; terminal speed after %.1f px"
		% [Tuning.safe_jump_drop_tiles(), Tuning.terminal_fall_height()])
	assert_gte(Tuning.safe_jump_drop_tiles(), MAX_INTENDED_DROP,
		"the jump's own rise never turns a drop a level asks for into a death")
	assert_lt(Tuning.safe_jump_drop_tiles(), Tuning.FATAL_FALL_TILES - 1,
		"and the rise does count: a jump survives less than a walk off the edge")


## --- the player ----------------------------------------------------------------

func test_a_walk_off_nine_tiles_is_survived() -> void:
	await _play(_cliff(9))
	var landing := await _until_landing(PlayerInput.BIT_RIGHT, 8.0 * Tuning.TILE)
	assert_false(landing.is_empty(), "he landed at the foot of the cliff")
	assert_almost_eq(float(landing.get("height", 0.0)), 9.0 * Tuning.TILE, 1.0, "nine tiles")
	assert_eq(float(landing.get("impact", 0.0)), Tuning.MAX_FALL_SPEED, "at terminal speed")
	assert_true(_game.player.is_alive(), "and walked away from it")
	assert_eq(_game.deaths, 0)


func test_a_walk_off_ten_tiles_kills_and_respawns_at_the_checkpoint() -> void:
	DeathWatch.expect_deaths(1)
	await _play(_cliff(10))
	var spawn := _game.level.spawn_world_position()
	var landing := await _until_landing(PlayerInput.BIT_RIGHT, 9.0 * Tuning.TILE)
	assert_almost_eq(float(landing.get("height", 0.0)), 10.0 * Tuning.TILE, 1.0, "ten tiles")
	assert_eq(float(landing.get("impact", 0.0)), Tuning.MAX_FALL_SPEED,
		"at the very speed nine tiles landed at: the height killed him, not the speed")
	assert_true(bool(landing.get("dead", false)), "the landing was the death")
	assert_true(bool(landing.get("fallen", false)), "and a fall's, laid out as one")
	assert_eq(_game.deaths, 1, "the game counted it")
	assert_eq(_game.phase, Game.Phase.DYING, "and holds the death beat")
	_input.bits = 0
	for _frame: int in 90:
		await wait_physics_frames(1)
		if _game.phase == Game.Phase.PLAYING and _game.player.is_alive():
			break
	assert_true(_game.player.is_alive(), "the ordinary death flow brought him back")
	assert_almost_eq(_game.player.position.x, spawn.x, 1.0, "at the checkpoint")
	assert_false(_game.player.is_fallen(), "standing")


func test_the_fall_is_measured_from_the_apex_of_a_jump() -> void:
	var safe := Tuning.safe_jump_drop_tiles()
	await _play(_cliff(safe))
	var jump := PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP
	var landing := await _until_landing(jump, float(safe - 1) * Tuning.TILE)
	assert_gt(float(landing.get("height", 0.0)), float(safe) * Tuning.TILE + Tuning.TILE,
		"a jump off %d tiles falls further than %d: the rise counts" % [safe, safe])
	assert_true(_game.player.is_alive(), "and is survived")


func test_a_jump_off_one_tile_deeper_kills() -> void:
	DeathWatch.expect_deaths(1)
	var drop := Tuning.safe_jump_drop_tiles() + 1
	await _play(_cliff(drop))
	var jump := PlayerInput.BIT_RIGHT | PlayerInput.BIT_JUMP
	var landing := await _until_landing(jump, float(drop - 1) * Tuning.TILE)
	assert_lt(float(drop) * Tuning.TILE, Tuning.fatal_fall_height(),
		"the ledge is under ten tiles")
	assert_true(bool(landing.get("dead", false)),
		"but the jump peaked high enough over it that the landing killed")


func test_a_ledge_grab_catches_a_fall() -> void:
	await _play(_notched_shaft())
	# Into the shaft, hands toward its wall: the notch catches him.
	_input.bits = PlayerInput.BIT_RIGHT
	for _frame: int in 90:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.HANG:
			break
	assert_true(_hung, "the hands found the notch on the way down")
	await wait_physics_frames(6)
	# Let go: down, and nothing toward the wall, so the hands stay off it.
	var landing := await _until_landing(PlayerInput.BIT_DOWN, 4.0 * Tuning.TILE)
	assert_false(landing.is_empty(), "he dropped from the hang to the floor")
	var total := _game.player.position.y - _game.level.spawn_world_position().y
	assert_gte(total, 11.0 * Tuning.TILE, "eleven tiles and more from the ledge to the floor")
	assert_lt(_deepest(), Tuning.fatal_fall_height(), "but no one fall was ten")
	assert_true(_game.player.is_alive(), "so the grab saved him")


func test_a_ladder_is_not_a_fall() -> void:
	await _play(_ladder_well())
	var top := _game.player.position.y
	_input.bits = PlayerInput.BIT_RIGHT | PlayerInput.BIT_DOWN
	for _frame: int in 20:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.LADDER:
			break
	assert_eq(_game.player.state, Player.State.LADDER, "on the rungs")
	# Shuffle over until the body is clear of the ledge it stepped off, which
	# would otherwise hold it up, then straight down and off the bottom.
	for _frame: int in 40:
		await wait_physics_frames(1)
		if _game.player.position.x >= 3.0 * Tuning.TILE + Tuning.BODY_WIDTH * 0.5 + 1.0:
			break
	var landing := await _until_landing(PlayerInput.BIT_DOWN, Tuning.TILE, 300)
	assert_false(landing.is_empty(), "he climbed off the ladder's foot and landed")
	assert_gte(_game.player.position.y - top, 11.5 * Tuning.TILE, "twelve tiles down in all")
	assert_lt(float(landing.get("height", 0.0)), 4.0 * Tuning.TILE,
		"but the fall was only from the ladder's foot")
	assert_true(_game.player.is_alive(), "on his feet at the bottom")


func test_a_plunge_is_a_fall() -> void:
	DeathWatch.expect_deaths(1)
	await _play(_cliff(10))
	_input.bits = PlayerInput.BIT_RIGHT
	for _frame: int in 60:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.FALL:
			break
	var landing := await _until_landing(PlayerInput.BIT_DOWN | PlayerInput.BIT_ATTACK,
		9.0 * Tuning.TILE)
	assert_true(bool(landing.get("dead", false)), "the point under the feet saves nothing")


func test_a_plunge_from_nine_tiles_bites_the_stone() -> void:
	await _play(_cliff(9))
	_input.bits = PlayerInput.BIT_RIGHT
	for _frame: int in 60:
		await wait_physics_frames(1)
		if _game.player.state == Player.State.FALL:
			break
	await _until_landing(PlayerInput.BIT_DOWN | PlayerInput.BIT_ATTACK, 8.0 * Tuning.TILE)
	assert_eq(_game.player.state, Player.State.PLUNGE_LAND, "the plunge landed as a plunge")
	assert_true(_game.player.is_alive())


func test_a_death_from_a_fall_draws_as_both_figures() -> void:
	for figure: String in ["prince", "heroine"]:
		var player := PLAYER_SCENE.instantiate() as Player
		add_child_autofree(player)
		player.set_physics_process(false)
		player.position = Vector2(160.0, 120.0)
		var art := player.get_node(^"PlayerArt") as PlayerArt
		var look := CharacterLook.new()
		look.take_ids({"figure": figure})
		look.dress(art)
		player.state = Player.State.DEAD
		player.state_time = 0.5
		# Nothing public raises the flag but the landing; read it back, since
		# Object.set() on a wrong name drops the value in silence.
		player.set("_fell", true)
		assert_true(player.is_fallen(), "%s is posed as fallen" % figure)
		var before := art.costume.frames_drawn
		art.queue_redraw()
		await wait_process_frames(2)
		assert_gt(art.costume.frames_drawn, before, "%s's fall drew" % figure)


## --- the proof ------------------------------------------------------------------

## The proof reaches a lower floor by jumping down to it: its walk-off arc
## lands back on the lip it walked off (the body is still half over it on
## the first falling frame), so a jump is the only way down it knows. A jump
## off safe_jump_drop_tiles() falls under ten tiles from its apex; one tile
## deeper it falls over ten. The proof before the rule went down both.
func test_the_proof_prunes_a_ten_tile_landing() -> void:
	var safe := Tuning.safe_jump_drop_tiles()
	for drop: int in [safe, safe + 1, Tuning.FATAL_FALL_TILES]:
		var level := AsciiLevel.new()
		level.parse(_cliff(drop))
		var report := LevelReachability.verify(level)
		assert_eq(bool(report["ok"]), drop <= safe,
			"the door at the foot of a %d-tile cliff: %s" % [drop, String(report["reason"])])


func test_the_masked_search_prunes_it_too() -> void:
	var safe := Tuning.safe_jump_drop_tiles()
	for drop: int in [safe, safe + 1]:
		var level := AsciiLevel.new()
		level.parse(_cliff(drop))
		# A wire that changes nothing but sends the search down ReachSearch.
		var model := ReachModel.new()
		model.switch_cells([Vector2i(WIDTH - 1, 0)] as Array[Vector2i], &"idle",
			Tiles.Kind.EMPTY, Tiles.Kind.EMPTY)
		assert_false(model.is_empty(), "the masked path is taken")
		var solver := LevelReachability.Solver.new(level, model)
		var door := Vector2i(WIDTH - 2, LEDGE_ROW + drop - 1)
		var goals: Array[Vector2i] = [door, door + Vector2i.UP]
		var report := ReachSearch.search(solver, level.spawn_point, goals, {})
		assert_eq(bool(report["ok"]), drop <= safe,
			"masked, a %d-tile cliff: %s" % [drop, String(report["reason"])])


## --- Endless ---------------------------------------------------------------------

func test_the_generator_never_needs_a_deep_fall() -> void:
	var built := 0
	for index: int in 40:
		var seed_value := 7919 * (index + 1)
		var difficulty := 0.1 + 0.85 * float(index % 10) / 9.0
		var result := LevelGenerator.build(seed_value, 170, difficulty)
		assert_true(bool(result["ok"]), "seed %d builds" % seed_value)
		if not bool(result["ok"]):
			continue
		built += 1
		var level := result["level"] as AsciiLevel
		assert_true(bool(LevelReachability.verify(level)["ok"]),
			"seed %d is proved without a landing from ten tiles" % seed_value)
		for beat: Dictionary in result["beats"]:
			var params: Dictionary = beat["params"]
			var descent := int(beat["entry"]) - int(beat["exit"])
			assert_lte(descent, MAX_INTENDED_DROP,
				"seed %d: a %s steps down no more than five" % [seed_value, beat["id"]])
			assert_lte(int(params.get("depth", 0)), MAX_INTENDED_DROP,
				"seed %d: a %s is no deeper than five" % [seed_value, beat["id"]])
	assert_eq(built, 40, "every seed built")
