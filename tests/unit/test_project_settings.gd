extends GutTest
## Smoke tests: assert the project settings that tools/configure_project.gd
## claims to write are actually in effect.
##
## These guard the contract that configuration lives in code, not in editor
## state. If someone changes a setting through the editor UI without updating
## configure_project.gd, this suite and the script disagree and CI fails.

const BASE_WIDTH := 320
const BASE_HEIGHT := 180


func test_application_name_is_swordknights() -> void:
	assert_eq(
		ProjectSettings.get_setting("application/config/name"),
		"Swordknights",
		"application/config/name must match configure_project.gd"
	)


func test_main_scene_is_the_boot_scene() -> void:
	assert_eq(
		ProjectSettings.get_setting("application/run/main_scene"),
		"res://scenes/boot.tscn",
		"the engine must enter through the scene we control"
	)


func test_viewport_is_the_fixed_virtual_resolution() -> void:
	assert_eq(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		BASE_WIDTH,
		"viewport width drives how large the character reads on screen"
	)
	assert_eq(
		ProjectSettings.get_setting("display/window/size/viewport_height"),
		BASE_HEIGHT,
		"viewport height is the fixed axis; width follows the aspect"
	)


func test_stretch_keeps_height_so_tall_phones_see_more_room() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")
	assert_eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "keep_height")


func test_physics_tick_is_fixed_at_60() -> void:
	# Jump arcs must be identical on 60 Hz and 120 Hz devices.
	assert_eq(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"), 60)
	assert_eq(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame"), 5)


func test_renderer_is_gl_compatibility_on_desktop_and_mobile() -> void:
	# Web and low-end Android both need the compatibility backend.
	assert_eq(
		ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility"
	)
	assert_eq(
		ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"),
		"gl_compatibility"
	)


func test_texture_filter_is_nearest_for_pixel_art() -> void:
	assert_eq(
		ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter"),
		0,
		"0 == nearest; anything else blurs the pixel art"
	)


func test_every_gameplay_input_action_is_mapped() -> void:
	var expected := [
		"move_left",
		"move_right",
		"move_up",
		"move_down",
		"jump",
		"attack",
		"walk",
		"pause",
		"ui_confirm_action",
	]
	for action: String in expected:
		assert_true(
			InputMap.has_action(action), "input action '%s' is missing from the input map" % action
		)
		assert_gt(
			InputMap.action_get_events(action).size(),
			0,
			"input action '%s' is mapped but has no events bound" % action
		)
