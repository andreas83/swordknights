extends GutTest
## The pose lab's TRY page is the duel, by thumb: the real fighters on the real
## duel frame, driven through the same actions the touch controls press, and a
## readout that says which posture the matrix saw and what came of it
## (scripts/ui/pose_lab_spar.gd).
##
## The page is for one question -- did my thumb make a LOW guard or a duck? --
## so these hold the answers it gives against the duel's own rules: down is a
## LOW guard, down with WALK is the duck; a LOW guard parries a LOW thrust and
## a duck dies to one; a duck lets a HIGH thrust over; a guard turns a thrust
## at its own height, a dummy with no sword turns nothing, and a thrust that
## meets nothing is a MISS. The readout's words come from DuelCombat's events,
## so a parry the readout reports is one the duel would have had.

const LAB := preload("res://scenes/pose_lab.tscn")

var _store := UserData.at("user://test_pose_lab_try.cfg")


func after_each() -> void:
	for action: String in ["move_down", "move_up", "walk", "attack", "jump", "move_left",
			"move_right", "throw", "pause"]:
		Input.action_release(action)


func test_down_is_a_low_guard_and_down_with_walk_is_the_duck() -> void:
	var lab := await _try()
	Input.action_press("move_down")
	await wait_physics_frames(4)
	assert_eq(lab.spar.you.posture(), DuelTuning.Stance.LOW, "down holds LOW")
	assert_eq(PoseLabSpar.posture_name(lab.spar.you), "LOW", "and the readout says so")
	var held := lab.spar.held
	await wait_physics_frames(6)
	assert_gt(lab.spar.held, held, "and counts how long it has held")
	Input.action_press("walk")
	await wait_physics_frames(3)
	assert_eq(lab.spar.you.posture(), DuelTuning.DUCKED, "down with WALK is the duck")
	assert_eq(PoseLabSpar.posture_name(lab.spar.you), "DUCKED")
	assert_string_contains(PoseLabSpar.bits_name(lab.ui.your_bits), "WALK",
		"the readout shows the thumb held WALK")


func test_a_low_guard_parries_a_low_thrust_and_a_duck_dies_to_it() -> void:
	var lab := await _try()
	lab.spar.set_dummy(PoseLabSpar.Dummy.LOW)
	lab.spar.dummy_thrusts = true
	Input.action_press("move_down")
	assert_eq(await _until_word(lab), "PARRY", "the LOW guard turned the LOW thrust")
	assert_true(lab.spar.you.is_alive())

	lab.spar.place()
	lab.spar.last = {}
	Input.action_press("walk")
	assert_eq(await _until_word(lab), "KILLED", "the duck died to it")


func test_a_duck_lets_a_high_thrust_over() -> void:
	var lab := await _try()
	lab.spar.set_dummy(PoseLabSpar.Dummy.HIGH)
	lab.spar.dummy_thrusts = true
	Input.action_press("move_down")
	Input.action_press("walk")
	assert_eq(await _until_word(lab), "MISSED YOU", "over the head")
	assert_true(lab.spar.you.is_alive())


func test_a_guard_turns_a_thrust_and_no_sword_turns_nothing() -> void:
	var lab := await _try()
	await _thrust(lab)
	assert_eq(String(lab.spar.last.get("word", "")), "PARRIED",
		"the dummy's MID guard turned a MID thrust")

	lab.spar.place()
	lab.spar.last = {}
	lab.spar.set_dummy(PoseLabSpar.Dummy.NONE)
	assert_false(lab.spar.dummy.is_armed(), "NONE is a dummy with no sword")
	await _thrust(lab)
	assert_eq(String(lab.spar.last.get("word", "")), "KILL")
	assert_false(lab.spar.dummy.is_alive())
	await wait_physics_frames(PoseLabSpar.RESPAWN_FRAMES + 4)
	assert_true(lab.spar.dummy.is_alive(), "and is put back on its mark")
	assert_false(lab.spar.dummy.is_armed(), "still without its sword")


func test_a_thrust_that_meets_nothing_is_a_miss() -> void:
	var lab := await _try()
	lab.spar.dummy.respawn_at(lab.spar.you.position + Vector2(120.0, 0.0), -1)
	await _thrust(lab)
	await wait_physics_frames(DuelTuning.default().thrust_frames + 2)
	assert_eq(String(lab.spar.last.get("word", "")), "MISS")


func test_describe_reads_a_clash_by_who_was_thrusting() -> void:
	var clash: Array[Dictionary] = [{"kind": "clash", "at": Vector2.ZERO}]
	assert_eq(PoseLabSpar.describe(clash, [true, true])["word"], "CLASH")
	assert_eq(PoseLabSpar.describe(clash, [true, false])["word"], "PARRIED")
	assert_eq(PoseLabSpar.describe(clash, [false, true])["word"], "PARRY")
	var none: Array[Dictionary] = []
	assert_true(PoseLabSpar.describe(none, [false, false]).is_empty(), "nothing happened")
	var disarm: Array[Dictionary] = [{"kind": "disarm", "victim": 0, "by": 1}]
	assert_eq(PoseLabSpar.describe(disarm, [true, false])["word"], "DISARMED")


func test_pause_and_back_return_to_the_poses() -> void:
	var lab := await _try()
	Input.action_press("pause")
	await wait_process_frames(2)
	Input.action_release("pause")
	assert_eq(lab.page, PoseLab.Page.BROWSE, "PAUSE is the way back on TRY")
	assert_false(lab.spar.visible, "and the sparring floor is put away")


## --- helpers --------------------------------------------------------------------

func _try() -> PoseLab:
	var lab := LAB.instantiate() as PoseLab
	lab.wardrobe_path = _store
	lab.leave = func() -> void: pass
	add_child_autofree(lab)
	await wait_process_frames(2)
	lab.open_try()
	await wait_physics_frames(4)
	assert_eq(lab.page, PoseLab.Page.TRY)
	return lab


## One press of SWORD, held for two frames.
func _thrust(lab: PoseLab) -> void:
	Input.action_press("attack")
	await wait_physics_frames(2)
	Input.action_release("attack")
	await wait_physics_frames(DuelTuning.default().thrust_frames)
	assert_not_null(lab)


## Waits up to two of the dummy's thrusts for the readout to say something.
func _until_word(lab: PoseLab) -> String:
	for _frame: int in PoseLabSpar.THRUST_EVERY * 2 + 10:
		if not lab.spar.last.is_empty():
			return String(lab.spar.last["word"])
		await wait_physics_frames(1)
	return ""
