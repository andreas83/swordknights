class_name SunMirror
extends Mechanism
## A sun mirror: a bronze disc on a pivot that throws the low sun the way its
## face points, and turns a quarter clockwise when the sword strikes it
## (docs/campaign.md, "Sun mirrors and sun-seals").
##
## ## Lit, and what it throws
##
## A mirror is lit when the sun reaches its pivot -- the dressed shadow mask
## says so, with the level's horizon in it, and no shut door stands in the
## lane back to the sun -- or when a beam ends on it. A lit mirror throws a
## beam from its centre along its face, one of four directions, and the light
## of the whole level is traced in one place (SunField, SunLight), because
## whether this mirror is lit depends on every other one.
##
## The mask is read once, when the mirror is placed: it is the same mask the
## world shader draws, solved once at load, so "lit" here is exactly the gold
## the player sees on the disc. What changes in play is the doors, and those
## are checked live against the few cells of the lane back to the sun.
##
## ## The strike
##
## A swing, an air slash or a plunge whose rect touches the disc turns it a
## quarter clockwise, once per swing: the strike is the moment the blade
## starts touching, so a blade that rests on the disc for the eight live
## frames of a swing turns it once. That is the verb that opens a cracked
## wall, so a player who has opened one already knows how to aim the sun. A
## turn takes TURN_FRAMES, and the beam is dark while it does -- long enough
## to see that something happened, short enough that two strikes in a row
## are a rhythm and not a wait.
##
## Every mirror starts facing up, throwing its light at the sky: a column of
## light over a mirror, seen from far below, is the tell that it can be
## turned. A respawn puts every mirror back facing up -- a trap resets -- and
## the doors they opened stay open, because a seal latches (SunSeal).
##
## ## Drawing
##
## The mirror is part of the city and takes the hour's grade like the stone
## it stands on; its light is not (MatchDusk.LIT), because a beam that dims
## at dusk is a beam the player cannot follow. So the beam and the polished
## face are drawn by a lifted child, SunBeamArt, and the bronze, the pivot
## and the mount by this node. The disc is seen edge-on: a polished face and
## a dark back, and whichever way the polished face points is where the light
## goes.
##
## A mirror declared with `great=1` (`;! mark G sun_mirror great=1`) is drawn
## larger, rimmed with the sun's rays: the summit's great mirror, the one the
## whole chapter is about. It behaves as every other mirror does.
##
## ## The sun goes under
##
## A mirror declared with `sunset=<wire>` sets the sun when that wire latches:
## SUNSET_FRAMES of physics steps later no mirror and no glass in the level is
## lit by the sun any more (SunField.sun_is_down()), and while they run the
## Sunset node walks the grade to night. Counted in steps, so it is the same
## on every device; kept by the wire's latch, so a respawn after it is a
## respawn into the night. The great mirror carries it: when the last ray has
## gone down into the Well, its wire latches, and the day is over.

const TURN_FRAMES := 6
## The disc's radius, in pixels: what a blade must touch.
const DISC_R := 5.0
const GREAT_R := 7.0
## How long the sun takes to go under once a sunset wire latches: three
## seconds, long enough to watch the light leave the tower, short enough that
## the player is already walking to the door through it.
const SUNSET_FRAMES := 180

## How the disc is held: on a post from the floor, on an arm from a wall
## beside it, or on a chain from the stone above.
enum Mount { FLOOR, WALL_LEFT, WALL_RIGHT, HUNG }

## Where the polished face points (SunLight.Face). Starts facing up.
var face: int = SunLight.Face.UP
var great := false

var _next_face: int = SunLight.Face.UP
var _turn_left := 0
var _touching := false
var _sun_in_mask := false
var _lane: Array[Vector2i] = []
var _mount: Mount = Mount.FLOOR
var _beam: SunBeamArt
## The wire whose latch sets the sun, or none; and the steps since it did.
var _sunset_wire: StringName = &""
var _sunset := 0


func _setup() -> void:
	add_to_group(SunField.MIRRORS)
	great = String(params.get("great", "")) not in ["", "0", "false"]
	position = SunLight.pivot(cell())
	face = SunLight.Face.UP
	_next_face = face
	if level != null and level.data != null:
		_mount = _mount_of(level.data, cell())
		var light := TimeOfDay.light_of(level.data)
		_sun_in_mask = _reads_lit(level.data, light)
		_lane = SunLight.sun_lane(position, float(light["reach"]))
	_beam = SunBeamArt.new()
	_beam.name = "Beam"
	_beam.mirror = self
	add_child(_beam)
	_sunset_wire = StringName(String(params.get("sunset", "")))
	if _sunset_wire != &"":
		# A respawn after the sun went down comes back into the night.
		_sunset = SUNSET_FRAMES if bus != null and bus.is_on(_sunset_wire) else 0
		var sunset := Sunset.new()
		sunset.name = "Sunset"
		sunset.mirror = self
		add_child(sunset)
	SunField.touch()


## The cell the mirror stands in.
func cell() -> Vector2i:
	return cells[0] if not cells.is_empty() else Vector2i.ZERO


## Mid-turn: the beam is dark.
func is_turning() -> bool:
	return _turn_left > 0


## Whether the sun itself reaches the pivot now: lit in the mask, and no
## door shut across the lane back to the sun.
func sun_reaches() -> bool:
	if not _sun_in_mask or level == null or SunField.sun_is_down(level):
		return false
	for at: Vector2i in _lane:
		var kind := level.overlay_at(at)
		if kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM:
			return false
	return true


## Lit this frame, by the sun or by a beam.
func is_lit() -> bool:
	return (SunField.light_of(level)["lit"] as Dictionary).has(cell())


## The disc, in world pixels: what a blade has to touch.
func disc_rect() -> Rect2:
	var r := GREAT_R if great else DISC_R
	return Rect2(position - Vector2(r, r), Vector2(r, r) * 2.0)


## A quarter turn clockwise, now.
func strike() -> void:
	_next_face = SunLight.turned(face)
	_turn_left = TURN_FRAMES
	SunField.touch()
	cue.emit(&"sword_hit", {"pitch": 1.6, "volume_db": -8.0})
	# Bronze answers the blade: the smallest held beat there is, the same a
	# block gets. Something resisted the sword, and it moved.
	impact.emit(position, 2, 0.5, 0.25)
	queue_redraw()


## How far the sun has gone under, 0 to 1: 0 until this mirror's sunset wire
## latches, 1 once SUNSET_FRAMES have passed since.
func sunset_progress() -> float:
	return clampf(float(_sunset) / float(SUNSET_FRAMES), 0.0, 1.0)


## The blade: a strike on the frame it starts touching the disc.
func meet(contact: Contact) -> void:
	if _sunset_wire != &"" and _sunset < SUNSET_FRAMES and bus != null \
			and bus.is_on(_sunset_wire):
		_sunset += 1
		if _sunset == SUNSET_FRAMES:
			SunField.touch()
	if _turn_left > 0:
		_turn_left -= 1
		if _turn_left == 0:
			face = _next_face
			SunField.touch()
		queue_redraw()
	var touching := contact.has_blade() and contact.blade.intersects(disc_rect())
	if touching and not _touching and _turn_left == 0:
		strike()
	_touching = touching


## How far through the current turn, 0 to 1; 0 when still.
func turn_progress() -> float:
	if _turn_left <= 0:
		return 0.0
	return 1.0 - float(_turn_left) / float(TURN_FRAMES)


## The angle the polished face points at, in radians, turning included: 0 is
## right, and up is -PI/2, as Godot's y runs down.
func face_angle() -> float:
	return (float(face) - 1.0 + turn_progress()) * PI * 0.5


## A mirror changes no cell: the proof hears about it from the seals, which
## ask the level's light what each setting of the mirrors would open
## (scripts/levels/sun_proof.gd).
static func reach(_mark: Dictionary, _model: ReachModel) -> void:
	pass


func _reads_lit(data: AsciiLevel, light: Dictionary) -> bool:
	if not bool(light["sun"]):
		return false
	var mask := SunShadow.last_mask
	var size := Vector2i(data.cols * Level.TILE, data.rows * Level.TILE)
	var step := 1
	while size.x / step > SunShadow.MAX_MASK_PX or size.y / step > SunShadow.MAX_MASK_PX:
		step *= 2
	if mask != null and mask.get_size() == size / step:
		var px := Vector2i(position) / step
		return mask.get_pixelv(px).r < 0.5
	# No mask to read -- a level built without a renderer: the bare terrain's
	# answer, which the proof uses and a test holds equal to the mask's.
	return SunProof.bare_sun_reaches(data, position, light)


static func _mount_of(data: AsciiLevel, at: Vector2i) -> Mount:
	if data.is_solid(at.x, at.y + 1):
		return Mount.FLOOR
	if data.is_solid(at.x - 1, at.y):
		return Mount.WALL_LEFT
	if data.is_solid(at.x + 1, at.y):
		return Mount.WALL_RIGHT
	return Mount.HUNG


## --- drawing -----------------------------------------------------------------

const BRONZE_LIT := Palette.LIGHT_WARM
const BRONZE_SHADE := Palette.SHADOW_WARM
const IRON := Palette.SHADOW_DEEP
const IRON_SHADE := Palette.INK


func _draw() -> void:
	_draw_mount()
	var r := GREAT_R if great else DISC_R
	var angle := face_angle()
	var normal := Vector2(cos(angle), sin(angle))
	var along := Vector2(-normal.y, normal.x)
	# The back of the disc: a thin dark lens behind the polished face.
	var back := PackedVector2Array()
	for i: int in 12:
		var a := TAU * float(i) / 12.0
		back.append(along * cos(a) * r + normal * (sin(a) * 1.6 - 0.6))
	draw_colored_polygon(back, IRON_SHADE)
	# The bronze rim, the world-left half in the sun.
	var rim := PackedVector2Array([
		along * r + normal * 0.4, along * r - normal * 1.4,
		-along * r - normal * 1.4, -along * r + normal * 0.4,
	])
	draw_colored_polygon(rim, BRONZE_SHADE)
	if great:
		_draw_rays(r, normal, along)
	# The axle.
	draw_rect(Rect2(-1.0, -1.0, 2.0, 2.0), BRONZE_LIT)


func _draw_mount() -> void:
	var tile := float(Level.TILE)
	match _mount:
		Mount.FLOOR:
			# A two-pixel post from the floor to the axle, and its foot.
			draw_rect(Rect2(-1.0, 0.0, 2.0, tile * 0.5), IRON)
			draw_rect(Rect2(-1.0, 0.0, 1.0, tile * 0.5), BRONZE_SHADE)
			draw_rect(Rect2(-3.0, tile * 0.5 - 2.0, 6.0, 2.0), IRON_SHADE)
			draw_rect(Rect2(-3.0, tile * 0.5 - 2.0, 3.0, 1.0), BRONZE_SHADE)
		Mount.WALL_LEFT:
			draw_rect(Rect2(-tile * 0.5, -1.0, tile * 0.5, 2.0), IRON)
			draw_rect(Rect2(-tile * 0.5, -1.0, tile * 0.5, 1.0), BRONZE_SHADE)
		Mount.WALL_RIGHT:
			draw_rect(Rect2(0.0, -1.0, tile * 0.5, 2.0), IRON)
			draw_rect(Rect2(0.0, -1.0, tile * 0.5, 1.0), BRONZE_SHADE)
		Mount.HUNG:
			_draw_hanger()


## A mirror with nothing under it and no wall beside it hangs from the
## stone: on a bracket from whichever corner below holds it, or on a chain
## from above.
func _draw_hanger() -> void:
	var tile := float(Level.TILE)
	var data := level.data if level != null else null
	var at := cell()
	var side := 0
	if data != null:
		if data.is_solid(at.x + 1, at.y + 1):
			side = 1
		elif data.is_solid(at.x - 1, at.y + 1):
			side = -1
	if side != 0:
		# A bracket springing from the corner of the stone below.
		var foot := Vector2(side * tile * 0.5, tile * 0.5)
		var knee := Vector2(side * tile * 0.25, tile * 0.25)
		draw_line(foot, knee, IRON, 2.0)
		draw_line(knee, Vector2.ZERO, IRON, 2.0)
		draw_line(foot + Vector2(-side * 0.5, -0.5), knee + Vector2(-side * 0.5, -0.5),
			BRONZE_SHADE, 1.0)
		return
	var y := -tile * 0.5
	while y < -2.0:
		draw_rect(Rect2(-1.0, y, 2.0, 2.0), IRON)
		y += 3.0


## The great mirror's rim: eight short rays of bronze round the disc, the
## sun the masons carved on everything that catches it.
func _draw_rays(r: float, normal: Vector2, along: Vector2) -> void:
	for i: int in 8:
		var a := TAU * float(i) / 8.0 + PI / 8.0
		var dir := along * cos(a) + normal * sin(a) * 0.35
		var from := dir * (r + 1.0)
		var to := dir * (r + 3.0)
		draw_line(from, to, BRONZE_LIT if dir.x < 0.0 else BRONZE_SHADE, 1.0)
