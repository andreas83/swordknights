class_name PlayerFx
extends Node2D
## The dust, scuffs, puffs, sparks and sword trail that sell the character's
## weight — all of it driven off Player's existing signals.
##
## The hit flash is NOT here: it belongs to the figure's own silhouette, so
## `PlayerArt` burns its planes white instead of this node laying a rectangle
## over the character.
##
## ## Why it attaches itself
##
## `PlayerArt._ready()` calls `PlayerFx.attach()`, which adds this node beside
## the art if it is not already there. Nothing has to be wired into
## `scenes/player.tscn`, so every Player everywhere — adventure, feel lab, a
## duel, a generated level — gets the effects for free and the scene file stays
## a two-node file that nobody has to merge.
##
## The node is `top_level`, so particles live in world space and stay where
## they were kicked up instead of riding along with the character.
##
## ## Why it is a float array
##
## This runs on phones next to a tilemap. Particles are a fixed-size
## PackedFloat32Array with a stride, so a full screen of dust allocates nothing
## per frame and dies in a flat loop. There is no object per particle, no
## timer, no tween, and nothing is created or freed while playing.
##
## Effects are cosmetic and read-only with respect to gameplay: nothing here
## can change a simulation value, which is what keeps it safe to skip entirely
## on a replay or a remote peer.
##
## ## Hitstop and haptics
##
## Two things reach out of this node, and neither can affect a simulation.
##
## It *reads* `Flow.is_hitstopped()` and holds every particle and the sword
## trail still while a frame is held. Without that the dust keeps drifting
## through a frozen image and the hitstop reads as a dropped frame instead of
## as weight. Reading the flag is safe anywhere: in a duel nothing ever sets
## it, so it is always false there (see docs/feel.md).
##
## It *calls* `Flow.haptic()`, which is `Input.vibrate_handheld()` behind a
## setting. Landings and hits buzz, scaled by the same `impact_weight()` the
## dust uses, so the phone agrees with the screen.

enum Kind { DUST, SCUFF, SPARK }

const MAX_PARTICLES := 56
const STRIDE := 8
const P_X := 0
const P_Y := 1
const P_VX := 2
const P_VY := 3
const P_LIFE := 4
const P_TTL := 5
const P_SIZE := 6
const P_KIND := 7

const DUST_GRAVITY := 34.0
const DUST_DRAG := 2.6
const SCUFF_INTERVAL := 0.11
const TRAIL_POINTS := 7

## Below this a landing is a touchdown, not an impact: no dust and no buzz.
const HAPTIC_LAND_FROM := 0.35
## A landing can never buzz as hard as taking a hit does.
const HAPTIC_LAND_CEILING := 0.7
const HAPTIC_HURT := 0.8
const HAPTIC_DEATH := 1.0

var _player: Player
var _art: PlayerArt

var _p := PackedFloat32Array()
var _next := 0

var _scuff_timer: float = 0.0
var _trail := PackedVector2Array()
var _trail_life: float = 0.0


## Adds the effects node to `player` unless it already has one. Safe to call
## more than once; returns the node either way. The child appears on the next
## idle frame, so look it up by name rather than assuming it is there at once.
static func attach(player: Player) -> PlayerFx:
	if player == null:
		return null
	var existing := player.get_node_or_null("PlayerFx") as PlayerFx
	if existing != null:
		return existing
	var fx := PlayerFx.new()
	fx.name = "PlayerFx"
	# Deferred because the usual caller is PlayerArt._ready(), and a parent
	# that is mid-_ready refuses new children.
	player.add_child.call_deferred(fx)
	return fx


func _ready() -> void:
	top_level = true
	position = Vector2.ZERO
	_p.resize(MAX_PARTICLES * STRIDE)
	_player = get_parent() as Player
	if _player == null:
		return
	_art = _player.get_node_or_null("PlayerArt") as PlayerArt
	_player.landed.connect(_on_landed)
	_player.grabbed_ledge.connect(_on_grabbed_ledge)
	_player.hurt.connect(_on_hurt)
	_player.died.connect(_on_died)


## Drops every live effect. Used by the pose harness so a captured frame shows
## only what that pose asked for.
func reset() -> void:
	_p.fill(0.0)
	_trail.clear()
	_trail_life = 0.0
	_scuff_timer = 0.0


func _process(delta: float) -> void:
	# A held frame holds everything in it. The redraw still happens so the
	# node survives a resize or a re-parent mid-hitstop.
	if Flow.is_hitstopped():
		queue_redraw()
		return
	_step_particles(delta)
	_step_scuffs(delta)
	_step_trail(delta)
	queue_redraw()


## --- simulation ------------------------------------------------------------

func _step_particles(delta: float) -> void:
	for i: int in MAX_PARTICLES:
		var o := i * STRIDE
		var life := _p[o + P_LIFE]
		if life <= 0.0:
			continue
		life -= delta
		if life <= 0.0:
			_p[o + P_LIFE] = 0.0
			continue
		var drag := 1.0 - minf(1.0, DUST_DRAG * delta)
		_p[o + P_VX] *= drag
		_p[o + P_VY] = _p[o + P_VY] * drag + DUST_GRAVITY * delta
		_p[o + P_X] += _p[o + P_VX] * delta
		_p[o + P_Y] += _p[o + P_VY] * delta
		_p[o + P_LIFE] = life


## Running kicks up grit at a steady cadence rather than every frame, which is
## both cheaper and reads better: discrete puffs, not a smear.
func _step_scuffs(delta: float) -> void:
	if _player == null:
		return
	var running := _player.state == Player.State.RUN and _player.is_grounded()
	if not running:
		_scuff_timer = SCUFF_INTERVAL * 0.5
		return
	_scuff_timer -= delta
	if _scuff_timer > 0.0:
		return
	_scuff_timer = SCUFF_INTERVAL
	var back := -_player.facing
	_spawn(_player.global_position + Vector2(back * 2.0, -0.5),
		Vector2(back * randf_range(10.0, 26.0), randf_range(-20.0, -8.0)),
		randf_range(0.2, 0.32), 1.0, Kind.SCUFF)


## The sword trail is a ribbon through the blade tip's recent positions. The
## tip comes from the art node, which already computes it for the swing, so the
## trail and the blade can never disagree.
func _step_trail(delta: float) -> void:
	if _player == null:
		return
	if _player.is_striking() and _art != null and _art.blade_hot > 0.0:
		_trail.append(_art.to_global(_art.blade_tip))
		while _trail.size() > TRAIL_POINTS:
			_trail.remove_at(0)
		_trail_life = 1.0
		return
	_trail_life = maxf(0.0, _trail_life - delta * 7.0)
	if _trail_life <= 0.0 and _trail.size() > 0:
		_trail.clear()


## --- signal handlers -------------------------------------------------------

## Sparks where a blade or a boot connected, plus the buzz for it.
##
## Called by `Game` rather than driven off a signal, because the player does
## not know it hit anything: the scene arbitrates that. `weight` is 0..1 and
## scales both the spark count and the haptic.
func sword_hit(at: Vector2, weight: float) -> void:
	var amount := clampf(weight, 0.0, 1.0)
	var count := 4 + int(amount * 6.0)
	for i: int in count:
		var angle := TAU * float(i) / float(count) + randf() * 0.5
		_spawn(at + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)),
			Vector2(cos(angle), sin(angle)) * (46.0 + 54.0 * amount) * randf_range(0.5, 1.0),
			randf_range(0.1, 0.2) + amount * 0.08, 1.0, Kind.SPARK)
	Flow.haptic(amount)


func _on_landed(impact_speed: float) -> void:
	var weight := Tuning.impact_weight(impact_speed)
	if weight <= 0.05:
		return
	if weight >= HAPTIC_LAND_FROM:
		Flow.haptic(weight * HAPTIC_LAND_CEILING)
	var count := 2 + int(weight * 9.0)
	var at := _player.global_position
	for i: int in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		_spawn(at + Vector2(side * randf_range(1.0, 4.0), -0.5),
			Vector2(side * randf_range(16.0, 30.0 + 44.0 * weight),
				-randf_range(8.0, 16.0 + 30.0 * weight)),
			randf_range(0.22, 0.34) + weight * 0.16,
			1.0 + weight, Kind.DUST)


func _on_grabbed_ledge() -> void:
	var hand := _player.global_position + Vector2(
		_player.facing * Tuning.BODY_WIDTH * 0.5,
		-Tuning.BODY_HEIGHT + Tuning.GRAB_PROBE_Y)
	for i: int in 5:
		_spawn(hand + Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0)),
			Vector2(_player.facing * randf_range(4.0, 20.0), randf_range(-14.0, 6.0)),
			randf_range(0.2, 0.36), 1.0, Kind.DUST)


func _on_hurt(_remaining_health: int) -> void:
	_burst(8, 60.0)
	Flow.haptic(HAPTIC_HURT)


func _on_died() -> void:
	_burst(14, 86.0)
	Flow.haptic(HAPTIC_DEATH)


func _burst(count: int, speed: float) -> void:
	var at := _player.global_position + Vector2(0.0, -Tuning.BODY_HEIGHT * 0.55)
	for i: int in count:
		var angle := TAU * float(i) / float(count) + randf() * 0.4
		_spawn(at, Vector2(cos(angle), sin(angle)) * speed * randf_range(0.5, 1.0),
			randf_range(0.16, 0.3), 1.0, Kind.SPARK)


func _spawn(at: Vector2, velocity: Vector2, ttl: float, size: float, kind: Kind) -> void:
	var o := _next * STRIDE
	_next = (_next + 1) % MAX_PARTICLES
	_p[o + P_X] = at.x
	_p[o + P_Y] = at.y
	_p[o + P_VX] = velocity.x
	_p[o + P_VY] = velocity.y
	_p[o + P_LIFE] = ttl
	_p[o + P_TTL] = ttl
	_p[o + P_SIZE] = size
	_p[o + P_KIND] = float(kind)


## --- drawing ---------------------------------------------------------------

func _draw() -> void:
	if _player == null:
		return
	_draw_trail()
	_draw_particles()


func _draw_particles() -> void:
	for i: int in MAX_PARTICLES:
		var o := i * STRIDE
		var life := _p[o + P_LIFE]
		if life <= 0.0:
			continue
		var age := 1.0 - life / maxf(0.001, _p[o + P_TTL])
		var kind := int(_p[o + P_KIND])
		var color := _color_for(kind, age)
		# Dust thins as it ages; sparks shrink to nothing.
		var size: float = _p[o + P_SIZE] * (1.0 - age * (0.75 if kind == Kind.SPARK else 0.4))
		if size <= 0.1:
			continue
		draw_rect(Rect2(_p[o + P_X] - size * 0.5, _p[o + P_Y] - size * 0.5, size, size), color)


func _color_for(kind: int, age: float) -> Color:
	match kind:
		Kind.SPARK:
			return Palette.with_alpha(Palette.PAPER, 1.0 - age * 0.8)
		Kind.SCUFF:
			return Palette.with_alpha(Palette.LIGHT_WARM, 0.5 * (1.0 - age))
		_:
			var hue := Palette.LIGHT_SOFT.lerp(Palette.SHADOW_WARM, age)
			return Palette.with_alpha(hue, 0.65 * (1.0 - age * age))


func _draw_trail() -> void:
	if _trail.size() < 3:
		return
	var alpha := 0.42 * _trail_life
	for i: int in range(1, _trail.size()):
		var t := float(i) / float(_trail.size() - 1)
		var w := lerpf(0.5, 2.0, t)
		var a := alpha * t
		var from := _trail[i - 1]
		var to := _trail[i]
		var along := (to - from)
		if along.length_squared() < 0.01:
			continue
		var side := Vector2(-along.y, along.x).normalized() * w
		draw_colored_polygon(PackedVector2Array([from + side, to + side, to - side, from - side]),
			Palette.with_alpha(Palette.PAPER, a))
