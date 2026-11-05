extends GutTest
## The pose lab shows every pose there is, on the phone that is being tested,
## and nowhere a store build goes (scripts/ui/pose_lab.gd, docs/character.md
## "The pose lab").
##
## The lab exists because the duel's LOW guard and its duck could not be told
## apart on the phone, and no screen could show either on demand. A lab that
## silently left out a pose would answer "does this read?" for the poses it
## happened to list, so the guard here is the enums: every Fighter.State,
## every DuelTuning.Stance, every Player.State and every IdleArt.Bit must be in
## the catalogue, and every entry must actually put the body into that pose --
## the lab writes private fields by name, and Object.set() drops a value it
## cannot take in silence (CLAUDE.md).
##
## Where it is listed is held like FEEL LAB's (tests/unit/test_mode_benches.gd),
## with the difference that this one is meant for the phone: a dev build lists
## it, as the editor does, and a release never does.

const LAB := preload("res://scenes/pose_lab.tscn")
const MENU := preload("res://scenes/menu.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const FIGHTER_SCENE := preload("res://scenes/fighter.tscn")

var _store := UserData.at("user://test_pose_lab.cfg")


func after_each() -> void:
	for action: String in ["jump", "attack", "pause", "move_left", "move_right"]:
		Input.action_release(action)
	if FileAccess.file_exists(_store):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_store))


## --- nothing is missing ---------------------------------------------------------

func test_every_fighter_state_and_stance_is_in_the_lab() -> void:
	var states := {}
	var guards := {}
	for entry: Dictionary in PoseCatalogue.fighter():
		states[int(entry["state"])] = true
		if int(entry["state"]) == Fighter.State.IDLE and not entry.has("drop_blade") \
				and not entry.has("thrown"):
			guards[int(entry.get("stance", DuelTuning.Stance.MID))] = true
	for state: int in Fighter.State.values():
		assert_true(states.has(state),
			"Fighter.State.%s has a pose in the lab" % Fighter.State.keys()[state])
	for stance: int in DuelTuning.Stance.values():
		assert_true(guards.has(stance),
			"the %s guard has a pose in the lab" % DuelTuning.Stance.keys()[stance])
	assert_gt(states.size(), 0, "the catalogue was read")


func test_every_prince_state_and_idle_bit_is_in_the_lab() -> void:
	var states := {}
	var bits := {}
	for entry: Dictionary in PoseCatalogue.prince():
		states[int(entry["state"])] = true
		if entry.has("bit"):
			bits[int(entry["bit"])] = true
	for state: int in Player.State.values():
		assert_true(states.has(state),
			"Player.State.%s has a pose in the lab" % Player.State.keys()[state])
	for bit: int in IdleArt.Bit.values():
		if bit != IdleArt.Bit.NONE:
			assert_true(bits.has(bit), "the %s idle bit is in the lab" % IdleArt.Bit.keys()[bit])
	assert_gt(states.size(), 0, "the catalogue was read")


func test_the_contact_sheet_and_the_lab_share_one_table() -> void:
	var names: Array[String] = []
	for entry: Dictionary in PoseCatalogue.prince():
		names.append(String(entry["name"]))
	for row: Dictionary in PoseCatalogue.prince_table():
		assert_true(names.has(String(row["name"])), "%s is in the lab" % row["name"])


## --- every entry is the pose it says ---------------------------------------------

func test_every_fighter_entry_puts_the_fighter_in_it() -> void:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	add_child_autofree(fighter)
	fighter.setup(0, null)
	fighter.respawn_at(Vector2(100.0, 100.0), 1)
	var checked := 0
	for entry: Dictionary in PoseCatalogue.fighter():
		var label := String(entry["label"])
		assert_true(PoseCatalogue.pin_fighter(fighter, entry, Vector2(100.0, 100.0), 3),
			"%s took" % label)
		assert_eq(int(fighter.state), int(entry["state"]), "%s: the state" % label)
		assert_eq(fighter.stance, int(entry.get("stance", DuelTuning.Stance.MID)),
			"%s: the stance" % label)
		var ducked := bool(entry.get("ducked", false))
		if ducked:
			assert_eq(fighter.posture(), DuelTuning.DUCKED, "%s: ducked, as the matrix sees" % label)
		var unarmed := entry.has("drop_blade") or entry.has("thrown") or entry.has("incoming")
		assert_eq(fighter.is_armed(), not unarmed, "%s: the sword is where it says" % label)
		checked += 1
	assert_eq(checked, PoseCatalogue.fighter().size())


## The read the lab was made for: a LOW guard and a duck are different
## postures to the matrix, so the two entries must not pin the same thing.
func test_the_low_guard_and_the_duck_are_different_postures() -> void:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	add_child_autofree(fighter)
	fighter.setup(0, null)
	var low := _entry(PoseCatalogue.fighter(), PoseCatalogue.GUARD_PREFIX + "LOW")
	var duck := _entry(PoseCatalogue.fighter(), "DUCK")
	PoseCatalogue.pin_fighter(fighter, low, Vector2.ZERO, 1)
	assert_eq(fighter.posture(), DuelTuning.Stance.LOW, "the LOW guard is a LOW posture")
	PoseCatalogue.pin_fighter(fighter, duck, Vector2.ZERO, 1)
	assert_eq(fighter.posture(), DuelTuning.DUCKED, "the duck is ducked")


func test_every_prince_entry_puts_the_prince_in_it() -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	for entry: Dictionary in PoseCatalogue.prince():
		var label := String(entry["label"])
		assert_true(PoseCatalogue.pin_player(player, entry, Vector2(100.0, 100.0),
			float(entry["t"])), "%s took" % label)
		assert_eq(int(player.state), int(entry["state"]), "%s: the state" % label)
		assert_eq(player.moves.armed(), not bool(entry.get("unarmed", false)),
			"%s: the sword is where it says" % label)


## --- the lab, stepped -------------------------------------------------------------

func test_the_lab_steps_through_every_pose_of_both_bodies() -> void:
	var lab := await _lab()
	for kind: int in [PoseLab.Kind.DUEL, PoseLab.Kind.ADVENTURE]:
		if lab.kind != kind:
			lab.change("kind")
		var count := lab.poses().size()
		assert_gt(count, 0, "poses to show")
		for i: int in count:
			assert_eq(lab.index, i)
			await wait_process_frames(1)
			var body := lab.lab_figure.body()
			var entry := lab.pose()
			assert_eq(int(body.get("state")), int(entry["state"]),
				"%s is what is on screen" % entry["label"])
			assert_eq(int(lab.inset.body().get("state")), int(entry["state"]),
				"and in the inset")
			lab.step_pose(1)
		assert_eq(lab.index, 0, "and round again")
	assert_true(lab.lab_figure.body() is Player, "the adventure's body is the prince")


func test_frozen_holds_one_frame_and_playing_moves() -> void:
	var lab := await _lab()
	lab.index = PoseCatalogue.fighter().find(
		_entry(PoseCatalogue.fighter(), "THRUST MID"))
	lab.step_pose(0)
	await wait_process_frames(30)
	var fighter := lab.lab_figure.fighter()
	var seen := {}
	for _frame: int in 30:
		seen[fighter.state_frame] = true
		await wait_process_frames(1)
	assert_gt(seen.size(), 3, "playing runs the thrust's frames")
	assert_false(lab.lab_figure.is_still(), "and the art keeps drawing")

	lab.change("motion")
	await wait_process_frames(PoseLabFigure.SETTLE + 2)
	assert_true(lab.lab_figure.is_still(), "frozen, the frame on screen stays one frame")
	assert_eq(fighter.state_frame, int(_entry(PoseCatalogue.fighter(), "THRUST MID")["frame"]),
		"at the catalogue's moment")


func test_the_figure_and_the_light_change() -> void:
	var lab := await _lab()
	var art := lab.lab_figure.art()
	lab.change("figure")
	await wait_process_frames(1)
	assert_true(lab.lab_figure.art().costume is HeroineCostume, "the heroine")
	lab.change("figure")
	await wait_process_frames(1)
	assert_false(lab.lab_figure.art().costume is HeroineCostume,
		"the saved look, which with no save is the prince")
	assert_eq(art, lab.lab_figure.art(), "one body, dressed again")

	var first := lab.stage.strip_id
	var seen: Array[String] = [first]
	for _step: int in PoseLabStage.ORDER.size() - 1:
		lab.change("light")
		seen.append(lab.stage.strip_id)
	assert_true(seen.has("tug"), "the afternoon")
	assert_true(seen.has("well"), "and the darkest, the Well at night")
	assert_eq(TimeOfDay.label(lab.stage.strip.hour), "Night", "the Well is lit as night")
	assert_eq(seen.size(), PoseLabStage.ORDER.size())


func test_rows_and_arrows_are_tapped() -> void:
	var lab := await _lab()
	await wait_process_frames(2)
	var next := lab.ui.arrow_rect("next")
	assert_true(next.has_area(), "the next arrow was drawn")
	assert_true(lab.tap(next.get_center()), "a tap on it lands")
	assert_eq(lab.index, 1, "and steps the pose")
	assert_true(lab.tap(lab.ui.arrow_rect("prev").get_center()))
	assert_eq(lab.index, 0, "and back")

	var motion := lab.ui.row_rect("motion")
	assert_true(motion.has_area(), "the MOTION row was drawn")
	assert_true(lab.tap(motion.end - Vector2(2.0, 2.0)))
	assert_false(lab.playing, "a tap changes it")
	assert_eq(PoseLab.ROWS[lab.row], "motion", "and selects it")

	assert_true(lab.tap(lab.ui.row_rect("try").get_center()))
	assert_eq(lab.page, PoseLab.Page.TRY, "TRY opens on a tap")
	await wait_process_frames(2)
	assert_true(lab.ui.row_rect("dummy").has_area(), "with its own rows")
	assert_true(lab.tap(lab.ui.row_rect("dummy").end - Vector2(2.0, 2.0)))
	assert_eq(lab.spar.dummy_stance, PoseLabSpar.Dummy.LOW, "MID, then LOW")
	assert_true(lab.tap(lab.ui.row_rect("back").get_center()))
	assert_eq(lab.page, PoseLab.Page.BROWSE, "and back to the poses")


func test_the_stick_steps_poses_and_sword_leaves() -> void:
	var left := [0]
	var lab := await _lab(func() -> void: left[0] += 1)
	Input.action_press("move_right")
	await wait_process_frames(2)
	Input.action_release("move_right")
	await wait_process_frames(2)
	assert_eq(lab.index, 1, "right is the next pose")
	Input.action_press("attack")
	await wait_process_frames(2)
	assert_eq(left[0], 1, "SWORD goes back to the title screen")


## --- where it is listed -----------------------------------------------------------

func test_dev_tools_are_for_dev_builds_and_the_editor_only() -> void:
	assert_true(ModeRegistry.dev_tools_for(false, true, DevUpdate.CHANNEL_DEV),
		"the phone's dev APK lists it")
	assert_true(ModeRegistry.dev_tools_for(true, false, ""), "the editor lists it")
	assert_false(ModeRegistry.dev_tools_for(false, false, ""), "a release does not")
	assert_false(ModeRegistry.dev_tools_for(false, true, ""),
		"nor a debug export nobody stamped for the dev channel")
	assert_false(ModeRegistry.dev_tools_for(false, false, DevUpdate.CHANNEL_DEV),
		"nor a release build that a mistake stamped dev")
	assert_eq(ModeRegistry.dev_tools_for(false, true, DevUpdate.CHANNEL_DEV),
		DevUpdate.should_check(true, DevUpdate.CHANNEL_DEV, "https://example.org/v.json"),
		"the same signal that turns the update check on")


func test_the_title_screen_lists_the_pose_lab_only_where_dev_tools_are() -> void:
	assert_true(_ids(ModeRegistry.modes(false, true)).has("pose_lab"))
	assert_false(_ids(ModeRegistry.modes(true, false)).has("pose_lab"),
		"benches do not bring it: it is the phone's, not the editor's")
	for dev: bool in [false, true]:
		var menu := MENU.instantiate() as MenuScene
		menu.benches = false
		menu.dev_tools = dev
		menu.quit_app = func() -> void: pass
		add_child_autofree(menu)
		var ids: Array[String] = []
		for row: Dictionary in menu.rows():
			ids.append(String(row["id"]))
		assert_eq(ids.has("pose_lab"), dev, "POSE LAB %s" % ("listed" if dev else "absent"))
		menu.free()


## --- helpers --------------------------------------------------------------------

func _lab(leave: Callable = func() -> void: pass) -> PoseLab:
	var lab := LAB.instantiate() as PoseLab
	lab.wardrobe_path = _store
	lab.leave = leave
	add_child_autofree(lab)
	await wait_process_frames(2)
	return lab


func _entry(entries: Array[Dictionary], label: String) -> Dictionary:
	for entry: Dictionary in entries:
		if String(entry["label"]) == label:
			return entry
	fail_test("no pose labelled %s" % label)
	return {}


func _ids(modes: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for mode: Dictionary in modes:
		out.append(String(mode["id"]))
	return out
