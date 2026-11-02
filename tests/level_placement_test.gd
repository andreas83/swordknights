extends SceneTree
## Checks the things that are not about reachability but still ruin a level:
## a spawn hanging in the air, an exit door with no floor under it, a relic
## walled into the rock, two guards in the same tile.
##
## Also checks the verifier rejects each of those, because the generator's
## retry loop is only as good as what `verify` refuses to pass.
##
##     godot --headless --script tests/level_placement_test.gd

const Asserts := preload("res://tests/level_asserts.gd")

const SEEDS := 48
const LENGTH := 130

var _check := Asserts.new("level_placement_test")


func _initialize() -> void:
	for i: int in SEEDS:
		_check_level(70000 + i * 541, LENGTH, float(i % 5) * 0.25)
	_check_verifier_rejects_bad_levels()
	quit(0 if _check.report() else 1)


func _check_level(seed_value: int, length: int, difficulty: float) -> void:
	var tag := "seed %d" % seed_value
	var level := LevelGenerator.generate(seed_value, length, difficulty)
	if level == null:
		_check.fail("%s produced no level" % tag)
		return

	# Structure: the parse must have kept every row the canvas drew.
	_check.equal(level.rows, LevelGrammar.ROWS, "%s keeps all its rows" % tag)
	# The chain stops once the next segment would overshoot, so the result
	# lands a little over the target but never wildly over or under it.
	_check.is_true(level.cols >= length - 16,
		"%s is at least about as wide as asked (%d vs %d)" % [tag, level.cols, length])
	_check.is_true(level.cols <= length + 32,
		"%s does not overshoot the asked width (%d vs %d)" % [tag, level.cols, length])

	var exits: Array[Vector2i] = []
	for mark: Dictionary in level.entities:
		if String(mark["kind"]) == "exit":
			exits.append(mark["cell"])
	_check.equal(exits.size(), 1, "%s has exactly one exit door" % tag)

	# Spawn and exit stand on solid ground with room for the body.
	_check_standing(level, level.spawn_point, "%s spawn" % tag, true)
	for cell: Vector2i in exits:
		_check_standing(level, cell, "%s exit" % tag, true)
		# ExitDoor.bounds() is two tiles tall, so the cell above must be clear.
		_check.is_false(level.is_solid(cell.x, cell.y - 1),
			"%s exit has headroom for the door" % tag)

	# No entity embedded in a wall, and no two in the same cell.
	var occupied := {level.spawn_point: "spawn"}
	for mark: Dictionary in level.entities:
		var kind := String(mark["kind"])
		var cell: Vector2i = mark["cell"]
		var what := "%s %s at %s" % [tag, kind, str(cell)]

		_check.is_true(
			cell.x >= 0 and cell.x < level.cols and cell.y >= 0 and cell.y < level.rows,
			"%s is inside the level" % what)
		_check.is_false(occupied.has(cell),
			"%s does not share a cell with the %s" % [what, str(occupied.get(cell, ""))])
		occupied[cell] = kind
		# Torches are wall dressing but still sit in open air on a surface, so
		# every mark gets the same treatment: solid under it, clear through it.
		_check_standing(level, cell, what, true)


## `supported` distinguishes "must be on the ground" from "must merely not be
## inside the rock".
func _check_standing(level: AsciiLevel, cell: Vector2i, what: String,
		supported: bool) -> void:
	_check.is_false(level.is_solid(cell.x, cell.y), "%s is not inside solid rock" % what)
	_check.is_false(level.is_solid(cell.x, cell.y - 1),
		"%s has a clear cell above it" % what)

	var under := level.kind_at(cell.x, cell.y + 1)
	if supported:
		_check.is_true(under == Tiles.Kind.SOLID or under == Tiles.Kind.PLATFORM,
			"%s has ground under it (found %s)" % [what, str(under)])

	for probe: Vector2i in [cell, cell + Vector2i.UP]:
		_check.is_false(Tiles.is_deadly(level.kind_at(probe.x, probe.y)),
			"%s is not standing in a hazard" % what)


## The generator's retry loop depends on these being refused.
func _check_verifier_rejects_bad_levels() -> void:
	var no_exit := _parse(["@", "#####"])
	_check.is_false(bool(LevelReachability.verify(no_exit)["ok"]),
		"a level with no exit door is refused")

	# Spawn floating in the air with nothing under it.
	var floating := _parse([
		"  @  ",
		"     ",
		"    D",
		"#####",
	])
	_check.is_false(bool(LevelReachability.verify(floating)["ok"]),
		"a spawn with no ground under it is refused")

	# Exit on the far side of a chasm far wider than the jump envelope.
	var unreachable := _parse([
		" @                        D",
		"###                     ###",
		"###                     ###",
	])
	_check.is_false(bool(LevelReachability.verify(unreachable)["ok"]),
		"an exit across an uncrossable chasm is refused")

	# The same level with the chasm filled in is accepted, so the refusals
	# above are about the geometry and not about the harness.
	var fixed := _parse([
		" @                        D",
		"###########################",
		"###########################",
	])
	var report := LevelReachability.verify(fixed)
	_check.is_true(bool(report["ok"]),
		"the same exit across solid ground is accepted: %s"
			% String(report.get("reason", "")))


func _parse(lines: Array) -> AsciiLevel:
	var level := AsciiLevel.new()
	var text := PackedStringArray()
	for line: String in lines:
		text.append(line)
	level.parse("\n".join(text))
	return level
