extends GutTest
## The title screen's half of the dev channel: the plaque appears only when
## there is something to offer, a tap on it opens the APK URL once, and the
## settings page names the running build (scripts/ui/menu.gd,
## scripts/ui/settings_panel.gd).

const MENU := preload("res://scenes/menu.tscn")
const BuildStamp := preload("res://scripts/core/build_stamp.gd")
const APK := "https://github.com/o/r/releases/download/dev/swordknights-dev.apk"

var _menu: MenuScene
var _opened: Array[String] = []


func before_each() -> void:
	_opened.clear()
	_menu = MENU.instantiate() as MenuScene
	add_child_autofree(_menu)
	_menu.opener = func(url: String) -> void: _opened.append(url)


func _offer() -> Dictionary:
	return {"code": 158, "name": "0.1.0-dev+4f2c9e1", "sha": "4f2c9e1", "date": "",
		"apk_url": APK}


func _tap(at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = at
	_menu._input(touch)


func test_the_build_under_test_shows_no_plaque() -> void:
	var check := _menu.get_node(^"UpdateCheck") as UpdateCheck
	assert_not_null(check, "the menu owns an update check")
	assert_false(check.busy(), "an unstamped build made no request")
	await wait_process_frames(2)
	assert_eq(_menu.offered(), {})
	assert_false(_menu.offer_rect().has_area(), "and drew no plaque")


func test_the_plaque_is_a_thumb_sized_target_at_the_top() -> void:
	_menu.offer_update(_offer())
	await wait_process_frames(2)
	var hit := _menu.offer_rect()
	var view := _menu.size
	assert_true(hit.has_area(), "the plaque was drawn")
	assert_gte(hit.size.y, MenuScene.PLAQUE_TOUCH, "tall enough for a thumb")
	assert_gte(hit.size.x, MenuScene.PLAQUE_TOUCH, "and wide enough")
	assert_lt(hit.end.y, view.y * 0.25, "in the top quarter, clear of the list")
	assert_almost_eq(hit.get_center().x, view.x * 0.5, 2.0, "centred over the title")


func test_a_tap_on_the_plaque_opens_the_apk_once() -> void:
	_menu.offer_update(_offer())
	await wait_process_frames(2)
	_tap(_menu.offer_rect().get_center())
	assert_eq(_opened, [APK] as Array[String], "the browser is handed the APK URL")

	_tap(Vector2(_menu.size.x * 0.5, _menu.size.y * 0.6))
	assert_eq(_opened.size(), 1, "a tap elsewhere opens nothing")

	# With touch emulation on, every tap also arrives as a mouse click; only the
	# touch counts, or one tap would open the browser twice.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _menu.offer_rect().get_center()
	_menu._input(click)
	assert_eq(_opened.size(), 1, "a mouse click is not a second tap")


func test_the_settings_page_covers_the_plaque() -> void:
	_menu.offer_update(_offer())
	await wait_process_frames(2)
	var at := _menu.offer_rect().get_center()
	(_menu.get_node(^"SettingsPanel") as SettingsPanel).visible = true
	_tap(at)
	assert_eq(_opened, [] as Array[String], "the plaque is not there to tap")


func test_taking_the_offer_down_clears_the_target() -> void:
	_menu.offer_update(_offer())
	await wait_process_frames(2)
	_menu.offer_update({})
	_tap(Vector2(_menu.size.x * 0.5, 4.0))
	assert_eq(_opened, [] as Array[String])
	assert_false(_menu.offer_rect().has_area())


func test_the_settings_page_names_the_running_build() -> void:
	var panel := _menu.get_node(^"SettingsPanel") as SettingsPanel
	var line := panel.build_line()
	assert_true(line.contains("BUILD "), "says which build: %s" % line)
	assert_eq(line, DevUpdate.running_label(BuildStamp.NAME, BuildStamp.CODE, BuildStamp.SHA))
