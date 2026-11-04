extends Node
## The mixer and the only thing the game talks to. Registered as the
## `AudioDirector` autoload by tools/configure_project.gd.
##
##     AudioDirector.play("land", {"pitch": 1.2})
##     AudioDirector.set_intensity(0.7)
##
## It owns four things:
##
## **Buses.** Master / Music / SFX, created from code in `_ensure_buses()` so
## there is no default_bus_layout.tres to keep in sync with anything. Music and
## SFX both send to Master; the settings drive the two faders and Master
## carries the mute.
##
## **A pool of players.** Overlapping one-shots on a platformer are the norm —
## a footstep under a sword swing under a relic pickup — so one
## AudioStreamPlayer per sound would cut them off. The pool hands out the
## longest-idle player and only steals a busy one when every player is in use.
##
## **Variation.** Every voice declares a pitch and gain jitter window and a
## minimum gap. Without the jitter, a run cycle machine-guns the identical
## sample five times a second and the ear hears a buzz instead of footsteps.
##
## **Ducking.** Loud events (a hard landing, every blow of a fight, a death, a
## pause) pull the music bus down by the amount in their spec and let it climb
## back at a fixed rate, so the hit reads over the loop without the music
## disappearing. The law -- trim, duck, drive, mood -- is Mix's, which the
## offline MixRender reads too, so what the tests measure is this mixer.
##
## **Mood.** A scene may claim a mood (`set_mood()`): the duel's is quieter and
## has no drum. The claim lasts while the node that made it is in the tree,
## so a scene change cannot leave the menu in a duel's mood.
##
## Baking happens off the main thread. Synthesising every voice plus the two
## music stems is around two seconds of GDScript on a desktop — a freeze, if it
## ran at load — so the worker fills the table in the background and `play()`
## is simply a no-op for a voice that is not baked yet. Platforms without
## thread support (a single-threaded web export) fall back to baking one voice
## per frame.

signal ready_changed(is_ready: bool)

const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"

## Enough for every overlapping one-shot the character can produce (footstep,
## cloth, sword, landing) plus world and UI events on top.
const POOL_SIZE := 12

## Seconds for the intensity cross-fade to travel the full 0..1 range.
const INTENSITY_RAMP := 2.5

## A one-shot asked for before the audio context was unlocked is replayed if
## the gesture arrives within this long. Browsers refuse to start an audio
## context without a user gesture, so the first tap would otherwise be silent.
const GESTURE_GRACE := 0.6

## Set false before the autoload's first frame (or call stop_music()) for a
## build that scores itself some other way.
var autostart_music := true
var autostart_ambience := true
## Test seam: a director created only to inspect the bus layout can skip the
## two seconds of synthesis it would otherwise start.
var bake_on_ready := true

var settings := AudioSettings.new()

var _streams: Dictionary = {}
## The catalogue, read once. play() is called several times a second during a
## run cycle and Voices.specs() builds its table fresh on every call, so the
## hot path keeps its own copy instead of allocating one per footstep.
var _specs: Dictionary = {}
var _aliases: Dictionary = {}
var _music_streams: Array[AudioStreamWAV] = []
var _pool: Array[AudioStreamPlayer] = []
var _started_at: PackedInt64Array = PackedInt64Array()
var _last_played: Dictionary = {}
var _bed: AudioStreamPlayer
var _drive: AudioStreamPlayer
var _ambience: AudioStreamPlayer

var _rng := RandomNumberGenerator.new()
var _duck_db := 0.0
var _duck_hold := 0.0
var _intensity := 0.0
var _intensity_target := 0.0
var _mood: StringName = Mix.MOOD_DEFAULT
var _mood_owner: WeakRef = null
## The mood's trim as it stands, moving toward Mix.mood_db(_mood).
var _mood_db := 0.0
var _music_wanted := false
var _ambience_wanted := false
var _gesture_needed := false
var _pending: Dictionary = {}
var _pending_age := 0.0
var _warmup_drops := 0

var _thread: Thread
var _mutex := Mutex.new()
var _bake_queue: PackedStringArray = PackedStringArray()
var _bake_done := false


func _ready() -> void:
	# The mixer has to keep running while the tree is paused, and the pause
	# sound itself is played on the frame the game freezes.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()

	_specs = Voices.specs()
	_aliases = Voices.aliases()

	_ensure_buses()
	settings.load_from_disk()
	settings.changed.connect(_apply_settings)

	_build_pool()
	_apply_settings()

	_gesture_needed = OS.has_feature("web")
	_music_wanted = autostart_music
	_ambience_wanted = autostart_ambience
	if bake_on_ready:
		_start_baking()


func _exit_tree() -> void:
	# A player still playing keeps a playback object alive inside the
	# AudioServer after the node is gone, which shows up as a leak at exit.
	for player: AudioStreamPlayer in _pool:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in [_bed, _drive, _ambience]:
		if player != null:
			player.stop()
			player.stream = null
	_streams.clear()
	_music_streams.clear()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null


## --- buses -----------------------------------------------------------------

func _ensure_buses() -> void:
	# Master is index 0 and always exists. Adding by name keeps this idempotent,
	# which matters because a test instantiates the director into a live
	# AudioServer that may already carry the layout.
	for bus: StringName in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus) != -1:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, String(bus))
		AudioServer.set_bus_send(index, BUS_MASTER)
	_ensure_limiter()


## A hard limiter on Master. The combat voices are now loud on purpose and
## stack: a killing blow is the wound and the kill on the same frame, which
## MixRender measures at +4.5 dB over full scale before the master fader. A
## phone's DAC would square that off; the limiter rounds it instead, and it
## touches nothing that is not about to clip.
func _ensure_limiter() -> void:
	for i: int in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.3
	AudioServer.add_bus_effect(0, limiter)


## What the director claims the mixer looks like: bus name -> {index, send}.
## The test compares this against the live AudioServer.
func bus_layout() -> Dictionary:
	return {
		String(BUS_MASTER): {"index": 0, "send": ""},
		String(BUS_MUSIC): {"index": AudioServer.get_bus_index(BUS_MUSIC),
			"send": String(BUS_MASTER)},
		String(BUS_SFX): {"index": AudioServer.get_bus_index(BUS_SFX),
			"send": String(BUS_MASTER)},
	}


func _apply_settings() -> void:
	AudioServer.set_bus_mute(0, settings.muted)
	AudioServer.set_bus_volume_db(0, settings.db_for(BUS_MASTER))
	var sfx := AudioServer.get_bus_index(BUS_SFX)
	if sfx != -1:
		AudioServer.set_bus_volume_db(sfx, settings.db_for(BUS_SFX))
	_apply_music_volume()


func _apply_music_volume() -> void:
	var music := AudioServer.get_bus_index(BUS_MUSIC)
	if music == -1:
		return
	AudioServer.set_bus_volume_db(music,
		Mix.music_db(settings.db_for(BUS_MUSIC), _mood_db, _duck_db))


## --- players ---------------------------------------------------------------

func _build_pool() -> void:
	_started_at.resize(POOL_SIZE)
	for i: int in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%02d" % i
		player.bus = BUS_SFX
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_pool.append(player)
		_started_at[i] = 0

	_bed = _make_music_player("MusicBed")
	_drive = _make_music_player("MusicDrive")
	_ambience = _make_music_player("Ambience")
	_ambience.bus = BUS_SFX


func _make_music_player(node_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = BUS_MUSIC
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


## --- baking ----------------------------------------------------------------

func _start_baking() -> void:
	_bake_queue = Voices.names()
	_bake_queue.append("__music__")
	if OS.has_feature("threads"):
		_thread = Thread.new()
		if _thread.start(_bake_worker) == OK:
			return
		_thread = null
	# No threads (single-threaded web export): spread the work over frames
	# instead, which _process drains one item at a time.
	push_warning("AudioDirector: no thread support, baking on the main thread")


func _bake_worker() -> void:
	for name: String in _bake_queue:
		_bake_one(name)
	_mutex.lock()
	_bake_done = true
	_mutex.unlock()


func _bake_one(name: String) -> void:
	if name == "__music__":
		var stems := Music.build_stems()
		_mutex.lock()
		_music_streams = stems
		_mutex.unlock()
		return
	var stream := Voices.build(name)
	_mutex.lock()
	_streams[name] = stream
	_mutex.unlock()


func is_ready() -> bool:
	_mutex.lock()
	var done := _bake_done
	_mutex.unlock()
	return done


func _stream_for(voice: String) -> AudioStreamWAV:
	_mutex.lock()
	var stream: AudioStreamWAV = _streams.get(voice, null)
	_mutex.unlock()
	return stream


## Voices that have not finished baking yet, for diagnostics.
func warmup_drops() -> int:
	return _warmup_drops


## --- the API ---------------------------------------------------------------

## Plays one voice. `opts` understands:
##   pitch       multiplier on top of the voice's own jitter (default 1.0)
##   volume_db   trim on top of the voice's spec (default 0)
##   vary        false to disable the pitch/gain jitter for this trigger
##   force       true to ignore the voice's minimum gap
## Returns the player, or null when the sound was dropped (muted, throttled,
## still baking, or waiting for a browser gesture).
func play(event: String, opts: Dictionary = {}) -> AudioStreamPlayer:
	var voice := resolve(event)
	if voice == "":
		push_warning("AudioDirector: no voice for event '%s'" % event)
		return null

	var spec := _specs[voice] as Dictionary
	var now := Time.get_ticks_msec()
	var gap := float(spec.get("min_gap", 0.0))
	if gap > 0.0 and not bool(opts.get("force", false)):
		var last: int = _last_played.get(voice, -100000)
		if float(now - last) < gap * 1000.0:
			return null
	_last_played[voice] = now

	if settings.muted:
		return null

	if _gesture_needed:
		# Remember it rather than firing into a suspended audio context.
		_pending = {"event": voice, "opts": opts.duplicate()}
		_pending_age = 0.0
		return null

	var stream := _stream_for(voice)
	if stream == null:
		_warmup_drops += 1
		return null

	var pitch := float(opts.get("pitch", 1.0))
	var volume := float(spec.get("db", 0.0)) + float(opts.get("volume_db", 0.0))
	if bool(opts.get("vary", true)):
		var pitch_jitter := float(spec.get("pitch_jitter", 0.0))
		var gain_jitter := float(spec.get("gain_jitter", 0.0))
		if pitch_jitter > 0.0:
			pitch *= 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
		if gain_jitter > 0.0:
			volume += _rng.randf_range(-gain_jitter, gain_jitter)

	var player := _take_player()
	player.stream = stream
	player.pitch_scale = clampf(pitch, 0.25, 4.0)
	player.volume_db = clampf(volume, -60.0, 6.0)
	player.play()

	var duck_db := float(spec.get("duck", 0.0))
	if duck_db > 0.0:
		duck(duck_db)
	return player


## Voice name for an event name, following the aliases. Empty when the event is
## not one the game can make a sound for.
func resolve(event: String) -> String:
	if _specs.has(event):
		return event
	return String(_aliases.get(event, ""))


func has_voice(event: String) -> bool:
	return resolve(event) != ""


## Pulls the music bus down by `amount` dB; it recovers by itself.
func duck(amount: float) -> void:
	_duck_db = maxf(_duck_db, absf(amount))
	_duck_hold = Mix.DUCK_HOLD
	_apply_music_volume()


## Puts the music in `which` (a Mix mood) for as long as `claimant` is in the
## tree. The last claim wins; when its claimant leaves, the default comes back.
func set_mood(which: StringName, claimant: Node = null) -> void:
	_mood = which if Mix.MOODS.has(which) else Mix.MOOD_DEFAULT
	_mood_owner = weakref(claimant) if claimant != null else null


func mood() -> StringName:
	return _mood


func play_music(intensity: float = -1.0) -> void:
	_music_wanted = true
	if intensity >= 0.0:
		set_intensity(intensity)
	_sync_music()


func stop_music() -> void:
	_music_wanted = false
	_bed.stop()
	_drive.stop()


## 0 is the bed alone — drone and oud. 1 adds the frame drum and the reed.
## The move is cross-faded over INTENSITY_RAMP, so this is safe to call every
## frame with a value derived from the game state.
func set_intensity(value: float) -> void:
	_intensity_target = clampf(value, 0.0, 1.0)


func intensity() -> float:
	return _intensity


func set_ambience(on: bool) -> void:
	_ambience_wanted = on
	if not on:
		_ambience.stop()
	else:
		_sync_music()


func set_muted(value: bool) -> void:
	settings.muted = value
	settings.save()


func toggle_mute() -> void:
	set_muted(not settings.muted)


## bus is "Master", "Music" or "SFX"; `value` is linear 0..1.
func set_volume(bus: StringName, value: float) -> void:
	match String(bus):
		"Music":
			settings.music = value
		"SFX":
			settings.sfx = value
		_:
			settings.master = value
	settings.save()


## --- per-frame -------------------------------------------------------------

func _process(delta: float) -> void:
	if _thread == null and not _bake_done:
		_bake_next_on_main_thread()

	if _duck_db > 0.0:
		var next := Mix.duck_step(_duck_db, _duck_hold, delta)
		_duck_db = next.x
		_duck_hold = next.y
		_apply_music_volume()

	_follow_mood(delta)

	var wanted := minf(_intensity_target, Mix.mood_intensity_cap(_mood))
	if not is_equal_approx(_intensity, wanted):
		_intensity = move_toward(_intensity, wanted, delta / INTENSITY_RAMP)
		_apply_intensity()

	if _gesture_needed and not _pending.is_empty():
		_pending_age += delta
		if _pending_age > GESTURE_GRACE:
			_pending.clear()

	_sync_music()


## A claim whose owner has left the tree is over. The trim then moves at
## MOOD_RAMP rather than jumping, so a scene change is not a step in volume.
func _follow_mood(delta: float) -> void:
	if _mood_owner != null:
		var claimant := _mood_owner.get_ref() as Node
		if claimant == null or not claimant.is_inside_tree():
			_mood = Mix.MOOD_DEFAULT
			_mood_owner = null
	var target := Mix.mood_db(_mood)
	if not is_equal_approx(_mood_db, target):
		_mood_db = move_toward(_mood_db, target, Mix.MOOD_RAMP * delta)
		_apply_music_volume()


func _bake_next_on_main_thread() -> void:
	if _bake_queue.is_empty():
		_bake_done = true
		ready_changed.emit(true)
		return
	var name := _bake_queue[0]
	_bake_queue.remove_at(0)
	_bake_one(name)


func _sync_music() -> void:
	if _gesture_needed:
		return

	if _ambience_wanted and not _ambience.playing:
		var wind := _stream_for("wind")
		if wind != null:
			_ambience.stream = wind
			_ambience.volume_db = float((_specs.get("wind", {}) as Dictionary)
				.get("db", -13.0))
			_ambience.play()

	# A music fader at zero is music off: the stems stop rather than play at
	# -60 dB, and come back from the top when the fader is raised again.
	if not _music_wanted or settings.music <= 0.001:
		if _bed.playing:
			_bed.stop()
			_drive.stop()
		return
	_mutex.lock()
	var stems := _music_streams
	_mutex.unlock()
	if stems.size() < 2:
		return

	# Both stems are one loop long and start in the same frame, which is what
	# keeps them sample-locked without any scheduling.
	if not _bed.playing:
		_bed.stream = stems[0]
		_drive.stream = stems[1]
		_apply_intensity()
		_bed.play()
		_drive.play()


func _apply_intensity() -> void:
	_bed.volume_db = 0.0
	_drive.volume_db = Mix.drive_db(_intensity)


func _take_player() -> AudioStreamPlayer:
	var oldest := 0
	var oldest_at := 9223372036854775807
	for i: int in _pool.size():
		if not _pool[i].playing:
			_started_at[i] = Time.get_ticks_msec()
			return _pool[i]
		if _started_at[i] < oldest_at:
			oldest_at = _started_at[i]
			oldest = i
	# Everything is busy: the longest-running one-shot is the least missed.
	_started_at[oldest] = Time.get_ticks_msec()
	return _pool[oldest]


## --- input -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _gesture_needed and event.is_pressed():
		var gesture := (
			event is InputEventKey
			or event is InputEventMouseButton
			or event is InputEventScreenTouch
			or event is InputEventJoypadButton
		)
		if gesture:
			_unlock()

	if InputMap.has_action("audio_mute") and event.is_action_pressed("audio_mute"):
		toggle_mute()


## Browsers will not start an audio context until the player has interacted, so
## the first tap arrives before any sound can be made. Rather than swallow it,
## the request is held and fired here.
func _unlock() -> void:
	_gesture_needed = false
	_apply_settings()
	var event: String = _pending.get("event", "") if _pending_age <= GESTURE_GRACE else ""
	var opts: Dictionary = _pending.get("opts", {})
	_pending.clear()
	if event != "":
		# The gap bookkeeping already recorded this one.
		opts["force"] = true
		play(event, opts)
	_sync_music()
