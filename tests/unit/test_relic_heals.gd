extends GutTest
## A relic gives back one heart, and the corner shows it the way it shows one
## being lost.
##
## Plays the real game scene, because the part that went wrong before was not
## any one class but the wiring between them: Hud burned a lost mark white in
## its unit test, and in play it was never told a heart had gone, so the flash
## never fired. These cases go through Player, Game and Hud together.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")

## The prince at column 1, a relic two tiles to his right.
const SHRINE := """; Shrine








 @ *            D
###################
###################
"""


class ScriptedInput extends PlayerInput:
	var bits := 0

	func poll() -> void:
		apply_bits(bits)


var _game: Game
var _input: ScriptedInput


func before_each() -> void:
	var data := AsciiLevel.new()
	data.parse(SHRINE)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	_input = ScriptedInput.new()
	_game.player.input = _input
	await wait_physics_frames(4)


## Holds right until the relic is taken, or gives up after two seconds.
func _walk_into_the_relic() -> void:
	_input.bits = PlayerInput.BIT_RIGHT
	for _frame: int in 120:
		await wait_physics_frames(1)
		if _game.relics > 0:
			break
	_input.bits = 0


func test_a_hit_reaches_the_corner() -> void:
	assert_true(_game.player.damage(1), "the hit lands")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH - 1)
	assert_eq(_game.hud.health, Tuning.MAX_HEALTH - 1, "the HUD is told about a hit")
	assert_gt(_game.hud.get("_hurt_pulse"), 0.0, "and the lost mark burns")


func test_a_relic_heals_one_heart() -> void:
	_game.player.damage(1)
	await wait_physics_frames(30)
	await _walk_into_the_relic()
	assert_eq(_game.relics, 1, "the relic was taken")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "and gave the heart back")
	assert_eq(_game.hud.health, Tuning.MAX_HEALTH, "the HUD shows it")
	assert_gt(_game.hud.get("_heal_pulse"), 0.0, "and the gained mark burns")
	assert_eq(_game.hud.get("_hurt_pulse"), 0.0, "a gain is not a loss")


func test_a_relic_at_full_health_is_only_a_relic() -> void:
	await _walk_into_the_relic()
	assert_eq(_game.relics, 1, "the relic still counts")
	assert_eq(_game.player.health, Tuning.MAX_HEALTH, "no heart past the maximum")
	assert_eq(_game.hud.get("_heal_pulse"), 0.0, "and the corner does not claim one")
	assert_gt(_game.hud.get("_relic_pulse"), 0.0, "only the relic count pops")


func test_healing_is_not_a_revival() -> void:
	DeathWatch.expect_deaths(1)
	_game.player.kill()
	assert_false(_game.player.heal(1), "a body that is down stays down")
	assert_eq(_game.player.health, 0)


func test_the_gained_mark_blinks_then_stays_lit() -> void:
	var hud: Hud = autofree(Hud.new())
	hud.update_model(2, 3, 0, 1)
	hud.update_model(3, 3, 1, 1)
	var gained := 2
	var seen_dark := false
	var seen_white := false
	var pulse: float = hud.get("_heal_pulse")
	while pulse > 0.0:
		var lit: bool = hud.call("_tally_lit", gained)
		seen_dark = seen_dark or not lit
		seen_white = seen_white or bool(hud.call("_tally_burning", gained))
		hud._process(1.0 / 60.0)
		pulse = hud.get("_heal_pulse")
	assert_true(seen_white and seen_dark, "it blinks white, like a lost mark does")
	assert_true(hud.call("_tally_lit", gained), "and then stays lit")
	assert_false(hud.call("_tally_burning", gained), "and no longer white")


func test_a_refill_is_not_a_heal() -> void:
	var hud: Hud = autofree(Hud.new())
	hud.update_model(1, 3, 2, 3)
	hud.set("_hurt_pulse", 0.0)
	hud.update_model(3, 3, 2, 3, true)
	assert_eq(hud.health, 3, "the numbers are taken")
	assert_eq(hud.get("_heal_pulse"), 0.0, "a respawn at a torch is not a heal")
	assert_eq(hud.get("_hurt_pulse"), 0.0)
	assert_eq(hud.get("_relic_pulse"), 0.0)
