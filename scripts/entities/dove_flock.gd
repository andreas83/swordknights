class_name DoveFlock
extends Node2D
## A few doves pecking on a lit terrace: the city's life
## (docs/campaign.md, "The doves -- the city's life").
##
## Not a foe and nothing to collect. Three to five birds, 3 x 2 px of
## LIGHT_SOFT, peck along the stretch of floor they were placed on. When the
## prince runs (or falls, or lands) within STARTLE_TILES they burst up -- three
## soft wingbeats, `cloth` high and quiet -- and settle at the far end of their
## stretch; if no end is far enough from him they leave, and come back to
## where they were put a while later. A pounce startles them as it leaves the
## ground, which is the whole of the Caracal's demonstration: it always lands
## on the spot they have just left (scripts/entities/caracal.gd).
##
## ## What it costs
##
## Nothing the prince can touch. A flock never collides, never hurts, never
## blocks a probe and never changes what the proof can reach, so the
## reachability proof does not know it exists. Its few numbers -- where it
## pecks, whether it is in the air -- are stepped in physics frames from what
## it has seen of the prince, so the cat that hunts it, which is simulation,
## sees the same flock on every run.
##
## ## Any chapter can place one
##
## Its glyph is `v` (Tiles.ENTITY_LEGEND): a bird, drawn the way a child
## would. The stretch it pecks along is found from the level, on the row it
## was placed in: every cell a body can stand in, joined to its own, up to
## SPAN_TILES each way. `;! mark` can place one too, with `count=` for the
## number of birds. Doves go to roost at dusk: a level set at `dusk` or
## `night` places none, which is where the owls hunt instead.

signal cue(voice: StringName, options: Dictionary)

## A flock never in the air for anything that walks: only a run, a fall or a
## landing this close puts it up.
const STARTLE_TILES := 3
const SPAN_TILES := 6
const FLY_FRAMES := 66
const LEAVE_FRAMES := 60
const AWAY_FRAMES := 420
const FLIGHT_HEIGHT := 26.0
const GROUP := &"doves"
const BIRD := Palette.LIGHT_SOFT
const BIRD_SHADE := Palette.LIGHT_WARM
## Wingbeats when a flock goes up: the `cloth` voice, high and quiet.
const BEATS := [0, 5, 10]

enum Mood { PECKING, FLYING, LEAVING, AWAY, RETURNING }

var level: Level
var post := ""
var mood: Mood = Mood.PECKING
var count := 4

var _floor_y := 0.0
var _span := Vector2.ZERO
var _home := 0.0
var _x := 0.0
var _from := 0.0
var _to := 0.0
var _frames := 0
var _clock := 0
var _roosting := false
var _birds: Array[Dictionary] = []


func place(site: EntitySite) -> void:
	position = site.at
	level = site.level
	post = site.post
	_floor_y = site.at.y
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(post)
	count = clampi(int(site.param("count", str(3 + rng.randi() % 3))), 1, 9)
	_span = _stretch(site.cell)
	_home = site.at.x
	_x = _home
	_roosting = _is_evening()
	for i: int in count:
		_birds.append({
			"dx": (float(i) - float(count - 1) * 0.5) * 5.0 + rng.randf_range(-1.5, 1.5),
			"phase": rng.randf() * TAU, "facing": 1.0 if rng.randf() < 0.5 else -1.0,
			"rate": rng.randf_range(1.6, 2.6),
		})
	if not _roosting:
		add_to_group(GROUP)
	visible = not _roosting


## Where the flock is pecking: the feet of its middle bird.
func spot() -> Vector2:
	return Vector2(_x, _floor_y)


func is_settled() -> bool:
	return mood == Mood.PECKING and not _roosting


## Something came at it from `from_x`: up they go.
func startle(from_x: float) -> void:
	if not is_settled():
		return
	_from = _x
	var west := _span.x
	var east := _span.y
	_to = west if absf(west - from_x) > absf(east - from_x) else east
	_frames = 0
	if absf(_to - from_x) < STARTLE_TILES * Level.TILE + 8.0 or absf(_to - _x) < 8.0:
		mood = Mood.LEAVING
	else:
		mood = Mood.FLYING


func meet(contact: Contact) -> void:
	if not is_settled() or not contact.alive:
		return
	var near := absf(contact.feet.x - _x) <= STARTLE_TILES * Level.TILE \
		and absf(contact.feet.y - _floor_y) <= 2.0 * Level.TILE
	var hurried := absf(contact.velocity.x) > Tuning.WALK_SPEED + 1.0 \
		or absf(contact.velocity.y) > 60.0
	if near and hurried:
		startle(contact.feet.x)


func _physics_process(_delta: float) -> void:
	if _roosting:
		return
	_clock += 1
	match mood:
		Mood.FLYING, Mood.LEAVING:
			if BEATS.has(_frames):
				cue.emit(&"cloth", {"pitch": 2.0, "volume_db": -14.0})
			_frames += 1
			if mood == Mood.FLYING and _frames >= FLY_FRAMES:
				_x = _to
				mood = Mood.PECKING
			elif mood == Mood.LEAVING and _frames >= LEAVE_FRAMES:
				mood = Mood.AWAY
				_frames = 0
		Mood.AWAY:
			_frames += 1
			if _frames >= AWAY_FRAMES:
				mood = Mood.RETURNING
				_frames = 0
				_from = _home
				_x = _home
		Mood.RETURNING:
			_frames += 1
			if _frames >= LEAVE_FRAMES:
				mood = Mood.PECKING


## The floor the flock can peck along: standing cells on its row, joined to
## the one it was placed in, SPAN_TILES each way at most. World x of the two
## ends, a bird's width in from each.
func _stretch(cell: Vector2i) -> Vector2:
	if level == null or level.data == null:
		return Vector2(position.x, position.x)
	var lo := cell.x
	var hi := cell.x
	while lo > cell.x - SPAN_TILES and _perch(Vector2i(lo - 1, cell.y)):
		lo -= 1
	while hi < cell.x + SPAN_TILES and _perch(Vector2i(hi + 1, cell.y)):
		hi += 1
	return Vector2(float(lo) * Level.TILE + 6.0, float(hi + 1) * Level.TILE - 6.0)


func _perch(cell: Vector2i) -> bool:
	var data := level.data
	var below := data.kind_at(cell.x, cell.y + 1)
	return not data.is_solid(cell.x, cell.y) \
		and (below == Tiles.Kind.SOLID or below == Tiles.Kind.PLATFORM)


func _is_evening() -> bool:
	if level == null or level.data == null:
		return false
	var stop := TimeOfDay.stop_of(level.data)
	return stop == "dusk" or stop == "night"


## --- drawing -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _roosting or mood == Mood.AWAY:
		return
	for i: int in _birds.size():
		var bird := _birds[i]
		var at := _bird_at(bird, i) - position
		if mood == Mood.PECKING:
			_draw_pecking(bird, at.round())
		else:
			_draw_flying(i, at.round())


## Where bird `i` is this frame, in world units: pecking along the floor, or
## on its arc through the air.
func _bird_at(bird: Dictionary, i: int) -> Vector2:
	var dx: float = bird["dx"]
	match mood:
		Mood.FLYING:
			var k := float(_frames) / float(FLY_FRAMES)
			var lag := clampf(k * 1.15 - float(i) * 0.04, 0.0, 1.0)
			var x := lerpf(_from, _to, lag) + dx * (1.0 + sin(lag * PI) * 0.8)
			return Vector2(x, _floor_y - sin(lag * PI) * FLIGHT_HEIGHT - 2.0)
		Mood.LEAVING:
			var k := float(_frames) / float(LEAVE_FRAMES)
			var away := signf(_from - _to) if not is_equal_approx(_from, _to) else 1.0
			return Vector2(_from + dx + away * k * 60.0, _floor_y - 2.0 - k * k * 140.0)
		Mood.RETURNING:
			var k := 1.0 - float(_frames) / float(LEAVE_FRAMES)
			return Vector2(_home + dx - k * 50.0, _floor_y - 2.0 - k * k * 120.0)
	var hop := absf(sin(float(_clock) / 60.0 * float(bird["rate"]) + float(bird["phase"])))
	return Vector2(_x + dx + floorf(hop * 2.0) * float(bird["facing"]) * 0.5, _floor_y)


## A body, a head that bobs down to the stone and up, a tail tick.
func _draw_pecking(bird: Dictionary, feet: Vector2) -> void:
	var f: float = bird["facing"]
	var t := float(_clock) / 60.0 * float(bird["rate"]) + float(bird["phase"])
	var down := fmod(t, TAU) < 0.9
	draw_rect(Rect2(feet + Vector2(-1.5, -2.0), Vector2(3.0, 2.0)), BIRD)
	draw_rect(Rect2(feet + Vector2(-1.5, -1.0), Vector2(3.0, 1.0)), BIRD_SHADE)
	var head := feet + Vector2(1.5 * f, -1.0 if down else -3.0)
	draw_rect(Rect2(head - Vector2(0.5, 0.0), Vector2(1.0, 1.0)), BIRD)
	draw_rect(Rect2(feet + Vector2(-2.5 * f - 0.5, -2.0), Vector2(1.0, 1.0)), BIRD_SHADE)


## A body and two wings that beat: up for four frames, down for four.
func _draw_flying(i: int, at: Vector2) -> void:
	var up := (_clock / 4 + i) % 2 == 0
	draw_rect(Rect2(at + Vector2(-1.0, -1.0), Vector2(2.0, 1.0)), BIRD)
	var tip_y := -3.0 if up else 1.0
	draw_line(at + Vector2(-1.0, -1.0), at + Vector2(-3.0, tip_y), BIRD, 1.0)
	draw_line(at + Vector2(1.0, -1.0), at + Vector2(3.0, tip_y), BIRD, 1.0)
