extends GutTest
## A hitstop dies with the scene it was struck in (Flow.enter()).
##
## Flow outlives every scene, and so did its hitstop: a kill on the frame
## before a door, or on the last frame of a test, froze the next level's first
## frames, and everything that level did was late by as many. Found by the
## Sun Terrace's frozen clear run, which died at the spike pit when it ran
## after tests/unit/test_specials.gd and cleared when it ran alone.

const GAME_SCENE := "res://scenes/game.tscn"
const ROOM := """; Hitstop Room



  @                       D
############################
############################
"""


func test_a_level_entered_during_a_hitstop_starts_moving_at_once() -> void:
	Flow.hitstop(self, Flow.MAX_HITSTOP)
	assert_true(Flow.is_hitstopped(), "a blow just landed somewhere")
	var data := AsciiLevel.new()
	data.parse(ROOM)
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_source = data
	add_child_autofree(game)
	assert_false(Flow.is_hitstopped(), "the new level is not held by it")
