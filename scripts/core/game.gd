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
# --- checkpoints --- how close, either side of a torch, the feet have to pass
# to claim it. Wider than one frame of full-speed running, so it cannot be
# skipped, and narrow enough that it reads as "I reached the torch".
const CHECKPOINT_REACH := 10.0

@export_file("*.txt") var level_path: String = "res://levels/level_01.txt"
## Set instead of level_path to run a generated level without writing a file.
var level_source: AsciiLevel
## What jump does on the complete screen, when a mode has somewhere further to
## go. Called at full cover of the wipe, like a restart. Unset, jump replays
## this level — the Adventure's one hand-authored level has no next one.
var advance := Callable()

@onready var level: Level = $Level
@onready var player: Player = $Player
@onready var camera: GameCamera = $Camera
@onready var sky: ParallaxSky = $Sky/ParallaxSky
@onready var hud: Hud = $HudLayer/Hud

var phase: Phase = Phase.PLAYING
var elapsed: float = 0.0
var relics: int = 0
var relics_total: int = 0
## --- checkpoints --- deaths since the level was (re)started, and where the
## next one comes back. See _respawn().
var deaths: int = 0
var checkpoint := Vector2.ZERO

var _death_timer: float = 0.0
var _entities: Node2D
var _exit: ExitDoor
# --- feel/flow (additive) --- last seen value of Flow.is_hitstopped(), so the
# freeze is applied on the edge rather than re-asserted every frame.
var _hitstopped := false
var _impact_cooldown: float = 0.0
# --- checkpoints --- torch cells proved to route to the exit, the guards'
# posts in spawn order, and which of those posts have been cleared for good.
var _checkpoint_cells: Array[Vector2i] = []
var _guard_posts: Array[Vector2] = []
var _guards_down: Dictionary = {}
# Guards the current swing has already wounded, by instance id. Cleared when a
# new swing starts. See _resolve_guard().
var _struck: Dictionary = {}
# --- secrets --- the level's secret rooms: what opens them, what is in them,
# how many are found. See scripts/world/secret_keeper.gd.
var secrets := SecretKeeper.new()


func _ready() -> void:
	var data := level_source if level_source != null else AsciiLevel.from_file(level_path)
	if data == null:
		push_error("no level data")
		return

	level.build(data)
	_checkpoint_cells = checkpoint_cells(data)
	_entities = Node2D.new()
	_entities.name = "Entities"
	add_child(_entities)
	_spawn_entities(data)

	player.level = level
	checkpoint = level.spawn_world_position()
	player.respawn(checkpoint)
	# Player one's saved look (scripts/player/wardrobe.gd). A costume and some
	# colours on the art node; the body, its hitbox and its tuning are the same.
	Wardrobe.open().look(Wardrobe.PLAYER_ONE).dress(player.get_node(^"PlayerArt") as PlayerArt)
	player.landed.connect(_on_landed)
	player.attacked.connect(func() -> void: _struck.clear())
	player.hurt.connect(_on_hurt)
	player.healed.connect(func(_h: int) -> void: _update_hud())
	player.died.connect(_on_died)
	player.plunge_landed.connect(_on_plunge_landed)
	# --- secrets ---
	secrets.setup(level, player)
	secrets.furnish(_entities)
	secrets.found.connect(_on_secret_found)

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
				Flow.wipe(self, advance if advance.is_valid() else _restart)
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
				Flow.wipe(self, _respawn, Flow.Pace.FAST)
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
			var next := "DESCEND" if advance.is_valid() else "REPLAY"
			# --- secrets --- counted only where there are any to count, and
			# then the prompt takes a line of its own: all four will not fit
			# across a phone held in landscape.
			if secrets.total > 0:
				return "%d/%d RELICS  ·  SECRETS %d/%d  ·  %.1fs\nJUMP TO %s" % [
					relics, relics_total, secrets.count, secrets.total, elapsed, next]
			return "%d/%d RELICS  ·  %.1fs  ·  JUMP TO %s" % [
				relics, relics_total, elapsed, next]
		_:
			return ""


func _spawn_entities(data: AsciiLevel) -> void:
	relics = 0
	relics_total = 0
	_exit = null
	_guard_posts.clear()

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
				torch.checkpoint = _checkpoint_cells.has(mark["cell"])
				_entities.add_child(torch)
			"patrol":
				_guard_posts.append(at)
				_spawn_guard(_guard_posts.size() - 1)


func _spawn_guard(post: int) -> void:
	var guard := Patrol.new()
	guard.position = _guard_posts[post]
	guard.level = level
	# The raise is the warning, so it is heard as well as seen:
	# a guard about to cut off-screen is still a guard about to cut.
	guard.alerted.connect(func() -> void: GameAudio.cue("cloth", {"pitch": 0.7}))
	guard.struck.connect(func() -> void: GameAudio.cue("sword", {"pitch": 0.78}))
	# --- checkpoints --- a guard cut down stays down after a respawn.
	guard.defeated.connect(func() -> void: _guards_down[post] = true)
	_entities.add_child(guard)


func _resolve_interactions() -> void:
	var body := player.body_rect()

	if player.is_alive():
		if level.rect_is_deadly(body) or body.position.y > level.world_size().y + 48.0:
			player.kill()
			return

	var attack := player.attack_rect()
	var has_attack := attack.size.x > 0.0
	secrets.resolve(player) # --- secrets ---

	for node: Node in _entities.get_children():
		if node is Relic and body.intersects((node as Relic).bounds()):
			(node as Relic).collect()
		elif node is Torch:
			_try_claim(node as Torch, body)
		elif node is Patrol:
			_resolve_guard(node as Patrol, body, attack, has_attack)

	if _exit != null and body.intersects(_exit.bounds()):
		_complete()


## One guard against the prince. A guard hurts only with its blade, and only
## while the blade is live (Patrol.strike_rect()); walking into one is free.
## A dying guard is scenery and is skipped entirely.
##
## A swing wounds a given guard once. The sword's rect is live for about eight
## frames and this runs on every one; a hit knocks the guard back about two
## pixels a frame, which does not clear a fourteen-pixel blade, so without
## `_struck` the next live frame hit him again and one swing took both hearts.
func _resolve_guard(guard: Patrol, body: Rect2, attack: Rect2, has_attack: bool) -> void:
	guard.target_rect = body if player.is_alive() else Rect2()
	if not guard.is_alive():
		return
	var id := guard.get_instance_id()
	if has_attack and not _struck.has(id) and attack.intersects(guard.bounds()):
		_struck[id] = true
		guard.hit(player.global_position.x)
		if player.is_plunging():
			_plunge_hit(guard)
			return
		GameAudio.cue("guard_hit")
		# --- feel/flow (additive) ---
		_impact(guard.global_position, Flow.HIT_FRAMES, 1.9, 0.55)
		return
	# A falling player lands on the guard instead of taking the hit.
	var stomping := (
		body.intersects(guard.bounds())
		and player.velocity.y > 40.0
		and body.position.y + body.size.y - guard.bounds().position.y < 10.0
	)
	if stomping:
		guard.hit(player.global_position.x)
		GameAudio.cue("guard_hit", {"pitch": 0.9})
		# --- feel/flow (additive) --- heavier than the
		# sword: the whole body is behind this one.
		_impact(guard.global_position, Flow.STOMP_FRAMES, 2.6, 0.8)
		player.velocity.y = -Tuning.JUMP_SPEED * Tuning.STOMP_BOUNCE
	elif guard.is_dangerous() and body.intersects(guard.strike_rect()):
		if player.deflect(guard.global_position.x) and guard.parried():
			_on_parried(guard)
		elif player.damage(1, guard.global_position.x):
			# --- feel/flow (additive) --- only when it landed:
			# damage() returns false during invulnerability.
			Flow.hitstop(self, Flow.HURT_FRAMES * Flow.FRAME)


## A plunge found a guard: the whole fall is behind this one, so it is the
## heaviest beat in the adventure -- the hitstop ceiling, the hardest shake
## short of a death, a full-weight settle, sparks at his helm -- and the prince
## springs back off him. The low wound sound under a stone thump, because the
## body arrived with the blade.
func _plunge_hit(guard: Patrol) -> void:
	GameAudio.cue("guard_hit", {"pitch": 0.8})
	GameAudio.cue("land_hard", {"volume_db": -6.0})
	_impact(guard.global_position + Vector2(0.0, -Patrol.BODY.y),
		Flow.PLUNGE_FRAMES, 2.8, 1.0)
	player.rebound()


## Steel turned steel. A bright clang rather than the dull wound sound, a held
## frame on the contact, sparks where the blades met, and almost no camera: a
## parry is the prince standing his ground, and a frame that lurches says the
## opposite.
func _on_parried(guard: Patrol) -> void:
	GameAudio.cue("sword_hit", {"pitch": 1.35})
	var at := Vector2(
		(player.global_position.x + guard.global_position.x) * 0.5,
		guard.global_position.y - Patrol.CUT_HIGH)
	_impact(at, Flow.PARRY_FRAMES, 0.8, 0.7)


## A plunge that met stone. The landing already thumps, dusts and settles at
## full weight; on top of it the point bites -- a low ring of steel, a shake
## and sparks at the point. No hitstop: that is for things that resist you,
## and the floor was simply there (docs/feel.md).
func _on_plunge_landed() -> void:
	GameAudio.cue("sword_hit", {"pitch": 0.62, "volume_db": -3.0})
	camera.shake(2.2, 0.22)
	var fx := PlayerFx.attach(player)
	if fx != null and fx.is_inside_tree():
		fx.sword_hit(player.global_position + Vector2(player.facing * 2.0, 0.0), 0.45)


func _complete() -> void:
	GameAudio.cue("level_complete")
	_set_phase(Phase.COMPLETE)
	level_completed.emit(elapsed, relics, relics_total)


func _restart() -> void:
	for node: Node in _entities.get_children():
		node.queue_free()
	_guards_down.clear()
	secrets.reseal() # --- secrets --- behind the wipe, like the rest
	_spawn_entities(level.data)
	secrets.furnish(_entities)
	checkpoint = level.spawn_world_position()
	deaths = 0
	player.respawn(checkpoint)
	camera.setup(player, level.world_size())
	elapsed = 0.0
	_death_timer = 0.0
	_impact_cooldown = 0.0 # --- feel/flow (additive) ---
	_set_phase(Phase.PLAYING)
	_update_hud(true)


## --- secrets --- the found beat. A chime that answers the relic's struck
## brass, the banner with the count, and for a cracked wall the blow landing:
## the sword's own impact, or under a plunge just the shake, since the point
## goes on down into the cellar and lands there with its own beat.
func _on_secret_found(_index: int, kind: String, at: Vector2) -> void:
	GameAudio.cue("secret")
	if kind == "cracked":
		GameAudio.cue("masonry")
		if player.is_plunging():
			camera.shake(2.0, 0.24)
		else:
			_impact(at, Flow.HIT_FRAMES, 2.2, 0.6)
	hud.show_secret(secrets.count, secrets.total)


## A relic is a heart as well as a shard: the level's optional objective pays
## for itself in the one currency the prince runs short of. At full health it
## is only a shard. Nothing is banked and nothing is converted into a score --
## the game keeps none, and the relic tally on the complete screen is already
## the reward for taking the detour. A heal you could store would turn every
## relic into a reason to stand still in front of a guard.
func _on_relic_collected() -> void:
	GameAudio.cue("relic")
	relics += 1
	# heal() reports through `healed`, which refreshes the HUD with both counts
	# at once; a pickup at full health has to refresh it here instead.
	if not player.heal(1):
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


## Every heart lost reaches the corner. Before this the HUD was told only about
## deaths, restarts and relics, so a hit that did not kill left three marks lit
## and the loss flash in Hud never fired in play -- only its unit test saw it.
func _on_hurt(_remaining: int) -> void:
	camera.shake(2.4, 0.26)
	_update_hud()


func _on_died() -> void:
	camera.shake(3.0, 0.4)
	deaths += 1
	_death_timer = DEATH_HOLD
	phase = Phase.DYING
	_update_hud()


## `refill` marks the level starting over -- a restart or a respawn -- which
## the HUD takes silently rather than as a gain or a loss.
func _update_hud(refill: bool = false) -> void:
	hud.update_model(player.health, Tuning.MAX_HEALTH, relics, relics_total, refill)


## --- checkpoints ------------------------------------------------------------
##
## A death used to rebuild the whole level and put the character back on the
## spawn. On the Sun Terrace that is a minute of replay for one missed jump; on
## a 170-column Endless ruin it is two, and the player relearns nothing in
## either: they just walk it again. The torches are already where a person
## would put a checkpoint, on the ground and on the main line, and the
## generator spaces them out, so a torch is a checkpoint, claimed by reaching
## it on your feet. Three rules keep that from going wrong:
##
## - **Proved, not assumed.** A torch counts only if `LevelReachability` routes
##   from its cell to the exit. A torch in a dead-end pit is still a torch; it
##   is just never somewhere a death sends you back to, so a respawn can never
##   be a soft lock.
## - **Forward only.** Walking back past an earlier torch does not move the
##   checkpoint backwards. "Further" is measured toward the exit door.
## - **The level remembers what you did.** Relics you picked up stay picked up
##   and guards you cut down stay down; a guard still standing goes back to its
##   post, so the respawn is never into the middle of the fight that killed
##   you. The clock keeps running: a death costs the seconds since the torch,
##   which is the point, and nothing more.

## Torch cells in `data` that a character could respawn on and still finish.
##
## Proved from the door backwards: each torch only has to reach one already
## proved, so the searches are short hops between torches rather than one
## crossing of the whole level per torch. On a 170-column ruin that is the
## difference between about 300 ms of loading and under 100, on a desktop.
static func checkpoint_cells(data: AsciiLevel) -> Array[Vector2i]:
	var exit_x := 0.0
	var torches: Array[Vector2i] = []
	for mark: Dictionary in data.entities:
		match String(mark["kind"]):
			"exit":
				exit_x = float((mark["cell"] as Vector2i).x)
			"torch":
				torches.append(mark["cell"])
	torches.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return absf(float(a.x) - exit_x) < absf(float(b.x) - exit_x))

	var proved: Array[Vector2i] = []
	for cell: Vector2i in torches:
		if bool(LevelReachability.verify_from(data, cell, proved)["ok"]):
			proved.append(cell)
	# Back in the level's own order, which is what a caller printing it expects.
	var out: Array[Vector2i] = []
	for mark: Dictionary in data.entities:
		if proved.has(mark["cell"]) and String(mark["kind"]) == "torch":
			out.append(mark["cell"])
	return out


func _try_claim(torch: Torch, body: Rect2) -> void:
	if not torch.checkpoint or torch.claimed or not player.is_grounded():
		return
	if absf(body.get_center().x - torch.position.x) > CHECKPOINT_REACH:
		return
	# On the torch's own floor, not jumping past it or on a ledge above it.
	if absf(player.position.y - torch.position.y) > 1.0:
		return
	if _progress(torch.position) <= _progress(checkpoint):
		return
	checkpoint = torch.position
	torch.claim()
	GameAudio.cue("relic", {"pitch": 0.72})


## Larger is closer to the exit. Levels run toward their door, which is the one
## direction every level in the game agrees on.
func _progress(at: Vector2) -> float:
	if _exit == null:
		return at.x
	return -absf(_exit.position.x - at.x)


## Back on the last checkpoint, behind the cover of the wipe.
func _respawn() -> void:
	for node: Node in _entities.get_children():
		if node is Patrol:
			_entities.remove_child(node)
			node.queue_free()
	for post: int in _guard_posts.size():
		if not _guards_down.has(post):
			_spawn_guard(post)
	player.respawn(checkpoint)
	# The same grace as after a hit: a torch can stand on a guard's beat, and
	# the first half-second back is for reading the room, not for paying again.
	player.invulnerable = Tuning.INVULNERABLE_TIME
	camera.setup(player, level.world_size())
	_death_timer = 0.0
	_impact_cooldown = 0.0
	_set_phase(Phase.PLAYING)
	_update_hud(true)
