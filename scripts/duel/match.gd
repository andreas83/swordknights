class_name DuelMatch
extends DuelSim
## The tug-of-war: initiative, a strip of zones, respawns, and the two gates.
##
## This replaced the round state machine the duel started as, which has since
## been retired. A duel is no longer first-to-three on one screen; it is a
## rope. Kill the other fighter and
## the screen starts moving your way. Die and it stops, and then it starts
## moving theirs. Reach your own gate and the city takes you.
##
## `step(bits_a, bits_b)` keeps every promise the round duel made: one call is
## one frame, and that frame is a function of nothing but this object's state
## and those two bytes. See scripts/duel/match_sim.gd for the contract and
## docs/netplay.md for what it buys.
##
## WHAT IS SIMULATION AND WHAT IS NOT
## Initiative, the zone index, the scroll and both respawn timers are simulation
## state. They are in write_state(), they are in the checksum, and they are
## therefore the same on the host and on the client — which is the whole point:
## initiative derived independently on each peer is initiative that will
## eventually disagree, and the disagreement would be a match where one screen
## scrolls and the other does not.
##
## Gore and the camera are NOT. The decals are a presentation layer fed by
## signals (scripts/duel/gore.gd) and the camera reads the authoritative scroll
## rather than deciding anything (scripts/duel/match_camera.gd). One field
## hiding outside the snapshot is what produced the only desync this project has
## had; one presentation field hiding INSIDE it would be just as bad, because it
## would make the splatter pattern a thing two peers could diverge over.
##
## HOW THE SCENE IS TOLD, AND WHY NOT FROM INSIDE THE STEP
## Nothing in the step emits a signal. What happened goes into `events`, the
## step hands that to a MatchLedger, and the ledger says what the scene has not
## been told yet -- after every fresh step, and once at the end of a replay
## (DuelSim.end_replay). A frame NetSession steps again therefore rings nothing
## a second time, and a correction that changes what happened -- a predicted
## kill the host never had, or one it had that the client never predicted --
## is settled as the rule in scripts/duel/match_ledger.gd says: a new kill is
## told late, a kill that never happened has its blood taken back
## (`death_retracted`), and a kill the correction merely moved is moved without
## a second beat. The beats (`fighter_died` and the rest) ring once per real
## event; the record (`death_recorded`, `death_retracted`) follows the history.
##
## THE WINDOW, AND WHY IT IS NOT A ZONE INDEX THAT JUMPS
## The playable window is one zone wide and slides continuously. The leader drags
## it: it is positioned to hold them at its centre, and it may only ever move in
## the leader's goal direction — that one-way ratchet IS "the screen edge opens
## only in the leader's goal direction", and running the wrong way walks you into
## the trailing edge instead of scrolling the world. Because the window slides
## rather than snapping from zone to zone, crossing a boundary is not an event
## anywhere in this file, and there is nothing there to stutter. The zone index
## is still carried and still authoritative — it is what buckets the gore, what
## drives the streaming, and what the HUD counts — but it is a consequence of
## where the window is, not a thing the fight steps between.

signal initiative_changed(leader: int) ## -1 for neutral, otherwise a seat
signal zone_changed(index: int)
## The beat of a death: shake, word, sound. Once per death, when first known.
signal fighter_died(victim: int, killer: int, at: Vector2)
## The record of a death: where its blood goes. `frame` is the frame it happened
## on in the history as now known, which both peers agree on and seed the
## splatter from. `blow` is the way the killing blow travelled, +1 east and -1
## west, from where the killer stood; 0 for a hazard. A correction that moves a
## death retracts it and records it again; one that undoes it only retracts it.
signal death_recorded(victim: int, at: Vector2, frame: int, blow: int)
signal death_retracted(victim: int, frame: int)
signal fighter_respawned(slot: int, at: Vector2, facing: int)
signal leader_consumed(winner: int, at: Vector2)
signal match_over(winner: int)
## A thrown sword was caught out of the air. Presentation only: the catch itself
## happened in DuelCombat and is in both fighters' state already.
signal blade_caught(catcher: int, thrower: int, at: Vector2)
## A slab of crumbling stone fell: the sound and the dust. Presentation; the
## fall itself is in `stones`, and what the floor looks like is read from
## there, so a predicted fall the host never had is put back by the state and
## only this beat -- rung once, by the ledger, like every other -- was early.
signal stone_fell(index: int, at: Vector2)

enum Phase {
	COUNTDOWN, ## Both on their marks in the middle zone. Inputs ignored.
	FIGHTING, ## The only phase in which a fighter can die or the world scroll.
	CONSUMED, ## The leader reached their gate and is being taken through it.
	MATCH_OVER,
}

## The spec's LeaderState, kept to its names. NEUTRAL is not a transitional
## state: a match opens in it, and nothing scrolls until someone has killed.
enum Initiative {
	NEUTRAL = 0,
	PLAYER_1 = 1,
	PLAYER_2 = 2,
}

const DT := DuelRules.DT

## The respawn algorithm, from the specification.
const RESPAWN_DELAY := 2.0
## "Roughly 1.5 screen widths ahead in the leader's direction of travel." One
## zone is one screen, and the screen is the DESIGN screen — 480 px — not
## whatever the device happens to be showing. A phone and a desktop have to
## agree about where a fighter comes back.
const RESPAWN_LEAD := 1.5 * ZoneStrip.SCREEN_WIDTH

## Both fighters stand on their marks while this runs down.
const COUNTDOWN_TIME := DuelRules.COUNTDOWN_TIME
## Long enough to watch the crowd take the winner off the board.
const CONSUMED_TIME := 2.4
## How close to the gate's mouth the leader has to get.
const ENDPOINT_REACH := 20.0

## How far inside the window's edges a fighter is held. Half a body plus a
## little, so nobody is ever drawn half off the screen.
const WINDOW_WALL := 7.0
## Where in the window the leader is held. Centre: the leader always has half a
## screen of warning ahead of them and half a screen of rope behind.
const WINDOW_ANCHOR := 0.5

var strip: ZoneStrip

## --- simulation state: everything step() reads, and the whole snapshot -----

var phase: Phase = Phase.COUNTDOWN
var phase_time: float = 0.0
var initiative: Initiative = Initiative.NEUTRAL
## Which zone the window is in. Authoritative, carried, and checksummed; see the
## class docstring for why it is derived from the scroll rather than stepped.
var zone_index: int = 0
## The left edge of the playable window, in strip coordinates.
var scroll: float = 0.0
## Seconds until each fighter comes back. Zero when they are up.
var respawn := PackedFloat64Array([0.0, 0.0])
var kills := PackedInt32Array([0, 0])
var winner: int = DuelRules.DRAW
## One byte per slab of the strip's crumbling stone: whole, burning, or fallen
## for good (StripHazards). Simulation state like a respawn timer: it is the
## floor, and it is in the snapshot and the checksum. Empty on a strip with
## none. The blades and floods need no state here; they are the frame's.
var stones := PackedByteArray()

var seats: Array[DuelSeat] = []

## Asked by set_arena() to put this match on another strip, when the host of an
## online duel names one this peer has not loaded. Set by the scene, which owns
## everything drawn around the strip; `func(id: String) -> bool`.
var arena_switch := Callable()

## Set by the scene to the real fighter. Left null in a test, which builds the
## placeholder in scripts/duel/match_stub_fighter.gd instead.
var fighter_scene: PackedScene = null
var fighter_profiles: Array[Resource] = [null, null]

var _view: ZoneView
## The collision a physics-bodied fighter moves against. See _build_ground().
var _ground: TileMapLayer
var _fighter_bytes := 0
var _scratch := PackedByteArray()
var _built := false
## What the scene has been told, against what the history now holds. Not
## simulation: never in the snapshot, the checksum, or a step's decisions.
var _ledger := MatchLedger.new()
## Inside step(). Something that happens outside one -- a scripted kill, a
## test's -- waits in `_between` and is the next step's: that step is where its
## consequences (the respawn timer running down) begin, so that is the frame
## the state will say it happened on.
var _stepping := false
var _between: Array[Dictionary] = []
## What the fighters were last told about `replaying`.
var _fighters_replaying := false
## The crumbling stone's collision: one body per slab, on a layer of this
## match's own (`_stone_layer`), enabled while the slab holds. See _build_stones().
var _stone_bodies: Array[StaticBody2D] = []
var _stone_layer := 0
## What a fighter is handed as its world on a strip with crumbling stone.
var _world: MatchGround

## Which of STONE_LAYERS the next match with stones takes. Two matches share a
## physics space only in a test (a host and a client side by side), and eight
## layers is more than any test builds at once.
static var _next_stone_layer := 0
const STONE_LAYERS := 8
const FIRST_STONE_LAYER := 16


## --- construction ----------------------------------------------------------

## Builds the two fighters on the strip. `view` is optional: without one the
## match is pure simulation, which is how every test runs it.
func build(zones: ZoneStrip, view: ZoneView = null) -> bool:
	strip = zones
	_view = view
	_free_seats()
	_world = MatchGround.new(strip, self) if strip.hazards.stone_count() > 0 else null
	_stone_layer = 0
	if _world != null:
		_stone_layer = 1 << (FIRST_STONE_LAYER + _next_stone_layer % STONE_LAYERS)
		_next_stone_layer += 1

	for slot: int in 2:
		var fighter := _make_fighter()
		if fighter == null:
			push_error("the match has no fighter for seat %d" % slot)
			return false
		fighter.name = "Fighter%d" % slot
		add_child(fighter)

		var seat := DuelSeat.new()
		seat.bind(slot, fighter)
		if not seat.is_complete():
			push_error("seat %d's fighter does not answer the interface: %s"
				% [slot, seat.missing()])
			return false
		if not seat.give_world(strip, _world):
			push_error("seat %d's fighter refused the strip as its world" % slot)
			return false
		if not seat.collide_with(_stone_layer):
			push_error("seat %d's fighter would not stand on the crumbling stone" % slot)
			return false
		seat.setup(fighter_profiles[slot])
		seat.on_died(_on_fighter_died)
		seats.append(seat)

	_fighter_bytes = seats[0].state_bytes()
	# A fighter that hashes itself may lay its state out however it likes. One
	# that does not is read back as float64s by checksum(), so it must be a
	# whole number of them.
	var aligned := _fighter_bytes > 0 and _fighter_bytes % 8 == 0
	if _fighter_bytes <= 0 or (not seats[0].hashes_itself() and not aligned):
		push_error("a fighter's state is %d bytes; it must be a whole number of"
			% _fighter_bytes + " float64s, or the fighter must hash itself")
		return false
	_scratch.resize(2 * _fighter_bytes)
	if seats[0].node is PhysicsBody2D:
		_build_ground()
		_build_stones()
	_built = true

	reset_match()
	return true


## Every solid and one-way cell of the whole strip, as one hidden tilemap,
## built once and never streamed.
##
## The real fighter moves with move_and_collide(), so the ground it stands on
## is whatever the physics space holds. ZoneView streams its cells in and out
## around the camera, which is right for drawing and wrong for this: a fighter
## on a peer whose view had not reached a zone yet would fall through a floor
## that the other peer has, and the two would disagree about a frame. The rule
## this layer already keeps for its own queries -- the geometry the simulation
## reads is never streamed -- now holds for the physics space too. ZoneView's
## tilemap has collision switched off; it only draws.
##
## Five zones of 30 x 23 cells is at most 3,450 tiles of static collision,
## and far fewer in practice -- only solid and one-way cells -- built once per
## match. Hidden, because a TileMapLayer collides
## whether or not it draws.
func _build_ground() -> void:
	if _ground != null:
		_ground.queue_free()
	_ground = TileMapLayer.new()
	_ground.name = "Ground"
	_ground.tile_set = GROUND_TILES
	_ground.visible = false
	for y: int in strip.rows():
		for x: int in strip.cols():
			var kind := strip.kind_at(x, y)
			if kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM:
				_ground.set_cell(Vector2i(x, y), 0, strip.atlas_for(x, y))
	add_child(_ground)
	_ground.update_internals()


## One static body per slab of crumbling stone, on this match's own layer.
##
## Not cells of _ground: a TileMapLayer rebuilds a whole physics quadrant when
## one cell changes, and a rewind may have to put slabs back as well as take
## them away. A body per slab is switched by its collision layer, which the
## physics server reads on the very next query, so a slab that fell on frame N
## is gone for frame N + 1's move and back again the moment a snapshot from
## before it is read. Each match has a layer of its own (_stone_layer) and its
## fighters are given it as an extra mask bit, so the two matches of a
## networked test, built in one physics space, never stand on each other's
## stone. Nothing about a body is state: _apply_stones() derives every one of
## them from `stones`.
func _build_stones() -> void:
	for body: StaticBody2D in _stone_bodies:
		body.queue_free()
	_stone_bodies.clear()
	var tile := float(ZoneStrip.TILE)
	for cell: Vector2i in strip.hazards.stones:
		var body := StaticBody2D.new()
		body.name = "Stone_%d_%d" % [cell.x, cell.y]
		body.collision_layer = _stone_layer
		body.collision_mask = 0
		body.position = Vector2(cell) * tile + Vector2(tile, tile) * 0.5
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(tile, tile)
		shape.shape = rect
		body.add_child(shape)
		add_child(body)
		_stone_bodies.append(body)


## Every slab's body to what `stones` says: there while whole or burning, gone
## once fallen.
func _apply_stones() -> void:
	for i: int in mini(_stone_bodies.size(), stones.size()):
		var layer := _stone_layer if StripHazards.holds(stones[i]) else 0
		if _stone_bodies[i].collision_layer != layer:
			_stone_bodies[i].collision_layer = layer


## One frame of the crumbling stone, after the fighters have moved: lights the
## slabs under living feet, burns the lit ones, drops the spent ones.
func _advance_stones() -> void:
	if stones.is_empty():
		return
	var feet: Array[Vector3] = []
	for seat: DuelSeat in seats:
		var span := seat.feet()
		if span != Vector3.ZERO:
			feet.append(span)
	var dropped := strip.hazards.step_stones(stones, feet)
	if dropped.is_empty():
		return
	_apply_stones()
	var tile := float(ZoneStrip.TILE)
	for i: int in dropped:
		var cell: Vector2i = strip.hazards.stones[i]
		_happened({"kind": "stone", "index": i,
			"at": Vector2(cell) * tile + Vector2(tile * 0.5, 0.0)})


## Takes the fighters of a previous build out of the tree and the physics
## space at once: a match put on another strip builds two new ones.
func _free_seats() -> void:
	for seat: DuelSeat in seats:
		if seat.node != null and seat.node.get_parent() == self:
			remove_child(seat.node)
			seat.node.queue_free()
	seats.clear()


func _make_fighter() -> Node2D:
	if fighter_scene != null:
		return fighter_scene.instantiate() as Node2D
	return StubFighter.new()


## Back to the middle zone, nobody leading, both fighters on their marks.
func reset_match() -> void:
	frame = 0
	phase = Phase.COUNTDOWN
	phase_time = 0.0
	initiative = Initiative.NEUTRAL
	respawn = PackedFloat64Array([0.0, 0.0])
	kills = PackedInt32Array([0, 0])
	winner = DuelRules.DRAW
	stones = strip.hazards.fresh_stones()
	_apply_stones()
	events.clear()
	_between.clear()
	_ledger.clear()

	@warning_ignore("integer_division")
	var middle := strip.zone_count() / 2
	scroll = strip.zone_left(middle)
	zone_index = middle

	for slot: int in seats.size():
		# They start facing each other: seat 0 is on the left of the mark.
		seats[slot].respawn_at(strip.start_position(slot), 1 if slot == 0 else -1)

	_refresh_streaming()
	if not replaying:
		initiative_changed.emit(-1)
		zone_changed.emit(zone_index)


## --- the step --------------------------------------------------------------

## One frame. Pure in this object's state and the two input bytes, and must be
## called from inside a physics frame: a fighter is a body in the physics space.
func step(bits_a: int, bits_b: int) -> void:
	events.assign(_between)
	_between.clear()
	if not _built:
		return
	_stepping = true
	_pass_replaying_on()

	# Outside the fight the fighters stand still. Zeroing the input rather than
	# skipping the simulation keeps the step uniform — gravity still runs, a
	# corpse still falls — and stops a button held through the countdown from
	# firing the instant it ends.
	var live := phase == Phase.FIGHTING
	seats[0].apply_bits(bits_a if live else 0)
	seats[1].apply_bits(bits_b if live else 0)

	seats[0].simulate(DT)
	seats[1].simulate(DT)
	events.append_array(DuelSeat.referee(seats[0], seats[1], strip, frame))
	_advance_stones()

	if phase != Phase.MATCH_OVER:
		_advance_respawns()
		_advance_window()
		_hold_inside_window()

	if live:
		_check_endpoint()

	_advance_phase()
	_refresh_streaming()
	_ledger.record(frame, events)
	frame += 1
	_stepping = false
	if not replaying:
		_settle()


## --- telling the scene -----------------------------------------------------

## Something happened. Into `events`, which is the record of this frame; the
## ledger decides when the scene hears of it.
func _happened(event: Dictionary) -> void:
	if _stepping:
		events.append(event)
	else:
		_between.append(event)


func _replay_ended() -> void:
	_pass_replaying_on()
	_settle()


## The fighters ring their own small beats -- a disarm, a clash, a knockdown --
## and must hold them during a replay as the match does.
func _pass_replaying_on() -> void:
	if _fighters_replaying == replaying:
		return
	_fighters_replaying = replaying
	for seat: DuelSeat in seats:
		if not seat.set_replaying(replaying):
			push_error("seat %d's fighter would not take replaying = %s"
				% [seat.slot, replaying])


## Tells the scene what it has not heard, takes back what did not happen, and
## moves what moved. See MatchLedger for the rule.
func _settle() -> void:
	var change := _ledger.settle(frame, _evidence())
	for event: Dictionary in change["retracted"]:
		if event["kind"] == "died":
			death_retracted.emit(int(event["victim"]), int(event["frame"]))
	for pair: Array in change["revised"]:
		var was: Dictionary = pair[0]
		var now: Dictionary = pair[1]
		if now["kind"] == "died":
			death_retracted.emit(int(was["victim"]), int(was["frame"]))
			death_recorded.emit(int(now["victim"]), now["at"] as Vector2, int(now["frame"]),
				int(now.get("blow", 0)))
	for event: Dictionary in change["told"]:
		_tell(event)


## What the state says about recent deaths, for the ledger to hold the
## timeline to. A respawn timer is set on the frame a fighter falls and runs
## down by one frame's worth every step after, so it names that frame exactly,
## and it is in the snapshot, so both peers read the same frame off it. It
## covers the two seconds it runs for, less a frame each end for rounding, and
## not at all once the match is over, when the timers stop.
func _evidence() -> Dictionary:
	if phase == Phase.MATCH_OVER:
		return {}
	var down := []
	for slot: int in seats.size():
		if respawn[slot] <= 0.0:
			down.append({})
			continue
		var ago := roundi((RESPAWN_DELAY - respawn[slot]) / DT)
		down.append({"frame": frame - ago, "at": seats[slot].position()})
	return {"since": frame - roundi(RESPAWN_DELAY / DT) + 2, "seats": down}


func _tell(event: Dictionary) -> void:
	match String(event["kind"]):
		"died":
			var victim := int(event["victim"])
			var at: Vector2 = event["at"]
			death_recorded.emit(victim, at, int(event["frame"]), int(event.get("blow", 0)))
			fighter_died.emit(victim, int(event["killer"]), at)
		"respawned":
			fighter_respawned.emit(
				int(event["slot"]), event["at"] as Vector2, int(event["facing"]))
		"initiative":
			initiative_changed.emit(int(event["leader"]))
		"zone":
			zone_changed.emit(int(event["index"]))
		"catch":
			blade_caught.emit(int(event["by"]), int(event["from"]), event["at"] as Vector2)
		"stone":
			stone_fell.emit(int(event["index"]), event["at"] as Vector2)
		"consumed":
			leader_consumed.emit(int(event["winner"]), event["at"] as Vector2)
		"over":
			match_over.emit(int(event["winner"]))
		_:
			pass


## --- initiative ------------------------------------------------------------

## Which seat is leading, or -1 for neutral.
func leader_slot() -> int:
	match initiative:
		Initiative.PLAYER_1:
			return 0
		Initiative.PLAYER_2:
			return 1
		_:
			return -1


## The specification's canScrollToZone, kept to the letter: player one pushes
## west and player two pushes east, and nothing else moves the world.
func can_scroll(direction: int) -> bool:
	if initiative == Initiative.PLAYER_1 and direction == -1:
		return true
	if initiative == Initiative.PLAYER_2 and direction == 1:
		return true
	return false


## Which way the leader is pushing, or 0 for neutral.
func leader_direction() -> int:
	var leader := leader_slot()
	return 0 if leader < 0 else ZoneStrip.goal_direction(leader)


func _take_initiative(slot: int) -> void:
	var next := Initiative.PLAYER_1 if slot == 0 else Initiative.PLAYER_2
	if next == initiative:
		return
	initiative = next
	_happened({"kind": "initiative", "leader": slot})


## The killer takes initiative.
##
## `killer` is -1 for a hazard, which the specification does not cover. The
## survivor takes it: there is no other reading that keeps the rope moving, and
## walking the other fighter into the cistern is a way of winning the exchange
## whether or not a blade was involved.
func _on_fighter_died(victim: int, killer: int) -> void:
	if victim < 0 or victim > 1:
		return
	# Already down and waiting to come back. A fighter cannot die twice, and a
	# fighter that reported it twice must not score twice.
	if respawn[victim] > 0.0:
		return

	var credited := killer if killer == 0 or killer == 1 else 1 - victim
	if credited != victim:
		kills[credited] += 1
		_take_initiative(credited)

	respawn[victim] = RESPAWN_DELAY
	var at := seats[victim].position()
	# Which way the blood is thrown. Read off positions the step already has,
	# and written only into the event: no step reads it back.
	var blow := 0
	if killer == 0 or killer == 1:
		blow = signi(roundi(at.x - seats[killer].position().x))
	# The gore layer hears of this one, by way of the ledger, and only of this
	# one; and it is one-way: nothing it does comes back into the step.
	_happened({"kind": "died", "victim": victim, "killer": killer, "at": at, "blow": blow})


## --- respawn ---------------------------------------------------------------

func _advance_respawns() -> void:
	for slot: int in seats.size():
		if respawn[slot] <= 0.0:
			continue
		respawn[slot] -= DT
		if respawn[slot] > 0.0:
			continue
		respawn[slot] = 0.0
		var plan := respawn_plan(slot)
		var at: Vector2 = plan["position"]
		var facing: int = int(plan["facing"])
		seats[slot].respawn_at(at, facing)
		_happened({"kind": "respawned", "slot": slot, "at": at, "facing": facing})


## Where a fighter will come back, as a pure function of the current state.
##
## THE ALGORITHM, from the specification
##   3. computed from the LEADER's position, roughly 1.5 screen widths ahead in
##      the leader's direction of travel
##   4. facing the leader, to intercept them
##   5. edge case: if the leader is already at the edge of the final zone, the
##      opponent spawns directly in front of the exit
##
## Step 5 is not a separate branch here, it is the same clamp: the band of legal
## respawn columns stops five tiles short of each gate, so a target that would
## land behind the gate is pushed up against its mouth — which is what "directly
## in front of the exit" is. The leader then has to get past a fighter standing
## between them and the gate, which is the point of the rule.
##
## THE PACIFIST LINE
## A leader who killed and ran must be able to go over or under the respawn
## rather than being forced to fight it. That survives here because the chosen
## column is not simply the nearest one to the target but the nearest one with
## open ground: five columns of unbroken floor and eighty pixels of clear air.
## ZoneStrip.is_open_ground is the predicate and tests/match_respawn_test.gd
## walks the leader across the whole strip asserting it for every spawn the
## algorithm can produce.
##
## Callable at any time, including while the timer is still running, which is
## what gives the streaming two seconds of warning about a zone it is about to
## need. Returns { position, facing, column, pinned, ok }.
func respawn_plan(slot: int) -> Dictionary:
	var leader := leader_slot()
	if leader < 0 or leader == slot or not _built:
		# Nobody is leading, so there is no direction to be ahead in. Back to
		# the mark. Only reachable before the first kill.
		var mark := strip.start_position(slot)
		return {
			"ok": true, "position": mark, "facing": 1 if slot == 0 else -1,
			"column": strip.cell_of(mark).x, "pinned": false,
		}

	var direction := ZoneStrip.goal_direction(leader)
	var leader_x := seats[leader].position().x
	var wanted := leader_x + direction * RESPAWN_LEAD

	var band := strip.spawn_columns()
	var column := floori(wanted / ZoneStrip.TILE)
	var pinned := column < band.x or column > band.y

	var found := strip.find_open_ground(wanted, leader_x)
	var at: Vector2 = found["position"]
	return {
		"ok": bool(found["ok"]),
		"position": at,
		# Facing the leader, to intercept them.
		"facing": 1 if leader_x >= at.x else -1,
		"column": int(found["column"]),
		"pinned": pinned,
	}


## --- the window ------------------------------------------------------------

func max_scroll() -> float:
	return float(strip.zone_count() - 1) * strip.zone_width()


func window_rect() -> Rect2:
	return Rect2(scroll, 0.0, strip.zone_width(), strip.world_size().y)


## Drags the window after the leader, one way only.
func _advance_window() -> void:
	var leader := leader_slot()
	if leader < 0:
		return # neutral: the court is closed at both ends

	var direction := ZoneStrip.goal_direction(leader)
	if not can_scroll(direction):
		return

	var wanted := clampf(
		seats[leader].position().x - strip.zone_width() * WINDOW_ANCHOR,
		0.0, max_scroll()
	)
	# The ratchet. Everything about "running the wrong way does not scroll the
	# world" is these two lines: the window may close on the leader's goal and
	# may never back away from it.
	scroll = minf(scroll, wanted) if direction < 0 else maxf(scroll, wanted)

	var was := zone_index
	zone_index = strip.zone_of_x(scroll + strip.zone_width() * 0.5)
	if zone_index != was:
		_happened({"kind": "zone", "index": zone_index})


## Keeps the fight on the screen.
##
## The TRAILING edge is a wall: a fighter who falls behind is pushed along by it,
## which is the rope pulling. The LEADING edge is not, because a respawn is
## placed a screen and a half ahead and has to be allowed to stand there until
## the leader arrives. In neutral both edges hold, and the zone is a closed
## court.
func _hold_inside_window() -> void:
	var direction := leader_direction()
	var left := scroll + WINDOW_WALL
	var right := scroll + strip.zone_width() - WINDOW_WALL

	for slot: int in seats.size():
		if not seats[slot].is_alive():
			continue # a corpse may fall out of frame
		var at := seats[slot].position()
		var held := at.x
		if direction <= 0:
			held = minf(held, right)
		if direction >= 0:
			held = maxf(held, left)
		if held != at.x:
			seats[slot].set_position(_shoved_onto_ground(Vector2(held, at.y)))


## A fighter the trailing edge shoves sideways can be shoved into the side of a
## bench. Lifted onto it instead, a tile at a time, which reads as being pushed
## up a step rather than sunk into the stone.
##
## This and set_x are the only two places the match moves a fighter, and both
## would rather be a `push()` on the fighter itself — see the report.
func _shoved_onto_ground(at: Vector2) -> Vector2:
	var lifted := at
	for _step: int in 3:
		if not strip.rect_hits_solid(_body_at(lifted)):
			return lifted
		lifted.y = float(floori((lifted.y - 1.0) / ZoneStrip.TILE)) * ZoneStrip.TILE
	return lifted


## The match does not know how big a fighter is; the interface does not say. A
## tile-and-a-bit, which is every character in this project, and only ever used
## to decide whether a shove would bury one in rock.
const BODY := Vector2(9.0, 22.0)


func _body_at(feet: Vector2) -> Rect2:
	return Rect2(feet.x - BODY.x * 0.5, feet.y - BODY.y, BODY.x, BODY.y)


## --- the gate --------------------------------------------------------------

## "The leader reaching the final zone wins by being consumed at the endpoint."
func _check_endpoint() -> void:
	var leader := leader_slot()
	if leader < 0 or not seats[leader].is_alive():
		return
	var at := seats[leader].position()
	if absf(at.x - strip.goal_x(leader)) > ENDPOINT_REACH:
		return

	winner = leader
	_set_phase(Phase.CONSUMED)
	_happened({"kind": "consumed", "winner": leader, "at": at})


func _advance_phase() -> void:
	phase_time += DT
	match phase:
		Phase.COUNTDOWN:
			if phase_time >= COUNTDOWN_TIME:
				_set_phase(Phase.FIGHTING)
		Phase.CONSUMED:
			if phase_time >= CONSUMED_TIME:
				_set_phase(Phase.MATCH_OVER)
				_happened({"kind": "over", "winner": winner})
		_:
			pass


func _set_phase(next: Phase) -> void:
	phase = next
	phase_time = 0.0


## --- streaming -------------------------------------------------------------

## Tells the view which zones it needs. Presentation only — the simulation's own
## geometry comes from ZoneStrip and is never streamed.
##
## The interests are both fighters and, crucially, any respawn whose timer is
## still running: its zone is realised when the timer STARTS, so the one build
## that travel does not announce has the full two seconds of warning.
func _refresh_streaming() -> void:
	if _view == null:
		return
	_view.focus(scroll, streaming_interests())


func streaming_interests() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for slot: int in seats.size():
		out.append(seats[slot].position().x)
		if respawn[slot] > 0.0:
			out.append(float((respawn_plan(slot)["position"] as Vector2).x))
	return out


## --- the shared simulation surface -----------------------------------------

func arena_identity() -> int:
	return strip.identity()


## The strip's name, which the host's WELCOME carries (DuelStrips).
func arena_id() -> String:
	return strip.id


## Puts the match on strip `id` if it is not on it already, through the scene's
## `arena_switch`, which rebuilds what is drawn around it. False if this build
## has no such strip or nothing here can switch. The handshake then compares
## arena hashes as before, so a strip of the same name that differs is still
## refused.
func set_arena(id: String) -> bool:
	if strip != null and strip.id == id:
		return true
	if not DuelStrips.is_strip(id) or not arena_switch.is_valid():
		return false
	return bool(arena_switch.call(id)) and strip.id == id


func match_length() -> int:
	return strip.zone_count()


## A host playing a different number of zones is not a match this peer can
## join. The strip hash would catch it too; this says it in the lobby in a
## sentence a player can act on.
func set_match_length(length: int) -> bool:
	return length == strip.zone_count()


## --- snapshots and the checksum --------------------------------------------
##
## The header is the match: initiative, the zone index, the scroll, both respawn
## timers, the kills and the phase. Then both fighters' state blocks, written by
## the fighters themselves at their own offsets.
##
## Doubles for the four time-and-distance values, for the reason docs/netplay.md
## gives at length: they are GDScript floats compared against thresholds, and
## rounding a threshold comparison to 32 bits moves a transition by a whole
## frame. A respawn landing a frame early is a fighter appearing in a different
## place; a scroll a frame late is a gate reached or not reached.

const HEADER_BYTES := 44

const GROUND_TILES: TileSet = preload("res://assets/tiles.tres")


## The header, both fighters, then one byte per slab of crumbling stone -- after
## the fighters, so a strip without stones has exactly the snapshot it had.
func snapshot_bytes() -> int:
	return HEADER_BYTES + 2 * _fighter_bytes + stones.size()


func fighter_state_bytes() -> int:
	return _fighter_bytes


func write_state() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_u32(frame)
	buf.put_u8(int(phase))
	buf.put_u8(int(initiative))
	buf.put_u8(zone_index)
	buf.put_u8(strip.zone_count())
	buf.put_8(winner)
	buf.put_u8(mini(kills[0], 255))
	buf.put_u8(mini(kills[1], 255))
	buf.put_u8(0) # padding, keeps the float block 4-byte aligned
	buf.put_double(phase_time)
	buf.put_double(respawn[0])
	buf.put_double(respawn[1])
	buf.put_double(scroll)

	var out := buf.data_array
	out.resize(snapshot_bytes())
	seats[0].write_state(out, HEADER_BYTES)
	seats[1].write_state(out, HEADER_BYTES + _fighter_bytes)
	var at := HEADER_BYTES + 2 * _fighter_bytes
	for i: int in stones.size():
		out[at + i] = stones[i]
	return out


func read_state(bytes: PackedByteArray) -> bool:
	var want := snapshot_bytes()
	if bytes.size() < want:
		push_error("match snapshot too short: %d of %d" % [bytes.size(), want])
		return false
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = bytes

	frame = buf.get_u32()
	phase = buf.get_u8() as Phase
	initiative = buf.get_u8() as Initiative
	zone_index = buf.get_u8()
	var zones := buf.get_u8()
	winner = buf.get_8()
	kills[0] = buf.get_u8()
	kills[1] = buf.get_u8()
	buf.get_u8()
	phase_time = buf.get_double()
	respawn[0] = buf.get_double()
	respawn[1] = buf.get_double()
	scroll = buf.get_double()

	if zones != strip.zone_count():
		push_error("snapshot is for a %d-zone strip; ours has %d"
			% [zones, strip.zone_count()])
		return false

	seats[0].read_state(bytes, HEADER_BYTES)
	seats[1].read_state(bytes, HEADER_BYTES + _fighter_bytes)
	var at := HEADER_BYTES + 2 * _fighter_bytes
	stones = bytes.slice(at, at + stones.size())
	_apply_stones()
	# Presentation bookkeeping, not state: from here on the history has not
	# happened yet, and will be recorded again as it is stepped.
	_ledger.rewind(frame)
	return true


## A fingerprint of the whole match, for comparing two simulations.
##
## The fighters' blocks are read back as float64s and quantised to 1/256 before
## hashing, which is what the round duel does field by field: a float differing
## in its last bit is noise, and a checksum that fired on noise would be ignored
## within a minute of play. That is why a fighter's state has to be a whole
## number of doubles — DuelSeat.state_bytes says so and build() enforces it.
func checksum() -> int:
	var words := PackedInt32Array()
	words.append(frame)
	words.append(int(phase))
	words.append(int(initiative))
	words.append(zone_index)
	words.append(winner)
	words.append(kills[0])
	words.append(kills[1])
	words.append(quantise(phase_time))
	words.append(quantise(respawn[0]))
	words.append(quantise(respawn[1]))
	words.append(quantise(scroll))
	for i: int in stones.size():
		words.append(stones[i])

	if seats[0].hashes_itself():
		seats[0].checksum_into(words)
		seats[1].checksum_into(words)
		return fnv1a(words)

	seats[0].write_state(_scratch, 0)
	seats[1].write_state(_scratch, _fighter_bytes)
	var doubles := _scratch.size() / 8
	for i: int in doubles:
		words.append(quantise(_scratch.decode_double(i * 8)))
	return fnv1a(words)


## --- what the presentation layer asks --------------------------------------

func fighter_position(slot: int) -> Vector2:
	return seats[slot].position() if _built else Vector2.ZERO


func is_fighter_alive(slot: int) -> bool:
	return seats[slot].is_alive() if _built else false


func respawn_left(slot: int) -> float:
	return respawn[slot]


func zone_count() -> int:
	return strip.zone_count()
