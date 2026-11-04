extends GutTest
## The title screen's rows and the settings page answer a tap
## (scripts/ui/menu.gd, scripts/ui/settings_panel.gd).
##
## Every other page could be tapped -- the chapter select, the duel page, the
## wardrobe, the pause menu -- but the first screen a phone shows ignored
## every touch except the update plaque's, and the settings page set its
## mouse filter to IGNORE and had no handler at all: on a phone the only way
## through either was the floating stick and JUMP. Held here: a tap selects a
## row and a tap on the selected row opens it; the touch counts and the mouse
## click Godot emulates from it does not, so one tap is one press; a touch
## that is a thumb button's is not also a row's; on the settings page a tap
## flips a switch, and a tap on a gauge's cells sets the volume there; and
## HAPTICS is a switch that writes through to Flow.

const MENU := preload("res://scenes/menu.tscn")


## The settings panel's director, as tests/ui_layout_test.gd stubs it: the
## real one would write the player's mixer.
class FakeAudio extends Node:
	var settings := AudioSettings.new()

	func set_volume(bus: StringName, value: float) -> void:
		match String(bus):
			"Music":
				settings.music = value
			"SFX":
				settings.sfx = value
			_:
				settings.master = value

	func toggle_mute() -> void:
		settings.muted = not settings.muted

	func play(_event: String) -> void:
		pass


var _haptics := false


func before_each() -> void:
	_haptics = Flow.haptics_enabled()


func after_each() -> void:
	Flow.set_haptics_enabled(_haptics)


## --- the title screen ---------------------------------------------------------

func test_a_tap_selects_a_row_and_a_second_opens_it() -> void:
	var menu := await _menu()
	var settings := _row_of(menu, MenuScene.SETTINGS_ID)
	assert_ne(menu.index(), settings, "the cursor starts elsewhere")
	_touch(menu, menu.row_rect(settings).get_center())
	assert_eq(menu.index(), settings, "a tap selects SETTINGS")
	var panel := menu.get_node(^"SettingsPanel") as SettingsPanel
	assert_false(panel.visible, "and only selects it")
	_touch(menu, menu.row_rect(settings).get_center())
	assert_true(panel.visible, "a tap on the selected row opens it")


func test_a_mouse_click_is_not_a_second_tap() -> void:
	var menu := await _menu()
	var settings := _row_of(menu, MenuScene.SETTINGS_ID)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = menu.row_rect(settings).get_center()
	menu._input(click)
	assert_ne(menu.index(), settings,
		"the click Godot emulates from a touch is not a press of its own")


func test_every_row_can_be_tapped_and_none_is_under_a_thumb_button() -> void:
	var menu := await _menu()
	var controls := TouchControls.of(menu)
	(controls.get_node(^"Surface") as Control).visible = true
	await wait_process_frames(2)
	for row: int in menu.rows().size():
		var rect := menu.row_rect(row)
		assert_true(rect.has_area(), "row %d has a place to tap" % row)
		for corner: Vector2 in [rect.position, rect.end, Vector2(rect.end.x, rect.position.y),
				Vector2(rect.position.x, rect.end.y)]:
			assert_true(controls.button_at(corner).is_empty(),
				"row %d's corner %s is clear of the thumb buttons" % [row, corner])


func test_a_touch_on_a_thumb_button_is_not_a_row() -> void:
	var menu := await _menu()
	var controls := TouchControls.of(menu)
	var jump: Dictionary = controls._buttons[0]
	var before := menu.index()
	# A row under JUMP, as a wider list or a narrower screen could put one.
	var last := menu.rows().size() - 1
	menu._row_rects[last] = Rect2(jump["at"] - Vector2(40.0, 6.0), Vector2(80.0, 12.0))
	assert_false(menu.tap(jump["at"]), "JUMP's touch is JUMP's, whatever is under it")
	assert_eq(menu.index(), before, "and the row under it is not chosen too")
	Input.action_release("jump")


## --- the settings page --------------------------------------------------------

func test_a_tap_selects_a_setting_and_flips_a_switch() -> void:
	var panel := await _panel()
	var haptics := _setting(panel, "haptics")
	assert_ne(panel.index(), haptics)
	_touch(panel, panel.row_rect(haptics).get_center())
	assert_eq(panel.index(), haptics, "a tap selects HAPTICS")
	var was := Flow.haptics_enabled()
	_touch(panel, panel.row_rect(haptics).get_center())
	assert_ne(Flow.haptics_enabled(), was, "a tap on it flips it, through Flow")
	assert_eq(panel.is_on(panel.rows()[haptics]), Flow.haptics_enabled(), "and says so")

	var back := _setting(panel, "back")
	var closed := [0]
	panel.closed.connect(func() -> void: closed[0] += 1)
	_touch(panel, panel.row_rect(back).get_center())
	_touch(panel, panel.row_rect(back).get_center())
	assert_eq(closed[0], 1, "and BACK, tapped twice, goes back")


func test_a_tap_on_a_gauge_sets_the_volume_there() -> void:
	var panel := await _panel()
	var music := _setting(panel, "music")
	_touch(panel, panel.row_rect(music).get_center())
	assert_eq(panel.index(), music)
	var gauge := panel.gauge_rect(music)
	assert_true(gauge.has_area(), "the gauge can be tapped")
	var cell := (SettingsPanel.GAUGE_CELL.x + 1.0)
	_touch(panel, Vector2(gauge.position.x + cell * 3.5, gauge.get_center().y))
	assert_almost_eq(panel.value_of(panel.rows()[music]), 0.4, 0.001, "the fourth cell is 40%")
	_touch(panel, Vector2(gauge.end.x - 1.0, gauge.get_center().y))
	assert_almost_eq(panel.value_of(panel.rows()[music]), 1.0, 0.001, "the last is full")
	_touch(panel, Vector2(gauge.position.x + 1.0, gauge.get_center().y))
	assert_almost_eq(panel.value_of(panel.rows()[music]), 0.1, 0.001, "the first, one cell")
	_touch(panel, Vector2(gauge.position.x + 1.0, gauge.get_center().y))
	assert_almost_eq(panel.value_of(panel.rows()[music]), 0.0, 0.001,
		"and the first again, when it is all that is lit, is silence")


func test_a_hidden_page_takes_no_taps() -> void:
	var panel := await _panel()
	var haptics := _setting(panel, "haptics")
	var rect := panel.row_rect(haptics)
	panel.visible = false
	assert_false(panel.tap(rect.get_center()), "nothing to tap on a page not shown")


## --- helpers ------------------------------------------------------------------

func _menu() -> MenuScene:
	var menu := MENU.instantiate() as MenuScene
	menu.quit_app = func() -> void: pass
	add_child_autofree(menu)
	await wait_process_frames(3)
	return menu


func _panel() -> SettingsPanel:
	var panel := SettingsPanel.new()
	panel.audio = FakeAudio.new()
	panel.add_child(panel.audio)
	add_child_autofree(panel)
	panel.visible = true
	await wait_process_frames(3)
	return panel


func _row_of(menu: MenuScene, id: String) -> int:
	for row: int in menu.rows().size():
		if String(menu.rows()[row]["id"]) == id:
			return row
	return -1


func _setting(panel: SettingsPanel, id: String) -> int:
	for row: int in panel.rows().size():
		if String(panel.rows()[row]["id"]) == id:
			return row
	return -1


## A touch, as the engine hands it to _input, already in canvas units.
func _touch(screen: Control, at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = at
	screen._input(touch)
