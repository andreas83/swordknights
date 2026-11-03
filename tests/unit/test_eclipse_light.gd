extends GutTest
## The Eclipse's third phase puts the Vault out, and the dark never hides what
## must be read (docs/campaign.md, "How he uses the light"): the world's grade
## goes down toward WorldGrade.DARK while everything in the lit group -- the
## prince and the King -- is lifted back to its own light by the inverse, and
## the kept sun goes to an ember with its light in his disc. The finale brings
## the light back. Played in the real Vault, set at night.

const EclipseSupport := preload("res://tests/eclipse_support.gd")
const GAME_SCENE := "res://scenes/game.tscn"

var _game: Game
var _king: Eclipse


func _arena(phase: int) -> void:
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_path = EclipseSupport.LEVEL
	add_child_autofree(_game)
	await wait_physics_frames(2)
	for node: Node in _game.get_node("Entities").get_children():
		if node is Eclipse:
			_king = node as Eclipse
	_king.resume(phase)
	_game.player.position = Vector2(_king.position.x - 120.0, _king.floor_y)
	_game.player.velocity = Vector2.ZERO
	_game.player.input = EclipseSupport.Program.new()


func _grade() -> WorldGrade:
	return get_tree().get_first_node_in_group(WorldGrade.GROUP) as WorldGrade


func _sun() -> KeptSun:
	return get_tree().get_first_node_in_group(KeptSun.GROUP) as KeptSun


func test_the_eclipse_puts_the_vault_out_and_lifts_what_must_be_read() -> void:
	await _arena(Eclipse.Phase.ECLIPSE)
	var grade := _grade()
	assert_not_null(grade, "the Vault is graded: it is night")
	assert_eq(grade.dim, 0.0, "lit while he waits under the kept sun")
	await wait_until(func() -> bool: return _king.state == Eclipse.State.STALK, 5.0)
	await wait_process_frames(2)
	assert_almost_eq(grade.dim, 1.0, 0.001, "put out once he has raised the disc")
	var hour: Color = grade.grade["world"]
	assert_almost_eq(grade.color.g, hour.g * WorldGrade.DARK, 0.001,
		"the world multiplied down past the night")
	var lift := grade.lift()
	assert_almost_eq(_game.player.modulate.g * grade.color.g, 1.0, 0.001,
		"the prince lifted back to his own light")
	assert_almost_eq(_king.modulate.g, lift.g, 0.001, "and the King")
	assert_eq(_sun().brightness(), 0.0, "the kept sun an ember")


func test_the_finale_brings_the_light_back() -> void:
	await _arena(Eclipse.Phase.FINALE)
	await wait_until(func() -> bool: return _king.state == Eclipse.State.GATHER, 5.0)
	await wait_process_frames(2)
	assert_almost_eq(_grade().dim, 0.0, 0.001, "the vault lit again for the last blow")
	assert_gt(_sun().brightness(), 0.0, "the kept sun burning, poured into the disc")
