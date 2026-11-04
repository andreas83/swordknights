extends GutTest
## The chapter select (scripts/ui/chapter_select.gd), on a campaign of its
## own: two chapters built, a third not, and a finale.
##
## Held here: CONTINUE is the first row, the cursor starts on it, and it goes
## where the progress says; a locked row says LOCKED and a row still being
## built says TO COME, and jump on either plays nothing; a cleared row shows
## its best time, and its caption the bests in full; a tap selects and a tap
## on the selected row plays; sword goes back.

var _path := UserData.at("user://test_chapter_select.cfg")
const SCENE := "res://scenes/chapter_select.tscn"

var _entries: Array[Dictionary] = [
	{"id": "alpha", "numeral": "I", "title": "The Alpha", "epigraph": "First light",
		"time": "afternoon", "file": "res://levels/level_01.txt", "finale": false},
	{"id": "beta", "numeral": "II", "title": "The Beta", "epigraph": "Second light",
		"time": "golden", "file": "res://levels/level_01.txt", "finale": false},
	{"id": "gamma", "numeral": "III", "title": "The Gamma", "epigraph": "",
		"time": "dusk", "file": "", "finale": false},
	{"id": "omega", "numeral": "", "title": "The Omega", "epigraph": "",
		"time": "night", "file": "", "finale": true},
]

var _played: Array[int] = []
var _left := 0


func before_each() -> void:
	Campaign.use_for_test(_entries)
	_remove()
	_played.clear()
	_left = 0


func after_each() -> void:
	Campaign.reset()
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func _page() -> ChapterSelect:
	var page := (load(SCENE) as PackedScene).instantiate() as ChapterSelect
	page.store_path = _path
	page.play = func(index: int) -> void: _played.append(index)
	page.leave = func() -> void: _left += 1
	add_child_autofree(page)
	return page


func _clear_alpha(seconds: float) -> void:
	var progress := CampaignProgress.open(_path)
	progress.record_clear(0, seconds, 4, 6, 1, 3)
	progress.save()


func _row_of(page: ChapterSelect, entry: int) -> int:
	for row: int in page.rows().size():
		if not bool(page.rows()[row]["continue"]) and page.entry_of(row) == entry:
			return row
	return -1


func test_continue_is_first_and_goes_where_the_progress_says() -> void:
	var page := _page()
	assert_eq(page.index(), 0, "the cursor starts on CONTINUE")
	assert_eq(page.row_title(0), "CONTINUE")
	assert_eq(page.row_value(0), "I  THE ALPHA", "a fresh campaign continues at chapter I")
	assert_eq(page.rows().size(), 1 + _entries.size(), "then every entry")
	page.confirm()
	assert_eq(_played, [0] as Array[int], "jump plays it")
	assert_eq(Campaign.selected, 0)


func test_a_cleared_chapter_shows_its_bests_and_continue_moves_on() -> void:
	_clear_alpha(62.4)
	var page := _page()
	assert_eq(page.row_value(0), "II  THE BETA", "CONTINUE moves on to chapter II")
	var alpha := _row_of(page, 0)
	assert_eq(page.row_value(alpha), "1:02.4", "chapter I shows its best time")
	var lines := page.caption(alpha)
	assert_eq(lines[0][0], "LATE AFTERNOON  ·  FIRST LIGHT", "the hour and the epigraph")
	assert_eq(lines[1][0], "BEST 1:02.4  ·  RELICS 4/6  ·  SECRETS 1/3", "the bests in full")
	assert_eq(page.row_value(_row_of(page, 1)), "NEW", "chapter II is open and unplayed")
	page.confirm()
	assert_eq(_played, [1] as Array[int], "CONTINUE plays chapter II")


func test_locked_and_unbuilt_rows_say_so_and_play_nothing() -> void:
	var page := _page()
	var beta := _row_of(page, 1)
	assert_eq(page.row_value(beta), "LOCKED")
	assert_eq(page.caption(beta)[1][0], "CLEAR THE ALPHA TO OPEN IT")
	var gamma := _row_of(page, 2)
	assert_eq(page.row_value(gamma), "TO COME")
	assert_eq(page.caption(gamma)[1][0], "STILL BEING BUILT")
	assert_eq(page.row_value(_row_of(page, 3)), "TO COME", "the finale too")
	for row: int in [beta, gamma]:
		while page.index() != row:
			page.move(1)
		assert_false(page.is_open(row), "row %d cannot be played" % row)
		page.confirm()
	assert_eq(_played, [] as Array[int], "and jump on it plays nothing")


func test_a_tap_selects_and_a_second_tap_plays() -> void:
	var page := _page()
	await wait_process_frames(2)
	var alpha := _row_of(page, 0)
	var rect: Rect2 = page._row_rects[alpha]
	assert_true(page.tap(rect.get_center()), "the tap landed on chapter I")
	assert_eq(page.index(), alpha, "and selected it")
	assert_eq(_played, [] as Array[int], "without playing it")
	assert_true(page.tap(rect.get_center()))
	assert_eq(_played, [0] as Array[int], "the second tap plays it")
	assert_false(page.tap(Vector2(-50.0, -50.0)), "a tap off the list is not a row")


func test_sword_goes_back() -> void:
	var page := _page()
	page.back()
	assert_eq(_left, 1)


func test_times_read_like_a_clock() -> void:
	assert_eq(ChapterSelect.format_time(62.44), "1:02.4")
	assert_eq(ChapterSelect.format_time(5.0), "0:05.0")
	assert_eq(ChapterSelect.format_time(3599.96), "60:00.0", "rounding carries")
	assert_eq(ChapterSelect.format_time(CampaignProgress.NO_TIME), "--")
