extends GutTest
## The crawl (PrinceCrawl, ReachCrawl; docs/character.md, "The crawl").
##
## The owner, in the Mirror Tower, wanted to get through a gap one tile high
## and could not: the prince crouched only standing still, and a crouch was
## all that fitted. Held here, in the real game scene: down and then the stick
## takes him through on hands and knees and he stands at the far side; a run
## with the stick drifted low is still a run; a wall with no gap stops a crawl
## as it stops a walk; under the ceiling no sword comes out and nothing makes
## him stand. And the proof: it finds the passage, needs it where nothing else
## goes, offers nothing where there is no passage, and -- every chapter, every
## race, every secret -- reaches nothing it did not reach before, and makes no
## race shorter than it was.

const GAME_SCENE := "res://scenes/game.tscn"
const D := PlayerInput.BIT_DOWN
const R := PlayerInput.BIT_RIGHT
const A := PlayerInput.BIT_ATTACK

## A wall to the top of the level with one tile of air under it: the only way
## to the door is through, on hands and knees.
const GAP := """; Gap
       ####
       ####
       ####
       ####
       ####
       ####
 @              D
#################
"""

## The same wall, down to the floor.
const WALL := """; Wall
       ####
       ####
       ####
       ####
       ####
       ####
 @     ####     D
#################
"""

const CHAPTERS := [
	"res://levels/level_01.txt", "res://levels/chapter_02.txt",
	"res://levels/chapter_03.txt", "res://levels/chapter_04.txt",
	"res://levels/chapter_05.txt", "res://levels/chapter_06_eclipse.txt",
]


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func after_each() -> void:
	ReachCrawl.enabled = true


func _play(text: String) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	for _frame: int in 30:
		await wait_physics_frames(1)


func _hold(bits: int, frames: int) -> void:
	_input.bits = bits
	for _frame: int in frames:
		await wait_physics_frames(1)


## Holds `bits` until `done`, or for as long as a crawl the width of the
## level would take.
func _hold_until(bits: int, done: Callable) -> void:
	_input.bits = bits
	for _frame: int in int(17.0 * Tuning.TILE / Tuning.CRAWL_SPEED * 60.0):
		if done.call():
			return
		await wait_physics_frames(1)


## --- the prince -------------------------------------------------------------

func test_down_then_the_stick_crawls_through_a_one_tile_gap() -> void:
	await _play(GAP)
	var wall := 7.0 * Tuning.TILE
	var beyond := 11.0 * Tuning.TILE + Tuning.BODY_WIDTH
	await _hold(D, 4)
	assert_eq(_game.player.state, Player.State.CROUCH, "down first: a crouch")
	await _hold(D | R, 12)
	assert_eq(_game.player.state, Player.State.CRAWL, "then the stick: a crawl")
	assert_almost_eq(absf(_game.player.velocity.x), Tuning.CRAWL_SPEED, 0.5,
		"at the crawl's speed")
	# Under the wall he stays down whatever the stick and the button say.
	await _hold_until(D | R, func() -> bool: return _game.player.position.x > wall + 6.0)
	assert_gt(_game.player.position.x, wall + 6.0, "in under the wall")
	await _hold(R, 4)
	assert_eq(_game.player.state, Player.State.CRAWL, "and still crawling with down let go")
	_input.bits = R | A
	await wait_physics_frames(2)
	assert_ne(_game.player.state, Player.State.ATTACK, "no room under it to swing a sword")
	await _hold_until(R, func() -> bool: return _game.player.position.x > beyond)
	assert_gt(_game.player.position.x, beyond, "out the far side")
	await _hold(0, 6)
	assert_almost_eq(_game.player.body_rect().size.y, Tuning.BODY_HEIGHT, 0.1,
		"and standing once there is room")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "unhurt")


## The spot the owner meant: R5's west wall in the Mirror Tower comes down to
## one tile above the floor, the slot the balcony Glassbearer fires through
## (levels/chapter_04.txt, beat 7). From standing still in R5, down and left
## takes him out onto the balcony, past the foot of R5's ladder, and the way
## back in is the same.
func test_the_mirror_tower_slot_is_crawled_through() -> void:
	await _play(FileAccess.get_file_as_string("res://levels/chapter_04.txt"))
	_game.player.respawn(_game.level.entity_world_position(Vector2i(19, 20)))
	await _hold(0, 10)
	var slot := 16.0 * Tuning.TILE
	await _hold_until(D | PlayerInput.BIT_LEFT,
		func() -> bool: return _game.player.body_rect().end.x < slot)
	assert_lt(_game.player.body_rect().end.x, slot, "out through the slot onto the balcony")
	assert_almost_eq(_game.player.position.y, 21.0 * Tuning.TILE, 0.5, "on its floor")
	await _hold_until(D | R, func() -> bool:
		return _game.player.body_rect().position.x > slot + Tuning.TILE)
	assert_gt(_game.player.body_rect().position.x, slot + Tuning.TILE, "and back in")


func test_a_run_with_the_stick_low_is_still_a_run() -> void:
	await _play(GAP)
	await _hold(R, 20)
	await _hold(D | R, 6)
	assert_ne(_game.player.state, Player.State.CRAWL, "down drifting into a run is no crawl")
	assert_gt(absf(_game.player.velocity.x), Tuning.WALK_SPEED, "he keeps his speed")


func test_no_crawl_where_there_is_no_gap() -> void:
	await _play(WALL)
	var wall := 7.0 * Tuning.TILE
	await _hold(D, 4)
	await _hold(D | R, int(6.0 * Tuning.TILE / Tuning.CRAWL_SPEED * 60.0))
	assert_lt(_game.player.body_rect().end.x, wall + 0.5, "a wall to the floor stops a crawl")


## --- the proof --------------------------------------------------------------

func test_the_proof_crawls_where_nothing_else_goes() -> void:
	var gap := AsciiLevel.new()
	gap.parse(GAP)
	assert_true(bool(LevelReachability.verify(gap)["ok"]), "the door, through the gap")
	ReachCrawl.enabled = false
	assert_false(bool(LevelReachability.verify(gap)["ok"]),
		"and only through it: without the crawl the proof has no way there")


func test_the_proof_crawls_nowhere_there_is_no_passage() -> void:
	var wall := AsciiLevel.new()
	wall.parse(WALL)
	var solver := LevelReachability.Solver.new(wall)
	var passages := 0
	for y: int in wall.rows:
		for x: int in wall.cols:
			if ReachCrawl.is_passage(solver, x, y):
				passages += 1
	assert_eq(passages, 0, "no passage in a wall to the floor")
	assert_false(bool(LevelReachability.verify(wall)["ok"]), "so no way to the door")


func test_the_crawl_reaches_nothing_new_in_any_chapter() -> void:
	for path: String in CHAPTERS:
		var level := AsciiLevel.from_file(path)
		ReachCrawl.enabled = false
		var without := LevelReachability.survey(level)
		ReachCrawl.enabled = true
		var with := LevelReachability.survey(level)
		assert_true(bool(with["ok"]), "%s still proves" % path)
		var fresh: Array[Vector2i] = []
		for cell: Vector2i in (with["reached"] as Dictionary):
			if not (without["reached"] as Dictionary).has(cell):
				fresh.append(cell)
		assert_eq(fresh, [] as Array[Vector2i],
			"%s: the crawl reaches no cell the chapter did not already reach" % path)


func test_no_race_is_shortened_by_the_crawl() -> void:
	var raced := 0
	for path: String in CHAPTERS:
		var level := AsciiLevel.from_file(path)
		ReachCrawl.enabled = false
		var without := ReachRace.measure(level)
		ReachCrawl.enabled = true
		var with := ReachRace.measure(level)
		assert_eq(with.size(), without.size(), "%s: the same races" % path)
		for i: int in mini(with.size(), without.size()):
			raced += 1
			assert_true(bool(with[i]["ok"]), "%s: race %s still fits its slack"
				% [path, with[i]["plate"]])
			assert_eq(float(with[i]["frames"]), float(without[i]["frames"]),
				"%s: race from %s is run in the same frames" % [path, with[i]["plate"]])
	assert_gt(raced, 0, "Chapter II's races were measured")


func test_the_secrets_stay_secret_with_the_crawl() -> void:
	for path: String in CHAPTERS:
		var level := AsciiLevel.from_file(path)
		if level.secrets.is_empty():
			continue
		var audit := LevelReachability.audit_secrets(level)
		assert_true(bool(audit["ok"]), "%s: %s" % [path, audit.get("reason", "")])
