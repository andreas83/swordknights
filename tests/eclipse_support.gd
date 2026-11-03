extends RefCounted
## Players for the Eclipse: a pilot that reads the fight and answers it, and a
## program that replays exactly what a pilot pressed.
##
## Not a test and not a `class_name`, for the reason tests/duel_support.gd
## gives; preload it:
##
##     const EclipseSupport := preload("res://tests/eclipse_support.gd")
##
## ## Why two players
##
## The clear run (tests/unit/test_eclipse_clear_run.gd) is a fixed input
## program in tools/trace_level.gd's format, `[frames, bits]` held for that
## many frames, replayed open-loop with no warps and no kills. A program
## cannot see the fight, so it proves the fight is the same fight it was
## recorded on, frame for frame: retune the King and it goes red, which is the
## point. It was recorded by the Pilot, which can see the fight -- the King's
## state, his bolts and his beam -- and answers each phase with its lesson,
## the way a player who has read the chapters would. The Pilot plays on under
## the LONGER WARNINGS assist, where every tell is longer and a program would
## be wrong on its first frame (tests/unit/test_eclipse_assist.gd).
##
##     godot --headless --path . --fixed-fps 60 --script tools/eclipse_pilot.gd
##
## re-records the program after a deliberate change to the fight.
##
## ## Frames are polls
##
## Both players count the prince's input polls, not physics frames: a hitstop
## or the complete screen holds the prince's physics, and with it his poll, so
## a program advances only on frames he acts on, whatever the scene around
## him is doing.

const LEVEL := "res://levels/chapter_06_eclipse.txt"

## The clear run: the steady pilot's whole fight, from the antechamber to dawn's
## door, as `[frames, bits]` held over the prince's polls -- a plunge a pass in
## phase 1, the first bolt of each volley parried and the rest crouched under,
## every pounce backstepped and cut, the beam parried. Recorded with
## `tools/eclipse_pilot.gd -- --steady`; re-record it after a deliberate change
## to the fight, never to make a failing run pass by accident.
const CLEAR_RUN: Array = [
	[71, 2], [1, 0], [52, 66], [260, 0], [11, 2], [1, 40], [3, 0], [5, 16], [23, 0], [13, 16],
	[13, 0], [13, 16], [21, 0], [9, 1], [20, 16], [4, 4], [18, 0], [4, 65], [898, 0], [11, 2],
	[1, 40], [3, 0], [5, 16], [23, 0], [13, 16], [13, 0], [13, 16], [21, 0], [9, 1], [20, 16],
	[4, 4], [18, 0], [4, 65], [898, 0], [11, 2], [1, 40], [3, 0], [5, 16], [23, 0], [13, 16],
	[13, 0], [13, 16], [13, 0], [7, 16], [238, 0], [1, 36], [4, 8], [29, 0], [1, 8], [162, 0],
	[1, 36], [3, 8], [183, 0], [1, 36], [2, 8], [304, 0], [1, 33], [29, 0], [9, 2], [1, 32],
	[1, 0], [1, 32], [1, 0], [1, 32], [23, 0], [1, 33], [197, 0], [1, 33], [29, 0], [9, 2],
	[1, 32], [1, 0], [1, 32], [1, 0], [1, 32], [324, 0], [1, 36], [310, 0], [252, 2]
]

const R := PlayerInput.BIT_RIGHT
const L := PlayerInput.BIT_LEFT
const U := PlayerInput.BIT_UP
const D := PlayerInput.BIT_DOWN
const J := PlayerInput.BIT_JUMP
const A := PlayerInput.BIT_ATTACK


## Replays `[frames, bits]` steps, one poll at a time; nothing once they run out.
class Program extends PlayerInput:
	var steps: Array = []
	var polls := 0
	var _step := 0
	var _left := 0
	var _bits := 0

	func _init(program: Array = []) -> void:
		steps = program

	func done() -> bool:
		return _step >= steps.size() and _left <= 0

	func poll() -> void:
		polls += 1
		while _left <= 0 and _step < steps.size():
			var step: Array = steps[_step]
			_step += 1
			_left = int(step[0])
			_bits = int(step[1])
		if _left > 0:
			_left -= 1
		else:
			_bits = 0
		apply_bits(_bits)


## Reads the fight every poll and presses what a player who has read the
## chapters would. Records every poll's bits, so a run can be kept as a
## Program (`program()`).
class Pilot extends PlayerInput:
	var game: Game
	var recorded := PackedInt32Array()
	## How the pilot plays phase 2: parry every bolt, or only the first of each
	## volley and crouch under the rest -- a steadier, slower player.
	var parry_every_bolt := false
	## How the pilot plays phase 1: chain the rebound into a second plunge, as
	## the expert line does, or one plunge a pass and back up the gallery.
	var chain_plunges := true
	## Logged beats: `{poll, what}`.
	var beats: Array[Dictionary] = []

	var _last := 0
	var _parried: Dictionary = {}
	var _phase := -1

	func _init(playing: Game = null) -> void:
		game = playing

	func poll() -> void:
		var bits := _decide() if game != null else 0
		# A swing is an edge: SWORD held from the last poll is let go first, so
		# every swing the pilot asks for is a fresh press. JUMP is held: how
		# long it is held is how high the jump goes.
		if bits & A and _last & A:
			bits &= ~A
		recorded.append(bits)
		_last = bits
		apply_bits(bits)

	## The run so far as `[frames, bits]` steps.
	func program() -> Array:
		var out: Array = []
		for bits: int in recorded:
			if not out.is_empty() and int(out[-1][1]) == bits:
				out[-1][0] = int(out[-1][0]) + 1
			else:
				out.append([1, bits])
		return out

	func king() -> Eclipse:
		var entities := game.get_node_or_null(^"Entities")
		if entities == null:
			return null
		for node: Node in entities.get_children():
			if node is Eclipse and not node.is_queued_for_deletion():
				return node as Eclipse
		return null

	func _decide() -> int:
		var prince := game.player
		var boss := king()
		if boss == null or not prince.is_alive():
			return 0
		if int(boss.phase) != _phase:
			_phase = int(boss.phase)
			beats.append({"poll": recorded.size(), "what": "phase %d" % _phase})
		if boss.state == Eclipse.State.FALL:
			return _to_the_door(prince, boss)
		if prince.position.y < boss.gallery_y - 2.0:
			return R # the antechamber: off its lip and down onto the gallery
		if boss.phase != Eclipse.Phase.SHIELD and prince.position.y < boss.floor_y - 2.0:
			return _down_to_the_floor(prince, boss)
		match boss.phase:
			Eclipse.Phase.SHIELD:
				return _shield(prince, boss)
			Eclipse.Phase.BURNING:
				return _burning(prince, boss)
			Eclipse.Phase.ECLIPSE:
				return _eclipse(prince, boss)
		return _finale(prince, boss)

	## Phase 1: from the west gallery, a walk off its lip into a plunge as he
	## pauses under it, and a second off the rebound; back up to wait for the
	## next pass.
	func _shield(prince: Player, boss: Eclipse) -> int:
		var on_gallery := absf(prince.position.y - boss.gallery_y) < 1.0
		var airborne := not prince.is_grounded()
		if prince.state == Player.State.HANG:
			return U
		if airborne and prince.position.y > boss.gallery_y + 8.0:
			# Climbing back up from the floor: the jump held to its top.
			return J if prince.state == Player.State.JUMP else 0
		var per_pass := Eclipse.PASS_WOUNDS if chain_plunges else 1
		if airborne:
			var chain := boss.pass_wounds < per_pass and not boss.crown_guard
			var over := absf(prince.position.x - boss.position.x) < 9.0
			if prince.state == Player.State.FALL or (prince.state == Player.State.JUMP and over):
				if chain and over and prince.position.y < boss.position.y - Eclipse.BODY.y:
					return D | A
			return 0
		if on_gallery:
			var edge := boss.west_lip - 6.0
			var paused := boss.state == Eclipse.State.PAUSE \
				and is_equal_approx(boss.position.x, boss.west_lip + Eclipse.PAUSE_INSET)
			if paused and boss.pass_wounds < per_pass and not boss.crown_guard:
				return R
			if prince.position.x < edge - 1.0:
				return R | PlayerInput.BIT_WALK
			if prince.position.x > edge + 1.0:
				return L | PlayerInput.BIT_WALK
			return 0
		# On the floor: back up the west gallery while he walks away from it.
		var under := boss.west_lip + Tuning.BODY_WIDTH * 0.5 + 1.0
		var leaving := boss.facing > 0 or boss.position.x > boss.west_lip + 60.0
		if not leaving:
			return _step_away(prince, boss)
		if prince.state == Player.State.HANG:
			return U
		if absf(prince.position.x - under) > 1.5:
			return (L if prince.position.x > under else R) | PlayerInput.BIT_WALK
		if prince.facing > 0:
			return L
		# A standing jump at the slab's end, held to the top: the grab takes
		# the corner on the way down.
		if prince.state == Player.State.JUMP or prince.is_grounded():
			return J
		return 0

	## From phase 2 on the fight is on the floor: off the gallery's lip,
	## toward the middle.
	func _down_to_the_floor(prince: Player, boss: Eclipse) -> int:
		if not prince.is_grounded():
			return 0
		return R if prince.position.x < boss.sun_x else L

	## Out of a shove's reach, toward the middle of the floor.
	func _step_away(prince: Player, boss: Eclipse) -> int:
		var gap := absf(prince.position.x - boss.position.x)
		if gap > 40.0:
			return 0
		return R if prince.position.x >= boss.position.x else L

	## Phase 2: face him at a distance and parry each bolt as it arrives.
	func _burning(prince: Player, boss: Eclipse) -> int:
		var face := _face(prince, boss)
		if face != 0:
			return face
		var shot := _nearest_shot(prince, EclipseBolt)
		if shot == null:
			return 0
		var gap := absf(shot.global_position.x - prince.position.x) - Tuning.BODY_WIDTH * 0.5 \
			- EclipseBolt.LENGTH * 0.5
		var first := not _parried.has(boss.volley)
		if gap <= 12.0 and prince.state != Player.State.PARRY:
			if parry_every_bolt or first:
				_parried[boss.volley] = true
				return U | A
			return D
		if gap <= 30.0 and not (parry_every_bolt or first):
			return D
		return 0

	## Phase 3: let him come, backstep as he leaves the ground, then step in
	## and cut while he skids.
	func _eclipse(prince: Player, boss: Eclipse) -> int:
		var away := L if boss.position.x > prince.position.x else R
		if boss.state == Eclipse.State.LEAP:
			# The first poll of the leap: the crouch has ended and the place he
			# will come down is fixed.
			if boss.state_time < 0.5 / 60.0:
				return away | A
			return 0
		if boss.state == Eclipse.State.CROUCH:
			return 0
		if boss.state == Eclipse.State.SKID and prince.state != Player.State.BACKSTEP:
			var gap := absf(boss.position.x - prince.position.x) - Eclipse.BODY.x * 0.5 \
				- Tuning.BODY_WIDTH * 0.5
			if gap > Tuning.ATTACK_REACH - 3.0:
				return R if boss.position.x > prince.position.x else L
			return A
		var face := _face(prince, boss)
		return face

	## The finale: face him, and parry the beam as its head arrives.
	func _finale(prince: Player, boss: Eclipse) -> int:
		var face := _face(prince, boss)
		if face != 0:
			return face
		var beam := boss.beam()
		if beam == null or beam.reflected:
			return 0
		var gap := absf(beam.global_position.x - prince.position.x) - Tuning.BODY_WIDTH * 0.5
		if gap <= 12.0 and prince.state != Player.State.PARRY:
			return U | A
		return 0

	func _to_the_door(prince: Player, boss: Eclipse) -> int:
		if boss.is_in_group(ExitDoor.HELD_SHUT):
			return 0
		return R if prince.position.x < boss.east_x + 4.0 else 0

	## A tap toward the King when the prince is turned away; 0 when he faces him.
	func _face(prince: Player, boss: Eclipse) -> int:
		var toward := 1 if boss.position.x > prince.position.x else -1
		if prince.facing == toward or not prince.is_grounded():
			return 0
		if prince.state != Player.State.IDLE and prince.state != Player.State.WALK:
			return 0
		return R if toward > 0 else L

	func _nearest_shot(prince: Player, kind: Script) -> FoeProjectile:
		var best: FoeProjectile = null
		var best_gap := INF
		for node: Node in game.get_node(^"Entities").get_children():
			var shot := node as FoeProjectile
			if shot == null or shot.get_script() != kind or shot.reflected or shot.is_spent():
				continue
			# Still to come, or still passing: a bolt is not by until its tail
			# has cleared the far side of the body.
			var ahead := (prince.position.x - shot.global_position.x) * signf(shot.velocity.x)
			var gap := absf(shot.global_position.x - prince.position.x)
			if ahead > -Tuning.BODY_WIDTH - shot.size.x and gap < best_gap:
				best = shot
				best_gap = gap
		return best
