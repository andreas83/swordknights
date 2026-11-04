extends GutTest
## The Last Light's title cards (Hud.show_card(), Campaign.card()).
##
## The story is told without dialogue, so the cards are most of what is ever
## written (docs/campaign.md, "Story without words"). Held here: every
## chapter in the catalogue has a numeral, a name and an epigraph, and the
## finale and the ending have their own -- the finale its chapter's numeral
## and no epigraph, the ending its two lines; a chapter opens on its card, in
## the reserved band; the card holds on its own clock and then goes; the
## first press of any verb takes it away before the jump it starts is at its
## height, without eating the jump; and a press already held when the card
## opens -- the jump that chose the chapter -- does not, until the card has
## been read (Hud.CARD_READ), when a verb still held is play.

const SCENE := "res://scenes/campaign_game.tscn"
var _progress := UserData.at("user://test_title_cards.cfg")
var _dir := UserData.at("user://test_title_cards")
const LEVEL := """; Alpha



 @          D
##############
"""


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var file := FileAccess.open(_dir.path_join("alpha.txt"), FileAccess.WRITE)
	file.store_string(LEVEL)
	file.close()


func after_each() -> void:
	for action: StringName in Hud.PLAY_ACTIONS:
		Input.action_release(action)
	Campaign.reset()
	for path: String in [_progress, _dir.path_join("alpha.txt")]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_every_chapter_has_a_numeral_a_name_and_an_epigraph() -> void:
	var chapters := 0
	for index: int in Campaign.count():
		var card := Campaign.card(index)
		var title := String(card["title"])
		assert_ne(title, "", "entry %d has a name" % index)
		if bool(card["finale"]):
			assert_eq(card["numeral"], "", "%s: a finale has no numeral of its own" % title)
			assert_ne(Campaign.numeral_of(index), "", "but is its chapter's")
			assert_eq(card["epigraph"], "", "%s: and nothing said under it" % title)
			continue
		chapters += 1
		assert_ne(card["numeral"], "", "%s has a numeral" % title)
		assert_ne(card["epigraph"], "", "%s has an epigraph" % title)
		assert_eq(card["epigraph"], Campaign.entry(index)["epigraph"],
			"%s's epigraph is the catalogue's own field" % title)
	assert_eq(chapters, 5, "five chapters")
	assert_ne(String(Campaign.ENDING["title"]), "", "the ending has a name")
	assert_ne(String(Campaign.ENDING["epigraph"]), "", "and a line under it")


func test_the_epigraphs_are_the_bibles() -> void:
	var lines := []
	for index: int in Campaign.count():
		lines.append(String(Campaign.card(index)["epigraph"]).to_upper())
	assert_eq(lines, ["THE LAST HOUR OF LIGHT", "THE GATES ARE FALLING",
		"THE OLD STONE IS TIRED", "CATCH THE LAST LIGHT", "WHAT THE CITY KEPT", ""],
		"docs/campaign.md, 'Story without words'")
	assert_eq(String(Campaign.ENDING["epigraph"]).to_upper(), "THE SUN REMEMBERS")


func test_every_card_fits_the_narrowest_screen() -> void:
	var room := UiLayout.banner(Vector2(320, 180)).size.x - UiLayout.GUTTER * 2.0
	for index: int in Campaign.count():
		var card := Campaign.card(index)
		var title := String(card["title"]).to_upper()
		assert_lt(UiFont.width(title, UiFont.Cut.DISPLAY), room, "%s fits at 320" % title)
		assert_lt(UiFont.width(String(card["epigraph"]).to_upper(), UiFont.Cut.TEXT), room,
			"and so does its epigraph")


func _start() -> CampaignGame:
	Campaign.use_for_test([{"id": "alpha", "numeral": "IV", "title": "Alpha",
		"epigraph": "Catch the last light", "time": "afternoon",
		"file": _dir.path_join("alpha.txt"), "finale": false}])
	var campaign := (load(SCENE) as PackedScene).instantiate() as CampaignGame
	campaign.progress_path = _progress
	campaign.leave = func() -> void: pass
	add_child_autofree(campaign)
	await wait_physics_frames(2)
	return campaign


func test_a_chapter_opens_on_its_card_and_it_goes_by_itself() -> void:
	var hud := (await _start()).game().hud
	assert_eq(hud.card(), {"numeral": "IV", "title": "ALPHA",
		"epigraph": "CATCH THE LAST LIGHT", "finale": false}, "the catalogue's card, not the file's")
	assert_true(hud.title_showing(), "on entry")
	await wait_seconds(Hud.CARD_EPIGRAPH_AT + Hud.CARD_EPIGRAPH_FADE)
	assert_almost_eq(hud.title_alpha(), 1.0, 0.01, "set and held")
	await wait_seconds(Hud.CARD_HOLD + Hud.TITLE_FADE - Hud.CARD_EPIGRAPH_AT
		- Hud.CARD_EPIGRAPH_FADE + 0.2)
	assert_false(hud.title_showing(), "and gone on its own clock")
	assert_false(hud.title_skipped(), "without being asked")


func test_the_first_jump_takes_it_away_and_is_still_a_jump() -> void:
	var game := (await _start()).game()
	await wait_seconds(Hud.CARD_EPIGRAPH_AT + Hud.CARD_EPIGRAPH_FADE)
	assert_almost_eq(game.hud.title_alpha(), 1.0, 0.01, "the card is up")
	var floor_y := game.player.global_position.y
	Input.action_press(&"jump")
	var frames := 0
	var gone_at := -1
	var apex_at := -1
	var left_floor := false
	while frames < 90 and (gone_at < 0 or apex_at < 0):
		await wait_physics_frames(1)
		frames += 1
		if gone_at < 0 and game.hud.title_alpha() <= 0.0:
			gone_at = frames
		if game.player.global_position.y < floor_y - 4.0:
			left_floor = true
		if left_floor and apex_at < 0 and game.player.velocity.y >= 0.0:
			apex_at = frames
	Input.action_release(&"jump")
	assert_true(game.hud.title_skipped(), "the press took it away")
	assert_true(left_floor, "and the prince jumped: the press was not eaten")
	assert_gt(gone_at, 0, "the card went")
	assert_gt(apex_at, 0, "the jump peaked")
	assert_lt(gone_at, apex_at, "the card is gone before the jump is at its height")


func test_a_press_already_held_when_it_opens_does_not_skip_it() -> void:
	Input.action_press(&"jump")
	var hud := (await _start()).game().hud
	await wait_seconds(Hud.CARD_EPIGRAPH_AT + Hud.CARD_EPIGRAPH_FADE)
	assert_false(hud.title_skipped(), "the jump that chose the chapter was not aimed at it")
	assert_almost_eq(hud.title_alpha(), 1.0, 0.01, "so the card is read")
	Input.action_release(&"jump")
	await wait_physics_frames(2)
	Input.action_press(&"move_right")
	await wait_seconds(Hud.SKIP_FADE + 0.1)
	assert_true(hud.title_skipped(), "a fresh press of any verb is")
	assert_false(hud.title_showing())


func test_a_verb_held_since_the_card_opened_is_play_once_it_is_read() -> void:
	Input.action_press(&"move_right")
	var hud := (await _start()).game().hud
	await wait_seconds(Hud.CARD_READ - 0.4)
	assert_false(hud.title_skipped(), "running in through the wipe does not skip it unread")
	await wait_seconds(0.4 + Hud.SKIP_FADE + 0.1)
	assert_true(hud.title_skipped(), "but once read, the run takes it away")
	assert_false(hud.title_showing(), "rather than running under it for its whole hold")


func test_the_finale_card_is_its_own() -> void:
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.show_card(Campaign.card(Campaign.count() - 1))
	var card := hud.card()
	assert_true(bool(card["finale"]), "the eclipse in the numeral's place")
	assert_eq(card["title"], "THE ECLIPSE")
	assert_eq(card["epigraph"], "")


func test_a_plain_title_is_timed_as_it_always_was() -> void:
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.show_title("level_gen_7")
	assert_eq(hud.card()["title"], "LEVEL GEN 7")
	assert_almost_eq(hud.title_alpha(), 1.0, 0.01, "up at once, as Endless's has been")
	await wait_seconds(Hud.TITLE_HOLD + Hud.TITLE_FADE + 0.2)
	assert_false(hud.title_showing())
