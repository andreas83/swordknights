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
## Where the seats' looks are read from. A seam for a test, which must never
## read or write the real save.
var wardrobe_path := Wardrobe.PATH

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

	dress_fighters()

	camera.framing_width = _framing_argument()
	camera.setup(fight)
	sky.camera = camera
	_light_the_last_rooms()
	sky.seed_value = hash(strip.name)

	_build_gates()

	hud.fight = fight
	hud.footer = "PAUSE TO QUIT" if not demo else strip.name.to_upper()

	fight.fighter_died.connect(_on_fighter_died)
	fight.death_recorded.connect(_on_death_recorded)
	fight.death_retracted.connect(_on_death_retracted)
	fight.initiative_changed.connect(_on_initiative_changed)
	fight.fighter_respawned.connect(_on_fighter_respawned)
	fight.leader_consumed.connect(_on_leader_consumed)
	fight.match_over.connect(_on_match_over)
	fight.blade_caught.connect(_on_blade_caught)


## Puts each seat in its look. Seat two wears sea-green whatever look it has;
## teal is player two's colour and no one else's (docs/art-direction.md, and
## FighterArt.dress). Presentation, so it is set here and not in the match,
## which must not know what a fighter looks like. Public so a scene that learns
## who is who later -- an online match, once seated -- can dress them again.
func dress_fighters() -> void:
	for slot: int in fight.seats.size():
		var fighter := fight.seats[slot].node as Fighter
		if fighter != null:
			FighterArt.dress(fighter, slot, look_for(slot))


## The look a seat wears: on one keyboard, the wardrobe's player one in the
## crimson seat and player two in the sea-green. The attract demo wears the
## defaults, so a screenshot of it never depends on what someone last chose in
## the wardrobe. match_online.gd answers this differently.
func look_for(slot: int) -> CharacterLook:
	if demo:
		return CharacterLook.new()
	return Wardrobe.open(wardrobe_path).look(slot)


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

	_step()
	_follow_the_match()


## The only line that matters: one frame of match is two bytes of intent. Here
## both come off one keyboard; scripts/duel/match_cpu.gd takes the second from
## the computer instead, and that is the whole of the difference.
func _step() -> void:
	fight.step(
		PlayerInput.bits_from_actions("_p1"),
		PlayerInput.bits_from_actions("_p2")
	)


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
##
## Each of these is rung once per thing that happened, by the match's ledger,
## and never by a frame NetSession steps again -- see DuelMatch and
## docs/netplay.md, "Corrected outcomes". So nothing here has to guard itself
## against an echo. The one reaction that is a record rather than a beat, the
## blood, has its own pair of signals, because a correction can take it back.

func _on_fighter_died(victim: int, _killer: int, _at: Vector2) -> void:
	camera.shake(3.6, 0.42)
	hud.flash(_down(victim))


## The dead fighter's colour, and it stays for the match -- unless the host
## says the death did not happen, or happened elsewhere.
func _on_death_recorded(victim: int, at: Vector2, frame: int) -> void:
	gore.spill(at, victim, frame)


## A kill the host never had. The shake and the sound are spent; the blood
## comes off the floor and the word off the band, because both would go on
## saying something untrue.
func _on_death_retracted(victim: int, frame: int) -> void:
	gore.wipe(victim, frame)
	hud.withdraw(_down(victim))


func _down(victim: int) -> String:
	return _said(victim, "%s DOWN", "YOU ARE DOWN")


## What a seat is called in the band: ONE and TWO on one keyboard. A scene
## that knows which seat is the player's (the computer opponent's) says YOU.
func seat_name(slot: int) -> String:
	return DuelRules.slot_label(slot)


## `third` with the seat's name in it, or `second` when the seat is the player.
func _said(slot: int, third: String, second: String) -> String:
	var who := seat_name(slot)
	return second if who == "YOU" else third % who


func _on_initiative_changed(leader: int) -> void:
	if leader < 0:
		return
	hud.flash(_said(leader, "%s HAS THE INITIATIVE", "YOU HAVE THE INITIATIVE"),
		_said(leader, "%s LEADS", "YOU LEAD"))


func _on_fighter_respawned(_slot: int, _at: Vector2, _facing: int) -> void:
	camera.shake(1.0, 0.16)


func _on_leader_consumed(winner: int, _at: Vector2) -> void:
	camera.shake(2.2, 0.6)
	hud.flash(_said(winner, "%s REACHES THE GATE", "YOU REACH THE GATE"),
		_said(winner, "%s AT THE GATE", "YOU AT THE GATE"))


## The catch: a camera beat, the steel, and the word. No frozen frame. The
## adventure holds its actors still on a hit, but the duel's tick is the
## network's: a peer that held still for four frames would be four frames off
## its host, which docs/feel.md calls a correctness question rather than a taste
## one. So the beat is in the camera alone, a short hard shake, and the
## simulation never sees it. See docs/duel-combat.md.
func _on_blade_caught(_catcher: int, _thrower: int, _at: Vector2) -> void:
	camera.shake(1.6, 0.14)
	GameAudio.cue(&"catch", {"pitch": 1.15})
	hud.flash("CAUGHT")


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
