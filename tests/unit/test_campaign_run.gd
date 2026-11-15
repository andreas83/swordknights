extends GutTest
## The Last Light played end to end, as a player would: the real CampaignGame
## from Chapter I through the Eclipse to the dawn and back to the chapter
## select, each chapter played by its own frozen clear run, under the death
## watch, with JUMP pressed on every complete screen.
##
## Each chapter's own test proves it plays on its own. What only a run of the
## whole campaign can show is the thread between them -- that every chapter
## opens the next, that the clear is saved the moment it happens, that every
## chapter opens on its own card, that the last door leads to the dawn and the
## dawn to the chapter select -- and how the campaign adds up: how long it
## takes, and where its threats and its new ideas fall. Those numbers are
## printed (gut.p) for docs/campaign.md's curve; the assertions hold the
## thread.
##
## Each program is the chapter's own, read from the test that froze it, so a
## re-recorded run is played here too. They are open-loop and frame-exact, and
## each starts on its chapter's first physics frame, exactly as in its own
## test; the Eclipse's counts the prince's polls (tests/eclipse_support.gd).
## The run is played ten times faster than the wall clock with every step
## still 1/60 s of simulation, as tests/unit/test_chapter_04.gd plays its own.

const EclipseSupport := preload("res://tests/eclipse_support.gd")
const SunTerrace := preload("res://tests/unit/test_sun_terrace_clear.gd")
const LongArcade := preload("res://tests/unit/test_chapter_02.gd")
const Aqueduct := preload("res://tests/unit/test_aqueduct_clear.gd")
const MirrorTower := preload("res://tests/unit/test_chapter_04.gd")
const SunWell := preload("res://tests/unit/test_sun_well.gd")

const SCENE := "res://scenes/campaign_game.tscn"
const SELECT := "res://scenes/chapter_select.tscn"
const FAST := 10
## The entries whose own clear runs are held to finishing without a scratch:
## played inside the campaign, faster than the wall clock, they must still.
const UNSCRATCHED: Array[String] = ["sun_terrace", "aqueduct", "sun_well"]
## The longest any entry may take, in physics frames, before the run gives up.
const ENTRY_LIMIT := 60 * 240


class ProgramInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _progress := UserData.at("user://test_campaign_run.cfg")
var _campaign: CampaignGame
var _left := 0
var _ticks := 0
var _saved_ticks := 0
var _saved_scale := 1.0
var _saved_steps := 0

## The entry being driven, and its program.
var _game: Game
var _input := ProgramInput.new()
var _steps: Array = []
var _step := 0
var _hold := 0
## Per entry: what the run saw.
var _seen: Array[Dictionary] = []
## Threats live last frame, by instance id, so each is counted once as it opens.
var _live: Dictionary = {}
var _shots: Dictionary = {}


func before_all() -> void:
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_scale = Engine.time_scale
	_saved_steps = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.time_scale = _saved_scale
	Engine.max_physics_steps_per_frame = _saved_steps
	Campaign.reset()
	Assist.reset()
	if FileAccess.file_exists(_progress):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_progress))


## Each entry's clear run, in order. The Eclipse's is played by poll.
func _programs() -> Array:
	return [
		SunTerrace.CLEAR_RUN, LongArcade.CLEAR_RUN, Aqueduct.RUN,
		_parse(MirrorTower.RUN), SunWell.CLEAR_RUN, EclipseSupport.CLEAR_RUN,
	]


## tests/unit/test_chapter_04.gd's `frames:buttons` text as `[frames, bits]`.
static func _parse(text: String) -> Array:
	var letters := {"L": PlayerInput.BIT_LEFT, "R": PlayerInput.BIT_RIGHT,
		"U": PlayerInput.BIT_UP, "D": PlayerInput.BIT_DOWN, "J": PlayerInput.BIT_JUMP,
		"A": PlayerInput.BIT_ATTACK}
	var out: Array = []
	for word: String in text.replace("\n", " ").split(" ", false):
		var pair := word.split(":")
		var bits := 0
		for letter: String in pair[1]:
			bits |= int(letters.get(letter, 0))
		out.append([int(pair[0]), bits])
	return out


## Every physics frame, before anything moves: a new entry's game is taken
## over on its first frame, a frame-program steps, and the threats are read.
func _on_tick() -> void:
	_ticks += 1
	var game := _campaign.game() if is_instance_valid(_campaign) else null
	if game == null:
		return
	if game != _game:
		_take(game)
	if _game.phase != Game.Phase.PLAYING:
		_input.bits = 0
		return
	if _game.player.input == _input:
		while _hold <= 0 and _step < _steps.size():
			_hold = int(_steps[_step][0])
			_input.bits = int(_steps[_step][1])
			_step += 1
		if _hold > 0:
			_hold -= 1
		else:
			_input.bits = 0
	_read_threats()


## A new entry: its program in the prince's hands, and a record begun.
func _take(game: Game) -> void:
	_game = game
	var index := _campaign.index
	var programs := _programs()
	_step = 0
	_hold = 0
	_steps = []
	_input = ProgramInput.new()
	if index == programs.size() - 1:
		_game.player.input = EclipseSupport.Program.new(programs[index])
	else:
		_steps = programs[index]
		_game.player.input = _input
	_live.clear()
	_seen.append({
		"index": index, "card": _game.hud.card(), "card_up": _game.hud.title_showing(),
		"label": _game.advance_label, "threats": 0, "shots": 0, "lowest": Tuning.MAX_HEALTH,
		"kinds": _kinds(_game.level.data),
	})


## The threats that opened this frame where the camera shows them: a foe's
## live window (each told Patrol.WINDUP_TIME ahead, by the foe contract), a
## blade's cut, and every shot loosed.
func _read_threats() -> void:
	var record: Dictionary = _seen[-1]
	record["lowest"] = mini(int(record["lowest"]), _game.player.health)
	var view := _view()
	var live := {}
	for node: Node in get_tree().get_nodes_in_group(Foe.GROUP):
		var foe := node as Foe
		if foe != null and foe.is_alive() and foe.is_dangerous() \
				and view.intersects(foe.bounds()):
			live[foe.get_instance_id()] = true
	for node: Node in get_tree().get_nodes_in_group(BeatBlade.GROUP):
		var blade := node as BeatBlade
		if blade != null and blade.is_live() and view.intersects(blade.cut_rect()):
			live[blade.get_instance_id()] = true
	for id: int in live:
		if not _live.has(id):
			record["threats"] = int(record["threats"]) + 1
	_live = live
	for node: Node in _game.get_node("Entities").get_children():
		if node is FoeProjectile and not _shots.has(node.get_instance_id()):
			_shots[node.get_instance_id()] = true
			record["shots"] = int(record["shots"]) + 1


## The frame as play reads it (CameraView): the camera's zoom taken out of the
## viewport's size, so a threat is counted only once it is really on screen.
func _view() -> Rect2:
	return CameraView.rect_for(_game.player)


## What a level is built from: its mechanisms and its foes, by kind.
static func _kinds(level: AsciiLevel) -> PackedStringArray:
	var out := PackedStringArray()
	for cell: Vector2i in level.mechanism_glyphs:
		var kind := Tiles.mechanism_kind(String(level.mechanism_glyphs[cell]))
		if kind != "" and not out.has(kind):
			out.append(kind)
	for mark: Dictionary in level.entities:
		var kind := String(mark["kind"])
		if not out.has(kind):
			out.append(kind)
	out.sort()
	return out


## JUMP on the complete screen, the way a thumb gives it, until the campaign
## has moved on from `from`.
func _press_on(from: Game) -> void:
	for _try: int in 40:
		Input.action_press("jump")
		await wait_physics_frames(2)
		Input.action_release("jump")
		await wait_physics_frames(6)
		if _campaign.game() != from:
			return


func test_the_last_light_from_the_first_terrace_to_the_dawn() -> void:
	Engine.max_physics_steps_per_frame = 8 * FAST
	Engine.physics_ticks_per_second = 60 * FAST
	Engine.time_scale = float(FAST)
	Campaign.reset()
	Campaign.selected = 0
	_campaign = (load(SCENE) as PackedScene).instantiate() as CampaignGame
	_campaign.progress_path = _progress
	_campaign.leave = func() -> void: _left += 1
	get_tree().physics_frame.connect(_on_tick)
	add_child_autofree(_campaign)

	var clocks: Array[float] = []
	var deaths: Array[int] = []
	var started := _ticks
	for index: int in Campaign.count():
		var limit := _ticks + ENTRY_LIMIT
		while (_game == null or _game.phase != Game.Phase.COMPLETE) and _ticks < limit:
			await wait_physics_frames(10)
		var entry := Campaign.entry(index)
		assert_eq(_campaign.index, index, "playing entry %d" % index)
		assert_eq(_game.phase, Game.Phase.COMPLETE, "%s: the door was reached" % entry["title"])
		if _game.phase != Game.Phase.COMPLETE:
			break
		clocks.append(_game.elapsed)
		deaths.append(_game.deaths)
		assert_eq(_game.deaths, 0, "%s: with no death" % entry["title"])
		if UNSCRATCHED.has(String(entry["id"])):
			assert_eq(int(_seen[-1]["lowest"]), Tuning.MAX_HEALTH,
				"%s: and without a scratch, as in its own test" % entry["title"])
		var saved := CampaignProgress.open(_progress)
		assert_true(saved.is_cleared(String(entry["id"])), "%s: the clear saved" % entry["title"])
		assert_almost_eq(float(saved.record_of(String(entry["id"]))["best_time"]),
			_game.elapsed, 0.01, "with its time")
		if index + 1 < Campaign.count():
			assert_true(saved.is_unlocked(index + 1), "%s: opens the next" % entry["title"])
		await _press_on(_game)

	get_tree().physics_frame.disconnect(_on_tick)
	var played := _ticks - started

	# Every chapter opened on its own card and offered the next.
	assert_eq(_seen.size(), Campaign.count(), "every entry was played")
	for record: Dictionary in _seen:
		var index := int(record["index"])
		var card: Dictionary = record["card"]
		assert_eq(String(card["title"]), String(Campaign.card(index)["title"]).to_upper(),
			"entry %d opened on its card" % index)
		assert_eq(String(card["epigraph"]), String(Campaign.card(index)["epigraph"]).to_upper(),
			"with its epigraph")
		assert_true(bool(record["card_up"]), "the card was up as the chapter began")
		var expected := "CONTINUE" if index + 1 < Campaign.count() else "DAWN"
		assert_eq(String(record["label"]), expected, "and its door said JUMP TO %s" % expected)

	# The dawn, and from it the chapter select.
	var dawn := _campaign.dawn()
	assert_not_null(dawn, "the last door led to the dawn")
	if dawn != null:
		await wait_physics_frames(roundi((EndingCard.HOLD + 0.5) * 60.0))
		Input.action_press("jump")
		await wait_physics_frames(3)
		Input.action_release("jump")
		await wait_physics_frames(3)
	assert_eq(_left, 1, "and the dawn went back to the chapter select")
	var page := (load(SELECT) as PackedScene).instantiate() as ChapterSelect
	page.store_path = _progress
	add_child_autofree(page)
	await wait_physics_frames(2)
	for row: int in page.rows().size():
		assert_true(page.is_open(row), "the chapter select opens row %d" % row)
		if not bool(page.rows()[row]["continue"]):
			assert_true(page.row_value(row).contains(":"),
				"%s shows its best time" % page.row_title(row))

	_report(clocks, deaths, played)
	_hold_to_the_bible(clocks)


## docs/campaign.md, "The campaign, played": each entry's par is its own
## test's, and its clear run is what this run measured. A run that moves
## without the table moving with it fails here, so the bible's numbers are
## always the game's.
func _hold_to_the_bible(clocks: Array[float]) -> void:
	var pars := [SunTerrace.PAR, LongArcade.PAR, Aqueduct.PAR, MirrorTower.PAR, SunWell.PAR]
	var row := RegEx.create_from_string(
		"^\\| [^|]* \\| ([^|]+) \\| [^|]+ \\| (\\d+):(\\d\\d) \\| ([0-9.]+) s \\|")
	var table := {}
	for line: String in FileAccess.get_file_as_string("res://docs/campaign.md").split("\n"):
		var hit := row.search(line)
		if hit != null:
			table[hit.get_string(1).strip_edges()] = [
				int(hit.get_string(2)) * 60 + int(hit.get_string(3)), float(hit.get_string(4))]
	for at: int in clocks.size():
		var title := String(Campaign.entry(at)["title"])
		assert_true(table.has(title), "%s has a row in the bible's campaign table" % title)
		if not table.has(title):
			continue
		var recorded: Array = table[title]
		if at < pars.size():
			assert_eq(float(recorded[0]), float(pars[at]), "%s: the bible's par is its test's" % title)
		assert_lt(clocks[at], float(recorded[0]), "%s: cleared inside the bible's par" % title)
		assert_almost_eq(clocks[at], float(recorded[1]), 0.05,
			"%s: the clear run the bible records" % title)


## The campaign's numbers, for docs/campaign.md's curve.
func _report(clocks: Array[float], deaths: Array[int], played: int) -> void:
	var total := 0.0
	var before := PackedStringArray()
	gut.p("entry | clock | deaths | hearts lost | threats on screen | shots | new")
	for at: int in clocks.size():
		var record: Dictionary = _seen[at]
		var fresh := PackedStringArray()
		for kind: String in record["kinds"]:
			if not before.has(kind):
				fresh.append(kind)
		before.append_array(fresh)
		total += clocks[at]
		gut.p("%s | %.2f s | %d | %d | %d | %d | %s" % [
			String(Campaign.entry(at)["title"]), clocks[at], deaths[at],
			Tuning.MAX_HEALTH - int(record["lowest"]), int(record["threats"]),
			int(record["shots"]), ", ".join(fresh)])
	gut.p("the campaign: %.2f s on the game's clocks, %.2f s of play from the first frame"
		% [total, float(played) / 60.0] + " to the last door, cards and screens included")
