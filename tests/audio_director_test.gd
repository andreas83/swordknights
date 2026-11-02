extends SceneTree
## Pins the mixer: the bus layout, event resolution, the player pool, the
## anti-machine-gun throttle, mute, and the settings round-trip.
##
## This runs the real autoload script against the real AudioServer — on a
## machine with no audio device that is Godot's dummy driver, which still
## creates buses and accepts players, so everything here is meaningful without
## anything being audible.
##
##     godot --headless --script tests/audio_director_test.gd

const DIRECTOR := "res://scripts/audio/audio_director.gd"
const BAKE_TIMEOUT_MSEC := 120000

var _failures := 0
var _director: Node


## A node added to the root during _initialize() is not in the tree yet, so its
## _ready has not run. The checks therefore happen on the first frame, in
## _process below, which is also the only place a SceneTree script can see the
## autoload behave the way it does in the game.
func _initialize() -> void:
	_silence_the_autoload()
	_check_settings()

	_director = load(DIRECTOR).new()
	_director.name = "AudioDirector"
	# No loop playing underneath the assertions.
	_director.autostart_music = false
	_director.autostart_ambience = false
	root.add_child(_director)


func _process(_delta: float) -> bool:
	if _director != null:
		_run(_director)
		# Freeing the director stops its players, but the AudioServer only
		# reaps a stopped playback on its next mix — so report on the frame
		# after, rather than leave the engine counting live playbacks as
		# leaked instances at exit.
		_director.free()
		_director = null
		return false

	if _failures > 0:
		printerr("audio_director_test: %d failure(s)" % _failures)
		quit(1)
		return true
	# Each play() leaves a playback object that only the AudioServer's next mix
	# reaps, and a two-frame headless run never gets there — so this test ends
	# with the engine's "ObjectDB instances leaked at exit" warning. It is an
	# accounting artifact of the short run, not a failure. docs/audio.md has
	# the detail.
	print("audio_director_test: ok (the leak warning below is expected)")
	quit(0)
	return true


func _run(director: Node) -> void:
	_check_bus_layout(director)
	_check_pool(director)
	_check_every_event_resolves(director)

	if not _await_bake(director):
		_fail("baking did not finish within %d ms" % BAKE_TIMEOUT_MSEC)
		return
	_check_playback(director)
	_check_throttle(director)
	_check_mute(director)
	_check_variation_stays_in_range(director)


## The layout the director claims has to be the layout the AudioServer has:
## Master at 0, Music and SFX both sending to it.
func _check_bus_layout(director: Node) -> void:
	var claimed: Dictionary = director.bus_layout()
	_equal(claimed.size(), 3, "three buses")
	for name: String in claimed:
		var index := AudioServer.get_bus_index(name)
		_true(index != -1, "bus '%s' exists in the AudioServer" % name)
		if index == -1:
			continue
		_equal(index, int(claimed[name]["index"]), "bus '%s' index" % name)
		_equal(AudioServer.get_bus_name(index), name, "bus %d name" % index)
		if name == "Master":
			continue
		_equal(AudioServer.get_bus_send(index), String(claimed[name]["send"]),
			"bus '%s' send" % name)

	_equal(AudioServer.get_bus_name(0), "Master", "Master is bus 0")
	_true(AudioServer.bus_count >= 3, "the server has at least three buses")

	# Idempotent: a second director (a scene reload, or this test running
	# twice in one process) must not stack duplicate buses.
	var before := AudioServer.bus_count
	var second: Node = load(DIRECTOR).new()
	second.autostart_music = false
	second.autostart_ambience = false
	second.bake_on_ready = false
	root.add_child(second)
	_equal(AudioServer.bus_count, before, "a second director added no buses")
	second.free()


func _check_pool(director: Node) -> void:
	var players := 0
	for child: Node in director.get_children():
		if child is AudioStreamPlayer:
			players += 1
	# The one-shot pool plus the bed, the drive stem and the ambience.
	_equal(players, director.POOL_SIZE + 3, "pool size")

	var buses := {}
	for child: Node in director.get_children():
		if child is AudioStreamPlayer:
			var player := child as AudioStreamPlayer
			buses[String(player.bus)] = true
			_true(AudioServer.get_bus_index(player.bus) != -1,
				"player '%s' points at a real bus" % player.name)
	_true(buses.has("SFX") and buses.has("Music"), "both buses are in use")


## Everything the game may hand to play(), including the player node's own
## table and the shorthand aliases, has to land on a real voice.
func _check_every_event_resolves(director: Node) -> void:
	for event: String in Voices.event_names():
		var voice := Voices.resolve(event)
		_true(voice != "", "event '%s' does not resolve" % event)
		_true(Voices.specs().has(voice), "event '%s' resolved to '%s'" % [event, voice])

	for event: String in PlayerAudio.event_names():
		_true(Voices.resolve(event) != "", "PlayerAudio emits '%s', which has no voice" % event)

	# The names the rest of the game is documented to use (docs/audio.md).
	for event: String in ["land", "step", "attack", "hit", "grab", "death",
			"pickup", "door", "complete", "menu_move", "menu_confirm",
			"menu_back", "pause", "unpause", "ambience"]:
		_true(Voices.resolve(event) != "", "documented event '%s' does not resolve" % event)

	_equal(Voices.resolve("no_such_sound"), "", "an unknown event resolves to nothing")
	_true(director.play("no_such_sound") == null, "an unknown event plays nothing")

	# The director keeps its own copy of the catalogue for the hot path; it has
	# to agree with the catalogue itself.
	for event: String in Voices.event_names():
		_equal(director.resolve(event), Voices.resolve(event),
			"the director resolves '%s' the same way Voices does" % event)
		_true(director.has_voice(event), "the director has a voice for '%s'" % event)
	_true(not director.has_voice("no_such_sound"), "has_voice rejects an unknown event")


func _await_bake(director: Node) -> bool:
	var started := Time.get_ticks_msec()
	while not director.is_ready():
		if Time.get_ticks_msec() - started > BAKE_TIMEOUT_MSEC:
			return false
		OS.delay_msec(20)
	return true


func _check_playback(director: Node) -> void:
	var player: AudioStreamPlayer = director.play("sword")
	_true(player != null, "a baked voice plays")
	if player == null:
		return
	_equal(String(player.bus), "SFX", "one-shots play on the SFX bus")
	_true(player.stream != null, "the player was given a stream")
	_equal(player.volume_db <= 6.0, true, "volume is inside the ceiling")

	# Overlapping one-shots must not land on the same player, or they cut each
	# other off — the whole reason the pool exists.
	var seen := {}
	for i: int in director.POOL_SIZE:
		var p: AudioStreamPlayer = director.play("step_run", {"force": true})
		if p == null:
			continue
		seen[p.get_instance_id()] = true
	_true(seen.size() > 1, "repeated one-shots all landed on one player")


func _check_throttle(director: Node) -> void:
	# min_gap exists so a five-a-second run cycle cannot stack the identical
	# sample on top of itself.
	var gap := float(Voices.spec("land_hard").get("min_gap", 0.0))
	_true(gap > 0.0, "land_hard declares a minimum gap")
	_true(director.play("land_hard", {"force": true}) != null, "first land plays")
	_true(director.play("land_hard") == null, "a land inside the gap is dropped")
	_true(director.play("land_hard", {"force": true}) != null, "force overrides the gap")


func _check_mute(director: Node) -> void:
	director.settings.muted = true
	_true(director.play("sword", {"force": true}) == null, "muted plays nothing")
	_true(AudioServer.is_bus_mute(0), "mute reaches the Master bus")
	director.settings.muted = false
	_true(not AudioServer.is_bus_mute(0), "unmute reaches the Master bus")
	_true(director.play("sword", {"force": true}) != null, "unmuted plays again")


func _check_variation_stays_in_range(director: Node) -> void:
	var spec := Voices.spec("step_run")
	var pitch_jitter := float(spec["pitch_jitter"])
	var lowest := 2.0
	var highest := 0.0
	for i: int in 24:
		var player: AudioStreamPlayer = director.play("step_run", {"force": true})
		if player == null:
			continue
		lowest = minf(lowest, player.pitch_scale)
		highest = maxf(highest, player.pitch_scale)
	_true(lowest >= 1.0 - pitch_jitter - 0.001 and highest <= 1.0 + pitch_jitter + 0.001,
		"pitch variation %.3f..%.3f left its +/-%.3f window" % [lowest, highest, pitch_jitter])
	# And it has to actually vary, or repeated steps machine-gun.
	_true(highest - lowest > pitch_jitter * 0.5,
		"pitch variation %.3f..%.3f barely moved" % [lowest, highest])

	var opts := {"pitch": 1.25, "vary": false, "force": true}
	var fixed: AudioStreamPlayer = director.play("step_run", opts)
	_true(fixed != null and is_equal_approx(fixed.pitch_scale, 1.25),
		"vary:false honours the requested pitch exactly")


func _check_settings() -> void:
	var settings := AudioSettings.new()
	settings.master = 0.5
	settings.music = 0.25
	settings.sfx = 1.0
	settings.muted = true
	_equal(settings.save(), OK, "settings save to user://")

	var loaded := AudioSettings.new()
	_true(loaded.load_from_disk(), "settings load back")
	_true(is_equal_approx(loaded.master, 0.5), "master round-trips")
	_true(is_equal_approx(loaded.music, 0.25), "music round-trips")
	_equal(loaded.muted, true, "mute round-trips")

	# A linear slider has to map onto the fader monotonically, and zero has to
	# mean silent rather than -0 dB.
	_true(loaded.db_for(&"Music") < loaded.db_for(&"SFX"), "quieter linear means fewer dB")
	loaded.music = 0.0
	_equal(loaded.db_for(&"Music"), AudioSettings.SILENCE_DB, "zero is silence")
	loaded.music = 1.0
	_true(is_zero_approx(loaded.db_for(&"Music")), "full is unity gain")
	_true(loaded.linear_for(&"Master") == loaded.master, "linear_for picks the right bus")

	# Leave the file in its default state so the test is repeatable.
	var defaults := AudioSettings.new()
	defaults.save()


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
