extends GutTest
## Walking the wardrobe page (scripts/ui/wardrobe_screen.gd): rows that change
## nothing are skipped, values cycle and are saved at once, each player keeps
## a look of their own, a tap does what the stick does, and going back goes
## back. Against its own file, never the real save.

const SCENE := preload("res://scenes/wardrobe.tscn")
const STORE := "user://test_wardrobe_screen.cfg"

var _screen: WardrobeScreen
var _left := 0


func before_each() -> void:
	_remove()
	_left = 0
	_screen = SCENE.instantiate() as WardrobeScreen
	_screen.store_path = STORE
	_screen.leave = func() -> void: _left += 1
	add_child_autofree(_screen)


func after_each() -> void:
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(STORE):
		DirAccess.remove_absolute(STORE)


func _row(id: String) -> int:
	for i: int in _screen.rows().size():
		if String(_screen.rows()[i]["id"]) == id:
			return i
	return -1


func _saved(player: int) -> CharacterLook:
	return Wardrobe.open(STORE).look(player)


func test_it_opens_on_player_one_and_the_saved_look() -> void:
	assert_eq(_screen.index(), 0)
	assert_eq(_screen.player(), Wardrobe.PLAYER_ONE)
	assert_eq(_screen.value_text(_row("figure")), "PRINCE")


func test_the_princes_hood_closes_hair_and_skin() -> void:
	assert_false(_screen.is_open(_row("hair")))
	assert_false(_screen.is_open(_row("skin")))
	assert_eq(_screen.value_text(_row("hair")), "HOODED")
	# Down from SASH goes round to the top, past the two closed rows.
	for _i: int in _row("accent"):
		_screen.move(1)
	assert_eq(_screen.index(), _row("accent"))
	_screen.move(1)
	assert_eq(_screen.index(), 0, "hair and skin were skipped")
	_screen.move(-1)
	assert_eq(_screen.index(), _row("accent"), "and skipped going up")


func test_choosing_the_heroine_opens_them_and_saves_at_once() -> void:
	_screen.move(1)
	assert_eq(_screen.index(), _row("figure"))
	_screen.adjust(1)
	assert_eq(_screen.value_text(_row("figure")), "HEROINE")
	assert_true(_screen.is_open(_row("hair")))
	assert_true(_saved(Wardrobe.PLAYER_ONE).is_heroine(), "on disk before leaving the page")

	for _i: int in 3:
		_screen.move(1)
	assert_eq(_screen.index(), _row("hair"))
	_screen.adjust(1)
	assert_eq(_saved(Wardrobe.PLAYER_ONE).index_of("hair"), 1)
	_screen.adjust(-1)
	_screen.adjust(-1)
	assert_eq(_saved(Wardrobe.PLAYER_ONE).index_of("hair"),
		CharacterLook.HAIRS.size() - 1, "stepping back past the first wraps")


func test_each_player_has_a_look_and_player_two_wears_the_seat() -> void:
	_screen.move(1)
	_screen.adjust(1) # player one: heroine
	_screen.move(-1)
	_screen.adjust(1) # now editing player two
	assert_eq(_screen.player(), Wardrobe.PLAYER_TWO)
	assert_eq(_screen.value_text(_row("figure")), "PRINCE", "player two is still the prince")
	assert_false(_screen.is_open(_row("outfit")), "player two's robe is the seat's")
	assert_eq(_screen.value_text(_row("outfit")), "SEA-GREEN")
	var preview := _screen.get_node(^"Preview") as FigurePreview
	assert_eq(preview.cloth, FighterArt.SEAT_CLOTH[1], "and the preview shows it")

	_screen.move(1)
	_screen.move(1)
	assert_eq(_screen.index(), _row("accent"), "the robe row is skipped")
	_screen.adjust(1)
	assert_eq(_saved(Wardrobe.PLAYER_TWO).index_of("accent"), 1)
	assert_true(_saved(Wardrobe.PLAYER_ONE).is_heroine(), "player one kept theirs")
	assert_eq(_saved(Wardrobe.PLAYER_ONE).index_of("accent"), 0)


func test_jump_steps_forward_and_back_leaves() -> void:
	_screen.move(1)
	_screen.confirm()
	assert_true(_saved(Wardrobe.PLAYER_ONE).is_heroine(), "jump stepped FIGURE forward")
	_screen.back()
	assert_eq(_left, 1, "sword goes back")


func test_a_tap_on_a_value_steps_it_by_side() -> void:
	await wait_process_frames(2) # the rows are laid out by the first draw
	var figure := _row("figure")
	var row := _screen._row_rects[figure]
	var value := _screen._value_rects[figure]
	assert_true(row.has_area(), "the rows were drawn")
	assert_true(_screen.tap(Vector2(value.end.x - 2.0, value.get_center().y)))
	assert_eq(_screen.index(), figure, "the tap selected the row")
	assert_true(_saved(Wardrobe.PLAYER_ONE).is_heroine(), "the right half steps forward")
	assert_true(_screen.tap(Vector2(value.position.x + 2.0, value.get_center().y)))
	assert_false(_saved(Wardrobe.PLAYER_ONE).is_heroine(), "the left half steps back")

	var hair := _screen._row_rects[_row("hair")]
	assert_true(_screen.tap(hair.get_center()), "a closed row takes the tap")
	assert_eq(_screen.index(), figure, "but cannot be selected")
	assert_false(_screen.tap(Vector2(-50.0, -50.0)), "a tap elsewhere is not a row's")


func test_the_rows_stay_clear_of_the_thumb_buttons() -> void:
	await wait_process_frames(2)
	var safe := UiLayout.safe(_screen.size)
	# TouchControls: JUMP at (right - 34, bottom - 34) r 24, SWORD at
	# (right - 82, bottom - 22) r 19, each with HIT_PADDING around it.
	var buttons: Array[Vector3] = [
		Vector3(safe.end.x - 34.0, safe.end.y - 34.0, 24.0 + TouchControls.HIT_PADDING),
		Vector3(safe.end.x - 82.0, safe.end.y - 22.0, 19.0 + TouchControls.HIT_PADDING),
	]
	for rect: Rect2 in _screen._row_rects:
		for b: Vector3 in buttons:
			var near := Vector2(clampf(b.x, rect.position.x, rect.end.x),
				clampf(b.y, rect.position.y, rect.end.y))
			assert_gt(near.distance_to(Vector2(b.x, b.y)), b.z,
				"row %s is clear of a thumb button" % rect)
