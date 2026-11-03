extends GutTest
## The computer opponent plays the seat the way a human does, and no better
## informed: through eight bits of PlayerInput, from a DuelView, late.
##
## Three claims, each with its own test:
##
## - STRUCTURE. The brain holds no match, fighter, seat or input, and its one
##   way in is a DuelView. The view carries no input bit. This is checked on the
##   scripts themselves, so a field added later that would let it peek fails
##   here rather than in a code review that missed it.
## - BYTES. Everything it emits is a byte a human could press: no bit above the
##   eighth, never left with right, never up with down.
## - TIME. Change the human's input on one frame and the computer's input does
##   not change for its whole reaction time -- it cannot have seen the change
##   yet -- and does change after it, so the change was one it could see. This
##   is the behaviour, end to end, through the same DuelCpu the scene drives.

const Cpu := preload("res://tests/cpu_support.gd")
const Support := preload("res://tests/duel_support.gd")

## Types the brain must never hold: any of them is a way to the live match.
const FORBIDDEN: Array[String] = [
	"DuelMatch", "DuelSim", "Fighter", "DuelSeat", "PlayerInput", "LocalInput",
	"DuelEyes", "DuelCpu", "Node", "Node2D", "CharacterBody2D", "NetSession",
]

var _strip: ZoneStrip


func before_all() -> void:
	_strip = Support.load_strip()


func test_the_brain_holds_nothing_it_could_peek_through() -> void:
	var brain := DuelBrain.new()
	var held := 0
	for property: Dictionary in brain.get_property_list():
		if int(property["type"]) != TYPE_OBJECT:
			continue
		held += 1
		var cls := String(property["class_name"])
		assert_false(FORBIDDEN.has(cls) or ClassDB.is_parent_class(cls, "Node"),
			"DuelBrain.%s is a %s" % [property["name"], cls])
	assert_gt(held, 0, "the property list was read (the RNG at least is an object)")

	var decide := _method(brain.get_script(), "decide")
	assert_false(decide.is_empty(), "DuelBrain has decide()")
	var args: Array = decide.get("args", [])
	assert_eq(args.size(), 1, "decide() takes one argument")
	if args.size() == 1:
		assert_eq(String((args[0] as Dictionary)["class_name"]), "DuelView",
			"and it is a DuelView")


func test_the_view_carries_no_input() -> void:
	var view := DuelView.new()
	var body := DuelView.Body.new()
	var sword := DuelView.Sword.new()
	for thing: Object in [view, body, sword]:
		for property: Dictionary in thing.get_property_list():
			var name := String(property["name"]).to_lower()
			for word: String in ["input", "bits", "press", "button"]:
				assert_false(name.contains(word),
					"%s.%s looks like an input" % [thing.get_class(), property["name"]])
			var cls := String(property["class_name"])
			assert_false(FORBIDDEN.has(cls), "%s.%s is a %s" % [
				thing.get_class(), property["name"], cls])


func test_every_byte_is_one_a_human_could_press() -> void:
	await wait_physics_frames(1)
	var pressed := 0
	var frames := 0
	var bad: Array[String] = []
	var sideways := PlayerInput.BIT_LEFT | PlayerInput.BIT_RIGHT
	var upright := PlayerInput.BIT_UP | PlayerInput.BIT_DOWN
	for level: int in 3:
		var cpu := DuelCpu.new(1, level as DuelBrain.Difficulty, 70 + level)
		var bout := Cpu.bout(get_tree().root, _strip,
			[Cpu.closing_bot(0, 70 + level), cpu], 2400, true)
		for pair: Vector2i in bout["bits"]:
			var bits := pair.y
			pressed |= bits
			frames += 1
			if bits & ~0xff != 0 or bits & sideways == sideways or bits & upright == upright:
				bad.append("%d on frame %d" % [bits, frames])
	assert_gt(frames, 3000, "read the bytes of three matches")
	assert_eq(bad, [] as Array[String], "bytes no stick or button could make")
	# Every button the duel uses was pressed at least once across the three:
	# a brain that only ever ran would pass the checks above vacuously.
	for bit: int in [PlayerInput.BIT_LEFT, PlayerInput.BIT_RIGHT, PlayerInput.BIT_UP,
			PlayerInput.BIT_DOWN, PlayerInput.BIT_JUMP, PlayerInput.BIT_ATTACK,
			PlayerInput.BIT_THROW]:
		assert_ne(pressed & bit, 0, "bit %d was pressed" % bit)


## The human's buttons for a frame reach the computer no sooner than its
## reaction time after it. Two matches, identical up to frame `fork`, where the
## human in the second throws their sword instead of standing. The fighters
## are a zone apart, so nothing the throw does can touch the computer's own
## fighter inside the window either.
func test_the_humans_buttons_reach_it_no_sooner_than_its_reaction() -> void:
	await wait_physics_frames(1)
	for level: int in [DuelBrain.Difficulty.EASY, DuelBrain.Difficulty.HARD]:
		var reaction := DuelBrain.new(1, level as DuelBrain.Difficulty).reaction()
		var fork := 160
		var still := _forked_human(fork, 0)
		var thrown := _forked_human(fork, PlayerInput.BIT_THROW | PlayerInput.BIT_UP)
		var a := Cpu.bout(get_tree().root, _strip,
			[still, DuelCpu.new(1, level as DuelBrain.Difficulty, 5)], fork + 240, true)
		var b := Cpu.bout(get_tree().root, _strip,
			[thrown, DuelCpu.new(1, level as DuelBrain.Difficulty, 5)], fork + 240, true)
		var seen_a: Array[Vector2i] = a["bits"]
		var seen_b: Array[Vector2i] = b["bits"]
		var first := -1
		for frame: int in mini(seen_a.size(), seen_b.size()):
			if seen_a[frame].y != seen_b[frame].y:
				first = frame
				break
		var name := DuelBrain.level_name(level as DuelBrain.Difficulty)
		assert_ne(first, -1, "%s: the throw changed what it did at all" % name)
		assert_gte(first, fork + reaction,
			"%s answered at frame %d, %d frames after a throw on frame %d; reaction %d"
			% [name, first, first - fork, fork, reaction])


## A human who stands on their mark until `fork`;
## on that frame they press `then` (and nothing after it).
func _forked_human(fork: int, then: int) -> Callable:
	return func(fight: DuelMatch) -> int:
		if fight.frame == fork:
			return then
		return 0


func _method(script: Script, name: String) -> Dictionary:
	for method: Dictionary in script.get_script_method_list():
		if String(method["name"]) == name:
			return method
	return {}
