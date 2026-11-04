class_name SunSeal
extends Mechanism
## A sun-seal: a doorway with a sun carved in it, which opens to light and to
## nothing else (docs/campaign.md, "Sun mirrors and sun-seals").
##
## ## Filling
##
## While a beam rests on any of its cells, its eight rays light one at a time
## over FILL_FRAMES -- the game's telegraph length, so a seal filling is read
## at the same pace as every other "now" in the game -- and they drain at the
## same rate when the light leaves. Full, it sinks into the floor over
## SINK_FRAMES and stays open. A sunbolt fills it at once: the Glassbearer's
## light is light. A run of `O` cells is one seal, a doorway when it stands
## and a hatch when it lies in the paving -- the Well's mouth.
##
## ## A deed, kept
##
## Opening latches a wire: the seal's mason's mark if it has one, and
## otherwise a wire of its own named for its cell (`implicit_channel()`). A
## respawn puts every mechanism back as authored on a bus that keeps its
## latches, so a seal opened stays open -- the level remembers what you did --
## while the mirrors that opened it go back to facing up. A wired seal is a
## trigger and a receiver both: when its wire comes on from elsewhere it fills
## as if lit and opens. That is how the Well's mouth opens the summit's great
## door, which carries the same mark: the last ray goes down the tower into
## the mouth, and the door at the top answers.
##
## ## The secret kind
##
## `Q` places this same seal over a secret room (Tiles.SEAL_LEGEND): stone in
## the grid until the room is found, which the secret keeper owns. It fills as
## any seal does and, full, asks for its room through
## `Contact.reveal_secret()` -- the count, the chime and the reveal are the
## secret keeper's, as for every secret -- and latches nothing: a found secret
## stays found by the secret keeper's own rule. Its node sits at the top of
## its doorway, in the stone above it, because the secret keeper hides what is
## inside a room until it is found, and the carved sun is the tell, not the
## prize.
##
## ## Telling the proof
##
## A door changes a cell -- stone while shut, air once open -- and what opens
## it is a setting of the mirrors, which only the level's light can answer.
## `reach()` hands both to SunProof (scripts/levels/sun_proof.gd), which
## traces every setting of the mirrors that can reach this seal and says, in
## the ReachModel's terms, from where it can be opened and which other doors
## must be open first. A secret seal says nothing: the secrets audit owns it.

const FILL_FRAMES := 27
const SINK_FRAMES := 30
const RAYS := 8
## The rays' rising ticks: the relic voice up a major scale, one per ray.
const RAY_STEPS: Array[int] = [0, 2, 4, 5, 7, 9, 11, 12]

enum Phase { SHUT, SINKING, OPEN }

var phase: Phase = Phase.SHUT
## How full the carved sun is, 0 to 1.
var fill := 0.0
## Frames into the sink.
var sinking := 0
## Over a secret room: opens it through the secret keeper, latches nothing.
var secret := false
## Its wire came on from elsewhere: it fills as if lit.
var answering := false

var _bolted := false
var _rays := 0
var _art: SunSealArt


func _setup() -> void:
	add_to_group(SunField.SEALS)
	secret = level != null and level.data != null \
		and String(level.data.seals.get(_anchor(), "")) == "sun"
	position = Vector2(_top_left()) * TILE
	var open := _already_open()
	phase = Phase.OPEN if open else Phase.SHUT
	fill = 1.0 if open else 0.0
	sinking = SINK_FRAMES if open else 0
	_rays = RAYS if open else 0
	if not secret:
		set_kind(Tiles.Kind.EMPTY if open else Tiles.Kind.SOLID)
	_art = SunSealArt.new()
	_art.name = "Sun"
	_art.seal = self
	add_child(_art)
	SunField.touch()


## The wire opening this seal latches: its mason's mark's, or its own.
func latch_channel() -> StringName:
	return channel if channel != &"" else implicit_channel(cells)


## The wire an unwired seal latches when it opens, named for its anchor --
## the bottom-left cell, where the level parser anchors every run.
static func implicit_channel(run: Array[Vector2i]) -> StringName:
	var anchor := run[0]
	for cell: Vector2i in run:
		if cell.y > anchor.y or (cell.y == anchor.y and cell.x < anchor.x):
			anchor = cell
	return StringName("sun@%d,%d" % [anchor.x, anchor.y])


## Lying in the paving rather than standing in a wall.
func is_hatch() -> bool:
	return _bounds().size.x > _bounds().size.y


## The doorway, in world pixels.
func door_rect() -> Rect2:
	var box := _bounds()
	return Rect2(Vector2(box.position) * TILE, Vector2(box.size) * TILE)


## A sunbolt struck it: full at once, on the next frame it is met.
func take_bolt() -> void:
	if phase == Phase.SHUT:
		_bolted = true


func meet(contact: Contact) -> void:
	match phase:
		Phase.SHUT:
			var lit := answering or SunField.rests_on(level, cells)
			if _bolted:
				fill = 1.0
			else:
				fill = clampf(fill + (1.0 if lit else -1.0) / float(FILL_FRAMES), 0.0, 1.0)
			_bolted = false
			_tick_rays()
			if fill >= 1.0:
				_open(contact)
		Phase.SINKING:
			sinking += 1
			if sinking >= SINK_FRAMES:
				phase = Phase.OPEN
				if not secret:
					set_kind(Tiles.Kind.EMPTY)
				SunField.touch()


func _on_channel(on: bool) -> void:
	if on and phase == Phase.SHUT:
		answering = true


func _open(contact: Contact) -> void:
	phase = Phase.SINKING
	sinking = 0
	fill = 1.0
	if secret:
		# The secret keeper chimes and reveals; the seal only sinks.
		contact.reveal_secret(_anchor(), door_rect().get_center())
		return
	cue.emit(&"secret", {})
	cue.emit(&"masonry", {"pitch": 0.7, "volume_db": -4.0})
	if bus != null:
		bus.latch(latch_channel())


func _already_open() -> bool:
	if level == null or level.data == null:
		return false
	if secret:
		return level.data.opened.has(level.data.secret_at(_anchor()))
	return bus != null and bus.is_on(latch_channel())


## A ray lights: its tick, a step up the scale. Draining is silent.
func _tick_rays() -> void:
	var now := mini(RAYS, floori(fill * float(RAYS) + 0.0001))
	if now > _rays:
		var step := RAY_STEPS[clampi(now - 1, 0, RAYS - 1)]
		cue.emit(&"relic", {"pitch": 0.8 * pow(2.0, float(step) / 12.0), "volume_db": -10.0})
	_rays = now


func lit_rays() -> int:
	return _rays


func _anchor() -> Vector2i:
	var anchor := cells[0]
	for cell: Vector2i in cells:
		if cell.y > anchor.y or (cell.y == anchor.y and cell.x < anchor.x):
			anchor = cell
	return anchor


func _top_left() -> Vector2i:
	return _bounds().position


func _bounds() -> Rect2i:
	var low := cells[0]
	var high := cells[0]
	for cell: Vector2i in cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	return Rect2i(low, high - low + Vector2i.ONE)


## Stone while shut, air once open, and opened by a setting of the mirrors:
## SunProof says which, from where, and behind which other doors.
static func reach(mark: Dictionary, model: ReachModel) -> void:
	SunProof.describe_seal(mark, model)


## --- drawing -----------------------------------------------------------------

## How far the slab has gone down into the floor, in pixels.
func sunk() -> float:
	if phase == Phase.SHUT:
		return 0.0
	var depth := door_rect().size.y
	return depth * clampf(float(sinking) / float(SINK_FRAMES), 0.0, 1.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if phase == Phase.OPEN:
		return
	var size := door_rect().size
	var drop := sunk()
	var slab := Rect2(Vector2(0.0, drop), Vector2(size.x, size.y - drop))
	if slab.size.y <= 0.0:
		return
	# The slab: a recessed door in shade, its sun-facing edge lit, its frame
	# ink. The carving is drawn here in the stone's own dark; the light that
	# fills it is the lifted art's.
	draw_rect(slab, Palette.SHADOW_DEEP)
	draw_rect(Rect2(slab.position, Vector2(1.0, slab.size.y)), Palette.SHADOW_WARM)
	draw_rect(Rect2(Vector2(slab.end.x - 1.0, slab.position.y), Vector2(1.0, slab.size.y)),
		Palette.INK)
	if drop <= 0.0:
		draw_rect(Rect2(slab.position, Vector2(slab.size.x, 1.0)), Palette.INK)
	# Courses of masonry across the slab, every half tile.
	var y := float(TILE) * 0.5
	while y < size.y:
		if y > drop:
			draw_rect(Rect2(1.0, y, size.x - 2.0, 1.0), Palette.SHADOW_PIT)
		y += float(TILE) * 0.5
	var centre := SunSealArt.sun_centre(size) + Vector2(0.0, drop)
	if centre.y + SunSealArt.SUN_R + 1.0 <= size.y:
		draw_circle(centre, SunSealArt.SUN_R + 1.0, Palette.INK)
		draw_circle(centre, SunSealArt.SUN_R, Palette.SHADOW_PIT)
