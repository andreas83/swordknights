extends GutTest
## The owner's rigged model stands on the 2D rig and nowhere else
## (scripts/player/rigged_costume.gd), proved twice: on a stand-in built in
## code in the shape a Mixamo `.glb` imports in (tests/rigged_support.gd),
## which holds the pipeline for any model and can be a file that is there or
## not; and, at the end, on the owner's princess herself
## (assets/characters/princess.glb, a Tripo export with clips of its own).
##
## The claim is test_model_figure.gd's, for bones instead of primitives: a
## textured, skinned body can be drawn without becoming a second source of
## truth for where a hand or a foot is. So each joint's bone is projected back
## through the model's own camera and must land on the rig point it was posed
## from, facing either way, in poses that reach, fold and raise the arms
## overhead. Seen to fail with the hand set a fifth of a unit off its point.
##
## A bone's origin is placed on its point whatever the bone's turn, so that
## alone cannot see a limb aimed wrong. The mesh is checked too: the points
## the model was built with are skinned through the bones and must land on
## the joints below them, each limb on its own side of the body. Seen to fail
## with the hinge's angle negated, with the skin's stretch taken out, and with
## the near side always the model's right (its shoulder then hangs from the
## wrong side of its chest whenever it faces left).
##
## And the rest of what the costume promises: every state draws with no engine
## error and inside the figure's envelope; the file's own animation is gone;
## the bones keep their size while the skin stretches; changing clothes takes
## the viewport away; a hit burns the model pale (seen to fail with the
## overlay left clear); a seat's team colour reaches the cloth and nothing
## else (seen to fail with the tint left off); and the PRINCESS figure wears
## the rigged model exactly when its file is there.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const FIGHTER_SCENE := preload("res://scenes/fighter.tscn")
const RiggedSupport := preload("res://tests/rigged_support.gd")
## How far a projected bone may sit from its rig point, in art units: well
## under a pixel at play size.
const TOLERANCE := 0.05
## test_figure_poses.gd's box around the feet: a bone outside it has come
## loose from the rig.
const ENVELOPE := Rect2(-30.0, -34.0, 60.0, 40.0)

var _store := UserData.at("user://test_rigged_figure.scn")
var _stand_in: PackedScene


func before_all() -> void:
	_stand_in = RiggedSupport.build()


func after_each() -> void:
	if FileAccess.file_exists(_store):
		DirAccess.remove_absolute(_store)


func _rigged() -> RiggedCostume:
	var costume := RiggedCostume.new()
	costume.scene = _stand_in
	costume.blade = PrincessCostume.BLADE
	return costume


func _dressed_player() -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.position = Vector2(160.0, 120.0)
	var art := _art(player)
	CharacterLook.from_ids({"figure": "princess"}).dress(art)
	art.costume = _rigged()
	return player


func _art(node: Node2D) -> PlayerArt:
	var art := node.get_node_or_null(^"PlayerArt") as PlayerArt
	return art if art != null else node.get_node(^"FighterArt") as PlayerArt


func _model(node: Node2D) -> RiggedCostume:
	return _art(node).costume as RiggedCostume


## Where a joint's bone lands, in the art's own space.
func _on_screen(model: RiggedCostume, id: String) -> Vector2:
	var pixel := model.camera().unproject_position(model.joint(id))
	var size := Vector2(model.viewport().size)
	return ModelCostume.BOX.position + pixel / size * ModelCostume.BOX.size


func test_the_stand_in_is_posed_by_the_rig() -> void:
	var player := _dressed_player()
	await wait_process_frames(2)
	var model := _model(player)
	assert_not_null(model.skeleton(), "the stand-in's skeleton was found and mapped")
	if model.skeleton() == null:
		return
	assert_not_null(model.clips(), "the stand-in's AnimationPlayer is kept, as clips")
	assert_eq(model.clips().ids(), [], "with none in it, so every state is the rig's")
	assert_eq(model.clips().player().callback_mode_process,
		AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "and it never runs on its own")
	assert_gt(model.cloth_materials().size(), 0, "the tunic is recognised as cloth")


func test_every_joint_lands_on_its_rig_point_facing_either_way() -> void:
	var player := _dressed_player()
	var checked := 0
	for state: Player.State in [Player.State.ATTACK, Player.State.FALL, Player.State.CROUCH,
			Player.State.HANG]:
		player.state = state
		player.state_time = 0.1
		for facing: int in [1, -1]:
			player.facing = facing
			_art(player).queue_redraw()
			await wait_process_frames(2)
			checked += _check_joints(player, "%s facing %d" % [Player.State.keys()[state], facing])
	assert_eq(checked, 4 * 2 * 9, "every joint of every pose, both ways")


func _check_joints(player: Player, what: String) -> int:
	var art := _art(player)
	var model := _model(player)
	var ankle := Vector2(0.0, -model.ankle_height())
	var pairs := {
		"hand_front": art._hand_front, "hand_back": art._hand_back,
		"knee_front": art._knee_front, "knee_back": art._knee_back,
		"elbow_front": art._elbow(art._hand_front), "elbow_back": art._elbow(art._hand_back),
		"ankle_front": art._foot_front + ankle, "shoulder_front": art._shoulder,
		"hip_back": art._hip,
	}
	var checked := 0
	for id: String in pairs:
		var landed := _on_screen(model, id)
		var want: Vector2 = pairs[id]
		assert_lt(landed.distance_to(want), TOLERANCE,
			"%s: %s at %s, rig at %s" % [what, id, landed, want])
		checked += 1
	return checked


## The near side is the model's right facing right and its left facing left:
## it turns round rather than being mirrored, so its face, not the back of its
## head, is toward the camera both ways.
func test_the_model_turns_to_face_the_way_it_runs() -> void:
	var player := _dressed_player()
	for facing: int in [1, -1]:
		player.facing = facing
		_art(player).queue_redraw()
		await wait_process_frames(2)
		var sk := _model(player).skeleton()
		var bone := sk.find_bone("mixamorig_Head")
		# The stand-in faces +Z at rest; carry that by the head's turn from
		# its rest, and out of the skeleton into the viewport's space.
		var turn := sk.get_bone_global_pose(bone).basis * sk.get_bone_global_rest(bone).basis.inverse()
		var rest_face := RiggedSupport.ARMATURE.basis.inverse() * Vector3.BACK
		var face := (sk.global_transform.basis * (turn * rest_face)).normalized()
		assert_gt(face.x * facing, 0.3, "facing %d: the face looks the way it runs" % facing)
		assert_gt(face.z, 0.0, "facing %d: and turns toward the camera, not away" % facing)


func test_every_player_state_draws() -> void:
	var player := _dressed_player()
	var art := _art(player)
	var checked := 0
	for state: int in Player.State.values():
		player.state = state as Player.State
		player.state_time = 0.12
		player.velocity = Vector2(60.0, 80.0)
		var before := art.costume.frames_drawn
		art.queue_redraw()
		await wait_process_frames(2)
		var what := String(Player.State.keys()[state])
		assert_gt(art.costume.frames_drawn, before, "%s was drawn" % what)
		assert_true(art.costume.drawn.has_area(), "%s placed its bones" % what)
		assert_true(ENVELOPE.encloses(art.costume.drawn),
			"%s stays on its rig: %s" % [what, art.costume.drawn])
		checked += 1
	assert_eq(checked, Player.State.size(), "every state")


## Where the mesh goes, not only where the bones are. A bone's origin is set on
## its rig point whatever its turn, so the joint test above cannot see a limb
## aimed wrong or a model whose near side is the wrong one. This skins the
## points the model was built with -- each wrist, elbow, knee, ankle and
## shoulder, wholly on the bone above it -- and requires each to land on the
## bone below, and each limb to hang from its own side of the body. Seen to
## fail with the hinge's angle negated, with the skin's stretch taken out, and
## with the near side always the model's right.
func test_the_skin_spans_every_limb_from_its_own_side() -> void:
	var player := _dressed_player()
	var checked := 0
	for state: Player.State in [Player.State.ATTACK, Player.State.RUN, Player.State.FALL,
			Player.State.CROUCH]:
		player.state = state
		player.state_time = 0.1
		for facing: int in [1, -1]:
			player.facing = facing
			_art(player).queue_redraw()
			await wait_process_frames(2)
			checked += _check_skin(_model(player), "%s facing %d" % [
				Player.State.keys()[state], facing])
	assert_eq(checked, 4 * 2 * 2 * 6, "every limb of every pose, both ways")


func _check_skin(model: RiggedCostume, what: String) -> int:
	var sk := model.skeleton()
	var to_view := sk.global_transform
	var body := model.viewport().find_children("*", "MeshInstance3D", true, false)[0]
	var skin := (body as MeshInstance3D).skin
	var checked := 0
	for side: String in ["Left", "Right"]:
		for pair: Array in [["Shoulder", "Arm"], ["Arm", "ForeArm"], ["ForeArm", "Hand"],
				["UpLeg", "Leg"], ["Leg", "Foot"]]:
			var upper := sk.find_bone("mixamorig_" + side + String(pair[0]))
			var lower := sk.find_bone("mixamorig_" + side + String(pair[1]))
			# The lower joint in the skin's own space, read through a bind that
			# never stretches: the head's.
			var head := sk.find_bone("mixamorig_Head")
			var mesh_space := (sk.get_bone_global_rest(head) * _bind(skin, sk.get_bone_name(head)))
			var joint := mesh_space.affine_inverse() * sk.get_bone_global_rest(lower).origin
			var bind := _bind(skin, sk.get_bone_name(upper))
			var skinned := to_view * (sk.get_bone_global_pose(upper) * bind * joint)
			var bone := to_view * sk.get_bone_global_pose(lower).origin
			assert_lt(skinned.distance_to(bone), TOLERANCE, "%s: %s%s's skin reaches %s at %s" % [
				what, side, pair[0], pair[1], bone])
			checked += 1
		# The body's own left, carried from rest by the hips' turn.
		var hips := sk.find_bone("mixamorig_Hips")
		var turn := sk.get_bone_global_pose(hips).basis * sk.get_bone_global_rest(hips).basis.inverse()
		var rest_left := (sk.get_bone_global_rest(sk.find_bone("mixamorig_LeftUpLeg")).origin
			- sk.get_bone_global_rest(sk.find_bone("mixamorig_RightUpLeg")).origin)
		var left := (to_view.basis * (turn * rest_left)).normalized()
		var sign := 1.0 if side == "Left" else -1.0
		for limb: String in ["Arm", "UpLeg"]:
			var root := to_view * sk.get_bone_global_pose(sk.find_bone("mixamorig_" + side + limb)).origin
			var centre := to_view * sk.get_bone_global_pose(hips).origin
			assert_gt((root - centre).dot(left) * sign, 0.0,
				"%s: %s%s hangs from the body's %s side" % [what, side, limb, side.to_lower()])
		checked += 1
	return checked


func _bind(skin: Skin, bone: String) -> Transform3D:
	for i: int in skin.get_bind_count():
		if skin.get_bind_name(i) == bone:
			return skin.get_bind_pose(i)
	fail_test("no bind for %s" % bone)
	return Transform3D.IDENTITY


## A limb the rig draws longer than the model's is spanned by stretching its
## skin, and the bone itself keeps its size: a scaled bone would swell the
## limb's width with its length.
func test_the_skin_stretches_and_the_bones_do_not() -> void:
	var player := _dressed_player()
	player.state = Player.State.ATTACK
	player.state_time = 0.1
	await wait_process_frames(2)
	var sk := _model(player).skeleton()
	for bone: int in sk.get_bone_count():
		var size := sk.get_bone_global_pose(bone).basis.get_scale()
		var rest := sk.get_bone_global_rest(bone).basis.get_scale()
		assert_almost_eq(size, rest, Vector3.ONE * 0.001,
			"%s keeps its size" % sk.get_bone_name(bone))
	for side: String in ["Left", "Right"]:
		var forearm := sk.find_bone("mixamorig_%sForeArm" % side)
		var hand := sk.find_bone("mixamorig_%sHand" % side)
		var reach := (sk.get_bone_global_pose(hand).origin
			- sk.get_bone_global_pose(forearm).origin).length()
		var modelled := (sk.get_bone_global_rest(hand).origin
			- sk.get_bone_global_rest(forearm).origin).length()
		assert_gt(absf(reach / modelled - 1.0), 0.1,
			"%s: the rig's forearm is not the model's, so the skin had to stretch" % side)


func test_changing_figure_takes_the_viewport_away() -> void:
	var player := _dressed_player()
	await wait_process_frames(2)
	var view := _model(player).viewport()
	assert_not_null(view, "the model built its viewport")
	CharacterLook.new().dress(_art(player))
	await wait_process_frames(2)
	assert_false(is_instance_valid(view), "the prince does not keep the model's viewport")


func test_a_hit_burns_the_model_pale() -> void:
	var player := _dressed_player()
	await wait_process_frames(2)
	var art := _art(player)
	var model := _model(player)
	assert_eq(model.flash(), 0.0, "unhurt, the overlay is clear")
	art._on_hurt(2)
	art.queue_redraw()
	await wait_process_frames(1)
	assert_gt(model.flash(), 0.5, "a hit burns the model pale")
	var meshes := model.viewport().find_children("*", "MeshInstance3D", true, false)
	for node: Node in meshes:
		assert_not_null((node as MeshInstance3D).material_overlay, "%s takes the flash" % node.name)


func test_the_seat_colour_reaches_the_cloth_and_nothing_else() -> void:
	for seat: int in 2:
		var art := await _seated(seat, _rigged())
		var model := art.costume as RiggedCostume
		assert_eq(model.cloth_materials().size(), 1, "seat %d: the tunic is the cloth" % seat)
		for material: ShaderMaterial in model.cloth_materials():
			assert_eq(material.get_shader_parameter("tint"), FighterArt.SEAT_CLOTH[seat],
				"seat %d: the tunic is dyed the team colour" % seat)
			assert_eq(material.get_shader_parameter("amount"), 1.0, "seat %d: fully" % seat)
			assert_not_null(material.get_shader_parameter("albedo_texture"),
				"seat %d: over its own texture" % seat)
		for node: Node in model.viewport().find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			for i: int in mesh.mesh.get_surface_count():
				var name := mesh.mesh.surface_get_material(i).resource_name
				if name == RiggedSupport.CLOTH:
					continue
				assert_null(mesh.get_surface_override_material(i),
					"seat %d: %s keeps its own material" % [seat, name])


## A fighter in `seat`, dressed as the princess and then in `costume`.
func _seated(seat: int, costume: RiggedCostume) -> PlayerArt:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	add_child_autofree(fighter)
	fighter.setup(seat, null)
	var art := FighterArt.dress(fighter, seat, CharacterLook.from_ids({"figure": "princess"}))
	art.costume = costume
	fighter.respawn_at(Vector2(160.0, 120.0), 1 - seat * 2)
	fighter.set_physics_process(false)
	art.queue_redraw()
	await wait_process_frames(2)
	return art


## --- the owner's princess ---------------------------------------------------------
##
## The same claims on the file itself (assets/characters/princess.glb, a Tripo
## export with Mixamo bones, a T-pose rest and clips of its own), and what the
## clips add: each state with a clip draws it, sampled on the simulation's
## clock; the clip is turned the way the body faces, pinned over the rig's hip
## and kept out of the floor; and the sword leaves the hand the clip moved.
## Nothing here reads her colours: the export is grey until the owner sends
## the textured one, and the pipeline must not care.

const CLIP_STATES := {
	Player.State.IDLE: "idle", Player.State.WALK: "walk", Player.State.RUN: "run",
	Player.State.CROUCH: "crouch", Player.State.JUMP: "jump", Player.State.FALL: "fall",
	Player.State.CLIMB_UP: "climb_up", Player.State.ATTACK: "attack",
	Player.State.HURT: "hurt", Player.State.DEAD: "death",
}


func _princess() -> RiggedCostume:
	assert_true(RiggedCostume.available(), "the owner's princess is in the project")
	var costume := RiggedCostume.new()
	costume.blade = PrincessCostume.BLADE
	return costume


func _princess_player() -> Player:
	var player := _dressed_player()
	_art(player).costume = _princess()
	return player


## A state at a time, walking pace forward and rising: what a clip reads.
func _pose(player: Player, state: Player.State, time: float, facing: int,
		velocity: Vector2 = Vector2(Tuning.WALK_SPEED, -Tuning.JUMP_SPEED * 0.5)) -> void:
	player.state = state
	player.state_time = time
	player.facing = facing
	player.velocity = velocity
	_art(player).queue_redraw()
	await wait_process_frames(2)


func test_the_owner_s_princess_lands_on_the_rig_where_she_has_no_clip() -> void:
	var player := _princess_player()
	var checked := 0
	for state: Player.State in [Player.State.TURN, Player.State.LAND, Player.State.HANG,
			Player.State.PARRY]:
		for facing: int in [1, -1]:
			await _pose(player, state, 0.1, facing)
			var what := "princess %s facing %d" % [Player.State.keys()[state], facing]
			assert_eq(_model(player).clip(), [], "%s: no clip, the rig" % what)
			checked += _check_joints(player, what)
			checked += _check_skin(_model(player), what)
	assert_eq(checked, 4 * 2 * (9 + 12), "every joint and limb of every pose, both ways")


func test_the_owner_s_princess_has_her_clips() -> void:
	var player := _princess_player()
	await _pose(player, Player.State.IDLE, 0.0, 1)
	var model := _model(player)
	assert_not_null(model.skeleton(), "her Mixamo bones are all found")
	var ids := model.clips().ids()
	ids.sort()
	var wanted := ["attack", "climb_up", "crouch", "death", "fall", "hurt", "idle", "jump",
		"run", "walk"]
	assert_eq(ids, wanted, "her ten prompted clips are found; land, hang and ladder she lacks")


func test_her_clips_play_where_the_body_is_facing_either_way() -> void:
	var player := _princess_player()
	var checked := 0
	for state: Player.State in CLIP_STATES:
		for facing: int in [1, -1]:
			await _pose(player, state, 0.11, facing)
			checked += _check_clip(player, state, facing)
	assert_eq(checked, CLIP_STATES.size() * 2, "every clip, both ways")


## One clip-drawn frame: the right clip, its hips over the rig's hip, its
## face the body's way, its feet out of the floor when the body is on it, and
## the sword in the hand the clip put somewhere.
func _check_clip(player: Player, state: Player.State, facing: int) -> int:
	var what := "%s facing %d" % [Player.State.keys()[state], facing]
	var art := _art(player)
	var model := _model(player)
	var sk := model.skeleton()
	assert_eq(model.clip()[0] if not model.clip().is_empty() else "", CLIP_STATES[state],
		"%s draws its clip" % what)
	var hips := sk.find_bone("mixamorig_Hips")
	var at := sk.global_transform * sk.get_bone_global_pose(hips).origin
	var landed := _project(model, at)
	assert_almost_eq(landed.x, art._hip.x, TOLERANCE, "%s: the hips stand over the rig's" % what)
	var forward := _facing(sk)
	assert_gt(forward.x * facing, 0.5, "%s: she faces the way the body does" % what)
	if art._grounded():
		for foot: String in ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]:
			var toe := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(foot)).origin
			assert_gt(toe.y, -0.3, "%s: %s is not under the floor" % [what, foot])
	var hand := sk.find_bone("mixamorig_RightHand")
	var held := _project(model, sk.global_transform * sk.get_bone_global_pose(hand).origin)
	assert_lt(model.sword_hand(art).distance_to(held), TOLERANCE,
		"%s: the sword hand reported is her right hand's bone" % what)
	return 1


## Where a point of the model's viewport lands in the art's space.
func _project(model: RiggedCostume, at: Vector3) -> Vector2:
	var pixel := model.camera().unproject_position(at)
	return ModelCostume.BOX.position + pixel / Vector2(model.viewport().size) * ModelCostume.BOX.size


## The way the model is turned to face, in the viewport's space: its rest
## forward (left cross up, from the bones) carried by the skeleton's
## transform -- the whole model's turn, whatever the clip does with the body
## (a death lies her on her back).
func _facing(sk: Skeleton3D) -> Vector3:
	var rest := func(bone: String) -> Vector3:
		return sk.get_bone_global_rest(sk.find_bone(bone)).origin
	var up: Vector3 = rest.call("mixamorig_Neck") - rest.call("mixamorig_Hips")
	var left: Vector3 = rest.call("mixamorig_LeftArm") - rest.call("mixamorig_RightArm")
	return (sk.global_transform.basis * left.cross(up)).normalized()


## The adventure's sword starts at the hand the clip moved, a hilt's length
## out, and on the rig's frames at the rig's hand.
func test_the_sword_leaves_the_hand_the_clip_moved() -> void:
	var player := _princess_player()
	var art := _art(player)
	await _pose(player, Player.State.IDLE, 0.3, 1)
	var held := _model(player).sword_hand(art)
	assert_false(is_nan(held.x), "a clip reports its sword hand")
	assert_gt(held.distance_to(art._hand_front), 0.5, "and it is not the rig's hand")
	var reach := float(art._posture()["blade_len"]) + 1.2
	assert_almost_eq(art.blade_tip.distance_to(held), reach, 0.01,
		"the blade runs from that hand")
	await _pose(player, Player.State.TURN, 0.05, 1)
	assert_true(is_nan(_model(player).sword_hand(art).x), "the rig's frames report none")
	reach = float(art._posture()["blade_len"]) + 1.2
	assert_almost_eq(art.blade_tip.distance_to(art._hand_front), reach, 0.01,
		"and the blade runs from the rig's hand")


## A clip is sampled at the state's own time, the same frame however it was
## reached: looping on the loop's length, a strike stretched over the
## strike's game duration.
func test_her_clips_follow_the_simulation_clock() -> void:
	var player := _princess_player()
	var model: RiggedCostume
	var poses := []
	for step: Array in [[Player.State.IDLE, 0.4], [Player.State.RUN, 0.7],
			[Player.State.IDLE, 0.4]]:
		await _pose(player, step[0], step[1], 1)
		model = _model(player)
		var frame := []
		for bone: int in model.skeleton().get_bone_count():
			frame.append(model.skeleton().get_bone_global_pose(bone))
		poses.append(frame)
	assert_eq(poses[2], poses[0], "the same moment draws the same frame")


## Tripo's clips are a second or longer; the game's moves are not. A clip is
## fitted to the game's own durations, read from Tuning (ModelClips).
func test_her_clips_are_timed_by_the_game() -> void:
	var player := _princess_player()
	await _pose(player, Player.State.IDLE, 0.0, 1)
	var clips := _model(player).clips()
	var idle := clips.window("idle")
	await _pose(player, Player.State.IDLE, idle.y + 0.25, 1)
	assert_almost_eq(_clip_time(player), 0.25, 0.0001, "an idle loops on its own length")
	var stab := clips.window("attack")
	assert_lt(stab.y - stab.x, 2.0, "only the useful second of her five-second stab")
	for share: float in [0.0, 0.5, 1.0]:
		await _pose(player, Player.State.ATTACK, Tuning.ATTACK_TIME * share, 1)
		assert_almost_eq(_clip_time(player), lerpf(stab.x, stab.y, share), 0.0001,
			"the stab is stretched over ATTACK_TIME: %.1f of it" % share)
	var climb := clips.window("climb_up")
	await _pose(player, Player.State.CLIMB_UP, Tuning.CLIMB_UP_TIME * 0.5, 1)
	assert_almost_eq(_clip_time(player), lerpf(climb.x, climb.y, 0.5), 0.0001,
		"the climb over CLIMB_UP_TIME")
	var hurt := clips.window("hurt")
	await _pose(player, Player.State.HURT, Tuning.HURT_TIME, 1)
	assert_almost_eq(_clip_time(player), hurt.y, 0.0001, "the stagger over HURT_TIME")
	var jump := clips.window("jump")
	await _pose(player, Player.State.JUMP, 0.05, 1, Vector2(0.0, -Tuning.JUMP_SPEED * 0.25))
	assert_almost_eq(_clip_time(player), lerpf(jump.x, jump.y, 0.75), 0.0001,
		"a jump three-quarters spent is three-quarters through its clip")
	await _pose(player, Player.State.JUMP, 0.5, 1, Vector2(0.0, 40.0))
	assert_eq(_model(player).clip()[0], "fall", "and past the top it falls")
	var walk := clips.window("walk")
	var slow := []
	for speed: float in [Tuning.WALK_SPEED * 0.5, Tuning.WALK_SPEED]:
		await _pose(player, Player.State.WALK, 0.2, 1, Vector2(speed, 0.0))
		slow.append(_clip_time(player) - walk.x)
	assert_almost_eq(float(slow[1]), float(slow[0]) * 2.0, 0.0001,
		"a walk's stride is paced by the body's speed")


func _clip_time(player: Player) -> float:
	var clip := _model(player).clip()
	return float(clip[1]) if not clip.is_empty() else NAN


## The duel draws her death from its clip and every other state from the
## rig, whose hand is on the blade rect; and with no cloth in a grey export
## a seat still wears its colour, on her edge.
func test_the_duel_keeps_her_on_the_rig_but_for_her_death() -> void:
	for seat: int in 2:
		var art := await _seated(seat, _princess())
		var model := art.costume as RiggedCostume
		assert_eq(model.clip(), [], "seat %d standing: the rig" % seat)
		if model.cloth_materials().is_empty():
			assert_eq(model.edge_colour(), art._c(FighterArt.SEAT_CLOTH[seat]),
				"seat %d: no cloth, so the edge is the team's" % seat)
		else:
			for material: ShaderMaterial in model.cloth_materials():
				assert_eq(material.get_shader_parameter("tint"), FighterArt.SEAT_CLOTH[seat],
					"seat %d: the cloth is the team's" % seat)
		var fighter := art.get_parent() as Fighter
		fighter.state = Fighter.State.DEAD
		fighter.state_frame = 30
		art.queue_redraw()
		await wait_process_frames(2)
		assert_eq(model.clip()[0] if not model.clip().is_empty() else "", "death",
			"seat %d dead: her death" % seat)


func test_clip_names_match_a_prompt_or_a_clean_id() -> void:
	assert_eq(ModelClips.PLAYER["ATTACK"][1], Tuning.ATTACK_TIME,
		"the table reads the game's durations from Tuning")
	var tripo := ModelClips.match_names(PackedStringArray([
		"Relaxed heroic stance_ sword lowered in right hand_ gentle brea",
		"Falling_ legs slightly apart_ free arm reaching upward as if to", "fall",
		"mit dem schwert zustechen_", "springen",
	]))
	assert_eq(tripo, {
		"idle": "Relaxed heroic stance_ sword lowered in right hand_ gentle brea",
		"fall": "Falling_ legs slightly apart_ free arm reaching upward as if to",
		"attack": "mit dem schwert zustechen_",
	}, "Tripo's prompt names, the prompt before a clean name")
	var clean := ModelClips.match_names(PackedStringArray([
		"idle", "Run", "library/walk", "fall", "death", "running_fast",
	]))
	assert_eq(clean, {"idle": "idle", "run": "Run", "walk": "library/walk", "fall": "fall",
		"death": "death"}, "clean ids, in any case and any library")


func test_the_princess_wears_the_model_exactly_when_its_file_is_there() -> void:
	var locks := CharacterLook.HAIRS[0]
	var face := CharacterLook.SKINS[0]
	assert_eq(ResourceSaver.save(_stand_in, _store), OK, "the stand-in is saved as a file")
	var worn := CharacterLook.princess(locks, face, _store)
	assert_true(worn is RiggedCostume, "with the file there, she is the rigged model")
	assert_eq(worn.blade_colours(), PrincessCostume.BLADE, "with her own sword")
	var missing := CharacterLook.princess(locks, face, _store + ".missing.scn")
	assert_true(missing is PrincessCostume, "without it, the primitives")
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	CharacterLook.from_ids({"figure": "princess"}).dress(_art(player))
	var expected: GDScript = RiggedCostume if RiggedCostume.available() else PrincessCostume
	assert_eq(_art(player).costume.get_script(), expected,
		"the wardrobe's princess follows res://assets/characters/princess.glb")
	# And the saved file is worn as a scene, as the .glb will be.
	var loaded := RiggedCostume.new(_store)
	_art(player).costume = loaded
	_art(player).queue_redraw()
	await wait_process_frames(2)
	assert_not_null(loaded.skeleton(), "a costume loads its model from the path it is given")


func test_bone_names_from_every_rigger_find_their_role() -> void:
	var names := {
		"mixamorig:Hips": "hips", "mixamorig_LeftArm": "arm_left",
		"mixamorig1:RightForeArm": "forearm_right", "LeftUpperArm": "arm_left",
		"RightLowerArm": "forearm_right", "LeftUpLeg": "thigh_left",
		"LeftUpperLeg": "thigh_left", "RightLowerLeg": "shin_right", "mixamorig_LeftLeg":
		"shin_left", "RightFoot": "foot_right", "Neck": "neck", "Head": "head",
		"LeftShoulder": "clavicle_left", "Left_Hand": "hand_left", "Spine1": "",
		"HeadTop_End": "", "LeftHandIndex1": "", "LeftToeBase": "",
	}
	for bone: String in names:
		assert_eq(RiggedCostume.role_of(bone), names[bone], bone)
