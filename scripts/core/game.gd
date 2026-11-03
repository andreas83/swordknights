class_name Game
extends Node2D
## The playable scene: owns a level's world, actors, camera and presentation,
## and arbitrates the interactions between them.
##
## Everything level-specific comes from the ASCII file it is given, so adding a
## level — hand-authored or generated — means supplying different text, not
## touching this file.
##
## The same holds for what is in a level. Every mark is placed through the
## entity registry (scripts/entities/entity_registry.gd) and every entity met
## the same way, once a frame, through a Contact; a foe hands itself back to
## be refereed against the foe contract (scripts/entities/foe.gd). So no kind
## of thing is named here, and adding one -- a foe, a mechanism, a boss --
## means a new file and a registry line (docs/architecture.md, "Adding a
## foe"). What is here is the referee: the rules for a sword, a stomp and a
## cut, the checkpoint, the tally, and the presentation every impact shares.

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
# --- feel/flow (additive) --- the backstep's camera beat, as a share of a
# full-weight landing's settle: GameCamera.SETTLE_MAX 4 px x 0.3 rounds to one
# pixel. Enough that the weight is felt going back, too little to be seen.
const BACKSTEP_SETTLE := 0.3

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
# The level's way out, for measuring which checkpoint is further on. The last
# exit mark's, like the door the level is run toward. See _progress().
var _goal := Vector2.ZERO
var _has_goal := false
# Set by an exit during the interaction pass; the level ends after the pass,
# so everything else touched on the same frame counts first.
var _completing := false
# The prince as the level's entities see him, refreshed every playing frame.
var _contact := Contact.new()
# --- feel/flow (additive) --- last seen value of Flow.is_hitstopped(), so the
# freeze is applied on the edge rather than re-asserted every frame.
var _hitstopped := false
var _impact_cooldown: float = 0.0
# --- checkpoints --- torch cells proved to route to the exit, the marks whose
# entities come back at a respawn -- foes and mechanisms, with their order
# among their kind -- and the posts cleared for good.
var _checkpoint_cells: Array[Vector2i] = []
var _returning: Array[Dictionary] = []
var _down: Dictionary = {}
# --- mechanisms --- the wiring of the mechanisms now placed. A new one every
# time they are placed again, so one on its way out never hears the next.
var _bus := ChannelBus.new()
# Foes the current swing has already reached, by instance id. Cleared when a
# new swing starts. See _resolve_foe().
var _struck: Dictionary = {}
# --- secrets --- the level's secret rooms: what opens them, what is in them,
# how many are found. See scripts/world/secret_keeper.gd.
var secrets := SecretKeeper.new()


func _ready() -> void:
	var data := level_source if level_source != null else AsciiLevel.from_file(level_path)
	if data == null:
		push_error("no level data")
		return
	# Malformed directives and glyphs in no legend: the level still plays, and
	# whoever wrote it hears about it here (tests refuse a shipping level with
	# any).
	for problem: String in data.problems + EntityRegistry.problems_in(data):
		push_warning("%s: %s" % [data.name, problem])

	level.build(data)
	_checkpoint_cells = checkpoint_cells(data)
	_entities = Node2D.new()
	_entities.name = "Entities"
	add_child(_entities)
	_contact.exit_reached = func() -> void: _completing = true
	_contact.checkpoint_offered = _offer_checkpoint
	_contact.foe_met = _resolve_foe
	_contact.shot_met = _resolve_shot
	_contact.harmed = _harm
	_bus = ChannelBus.for_level(data)
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
	# The backstep's weight going onto the rear foot: a single pixel of dip,
	# the lightest settle in the game. The lead is held by the camera itself.
	player.backstepped.connect(func() -> void: camera.settle(BACKSTEP_SETTLE))
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
			# --- mechanisms --- the wires' clock: holds count down, beats turn.
			_bus.step()
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


## Every mark, in the level's order, through the registry. Kinds the registry
## does not place (EntityRegistry.ELSEWHERE) are left to whoever does.
func _spawn_entities(data: AsciiLevel) -> void:
	relics = 0
	relics_total = 0
	_returning.clear()
	_has_goal = false
	var counted := {}
	for mark: Dictionary in data.entities:
		var kind := String(mark["kind"])
		var ordinal := int(counted.get(kind, 0))
		counted[kind] = ordinal + 1
		var node := _place(mark, ordinal)
		if node is Foe or node is Mechanism:
			_returning.append({"mark": mark, "ordinal": ordinal})


## One entity from one mark: made by the registry, placed on its site, its
## presentation signals wired to Game's, and into the level.
func _place(mark: Dictionary, ordinal: int) -> Node:
	var kind := String(mark["kind"])
	var node := EntityRegistry.make(kind)
	if node == null:
		if not EntityRegistry.ELSEWHERE.has(kind):
			push_warning("no entity registered for '%s' (scripts/entities/entity_registry.gd)"
				% kind)
		return null
	node.call(&"place", _site_for(mark, ordinal))
	_adopt(node)
	_entities.add_child(node)
	return node


func _site_for(mark: Dictionary, ordinal: int) -> EntitySite:
	var site := EntitySite.new()
	site.kind = String(mark["kind"])
	site.cell = mark["cell"]
	for cell: Vector2i in mark.get("cells", [site.cell]):
		site.cells.append(cell)
	site.params = mark.get("params", {})
	site.at = level.entity_world_position(site.cell)
	site.post = EntitySite.post_of(site.kind, site.cell)
	site.ordinal = ordinal
	site.level = level
	site.checkpoint = _checkpoint_cells.has(site.cell)
	site.bus = _bus
	site.relic_taken = _on_relic_collected
	site.relic_counted = func() -> void: relics_total += 1
	site.exit_declared = _declare_exit
	return site


## A way out was placed at `at`. The last one placed is the door the level is
## run toward, and checkpoints are measured against it (_progress()).
func _declare_exit(at: Vector2) -> void:
	_goal = at
	_has_goal = true


## Wires what an entity asks of the game: its sounds through GameAudio.cue,
## its weight through _impact(), and for a foe, its projectiles and the memory
## that it is down.
func _adopt(node: Node) -> void:
	if node.has_signal(&"cue"):
		node.connect(&"cue", _on_cue)
	if node.has_signal(&"impact"):
		node.connect(&"impact", _impact)
	var foe := node as Foe
	if foe == null:
		return
	foe.launched.connect(_adopt_runtime)
	foe.summoned.connect(_adopt_runtime)
	# --- checkpoints --- a foe cut down stays down after a respawn.
	if foe.post != "":
		var post := foe.post
		foe.defeated.connect(func() -> void: _down[post] = true)


## Something a foe brought into the level -- a projectile, a summons. It has
## no mark, so a respawn clears it and nothing puts it back.
func _adopt_runtime(node: Node) -> void:
	_adopt(node)
	_entities.add_child(node)


func _on_cue(voice: StringName, options: Dictionary) -> void:
	GameAudio.cue(voice, options)


func _resolve_interactions() -> void:
	var body := player.body_rect()

	if player.is_alive():
		if level.rect_is_deadly(body) or body.position.y > level.world_size().y + 48.0:
			player.kill()
			return

	_read_contact(body)
	secrets.resolve(player) # --- secrets ---

	_completing = false
	for node: Node in _entities.get_children():
		if node.has_method(&"meet"):
			node.call(&"meet", _contact)
	if _completing:
		_complete()


## The prince as this frame's pass sees him. Read once, before anything is
## met, so every entity on the frame sees the same body and the same blade.
func _read_contact(body: Rect2) -> void:
	_contact.body = body
	_contact.blade = player.attack_rect()
	_contact.feet = player.position
	_contact.velocity = player.velocity
	_contact.facing = player.facing
	_contact.grounded = player.is_grounded()
	_contact.alive = player.is_alive()
	_contact.plunging = player.is_plunging()


## One foe against the prince, through the foe contract. A dying foe is
## scenery and is skipped entirely; one that is alive hurts only through its
## dangers, and walking into it is free.
##
## The body and the blade are this frame's, as the pass began. Everything
## else is read from the prince as it is now, because a foe met earlier in
## the same pass may have changed it: a plunge that found one guard has
## already sprung him back, so the next is met by a falling prince, not a
## plunging one.
##
## A swing reaches a given foe once. The sword's rect is live for about eight
## frames and this runs on every one; a hit knocks a guard back about two
## pixels a frame, which does not clear a fourteen-pixel blade, so without
## `_struck` the next live frame hit him again and one swing took both hearts.
func _resolve_foe(foe: Foe) -> void:
	var body := _contact.body
	foe.target_rect = body if player.is_alive() else Rect2()
	if not foe.is_alive():
		return
	var id := foe.get_instance_id()
	if _contact.has_blade() and not _struck.has(id) \
			and _contact.blade.intersects(foe.hurt_rect()):
		_struck[id] = true
		var plunging := player.is_plunging()
		var blow := Foe.Blow.PLUNGE if plunging else Foe.Blow.SWORD
		var outcome := foe.take_blow(blow, player.global_position.x)
		if plunging:
			_plunge_hit(foe, outcome)
		else:
			_sword_hit(foe, outcome)
		return
	# A falling player lands on the foe instead of taking the hit.
	var stomping := (
		body.intersects(foe.bounds())
		and player.velocity.y > 40.0
		and body.position.y + body.size.y - foe.bounds().position.y < 10.0
	)
	if stomping:
		var outcome := foe.take_blow(Foe.Blow.STOMP, player.global_position.x)
		if outcome != Foe.Outcome.NONE:
			_stomp_hit(foe, outcome)
			return
	if foe.is_dangerous():
		for danger: FoeDanger in foe.dangers():
			if _resolve_danger(danger, body):
				break


## One danger against the prince's body. True when it touched him, whatever
## came of it: a foe hurts once a frame.
func _resolve_danger(danger: FoeDanger, body: Rect2) -> bool:
	if not body.intersects(danger.rect):
		return false
	if danger.can_be_parried() and player.deflect(danger.from_x) and danger.parried():
		_on_parried(danger)
	elif danger.evadable and player.evades(danger.from_x):
		# The backstep: the cut goes by in front of him. Nothing happens
		# to either of them -- the guard's own cut is its sound, and the
		# missing hit is the read. No riposte, no reel: see Player.evades().
		pass
	else:
		var dealt := player.damage(danger.damage, danger.from_x)
		danger.landed(dealt)
		if dealt:
			# --- feel/flow (additive) --- only when it landed:
			# damage() returns false during invulnerability.
			Flow.hitstop(self, Flow.HURT_FRAMES * Flow.FRAME)
	return true


## A foe's projectile in flight. Until a parry turns it, a danger to the
## prince; after, the prince's, and the first foe it meets takes it as a blow.
func _resolve_shot(shot: FoeProjectile) -> void:
	if shot.is_spent():
		return
	if not shot.reflected:
		var danger := shot.danger()
		if danger != null and player.is_alive():
			_resolve_danger(danger, _contact.body)
		return
	for node: Node in _entities.get_children():
		var foe := node as Foe
		if foe == null or not foe.is_alive() or not shot.rect().intersects(foe.hurt_rect()):
			continue
		var outcome := foe.take_blow(Foe.Blow.SHOT, shot.global_position.x - shot.velocity.x)
		_sword_hit(foe, outcome)
		shot.spend()
		return


## A swing, an air slash or a sent-back shot met a foe.
func _sword_hit(foe: Foe, outcome: Foe.Outcome) -> void:
	match outcome:
		Foe.Outcome.NONE:
			pass
		Foe.Outcome.BLOCKED:
			_on_blocked(foe)
		_:
			GameAudio.cue(foe.wound_voice())
			# --- feel/flow (additive) ---
			_impact(foe.global_position, Flow.HIT_FRAMES, 1.9, 0.55)


## A falling prince landed on one. Heavier than the sword: the whole body is
## behind this one. He bounces either way; a foe that turned it takes no
## wound and makes the clang instead.
func _stomp_hit(foe: Foe, outcome: Foe.Outcome) -> void:
	if outcome == Foe.Outcome.BLOCKED:
		_on_blocked(foe)
	else:
		GameAudio.cue(foe.wound_voice(), {"pitch": 0.9})
		# --- feel/flow (additive) ---
		_impact(foe.global_position, Flow.STOMP_FRAMES, 2.6, 0.8)
	player.velocity.y = -Tuning.JUMP_SPEED * Tuning.STOMP_BOUNCE


## A plunge found a foe: the whole fall is behind this one, so it is the
## heaviest beat in the adventure -- the hitstop ceiling, the hardest shake
## short of a death, a full-weight settle, sparks at his helm -- and the prince
## springs back off him. The low wound sound under a stone thump, because the
## body arrived with the blade. A foe the plunge passed through (NONE) is not
## sprung from.
func _plunge_hit(foe: Foe, outcome: Foe.Outcome) -> void:
	match outcome:
		Foe.Outcome.NONE:
			return
		Foe.Outcome.BLOCKED:
			_on_blocked(foe)
		_:
			GameAudio.cue(foe.wound_voice(), {"pitch": 0.8})
			GameAudio.cue("land_hard", {"volume_db": -6.0})
			_impact(foe.impact_point(), Flow.PLUNGE_FRAMES, 2.8, 1.0)
	player.rebound()


## Steel turned steel. A bright clang rather than the dull wound sound, a held
## frame on the contact, sparks where the blades met, and almost no camera: a
## parry is the prince standing his ground, and a frame that lurches says the
## opposite.
func _on_parried(danger: FoeDanger) -> void:
	GameAudio.cue("sword_hit", {"pitch": 1.35})
	var at := Vector2(
		(player.global_position.x + danger.from_x) * 0.5, danger.rect.position.y)
	_impact(at, Flow.PARRY_FRAMES, 0.8, 0.7)


## The prince's blow was turned by the foe -- a shield, a guard up. The same
## clang a parry makes, a shade lower, and the smallest held beat: something
## resisted him, but nothing gave.
func _on_blocked(foe: Foe) -> void:
	GameAudio.cue("sword_hit", {"pitch": 1.1})
	_impact(foe.impact_point(), Flow.HURT_FRAMES, 0.6, 0.4)


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


## A mechanism hurt the prince: the cut's own path, grace and held frames.
func _harm(hearts: int, from_x: float) -> bool:
	var dealt := player.damage(hearts, from_x)
	if dealt:
		Flow.hitstop(self, Flow.HURT_FRAMES * Flow.FRAME)
	return dealt


func _restart() -> void:
	for node: Node in _entities.get_children():
		# A mechanism or a shot leaves now, not at the end of the frame. Left
		# in the tree it is met once more: a plate lets go on the bus it was
		# wired to, its old gate shuts and takes back the cells its
		# replacement has just claimed, then clears them as it is freed.
		if node is Mechanism or node is FoeProjectile:
			_entities.remove_child(node)
		node.queue_free()
	_down.clear()
	_bus = ChannelBus.for_level(level.data)
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
##   and foes you cut down stay down; a foe still standing goes back to its
##   post, so the respawn is never into the middle of the fight that killed
##   you, and anything a foe had loosed is gone. The clock keeps running: a
##   death costs the seconds since the torch, which is the point, and nothing
##   more.
## - **A trap resets; a deed does not.** Every plate, gate and crumbling floor
##   is put back as the level text placed it, on a new bus that keeps what the
##   old one latched: a gate whose plate latched it comes back open, a hold
##   that was running does not, and a beat starts its count again. A latched
##   wire is a puzzle solved, and solving it again after every death is replay
##   with nothing to learn. What keeps the first rule true is the proof: a
##   torch is proved from every channel mask the prince can be standing on it
##   under (LevelReachability.prove_checkpoints()), and every bit in a mask is
##   a latch, so whatever he respawns with is a state the proof has walked. A
##   latch that drops a floor between a torch and the door costs that torch
##   its checkpoint instead of making the respawn a soft lock. The rest that
##   persists is safe by construction: relics never touch passability, foes
##   being down only removes danger, and found secrets are proved never-a-trap
##   in every combination (audit_secrets).

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

	var proved := LevelReachability.prove_checkpoints(data, torches)
	# Back in the level's own order, which is what a caller printing it expects.
	var out: Array[Vector2i] = []
	for mark: Dictionary in data.entities:
		if proved.has(mark["cell"]) and String(mark["kind"]) == "torch":
			out.append(mark["cell"])
	return out


## A torch (or anything else that can be) offered `at` as the place a death
## comes back to. Forward only: taken when it is further on than the one held.
## The torch decides what reaching it means (Torch.meet()); this decides
## whether it counts.
func _offer_checkpoint(at: Vector2) -> bool:
	if _progress(at) <= _progress(checkpoint):
		return false
	checkpoint = at
	GameAudio.cue("relic", {"pitch": 0.72})
	return true


## Larger is closer to the exit. Levels run toward their door, which is the one
## direction every level in the game agrees on.
func _progress(at: Vector2) -> float:
	if not _has_goal:
		return at.x
	return -absf(_goal.x - at.x)


## Back on the last checkpoint, behind the cover of the wipe. Every foe still
## standing goes back to its post, every projectile in the air is gone, every
## mechanism is as authored on a new bus that keeps the old one's latches,
## and the rest of the level stays as the prince left it.
func _respawn() -> void:
	for node: Node in _entities.get_children():
		if node is Foe or node is FoeProjectile or node is Mechanism:
			_entities.remove_child(node)
			node.queue_free()
	_bus = ChannelBus.for_level(level.data, _bus)
	for entry: Dictionary in _returning:
		var mark: Dictionary = entry["mark"]
		if not _down.has(EntitySite.post_of(String(mark["kind"]), mark["cell"])):
			_place(mark, int(entry["ordinal"]))
	player.respawn(checkpoint)
	# The same grace as after a hit: a torch can stand on a guard's beat, and
	# the first half-second back is for reading the room, not for paying again.
	player.invulnerable = Tuning.INVULNERABLE_TIME
	camera.setup(player, level.world_size())
	_death_timer = 0.0
	_impact_cooldown = 0.0
	_set_phase(Phase.PLAYING)
	_update_hud(true)
