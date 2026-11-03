class_name DuelMatch
extends DuelSim
## The tug-of-war: initiative, a strip of zones, respawns, and the two gates.
##
## This replaces the round state machine in scripts/duel/duel.gd. A duel is no
## longer first-to-three on one screen; it is a rope. Kill the other fighter and
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
signal fighter_died(victim: int, killer: int, at: Vector2)
signal fighter_respawned(slot: int, at: Vector2, facing: int)
signal leader_consumed(winner: int, at: Vector2)
signal match_over(winner: int)

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

var seats: Array[DuelSeat] = []

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


## --- construction ----------------------------------------------------------

## Builds the two fighters on the strip. `view` is optional: without one the
## match is pure simulation, which is how every test runs it.
func build(zones: ZoneStrip, view: ZoneView = null) -> bool:
	strip = zones
	_view = view
	seats.clear()

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
		if not seat.give_world(strip):
			push_error("seat %d's fighter refused the strip as its world" % slot)
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
	events.clear()

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
	events.clear()
	if not _built:
		return

	# Outside the fight the fighters stand still. Zeroing the input rather than
	# skipping the simulation keeps the step uniform — gravity still runs, a
	# corpse still falls — and stops a button held through the countdown from
	# firing the instant it ends.
	var live := phase == Phase.FIGHTING
	seats[0].apply_bits(bits_a if live else 0)
	seats[1].apply_bits(bits_b if live else 0)

	seats[0].simulate(DT)
	seats[1].simulate(DT)
	events.append_array(DuelSeat.referee(seats[0], seats[1], strip))

	if phase != Phase.MATCH_OVER:
		_advance_respawns()
		_advance_window()
		_hold_inside_window()

	if live:
		_check_endpoint()

	_advance_phase()
	_refresh_streaming()
	frame += 1


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
	if not replaying:
		initiative_changed.emit(slot)


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
	events.append({
		"kind": "died", "victim": victim, "killer": killer, "at": at,
	})
	if not replaying:
		# The gore layer listens to this one. It is the only thing it listens
		# to, and it is one-way: nothing it does comes back into the step.
		fighter_died.emit(victim, killer, at)


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
		events.append({"kind": "respawned", "slot": slot, "at": at})
		if not replaying:
			fighter_respawned.emit(slot, at, facing)


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
		events.append({"kind": "zone", "index": zone_index})
		if not replaying:
			zone_changed.emit(zone_index)


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
	events.append({"kind": "consumed", "winner": leader, "at": at})
	if not replaying:
		leader_consumed.emit(leader, at)


func _advance_phase() -> void:
	phase_time += DT
	match phase:
		Phase.COUNTDOWN:
			if phase_time >= COUNTDOWN_TIME:
				_set_phase(Phase.FIGHTING)
		Phase.CONSUMED:
			if phase_time >= CONSUMED_TIME:
				_set_phase(Phase.MATCH_OVER)
				events.append({"kind": "over", "winner": winner})
				if not replaying:
					match_over.emit(winner)
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


func snapshot_bytes() -> int:
	return HEADER_BYTES + 2 * _fighter_bytes


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
