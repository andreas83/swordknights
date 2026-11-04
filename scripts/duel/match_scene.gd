extends Node2D
## The tug-of-war, playable: two seats on one keyboard, five zones, two gates.
##
## Build the world, read two bytes of input, step. Everything that is the mode
## — initiative, the window, respawns, the gates — is in scripts/duel/match.gd,
## because the networked version (scripts/duel/match_online.gd, which extends
## this) has to get exactly the same rules out of exactly the same code. What is
## here is wiring and reactions. The duel page's ONE KEYBOARD is this scene.
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
##
## `--demo-cpu` instead hands both seats to the computer (DuelCpu, MEDIUM, seed
## `--seed=N` or 1), so a strip can be looked at with a real fight on it: the
## beat, the tide and the falling stone are worth nothing in a picture with
## nobody standing in them. With `--strip=<id>` it is how docs/duel-strips.png
## is made (docs/duel-match.md, "The strips").

## Where quitting a match goes: the duel page, as quitting a chapter goes to
## the chapter select. The title screen is one SWORD further back.
const MENU_SCENE := "res://scenes/duel_select.tscn"
const FIGHTER_SCENE: PackedScene = preload("res://scenes/fighter.tscn")
## The persistent hint while the match is played, and once it is over.
const PLAY_FOOTER := "PAUSE FOR THE MENU"
const OVER_FOOTER := "JUMP FOR A REMATCH  ·  SWORD TO LEAVE"

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
var wardrobe_path := UserData.at(Wardrobe.PATH)
## Where the duel page's choices are read from: the strip here, and the
## computer's level in match_cpu.gd. A seam for a test, likewise.
var choice_path := UserData.at(DuelChoice.PATH)
## The blades, the water and the crumbling stone, drawn (HazardView).
var hazards: HazardView

## Test seam: what leaving the match does instead of changing to the duel
## page, which would take the test runner's scene with it.
var leave := Callable()
## The menu PAUSE opens (scripts/ui/pause_menu.gd). Null in the attract demo,
## which is nobody's to pause.
var menu: PauseMenu

var _gates: Array[GateArt] = []
var _dusk: MatchDusk
var _demo_frame := 0
var _held_over := false
## Both seats' computers, for `--demo-cpu`; empty otherwise.
var _demo_cpus: Array[DuelCpu] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	demo = args.has("--demo") or args.has("--demo-cpu")

	# Over the zone's stone and under the actors and the foreground plane:
	# after ZoneView in the tree at its z, so blood lies ON the floor and the
	# walls. It was once at -1, beneath the stone, where every stain in front
	# of a backdrop was drawn and hidden. See tests/unit/test_duel_blood.gd.
	gore.z_index = 0
	# The hazards over the blood and under the fighters, as the floor's own
	# furniture; the water alone is drawn over the fighters (HazardView).
	hazards = HazardView.new()
	hazards.name = "Hazards"
	$World.add_child(hazards)
	$World.move_child(hazards, gore.get_index() + 1)

	fight.fighter_scene = FIGHTER_SCENE
	fight.arena_switch = use_strip
	camera.framing_width = _framing_argument()
	sky.camera = camera

	if not use_strip(chosen_strip()):
		return
	if args.has("--demo-cpu"):
		var seed_value := 1
		for arg: String in args:
			if arg.begins_with("--seed="):
				seed_value = arg.trim_prefix("--seed=").to_int()
		for slot: int in 2:
			var cpu := DuelCpu.new(slot, DuelBrain.Difficulty.MEDIUM, seed_value + slot)
			cpu.watch(fight)
			_demo_cpus.append(cpu)

	hud.fight = fight
	hud.footer = PLAY_FOOTER if not demo else strip.name.to_upper()
	if not demo:
		menu = PauseMenu.install(self)
		menu.chosen.connect(_on_menu_chosen)

	fight.fighter_died.connect(_on_fighter_died)
	fight.death_recorded.connect(_on_death_recorded)
	fight.death_retracted.connect(_on_death_retracted)
	fight.initiative_changed.connect(_on_initiative_changed)
	fight.fighter_respawned.connect(_on_fighter_respawned)
	fight.leader_consumed.connect(_on_leader_consumed)
	fight.match_over.connect(_on_match_over)
	fight.blade_caught.connect(_on_blade_caught)
	fight.stone_fell.connect(_on_stone_fell)


## Which strip this match is fought on: `--strip=<id>` in the user arguments,
## or the duel page's saved choice, with RANDOM drawn here, once. The attract
## demo is the Tug of War unless told otherwise, so its screenshots never
## depend on what someone last chose.
func chosen_strip() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--strip="):
			var named := arg.trim_prefix("--strip=")
			if DuelStrips.is_choice(named):
				return DuelStrips.resolve(named, Time.get_ticks_usec())
			push_warning("there is no duel strip called '%s'" % named)
	if demo:
		return DuelStrips.TUG
	return DuelStrips.resolve(DuelChoice.open(choice_path).strip, Time.get_ticks_usec())


## Builds the match, and everything drawn around it, on strip `id`: the zones,
## the blood, the hazards, the fighters, the gates, the light. Called once from
## _ready(), and again by DuelMatch.set_arena() when the host of an online duel
## names another strip in its WELCOME. False, with an error, if it would not
## build; the match is then left on the strip it had.
func use_strip(id: String) -> bool:
	var next := DuelStrips.open(id)
	if next == null:
		push_error("no duel strip '%s'" % id)
		return false
	strip = next
	zones.setup(strip)
	gore.setup(strip)
	gore.clear()
	if not fight.build(strip, zones):
		push_error("the match would not build on %s" % id)
		return false
	hazards.setup(strip, fight, zones.zone_materials)
	_start_in_zone_argument()
	dress_fighters()
	camera.setup(fight)
	_light_the_last_rooms()
	sky.seed_value = hash(strip.name)
	_build_gates()
	return true


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


## The strip's hour, and dusk over the gate zone at each end. See MatchDusk.
func _light_the_last_rooms() -> void:
	for seat: DuelSeat in fight.seats:
		var art := seat.node.get_node_or_null("FighterArt")
		if art != null:
			art.add_to_group(MatchDusk.LIT)
	if _dusk == null:
		_dusk = MatchDusk.new()
		_dusk.name = "Dusk"
		add_child(_dusk)
	_dusk.setup(camera, strip, sky)


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
	for old: GateArt in _gates:
		old.queue_free()
	_gates.clear()
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


func _physics_process(delta: float) -> void:
	if not _demo_cpus.is_empty():
		var pair := Vector2i(_demo_cpus[0].next_bits(), _demo_cpus[1].next_bits())
		fight.step(pair.x, pair.y)
		for cpu: DuelCpu in _demo_cpus:
			cpu.watch(fight)
		_follow_the_match()
		return
	if demo:
		_demo_frame += 1
		var bits := _demo_input()
		fight.step(bits.x, bits.y)
		_follow_the_match()
		return

	_label_thumbs()
	if Input.is_action_just_pressed("pause"):
		if fight.phase == DuelMatch.Phase.MATCH_OVER:
			_to_menu()
			return
		if menu.is_open():
			menu.close()
			GameAudio.cue("pause_out")
		else:
			menu.title = "PAUSED"
			menu.scrim = 0.74
			menu.open(menu_rows())
			GameAudio.cue("pause_in")
		_label_thumbs()
		return

	if menu.is_open():
		# On one device the match stops while the menu is up: nobody else is
		# waiting on this frame.
		menu.step(delta)
		return

	if fight.phase == DuelMatch.Phase.MATCH_OVER:
		hud.footer = OVER_FOOTER
		if Input.is_action_just_pressed("jump"):
			_rematch()
		elif Input.is_action_just_pressed("attack"):
			_to_menu()
		return

	# The JUMP or SWORD that chose RESUME is still down: stepped now, the
	# fighter would read it as a press and jump or swing with it.
	if _held_over:
		if _menu_press_held():
			return
		_held_over = false

	_step()
	_follow_the_match()


## --- the menu ---------------------------------------------------------------
##
## RESUME, RESTART MATCH, LEAVE MATCH. A duel has no torch and nothing to keep,
## so starting again is the whole match -- the rematch the result screen
## offers, from wherever the rope stood -- and leaving goes to the duel page,
## as the result screen's SWORD does. Online the list is shorter and the game
## does not stop (match_online.gd).

func menu_rows() -> Array[Dictionary]:
	return [
		{"id": &"resume", "title": "RESUME", "enabled": true},
		{"id": &"rematch", "title": "RESTART MATCH", "enabled": true},
		{"id": &"leave", "title": "LEAVE MATCH", "enabled": true},
	]


func _on_menu_chosen(id: StringName) -> void:
	menu.close()
	_held_over = true
	match id:
		&"resume":
			GameAudio.cue("pause_out")
		&"rematch":
			_rematch()
		&"leave":
			_to_menu()
	_label_thumbs()


func _menu_press_held() -> bool:
	for action: String in ["jump", "attack", "jump_p1", "attack_p1", "jump_p2", "attack_p2"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


## What the thumb buttons say now, and whether the duel's THROW is up: only
## in play, as TouchControls hides its own (TouchControls.is_play()).
func _label_thumbs() -> void:
	var controls := TouchControls.of(self)
	if controls == null:
		return
	if menu != null and menu.is_open():
		controls.set_labels("SELECT", "BACK")
	elif fight.phase == DuelMatch.Phase.MATCH_OVER:
		controls.set_labels(over_jump_label(), "QUIT")
	else:
		controls.play_labels()
	var throw := get_node_or_null(^"ThrowLayer/ThrowButton") as DuelTouchGuard
	if throw != null:
		throw.suppressed = not controls.is_play()


## JUMP's word once the match is over: a rematch, which REMATCH is too wide
## for JUMP's ring to hold. The online match, which has none, says nothing.
func over_jump_label() -> String:
	return "REMATCH|AGAIN"


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
	gore.tick(fight.frame)
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
	hud.footer = PLAY_FOOTER


func _to_menu() -> void:
	if leave.is_valid():
		leave.call()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


## --- reactions --------------------------------------------------------------
##
## Each of these is rung once per thing that happened, by the match's ledger,
## and never by a frame NetSession steps again -- see DuelMatch and
## docs/netplay.md, "Corrected outcomes". So nothing here has to guard itself
## against an echo. The one reaction that is a record rather than a beat, the
## blood, has its own pair of signals, because a correction can take it back.

func _on_fighter_died(victim: int, _killer: int, at: Vector2) -> void:
	camera.kill_beat(at)
	camera.shake(3.6, 0.42)
	hud.flash(_down(victim))


## The blood, and it stays for the match -- unless the host
## says the death did not happen, or happened elsewhere.
func _on_death_recorded(victim: int, at: Vector2, frame: int, blow: int) -> void:
	gore.spill(at, victim, frame, blow)


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


## A slab of the Aqueduct's deck gave way: a short shake and the stone's
## voice, once, from the ledger. What the floor looks like is the state's.
func _on_stone_fell(_index: int, at: Vector2) -> void:
	if camera.get_screen_center_position().distance_to(at) < strip.zone_width():
		camera.shake(1.2, 0.18)
		GameAudio.cue(&"masonry", {"pitch": 0.8, "volume_db": -6.0})


func _on_match_over(_winner: int) -> void:
	hud.footer = OVER_FOOTER


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
