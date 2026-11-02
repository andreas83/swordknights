extends SceneTree
## Writes every project setting and input action from code.
##
## Keeping the configuration in a script rather than in editor state means the
## settings are reviewable in a diff, reproducible on a fresh clone, and safe to
## regenerate in CI. Run it with:
##
##     godot --headless --script tools/configure_project.gd
##
## It rewrites project.godot in place and exits.

const BASE_WIDTH := 320
const BASE_HEIGHT := 180


func _initialize() -> void:
	_apply_settings()
	_apply_input_map()

	var err := ProjectSettings.save()
	if err != OK:
		push_error("Could not save project settings: %d" % err)
		quit(1)
		return

	print("project.godot written — viewport %dx%d, %d input actions" % [
		BASE_WIDTH, BASE_HEIGHT, _action_names().size(),
	])
	quit(0)


func _apply_settings() -> void:
	var settings := {
		"application/config/name": "Swordknights",
		"application/config/description":
			"A mobile platform adventure in the spirit of Prince of Persia.",
		"application/run/main_scene": "res://scenes/boot.tscn",
		"application/config/icon": "res://icon.svg",
		"application/boot_splash/show_image": false,
		"application/boot_splash/bg_color": Color("2b0a14"),

		# Fixed virtual height with an aspect-derived width: the character reads
		# the same size on every device, and a tall phone sees more of the room
		# instead of black bars.
		"display/window/size/viewport_width": BASE_WIDTH,
		"display/window/size/viewport_height": BASE_HEIGHT,
		"display/window/size/window_width_override": BASE_WIDTH * 4,
		"display/window/size/window_height_override": BASE_HEIGHT * 4,
		"display/window/stretch/mode": "canvas_items",
		"display/window/stretch/aspect": "keep_height",
		"display/window/handheld/orientation": 4, # sensor landscape
		"display/window/vsync/vsync_mode": 1,

		# The simulation must advance in constant slices so jump arcs are
		# identical on 60 Hz and 120 Hz devices, and so lockstep netplay stays
		# in step. Everything gameplay-related lives in _physics_process.
		"physics/common/physics_ticks_per_second": 60,
		"physics/common/max_physics_steps_per_frame": 5,
		"physics/2d/default_gravity": 0, # the player applies its own gravity

		"rendering/renderer/rendering_method": "gl_compatibility",
		"rendering/renderer/rendering_method.mobile": "gl_compatibility",
		"rendering/textures/canvas_textures/default_texture_filter": 0, # nearest
		"rendering/environment/defaults/default_clear_color": Color("2b0a14"),

		"input_devices/pointing/emulate_touch_from_mouse": true,
	}

	for key: String in settings:
		ProjectSettings.set_setting(key, settings[key])


## action name -> [physical key codes], [joypad buttons]
func _action_names() -> Dictionary:
	return {
		"move_left": [[KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT]],
		"move_right": [[KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT]],
		"move_up": [[KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP]],
		"move_down": [[KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN]],
		"jump": [[KEY_SPACE, KEY_K], [JOY_BUTTON_A]],
		"attack": [[KEY_J, KEY_E, KEY_ENTER], [JOY_BUTTON_X, JOY_BUTTON_B]],
		"walk": [[KEY_SHIFT], [JOY_BUTTON_LEFT_SHOULDER]],
		"pause": [[KEY_ESCAPE, KEY_P], [JOY_BUTTON_START]],
		"ui_confirm_action": [[KEY_SPACE, KEY_ENTER], [JOY_BUTTON_A]],
	}


func _apply_input_map() -> void:
	for action: String in _action_names():
		var path := "input/" + action
		var events: Array[InputEvent] = []

		var spec: Array = _action_names()[action]
		for key: int in spec[0]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = key
			events.append(key_event)
		for button: int in spec[1]:
			var pad_event := InputEventJoypadButton.new()
			pad_event.button_index = button
			events.append(pad_event)

		# Analogue stick, so a thumbstick works without a D-pad.
		var axis_event := _axis_for(action)
		if axis_event != null:
			events.append(axis_event)

		ProjectSettings.set_setting(path, {"deadzone": 0.4, "events": events})


func _axis_for(action: String) -> InputEventJoypadMotion:
	var axes := {
		"move_left": [JOY_AXIS_LEFT_X, -1.0],
		"move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0],
		"move_down": [JOY_AXIS_LEFT_Y, 1.0],
	}
	if not axes.has(action):
		return null
	var event := InputEventJoypadMotion.new()
	event.axis = axes[action][0]
	event.axis_value = axes[action][1]
	return event
