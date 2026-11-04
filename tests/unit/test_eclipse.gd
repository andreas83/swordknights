extends GutTest
## The Eclipse's numbers and rules, stepped frame by frame with no scene
## (scripts/entities/eclipse.gd): the arena he reads from the level, the length
## of every tell with the assist off and on, phase 2's volleys against the
## parry's cycle, and which blow each phase opens him to.
##
## The fight itself -- the real referee, real inputs, a death -- is played in
## tests/unit/test_eclipse_lessons.gd, tests/unit/test_eclipse_persistence.gd
## and tests/unit/test_eclipse_clear_run.gd.

const FRAME := 1.0 / 60.0
const LEVEL := "res://levels/chapter_06_eclipse.txt"
var _assist_path := UserData.at("user://test_eclipse_assist.cfg")
const ARENA := {
	"floor_y": 240.0, "west_x": 96.0, "east_x": 512.0,
	"west_lip": 176.0, "east_lip": 432.0, "gallery_y": 176.0,
}

var _shots: Array[FoeProjectile] = []


func before_each() -> void:
	Assist.reset()
	_shots.clear()


func after_each() -> void:
	Assist.reset()
	for shot: FoeProjectile in _shots:
		if is_instance_valid(shot):
			shot.free()
	_shots.clear()
	if FileAccess.file_exists(_assist_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_assist_path))


## A King in `phase`, standing under the sun of a hand-set arena, and woken by
## a prince on his floor `gap` pixels in front of his west side.
func _king(phase: int, gap: float) -> Eclipse:
	var king: Eclipse = autofree(Eclipse.new())
	king.sun_x = 296.0
	king.set_arena(ARENA)
	king.launched.connect(func(shot: FoeProjectile) -> void: _shots.append(shot))
	king.resume(phase)
	_stand(king, king.position.x - Eclipse.BODY.x * 0.5 - gap - Tuning.BODY_WIDTH * 0.5)
	return king


func _stand(king: Eclipse, x: float) -> void:
	king.target_rect = Rect2(x - Tuning.BODY_WIDTH * 0.5, king.floor_y - Tuning.BODY_HEIGHT,
		Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT)


## Steps until `state` begins, then counts the frames it lasts.
func _frames_in(king: Eclipse, state: Eclipse.State, limit := 900) -> int:
	var frames := 0
	for _frame: int in limit:
		king.tick(FRAME)
		if king.state == state:
			frames += 1
		elif frames > 0:
			return frames
	return frames


func test_the_arena_is_read_from_the_level() -> void:
	var data := AsciiLevel.from_file(LEVEL)
	var king := Vector2i(-1, -1)
	var sun := Vector2i(-1, -1)
	for mark: Dictionary in data.entities:
		match String(mark["kind"]):
			"eclipse":
				king = mark["cell"]
			"kept_sun":
				sun = mark["cell"]
	assert_ne(king, Vector2i(-1, -1), "the King is posted")
	assert_eq(sun.x, king.x, "under the kept sun, which hangs over his post")
	var arena := Eclipse.arena_of(data, king)
	assert_eq(arena, ARENA, "walls, lips and galleries as the level draws them")
	var tile := float(Level.TILE)
	assert_eq((float(arena["east_x"]) - float(arena["west_x"])) / tile, 26.0,
		"a floor 26 tiles wide (docs/campaign.md)")
	assert_eq((float(arena["west_lip"]) - float(arena["west_x"])) / tile, 5.0,
		"a gallery five tiles long at the west end")
	assert_eq((float(arena["east_x"]) - float(arena["east_lip"])) / tile, 5.0, "and the east")
	assert_eq(int((float(arena["floor_y"]) - float(arena["gallery_y"])) / tile),
		Tuning.grab_tiles(), "as high as a grab: plunged from, and climbed back onto")


func test_every_tell_is_the_standard_one_and_the_last_twice_it() -> void:
	var standard := roundi(Patrol.WINDUP_TIME / FRAME)
	assert_eq(standard, 27, "the game's word for 'now'")
	assert_eq(_frames_in(_king(Eclipse.Phase.SHIELD, 4.0), Eclipse.State.DRAW), standard,
		"the shove's draw")
	assert_eq(_frames_in(_king(Eclipse.Phase.BURNING, 100.0), Eclipse.State.CHARGE), standard,
		"a bolt's charge")
	assert_eq(_frames_in(_king(Eclipse.Phase.ECLIPSE, 30.0), Eclipse.State.CROUCH), standard,
		"the crouch before a pounce")
	assert_eq(_frames_in(_king(Eclipse.Phase.FINALE, 100.0), Eclipse.State.GATHER),
		standard * 2, "the gather: twice the standard tell, the only one that long")


func test_the_assist_stretches_every_tell_and_nothing_else() -> void:
	Assist.load_saved(_assist_path)
	Assist.set_longer_warnings(true)
	var longer := roundi(Patrol.WINDUP_TIME * Assist.LONGER / FRAME)
	assert_almost_eq(_frames_in(_king(Eclipse.Phase.SHIELD, 4.0), Eclipse.State.DRAW),
		longer, 1, "the draw")
	assert_almost_eq(_frames_in(_king(Eclipse.Phase.BURNING, 100.0), Eclipse.State.CHARGE),
		longer, 1, "the charge")
	assert_almost_eq(_frames_in(_king(Eclipse.Phase.ECLIPSE, 30.0), Eclipse.State.CROUCH),
		longer, 1, "the crouch")
	assert_almost_eq(_frames_in(_king(Eclipse.Phase.FINALE, 100.0), Eclipse.State.GATHER),
		longer * 2, 1, "the gather")
	assert_almost_eq(_frames_in(_king(Eclipse.Phase.SHIELD, 4.0), Eclipse.State.SHOVE),
		roundi(Patrol.STRIKE_TIME / FRAME), 1, "but the shove itself keeps its own timing")


## Bolt to bolt is the parry's whole cycle, its window and six frames: a press
## that would have been a riposte has ended before the next bolt needs a fresh
## parry (Player._update_parry()). Under the assist only the charge stretches.
func test_bolts_come_a_fresh_parry_apart() -> void:
	var cycle := roundi((Tuning.PARRY_TIME + Tuning.PARRY_ACTIVE) / FRAME) + 6
	assert_eq(roundi(Eclipse.BOLT_SPACING / FRAME), cycle, "42 frames, by the bible's sum")
	for assisted: bool in [false, true]:
		if assisted:
			Assist.load_saved(_assist_path)
			Assist.set_longer_warnings(true)
		var king := _king(Eclipse.Phase.BURNING, 100.0)
		var at: Array[int] = []
		for frame: int in 600:
			var before := _shots.size()
			king.tick(FRAME)
			if _shots.size() > before:
				at.append(frame)
			if at.size() == Eclipse.BOLTS:
				break
		assert_eq(at.size(), Eclipse.BOLTS, "a volley of three")
		for i: int in range(1, at.size()):
			assert_gte(at[i] - at[i - 1], cycle, "each a fresh parry after the last")
		if not assisted:
			assert_eq(at[1] - at[0], cycle, "and exactly that, unassisted")


func test_each_volley_is_faster_than_the_last() -> void:
	var king := _king(Eclipse.Phase.BURNING, 100.0)
	for _frame: int in 1200:
		king.tick(FRAME)
		if _shots.size() >= Eclipse.BOLTS * 3:
			break
	var speeds: Array[float] = []
	for shot: FoeProjectile in _shots:
		speeds.append(absf(shot.velocity.x))
	assert_eq(speeds.slice(0, 9), [150.0, 150.0, 150.0, 180.0, 180.0, 180.0,
		210.0, 210.0, 210.0] as Array[float], "150, 180, 210 px/s, a volley each")
	for shot: FoeProjectile in _shots:
		assert_almost_eq(shot.position.y, king.floor_y - Eclipse.BOLT_HEIGHT, 0.01,
			"at chest height, clear over a crouching prince")
		assert_gt(king.floor_y - Tuning.CROUCH_HEIGHT, shot.position.y + shot.size.y * 0.5,
			"which it clears")


## Only the phase's own lesson wounds him; every other blow rings off his bronze.
func test_each_phase_opens_to_its_lesson_and_nothing_else() -> void:
	var lessons := {
		Eclipse.Phase.SHIELD: [Eclipse.State.PAUSE, Foe.Blow.PLUNGE],
		Eclipse.Phase.BURNING: [Eclipse.State.REST, Foe.Blow.SHOT],
		Eclipse.Phase.ECLIPSE: [Eclipse.State.SKID, Foe.Blow.SWORD],
		Eclipse.Phase.FINALE: [Eclipse.State.POUR, Foe.Blow.SHOT],
	}
	for phase: int in lessons:
		var open: Eclipse.State = lessons[phase][0]
		var lesson: Foe.Blow = lessons[phase][1]
		for blow: Foe.Blow in [Foe.Blow.SWORD, Foe.Blow.PLUNGE, Foe.Blow.STOMP, Foe.Blow.SHOT]:
			var king := _king(phase, 100.0)
			king.state = open
			var outcome := king.take_blow(blow, king.position.x - 20.0)
			var name := "%s, %s" % [Eclipse.Phase.keys()[phase], Foe.Blow.keys()[blow]]
			if blow == lesson:
				assert_true(outcome == Foe.Outcome.WOUNDED or outcome == Foe.Outcome.KILLED,
					"%s: the lesson wounds him" % name)
			else:
				assert_eq(outcome, Foe.Outcome.BLOCKED, "%s: rings off his bronze" % name)


func test_the_lesson_wounds_only_in_its_window() -> void:
	var cases := [
		[Eclipse.Phase.ECLIPSE, Eclipse.State.STALK, Foe.Blow.SWORD, "a cut while he stalks"],
		[Eclipse.Phase.ECLIPSE, Eclipse.State.CROUCH, Foe.Blow.SWORD, "a cut in the crouch"],
		[Eclipse.Phase.FINALE, Eclipse.State.GATHER, Foe.Blow.SHOT, "light while he gathers"],
		[Eclipse.Phase.SHIELD, Eclipse.State.DRAW, Foe.Blow.PLUNGE, "a plunge into his shove"],
	]
	for case: Array in cases:
		var king := _king(int(case[0]), 100.0)
		king.state = case[1]
		assert_eq(king.take_blow(case[2], king.position.x - 20.0), Foe.Outcome.BLOCKED,
			"%s is turned" % case[3])


## The rebound off his crown chains a second plunge; the third in one pass
## meets the disc, raised over his head until he has turned away.
func test_two_plunges_a_pass_and_no_more() -> void:
	var king := _king(Eclipse.Phase.SHIELD, 100.0)
	king.state = Eclipse.State.PAUSE
	assert_eq(king.take_blow(Foe.Blow.PLUNGE, 0.0), Foe.Outcome.WOUNDED, "the plunge")
	assert_eq(king.state, Eclipse.State.STAGGER, "staggered where he stands")
	assert_eq(king.take_blow(Foe.Blow.PLUNGE, 0.0), Foe.Outcome.WOUNDED, "the rebound's")
	assert_true(king.crown_guard, "and the disc goes up over the crown")
	assert_eq(king.take_blow(Foe.Blow.PLUNGE, 0.0), Foe.Outcome.BLOCKED, "a third meets it")


func test_a_phase_is_won_and_remembered_on_its_last_wound() -> void:
	# Placed as Game places him, so the memory is the one his post keeps.
	var site := EntitySite.new()
	site.at = Vector2(296.0, 240.0)
	site.memory = {"phase": Eclipse.Phase.BURNING}
	var memory := site.memory
	var king: Eclipse = autofree(Eclipse.new())
	king.place(site)
	king.set_arena(ARENA)
	king.launched.connect(func(shot: FoeProjectile) -> void: _shots.append(shot))
	assert_eq(king.phase, Eclipse.Phase.BURNING, "placed in the phase his post remembers")
	var won: Array[int] = []
	king.phase_won.connect(func(phase: int) -> void: won.append(phase))
	for _wound: int in Eclipse.WOUNDS[Eclipse.Phase.BURNING]:
		king.state = Eclipse.State.REST
		king.take_blow(Foe.Blow.SHOT, 0.0)
	assert_eq(won, [Eclipse.Phase.BURNING] as Array[int], "won on the third")
	assert_eq(memory.get("phase"), Eclipse.Phase.ECLIPSE, "and remembered at once")
	assert_eq(king.state, Eclipse.State.WON, "the disc cracks")
	assert_eq(king.wounds_total(), 3 + 3, "three crown spikes out for each phase so far")


func test_the_crown_has_a_spike_for_every_wound_in_the_fight() -> void:
	var total := 0
	for need: int in Eclipse.WOUNDS:
		total += need
	assert_eq(total, EclipseArt.SPIKES, "nine wounds, nine spikes")
	assert_eq(EclipseArt.SNUFF_ORDER.size(), EclipseArt.SPIKES, "each put out once")
	assert_eq(EclipseArt.SNUFF_ORDER[-1], (EclipseArt.SPIKES - 1) / 2,
		"and the centre spike is the finale's")
