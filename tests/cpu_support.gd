extends RefCounted
## Headless bouts against the computer opponent: a match on the real fighter,
## stepped to its end or a frame limit, with each seat driven by a DuelCpu or
## by a scripted callable, and an account of what happened.
##
## A support library, like tests/duel_support.gd, and deliberately named to
## match neither test convention: it asserts nothing and is preloaded by the
## suites that do (tests/unit/test_duel_cpu_bouts.gd and its neighbours).
##
## The two rules tests/duel_support.gd gives hold here too: the match is in the
## tree, and bout() must be called from inside a physics frame, because the
## fighters are bodies and move_and_collide() queries the physics space.

const Support := preload("res://tests/duel_support.gd")

## One frame of a scripted seat: `func(fight: DuelMatch) -> int`. It reads the
## live match, which is fine for a test's dumb opponent and is exactly what the
## computer opponent is not allowed to do.


## Plays one match. `drivers` holds, per seat, a DuelCpu or a Callable as above.
## Returns { winner, over, frames, kills, deaths, hazards, checksums, bits }:
## `deaths` and `hazards` count each seat's deaths, and those of them that were
## the ground's (spikes, water, falling out); `bits` is every frame's pair of
## inputs, and `checksums` every frame's checksum when `trace` is set.
static func bout(root: Node, strip: ZoneStrip, drivers: Array, limit: int,
		trace: bool = false) -> Dictionary:
	var fight := Support.spawn_match(root, strip)
	if fight == null:
		return {}
	var deaths := PackedInt32Array([0, 0])
	var hazards := PackedInt32Array([0, 0])
	var tally := func(victim: int, killer: int, _at: Vector2) -> void:
		deaths[victim] += 1
		if killer < 0:
			hazards[victim] += 1
	fight.fighter_died.connect(tally)
	_watch(drivers, fight)

	var checksums := PackedInt64Array()
	var bits: Array[Vector2i] = []
	var frames := 0
	while frames < limit and fight.phase != DuelMatch.Phase.MATCH_OVER:
		var pair := Vector2i(_ask(drivers[0], fight), _ask(drivers[1], fight))
		fight.step(pair.x, pair.y)
		_watch(drivers, fight)
		frames += 1
		if trace:
			checksums.append(fight.checksum())
			bits.append(pair)

	var out := {
		"winner": fight.winner,
		"over": fight.phase == DuelMatch.Phase.MATCH_OVER,
		"frames": frames,
		"kills": PackedInt32Array([fight.kills[0], fight.kills[1]]),
		"deaths": deaths,
		"hazards": hazards,
		"checksums": checksums,
		"bits": bits,
	}
	fight.free()
	return out


static func _ask(driver: Variant, fight: DuelMatch) -> int:
	if driver is DuelCpu:
		return (driver as DuelCpu).next_bits()
	return int((driver as Callable).call(fight))


static func _watch(drivers: Array, fight: DuelMatch) -> void:
	for driver: Variant in drivers:
		if driver is DuelCpu:
			(driver as DuelCpu).watch(fight)


## The closing bot of tests/match_net_test.gd -- noise on every button but the
## direction, which closes on the other fighter -- with one addition: holding
## the initiative, it runs for its gate and leaves every button but the stance
## alone while it does, taking the moat and the pit with DuelFeet, the computer
## opponent's own legs. Without that it could never win a match -- it threw
## itself into the moat at every run -- and a test that an easy opponent can
## lose would have nothing to lose to. It fights no better for it: the legs
## only know the ground. The chance is a hash of the frame, the seat and the
## seed, so the same seed is the same bot.
static func closing_bot(seat: int, seed_value: int) -> Callable:
	var chance := PlayerInput.BIT_UP | PlayerInput.BIT_DOWN | PlayerInput.BIT_JUMP \
		| PlayerInput.BIT_ATTACK | PlayerInput.BIT_THROW
	var held := PackedInt32Array([0])
	return func(fight: DuelMatch) -> int:
		var me := fight.fighter_position(seat)
		var them := fight.fighter_position(1 - seat)
		var bits := hash(Vector3i(fight.frame, seat, seed_value)) & chance
		if fight.frame % 7 != 0:
			bits &= ~PlayerInput.BIT_THROW
		if fight.leader_slot() == seat:
			var stance := bits & (PlayerInput.BIT_UP | PlayerInput.BIT_DOWN)
			return _run(fight, seat, held) | (stance if held[0] == 0 else 0)
		held[0] = 0
		if absf(them.x - me.x) > 6.0:
			bits |= PlayerInput.BIT_RIGHT if them.x > me.x else PlayerInput.BIT_LEFT
		return bits


## The way home, with a jump at whatever DuelFeet says needs one. `held` is the
## frames of jump still to hold, kept between calls.
static func _run(fight: DuelMatch, seat: int, held: PackedInt32Array) -> int:
	var fighter := fight.seats[seat].node as Fighter
	var body := DuelView.Body.of(fighter)
	var way := DuelFeet.steer(fight.strip, fighter.tuning, body,
		ZoneStrip.goal_direction(seat), held[0])
	var bits := 0
	if bool(way["jump"]) and held[0] == 0 and body.grounded:
		held[0] = int(way["hold"])
	if held[0] > 0:
		bits |= PlayerInput.BIT_JUMP
		held[0] -= 1
	match int(way["dir"]):
		-1:
			bits |= PlayerInput.BIT_LEFT
		1:
			bits |= PlayerInput.BIT_RIGHT
	return bits


## A human who knows the controls and nothing else: a seeded stream of input
## held for a few frames at a time, leaning on closing the distance -- the
## stream tests/duel_support.gd makes for the determinism suites, for seat 0.
static func scripted_human(length: int, seed_value: int) -> Callable:
	var stream := Support.input_stream(length, seed_value)
	return func(fight: DuelMatch) -> int:
		return stream[mini(fight.frame, stream.size() - 1)].x
