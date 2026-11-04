class_name PlayerAudio
extends Node
## Gives the character a body: footsteps, cloth, the sword, catches and damage.
##
## The same shape as PlayerArt — a node under Player that reads the parent's
## state and owns exactly one concern. Nothing in gameplay reads this node, it
## never writes to the character, and removing it leaves a silent but
## otherwise identical game.
##
## Footsteps are not on a timer. PlayerArt swings the legs with sin(t * 16) in
## RUN and sin(t * 9) in WALK, so a foot lands every half cycle of that same
## wave; this node watches the parent's `state_time` cross each multiple of PI
## and fires there. Retune the run cycle in one place and the feet stay under
## the character, at 5.1 steps a second running and 2.9 walking, and a state
## change restarts the cadence instead of landing a step mid-stride.
##
## Everything else hangs off the character's signals, which is why this file
## needs no changes to player.gd.

## Anything in this group holds the music down to its bed stem, whatever the
## prince is doing: the Eclipse while the Vault is put out (docs/campaign.md,
## "The Eclipse"). Asked every frame, like the rest of the intensity, so the
## drive comes back the moment the last member leaves.
const HUSH := &"hushes_the_music"

## Cycle rate of each locomotion state, in radians per second, matching
## PlayerArt's leg swing. A footfall happens every PI radians.
const STEP_RATES := {
	Player.State.RUN: 16.0,
	Player.State.WALK: 9.0,
	Player.State.LADDER: 8.0,
}

## States whose entry moves the cloak enough to be heard, and how loud.
const CLOTH_ON_ENTER := {
	Player.State.JUMP: -2.0,
	Player.State.FALL: -6.0,
	Player.State.TURN: -3.0,
	Player.State.CROUCH: -5.0,
	Player.State.LAND: -4.0,
	Player.State.HANG: -4.0,
	Player.State.CLIMB_UP: -3.0,
	Player.State.ATTACK: -5.0,
	Player.State.AIR_SLASH: -4.0,
	Player.State.PLUNGE: -1.0,
	Player.State.PARRY: -4.0,
	Player.State.BACKSTEP: -2.0,
}

## Below this impact a landing is inaudible — stepping off a kerb should not
## thud. Above HARD_LAND_SPEED it is the heavy voice.
const LAND_FLOOR := 40.0

## How long a hit or a swing keeps the music intensity raised.
const HEAT_DECAY := 0.55

## A landing from ten tiles (Tuning.FATAL_FALL_TILES): the hard landing's
## voice a fifth lower and at its loudest, with stone under it. Every
## survivable landing from five tiles down hits at the same speed and so
## sounds the same, at pitch 0.92; this one is pitched apart from all of them,
## so the ear has the cause before `die` follows it.
const FATAL_LANDING := {"pitch": 0.68, "volume_db": 2.0}


@export var drive_music_intensity := true

var _player: Player
var _director: Node
var _last_state: int = -1
var _step_index: int = -1
var _heat: float = 0.0


func _ready() -> void:
	_player = get_parent() as Player
	if _player == null:
		push_warning("PlayerAudio expects to be a child of Player")
		return

	# Resolved by path rather than as a hard dependency: the character scene
	# has to keep working in a headless test or a tool that has no autoloads.
	_director = get_node_or_null(^"/root/AudioDirector")

	_player.jumped.connect(_on_jumped)
	_player.landed.connect(_on_landed)
	_player.grabbed_ledge.connect(_on_grabbed_ledge)
	_player.attacked.connect(_on_attacked)
	_player.hurt.connect(_on_hurt)
	_player.died.connect(_on_died)


## --- cadence (pure, so the test can pin it without a scene) ----------------

static func step_rate(state: int) -> float:
	return float(STEP_RATES.get(state, 0.0))


## Which footfall of the current state `state_time` falls in, or -1 for a state
## that does not walk.
static func step_index(state: int, state_time: float) -> int:
	var rate := step_rate(state)
	if rate <= 0.0:
		return -1
	return int(maxf(0.0, state_time) * rate / PI)


static func steps_per_second(state: int) -> float:
	return step_rate(state) / PI


static func voice_for_landing(impact: float) -> String:
	if impact < LAND_FLOOR:
		return ""
	return "land_hard" if impact >= Tuning.HARD_LAND_SPEED else "land_soft"


## Every voice this node can ask for. The test checks each one resolves.
static func event_names() -> PackedStringArray:
	return PackedStringArray([
		"step_run", "step_walk", "ladder", "cloth", "jump",
		"land_soft", "land_hard", "ledge_grab", "climb",
		"sword", "hurt", "die", "masonry",
	])


## --- per-frame -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null:
		return

	_heat = maxf(0.0, _heat - delta * HEAT_DECAY)

	var state: int = _player.state
	if state != _last_state:
		_on_state_entered(state)
		_last_state = state
		_step_index = -1

	_update_footsteps(state)

	if drive_music_intensity and _director != null:
		_director.set_intensity(_wanted_intensity())


func _update_footsteps(state: int) -> void:
	if step_rate(state) <= 0.0:
		_step_index = -1
		return
	# A ladder only creaks while the character is actually climbing it.
	if state == Player.State.LADDER and absf(_player.velocity.y) < 1.0:
		return

	var index := step_index(state, _player.state_time)
	if index == _step_index:
		return
	_step_index = index

	match state:
		Player.State.RUN:
			# Scaled by how fast the character is really moving, so the first
			# strides out of idle are lighter than full sprint.
			var speed := clampf(absf(_player.velocity.x) / Tuning.RUN_SPEED, 0.3, 1.0)
			_play("step_run", {"volume_db": linear_to_db(speed)})
			if index % 2 == 0:
				_play("cloth", {"volume_db": -8.0})
		Player.State.WALK:
			_play("step_walk")
		Player.State.LADDER:
			_play("ladder", {"volume_db": -3.0})


func _wanted_intensity() -> float:
	if not _player.is_alive():
		return 0.0
	if is_inside_tree() and get_tree().get_first_node_in_group(HUSH) != null:
		return 0.0
	var wounded := float(Tuning.MAX_HEALTH - _player.health) / float(maxi(1, Tuning.MAX_HEALTH))
	return combat_intensity(wounded, _heat)


## The drive stem for a prince `wounded` (0..1 of his hearts gone) with the
## fight's `heat` (0..1). It used to rest at 0.28 and rise to nearly full in a
## fight, so the drum was always ticking and loudest exactly when the swords
## had to be heard. Now it is silent at rest -- running is not tension -- and a
## fight raises it to half at most: the drum says "a fight" and then gets out
## of the way. MixRender's guard fight is scored at combat_intensity(1/3, 1).
static func combat_intensity(wounded: float, heat: float) -> float:
	return clampf(wounded * 0.3 + heat * 0.25, 0.0, 0.5)


## --- events ----------------------------------------------------------------

func _on_state_entered(state: int) -> void:
	if CLOTH_ON_ENTER.has(state):
		_play("cloth", {"volume_db": float(CLOTH_ON_ENTER[state])})
	if state == Player.State.CLIMB_UP:
		_play("climb")
	if state == Player.State.PARRY:
		# The blade going up: the sword's own voice, higher and quieter than
		# a swing, so a parry and a swing are told apart by ear.
		_play("sword", {"pitch": 1.25, "volume_db": -5.0})
	if state == Player.State.BACKSTEP:
		# The blade drawn back across the body: the same voice low and soft, a
		# whoosh under the cloth rather than a swing, so the ear does not
		# hear an attack in a move that is not one.
		_play("sword", {"pitch": 0.7, "volume_db": -10.0})


func _on_jumped() -> void:
	_play("jump")


func _on_landed(impact: float) -> void:
	if _player.is_fallen():
		_on_fatal_landing()
		return
	var voice := voice_for_landing(impact)
	if voice == "":
		return
	# One instrument scaled by the impact rather than two unrelated sounds:
	# quiet and high for a hop, loud and low for a drop.
	var t := clampf((impact - LAND_FLOOR) / (Tuning.HARD_LAND_SPEED - LAND_FLOOR), 0.0, 1.0)
	_play(voice, {
		"volume_db": lerpf(-15.0, 0.0, t),
		"pitch": lerpf(1.14, 0.92, t),
	})
	if t > 0.45:
		_play("cloth", {"volume_db": lerpf(-10.0, -2.0, t)})
	if voice == "land_hard":
		_heat = 1.0


func _on_fatal_landing() -> void:
	_play("land_hard", FATAL_LANDING)
	_play("masonry", {"pitch": 0.6, "volume_db": -8.0})
	_play("cloth", {"volume_db": -1.0})


func _on_grabbed_ledge() -> void:
	_play("ledge_grab")


func _on_attacked() -> void:
	_play("sword")
	_heat = maxf(_heat, 0.8)


func _on_hurt(remaining_health: int) -> void:
	var hurt_more := float(Tuning.MAX_HEALTH - remaining_health)
	_play("hurt", {"pitch": maxf(0.8, 1.0 - 0.06 * hurt_more)})
	_heat = 1.0


func _on_died() -> void:
	_play("die")
	_heat = 0.0


## Through the front door like every other sound in the game (CLAUDE.md).
## `_director` is still resolved for the music intensity, which is not a cue.
func _play(event: String, opts: Dictionary = {}) -> void:
	GameAudio.cue(event, opts)
