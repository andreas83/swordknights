extends GutTest
## The Caracal (scripts/entities/caracal.gd) in the real game scene, refereed
## by Game through the foe contract like any other foe.
##
## Pinned here, as docs/campaign.md's build plan asks: the crouch is the
## game's telegraph and the assist stretches it; the backstep beats the pounce
## when thrown anywhere in a window of at least 28 frames between the crouch's
## end and the landing, and not thrown at all it lands; the skid outlasts the
## backstep's remainder plus a swing's lead, so the cut lands; a swing meets it
## in the air; the parry does nothing; it is harmless to touch and weighs
## nothing; it never pounces over a hole; and a cat that pushes off crumbling
## stone falls through it.

const GAME_SCENE := "res://scenes/game.tscn"
const ASSIST_PATH := "user://test_caracal_assist.cfg"

## The prince facing east, the cat eight tiles off, facing him.
const ARENA := """; Cat Arena





   @       j            D
##########################
##########################
"""

## The prince with his back to a drop: the collapse behind him, as at the
## tower's foot. A backstep has three pixels to slide.
const LIP := """; Cat At The Lip





      @     j          D
#     ##################
#     ##################
"""

## The deck's twist in miniature: the cat on the stone east of a run of
## slabs, the prince waiting west of it exactly as far short of the run as
## he does on Chapter III's deck (76.5 px).
const DECK := """; Cat On The Deck





                j       D
#########,,,#############
#########   #############
#########   #############
"""

## The prince across a gap from the cat: it may stalk to the lip, never leap.
const ACROSS := """; Cat Across





   @          j       D
#######   ################
#######   ################
"""

## The cat is posted on a run of crumbling stone over the void, the prince on
## the stone to its west, within its reach.
const SLABS := """; Cat On Slabs





  @        j           D
##########,,,###########
##########   ###########
##########   ###########
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func before_each() -> void:
	Assist.reset()
	Assist.load_saved(ASSIST_PATH)


func after_each() -> void:
	Assist.reset()
	if FileAccess.file_exists(ASSIST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ASSIST_PATH))


func _play(text: String) -> void:
	var data := AsciiLevel.new()
	data.parse(text)
	assert_eq(data.problems, PackedStringArray(), "the level parses clean")
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(2)


func _cat() -> Caracal:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Caracal and not node.is_queued_for_deletion():
			return node as Caracal
	return null


## Steps until `cat` is in `state`, at most `frames`. True when it got there.
func _until_state(cat: Caracal, state: Caracal.State, frames: int) -> bool:
	for _frame: int in frames:
		if is_instance_valid(cat) and cat.state == state:
			return true
		await get_tree().physics_frame
	return is_instance_valid(cat) and cat.state == state


func _tap(bits: int) -> void:
	_input.bits = bits
	await get_tree().physics_frame
	_input.bits = 0


## Plays one pounce at a standing prince, throwing the backstep `throw`
## frames after the cat leaves the ground (-1: never), and stops `settle`
## frames after it lands (-1: when its skid is over), before it can come
## again. Returns `{hurt, flight}`: whether he lost a heart, and the frames
## the pounce was in the air.
func _pounce_at_him(throw: int, settle: int = -1, text: String = ARENA) -> Dictionary:
	await _play(text)
	var cat := _cat()
	assert_true(await _until_state(cat, Caracal.State.POUNCE, 400), "it pounced")
	var flight := 0
	var down := -1
	for frame: int in 150:
		if frame == throw:
			await _tap(PlayerInput.BIT_LEFT | PlayerInput.BIT_ATTACK)
		else:
			await get_tree().physics_frame
		if not is_instance_valid(cat):
			break
		if cat.state == Caracal.State.POUNCE:
			flight = frame + 1
		elif down < 0:
			down = frame
		if down >= 0 and (frame - down == settle
				or settle < 0 and cat.state != Caracal.State.SKID):
			break
	return {"hurt": _game.player.health < Tuning.MAX_HEALTH, "flight": flight}


## --- the numbers ---------------------------------------------------------------

func test_the_crouch_is_the_telegraph_and_the_assist_stretches_it() -> void:
	var cat := Caracal.new()
	autofree(cat)
	assert_eq(roundi(cat.crouch_time() * 60.0), 27, "Patrol.WINDUP_TIME: 'now'")
	assert_eq(Assist.set_longer_warnings(true), OK, "saved to the test's own file")
	assert_almost_eq(cat.crouch_time(), Caracal.CROUCH_TIME * Assist.LONGER, 0.0001,
		"stretched by the one factor")
	cat.target_rect = Rect2(Vector2(40.0, -22.0), Vector2(9.0, 22.0))
	cat.facing = -1
	cat.position = Vector2(100.0, 0.0)
	var crouched := 0
	for _frame: int in 120:
		cat.tick(1.0 / 60.0, true)
		if cat.state == Caracal.State.CROUCH:
			crouched += 1
		if cat.state == Caracal.State.POUNCE:
			break
	assert_eq(crouched, roundi(27.0 * Assist.LONGER), "and it crouches that long, to the frame")


func test_the_skid_outlasts_a_late_backstep_and_a_swing() -> void:
	var skid := roundi(Caracal.SKID_TIME * 60.0)
	var latest_remainder := roundi(Tuning.BACKSTEP_TIME * 60.0) - 2
	var lead := ceili(Tuning.ATTACK_TIME * 0.25 * 60.0)
	assert_eq(skid, 40)
	assert_gt(skid, roundi(Patrol.RECOVER_TIME * 60.0), "longer than a sentinel's opening")
	assert_gt(skid, latest_remainder + lead,
		"a backstep thrown two frames before the landing is over, and a swing live, in it")


func test_it_is_light_and_harmless_to_touch() -> void:
	var cat := Caracal.new()
	autofree(cat)
	assert_false(cat.has_weight(), "no plate or lift counts a cat")
	await _play(ARENA)
	cat = _cat()
	cat.on_screen = false
	_game.player.position = cat.position
	for _frame: int in 30:
		cat.state = Caracal.State.PROWL
		await get_tree().physics_frame
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "standing in it costs nothing")


## --- the pounce and the backstep ------------------------------------------------

func test_a_pounce_he_does_nothing_about_lands() -> void:
	var report := await _pounce_at_him(-1)
	assert_true(bool(report["hurt"]), "it lands on where he stood")
	assert_between(int(report["flight"]), 25, 31,
		"its claws find him only at the end of the thirty-frame leap")


func test_the_backstep_beats_it_across_a_window_of_28_frames() -> void:
	var safe: Array[int] = []
	var flight := 0
	for throw: int in [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 28, 29]:
		var report := await _pounce_at_him(throw)
		flight = maxi(flight, int(report["flight"]))
		if not bool(report["hurt"]):
			safe.append(throw)
	assert_eq(safe.slice(0, 10), [0, 3, 6, 9, 12, 15, 18, 21, 24, 27] as Array[int],
		"thrown any time from the crouch's end to about two frames before the landing")
	assert_gte(safe.max() + 1, 28, "a window of at least 28 frames")
	assert_false(safe.has(29), "and not after its claws are in him")
	assert_gt(flight, 0, "it was in the air")


func test_with_no_ground_behind_only_a_late_backstep_survives() -> void:
	var early := await _pounce_at_him(0, -1, LIP)
	assert_true(bool(early["hurt"]),
		"thrown at once it slides nowhere, and is over before the claws arrive")
	var late := await _pounce_at_him(22, -1, LIP)
	assert_false(bool(late["hurt"]),
		"thrown late, its window covers the claws where he stands: the ground he no longer has")


func test_after_the_backstep_the_skid_is_the_opening() -> void:
	await _pounce_at_him(12, 14)
	var cat := _cat()
	assert_eq(cat.state, Caracal.State.SKID, "the backstep is over and the cat still skids")
	assert_ne(_game.player.state, Player.State.BACKSTEP, "and he is standing again")
	_input.bits = PlayerInput.BIT_RIGHT
	await get_tree().physics_frame
	await _tap(PlayerInput.BIT_RIGHT | PlayerInput.BIT_ATTACK)
	for _frame: int in 20:
		await get_tree().physics_frame
	assert_false(is_instance_valid(cat) and cat.is_alive(), "step in and cut: one heart")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "and it never touched him")


func test_a_swing_meets_it_in_the_air() -> void:
	await _play(ARENA)
	var cat := _cat()
	assert_true(await _until_state(cat, Caracal.State.POUNCE, 400), "it pounced")
	var swung := false
	for _frame: int in 60:
		var nose := cat.bounds().position.x
		var front := _game.player.position.x + Tuning.BODY_WIDTH * 0.5
		if not swung and nose - front <= 18.0:
			swung = true
			await _tap(PlayerInput.BIT_ATTACK)
		else:
			await get_tree().physics_frame
	assert_true(swung, "it came into reach")
	assert_false(is_instance_valid(cat) and cat.is_alive(), "the sword's band reached it first")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "before its claws reached him")


func test_the_parry_turns_blades_not_bodies() -> void:
	await _play(ARENA)
	var cat := _cat()
	assert_true(await _until_state(cat, Caracal.State.POUNCE, 400), "it pounced")
	for _frame: int in 22:
		await get_tree().physics_frame
	await _tap(PlayerInput.BIT_UP | PlayerInput.BIT_ATTACK)
	for _frame: int in 30:
		await get_tree().physics_frame
	assert_lt(_game.player.health, Tuning.MAX_HEALTH, "it came in under the raised guard")


## --- terrain ----------------------------------------------------------------------

func test_it_never_pounces_over_a_hole() -> void:
	await _play(ACROSS)
	var cat := _cat()
	for _frame: int in 300:
		await get_tree().physics_frame
		assert_ne(cat.state, Caracal.State.POUNCE, "not across the gap")
		if cat.state == Caracal.State.POUNCE:
			break
	assert_eq(_game.player.health, Tuning.MAX_HEALTH)


func test_it_never_pounces_at_a_target_over_a_hole() -> void:
	await _play(ACROSS)
	var cat := Caracal.new()
	autofree(cat)
	cat.level = _game.level
	cat.position = Vector2(11.0 * 16.0, 6.0 * 16.0)
	cat.facing = -1
	# A prince hanging off the lip in front of it: his feet are within a tile
	# of its floor and in reach, but there is nothing under them.
	var feet := Vector2(9.0 * 16.0 + 8.0, 7.0 * 16.0)
	cat.target_rect = Rect2(feet - Vector2(4.5, 22.0), Vector2(9.0, 22.0))
	var crouched := false
	for _frame: int in 60:
		cat.tick(1.0 / 60.0, true)
		crouched = crouched or cat.state == Caracal.State.CROUCH
	assert_false(crouched, "no crouch at a target over the pit")
	var floor_feet := Vector2(10.0 * 16.0 + 4.0, 6.0 * 16.0)
	cat.target_rect = Rect2(floor_feet - Vector2(4.5, 22.0), Vector2(9.0, 22.0))
	cat.state = Caracal.State.PROWL
	cat.facing = -1
	for _frame: int in 3:
		cat.tick(1.0 / 60.0, true)
	assert_eq(cat.state, Caracal.State.CROUCH, "while one on the stone is fair game")


func test_a_cat_drawn_onto_the_slabs_is_on_them_with_all_four_feet() -> void:
	await _play(DECK)
	_game.player.position = Vector2(9.0 * 16.0 - 76.5, 6.0 * 16.0)
	var cat := _cat()
	assert_true(await _until_state(cat, Caracal.State.CROUCH, 400), "it stalked him and crouched")
	var body := cat.bounds()
	assert_gte(body.position.x, 9.0 * 16.0, "every foot on the crumbling stone")
	assert_true(await _until_state(cat, Caracal.State.FALL, 60), "so its push-off breaks them")
	for _frame: int in 120:
		await get_tree().physics_frame
	assert_false(is_instance_valid(cat), "and it goes through, not onto the stone beside")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH)


func test_a_cat_cannot_push_off_crumbling_stone() -> void:
	await _play(SLABS)
	var cat := _cat()
	_game.player.position = Vector2(8.0 * 16.0, 6.0 * 16.0)
	assert_true(await _until_state(cat, Caracal.State.CROUCH, 300), "it crouched on the slabs")
	var slabs: CrumblingStone = null
	for node: Node in _game.get_node("Entities").get_children():
		if node is CrumblingStone:
			slabs = node as CrumblingStone
	var whole := 0
	for index: int in 3:
		whole += 1 if slabs.holds(index) else 0
	assert_eq(whole, 3, "it walked them without breaking any")
	assert_true(await _until_state(cat, Caracal.State.FALL, 60), "the push-off broke the slab")
	for _frame: int in 120:
		await get_tree().physics_frame
	assert_false(is_instance_valid(cat), "and the cat went through it, into the void")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "without ever leaving the ground")
