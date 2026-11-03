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
	_apply_audio() # audio branch — see the marked section at the end of the file
	_apply_duel_input() # fighter branch — see the marked section at the end

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

		# Android's exporter refuses to export at all without this -- an error
		# it prints with an empty reason when run headless. The game's textures
		# are pixel art imported lossless, so it changes nothing they look like;
		# it only lets the mobile exports run.
		"rendering/textures/vram_compression/import_etc2_astc": true,

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

		# --- duel: raise the sword to block --------------------------------
		# The eighth and last input bit. Shared by the adventure (where nothing
		# reads it yet) and by the online duel, whose local seat drives the
		# unsuffixed actions so the gamepad and the touch controls keep working.
		"guard": [[KEY_Q, KEY_L], [JOY_BUTTON_RIGHT_SHOULDER]],

		# --- duel: two seats on one keyboard -------------------------------
		# A second binding set cannot simply be added next to the first: the
		# shared actions already claim BOTH the arrows and WASD, so on a local
		# duel one key would move both duellists. Hence two complete,
		# non-overlapping sets, and the local duel reads only these. Seat one
		# takes the left of the keyboard, seat two the right and the numpad.
		#
		# Keyboard only, deliberately: a Godot action cannot tell one gamepad
		# from another without per-device events, so a pad bound here would
		# drive both seats at once. See docs/netplay.md.
		"move_left_p1": [[KEY_A], []],
		"move_right_p1": [[KEY_D], []],
		"move_up_p1": [[KEY_W], []],
		"move_down_p1": [[KEY_S], []],
		"jump_p1": [[KEY_SPACE, KEY_V], []],
		"attack_p1": [[KEY_F], []],
		"guard_p1": [[KEY_G], []],
		"walk_p1": [[KEY_SHIFT], []],

		"move_left_p2": [[KEY_LEFT, KEY_KP_4], []],
		"move_right_p2": [[KEY_RIGHT, KEY_KP_6], []],
		"move_up_p2": [[KEY_UP, KEY_KP_8], []],
		"move_down_p2": [[KEY_DOWN, KEY_KP_5], []],
		"jump_p2": [[KEY_K, KEY_KP_0], []],
		"attack_p2": [[KEY_J, KEY_KP_1], []],
		"guard_p2": [[KEY_L, KEY_KP_2], []],
		"walk_p2": [[KEY_SEMICOLON, KEY_KP_3], []],
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


## --- AUDIO ------------------------------------------------------------------
## Everything the audio system needs from project.godot lives in this one
## function, on purpose: it is the only part of this file the audio branch
## touches, so it cannot collide with input actions being added elsewhere.
##
## There is no default_bus_layout.tres and there is no audio importer config,
## because there are no audio files. AudioDirector builds the Master / Music /
## SFX buses from code at startup and synthesises every sample it plays.
func _apply_audio() -> void:
	# One autoload. It owns the buses, the player pool and the music, and it is
	# the only global the audio system adds.
	ProjectSettings.set_setting(
		"autoload/AudioDirector", "*res://scripts/audio/audio_director.gd"
	)

	# A mute toggle. Deliberately not in _action_names(): that table is shared
	# with the other branches, and this action has no gamepad or touch binding
	# yet — the menu is the place for those, and the menu is not ours.
	var mute := InputEventKey.new()
	mute.physical_keycode = KEY_M
	var events: Array[InputEvent] = [mute]
	ProjectSettings.set_setting("input/audio_mute", {"deadzone": 0.4, "events": events})

	print("audio — AudioDirector autoload, audio_mute bound to M")
## --- END AUDIO --------------------------------------------------------------


## --- DUEL FIGHTER -----------------------------------------------------------
## Everything the Nidhogg-style fighter needs from project.godot lives in this
## one function, on purpose: it is the only part of this file the fighter
## branch touches, so it cannot collide with actions being added elsewhere.
##
## The fighter needs seven buttons — left, right, up, down, jump, attack and
## THROW — and the frame is still one byte, because the three sword stances are
## driven by up and down and cost no bit at all. Throw takes bit 7, which the
## duel's retired guard button used to carry, so it is bound to the same keys:
## PlayerInput.bits_from_actions() reads `throw` and `guard` onto that one bit
## and the old duel keeps working while it still exists.
func _apply_duel_input() -> void:
	var throws := {
		"throw": [[KEY_Q, KEY_L], [JOY_BUTTON_RIGHT_SHOULDER]],
		"throw_p1": [[KEY_G], []],
		"throw_p2": [[KEY_L, KEY_KP_2], []],
	}
	for action: String in throws:
		var events: Array[InputEvent] = []
		var spec: Array = throws[action]
		for key: int in spec[0]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = key
			events.append(key_event)
		for button: int in spec[1]:
			var pad_event := InputEventJoypadButton.new()
			pad_event.button_index = button
			events.append(pad_event)
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.4, "events": events})

	print("duel — throw bound for the shared set and both local seats")
## --- END DUEL FIGHTER -------------------------------------------------------
