extends GutTest
## A respawn is shown where it happens (scripts/duel/respawn_beacon.gd,
## MatchHud._draw_respawns()): while a fighter is down their column stands on
## the very spot the match will put them -- DuelMatch.respawn_plan(), not a
## guess of the beacon's own -- and the HUD's pointer aims at the same spot;
## when they come back the column flares and the band says so; and a fighter
## who is back but out of the view still has an arrow at the screen's edge.
##
## The owner found the respawn unclear; these hold the three things that made
## it clear on rendered frames.

const Support := preload("res://tests/duel_support.gd")
const SCENE := "res://scenes/duel_match.tscn"
var _wardrobe := UserData.at("user://test_respawn_marks_wardrobe.cfg")


func after_all() -> void:
	if FileAccess.file_exists(_wardrobe):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_wardrobe))


func _scene() -> Node:
	var scene := (load(SCENE) as PackedScene).instantiate()
	scene.set("wardrobe_path", _wardrobe)
	add_child_autofree(scene)
	return scene


## Plays a match on the placeholder fighters until someone is down.
func _down_one() -> Array:
	var fight := DuelMatch.new()
	add_child_autofree(fight)
	assert_true(fight.build(Support.load_strip()), "the match builds")
	var beacon := RespawnBeacon.new()
	beacon.fight = fight
	add_child_autofree(beacon)
	var stream := Support.input_stream(3600, 5)
	for frame: int in stream.size():
		fight.step(stream[frame].x, stream[frame].y)
		for slot: int in 2:
			if not fight.is_fighter_alive(slot):
				return [fight, beacon, slot]
	return [fight, beacon, -1]


func test_the_column_stands_on_the_spot_the_match_will_use() -> void:
	var played := _down_one()
	var fight: DuelMatch = played[0]
	var beacon: RespawnBeacon = played[1]
	var slot: int = played[2]
	assert_gte(slot, 0, "someone went down in a minute of play")
	if slot < 0:
		return
	assert_true(beacon.marked(slot), "the one who is down has a column")
	assert_false(beacon.marked(1 - slot), "the one standing has none")
	assert_eq(beacon.spot(slot), fight.respawn_plan(slot)["position"],
		"on the spot the match will put them")


func test_a_return_flares_the_column_and_says_so() -> void:
	var scene := _scene()
	var beacon := scene.get("beacon") as RespawnBeacon
	var hud := scene.get_node(^"HudLayer/Hud") as MatchHud
	assert_not_null(beacon, "the scene stands a beacon in its world")
	if beacon == null:
		return
	assert_eq(hud.beacon, beacon, "and the HUD points at what it marks")
	assert_eq(hud.camera, scene.get("camera"), "through the duel's own camera")
	var fight := scene.get("fight") as DuelMatch
	fight.fighter_respawned.emit(1, Vector2(200.0, 100.0), -1)
	assert_gt(beacon.burst_left(1), 0.0, "the column flares where they stand")
	var said: PackedStringArray = hud.get("_flash_options")
	assert_true(said.size() > 0 and String(said[0]).contains("RETURN"),
		"and the band says they are back: %s" % [said])


func test_a_spot_off_the_screen_is_pointed_at_from_its_edge() -> void:
	var scene := _scene()
	await wait_process_frames(3)
	var hud := scene.get_node(^"HudLayer/Hud") as MatchHud
	var camera := scene.get("camera") as MatchCamera
	var view := camera.view_rect()
	var content := Rect2(Vector2.ZERO, hud.size)
	var far_right := Vector2(view.end.x + 400.0, view.get_center().y)
	var pointer := hud.pointer_for(far_right, content)
	assert_false(pointer.is_empty(), "a spot a screen away is pointed at")
	if not pointer.is_empty():
		var at: Vector2 = pointer["at"]
		assert_gt(at.x, hud.size.x * 0.8, "from the right edge: %s of %s" % [at, hud.size])
		assert_gt((pointer["direction"] as Vector2).x, 0.5, "and points out to the right")
	var inside := view.get_center() + Vector2(0.0, 10.0)
	assert_true(hud.pointer_for(inside, content).is_empty(),
		"a spot in the middle of the view is its own column, not an arrow")
