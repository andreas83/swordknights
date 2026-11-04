class_name Bloodshed
extends Node2D
## A kill reads as a kill: a burst thrown the way the blow went, droplets that
## fly and fall, and stains where they land that stay for the life of the level.
##
## ## Hung off the foe contract, so every foe has it
##
## Nothing here names a kind of foe. `install()` watches the level's entity
## node, and every Foe that enters it -- placed from a mark, put back at a
## respawn, summoned by a boss, or a kind that a chapter adds next week -- has
## its `defeated` heard. That signal is the contract's "the killing blow
## landed" (scripts/entities/foe.gd), so a foe that keeps the contract bleeds,
## and one that does not has a bug the contract tests already look for. The
## kill's sound is rung here too, on the same signal: the blood and the sound
## are one beat, and a beat with two owners drifts apart.
##
## ## Directed by the blow
##
## The burst is thrown away from the prince -- the blow came from him, or from
## a shot he sent back -- and up, from the middle of the body the blade
## reached. A few drops go the other way, the way they do, so it is a burst
## and not a jet. A drop that meets stone becomes a stain on it: a short smear
## along a floor, a run down a wall. One pool goes on the floor under the body.
##
## ## Its own red, two tones to every mark, hard pixels, no glow
##
## Blood used to be the cloth crimson, which is the architecture's crimson: it
## read on a gold floor and went out against every wall. It is now the blood
## ramp (Palette.BLOOD, BLOOD_DRIED, BLOOD_WET), the one accent rationed to
## blood alone (docs/art-direction.md). The ramp is set apart from the stone by
## chroma, and each tone of it is still near one stone tone in lightness, so
## every mark is two: a drop in the air is fresh red with the wet glint on its
## sunward corner, a floor smear is fresh over dried, a wall run is a fresh
## blob over a dried run, and a pool is wet with a dried heart and the glint
## on its sunward edge. Whatever it lands on, part of it reads. All of it is
## opaque and on the pixel grid: nothing is blended, faded or blurred.
##
## ## A pool spreads, glistens, and dries
##
## A pool is not a stain: it spreads for POOL_TIME, stays wet -- the glint on
## its sunward edge -- for WET_TIME, then dries from the rim inward over
## DRY_TIME and stays dark. Drying is a hard edge moving in, not a fade. The
## clock is this node's own and stops with the hitstop and the pause, like the
## drops. A foe's pool is wider than it was, and the prince's death leaves one
## too: the two moments the blood exists for.
##
## ## Lit like the stone it lies on
##
## The tiles are drawn by an unshaded shader, so a level's hour (WorldGrade)
## never lands on the stone -- but it lands on everything else on the canvas,
## and blood under the sunset or night multiply went out against the stone it
## was spilled on. Each frame the hour's multiply is taken back off this node,
## so blood is graded exactly as the stone is: not at all by the hour, and by
## the same factor as the stone when the world is put out (WorldGrade.dim). It
## does not join MatchDusk.LIT, because the lit group is lifted out of that
## dim too, and blood glowing in the Eclipse's dark would be a light source.
##
## ## Capped for phones
##
## Drops live in one fixed PackedFloat32Array, like PlayerFx's dust: nothing
## is allocated while playing and a kill can never cost more than MAX_DROPS.
## Stains are a ring of MAX_STAINS rects and pools a ring of MAX_POOLS; past
## either the oldest goes. All of it is drawn in one pass of rects, redrawn
## every frame only while a drop is in the air or a pool is still drying.
##
## ## What a death and a restart do to it
##
## It is a child of Game, not of the entity node a respawn empties, so a
## checkpoint respawn keeps every stain: the level remembers what you did, and
## a guard you cut down stays down beside his blood. A restart is the level
## starting over, and Game calls `clear()` there.
##
## Presentation only. It reads the level's solidity and writes nothing that
## anything else reads.

## Drops in the air at once, across every kill.
const MAX_DROPS := 64
## Stains a level keeps. Far more than a level's foes leave -- a kill leaves
## about a score -- so the oldest only go in a level fought over at length.
const MAX_STAINS := 240
## Pools a level keeps: one a kill and one a death of the prince's.
const MAX_POOLS := 48
## Drops in one kill's burst, in the spatter when the prince is cut, and when
## he dies. His death is louder than a wound and still quieter than a kill:
## the burst is the reward for a blow landed, and his own blood should not
## compete with it.
const KILL_DROPS := 24
const HURT_DROPS := 4
const DEATH_DROPS := 14

const GRAVITY := 300.0
## A drop that has not landed by then is let go without a stain.
const DROP_LIFE := 1.6

## A foe's pool, and the prince's, in pixels wide when spread.
const POOL_MIN := 16
const POOL_MAX := 24
const PRINCE_POOL_MIN := 10
const PRINCE_POOL_MAX := 14
## Seconds a pool spreads, stays wet, and then takes to dry from the rim in.
## The duel's pool keeps the same three beats (scripts/duel/gore.gd).
const POOL_TIME := 1.5
const WET_TIME := 4.0
const DRY_TIME := 6.0
## How far a pool spreads from: a share of its width at the instant of death.
const POOL_START := 0.4

const STRIDE := 6
const D_X := 0
const D_Y := 1
const D_VX := 2
const D_VY := 3
const D_AGE := 4
const D_SIZE := 5

var level: Level
var player: Player
## Kills bled for since the last clear(), for the tests and the seed.
var kills := 0

var _drops := PackedFloat32Array()
var _next := 0
## [Rect2, Color] pairs, oldest first.
var _stains: Array[Array] = []
## { x, top, width, born } -- the centre, the floor's top, the spread width
## and the clock at the death -- oldest first.
var _pools: Array[Dictionary] = []
## Seconds of unfrozen play since the last clear(): the pools' clock.
var _clock := 0.0
## While the clock is before this, a pool is still spreading or drying.
var _drying_until := 0.0
var _rng := RandomNumberGenerator.new()
var _frozen := Callable()


## Puts a Bloodshed in `game`, hearing every foe that enters `entities`.
static func install(game: Game, entities: Node) -> Bloodshed:
	var blood := Bloodshed.new()
	blood.name = "Bloodshed"
	blood.level = game.level
	blood.player = game.player
	blood._frozen = func() -> bool: return game.phase == Game.Phase.PAUSED
	game.add_child(blood)
	entities.child_entered_tree.connect(blood.watch)
	if game.player != null:
		game.player.hurt.connect(func(_left: int) -> void: blood.spatter(HURT_DROPS))
		game.player.died.connect(blood.prince_down)
	return blood


func _ready() -> void:
	# Over the actors, under the foreground plane (Level.FOREGROUND_Z): a drop
	# is thrown out of a body, and drawn behind it the burst would be lost.
	z_index = 1
	_drops.resize(MAX_DROPS * STRIDE)
	_rng.seed = 7919


## Hears `node`'s death, if it is a foe. Safe to call twice for one foe.
func watch(node: Node) -> void:
	var foe := node as Foe
	if foe == null:
		return
	var heard := bleed_for.bind(foe)
	if not foe.defeated.is_connected(heard):
		foe.defeated.connect(heard)


## A foe was cut down: the kill's sound, the burst, the pool.
func bleed_for(foe: Foe) -> void:
	kills += 1
	GameAudio.cue(&"kill")
	var body := foe.hurt_rect()
	if body.size == Vector2.ZERO:
		body = Rect2(foe.global_position - Vector2(4.0, 16.0), Vector2(8.0, 16.0))
	var origin := to_local(body.get_center())
	burst(origin, _away_from_prince(origin.x), KILL_DROPS)
	pool(Vector2(origin.x, to_local(body.end).y), _rng.randi_range(POOL_MIN, POOL_MAX))


## The prince cut: a few drops, thrown the way the blow knocked him.
func spatter(count: int = HURT_DROPS) -> void:
	if player == null:
		return
	var body := player.body_rect()
	var direction := signf(player.velocity.x)
	if is_zero_approx(direction):
		direction = -float(player.facing)
	burst(to_local(body.get_center()), direction, count)


## The prince killed: a spatter the size of a small burst, and a pool of his
## own where he fell, which the respawn leaves on the floor.
func prince_down() -> void:
	if player == null:
		return
	spatter(DEATH_DROPS)
	var body := player.body_rect()
	pool(Vector2(to_local(body.get_center()).x, to_local(body.end).y),
		_rng.randi_range(PRINCE_POOL_MIN, PRINCE_POOL_MAX))


## `count` drops from `origin`, thrown toward `direction` (-1 or 1) and up.
func burst(origin: Vector2, direction: float, count: int) -> void:
	for i: int in count:
		# One in five goes back over the shoulder: a burst, not a jet. The
		# first few leave fast and flat -- the spurt that says which way the
		# blade went -- and the rest climb and fall around it.
		var way := -direction if i % 5 == 4 else direction
		var spurt := i < count / 4
		var speed := _rng.randf_range(130.0, 190.0) if spurt else _rng.randf_range(35.0, 150.0)
		var lift := _rng.randf_range(15.0, 50.0) if spurt else _rng.randf_range(40.0, 150.0)
		var at := _next * STRIDE
		_drops[at + D_X] = origin.x + _rng.randf_range(-2.0, 2.0)
		_drops[at + D_Y] = origin.y + _rng.randf_range(-3.0, 3.0)
		_drops[at + D_VX] = way * speed
		_drops[at + D_VY] = -lift
		_drops[at + D_AGE] = 0.0001
		_drops[at + D_SIZE] = float(3 - i % 3)
		_next = (_next + 1) % MAX_DROPS
	queue_redraw()


## A pool `width` pixels wide when spread, on the floor under `at`, if there
## is one within a few tiles. The oldest goes once there are MAX_POOLS.
func pool(at: Vector2, width: int = POOL_MIN) -> void:
	if level == null:
		return
	var probe := at
	for _step: int in 3 * Level.TILE:
		if level.is_solid_at(to_global(probe)):
			if _pools.size() >= MAX_POOLS:
				_pools.pop_front()
			_pools.append({
				"x": roundf(at.x),
				"top": floorf(probe.y / Level.TILE) * Level.TILE,
				"width": float(width),
				"born": _clock,
			})
			_drying_until = _clock + WET_TIME + DRY_TIME
			queue_redraw()
			return
		probe.y += 1.0


## Leaves a stain. The oldest goes once there are MAX_STAINS.
func stain(rect: Rect2, colour: Color) -> void:
	if _stains.size() >= MAX_STAINS:
		_stains.pop_front()
	_stains.append([rect, colour])
	queue_redraw()


## Everything off the floor and out of the air: the level is starting over.
func clear() -> void:
	_drops.fill(0.0)
	_stains.clear()
	_pools.clear()
	_clock = 0.0
	_drying_until = 0.0
	kills = 0
	queue_redraw()


func drops_in_flight() -> int:
	var out := 0
	for i: int in MAX_DROPS:
		if _drops[i * STRIDE + D_AGE] > 0.0:
			out += 1
	return out


## The velocity of every drop in the air, for a test to read the burst's way.
func velocities() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in MAX_DROPS:
		var at := i * STRIDE
		if _drops[at + D_AGE] > 0.0:
			out.append(Vector2(_drops[at + D_VX], _drops[at + D_VY]))
	return out


func stain_count() -> int:
	return _stains.size()


func pool_count() -> int:
	return _pools.size()


## Every colour a stain on the floor is in, for a test to hold to the ramp.
func stain_colours() -> Array[Color]:
	var out: Array[Color] = []
	for entry: Array in _stains:
		if not out.has(entry[1] as Color):
			out.append(entry[1] as Color)
	return out


## --- per-frame ----------------------------------------------------------------

func _process(_delta: float) -> void:
	_grade_like_the_stone()


func _physics_process(delta: float) -> void:
	if Flow.is_hitstopped() or (_frozen.is_valid() and bool(_frozen.call())):
		return
	var was := _clock
	_clock += delta
	var moved := was < _drying_until
	for i: int in MAX_DROPS:
		var at := i * STRIDE
		if _drops[at + D_AGE] <= 0.0:
			continue
		moved = true
		_step_drop(at, delta)
	if moved:
		queue_redraw()


## The hour's multiply taken back off: the canvas multiply is the hour times
## the dim, and this leaves only the dim, which is what the stone gets
## through the world shader's tint. See "Lit like the stone it lies on".
func _grade_like_the_stone() -> void:
	var grade := get_tree().get_first_node_in_group(WorldGrade.GROUP) as WorldGrade
	var hour: Color = Color.WHITE if grade == null else grade.grade.get("world", Color.WHITE)
	modulate = Color.WHITE / hour


func _step_drop(at: int, delta: float) -> void:
	_drops[at + D_AGE] += delta
	if _drops[at + D_AGE] > DROP_LIFE:
		_drops[at + D_AGE] = 0.0
		return
	var was := Vector2(_drops[at + D_X], _drops[at + D_Y])
	_drops[at + D_VY] += GRAVITY * delta
	var now := was + Vector2(_drops[at + D_VX], _drops[at + D_VY]) * delta
	_drops[at + D_X] = now.x
	_drops[at + D_Y] = now.y
	if level == null or not level.is_solid_at(to_global(now)):
		return
	_drops[at + D_AGE] = 0.0
	var size := _drops[at + D_SIZE]
	if not level.is_solid_at(to_global(Vector2(now.x, was.y))):
		# Came down onto it, or up into it: a floor takes a smear along it.
		if now.y > was.y:
			var top := floorf(now.y / Level.TILE) * Level.TILE
			# Two rows, fresh over dried: the fresh row reads on dark stone
			# and gold, the dried one on mid crimson.
			stain(Rect2(floorf(now.x) - 1.0, top, size + 2.0, 1.0), Palette.BLOOD)
			stain(Rect2(floorf(now.x), top + 1.0, size, 1.0), Palette.BLOOD_DRIED)
		return
	# Came in from the side: a wall takes a blob where it struck and a run
	# down the face from it, fresh over dried.
	var leftward := now.x < was.x
	var face := floorf(now.x / Level.TILE) * Level.TILE + (Level.TILE - 1.0 if leftward else 0.0)
	var y := floorf(now.y)
	stain(Rect2(face - (1.0 if leftward else 0.0), y, 2.0, 2.0), Palette.BLOOD)
	stain(Rect2(face, y + 2.0, 1.0, size + 1.0), Palette.BLOOD_DRIED)


func _away_from_prince(x: float) -> float:
	if player == null:
		return 1.0
	var away := signf(x - to_local(player.global_position).x)
	return away if not is_zero_approx(away) else float(player.facing)


func _draw() -> void:
	for entry: Array in _stains:
		draw_rect(entry[0] as Rect2, entry[1] as Color)
	for each: Dictionary in _pools:
		_draw_pool(each)
	for i: int in MAX_DROPS:
		var at := i * STRIDE
		if _drops[at + D_AGE] <= 0.0:
			continue
		var size := _drops[at + D_SIZE]
		var corner := Vector2(floorf(_drops[at + D_X]), floorf(_drops[at + D_Y]))
		draw_rect(Rect2(corner, Vector2(size, size)), Palette.BLOOD)
		if size > 1.0:
			# The glint on the sunward corner: the sun is low on the left.
			draw_rect(Rect2(corner, Vector2.ONE), Palette.BLOOD_WET)


## Three rows into the floor's top, narrowing: the lip, the body, the
## underside. Wet, it is fresh with a dried heart and the glint along the
## sunward end of the lip; drying, the dried tone takes it from the rim in;
## dry, it is the dried tone alone.
func _draw_pool(each: Dictionary) -> void:
	var age := _clock - float(each["born"])
	var spread := 1.0 - pow(1.0 - clampf(age / POOL_TIME, 0.0, 1.0), 2.0)
	var width := maxf(4.0, 2.0 * roundf(float(each["width"]) * lerpf(POOL_START, 1.0, spread) * 0.5))
	var left := float(each["x"]) - width * 0.5
	var top := float(each["top"])
	var rows: Array[Rect2] = [
		Rect2(left, top, width, 1.0),
		Rect2(left + 1.0, top + 1.0, width - 2.0, 1.0),
		Rect2(left + 3.0, top + 2.0, maxf(0.0, width - 6.0), 1.0),
	]
	if age >= WET_TIME + DRY_TIME:
		for row: Rect2 in rows:
			draw_rect(row, Palette.BLOOD_DRIED)
		return
	if age < WET_TIME:
		for row: Rect2 in rows:
			draw_rect(row, Palette.BLOOD)
		draw_rect(Rect2(left + 3.0, top + 1.0, maxf(0.0, width - 6.0), 1.0), Palette.BLOOD_DRIED)
		draw_rect(Rect2(left + 1.0, top, ceilf(width * 0.3), 1.0), Palette.BLOOD_WET)
		return
	var wet := 1.0 - (age - WET_TIME) / DRY_TIME
	for row: Rect2 in rows:
		draw_rect(row, Palette.BLOOD_DRIED)
	var inner := 2.0 * roundf((width - 2.0) * wet * 0.5)
	if inner > 0.0:
		draw_rect(Rect2(float(each["x"]) - inner * 0.5, top, inner, 2.0), Palette.BLOOD)
