extends GutTest
## A kill's blood (scripts/duel/gore.gd): enough of it to read as a kill, thrown
## the way the blow went, drawn where it can be seen, on the match's clock so a
## correction never spills it twice, and bounded.
##
## tests/match_gore_test.gd holds the other half: gore never reaches the
## match's state, and the lists are bounded under a flood of spills.
## tests/unit/test_duel_replay_presentation.gd holds when the scene spills and
## wipes -- once per death, never again on a replay.

const SCENE := "res://scenes/duel_match.tscn"
const WARDROBE := "user://test_duel_blood_wardrobe.cfg"

var _strip: ZoneStrip


func before_all() -> void:
	_strip = ZoneStrip.from_manifest("res://levels/duel_zones.txt")


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WARDROBE))


func _field() -> GoreField:
	var field := GoreField.new()
	add_child_autofree(field)
	field.setup(_strip)
	return field


## Feet on the open floor in the middle of the middle zone.
func _floor_spot() -> Vector2:
	var x := _strip.zone_left(2) + _strip.zone_width() * 0.5
	return Vector2(x, _strip.ground_row(floori(x / ZoneStrip.TILE)) * ZoneStrip.TILE)


## Where a kill's droplets came down, relative to the body, once all are down.
func _landed_offsets(field: GoreField, at: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for list: Array in field._drops:
		for drop: Dictionary in list:
			out.append((drop["at"] as Vector2).x - at.x)
	return out


## The seventh way of looking right while showing nothing: the blood was at
## z -1, beneath the zone's stone, and every stain in front of a backdrop was
## drawn and hidden. This holds it over the stone and under the actors.
func test_the_blood_is_drawn_over_the_stone_and_under_the_actors() -> void:
	var scene := (load(SCENE) as PackedScene).instantiate()
	scene.set("wardrobe_path", WARDROBE)
	add_child_autofree(scene)
	var gore := scene.get_node(^"World/Gore") as GoreField
	var view := scene.get_node(^"World/ZoneView")
	assert_gt(gore.get_index(), view.get_index(), "drawn after the zones, at the same z")
	var layers := view.find_children("*", "TileMapLayer", true, false)
	assert_gt(layers.size(), 0, "the zones have drawn layers to compare with")
	for layer: Node in layers:
		var z := (layer as CanvasItem).z_index
		if layer.name.begins_with("Fore"):
			assert_lt(gore.z_index, z, "under the foreground plane %s" % layer.get_path())
		else:
			assert_gte(gore.z_index, z, "over the stone of %s" % layer.get_path())
	for art: Node in scene.find_children("FighterArt", "", true, false):
		assert_lt(gore.z_index, (art as CanvasItem).z_index, "under the fighters")


func test_a_kill_is_a_spurt_a_streak_and_a_pool() -> void:
	var field := _field()
	var at := _floor_spot()
	field.spill(at, 0, 300, 1)
	assert_eq(field.count_in(2) + field.count_in(1) + field.count_in(3),
		GoreField.DROPS_PER_KILL + 2, "every droplet, a pool and a streak")
	assert_eq(field.marks_in(2), 2, "the pool and the streak")
	var pulses := 0
	for n: int in GoreField.PULSES:
		pulses += n
	assert_eq(pulses, GoreField.DROPS_PER_KILL, "the pulses add up to the count")


func test_the_spray_goes_the_way_the_blow_went() -> void:
	for blow: int in [1, -1]:
		var field := _field()
		var at := _floor_spot()
		field.spill(at, 1, 400, blow)
		var with_blow := 0
		for dx: float in _landed_offsets(field, at):
			if dx * blow > 2.0:
				with_blow += 1
		assert_gt(with_blow, GoreField.DROPS_PER_KILL * 2 / 3,
			"blow %d: %d of %d droplets came down on its side" % [
				blow, with_blow, GoreField.DROPS_PER_KILL])
	var hazard := _field()
	hazard.spill(_floor_spot(), 0, 500, 0)
	var east := 0
	var west := 0
	for dx: float in _landed_offsets(hazard, _floor_spot()):
		east += 1 if dx > 0.0 else 0
		west += 1 if dx < 0.0 else 0
	assert_true(east > 0 and west > 0, "a hazard throws to both sides (%d, %d)" % [east, west])


func test_the_spurt_runs_on_the_matchs_clock() -> void:
	var field := _field()
	field.spill(_floor_spot(), 0, 300, 1)
	assert_eq(field.flying().size(), 0, "with no clock everything is down")
	field.tick(300)
	assert_true(field.moving(), "the death frame: it starts")
	field.tick(306)
	var early := field.flying().size()
	assert_gt(early, 0, "six frames in, droplets are in the air")
	field.tick(300 + GoreField.PULSE_FRAMES[2] + 2)
	assert_gt(field.flying().size(), 0, "the last pulse is out after the first")
	field.tick(300 + GoreField.PULSE_FRAMES[2] + GoreField.FLIGHT_FRAMES + 1)
	assert_eq(field.flying().size(), 0, "and all of it is down by the end")
	field.tick(300 + GoreField.POOL_FRAMES + GoreField.FLIGHT_FRAMES + 30)
	assert_false(field.moving(), "after which nothing moves, and nothing redraws")


## A correction that moves a death two frames carries the spurt on at the age
## the host says, rather than spurting again: the moved death at frame 302,
## seen at 310, is exactly a death at 302 seen at 310 -- not a fresh one.
func test_a_moved_death_carries_on_and_a_wiped_one_leaves_the_air() -> void:
	var at := _floor_spot()
	var field := _field()
	field.spill(at, 0, 300, 1)
	field.tick(308)
	field.wipe(0, 300)
	assert_eq(field.flying().size(), 0, "wiped: out of the air as well as off the floor")
	assert_eq(field.total(), 0, "and off the floor")
	field.spill(at, 0, 302, 1)
	field.tick(310)
	var moved := field.flying()

	var straight := _field()
	straight.spill(at, 0, 302, 1)
	straight.tick(310)
	assert_eq(moved, straight.flying(), "the moved spurt is the host's, at its age")
	var fresh := _field()
	fresh.spill(at, 0, 302, 1)
	fresh.tick(302)
	assert_ne(moved, fresh.flying(), "not a spurt starting over")


func test_pools_outlast_the_spray_under_the_bound() -> void:
	var field := _field()
	var at := _floor_spot()
	var kills := 20
	for i: int in kills:
		field.spill(at + Vector2(float(i % 5) * 3.0, 0.0), i % 2, 1000 + i * 150, 1)
	assert_eq(field.marks_in(2), kills * 2, "every pool and streak kept")
	assert_eq(field.count_in(2) - field.marks_in(2), GoreField.MAX_DROPS,
		"the droplets at their bound, oldest gone first")
