extends Node2D
## The tug-of-war, playable: two seats on one keyboard, five zones, two gates.
##
## Build the world, read two bytes of input, step. Everything that is the mode
## — initiative, the window, respawns, the gates — is in scripts/duel/match.gd,
## because the networked version (scripts/duel/match_online.gd, which extends
## this) has to get exactly the same rules out of exactly the same code. What is
## here is wiring and reactions. The menu's Duel entry is this scene.
##
## CONTROLS (written by tools/configure_project.gd)
##   seat one   A D   W S   SPACE jump   F sword   G guard   SHIFT walk
##   seat two   <- ->  up/down  K jump   J sword   L guard   ; walk
##
## THE ATTRACT DEMO
## Run with `--demo` in the user arguments and the scene drives itself through a
## scripted match: a kill, the initiative arrow, a run west across a zone
## boundary, and a cluster of exchanges in one place so the floor fills up. It
## exists because the three things this layer has to be LOOKED at to judge — a
## seam crossing that does not stutter, the indicator, and accumulated gore —
## cannot be judged from a test's exit code. docs/duel-match.png is three frames
## of it, taken with tools/screenshot.gd, which needs no display and no edits:
##
##     xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --script tools/screenshot.gd -- --scene res://scenes/duel_match.tscn \
##       --out /tmp/shots --shots 3.4,9.0,15.5 --demo

const MENU_SCENE := "res://scenes/menu.tscn"
const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighter.tscn")
const MANIFEST := "res://levels/duel_zones.txt"

@onready var fight: DuelMatch = $World/Match
@onready var zones: ZoneView = $World/ZoneView
@onready var gore: GoreField = $World/Gore
@onready var camera: MatchCamera = $Camera
@onready var sky: ParallaxSky = $Sky/ParallaxSky
@onready var hud: MatchHud = $HudLayer/Hud

var strip: ZoneStrip
var demo := false

var _gates: Array[GateArt] = []
var _paused := false
var _demo_frame := 0


func _ready() -> void:
	demo = OS.get_cmdline_user_args().has("--demo")

	strip = ZoneStrip.from_manifest(MANIFEST)
	if strip == null:
		push_error("no zone strip at %s" % MANIFEST)
		return

	zones.setup(strip)
	gore.setup(strip)
	gore.z_index = -1 # beneath the actors, in one pass

	fight.fighter_scene = FIGHTER_SCENE
	if not fight.build(strip, zones):
		push_error("the match would not build")
		return

	_start_in_zone_argument()

	# Seat two wears steel and sea-green; teal is player two's colour and no one
	# else's (docs/art-direction.md). Presentation, so it is set here and not
	# in the match, which must not know what a fighter looks like.
	for slot: int in fight.seats.size():
		var fighter := fight.seats[slot].node as Fighter
		if fighter != null:
			FighterArt.dress(fighter, slot)

	camera.framing_width = _framing_argument()
	camera.setup(fight)
	sky.camera = camera
	_light_the_last_rooms()
	sky.seed_value = hash(strip.name)

	_build_gates()

	hud.fight = fight
	hud.footer = "PAUSE TO QUIT" if not demo else strip.name.to_upper()

	fight.fighter_died.connect(_on_fighter_died)
	fight.initiative_changed.connect(_on_initiative_changed)
	fight.fighter_respawned.connect(_on_fighter_respawned)
	fight.leader_consumed.connect(_on_leader_consumed)
	fight.match_over.connect(_on_match_over)


## Dusk over the gate zone at each end of the strip. See MatchDusk.
func _light_the_last_rooms() -> void:
	for seat: DuelSeat in fight.seats:
		var art := seat.node.get_node_or_null("FighterArt")
		if art != null:
			art.add_to_group(MatchDusk.LIT)
	var dusk := MatchDusk.new()
	dusk.name = "Dusk"
	add_child(dusk)
	dusk.setup(camera, strip, sky)


## `--start-zone=N` in the user arguments opens the match with the window on
## zone N instead of the middle, both fighters on open ground in it. For looking
## at a zone -- the dusk over the last rooms above all -- without fighting the
## way there. Not a game mode: it writes match state from outside the match.
func _start_in_zone_argument() -> void:
	var zone := -1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--start-zone="):
			zone = arg.trim_prefix("--start-zone=").to_int()
	if zone < 0 or zone >= strip.zone_count():
		return
	var left := strip.zone_left(zone)
	var width := strip.zone_width()
	fight.scroll = left
	fight.zone_index = zone
	for slot: int in fight.seats.size():
		var wanted := left + width * (0.38 if slot == 0 else 0.62)
		var found := strip.find_open_ground(wanted, left + width * 0.5)
		if bool(found["ok"]):
			fight.seats[slot].respawn_at(found["position"], 1 if slot == 0 else -1)


## `--framing=320` in the user arguments frames the view that many world pixels
## wide instead of one zone. Used to compare zone widths on screen; see
## docs/duel-match.md.
func _framing_argument() -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--framing="):
			return maxf(0.0, arg.trim_prefix("--framing=").to_float())
	return 0.0


func _build_gates() -> void:
	for seat: int in 2:
		var gate := GateArt.new()
		gate.name = "Gate%d" % seat
		$World.add_child(gate)
		var cell: Vector2i = strip.gates[seat]
		gate.setup(
			Vector2(cell.x * ZoneStrip.TILE + ZoneStrip.TILE * 0.5,
				float(cell.y + 1) * ZoneStrip.TILE),
			ZoneStrip.goal_direction(seat),
			hash(strip.name) + seat
		)
		_gates.append(gate)


func _physics_process(_delta: float) -> void:
	if demo:
		_demo_frame += 1
		var bits := _demo_input()
		fight.step(bits.x, bits.y)
		_follow_the_match()
		return

	if Input.is_action_just_pressed("pause"):
		if fight.phase == DuelMatch.Phase.MATCH_OVER:
			_to_menu()
			return
		_paused = not _paused
		hud.footer = "PAUSE TO RESUME  ·  SWORD TO QUIT" if _paused else "PAUSE TO QUIT"

	if _paused:
		if Input.is_action_just_pressed("attack"):
			_to_menu()
		return

	if fight.phase == DuelMatch.Phase.MATCH_OVER:
		hud.footer = "JUMP FOR A REMATCH  ·  SWORD FOR THE MENU"
		if Input.is_action_just_pressed("jump"):
			_rematch()
		elif Input.is_action_just_pressed("attack"):
			_to_menu()
		return

	# The only line that matters: one frame of match is two bytes of intent.
	fight.step(
		PlayerInput.bits_from_actions("_p1"),
		PlayerInput.bits_from_actions("_p2")
	)
	_follow_the_match()


## Presentation that tracks the simulation rather than reacting to it: which
## zones to draw gore for, and how far through being consumed the winner is.
func _follow_the_match() -> void:
	gore.show_zones(camera.visible_zones())
	for seat: int in _gates.size():
		_gates[seat].consuming = (
			clampf(fight.phase_time / DuelMatch.CONSUMED_TIME, 0.0, 1.0)
			if fight.phase == DuelMatch.Phase.CONSUMED and fight.winner == seat
			else 0.0
		)


func _rematch() -> void:
	fight.reset_match()
	gore.clear()
	camera.setup(fight)
	hud.footer = "PAUSE TO QUIT"


func _to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## --- reactions --------------------------------------------------------------

func _on_fighter_died(victim: int, _killer: int, at: Vector2) -> void:
	# The dead fighter's colour, and it stays for the match.
	gore.spill(at, victim, fight.frame)
	camera.shake(3.6, 0.42)
	hud.flash("%s DOWN" % DuelRules.slot_label(victim))


func _on_initiative_changed(leader: int) -> void:
	if leader < 0:
		return
	var who := DuelRules.slot_label(leader)
	hud.flash("%s HAS THE INITIATIVE" % who, "%s LEADS" % who)


func _on_fighter_respawned(_slot: int, _at: Vector2, _facing: int) -> void:
	camera.shake(1.0, 0.16)


func _on_leader_consumed(winner: int, _at: Vector2) -> void:
	camera.shake(2.2, 0.6)
	var who := DuelRules.slot_label(winner)
	hud.flash("%s REACHES THE GATE" % who, "%s AT THE GATE" % who)


func _on_match_over(_winner: int) -> void:
	hud.footer = "JUMP FOR A REMATCH  ·  SWORD FOR THE MENU"


## --- the attract demo -------------------------------------------------------
##
## A scripted match, by frame number, so a screenshot taken at a given second
## shows the same thing every time. Kills are scripted rather than fought: this
## branch's fighter is a placeholder and cannot be relied on to land a blow at
## a particular moment, and the point of the demo is the match layer anyway.
## The fighters are real now; the kills stay scripted so a screenshot at a given
## second is the same screenshot every time.

## frame -> [victim, killer]
const DEMO_KILLS := {
	120: [1, 0],
	430: [1, 0],
	560: [0, 1],
	700: [1, 0],
	820: [0, 1],
	960: [1, 0],
	1260: [0, 1],
}


func _demo_input() -> Vector2i:
	if DEMO_KILLS.has(_demo_frame):
		var pair: Array = DEMO_KILLS[_demo_frame]
		var victim := int(pair[0])
		if fight.is_fighter_alive(victim):
			fight.seats[victim].kill(int(pair[1]))

	var leader := fight.leader_slot()
	if leader < 0:
		# Before the first kill, close the distance so the first exchange reads.
		return Vector2i(PlayerInput.BIT_RIGHT, PlayerInput.BIT_LEFT)

	# The leader runs at their gate; the other one runs at the leader.
	var bits := PackedInt32Array([0, 0])
	bits[leader] = _walk(leader, ZoneStrip.goal_direction(leader))
	var chaser := 1 - leader
	var toward := signi(int(
		fight.fighter_position(leader).x - fight.fighter_position(chaser).x
	))
	bits[chaser] = _walk(chaser, toward if toward != 0 else 1)
	return Vector2i(bits[0], bits[1])


## Holds a direction and jumps at a gap or a step, which is what a player does.
func _walk(slot: int, direction: int) -> int:
	var bits := PlayerInput.BIT_LEFT if direction < 0 else PlayerInput.BIT_RIGHT
	var at := fight.fighter_position(slot)
	var column := floori(at.x / ZoneStrip.TILE)
	var here := strip.ground_row(column)
	var ahead := strip.ground_row(column + direction)
	var blocked := ahead < 0 or (here > 0 and ahead < here)
	# Held, then let go long enough for the next press to be an edge. A tap is
	# not a jump: the fighter has variable jump height, and two frames of jump
	# is a 13 px hop that will not clear a one-tile step. The placeholder had no
	# jump cut, which is why the old two-frame tap worked for it.
	if blocked and _demo_frame % 20 < 14:
		bits |= PlayerInput.BIT_JUMP
	return bits
