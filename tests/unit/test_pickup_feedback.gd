extends GutTest
## Feedback that must say exactly one thing, once.
##
## A relic that bursts instead of vanishing is on screen for a third of a
## second after it has been taken, which is long enough for the prince to
## still be standing in it -- so the burst must not be collectable. And the HUD
## pops on a gain and burns on a loss, but a restart that resets both counts
## is neither, and must not set either off.


func test_a_relic_is_counted_once_however_long_it_bursts() -> void:
	var relic := Relic.new()
	add_child_autofree(relic)
	var count := [0]
	relic.collected.connect(func() -> void: count[0] += 1)
	relic.collect()
	relic.collect()
	assert_eq(count[0], 1, "collected fires once")
	assert_true(relic.is_taken())
	assert_eq(relic.bounds(), Rect2(), "a taken relic has nothing left to touch")


func test_a_taken_relic_goes_after_its_burst() -> void:
	var relic := Relic.new()
	add_child(relic)
	relic.collect()
	relic._process(Relic.BURST_TIME + 0.01)
	assert_true(relic.is_queued_for_deletion(), "the node does not outlive the burst")


func test_hud_pops_on_a_gain_and_burns_on_a_loss() -> void:
	var hud: Hud = autofree(Hud.new())
	hud.update_model(3, 3, 0, 3)
	assert_eq(hud.get("_relic_pulse"), 0.0, "the first report is not news")
	hud.update_model(3, 3, 1, 3)
	assert_gt(hud.get("_relic_pulse"), 0.0, "a relic gained pops the count")
	hud.update_model(2, 3, 1, 3)
	assert_gt(hud.get("_hurt_pulse"), 0.0, "a mark lost burns")


func test_hud_does_not_celebrate_a_restart() -> void:
	var hud: Hud = autofree(Hud.new())
	hud.update_model(1, 3, 2, 3)
	hud.set("_relic_pulse", 0.0)
	hud.set("_hurt_pulse", 0.0)
	hud.update_model(3, 3, 0, 3)
	assert_eq(hud.get("_relic_pulse"), 0.0, "relics reset to zero is not a gain")
	assert_eq(hud.get("_hurt_pulse"), 0.0, "health refilled is not a loss")
