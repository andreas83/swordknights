extends GutTest
## The wardrobe survives a restart, and a bad file costs nothing worse than the
## defaults (scripts/player/wardrobe.gd).
##
## Every case runs against its own file under user://, never the real
## user://wardrobe.cfg: a test that rewrote what someone plays as would be a
## test with a side effect nobody asked for.

var _path := UserData.at("user://test_wardrobe_save.cfg")


func before_each() -> void:
	_remove()


func after_each() -> void:
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


func _heroine() -> CharacterLook:
	var look := CharacterLook.new()
	look.take_ids({"figure": "heroine", "outfit": "saffron", "accent": "pale",
		"hair": "henna", "skin": "umber"})
	return look


func _is_default(look: CharacterLook) -> bool:
	return look.equals(CharacterLook.new())


func test_the_default_is_the_prince_the_game_always_drew() -> void:
	var look := CharacterLook.new()
	assert_false(look.is_heroine())
	var art := PlayerArt.new()
	add_child_autofree(art)
	var bare := [art.cloth, art.cloth_dark, art.cloak_shade, art.accent]
	look.dress(art)
	assert_eq([art.cloth, art.cloth_dark, art.cloak_shade, art.accent], bare,
		"the default look changes no colour of a bare PlayerArt")
	assert_false(art.costume is HeroineCostume)


func test_a_look_survives_save_and_load() -> void:
	var wardrobe := Wardrobe.open(_path)
	wardrobe.set_look(Wardrobe.PLAYER_ONE, _heroine())
	var two := CharacterLook.new()
	two.take_ids({"accent": "ink"})
	wardrobe.set_look(Wardrobe.PLAYER_TWO, two)
	assert_eq(wardrobe.save(), OK)

	var again := Wardrobe.open(_path)
	assert_true(again.look(Wardrobe.PLAYER_ONE).equals(_heroine()),
		"player one: %s" % again.look(Wardrobe.PLAYER_ONE).to_ids())
	assert_true(again.look(Wardrobe.PLAYER_TWO).equals(two),
		"player two: %s" % again.look(Wardrobe.PLAYER_TWO).to_ids())
	assert_false(again.look(Wardrobe.PLAYER_TWO).is_heroine(), "the two are kept apart")


func test_a_look_is_handed_out_as_a_copy() -> void:
	var wardrobe := Wardrobe.open(_path)
	wardrobe.look(Wardrobe.PLAYER_ONE).set_index("figure", CharacterLook.Figure.HEROINE)
	assert_false(wardrobe.look(Wardrobe.PLAYER_ONE).is_heroine(),
		"only set_look() changes what is kept")


func test_a_missing_file_is_the_defaults() -> void:
	var wardrobe := Wardrobe.new()
	wardrobe.path = _path
	assert_false(wardrobe.load_from_disk(), "there was nothing to load")
	assert_true(_is_default(wardrobe.look(Wardrobe.PLAYER_ONE)))
	assert_true(_is_default(wardrobe.look(Wardrobe.PLAYER_TWO)))


func test_a_file_that_does_not_parse_is_the_defaults() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("[player_one\nfigure = = \"heroine\n\u0000ÿ garbage {{{")
	file.close()
	var wardrobe := Wardrobe.new()
	wardrobe.path = _path
	assert_false(wardrobe.load_from_disk(), "a corrupt file is not a loaded one")
	# ConfigFile logs the parse error itself. It is the expected one, and it is
	# the only one: the wardrobe adds no error of its own for a player to see.
	assert_engine_error("ConfigFile parse error", "the engine noticed the corruption")
	assert_eq(get_errors().size(), 1, "and nothing else went wrong")
	assert_true(_is_default(wardrobe.look(Wardrobe.PLAYER_ONE)))
	assert_true(_is_default(wardrobe.look(Wardrobe.PLAYER_TWO)))


func test_nonsense_falls_back_one_field_at_a_time() -> void:
	var file := ConfigFile.new()
	file.set_value("player_one", "figure", "heroine")
	file.set_value("player_one", "outfit", "tartan") # no such outfit
	file.set_value("player_one", "accent", 3) # a number, not an id
	file.set_value("player_one", "hair", ["henna"]) # the wrong type
	file.set_value("player_one", "skin", "umber")
	file.set_value("somebody_else", "figure", "heroine") # an unknown section
	assert_eq(file.save(_path), OK)

	var look := Wardrobe.open(_path).look(Wardrobe.PLAYER_ONE)
	var plain := CharacterLook.new()
	assert_true(look.is_heroine(), "a good field is kept")
	assert_eq(look.index_of("skin"), 3, "and another")
	for field: String in ["outfit", "accent", "hair"]:
		assert_eq(look.index_of(field), plain.index_of(field), "%s fell back" % field)
	assert_true(_is_default(Wardrobe.open(_path).look(Wardrobe.PLAYER_TWO)),
		"a missing section is the default")


func test_the_file_names_ids_not_positions() -> void:
	var wardrobe := Wardrobe.open(_path)
	wardrobe.set_look(Wardrobe.PLAYER_ONE, _heroine())
	wardrobe.save()
	var file := ConfigFile.new()
	assert_eq(file.load(_path), OK)
	assert_eq(file.get_value("player_one", "figure"), "heroine")
	assert_eq(file.get_value("player_one", "hair"), "henna")
