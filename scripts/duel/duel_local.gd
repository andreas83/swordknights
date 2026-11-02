class_name DuelLocalScene
extends Node2D
## Two players, one keyboard, no network.
##
## This is the whole duel with the networking taken out, and it is deliberately
## the shortest file in scripts/duel: build the arena, read two bytes of input,
## step. Everything else — rounds, hit resolution, respawns — is in Duel,
## because the online mode has to get exactly the same rules from exactly the
## same code.
##
## It is also the fallback. When a connection cannot be made, the lobby offers
## this, and scripts/duel/duel_online.gd drops into it.
##
## CONTROLS (written by tools/configure_project.gd)
##   seat one   A D   W S   SPACE jump   F sword   G guard   SHIFT walk
##   seat two   ← →   ↑ ↓   K jump       J sword   L guard   ; walk
##              (and the numpad: 4 6 8 5, 0 jump, 1 sword, 2 guard)
##
## The two sets do not overlap, which they would if the second player simply
## reused the shared actions — those already claim both the arrows and WASD.

const MENU_SCENE := "res://scenes/menu.tscn"

@onready var duel: Duel = $Duel
@onready var camera: DuelCamera = $Camera
@onready var sky: ParallaxSky = $Sky/ParallaxSky
@onready var hud: DuelHud = $HudLayer/Hud

var _paused := false


func _ready() -> void:
	var arena := AsciiLevel.from_file(DuelRules.ARENA_PATH)
	if arena == null:
		push_error("no arena at %s" % DuelRules.ARENA_PATH)
		return

	duel.setup(arena)
	for slot: int in 2:
		# Both duellists belong to whoever is at the keyboard, so neither gets
		# the "this one is you" marker.
		DuelArt.dress(duel.players[slot], slot, false)

	camera.setup(duel)
	sky.camera = camera
	sky.seed_value = hash(arena.name)

	hud.duel = duel
	hud.footer = "PAUSE TO QUIT"

	duel.cut_landed.connect(_on_cut_landed)
	duel.cut_blocked.connect(_on_cut_blocked)
	duel.swords_clashed.connect(_on_clash)
	duel.round_ended.connect(_on_round_ended)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		if duel.phase == Duel.Phase.MATCH_OVER:
			_to_menu()
			return
		_paused = not _paused
		hud.footer = "PAUSE TO RESUME  ·  SWORD TO QUIT" if _paused else "PAUSE TO QUIT"

	if _paused:
		if Input.is_action_just_pressed("attack"):
			_to_menu()
		return

	if duel.phase == Duel.Phase.MATCH_OVER:
		hud.footer = "JUMP FOR A REMATCH  ·  SWORD FOR THE MENU"
		if Input.is_action_just_pressed("jump"):
			duel.reset_match()
			camera.setup(duel)
		elif Input.is_action_just_pressed("attack"):
			_to_menu()
		return

	# The only line that matters: one frame of duel is two bytes of intent.
	duel.step(
		PlayerInput.bits_from_actions("_p1"),
		PlayerInput.bits_from_actions("_p2")
	)


func _to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## --- presentation reactions -------------------------------------------------

func _on_cut_landed(victim: int, _at: Vector2) -> void:
	camera.shake(3.4, 0.4)
	hud.flash("%s DOWN" % DuelRules.slot_label(victim))


func _on_cut_blocked(_defender: int, parried: bool, _at: Vector2) -> void:
	camera.shake(2.6 if parried else 1.5, 0.22)
	hud.flash("PARRY" if parried else "BLOCKED")


func _on_clash(_at: Vector2) -> void:
	camera.shake(2.0, 0.2)
	hud.flash("CLASH")


func _on_round_ended(winner: int) -> void:
	if winner == DuelRules.DRAW:
		hud.flash("DRAW")
