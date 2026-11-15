extends GutTest
## Every pose renders as every figure: every Player state and every Fighter
## state, the prince, the heroine, the stick avatar and the 3D princess, with no
## engine error and inside the box a figure of that size can occupy
## (scripts/player/costume.gd).
##
## The states are read from the enums, not listed here. A pose added to
## player_art.gd or sword_poses.gd is a state added to Player.State, and so a
## pose this test draws on every figure without anyone remembering to add it --
## which is the promise the costume layer makes, held. The figures are read
## from CharacterLook.FIGURES for the same reason: a fifth figure is drawn
## through every pose here the day it is added to the list.
##
## Godot refuses to triangulate a polygon that crosses itself and says so as an
## engine error, which GUT fails the test on; that is how a costume plane that
## folds over in some pose shows up here. The frame counter is the guard that
## the drawing happened at all: a headless run that never called _draw() would
## otherwise pass having drawn nothing.
##
## The prince draws through PlayerArt's own helpers and so keeps no box; every
## other costume records what it drew, and that box is held to the envelope.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const FIGHTER_SCENE := preload("res://scenes/fighter.tscn")
## Around the feet, in the art's own units. The figure is 22 tall and its
## widest pose -- a lunge with the cloth streaming -- reaches about 20 either
## side; a plane outside this box has come loose from the rig.
const ENVELOPE := Rect2(-30.0, -34.0, 60.0, 40.0)
## The costume class each figure id is dressed in. The princess is the owner's
## rigged model once its file is in the project (CharacterLook.princess()).
var costumes := {
	"prince": Costume, "heroine": HeroineCostume, "stick": StickCostume,
	"princess": RiggedCostume if RiggedCostume.available() else PrincessCostume,
}


func _figures() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in CharacterLook.FIGURES:
		out.append(String(entry["id"]))
	return out


func _look(figure: String) -> CharacterLook:
	var look := CharacterLook.new()
	look.take_ids({"figure": figure})
	return look


func test_every_figure_has_its_costume() -> void:
	for figure: String in _figures():
		assert_true(costumes.has(figure), "%s is in this test's table" % figure)


func test_every_player_state_draws_as_every_figure() -> void:
	var checked := 0
	for figure: String in _figures():
		var player := PLAYER_SCENE.instantiate() as Player
		add_child_autofree(player)
		player.set_physics_process(false)
		player.position = Vector2(160.0, 120.0)
		var art := player.get_node(^"PlayerArt") as PlayerArt
		_look(figure).dress(art)
		assert_eq(art.costume.get_script(), costumes.get(figure),
			"%s wears its own costume" % figure)
		for state: int in Player.State.values():
			player.state = state as Player.State
			player.state_time = 0.12
			player.velocity = Vector2(60.0, 80.0)
			checked += await _drew(art, "%s %s" % [figure, Player.State.keys()[state]])
	assert_eq(checked, Player.State.size() * _figures().size(), "every state, every figure")


func test_every_fighter_state_draws_as_every_figure() -> void:
	var checked := 0
	for figure: String in _figures():
		for seat: int in 2:
			var fighter := FIGHTER_SCENE.instantiate() as Fighter
			add_child_autofree(fighter)
			fighter.setup(seat, null)
			var art := FighterArt.dress(fighter, seat, _look(figure))
			fighter.respawn_at(Vector2(160.0, 120.0), 1 - seat * 2)
			fighter.set_physics_process(false)
			for state: int in Fighter.State.values():
				fighter.state = state as Fighter.State
				fighter.state_frame = 6
				fighter.grounded = true
				checked += await _drew(art, "%s seat %d %s" % [
					figure, seat, Fighter.State.keys()[state]])
	assert_eq(checked, Fighter.State.size() * _figures().size() * 2,
		"every fighter state, every figure, both seats")


## Waits for the art to draw a frame, and checks what it drew. 1 if it drew.
func _drew(art: PlayerArt, what: String) -> int:
	var before := art.costume.frames_drawn
	art.queue_redraw()
	await wait_process_frames(2)
	var drew := art.costume.frames_drawn > before
	assert_true(drew, "%s was drawn" % what)
	if art.costume.get_script() != Costume:
		var box := art.costume.drawn
		assert_true(box.has_area(), "%s drew some planes" % what)
		assert_true(ENVELOPE.encloses(box), "%s stays on its rig: %s" % [what, box])
	return 1 if drew else 0
