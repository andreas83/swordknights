class_name LevelGenerator
extends RefCounted
## Chains grammar segments into a playable level, then proves it is playable.
##
##     var level := LevelGenerator.generate(0xC0FFEE, 160, 0.55)
##
## Deterministic by construction: all randomness comes from one seeded
## RandomNumberGenerator, drawn in a fixed order, and nothing here touches the
## global `randi`. The same (seed, length, difficulty) always produces
## byte-identical text — that is what makes a seed worth reporting.
##
## The chain itself cannot produce a seam: every segment declares an entry and
## an exit height, the next segment's entry is the previous one's exit, and
## each segment fills its own ground from its surface row down to the bedrock.
## What the chain *can* produce is a level that is no longer solvable — a gap
## landed next to a wall, a relic shelf that blocks the only approach — so
## every candidate goes through LevelReachability before it is returned. A
## rejected candidate is retried under a fresh sub-seed derived from the
## original, so a retry is as reproducible as a first attempt.

## Shortest level worth generating: head terrace, one beat, tail terrace.
const MIN_LENGTH := 32
## How many sub-seeds to try before admitting defeat. Verification failures are
## rare (see docs/level-generation.md), so this is generous rather than tuned.
const MAX_ATTEMPTS := 24
## Segments harder than the requested difficulty by more than this never appear.
const DIFFICULTY_TOLERANCE := 0.25

const ADJECTIVES: PackedStringArray = [
	"Sunken", "Gilded", "Hollow", "Quiet", "Burning", "Drowned",
	"Forgotten", "Narrow", "Bitter", "Old", "Shifting", "Patient",
]
const NOUNS: PackedStringArray = [
	"Cistern", "Terrace", "Halls", "Stair", "Reservoir", "Vault",
	"Gallery", "Causeway", "Catacomb", "Rampart", "Aqueduct", "Court",
]


## Generates and verifies a level. Returns null — after pushing an error — when
## no sub-seed produced a solvable level, rather than handing back a level the
## player cannot finish.
static func generate(seed_value: int, length: int, difficulty: float) -> AsciiLevel:
	var result := build(seed_value, length, difficulty)
	if not bool(result["ok"]):
		return null
	return result["level"] as AsciiLevel


## The ASCII the generator would write to a file, header comments and all.
## Empty when generation failed.
static func generate_text(seed_value: int, length: int, difficulty: float) -> String:
	var result := build(seed_value, length, difficulty)
	if not bool(result["ok"]):
		return ""
	return String(result["text"])


## Generation with the paperwork: `{ok, text, level, attempts, report, beats,
## reason}`. The CLI and the tests use this; `generate` is the short form.
static func build(seed_value: int, length: int, difficulty: float) -> Dictionary:
	var target := maxi(length, MIN_LENGTH)
	var diff := clampf(difficulty, 0.0, 1.0)
	var reasons := PackedStringArray()

	for attempt: int in MAX_ATTEMPTS:
		var composed := _compose(sub_seed(seed_value, attempt), target, diff, seed_value)
		var level := AsciiLevel.new()
		level.parse(String(composed["text"]))

		var report := LevelReachability.verify(level)
		if bool(report["ok"]):
			return {
				"ok": true,
				"text": String(composed["text"]),
				"level": level,
				"beats": composed["beats"],
				"attempts": attempt + 1,
				"report": report,
				"reason": "",
			}
		reasons.append("attempt %d: %s" % [attempt + 1, String(report["reason"])])

	var reason := (
		"could not generate a solvable level for seed %d (length %d, difficulty %.2f) "
		% [seed_value, target, diff]
		+ "in %d attempts — %s" % [MAX_ATTEMPTS, " | ".join(reasons)]
	)
	push_error(reason)
	return {"ok": false, "reason": reason, "text": "", "level": null,
		"beats": [], "attempts": MAX_ATTEMPTS, "report": {}}


## Mixes the caller's seed with the attempt number. Public because "a retry is as
## reproducible as a first attempt" is part of the contract, and the only way
## to check that from outside is to be able to ask for attempt N's seed.
##
## A retry has to be a different level but still a reproducible one, so this is
## a hash rather than a fresh random seed: murmur3's 32-bit finaliser, with the
## seed's high word folded in first. Every intermediate is masked back to 32
## bits, so the arithmetic never overflows and the result cannot drift between
## platforms.
static func sub_seed(seed_value: int, attempt: int) -> int:
	const MASK := 0xFFFFFFFF
	const MIX := 0x45D9F3B
	var h := (seed_value ^ (seed_value >> 32)) & MASK
	h = (h ^ ((attempt + 1) * 0x9E3779B1)) & MASK
	h = ((h ^ (h >> 16)) * MIX) & MASK
	h = ((h ^ (h >> 16)) * MIX) & MASK
	return (h ^ (h >> 16)) & MASK


## --- composition -----------------------------------------------------------

static func _compose(stream_seed: int, target: int, difficulty: float,
		display_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = stream_seed

	var beats := _chain(rng, target, difficulty)
	var cols := 0
	for spec: Dictionary in beats:
		cols += int(spec["width"])

	var canvas := LevelGrammar.Canvas.new(cols, LevelGrammar.ROWS)
	var marks: Array[Dictionary] = []
	var x := 0
	for spec: Dictionary in beats:
		spec["x"] = x
		for mark: Dictionary in LevelGrammar.stamp(canvas, x, spec):
			marks.append(mark)
		x += int(spec["width"])

	var placed := _place_entities(canvas, beats, marks, rng, difficulty)
	# Two words and no seed: Hud.show_title draws this across a 320 px
	# viewport at 15 px with letter spacing, and a ten-digit seed on the end
	# runs off both sides of the screen. The seed is on screen for the whole
	# level in GeneratedGame's readout, and in the header comment below.
	var name := "%s %s" % [
		ADJECTIVES[rng.randi_range(0, ADJECTIVES.size() - 1)],
		NOUNS[rng.randi_range(0, NOUNS.size() - 1)],
	]

	return {
		"text": _render(canvas, beats, placed, name, display_seed, target, difficulty),
		"beats": beats,
	}


## Picks the run of segments. The opening and closing beats are plain terraces
## wide enough to hold the spawn and the exit door with runway around them.
static func _chain(rng: RandomNumberGenerator, target: int,
		difficulty: float) -> Array[Dictionary]:
	var head := LevelGrammar.flat_terrace(0, 7)
	var beats: Array[Dictionary] = [head]
	var used := int(head["width"])
	var tail_width := 7
	var height := 0
	var recent := PackedStringArray(["terrace"])

	while used + tail_width < target:
		# A level that opens on its hardest beat reads as a difficulty spike
		# rather than a level, so the requested difficulty ramps in across the
		# run — the opening terrace earns the ledge-grab wall later on.
		var progress := clampf(float(used) / float(target), 0.0, 1.0)
		var local := difficulty * (0.55 + 0.45 * progress)
		var id := _choose(rng, height, local, recent)
		var spec := LevelGrammar.instantiate(id, height, local, rng)
		if spec.is_empty():
			spec = LevelGrammar.flat_terrace(height, 5)
		beats.append(spec)
		used += int(spec["width"])
		height = int(spec["exit"])
		recent.append(String(spec["id"]))
		if recent.size() > 4:
			recent.remove_at(0)

	beats.append(LevelGrammar.flat_terrace(height, tail_width))
	return beats


## Weighted choice among the segments that fit here and are not harder than
## asked. Consumes exactly one draw so the rng stream does not depend on how
## many candidates were rejected.
static func _choose(rng: RandomNumberGenerator, height: int, difficulty: float,
		recent: PackedStringArray) -> String:
	var ids := PackedStringArray()
	var weights := PackedFloat32Array()
	var total := 0.0
	var ceiling := LevelGrammar.MAX_HEIGHT

	for template: Dictionary in LevelGrammar.templates():
		var id := String(template["id"])
		if not LevelGrammar.fits(id, height):
			continue
		var intrinsic := float(template["difficulty"])
		if intrinsic > difficulty + DIFFICULTY_TOLERANCE:
			continue

		var weight := maxf(0.08, 1.0 - absf(intrinsic - difficulty) * 2.0)
		# A terrace is the grammar's connective tissue and its only descent, so
		# it keeps a floor under its weight however hard the level is asked
		# to be — otherwise the chain ratchets up to MAX_HEIGHT and sticks.
		if id == "terrace":
			weight = maxf(weight, 0.45)
			if height >= ceiling - LevelGrammar.hop_rise():
				weight *= 2.5
		# Guard posts are the only beat that puts something to fight in the
		# level, so they keep a floor too rather than being squeezed out of
		# hard levels by the hazards clustered around that difficulty.
		if id == "guard_post":
			weight = maxf(weight, 0.25)
		# A level that never leaves the ground reads as a corridor, so the two
		# climbing beats are pushed hard while there is sky to climb into and
		# damped once the chain is running out of it.
		if int(template["ascent"]) > 0:
			if height <= LevelGrammar.hop_rise():
				weight *= 2.6
			elif height > ceiling / 2:
				weight *= 0.4
		# Spread the vocabulary: a beat used in the last few segments is much
		# less likely than one that has not appeared yet.
		var seen := 0
		for past: String in recent:
			if past == id:
				seen += 1
		weight *= pow(0.3, float(seen))

		ids.append(id)
		weights.append(weight)
		total += weight

	if ids.is_empty():
		return "terrace"

	var roll := rng.randf() * total
	for i: int in ids.size():
		roll -= weights[i]
		if roll <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]


## --- entities --------------------------------------------------------------

## Writes the spawn, the exit door and the entity marks into the canvas. Only
## cells that are already empty are ever written, so an entity can never punch
## a hole in the geometry the verifier just measured.
static func _place_entities(canvas: LevelGrammar.Canvas, beats: Array[Dictionary],
		marks: Array[Dictionary], rng: RandomNumberGenerator,
		difficulty: float) -> Dictionary:
	var head: Dictionary = beats[0]
	var tail: Dictionary = beats[beats.size() - 1]

	var spawn := Vector2i(int(head["x"]) + 2, LevelGrammar.stand_row(int(head["entry"])))
	var exit := Vector2i(
		int(tail["x"]) + int(tail["width"]) - 3,
		LevelGrammar.stand_row(int(tail["exit"]))
	)

	var taken := {spawn: true, exit: true}
	canvas.set_cell(spawn.x, spawn.y, LevelGrammar.SPAWN)
	canvas.set_cell(exit.x, exit.y, LevelGrammar.EXIT)

	# Budgets scale with how long and how hard the level was asked to be.
	var columns := canvas.cols
	var relic_budget := 1 + int(round(difficulty * 2.0)) + columns / 70
	var guard_budget := int(round(difficulty * 3.0)) + columns / 60
	var torch_budget := 2 + columns / 14

	var counts := {"relic": 0, "patrol": 0, "torch": 0}
	var budgets := {"relic": relic_budget, "patrol": guard_budget, "torch": torch_budget}
	var placed: Array[Dictionary] = []

	for mark: Dictionary in marks:
		var kind := String(mark["kind"])
		var cell: Vector2i = mark["cell"]
		if taken.has(cell) or counts[kind] >= budgets[kind]:
			continue
		if canvas.get_cell(cell.x, cell.y) != LevelGrammar.EMPTY:
			continue
		# Guards are thinned out at low difficulty; relics and torches are
		# dressing the grammar already decided to offer.
		if kind == "patrol" and rng.randf() > 0.35 + 0.65 * difficulty:
			continue
		taken[cell] = true
		counts[kind] = int(counts[kind]) + 1
		canvas.set_cell(cell.x, cell.y, _glyph_for(kind))
		placed.append(mark)

	# A level with no relic at all has no optional objective, so backfill one
	# onto a surface somewhere in the middle of the run.
	if int(counts["relic"]) == 0:
		var surfaces := _surface_cells(canvas)
		if not surfaces.is_empty():
			var start := surfaces.size() / 3
			for i: int in surfaces.size():
				var cell: Vector2i = surfaces[(start + i) % surfaces.size()]
				if taken.has(cell):
					continue
				taken[cell] = true
				counts["relic"] = 1
				canvas.set_cell(cell.x, cell.y, LevelGrammar.RELIC)
				placed.append({"kind": "relic", "cell": cell})
				break

	return {"spawn": spawn, "exit": exit, "entities": placed, "counts": counts}


static func _glyph_for(kind: String) -> String:
	match kind:
		"relic":
			return LevelGrammar.RELIC
		"patrol":
			return LevelGrammar.PATROL
		"torch":
			return LevelGrammar.TORCH
		_:
			return LevelGrammar.EMPTY


## Every cell a character could stand in on top of the terrain's skyline.
static func _surface_cells(canvas: LevelGrammar.Canvas) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x: int in canvas.cols:
		for y: int in canvas.rows:
			var glyph := canvas.get_cell(x, y)
			if glyph != LevelGrammar.SOLID and glyph != LevelGrammar.PLATFORM:
				continue
			if y > 0 and canvas.get_cell(x, y - 1) == LevelGrammar.EMPTY:
				out.append(Vector2i(x, y - 1))
			break
	return out


## --- rendering -------------------------------------------------------------

## Writes the level out the way a person would have: a titled header, the
## legend, the derived grammar it was built against, and a beat sheet — so a
## generated level reviews and hand-edits exactly like levels/level_01.txt.
static func _render(canvas: LevelGrammar.Canvas, beats: Array[Dictionary],
		placed: Dictionary, name: String, seed_value: int, length: int,
		difficulty: float) -> String:
	var lines := PackedStringArray()
	lines.append("; " + name)
	lines.append(";")
	lines.append("; Seed %d, length %d, difficulty %.2f." % [seed_value, length, difficulty])
	lines.append("; Generated by scripts/levels/generator.gd — regenerate with:")
	lines.append(";   godot --headless --script tools/generate_level.gd --"
		+ " --seed %d --length %d --difficulty %.2f" % [seed_value, length, difficulty])
	lines.append(";")
	lines.append("; Legend (see scripts/world/tiles.gd):")
	lines.append(";   #  solid        =  one-way platform    H  ladder")
	lines.append(";   ^  spikes       ~  water               :  background niche")
	lines.append(";   @  spawn        *  relic               D  exit door")
	lines.append(";   t  torch        p  patrol guard        space/. empty")
	lines.append(";")
	lines.append("; Vertical spacing comes out of scripts/core/tuning.gd:")
	lines.append(";   %d-tile rise -> plain hop" % LevelGrammar.hop_rise())
	lines.append(";   %d-tile rise -> needs a one-way platform step" % LevelGrammar.step_rise())
	lines.append(";   %d-tile rise -> needs a ledge grab" % LevelGrammar.grab_rise())
	lines.append(";   %d-tile gap  -> the widest a running jump crosses"
		% LevelGrammar.max_gap_tiles())
	lines.append(";")
	var counts: Dictionary = placed["counts"]
	lines.append("; %d columns, %d beats, relics %d, guards %d, difficulty %.2f."
		% [canvas.cols, beats.size(), int(counts["relic"]), int(counts["patrol"]),
			difficulty])
	lines.append("; Verified solvable by scripts/levels/reachability.gd before it")
	lines.append("; was written out — spawn to exit over walks, jumps, falls, ledge")
	lines.append("; grabs, ladders and drop-throughs.")
	lines.append(";")
	lines.append("; Beat sheet, left to right:")
	for i: int in beats.size():
		var spec: Dictionary = beats[i]
		lines.append(";   %2d. %-15s cols %3d-%-3d  height %d -> %d" % [
			i + 1,
			String(spec["id"]),
			int(spec["x"]),
			int(spec["x"]) + int(spec["width"]) - 1,
			int(spec["entry"]),
			int(spec["exit"]),
		])

	for line: String in canvas.to_lines():
		lines.append(line)
	return "\n".join(lines) + "\n"
