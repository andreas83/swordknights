extends GutTest
## The two duel seats stay crimson and sea-green whatever either player wears
## (scripts/duel/fighter_art.gd, scripts/player/character_look.gd).
##
## The guarantee has two halves, and each is checked over every look there is
## -- both figures, every outfit, sash, hair and skin -- rather than over a few
## picked by hand, because the case that breaks it is the one nobody picked:
##
## 1. A seat's robe planes are its team colour, after any look is put on.
## 2. No colour a player can choose belongs to either team, so a customised
##    seat can never carry the other seat's colour anywhere on the figure.
##
## And the online half: a phone shows its own seat in its player's look and
## the other seat in that seat's default, without the protocol carrying either.

const FIGHTER_SCENE := preload("res://scenes/fighter.tscn")
const ONLINE_SCENE := preload("res://scenes/duel_match_online.tscn")
const STORE := "user://test_duel_seats_distinct.cfg"


func after_each() -> void:
	if FileAccess.file_exists(STORE):
		DirAccess.remove_absolute(STORE)


func _team(seat: int) -> Array[Color]:
	return [FighterArt.SEAT_CLOTH[seat], FighterArt.SEAT_CLOTH_DARK[seat],
		FighterArt.SEAT_CLOAK[seat]]


## Every combination of every option: 2 x 4 x 4 x 4 x 4.
func _every_look() -> Array[CharacterLook]:
	var looks: Array[CharacterLook] = [CharacterLook.new()]
	for field: String in CharacterLook.FIELDS:
		var grown: Array[CharacterLook] = []
		for base: CharacterLook in looks:
			for i: int in CharacterLook.options(field).size():
				var look := base.duplicate_look()
				look.set_index(field, i)
				grown.append(look)
		looks = grown
	return looks


## The colours on a dressed figure that a player chose rather than the seat.
func _chosen(art: PlayerArt) -> Array[Color]:
	var out: Array[Color] = [art.accent]
	var heroine := art.costume as HeroineCostume
	if heroine != null:
		out.append_array([heroine.hair, heroine.hair_dark, heroine.skin, heroine.skin_dark])
	return out


func test_the_two_teams_share_no_colour() -> void:
	for colour: Color in _team(0):
		assert_false(_team(1).has(colour), "%s is in both teams" % colour.to_html())


func test_every_look_keeps_each_seat_in_its_colour() -> void:
	var looks := _every_look()
	assert_eq(looks.size(), 2 * 4 * 4 * 4 * 4, "walked every look")
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	add_child_autofree(fighter)
	fighter.setup(0, null)
	var bad: Array[String] = []
	for seat: int in 2:
		for look: CharacterLook in looks:
			var art := FighterArt.dress(fighter, seat, look)
			var planes: Array[Color] = [art.cloth, art.cloth_dark, art.cloak_shade]
			if planes != _team(seat):
				bad.append("seat %d robe in %s" % [seat, look.to_ids()])
			for colour: Color in _chosen(art):
				if _team(0).has(colour) or _team(1).has(colour):
					bad.append("seat %d wears team colour %s in %s"
						% [seat, colour.to_html(), look.to_ids()])
	assert_eq(bad, [] as Array[String], "\n".join(bad.slice(0, 8)))


func test_the_seat_colour_wins_whichever_order_things_happen_in() -> void:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	fighter.setup(1, null)
	var look := CharacterLook.new()
	look.take_ids({"figure": "heroine", "outfit": "saffron"})
	# Dressed before the fighter is in the tree: _bind() re-imposes the seat.
	var art := FighterArt.dress(fighter, 1, look)
	add_child_autofree(fighter)
	await wait_process_frames(1)
	assert_eq(art.cloth, FighterArt.SEAT_CLOTH[1], "still sea-green once bound")
	assert_true(art.costume is HeroineCostume, "and still the heroine")


func test_online_shows_my_look_on_my_seat_and_the_default_on_theirs() -> void:
	var wardrobe := Wardrobe.open(STORE)
	var mine := CharacterLook.new()
	mine.take_ids({"figure": "heroine", "accent": "fire", "hair": "gold"})
	wardrobe.set_look(Wardrobe.PLAYER_ONE, mine)
	var unused := CharacterLook.new()
	unused.take_ids({"figure": "heroine", "accent": "ink"})
	wardrobe.set_look(Wardrobe.PLAYER_TWO, unused)
	wardrobe.save()

	var scene := ONLINE_SCENE.instantiate()
	scene.set("wardrobe_path", STORE)
	assert_eq(scene.get("wardrobe_path"), STORE, "the seam took")
	add_child_autofree(scene)
	await wait_process_frames(1)

	# In the lobby: nobody is seated, so both seats are their defaults.
	for slot: int in 2:
		assert_true(scene.call("look_for", slot).equals(CharacterLook.new()),
			"lobby seat %d is the default" % slot)

	# Seated as the guest, in the sea-green seat: player one's look goes on
	# seat two -- a phone is one player -- and seat one is the default.
	scene.set("_online", true)
	scene.call("_on_seated", 1)
	assert_true(scene.call("look_for", 1).equals(mine), "my seat wears my look")
	assert_true(scene.call("look_for", 0).equals(CharacterLook.new()),
		"their seat wears its default, not their choice, which this phone never saw")
	var seats: Array = scene.get_node(^"World/Match").get("seats")
	var art := (seats[1] as DuelSeat).node.get_node(^"FighterArt") as FighterArt
	assert_true(art.costume is HeroineCostume, "and it was put on")
	assert_eq(art.cloth, FighterArt.SEAT_CLOTH[1], "in the seat's colour")
	scene.set("_online", false)
