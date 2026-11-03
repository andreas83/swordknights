extends GutTest
## LONGER WARNINGS (scripts/core/assist.gd): one setting, read through one API
## in the foe contract (Foe.warn()), reaching the sentinel's raise.
##
## Held here: off, the factor is exactly 1.0 and the raise is the frames it
## always was -- which is what keeps a game nobody assisted the game it was;
## on, the raise lasts the factor longer, frame for frame, while the cut and
## the opening after it keep their own timing; the choice survives the app
## being closed, and a missing or broken file is "off"; and the settings page
## is where it is switched.

const FRAME := 1.0 / 60.0
const PATH := "user://test_assist.cfg"


func before_each() -> void:
	Assist.reset()


func after_each() -> void:
	Assist.reset()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## A guard with a prince just inside its reach, so it raises on the first
## frame. Returns the frames each state of its attack lasted.
func _attack() -> Dictionary:
	var guard := Patrol.new()
	autofree(guard)
	guard.facing = 1
	guard.position = Vector2(100.0, 200.0)
	var front := guard.position.x + Patrol.BODY.x * 0.5
	guard.target_rect = Rect2(
		Vector2(front + Patrol.ENGAGE_GAP - 1.0, guard.position.y - Tuning.BODY_HEIGHT),
		Vector2(Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT))
	var frames := {}
	for _frame: int in 300:
		guard.tick(FRAME, true)
		var state := String(Patrol.State.keys()[guard.state])
		frames[state] = int(frames.get(state, 0)) + 1
		if guard.state == Patrol.State.WALK and frames.has("RECOVER"):
			break
	return frames


func test_off_the_factor_is_one_and_the_raise_is_as_it_was() -> void:
	assert_false(Assist.longer_warnings(), "off by default")
	assert_eq(Assist.warning_scale(), 1.0, "exactly one: an unassisted game is unchanged")
	var guard: Patrol = autofree(Patrol.new())
	assert_eq(guard.warn(Patrol.WINDUP_TIME), Patrol.WINDUP_TIME, "warn() is the number given")
	assert_eq(guard.windup_time(), Patrol.WINDUP_TIME, "and the raise is WINDUP_TIME")
	var frames := _attack()
	assert_almost_eq(int(frames.get("WINDUP", 0)), roundi(Patrol.WINDUP_TIME / FRAME), 1,
		"27 frames of raise")


func test_on_the_sentinels_raise_lasts_the_factor_longer() -> void:
	var off := _attack()
	Assist.load_saved(PATH)
	assert_eq(Assist.set_longer_warnings(true), OK, "saved")
	assert_eq(Assist.warning_scale(), Assist.LONGER)
	var guard: Patrol = autofree(Patrol.new())
	assert_eq(guard.windup_time(), Patrol.WINDUP_TIME * Assist.LONGER,
		"the raise reads the assist through the foe contract")
	var on := _attack()
	assert_almost_eq(int(on.get("WINDUP", 0)),
		roundi(Patrol.WINDUP_TIME * Assist.LONGER / FRAME), 1, "the raise, frame for frame")
	assert_gt(int(on.get("WINDUP", 0)), int(off.get("WINDUP", 0)), "longer than unassisted")
	assert_eq(on.get("STRIKE"), off.get("STRIKE"), "the cut itself is not slowed")
	assert_eq(on.get("RECOVER"), off.get("RECOVER"), "nor the opening after it")


func test_the_choice_is_kept_and_a_bad_file_is_off() -> void:
	Assist.load_saved(PATH)
	Assist.set_longer_warnings(true)
	Assist.reset()
	assert_true(Assist.load_saved(PATH), "the file is read back")
	assert_true(Assist.longer_warnings(), "with the assist on")

	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("[assist]\nlonger_warnings=\"very\"\n")
	file.close()
	assert_false(Assist.load_saved(PATH), "a value of the wrong type is not believed")
	assert_false(Assist.longer_warnings(), "and is off")

	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("not a config file [[[")
	file.close()
	Assist.load_saved(PATH)
	assert_false(Assist.longer_warnings(), "a broken file is off")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	assert_false(Assist.load_saved(PATH), "and so is no file at all")
	assert_false(Assist.longer_warnings())


func test_the_settings_page_switches_it() -> void:
	Assist.load_saved(PATH)
	var panel := SettingsPanel.new()
	add_child_autofree(panel)
	var rows := panel.rows()
	var at := -1
	for i: int in rows.size():
		if String(rows[i]["id"]) == "warnings":
			at = i
	assert_gt(at, -1, "the page has the row")
	if at < 0:
		return
	assert_eq(String(rows[at]["label"]), "LONGER WARNINGS")
	while panel.index() != at:
		panel.move(1)
	assert_false(panel.is_on(rows[at]), "off to start")
	panel.confirm()
	assert_true(Assist.longer_warnings(), "jump on the row turns it on")
	assert_true(FileAccess.file_exists(PATH), "and saves it")
	panel.adjust(-1)
	assert_false(Assist.longer_warnings(), "left turns it off")
	panel.adjust(-1)
	assert_false(Assist.longer_warnings(), "and left again leaves it off")
