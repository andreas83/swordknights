extends GutTest
## Phases already won stay won through a death; the respawn puts the prince
## back at the start of the phase he is in (docs/campaign.md, "Decided by the
## owner"). Played in the real Vault, through Game's real respawn, where every
## foe is put back whole -- the King included -- so what is held here is that
## his post's memory (EntitySite.memory) is what brings the phase back:
##
## - a phase won and then a death: the King placed again is in the next phase,
##   waiting under the kept sun, and rises into its start when the prince
##   drops back into the vault;
## - a death part-way through a phase: that phase again from its start, its
##   wounds healed;
## - the gallery hearts, taken once, stay taken;
## - a restart -- JUMP TO REPLAY -- forgets it all: the first phase again.
##
## Each death is announced to the death watch (tests/death_watch.gd).

const DeathWatch := preload("res://tests/death_watch.gd")
const EclipseSupport := preload("res://tests/eclipse_support.gd")
const GAME_SCENE := "res://scenes/game.tscn"

var _game: Game


func _king() -> Eclipse:
	for node: Node in _game.get_node("Entities").get_children():
		if node is Eclipse and not node.is_queued_for_deletion():
			return node as Eclipse
	return null


## A King other than the one with `before`'s id, in a game back in play. By
## id: the King before the respawn is freed by it, and a callable holding him
## would be holding nothing.
func _respawned(before: int) -> bool:
	var now := _king()
	return now != null and now.get_instance_id() != before \
		and _game.phase == Game.Phase.PLAYING


func test_won_phases_outlive_a_death_and_a_restart_forgets_them() -> void:
	DeathWatch.expect_deaths(2)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_path = EclipseSupport.LEVEL
	add_child_autofree(_game)
	var pilot := EclipseSupport.Pilot.new(_game)
	_game.player.input = pilot
	await wait_physics_frames(2)

	# The fight from the antechamber, phase 1 won the way it is meant to be:
	# from the gallery, onto his crown. A gallery heart is taken on the way in.
	var first := _king()
	await wait_until(func() -> bool: return first.phase == Eclipse.Phase.BURNING, 40.0)
	assert_eq(first.phase, Eclipse.Phase.BURNING, "the Shield won")
	assert_eq(_game.relics, 1, "the west gallery's heart taken")

	# Then a death before the Burning is won.
	await wait_until(func() -> bool: return first.state == Eclipse.State.REST, 5.0)
	_game.player.input = EclipseSupport.Program.new()
	var first_id := first.get_instance_id()
	_game.player.kill()
	await wait_until(func() -> bool: return _respawned(first_id), 5.0)
	var second := _king()
	assert_ne(second.get_instance_id(), first_id, "the respawn put a new King at the post")
	assert_eq(second.phase, Eclipse.Phase.BURNING, "in the phase he had come to: the Shield stays won")
	assert_eq(second.state, Eclipse.State.AWAIT, "waiting under the kept sun")
	assert_eq(second.position, Vector2(second.sun_x, second.floor_y), "at his post")
	assert_eq(second.wounds, 0, "the phase whole")
	assert_eq(_game.relics, 1, "the heart stays taken")
	assert_lt(_game.player.position.y, second.gallery_y, "the prince back in the antechamber")

	# Down into the vault again: he rises into the start of the Burning, and
	# is wounded once.
	pilot = EclipseSupport.Pilot.new(_game)
	_game.player.input = pilot
	await wait_until(func() -> bool: return second.state == Eclipse.State.REST, 8.0)
	assert_eq(second.volley, 0, "from its first volley")
	await wait_until(func() -> bool: return second.wounds >= 1, 10.0)
	assert_eq(second.wounds, 1, "a wound into the Burning")

	# A death part-way: the Burning again from its start, the wound healed.
	_game.player.input = EclipseSupport.Program.new()
	var second_id := second.get_instance_id()
	_game.player.kill()
	await wait_until(func() -> bool: return _respawned(second_id), 5.0)
	var third := _king()
	assert_eq(third.phase, Eclipse.Phase.BURNING, "still the Burning")
	assert_eq(third.wounds, 0, "from its start: a wound is not a phase")

	# A restart forgets every phase.
	_game._restart()
	await wait_physics_frames(2)
	var fourth := _king()
	assert_eq(fourth.phase, Eclipse.Phase.SHIELD, "a restart is the Shield again")
	assert_eq(_game.relics, 0, "with the hearts back on the galleries")
