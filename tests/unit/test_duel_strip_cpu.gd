extends GutTest
## The computer opponent on every strip: two of it, at each level, always
## finish a match, and seldom die to the ground -- the scythe, the slot, the
## tide, a slab, an alley.
##
## tests/unit/test_duel_cpu_bouts.gd holds the Tug of War to three minutes and
## one hazard death in twenty. The other strips are slower to cross -- a
## runner waits for the beat, takes the stones round a flooded court -- and an
## evenly matched pair on the Well can pass the rope back and forth for most of
## five minutes, so the limit here is six. The hazard share is held per level:
## HARD reads the ground as well as a practised player and is held to one
## death in twenty, as on the Tug of War; EASY and MEDIUM to one in eight.
## The numbers are printed, because docs/duel-match.md quotes them.
##
## Seen to fail with the ground left out of the brain's view: with no clock in
## DuelFeet, the Floodgates killed a computer at every tide and no match on it
## finished; with the burning slabs not on the feet's grid, the Aqueduct's
## HARD pair fenced on cracked stone until both fell.

const Cpu := preload("res://tests/cpu_support.gd")
## Six minutes at 60 Hz.
const LIMIT := 21600
const SEEDS := 2
const HARD_SHARE := 0.05
const SHARE := 0.125


func test_two_computers_finish_on_every_strip_at_every_level() -> void:
	await wait_physics_frames(1)
	var hard_deaths := 0
	var hard_ground := 0
	var deaths := 0
	var ground := 0
	for id: String in DuelStrips.IDS:
		if id == DuelStrips.TUG:
			continue # test_duel_cpu_bouts.gd
		var strip := DuelStrips.open(id)
		var line := PackedStringArray()
		for level: int in 3:
			var died := 0
			var fell := 0
			var longest := 0
			for i: int in SEEDS:
				var a := DuelCpu.new(0, level as DuelBrain.Difficulty, 2000 + i)
				var b := DuelCpu.new(1, level as DuelBrain.Difficulty, 3000 + i)
				var bout := Cpu.bout(get_tree().root, strip, [a, b], LIMIT)
				var name := "%s %s #%d" % [id, DuelBrain.level_name(level as
					DuelBrain.Difficulty), i]
				assert_true(bool(bout["over"]), "%s finished (%d frames)" % [name, bout["frames"]])
				longest = maxi(longest, int(bout["frames"]))
				var both := bout["deaths"] as PackedInt32Array
				var hazard := bout["hazards"] as PackedInt32Array
				died += both[0] + both[1]
				fell += hazard[0] + hazard[1]
			line.append("%s %d deaths, %d to the ground, longest %d" % [
				DuelBrain.level_name(level as DuelBrain.Difficulty), died, fell, longest])
			deaths += died
			ground += fell
			if level == DuelBrain.Difficulty.HARD:
				hard_deaths += died
				hard_ground += fell
		gut.p("%s: %s" % [id, "; ".join(line)])
	assert_gt(hard_deaths, 0, "they fought")
	assert_lte(float(hard_ground), float(hard_deaths) * HARD_SHARE,
		"HARD dies to the ground at most one time in twenty (%d of %d)"
			% [hard_ground, hard_deaths])
	assert_lte(float(ground), float(deaths) * SHARE,
		"every level, at most one in eight (%d of %d)" % [ground, deaths])


## A computer standing where a scythe is about to cut ducks under it, and one
## standing on a slab that has started to burn walks off it: the ground comes
## first, before any fencing.
func test_it_ducks_a_scythe_and_walks_off_a_burning_slab() -> void:
	var well := DuelStrips.open("well")
	var scythe: Dictionary = {}
	for blade: Dictionary in well.hazards.blades:
		if int(blade["kind"]) == StripHazards.Kind.SCYTHE:
			scythe = blade
			break
	var cell: Vector2i = scythe["cut"][0]
	var view := _view(well, Vector2(cell.x * 16.0 + 8.0, (cell.y + 2) * 16.0))
	# Ten frames before the cut: the ratchet is ticking.
	view.frame = int(scythe["phase"]) + StripHazards.PERIOD * 3 - 10
	var brain := DuelBrain.new(0, DuelBrain.Difficulty.HARD, 1)
	var bits := brain.decide(view)
	assert_true(bits & PlayerInput.BIT_DOWN != 0, "it ducks under the scythe")
	assert_eq(bits & PlayerInput.BIT_JUMP, 0, "rather than jumping into it")

	var aqueduct := DuelStrips.open("aqueduct")
	var stone: Vector2i = aqueduct.hazards.stones[aqueduct.hazards.stone_count() / 2]
	view = _view(aqueduct, Vector2(stone.x * 16.0 + 8.0, stone.y * 16.0))
	view.stones = aqueduct.hazards.fresh_stones()
	view.stones[aqueduct.hazards.stone_count() / 2] = 10
	brain = DuelBrain.new(0, DuelBrain.Difficulty.HARD, 1)
	bits = brain.decide(view)
	var moving := bits & (PlayerInput.BIT_LEFT | PlayerInput.BIT_RIGHT) != 0
	assert_true(moving, "it walks off the burning slab")
	assert_eq(bits & PlayerInput.BIT_DOWN, 0, "and does not duck on it")


## A view of a fight in progress on `strip`, seat 0 standing at `at`, the
## other fighter far off and not a threat.
func _view(strip: ZoneStrip, at: Vector2) -> DuelView:
	var view := DuelView.new()
	view.seat = 0
	view.strip = strip
	view.tuning = DuelTuning.default()
	view.phase = DuelMatch.Phase.FIGHTING
	view.age = 8
	view.me = DuelView.Body.new()
	view.me.position = at
	view.me.grounded = true
	view.them = DuelView.Body.new()
	view.them.seat = 1
	view.them.position = at + Vector2(300.0, 0.0)
	view.them.grounded = true
	view.them.facing = -1
	view.stones = strip.hazards.fresh_stones()
	return view
