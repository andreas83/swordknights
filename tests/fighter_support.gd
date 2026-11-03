extends RefCounted
## Shared scaffolding for the fighter and combat tests.
##
## Deliberately not a `class_name`, exactly as tests/duel_support.gd is not:
## these are standalone scripts, run one at a time with
## `godot --headless --script tests/<name>_test.gd`, and test support has no
## business in the project's global class registry. Load it with
##
##     const Support := preload("res://tests/fighter_support.gd")
##
## THREE RULES THESE TESTS LIVE BY:
##
## 1. A fighter has to be inside the tree and stepped from a physics frame.
##    It is a CharacterBody2D and move_and_collide() queries the physics space,
##    which does not exist outside a physics frame (Godot logs
##    `body->get_space() is null` and the move silently does nothing).
##
## 2. ONE STAGE AT A TIME, always at the same coordinates. 2D physics is
##    single-precision, so the same body at y=8192 resolves collisions on a
##    coarser grid than at y=192: two stages side by side disagree within a
##    couple of hundred frames and the disagreement belongs to the harness, not
##    to the duel. So: build, run, free, build again.
##
## 3. The stage is built here rather than loaded from levels/, so a test says
##    what geometry it needs and no arena edit can quietly turn a case into
##    nonsense. It is flat, walled and boring on purpose.

## The simulation step. Fixed, never a real frame delta.
const DT := 1.0 / 60.0

const STAGE_COLS := 40
const STAGE_ROWS := 12
## Row index of the floor surface: feet stand at FLOOR_ROW * 16.
const FLOOR_ROW := 10
const TILE := 16.0

## Where the left-hand fighter stands, well clear of both walls.
const LEFT_X := 160.0

const HIGH := DuelTuning.Stance.HIGH
const MID := DuelTuning.Stance.MID
const LOW := DuelTuning.Stance.LOW
const DUCKED := DuelTuning.DUCKED

const LEFT := PlayerInput.BIT_LEFT
const RIGHT := PlayerInput.BIT_RIGHT
const UP := PlayerInput.BIT_UP
const DOWN := PlayerInput.BIT_DOWN
const JUMP := PlayerInput.BIT_JUMP
const ATTACK := PlayerInput.BIT_ATTACK
const THROW := PlayerInput.BIT_THROW

const FIGHTER_SCENE := "res://scenes/fighter.tscn"

var failures: PackedStringArray = []
var checks := 0


## Two fighters, one flat arena, and the frame that drives them.
class Stage:
	extends RefCounted

	var root: Node2D
	var level: Level
	var a: Fighter
	var b: Fighter
	var tuning: DuelTuning
	## Every event DuelCombat has reported since the last clear.
	var events: Array[Dictionary] = []

	func ground_y() -> float:
		return float(FLOOR_ROW) * TILE

	## One duel frame: both inputs, both simulations, then the fight.
	func step(bits_a: int, bits_b: int) -> void:
		for event: Dictionary in DuelCombat.step(a, b, bits_a, bits_b, DT):
			events.append(event)

	func run(frames: int, bits_a: int, bits_b: int) -> void:
		for _frame: int in frames:
			step(bits_a, bits_b)

	## Puts A on its mark facing right and B `gap` pixels away facing left,
	## then lets them settle so both are reported as standing on the floor.
	func place(gap: float, settle: int = 3) -> void:
		a.respawn_at(Vector2(LEFT_X, ground_y()), 1)
		b.respawn_at(Vector2(LEFT_X + gap, ground_y()), -1)
		b.facing = -1
		events.clear()
		run(settle, 0, 0)
		events.clear()

	func saw(kind: String) -> bool:
		for event: Dictionary in events:
			if event.get("kind", "") == kind:
				return true
		return false

	func dispose() -> void:
		root.free()


## --- building ---------------------------------------------------------------

## A flat, walled stage: solid floor, solid walls, nothing else to argue with.
static func stage_text() -> String:
	var lines := PackedStringArray()
	for row: int in STAGE_ROWS:
		var line := ""
		for col: int in STAGE_COLS:
			var solid := row >= FLOOR_ROW or col == 0 or col == STAGE_COLS - 1
			line += "#" if solid else "."
		lines.append(line)
	return "\n".join(lines)


static func build(root: Node) -> Stage:
	var stage := Stage.new()
	stage.root = Node2D.new()
	stage.root.name = "Stage"
	root.add_child(stage.root)

	stage.level = Level.new()
	stage.level.name = "Arena"
	stage.root.add_child(stage.level)
	var ascii := AsciiLevel.new()
	ascii.parse(stage_text())
	stage.level.build(ascii)
	# A TileMapLayer builds its collision bodies on a deferred internal update,
	# so without this the floor is scenery for one frame and the fighters fall
	# through it — which would make the first frame of every test a lie.
	stage.level.tilemap.update_internals()

	stage.tuning = DuelTuning.new()
	stage.a = _spawn(stage, 0)
	stage.b = _spawn(stage, 1)
	stage.place(20.0)
	return stage


static func _spawn(stage: Stage, seat: int) -> Fighter:
	var packed := load(FIGHTER_SCENE) as PackedScene
	var fighter := packed.instantiate() as Fighter
	fighter.name = "Fighter%d" % seat
	stage.root.add_child(fighter)
	fighter.level = stage.level
	fighter.setup(seat, stage.tuning)
	fighter.respawn_at(Vector2(LEFT_X, float(FLOOR_ROW) * TILE), 1)
	return fighter


## --- input ------------------------------------------------------------------

## The bits that hold a stance. Up is HIGH, down is LOW, neither is MID.
##
## A LOW stance also needs a direction held: down while standing still is a
## DUCK, which is a different column of the combat matrix. `toward` is the sign
## of the direction to hold, normally toward the opponent, because meeting a
## low blade is something you do while closing.
static func stance_bits(stance: int, toward: int = 0) -> int:
	match stance:
		DuelTuning.Stance.HIGH:
			return UP
		DuelTuning.Stance.LOW:
			return DOWN | (LEFT if toward < 0 else RIGHT)
		DuelTuning.DUCKED:
			return DOWN
		_:
			return 0


## --- assertions -------------------------------------------------------------

func check(condition: bool, what: String) -> bool:
	checks += 1
	if not condition:
		failures.append(what)
	return condition


func equal(actual: Variant, expected: Variant, what: String) -> bool:
	return check(
		actual == expected, "%s — expected %s, got %s" % [what, str(expected), str(actual)]
	)


## Returns the process exit code and prints the verdict.
func report(suite: String) -> int:
	if failures.is_empty():
		print("PASS  %s  (%d checks)" % [suite, checks])
		return 0
	print("FAIL  %s  (%d of %d checks failed)" % [suite, failures.size(), checks])
	for line: String in failures:
		print("  - ", line)
	return 1
