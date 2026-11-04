extends GutTest
## A touch on a drawn control presses that control.
##
## The first build on a phone shipped with every touch scaled down by the
## stretch factor: events arrive in canvas units, and TouchControls converted
## them again as if they were window pixels. The buttons were drawn in one place
## and pressed in another. This holds the contract both halves rely on: a touch
## whose position is where a button is drawn presses that button, and a touch
## on the left drives the stick.
##
## Headless has no window, so the engine's own pixel-to-canvas step cannot run
## here; the events are built in canvas units, which is what the engine hands
## _input on a device. The old code scaled them by the canvas width over a
## window width it read as zero, and fails every case below.

const SCENE := preload("res://scenes/touch_controls.tscn")

var _controls: TouchControls


func before_each() -> void:
	_controls = SCENE.instantiate() as TouchControls
	add_child_autofree(_controls)
	await wait_physics_frames(2)
	_controls._layout()


func after_each() -> void:
	for action: String in ["jump", "attack", "pause", "move_left", "move_right", "throw"]:
		Input.action_release(action)


func test_every_action_button_is_pressed_where_it_is_drawn() -> void:
	var pressed := 0
	for button: Dictionary in _controls._buttons:
		var action := String(button["action"])
		if action == "":
			continue # the mute toggle has no action to observe
		var at: Vector2 = button["at"]
		_controls._input(_touch(at, true, 1))
		assert_true(Input.is_action_pressed(action),
			"a touch at %s, where %s is drawn, presses %s" % [at, button["id"], action])
		_controls._input(_touch(at, false, 1))
		assert_false(Input.is_action_pressed(action), "and letting go releases it")
		pressed += 1
	# A layout with no buttons would pass the loop above on nothing.
	assert_gte(pressed, 3, "jump, sword and pause were all tried")


func test_a_touch_on_the_left_drives_the_stick() -> void:
	var view := _controls.get_viewport().get_visible_rect().size
	var origin := Vector2(view.x * 0.2, view.y * 0.6)
	_controls._input(_touch(origin, true, 2))
	_controls._input(_drag(origin + Vector2(TouchControls.STICK_RADIUS, 0.0), 2))
	assert_true(Input.is_action_pressed("move_right"), "dragging right moves right")
	_controls._input(_touch(origin, false, 2))
	assert_false(Input.is_action_pressed("move_right"), "and letting go stops")


func test_a_button_touch_does_not_grab_the_stick() -> void:
	var jump: Dictionary = _controls._buttons[0]
	_controls._input(_touch(jump["at"], true, 3))
	assert_eq(_controls._stick_index, -1, "a tap on JUMP is not taken for the stick")
	_controls._input(_touch(jump["at"], false, 3))


func _touch(at: Vector2, down: bool, index: int) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.pressed = down
	event.index = index
	return event


func _drag(at: Vector2, index: int) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.position = at
	event.index = index
	return event


## --- THROW, the adventure's third button -------------------------------------

func _button(id: String) -> Dictionary:
	for button: Dictionary in _controls._buttons:
		if String(button["id"]) == id:
			return button
	return {}


func test_the_menus_have_no_throw() -> void:
	assert_true(_button("throw").is_empty(), "off by default: the menus have nothing to throw")


func test_every_scene_that_plays_asks_for_throw_and_draws_no_other() -> void:
	for path: String in ["res://scenes/game.tscn", "res://scenes/duel_match_cpu.tscn",
			"res://scenes/duel_match_online.tscn"]:
		var scene := (load(path) as PackedScene).instantiate()
		var touch := scene.get_node(^"TouchControls") as TouchControls
		assert_true(touch.throw_button, "%s lays THROW out with the other buttons" % path)
		assert_null(scene.get_node_or_null(^"ThrowLayer"),
			"%s has no THROW of its own with a hit test of its own" % path)
		scene.free()


func test_throw_sits_above_jump_and_is_pressed_where_drawn() -> void:
	_controls.throw_button = true
	_controls._layout()
	var throw := _button("throw")
	assert_false(throw.is_empty(), "laid out")
	var view := _controls.get_viewport().get_visible_rect().size
	var safe := UiLayout.safe(view)
	var jump := _button("jump")
	assert_eq((throw["at"] as Vector2).x, (jump["at"] as Vector2).x,
		"in JUMP's column, at the screen's edge rather than over the way ahead")
	assert_lt((throw["at"] as Vector2).y, (jump["at"] as Vector2).y, "above it")
	assert_eq(throw["at"], safe.end - TouchControls.THROW_AT)
	for other: String in ["jump", "attack"]:
		var button := _button(other)
		var apart: float = (throw["at"] as Vector2).distance_to(button["at"])
		assert_gt(apart, float(throw["r"]) + float(button["r"]),
			"clear of %s: a thumb on one never lands on the other" % other)
	_controls._input(_touch(throw["at"], true, 4))
	assert_true(Input.is_action_pressed("throw"), "a touch on it presses throw")
	_controls._input(_touch(throw["at"], false, 4))
	assert_false(Input.is_action_pressed("throw"), "and letting go releases it")


## --- one touch, one button ----------------------------------------------------
##
## The padded circles overlap: mute's and pause's, JUMP's and SWORD's, THROW's
## and JUMP's. The first button in the list used to take every overlap -- a
## fifth of mute's area paused the game -- and the duel's THROW, in a node of
## its own, took a touch JUMP took too. Held at both widths, over a grid laid
## across every button: a touch presses exactly one action, the one whose
## ring is nearest.

const ACTIONS: Array[String] = ["jump", "attack", "pause", "throw"]


func test_one_touch_presses_one_button_at_most() -> void:
	_controls.throw_button = true
	var surface := _controls.get_node(^"Surface") as Control
	var tried := 0
	var shared := 0
	for wide: float in [320.0, 440.0]:
		surface.size = Vector2(wide, 180.0)
		_controls._layout()
		for button: Dictionary in _controls._buttons:
			var reach: float = float(button["r"]) + TouchControls.HIT_PADDING
			var centre: Vector2 = button["at"]
			for gx: int in range(-8, 9):
				for gy: int in range(-8, 9):
					var at := centre + Vector2(gx, gy) * (reach / 8.0)
					var holders := _holders(at)
					if holders.size() > 1:
						shared += 1
					var pressed := _press_and_count(at)
					assert_lte(pressed, 1, "a touch at %s presses %d actions" % [at, pressed])
					if holders.is_empty():
						continue
					tried += 1
					var expected := _nearest(holders, at)
					var got := _controls.button_at(at)
					if String(got.get("id", "")) != String(expected["id"]):
						assert_eq(got.get("id", ""), expected["id"],
							"at %s the nearest ring takes the touch" % at)
	assert_gt(tried, 1000, "the grid landed on the buttons")
	assert_gt(shared, 0, "and in their overlaps, which is what this is about")


func test_the_edge_of_mute_does_not_pause() -> void:
	var mute := _button("mute")
	var pause := _button("pause")
	var toward := ((pause["at"] as Vector2) - (mute["at"] as Vector2)).normalized()
	# In mute's padding, off toward pause and down, and inside pause's padding
	# too: nearer mute's ring than pause's, and first in the list for pause.
	var at: Vector2 = (mute["at"] as Vector2) \
		+ toward.rotated(deg_to_rad(40.0)) * (float(mute["r"]) + 4.0)
	assert_lte(at.distance_to(pause["at"]), float(pause["r"]) + TouchControls.HIT_PADDING,
		"the touch is in both paddings")
	assert_eq(String(_controls.button_at(at)["id"]), "mute", "mute's edge is mute's")
	_controls._input(_touch(at, true, 6))
	assert_false(Input.is_action_pressed("pause"), "and does not pause the game")
	_controls._input(_touch(at, false, 6))
	GameAudio.toggle_mute() # put the sound back as it was


func test_a_page_knows_a_touch_is_a_buttons() -> void:
	var page := Control.new()
	var controls := SCENE.instantiate() as TouchControls
	controls.name = "TouchControls"
	page.add_child(controls)
	add_child_autofree(page)
	await wait_physics_frames(1)
	controls._layout()
	var jump: Dictionary = controls._buttons[0]
	assert_true(TouchControls.claims(page, jump["at"]), "JUMP's touch is JUMP's")
	var view := controls.get_viewport().get_visible_rect().size
	assert_false(TouchControls.claims(page, view * 0.5), "the middle of the screen is not")
	assert_false(TouchControls.claims(Control.new(), view * 0.5), "a screen with none claims nothing")


func _holders(at: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for button: Dictionary in _controls._buttons:
		var reach: float = float(button["r"]) + TouchControls.HIT_PADDING
		if at.distance_to(button["at"]) <= reach:
			out.append(button)
	return out


func _nearest(holders: Array[Dictionary], at: Vector2) -> Dictionary:
	var best: Dictionary = holders[0]
	for button: Dictionary in holders:
		if at.distance_to(button["at"]) - float(button["r"]) \
				< at.distance_to(best["at"]) - float(best["r"]):
			best = button
	return best


## Touches `at`, counts the actions held, and lets go. A touch on mute flips
## the sound, so a second flip puts it back.
func _press_and_count(at: Vector2) -> int:
	_controls._input(_touch(at, true, 7))
	var count := 0
	for action: String in ACTIONS:
		if Input.is_action_pressed(action):
			count += 1
	_controls._input(_touch(at, false, 7))
	if String(_controls.button_at(at).get("id", "")) == "mute":
		GameAudio.toggle_mute()
	return count
