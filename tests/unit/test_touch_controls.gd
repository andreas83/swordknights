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


func test_the_menus_and_the_duel_have_no_throw_of_this_layouts() -> void:
	assert_true(_button("throw").is_empty(),
		"off by default: the menus have nothing to throw, the duel draws its own")


func test_the_adventure_scene_asks_for_throw() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	var touch := game.get_node(^"TouchControls") as TouchControls
	assert_true(touch.throw_button, "scenes/game.tscn lays THROW out")
	game.free()


func test_throw_sits_where_the_duels_does_and_is_pressed_where_drawn() -> void:
	_controls.throw_button = true
	_controls._layout()
	var throw := _button("throw")
	assert_false(throw.is_empty(), "laid out")
	var view := _controls.get_viewport().get_visible_rect().size
	var safe := UiLayout.safe(view)
	assert_eq(throw["at"], Vector2(safe.end.x - 52.0, safe.end.y - 78.0),
		"at the duel's place: up and to the left of JUMP (scripts/duel/duel_touch.gd)")
	assert_eq(float(throw["r"]), DuelTouchGuard.RADIUS, "and the duel's size")
	for other: String in ["jump", "attack"]:
		var button := _button(other)
		var apart: float = (throw["at"] as Vector2).distance_to(button["at"])
		assert_gt(apart, float(throw["r"]) + float(button["r"]),
			"clear of %s: a thumb on one never lands on the other" % other)
	_controls._input(_touch(throw["at"], true, 4))
	assert_true(Input.is_action_pressed("throw"), "a touch on it presses throw")
	_controls._input(_touch(throw["at"], false, 4))
	assert_false(Input.is_action_pressed("throw"), "and letting go releases it")
