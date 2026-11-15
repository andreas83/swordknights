class_name Glassbearer
extends Foe
## The King's mirror-man: a tall, thin figure with a burning glass on a staff,
## who throws the sun at the prince -- and only while the sun is on his glass
## (docs/campaign.md, "The Glassbearer -- the parry").
##
## ## The rule is on the foe
##
## His glass is lit when the sun reaches it -- the same dressed shadow mask
## the world is drawn with, the horizon included, and no shut door in the
## lane back to the sun -- or when a beam crosses it (SunField). Lit, the
## disc is LIGHT_SOFT; dark, it is SHADOW_PIT; and a Glassbearer whose glass
## is dark does nothing but walk. So the chapter's whole rule is visible on
## the foe before he ever acts: the one in the square, in the city's shadow,
## paces with a dull glass and is no danger at all, and that is the lesson.
##
## ## One threat, told the standard way
##
## He hurts in one way only, the sunbolt (scripts/entities/sunbolt.gd), and
## he cannot loose one except at the end of AIM: WINDUP_TIME read through
## warn(), the sentinel's 27 frames, during which the staff tips toward the
## prince, the disc brightens in three steps and a star grows on it, and the
## glass whines up an octave (`glass_charge`). He aims only at a prince on
## his own floor, within RANGE, in a clear line, and only while he is in the
## frame the camera shows -- the bible's ranges are maxima, and a foe that
## fires from off screen is a death nobody could read.
##
## Then SPENT: the glass dull for a second while it gathers the sun again,
## and the Glassbearer backs away from a prince who has closed in. That is
## the opening, and it is wide: one heart, so one swing.
##
## ## The counters
##
## The parry turns his bolt and sends it home (FoeProjectile.reflect()): it
## kills him. A crouch lets it pass overhead -- it flies at chest height, over
## a crouching prince's 13 px. A mirror in the line turns it, a wall stops
## it, and reaching him is one swing. The backstep does not help: "the
## backstep survives blades, not bolts".
##
## The duel's moves (docs/campaign.md, "What each foe does with the duel's
## moves"): the bolt flies over a roll's tuck by height, so a roll closes on
## him under fire; a dive kick or a sweep jolts the glass off the sun and
## knocks him out of his aim into SPENT with no wound (knock()); a thrown
## sword is a blade, and one heart is all he has.
##
## ## Posted, not patrolling
##
## He walks a short beat round the post the level gave him, BEAT either way,
## and turns at its end as at a wall or a drop. A sentinel's beat is the
## floor; a Glassbearer's is a station, because what he does depends on
## where he stands -- in the sun or out of it, at a window or not -- and the
## level is designed around that place: the balcony outside R6's doorway, the
## last gold at the summit. One that wandered in through the doorway he was
## posted to fire through would be a different chapter.
##
## ## Simulation and drawing
##
## As the sentinel's: `tick()` is the whole decision for a frame and needs
## no physics world, so tests drive it directly; GlassbearerArt reads
## `state`, `state_time`, `facing` and `glass` and poses a figure from them.

## The aim began: the warning.
signal aimed()
## A bolt left the glass.
signal fired(bolt: Sunbolt)

enum State { WALK, LOOK, AIM, SPENT, DYING }

const SPEED := 20.0
const GRAVITY := 900.0
const MAX_FALL := 320.0
## The robe: what a blade and a stomp find.
const BODY := Vector2(9.0, 22.0)
## The disc's centre, up from the feet: higher than anyone else's outline.
const GLASS_HEIGHT := 28.0
const GLASS_R := 3.5
## The bolt leaves at chest height on a standing prince, over a crouching one.
const BOLT_HEIGHT := 15.0
## The telegraph: the sentinel's, so a player who reads one reads both.
const WINDUP_TIME := Patrol.WINDUP_TIME
## The glass gathering the sun again after a shot.
const SPENT_TIME := 1.0
const LOOK_TIME := 0.6
const DEATH_TIME := 1.3
## He aims at a prince this far away at most, in pixels: twelve tiles.
const RANGE := 12.0 * 16.0
## A prince's feet this close to his, up or down, is on his floor.
const SAME_FLOOR := 16.0
## A prince closer than this while the glass is spent is backed away from.
const CROWDED := 3.0 * 16.0
## How far from his post his beat runs, either way: a tile and a half.
const BEAT := 24.0
## The test seam's frame (frame_half_width) is centred on the prince, so this
## much of it is kept back from the edge before he counts as on screen: the
## camera leads the prince by up to its look-ahead.
const FRAME_MARGIN := 34.0 + 10.0

var facing: int = -1
var state: State = State.WALK
var state_time: float = 0.0
## The glass is lit this frame.
var glass := false
## Test seam: the half-width of a frame centred on the prince that he must be
## inside to act, or 0 for the frame the camera really shows (CameraView).
var frame_half_width := 0.0

## Where the level posted him: the middle of his beat.
var _post_x := 0.0


func _ready() -> void:
	super()
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	up_direction = Vector2.UP
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BODY
	shape.shape = rect
	shape.position = Vector2(0.0, -BODY.y * 0.5)
	add_child(shape)
	if get_node_or_null("Art") == null:
		var art := GlassbearerArt.new()
		art.name = "Art"
		add_child(art)


func place(site: EntitySite) -> void:
	super(site)
	_post_x = site.at.x


func bounds() -> Rect2:
	return Rect2(global_position - Vector2(BODY.x * 0.5, BODY.y), BODY)


func is_alive() -> bool:
	return state != State.DYING


## His threat is the bolt, which is its own danger once it leaves the glass.
func is_dangerous() -> bool:
	return false


func is_engaged() -> bool:
	return state == State.AIM


## The aim's length: the telegraph, through the LONGER WARNINGS assist.
func aim_time() -> float:
	return warn(WINDUP_TIME)


## The feet: the glass jolted off the sun. Out of an aim -- or into a fresh
## spent second if he was already spent -- and no wound, so the kick buys
## the prince the same opening a fired bolt does without the bolt.
func knock(_from_x: float) -> bool:
	if not is_alive():
		return false
	_enter(State.SPENT)
	velocity.x = 0.0
	return true


## One heart: any blow that lands kills him.
func hit(_from_x: float) -> bool:
	if not is_alive():
		return false
	_enter(State.DYING)
	velocity = Vector2(0.0, velocity.y)
	defeated.emit()
	cue.emit(&"shatter", {})
	return true


## Where his glass is, in world pixels.
func glass_point() -> Vector2:
	var lean := 0.0
	if state == State.AIM:
		lean = 4.0 * clampf(state_time / maxf(aim_time(), 0.001), 0.0, 1.0)
	return global_position + Vector2(float(facing) * (2.0 + lean), -GLASS_HEIGHT)


func _physics_process(delta: float) -> void:
	glass = glass_lit()
	tick(delta, is_on_floor())
	move_and_slide()
	if is_on_wall() and state == State.WALK:
		facing = -facing
	if state == State.DYING and state_time >= DEATH_TIME:
		queue_free()
	elif level != null and global_position.y > level.world_size().y + 64.0:
		queue_free()


## One frame of decision. Takes `grounded` rather than asking the physics
## body, and reads `glass` as set, so it runs with no physics world.
func tick(delta: float, grounded: bool) -> void:
	state_time += delta
	velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)
	match state:
		State.WALK:
			velocity.x = facing * SPEED
			if grounded and _sees_prince():
				_start_aim()
				return
			if _beat_ends(grounded, facing) or _off_post(facing):
				_enter(State.LOOK)
				velocity.x = 0.0
		State.LOOK:
			velocity.x = 0.0
			if grounded and _sees_prince():
				_start_aim()
				return
			if state_time >= LOOK_TIME:
				facing = -facing
				_enter(State.WALK)
		State.AIM:
			velocity.x = 0.0
			if not glass:
				# The sun left the glass mid-aim: it gutters, and he walks on.
				_enter(State.WALK)
				return
			if state_time >= aim_time():
				_fire()
		State.SPENT:
			velocity.x = 0.0
			var away := _backing_off()
			if away != 0 and not _beat_ends(grounded, away) and not _off_post(away):
				velocity.x = away * SPEED
			if state_time >= SPENT_TIME:
				_enter(State.WALK)
		State.DYING:
			velocity.x = 0.0


## The prince is someone he can shoot now: his glass lit, the prince on his
## floor, within range, in a clear line, and both of them in the frame.
func _sees_prince() -> bool:
	if not glass or target_rect.size == Vector2.ZERO:
		return false
	var feet := target_rect.end.y
	if absf(feet - global_position.y) > SAME_FLOOR:
		return false
	var centre := target_rect.get_center().x
	var gap := absf(centre - global_position.x)
	if gap > RANGE or not _in_frame(gap):
		return false
	return _clear_line(centre)


func _start_aim() -> void:
	facing = 1 if target_rect.get_center().x > global_position.x else -1
	velocity.x = 0.0
	_enter(State.AIM)
	aimed.emit()
	# A longer warning is the same whine drawn out, so it ends on the shot.
	cue.emit(&"glass_charge", {"pitch": 1.0 / Assist.warning_scale()})


func _fire() -> void:
	var at := global_position + Vector2(float(facing) * (BODY.x * 0.5 + 2.0), -BOLT_HEIGHT)
	var bolt := Sunbolt.make(at, Vector2(facing, 0.0))
	launch(bolt)
	fired.emit(bolt)
	cue.emit(&"sword", {"pitch": 1.8, "volume_db": -6.0})
	_enter(State.SPENT)


## Nothing between his glass's line and the prince that stops light, along
## the row his bolt would fly in.
func _clear_line(to_x: float) -> bool:
	if level == null:
		return true
	var y := global_position.y - BOLT_HEIGHT
	var from := level.cell_of(Vector2(global_position.x, y))
	var to := level.cell_of(Vector2(to_x, y))
	var step := 1 if to.x >= from.x else -1
	for x: int in range(from.x, to.x + step, step):
		var cell := Vector2i(x, from.y)
		if SunField.stops_light_at(level.data, cell, level.kind_at_cell(cell)):
			return false
	return true


## -1 or 1 to back away from a prince crowding a spent glass; 0 otherwise.
func _backing_off() -> int:
	if target_rect.size == Vector2.ZERO:
		return 0
	if absf(target_rect.end.y - global_position.y) > SAME_FLOOR:
		return 0
	var dx := global_position.x - target_rect.get_center().x
	if absf(dx) > CROWDED:
		return 0
	return 1 if dx >= 0.0 else -1


## Whether he is in the frame, `gap` from the prince: all of him inside the
## rectangle the camera shows (CameraView), as the owl and the blades ask.
##
## It used to be an estimate -- the viewport's half-width round the prince,
## less the look-ahead the camera might lead him by -- which was safe at 1:1
## and, once the Adventure's camera went to 1.5x (GameCamera.ZOOM), left him
## 62 units of reach on a 320-unit screen and 36 on a 4:3 one: R5's slot in
## Chapter IV is 69 from the wall the prince stands at, so the encounter could
## never open. The real frame is what the rule is about, and it is cheaper
## to ask than to bound.
func _in_frame(gap: float) -> bool:
	if frame_half_width > 0.0:
		return gap <= maxf(0.0, frame_half_width - FRAME_MARGIN)
	return CameraView.rect_for(self).encloses(bounds())


## Whether his glass is lit now: the sun on it, or a beam through it.
func glass_lit() -> bool:
	if level == null or level.data == null:
		return false
	var at := glass_point()
	if SunField.beam_crosses(level, level.cell_of(at)):
		return true
	return _sun_reaches(at)


func _sun_reaches(at: Vector2) -> bool:
	var light := TimeOfDay.light_of(level.data)
	if not bool(light["sun"]) or SunField.sun_is_down(level):
		return false
	var px := Vector2i(at.floor())
	var mask := SunShadow.last_mask
	var size := Vector2i(level.data.cols * Level.TILE, level.data.rows * Level.TILE)
	var lit := false
	if mask != null and mask.get_size() == size:
		if px.x < 0 or px.y < 0 or px.x >= size.x or px.y >= size.y:
			lit = px.y < 0
		else:
			lit = mask.get_pixelv(px).r < 0.5
	else:
		lit = SunProof.bare_sun_reaches(level.data, at, light)
	if not lit:
		return false
	for cell: Vector2i in SunLight.sun_lane(at, float(light["reach"])):
		var kind := level.overlay_at(cell)
		if kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM:
			return false
	return true


## Going `toward` would take him past the end of his beat.
func _off_post(toward: int) -> bool:
	return (global_position.x - _post_x) * float(toward) >= BEAT


## A wall ahead, or the floor running out under the next step -- the end of
## his beat, as for the sentinel.
func _beat_ends(grounded: bool, toward: int) -> bool:
	if level == null or not grounded:
		return false
	var ahead_x := global_position.x + (BODY.x * 0.5 + 2.0) * toward
	var wall := level.looks_solid_at(Vector2(ahead_x, global_position.y - 4.0))
	var ground_kind := level.kind_at_world(Vector2(ahead_x, global_position.y + 2.0))
	var ground := ground_kind == Tiles.Kind.SOLID or ground_kind == Tiles.Kind.PLATFORM
	return wall or not ground


func _enter(next: State) -> void:
	state = next
	state_time = 0.0
