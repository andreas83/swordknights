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
	for action: String in ["jump", "attack", "pause", "move_left", "move_right"]:
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
