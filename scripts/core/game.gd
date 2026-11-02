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

const DEATH_HOLD := 1.1
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


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		if phase == Phase.PLAYING:
			_set_phase(Phase.PAUSED)
		elif phase == Phase.PAUSED:
			_set_phase(Phase.PLAYING)

	match phase:
		Phase.PAUSED:
			if Input.is_action_just_pressed("attack"):
				get_tree().change_scene_to_file(MENU_SCENE)
		Phase.COMPLETE:
			if Input.is_action_just_pressed("jump"):
				_restart()
			elif Input.is_action_just_pressed("attack"):
				get_tree().change_scene_to_file(MENU_SCENE)
		Phase.DYING:
			_death_timer -= delta
			if _death_timer <= 0.0:
				_restart()
		Phase.PLAYING:
			elapsed += delta
			_resolve_interactions()


func _set_phase(next: Phase) -> void:
	phase = next
	var frozen := next == Phase.PAUSED or next == Phase.COMPLETE
	player.set_physics_process(not frozen)
	_entities.process_mode = (
		Node.PROCESS_MODE_DISABLED if frozen else Node.PROCESS_MODE_INHERIT
	)
	hud.set_overlay(_overlay_title(), _overlay_subtitle())


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
			elif body.intersects(guard.bounds()):
				# A falling player lands on the guard instead of taking the hit.
				var stomping := (
					player.velocity.y > 40.0
					and body.position.y + body.size.y - guard.bounds().position.y < 10.0
				)
				if stomping:
					guard.hit(player.global_position.x)
					player.velocity.y = -Tuning.JUMP_SPEED * 0.68
				else:
					player.damage(1, guard.global_position.x)

	if _exit != null and body.intersects(_exit.bounds()):
		_complete()


func _complete() -> void:
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
	_set_phase(Phase.PLAYING)
	_update_hud()


func _on_relic_collected() -> void:
	relics += 1
	_update_hud()


func _on_landed(impact: float) -> void:
	if impact >= Tuning.HARD_LAND_SPEED:
		camera.shake(1.6, 0.18)


func _on_died() -> void:
	camera.shake(3.0, 0.4)
	_death_timer = DEATH_HOLD
	phase = Phase.DYING
	_update_hud()


func _update_hud() -> void:
	hud.update_model(player.health, Tuning.MAX_HEALTH, relics, relics_total)
