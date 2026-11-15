extends GutTest
## The 3D figure stands on the 2D rig and nowhere else (scripts/player/model_costume.gd,
## scripts/player/princess_costume.gd).
##
## Its whole claim is that a 3D body can be drawn without becoming a second
## source of truth for where a hand or a foot is. So this projects the model's
## joints back through its own camera and requires each to land on the 2D rig
## point it was lifted from, facing either way -- the camera is turned, and a
## pre-shear that was wrong by its sign would put the sword hand a pixel or two
## off the hilt on one facing only. Seen to fail with the shear's sign flipped.
##
## And the three ways a viewport-per-figure goes wrong in silence: two models
## sharing one world (each renders the other), a costume change leaving the old
## viewport rendering behind the new figure, and a hit flash that burns the
## flat figures white but not the model.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
## How far a projected joint may sit from its rig point, in art units: well
## under a pixel at play size.
const TOLERANCE := 0.05


func _dressed_player(figure: String = "princess") -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.position = Vector2(160.0, 120.0)
	var look := CharacterLook.new()
	look.take_ids({"figure": figure})
	var art := player.get_node(^"PlayerArt") as PlayerArt
	look.dress(art)
	if figure == "princess":
		# The primitives, whether or not the owner's rigged model is in the
		# project: they are what this file pins (test_rigged_figure.gd pins
		# the model), and dropping the .glb in must not turn it red.
		var locks := look.option("hair")
		art.costume = PrincessCostume.new(locks["lit"], locks["shade"],
			look.option("skin")["lit"])
	return player


func _art(player: Player) -> PlayerArt:
	return player.get_node(^"PlayerArt") as PlayerArt


func _model(player: Player) -> ModelCostume:
	return _art(player).costume as ModelCostume


## Where a model part's centre lands, in the art's own space.
func _on_screen(model: ModelCostume, id: String) -> Vector2:
	var at := model.part(id).global_position
	var pixel := model.camera().unproject_position(at)
	var size := Vector2(model.viewport().size)
	return ModelCostume.BOX.position + pixel / size * ModelCostume.BOX.size


func test_the_model_has_a_world_of_its_own() -> void:
	var one := _dressed_player()
	var two := _dressed_player()
	await wait_process_frames(2)
	var a := _model(one).viewport()
	var b := _model(two).viewport()
	assert_not_null(a, "the first model built its viewport on its first frame")
	assert_not_null(b, "and so did the second")
	if a == null or b == null:
		return
	assert_true(a.own_world_3d and b.own_world_3d, "each renders only itself")
	assert_ne(a.find_world_3d(), b.find_world_3d(), "in two different worlds")


func test_every_joint_lands_on_its_rig_point_facing_either_way() -> void:
	var player := _dressed_player()
	player.state = Player.State.ATTACK
	player.state_time = 0.1
	for facing: int in [1, -1]:
		player.facing = facing
		await wait_process_frames(2)
		var art := _art(player)
		var model := _model(player)
		var pairs := {
			"hand_front": art._hand_front, "hand_back": art._hand_back,
			"knee_front": art._knee_front, "knee_back": art._knee_back,
			"elbow_front": art._elbow(art._hand_front),
		}
		for id: String in pairs:
			var landed := _on_screen(model, id)
			var want: Vector2 = pairs[id]
			assert_lt(landed.distance_to(want), TOLERANCE,
				"facing %d: %s at %s, rig at %s" % [facing, id, landed, want])


func test_changing_figure_takes_the_viewport_away() -> void:
	var player := _dressed_player()
	await wait_process_frames(2)
	var view := _model(player).viewport()
	assert_not_null(view, "the model built its viewport")
	CharacterLook.new().dress(_art(player))
	await wait_process_frames(2)
	assert_false(is_instance_valid(view), "the prince does not keep the model's viewport")
	assert_eq(_art(player).texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE,
		"and the art's filter is given back")


func test_a_hit_burns_the_model_white() -> void:
	var player := _dressed_player()
	await wait_process_frames(2)
	var art := _art(player)
	var calm := _model(player).material_colour("cloth")
	assert_eq(calm, art.cloth, "the tunic wears the art's cloth")
	art._on_hurt(2)
	art.queue_redraw()
	await wait_process_frames(1)
	var burnt := _model(player).material_colour("cloth")
	assert_gt(burnt.get_luminance(), calm.get_luminance() + 0.2, "a hit burns the tunic pale")


func test_the_stick_avatar_draws_its_own_limbs() -> void:
	var player := _dressed_player("stick")
	await wait_process_frames(2)
	var stick := _art(player).costume as StickCostume
	assert_not_null(stick, "the stick avatar is a StickCostume")
	if stick == null:
		return
	var art := _art(player)
	var box := stick.drawn
	for joint: Vector2 in [art._foot_front, art._foot_back, art._hand_front, art._hand_back]:
		assert_true(box.grow(0.01).has_point(joint), "the stroke reaches %s" % joint)


func test_choosing_the_princess_puts_on_her_concept() -> void:
	var look := CharacterLook.from_ids({"figure": "princess"})
	assert_eq(look.to_ids(), {"figure": "princess", "outfit": "royal", "accent": "gold",
		"hair": "brown", "skin": "fair"}, "the concept's blue, brown hair and fair skin")
	var chosen := CharacterLook.from_ids({"figure": "princess", "outfit": "wine"})
	assert_eq(String(chosen.option("outfit")["id"]), "wine", "but a named field wins")
	var prince := CharacterLook.from_ids({"figure": "prince"})
	assert_eq(String(prince.option("outfit")["id"]), "crimson", "and the prince has none")


func test_the_princess_blade_glows_and_the_rest_do_not() -> void:
	var player := _dressed_player()
	var tones := _art(player).costume.blade_colours()
	assert_true(tones.has("glow"), "her sword glows")
	for figure: String in ["prince", "heroine", "stick"]:
		var look := CharacterLook.from_ids({"figure": figure})
		look.dress(_art(player))
		assert_eq(_art(player).costume.blade_colours(), {}, "%s keeps steel" % figure)


## A portrait (ModelCostume.view_yaw) is unsheared, so its joints leave the
## rig: nothing that plays may set it. Only the costume that defines it and
## the portrait tool name it.
func test_only_the_portrait_tool_turns_the_camera_round() -> void:
	var allowed: Array[String] = [
		"res://scripts/player/model_costume.gd", "res://tools/model_portrait.gd",
	]
	var found: Array[String] = []
	for dir: String in ["res://scripts", "res://tools"]:
		found.append_array(_naming(dir, "view_yaw"))
	for path: String in found:
		assert_has(allowed, path, "%s sets a portrait camera" % path)
	assert_has(found, "res://tools/model_portrait.gd", "the scan reads the files")


func _naming(dir: String, word: String) -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at(dir):
		var path := dir.path_join(name)
		if name.ends_with(".gd") and FileAccess.get_file_as_string(path).contains(word):
			out.append(path)
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_naming(dir.path_join(sub), word))
	return out
