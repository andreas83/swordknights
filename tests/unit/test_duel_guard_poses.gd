extends GutTest
## The three guards and the duck are four pictures, not one picture with the
## blade moved (scripts/duel/fighter_art.gd, GUARDS and BLADE_SLOPE;
## docs/duel-combat.md, "Seeing the guard").
##
## The owner, on a phone, asked whether he could tell he was in a LOW guard,
## and whether he could tell it from the duck: no. The LOW guard was the MID
## figure with its level blade seven pixels lower, and the duck was a folded
## figure holding the same level blade at the same height. These pin what now
## tells them apart at a glance, on the rig's own points, for both figures and
## both seats: the blade's slant, the body's height, the free arm, and no blade
## on the duck. Seen to fail against the art as it was (every LOW and duck
## check below), and the spark test with the spark taken out.

const FIGHTER_SCENE := preload("res://scenes/fighter.tscn")
const FIGURES: Array[String] = ["prince", "heroine"]


func _fighter(figure: String, seat: int) -> FighterArt:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	add_child_autofree(fighter)
	fighter.setup(seat, null)
	var look := CharacterLook.new()
	look.take_ids({"figure": figure})
	var art := FighterArt.dress(fighter, seat, look)
	fighter.respawn_at(Vector2(160.0, 120.0), 1 - seat * 2)
	fighter.grounded = true
	fighter.set_physics_process(false)
	return art


## Poses `art`'s fighter standing at `stance` (or ducked), rigs it, and returns
## the points that tell a guard: hilt, tip, head and the free hand.
func _rigged(art: FighterArt, stance: int, ducked: bool = false) -> Dictionary:
	var f := art.get_parent() as Fighter
	f.state = Fighter.State.DUCKING if ducked else Fighter.State.IDLE
	f.stance = stance
	f.set("_ducked", ducked)
	var pose := art._posture()
	art._rig(pose)
	var blade := art._blade_local()
	var line := art._blade_line(blade) if blade.has_area() else PackedVector2Array()
	return {"blade": blade, "line": line, "head": art._head, "back": art._hand_back,
		"shoulder": art._shoulder, "pose": pose}


func test_each_height_has_its_own_slant() -> void:
	for figure: String in FIGURES:
		for seat: int in 2:
			var art := _fighter(figure, seat)
			var high := _rigged(art, DuelTuning.Stance.HIGH)
			var mid := _rigged(art, DuelTuning.Stance.MID)
			var low := _rigged(art, DuelTuning.Stance.LOW)
			var who := "%s seat %d" % [figure, seat]
			var h: PackedVector2Array = high["line"]
			var m: PackedVector2Array = mid["line"]
			var l: PackedVector2Array = low["line"]
			assert_lt(h[1].y, h[0].y - 2.0, "%s: HIGH points up" % who)
			assert_almost_eq(m[1].y, m[0].y, 0.01, "%s: MID is level" % who)
			assert_gt(l[1].y, l[0].y + 2.0, "%s: LOW points down at the shins" % who)
			for pair: Array in [[high, "HIGH"], [mid, "MID"], [low, "LOW"]]:
				var rect: Rect2 = pair[0]["blade"]
				for point: Vector2 in pair[0]["line"]:
					assert_true(rect.grow(0.01).has_point(point),
						"%s: the %s blade is drawn inside what parries" % [who, pair[1]])


func test_low_stands_tall_with_the_free_arm_up() -> void:
	for figure: String in FIGURES:
		var art := _fighter(figure, 0)
		var mid := _rigged(art, DuelTuning.Stance.MID)
		var low := _rigged(art, DuelTuning.Stance.LOW)
		var duck := _rigged(art, DuelTuning.Stance.LOW, true)
		var low_head: Vector2 = low["head"]
		var mid_head: Vector2 = mid["head"]
		var duck_head: Vector2 = duck["head"]
		assert_lte(low_head.y, mid_head.y + 0.3, "%s: LOW stands as tall as MID" % figure)
		assert_gt(duck_head.y, low_head.y + 6.0, "%s: the duck is far lower than LOW" % figure)
		var back: Vector2 = low["back"]
		var shoulder: Vector2 = low["shoulder"]
		assert_lt(back.y, shoulder.y - 2.0, "%s: LOW throws the free arm up" % figure)
		assert_lt(back.x * art._f, 0.0, "%s: and back, behind the body" % figure)
		var mid_back: Vector2 = mid["back"]
		assert_gt(mid_back.y, shoulder.y, "%s: MID's free arm hangs" % figure)


func test_the_duck_holds_no_guard() -> void:
	for figure: String in FIGURES:
		var art := _fighter(figure, 1)
		var duck := _rigged(art, DuelTuning.Stance.LOW, true)
		var rect: Rect2 = duck["blade"]
		assert_false(rect.has_area(), "%s: no blade is drawn along a duck's guard" % figure)
		var pose: Dictionary = duck["pose"]
		assert_lt(float(pose["blade"]), -1.0, "%s: the sword is pulled up out of it" % figure)


## Blades meeting strike a spark at this fighter's own blade, so a LOW parry
## lights up at the shins, where the guard that turned the thrust is.
func test_a_parry_sparks_at_the_blade() -> void:
	var art := _fighter("prince", 0)
	var f := art.get_parent() as Fighter
	f.stance = DuelTuning.Stance.LOW
	art.queue_redraw()
	await wait_process_frames(2)
	f.clashed.emit(f.position)
	assert_gt(art._spark, 0.0, "the clash strikes a spark")
	var rect := art._blade_local()
	assert_true(rect.grow(1.0).has_point(art._spark_at), "at the LOW blade: %s in %s" % [
		art._spark_at, rect])
	await wait_seconds(FighterArt.SPARK_TIME + 0.1)
	assert_eq(art._spark, 0.0, "and burns out")
