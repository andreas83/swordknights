extends SceneTree
## Pins the character's side of the audio: the footstep cadence, the landing
## map, and the fact that the node is harmless without a mixer.
##
## The cadence is the part most likely to rot. Footsteps are not on a timer —
## they are derived from the same leg-swing frequency PlayerArt draws with — so
## if somebody retunes the run cycle and only changes one of the two, the feet
## stop matching the legs. These numbers are what makes that loud.
##
##     godot --headless --script tests/audio_player_test.gd

## PlayerArt swings the legs with sin(state_time * 16) in RUN and
## sin(state_time * 9) in WALK. A foot lands every half cycle.
const ART_RUN_RATE := 16.0
const ART_WALK_RATE := 9.0

var _failures := 0
var _player: Player
var _audio: Node


func _initialize() -> void:
	_silence_the_autoload()
	_check_cadence()
	_check_landing_map()
	_check_events_resolve()

	var scene := load("res://scenes/player.tscn") as PackedScene
	if scene == null:
		_fail("could not load scenes/player.tscn")
		return
	_player = scene.instantiate() as Player
	if _player == null:
		_fail("player.tscn is not a Player")
		return
	root.add_child(_player)


func _process(_delta: float) -> bool:
	if _player != null:
		_check_scene_wiring()
		_check_signals_are_harmless_without_a_mixer()
		_player.free()

	if _failures > 0:
		printerr("audio_player_test: %d failure(s)" % _failures)
		quit(1)
		return true
	print("audio_player_test: ok")
	quit(0)
	return true


func _check_cadence() -> void:
	_equal(PlayerAudio.step_rate(Player.State.RUN), ART_RUN_RATE,
		"the run cadence matches PlayerArt's leg swing")
	_equal(PlayerAudio.step_rate(Player.State.WALK), ART_WALK_RATE,
		"the walk cadence matches PlayerArt's leg swing")
	_equal(PlayerAudio.step_rate(Player.State.IDLE), 0.0, "idle does not step")
	_equal(PlayerAudio.step_rate(Player.State.JUMP), 0.0, "a jump does not step")
	_equal(PlayerAudio.step_index(Player.State.FALL, 1.0), -1, "falling has no footfall")

	# Running has to be faster than walking, and both have to be in the range a
	# human leg actually moves at. Five steps a second running, under three
	# walking.
	var run := PlayerAudio.steps_per_second(Player.State.RUN)
	var walk := PlayerAudio.steps_per_second(Player.State.WALK)
	_true(absf(run - 5.093) < 0.01, "run is %.3f steps/s, expected 5.09" % run)
	_true(absf(walk - 2.865) < 0.01, "walk is %.3f steps/s, expected 2.86" % walk)
	_true(run > walk, "running is not faster than walking")

	# Stepping through a second of RUN at the physics rate must produce exactly
	# the cadence above — no doubled steps inside one frame, no silent gaps.
	for state: int in [Player.State.RUN, Player.State.WALK]:
		var expected := int(PlayerAudio.steps_per_second(state))
		var steps := 0
		var last := -1
		for frame: int in 60:
			var index := PlayerAudio.step_index(state, float(frame) / 60.0)
			if index != last:
				steps += 1
				last = index
		# The first footfall is at state_time 0 — entering the state puts a
		# foot down — so one second of running is the rate plus that one.
		_equal(steps, expected + 1,
			"one second of state %d produced %d footfalls" % [state, steps])

	# A state change restarts the cadence rather than carrying a phase over.
	_equal(PlayerAudio.step_index(Player.State.RUN, 0.0), 0, "a new state steps immediately")
	_true(PlayerAudio.step_index(Player.State.RUN, 0.2)
		> PlayerAudio.step_index(Player.State.RUN, 0.1), "the cadence advances")


func _check_landing_map() -> void:
	_equal(PlayerAudio.voice_for_landing(0.0), "", "standing still is not a landing")
	_equal(PlayerAudio.voice_for_landing(PlayerAudio.LAND_FLOOR - 1.0), "",
		"a nudge below the floor is silent")
	_equal(PlayerAudio.voice_for_landing(PlayerAudio.LAND_FLOOR + 1.0), "land_soft",
		"just over the floor is the light landing")
	_equal(PlayerAudio.voice_for_landing(Tuning.SOFT_LAND_SPEED), "land_soft",
		"the soft threshold is the light landing")
	_equal(PlayerAudio.voice_for_landing(Tuning.HARD_LAND_SPEED), "land_hard",
		"the hard threshold is the heavy landing")
	_equal(PlayerAudio.voice_for_landing(Tuning.MAX_FALL_SPEED), "land_hard",
		"terminal velocity is the heavy landing")
	# The thresholds are Tuning's, not a second copy of them.
	_true(PlayerAudio.LAND_FLOOR < Tuning.SOFT_LAND_SPEED,
		"the audible floor sits below Tuning's soft landing")


func _check_events_resolve() -> void:
	for event: String in PlayerAudio.event_names():
		_true(Voices.resolve(event) != "", "PlayerAudio emits '%s' with no voice" % event)
	for state: int in PlayerAudio.CLOTH_ON_ENTER:
		_true(float(PlayerAudio.CLOTH_ON_ENTER[state]) <= 0.0,
			"cloth on state %d is a trim, not a boost" % state)
	_true(PlayerAudio.event_names().has("cloth"), "cloth is in the emitted set")


func _check_scene_wiring() -> void:
	_audio = _player.get_node_or_null(^"PlayerAudio")
	_true(_audio != null, "player.tscn carries a PlayerAudio node")
	if _audio == null:
		return
	_true(_audio is PlayerAudio, "the node runs player_audio.gd")
	_equal(_audio.get_parent(), _player, "PlayerAudio hangs off the Player")

	# It listens rather than polls, which is what keeps player.gd untouched.
	for signal_name: String in ["jumped", "landed", "grabbed_ledge", "attacked",
			"hurt", "died"]:
		var connections: Array = _player.get_signal_connection_list(signal_name)
		var found := false
		for connection: Dictionary in connections:
			var callable: Callable = connection["callable"]
			if callable.get_object() == _audio:
				found = true
		_true(found, "PlayerAudio is not connected to '%s'" % signal_name)


## Every signal handler has to run without exploding, and the node has to
## survive having no mixer at all: the autoload is resolved by path precisely
## so that a tool, a unit test or a scene opened on its own still works. If
## this breaks, the headless tests of the rest of the game break with it.
func _check_signals_are_harmless_without_a_mixer() -> void:
	# A node that never entered the tree has no director and no parent, which
	# is the hostile case both guards exist for.
	var orphan := PlayerAudio.new()
	orphan._play("sword")
	orphan._physics_process(1.0 / 60.0)
	orphan.free()
	_true(true, "PlayerAudio is inert with no parent and no mixer")

	_player.jumped.emit()
	_player.landed.emit(Tuning.HARD_LAND_SPEED + 10.0)
	_player.landed.emit(5.0)
	_player.grabbed_ledge.emit()
	_player.attacked.emit()
	_player.hurt.emit(1)
	_player.died.emit()
	# Several physics frames with no level and no mixer.
	for frame: int in 8:
		_player._physics_process(1.0 / 60.0)
	_true(true, "the character ran silently without a mixer")


func _equal(actual: Variant, expected: Variant, what: String) -> void:
	if actual == expected:
		return
	_fail("%s: expected %s, got %s" % [what, str(expected), str(actual)])


func _true(condition: bool, what: String) -> void:
	if not condition:
		_fail(what)


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  " + message)


## The project's own AudioDirector autoload is instantiated even for a --script
## run. Silencing it before its first frame keeps this test measuring only what
## it creates itself, and keeps the engine from reporting leaked instances at
## exit — which it does for any AudioStreamPlayer still playing as it shuts
## down, including a bare one with no project code involved.
func _silence_the_autoload() -> void:
	var autoload := root.get_node_or_null(^"AudioDirector")
	if autoload == null:
		return
	autoload.autostart_music = false
	autoload.autostart_ambience = false
	autoload.bake_on_ready = false
