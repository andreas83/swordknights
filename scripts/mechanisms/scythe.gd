class_name Scythe
extends BeatBlade
## A scythe on a beat (`z`, docs/campaign.md "Blades on the beat"): a two-cell
## run in a doorway or a shaft, a crescent of steel on an ink arm hung from the
## mason's mark that wires it.
##
## ## The cycle
##
## | | frames | what it is |
## | --- | --- | --- |
## | tell | 27 (warn) | three ratchet steps further up, each a click; a glint runs along the edge |
## | cut | 9 | Patrol.STRIKE_TIME: it sweeps the whole run -- one heart and a knockback |
## | return | 18 | it settles where the cut carried it |
## | rest | the rest | the opening is empty: the way through |
##
## A runner crosses a scythe's cell in 17 frames, so of the 91 frames it is not
## live, 74 are a moment to set off from -- the window BeatProof measures.
##
## ## Where it hangs, and why it is never in the way at rest
##
## Its mark says: a mark over the run is a lintel, a mark beside it a wall.
##
## Hung from a lintel it is a pendulum that keeps time. It parks high on one
## side of the doorway, above a standing head; through the tell it ratchets
## further up; it cuts across the opening and parks high on the other side --
## tick, and the next cut comes back, tock. The first drawing hung it straight
## down at rest, at the height of a runner's knees, and a prince walked
## through a blade that did not hurt him: danger had two looks. Parked out of
## the opening, it has one. An empty doorway is the way through.
##
## From a wall it lives in a slot in the stone. It comes up out of the slot
## along the wall through the tell, cuts down across its half of the shaft,
## and goes back into the stone. In the throat, where the shaft is exactly
## two cells wide, each scythe sweeps one half and the other half is safe.
##
## The knockback is away from where it hangs: from a doorway's middle, a
## prince short of it is thrown back the way he came and one past it onward;
## from a wall, across the shaft against the far one. A blade is a blade: one
## heart, a sentinel's cut.

enum Mount { LINTEL, WALL_LEFT, WALL_RIGHT }

## Patrol.STRIKE_TIME: the cut is live for as long as a sentinel's.
const LIVE := 9
## The arm swinging back after the cut.
const RETURN := 18
## The pendulum: parked this far up either side, ratcheted this much more
## per tooth of the tell; its arm from the lintel, and a wall arm's.
const PARK_DEG := 100.0
const RATCHET_DEG := 10.0
const ARM := 23.0
const WALL_ARM := 13.0
const CRESCENT := 7.0

var mount: Mount = Mount.LINTEL
## The side of the doorway a pendulum is parked on, -1 or 1, turned over by
## every cut on the frame it starts: while a cut is live it is the side the
## blade is going to. Starts on the west, so the first cut goes east.
var side := -1

## The prince's body already cut by this pass of the blade.
var _struck := false


static func live_frames() -> int:
	return LIVE


static func recover_frames() -> int:
	return RETURN


func live() -> int:
	return LIVE


func recover() -> int:
	return RETURN


func _setup() -> void:
	mount = mount_of(cells, _mark_cell())
	if level != null and in_ladder(cells, level.data):
		set_kind(Tiles.Kind.LADDER)
	super()


## Whether a ladder runs through `run_cells`: a ladder over the run and under
## it. A scythe in a ladder shaft is cut into the rungs, not into the way: its
## cells climb like the ladder around them, and it is crossed at the ladder's
## speed (BeatProof).
static func in_ladder(run_cells: Array[Vector2i], grid: AsciiLevel) -> bool:
	if grid == null or run_cells.is_empty():
		return false
	var top := run_cells[0]
	var bottom := run_cells[run_cells.size() - 1]
	var ladder := Tiles.Kind.LADDER
	return grid.kind_at(top.x, top.y - 1) == ladder and grid.kind_at(bottom.x, bottom.y + 1) == ladder


## Files its timing, and in a ladder shaft says its cells climb.
static func reach(mark: Dictionary, model: ReachModel) -> void:
	BeatBlade.reach(mark, model)
	var run := mark_cells(mark)
	if in_ladder(run, model.level):
		model.fixed_cells(run, Tiles.Kind.LADDER)


## Where a run of `run_cells` hangs from, given the mark that wires it: over
## it, a lintel; beside it, a wall. Static, for the proof.
static func mount_of(run_cells: Array[Vector2i], mark: Vector2i) -> Mount:
	for cell: Vector2i in run_cells:
		if mark == cell + Vector2i.LEFT:
			return Mount.WALL_LEFT
		if mark == cell + Vector2i.RIGHT:
			return Mount.WALL_RIGHT
	return Mount.LINTEL


## The x a cut throws the prince away from: the doorway's middle, or the wall.
static func pivot_x(run_cells: Array[Vector2i], how: Mount) -> float:
	var rect := danger_rect(run_cells)
	match how:
		Mount.WALL_LEFT:
			return rect.position.x
		Mount.WALL_RIGHT:
			return rect.end.x
		_:
			return rect.get_center().x


func _mark_cell() -> Vector2i:
	if level == null or level.data == null:
		return Vector2i(-1, -1)
	for cell: Vector2i in cells:
		for step: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
			if level.data.masons_marks.has(cell + step):
				return cell + step
	return Vector2i(-1, -1)


func _on_tell_step(step: int) -> void:
	if _on_screen():
		# The ratchet: three clicks, each a tooth further back.
		cue.emit(&"ladder", {"pitch": 1.8 + 0.06 * float(step), "volume_db": -8.0})


func _on_cut() -> void:
	_struck = false
	side = -side
	if _on_screen():
		cue.emit(&"sword", {"pitch": 0.9})


func _strike(contact: Contact) -> void:
	if _struck or not contact.body.intersects(cut_rect()):
		return
	_struck = true
	contact.harm(1, pivot_x(cells, mount))


## --- drawing ------------------------------------------------------------------

## The arm as the clock has it: `{deg, length}`, the angle from hanging
## straight down (positive toward +x) and how far out of its slot the arm is.
## A pure function of `t` and `side`, so a frame can be posed from those
## alone (tools/owl_poses.gd).
##
## Hanging from a lintel it is a pendulum that keeps time: parked high on one
## side of the doorway -- above a standing head and clear of the opening, so
## an empty doorway is the way through -- it ratchets further up through the
## tell, cuts across to the other side, and parks there. Tick, tock: the next
## cut comes back. From a wall it lives in a slot in the stone: it comes up
## out of the slot along the wall through the tell, cuts down across its
## half of the shaft, and goes back into the stone.
func arm_pose() -> Dictionary:
	var tell := tell_frames()
	var step := 0
	if is_telling():
		step = 1 + mini(2, (t - (PERIOD - tell)) * 3 / tell)
	if mount == Mount.LINTEL:
		var from := PARK_DEG * float(side)
		if step > 0:
			return {"deg": from + RATCHET_DEG * float(step * side), "length": ARM}
		if is_live():
			# `side` turned over on the cut: it is where the blade is going.
			var swing := float(t + 1) / float(LIVE)
			return {"deg": lerpf(_cut_start(), from, swing), "length": ARM}
		return {"deg": from, "length": ARM}
	# The wall: +x is into the shaft from a left wall, -x from a right one.
	var into := 1.0 if mount == Mount.WALL_LEFT else -1.0
	if step > 0:
		return {"deg": into * (150.0 + 10.0 * float(step)), "length": WALL_ARM * float(step) / 3.0}
	if is_live():
		var swing := float(t + 1) / float(LIVE)
		return {"deg": into * lerpf(180.0, 0.0, swing), "length": WALL_ARM}
	if _armed and t < LIVE + RETURN:
		var back := float(t - LIVE) / float(RETURN)
		return {"deg": -into * 70.0 * back, "length": WALL_ARM * (1.0 - back)}
	return {"deg": 0.0, "length": 0.0}


func _pivot_local() -> Vector2:
	var rect := danger_rect(cells)
	rect.position -= position
	match mount:
		Mount.WALL_LEFT:
			return Vector2(rect.position.x, rect.get_center().y)
		Mount.WALL_RIGHT:
			return Vector2(rect.end.x, rect.get_center().y)
		_:
			return Vector2(rect.get_center().x, rect.position.y)


func _draw() -> void:
	if cells.is_empty():
		return
	var pivot := _pivot_local()
	var pose := arm_pose()
	var degrees := float(pose["deg"])
	var length := float(pose["length"])
	if is_live():
		# Two hard afterimages behind the blade: the sweep, without a blur.
		var start := _cut_start()
		for ghost: int in [2, 1]:
			var behind := lerpf(degrees, start, float(ghost) * 0.25)
			_crescent(pivot, behind, length, Palette.STEEL_DARK, false)
	if length > 0.5:
		_arm(pivot, degrees, length)
		_crescent(pivot, degrees, length, Palette.STEEL, is_telling())
	_hub(pivot)


## Where this cut started, for its afterimages.
func _cut_start() -> float:
	if mount == Mount.LINTEL:
		return -(PARK_DEG + RATCHET_DEG * 3.0) * float(side)
	return 180.0 if mount == Mount.WALL_LEFT else -180.0


func _toward(degrees: float) -> Vector2:
	var radians := deg_to_rad(degrees)
	return Vector2(sin(radians), cos(radians))


## Ink, with a hard crimson edge: at night ink on the Well's stone is a line
## nobody sees, and the arm is what makes the crescent read as a pendulum.
func _arm(pivot: Vector2, degrees: float, length: float) -> void:
	var tip := pivot + _toward(degrees) * length
	draw_line(pivot, tip, Palette.SHADOW_DEEP, 4.0)
	draw_line(pivot, tip, Palette.INK, 2.0)


## The crescent at the end of the arm, across it, bellied outward. `glint`
## runs a point of light along the edge across the tell: the one PAPER pixel,
## as on the sentinel's raise.
func _crescent(pivot: Vector2, degrees: float, length: float, steel: Color,
		glint: bool) -> void:
	var along := _toward(degrees)
	var across := Vector2(along.y, -along.x)
	var tip := pivot + along * length
	var points := PackedVector2Array()
	var steps := 7
	for i: int in steps + 1:
		var a := lerpf(-1.0, 1.0, float(i) / float(steps))
		points.append(tip + across * a * CRESCENT + along * (1.0 - a * a) * 3.0)
	for i: int in range(steps, -1, -1):
		var a := lerpf(-1.0, 1.0, float(i) / float(steps))
		points.append(tip + across * a * CRESCENT * 0.82 + along * (1.0 - a * a) * 1.2)
	if Geometry2D.triangulate_polygon(points).is_empty():
		return
	draw_colored_polygon(points, steel)
	# The back of the blade in the darker steel: the edge is the bright side.
	draw_line(tip + across * -CRESCENT * 0.82, tip + across * CRESCENT * 0.82,
		Palette.STEEL_DARK, 1.0)
	if glint:
		var a := lerpf(-0.8, 0.8, tell_progress())
		var at := (tip + across * a * CRESCENT + along * (1.0 - a * a) * 3.0).round()
		draw_rect(Rect2(at - Vector2(0.5, 0.5), Vector2.ONE), Palette.PAPER)


func _hub(pivot: Vector2) -> void:
	draw_circle(pivot, 3.5, Palette.SHADOW_DEEP)
	draw_circle(pivot, 2.5, Palette.INK)
	draw_rect(Rect2(pivot - Vector2(0.5, 0.5), Vector2.ONE), Palette.SHADOW_WARM)
