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
## ## Two tones, hard pixels, no glow
##
## docs/art-direction.md: every surface is lit gold or crimson shadow and the
## line between them is hard. Blood is the deep cloth crimson, with a near-
## black crimson for the heart of a stain and the old edge of a pool -- both
## palette steps, so it reads on gold floors and on shaded stone alike, and
## both opaque: nothing is blended, faded or blurred. A drop is one pixel or
## two, snapped to the grid, every frame.
##
## ## Capped for phones
##
## Drops live in one fixed PackedFloat32Array, like PlayerFx's dust: nothing
## is allocated while playing and a kill can never cost more than MAX_DROPS.
## Stains are a ring of MAX_STAINS rects; past it the oldest goes. Both are
## drawn in one pass of rects.
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
## Drops in one kill's burst, and in the spatter when the prince is cut.
const KILL_DROPS := 24
const HURT_DROPS := 4

const GRAVITY := 300.0
## A drop that has not landed by then is let go without a stain.
const DROP_LIFE := 1.6

## Fresh blood, and the dark heart of a stain.
const BLOOD := Palette.CLOTH_DARK
const BLOOD_DARK := Palette.SHADOW_PIT

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
		game.player.died.connect(func() -> void: blood.spatter(HURT_DROPS * 2))
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
	pool(Vector2(origin.x, to_local(body.end).y))


## The prince cut, or killed: a few drops, thrown the way the blow knocked
## him. A smaller thing than a kill on purpose -- the burst is the reward for
## a blow landed, and his own blood should not compete with it.
func spatter(count: int = HURT_DROPS) -> void:
	if player == null:
		return
	var body := player.body_rect()
	var direction := signf(player.velocity.x)
	if is_zero_approx(direction):
		direction = -float(player.facing)
	burst(to_local(body.get_center()), direction, count)


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


## A pool on the floor under `at`, if there is one within a couple of tiles.
func pool(at: Vector2) -> void:
	if level == null:
		return
	var probe := at
	for _step: int in 3 * Level.TILE:
		if level.is_solid_at(to_global(probe)):
			var top := floorf(probe.y / Level.TILE) * Level.TILE
			var width := float(_rng.randi_range(12, 18))
			var left := floorf(at.x - width * 0.5)
			stain(Rect2(left, top, width, 2.0), BLOOD)
			stain(Rect2(left + 3.0, top, width - 6.0, 2.0), BLOOD_DARK)
			stain(Rect2(left + 2.0, top + 2.0, width - 4.0, 1.0), BLOOD)
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


## --- per-frame ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Flow.is_hitstopped() or (_frozen.is_valid() and bool(_frozen.call())):
		return
	var moved := false
	for i: int in MAX_DROPS:
		var at := i * STRIDE
		if _drops[at + D_AGE] <= 0.0:
			continue
		moved = true
		_step_drop(at, delta)
	if moved:
		queue_redraw()


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
			# Two rows, crimson over near-black: the crimson reads on a lit
			# floor, the dark row on one in shade.
			stain(Rect2(floorf(now.x) - 1.0, top, size + 2.0, 1.0), BLOOD)
			stain(Rect2(floorf(now.x), top + 1.0, size, 1.0), BLOOD_DARK)
		return
	# Came in from the side: a wall takes a run down its face.
	var face := floorf(now.x / Level.TILE) * Level.TILE
	if now.x < was.x:
		face += Level.TILE - 1.0
	stain(Rect2(face - (1.0 if now.x < was.x else 0.0), floorf(now.y), 2.0, size + 3.0), BLOOD)


func _away_from_prince(x: float) -> float:
	if player == null:
		return 1.0
	var away := signf(x - to_local(player.global_position).x)
	return away if not is_zero_approx(away) else float(player.facing)


func _draw() -> void:
	for entry: Array in _stains:
		draw_rect(entry[0] as Rect2, entry[1] as Color)
	for i: int in MAX_DROPS:
		var at := i * STRIDE
		if _drops[at + D_AGE] <= 0.0:
			continue
		var size := _drops[at + D_SIZE]
		var corner := Vector2(floorf(_drops[at + D_X]), floorf(_drops[at + D_Y]))
		draw_rect(Rect2(corner, Vector2(size, size)), BLOOD)
		if size > 1.0:
			draw_rect(Rect2(corner, Vector2.ONE), BLOOD_DARK)
