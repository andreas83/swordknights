class_name Game
extends Node2D
## The playable scene: owns a level's world, actors, camera and presentation,
## and arbitrates the interactions between them.
##
## Everything level-specific comes from the ASCII file it is given, so adding a
## level — hand-authored or generated — means supplying different text, not
## touching this file.

signal level_completed(elapsed: float, relics: int, relics_total: int)

enum Phase { PLAYING, DYING, COMPLETE, PAUSED }

# --- feel/flow (additive) --- the death beat, which was a flat 1.1 s hold and
# a hard cut. It is now long enough to read what killed you and short enough
# that the next attempt is the thing you are thinking about; the respawn itself
# happens behind the wipe, so this is the whole of the wait. Mashing jump skips
# it after DEATH_SKIP_DELAY. See docs/feel.md.
const DEATH_HOLD := 0.3
const DEATH_SKIP_DELAY := 0.1
# --- feel/flow (additive) --- one swing, one impact. The attack rect stays
# live for about eight frames and the interaction pass runs every one of them,
# so without this a single swing spends the hitstop budget two or three times
# over and the frame appears to freeze for a fifth of a second.
const IMPACT_COOLDOWN := 0.16
const MENU_SCENE := "res://scenes/menu.tscn"

@export_file("*.txt") var level_path: String = "res://levels/level_01.txt"
## Set instead of level_path to run a generated level without writing a file.
var level_source: AsciiLevel

@onready var level: Level = $Level
@onready var player: Player = $Player
@onready var camera: GameCamera = $Camera
@onready var sky: ParallaxSky = $Sky/ParallaxSky
@onready var hud: Hud = $HudLayer/Hud

var phase: Phase = Phase.PLAYING
var elapsed: float = 0.0
var relics: int = 0
var relics_total: int = 0

var _death_timer: float = 0.0
var _entities: Node2D
var _exit: ExitDoor
# --- feel/flow (additive) --- last seen value of Flow.is_hitstopped(), so the
# freeze is applied on the edge rather than re-asserted every frame.
var _hitstopped := false
var _impact_cooldown: float = 0.0


func _ready() -> void:
	var data := level_source if level_source != null else AsciiLevel.from_file(level_path)
	if data == null:
		push_error("no level data")
		return

	level.build(data)
	_entities = Node2D.new()
	_entities.name = "Entities"
	add_child(_entities)
	_spawn_entities(data)

	player.level = level
	player.respawn(level.spawn_world_position())
	player.landed.connect(_on_landed)
	player.hurt.connect(func(_h: int) -> void: camera.shake(2.4, 0.26))
	player.died.connect(_on_died)

	camera.setup(player, level.world_size())
	sky.camera = camera
	sky.seed_value = hash(data.name)

	hud.show_title(data.name)
	_update_hud()

	# --- feel/flow (additive) --- lift the shadow off whatever just loaded. A
	# no-op when the previous scene already drove the wipe.
	Flow.enter(self)


func _physics_process(delta: float) -> void:
	# --- feel/flow (additive) --- a hitstop holds the actors for a handful
	# of frames so an impact has weight. It is driven from this scene and
	# only this scene: a duel steps in _physics_process and must never be
	# frozen by one peer's local hit. See docs/feel.md.
	var stopped := Flow.is_hitstopped()
	if stopped != _hitstopped:
		_hitstopped = stopped
		_apply_freeze()
	if stopped:
		return

	# --- feel/flow (additive) --- a transition owns the screen while it
	# runs, so nothing queues a second one behind it.
	if Input.is_action_just_pressed("pause") and not Flow.busy():
		if phase == Phase.PLAYING:
			_set_phase(Phase.PAUSED)
			GameAudio.cue("pause_in")
		elif phase == Phase.PAUSED:
			_set_phase(Phase.PLAYING)
			GameAudio.cue("pause_out")

	match phase:
		Phase.PAUSED:
			if Input.is_action_just_pressed("attack") and not Flow.busy():
				Flow.change_scene(self, MENU_SCENE)
		Phase.COMPLETE:
			if Flow.busy():
				pass
			elif Input.is_action_just_pressed("jump"):
				Flow.wipe(self, _restart)
			elif Input.is_action_just_pressed("attack"):
				Flow.change_scene(self, MENU_SCENE)
		Phase.DYING:
			# --- feel/flow (additive) --- the beat, then the respawn behind
			# the wipe. Nothing is added to the wait: the player is already
			# playing again as the shadow lifts.
			_death_timer -= delta
			var skipped := (
				Input.is_action_just_pressed("jump")
				and _death_timer <= DEATH_HOLD - DEATH_SKIP_DELAY
			)
			if (_death_timer <= 0.0 or skipped) and not Flow.busy():
				Flow.wipe(self, _restart, Flow.Pace.FAST)
		Phase.PLAYING:
			elapsed += delta
			# --- feel/flow (additive) --- spent in live frames, so a held
			# frame does not count against it.
			_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
			_resolve_interactions()


func _set_phase(next: Phase) -> void:
	phase = next
	_apply_freeze()
	hud.set_overlay(_overlay_title(), _overlay_subtitle())


# --- feel/flow (additive) --- was the body of _set_phase, with hitstop added
# as a third reason to hold the actors still. Split out so the hitstop edge can
# re-apply the freeze without going through a phase change.
func _apply_freeze() -> void:
	var frozen := (
		phase == Phase.PAUSED
		or phase == Phase.COMPLETE
		or Flow.is_hitstopped()
	)
	player.set_physics_process(not frozen)
	_entities.process_mode = (
		Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
	)


func _overlay_title() -> String:
	match phase:
		Phase.PAUSED:
			return "PAUSED"
		Phase.COMPLETE:
			return "ESCAPED"
		_:
			return ""


func _overlay_subtitle() -> String:
	match phase:
		Phase.PAUSED:
			return "PAUSE TO RESUME  ·  SWORD TO QUIT"
		Phase.COMPLETE:
			return "%d/%d RELICS  ·  %.1fs  ·  JUMP TO REPLAY" % [relics, relics_total, elapsed]
		_:
			return ""


func _spawn_entities(data: AsciiLevel) -> void:
	relics = 0
	relics_total = 0
	_exit = null

	for mark: Dictionary in data.entities:
		var at: Vector2 = level.entity_world_position(mark["cell"])
		match String(mark["kind"]):
			"relic":
				var relic := Relic.new()
				relic.position = at
				relic.collected.connect(_on_relic_collected)
				_entities.add_child(relic)
				relics_total += 1
			"exit":
				_exit = ExitDoor.new()
				_exit.position = at
				_exit.is_open = true
				_entities.add_child(_exit)
			"torch":
				var torch := Torch.new()
				torch.position = at
				_entities.add_child(torch)
			"patrol":
				var guard := Patrol.new()
				guard.position = at
				guard.level = level
				_entities.add_child(guard)


func _resolve_interactions() -> void:
	var body := player.body_rect()

	if player.is_alive():
		if level.rect_is_deadly(body) or body.position.y > level.world_size().y + 48.0:
			player.kill()
			return

	var attack := player.attack_rect()
	var has_attack := attack.size.x > 0.0

	for node: Node in _entities.get_children():
		if node is Relic and body.intersects((node as Relic).bounds()):
			(node as Relic).collect()
		elif node is Patrol:
			var guard := node as Patrol
			if has_attack and attack.intersects(guard.bounds()):
				guard.hit(player.global_position.x)
				GameAudio.cue("guard_hit")
				# --- feel/flow (additive) ---
				_impact(guard.global_position, Flow.HIT_FRAMES, 1.9, 0.55)
			elif body.intersects(guard.bounds()):
				# A falling player lands on the guard instead of taking the hit.
				var stomping := (
					player.velocity.y > 40.0
					and body.position.y + body.size.y - guard.bounds().position.y < 10.0
				)
				if stomping:
					guard.hit(player.global_position.x)
					GameAudio.cue("guard_hit", {"pitch": 0.9})
					# --- feel/flow (additive) --- heavier than the
					# sword: the whole body is behind this one.
					_impact(guard.global_position, Flow.STOMP_FRAMES, 2.6, 0.8)
					player.velocity.y = -Tuning.JUMP_SPEED * 0.68
				elif player.damage(1, guard.global_position.x):
					# --- feel/flow (additive) --- only when it landed:
					# damage() returns false during invulnerability.
					Flow.hitstop(self, Flow.HURT_FRAMES * Flow.FRAME)

	if _exit != null and body.intersects(_exit.bounds()):
		_complete()


func _complete() -> void:
	GameAudio.cue("level_complete")
	_set_phase(Phase.COMPLETE)
	level_completed.emit(elapsed, relics, relics_total)


func _restart() -> void:
	for node: Node in _entities.get_children():
		node.queue_free()
	_spawn_entities(level.data)
	player.respawn(level.spawn_world_position())
	camera.setup(player, level.world_size())
	elapsed = 0.0
	_death_timer = 0.0
	_impact_cooldown = 0.0 # --- feel/flow (additive) ---
	_set_phase(Phase.PLAYING)
	_update_hud()


func _on_relic_collected() -> void:
	GameAudio.cue("relic")
	relics += 1
	_update_hud()


# --- feel/flow (additive) --- one place for "something connected": a few
# frozen frames, a camera settle, sparks at the contact point and a buzz, all
# scaled off the same weight so they cannot disagree.
func _impact(at: Vector2, frames: int, shake_amount: float, weight: float) -> void:
	if _impact_cooldown > 0.0:
		return
	_impact_cooldown = IMPACT_COOLDOWN
	Flow.hitstop(self, frames * Flow.FRAME)
	camera.shake(shake_amount, 0.2)
	camera.settle(weight * 0.5)
	var fx := PlayerFx.attach(player)
	if fx != null and fx.is_inside_tree():
		fx.sword_hit(at, weight)


func _on_landed(impact: float) -> void:
	if impact >= Tuning.HARD_LAND_SPEED:
		camera.shake(1.6, 0.18)
	# --- feel/flow (additive) --- the frame settles with the weight of it.
	camera.settle(Tuning.impact_weight(impact))


func _on_died() -> void:
	camera.shake(3.0, 0.4)
	_death_timer = DEATH_HOLD
	phase = Phase.DYING
	_update_hud()


func _update_hud() -> void:
	hud.update_model(player.health, Tuning.MAX_HEALTH, relics, relics_total)
