extends GutTest
## Blades on the beat (scripts/mechanisms/beat_blade.gd, scythe.gd,
## spike_slot.gd) and their timing proof (scripts/mechanisms/beat_proof.gd),
## held to docs/campaign.md, "Blades on the beat".
##
## What is pinned:
##
## - a blade cuts on physics frame 100k + its phase -- off the bus, the
##   physics step, so a display running at any rate cuts on the same frames --
##   and never on a frame no tell came before;
## - the tell is the sentinel's 27 frames, through warn(): the assist widens it
##   into the rest and leaves the cut, the beat and the opening where they were;
## - every tell is heard on its own frames, and the Well's escapement knocks
##   once a beat however many blades are on screen;
## - a scythe cuts the prince once a pass and throws him from where it hangs;
##   a slot is spikes exactly while it is up, and kills like them;
## - the proof measures the bible's numbers (a scythe's 17-frame crossing and
##   74-frame window, two slots' 28 and 42), refuses a window under the
##   parry's 12, a run without the races' slack, and a blade on a wire that
##   does not keep the music's time;
## - a scythe cut into a ladder shaft climbs like the ladder.

const GAME_SCENE := "res://scenes/game.tscn"
const DeathWatch := preload("res://tests/death_watch.gd")

## A doorway scythe on the beat and two slots off it, on one floor.
const ROOM := """;! channel 4 beat 0
;! channel 5 beat 50
; Blade Room

##################
##################
#####4############
     z
  @  z     ii     D
###########5######
##################
"""

## A prince standing on two slots that come up on the off-beat.
const ON_THE_SLOTS := """;! channel 5 beat 50
; On The Slots



   i@
   5#           D
#################
"""


class Ear extends RefCounted:
	## "frame voice" for every cue heard.
	var heard: Array[String] = []
	var bus: ChannelBus

	func hear(voice: StringName, options: Dictionary) -> void:
		var tag := "" if options.get("vary", true) else " knock"
		heard.append("%d %s%s" % [bus.frame, voice, tag])


func before_each() -> void:
	Assist.reset()


func after_each() -> void:
	Assist.reset()
	Engine.max_fps = 0


func _bus() -> ChannelBus:
	var bus := ChannelBus.new()
	bus.configure(&"4", {"mode": "beat", "phase": 0, "period": 100})
	bus.configure(&"5", {"mode": "beat", "phase": 50, "period": 100})
	return bus


## `blade` placed on bare cells, with no level: the clock, the cues and the
## cut need nothing else.
func _place(blade: BeatBlade, cells: Array[Vector2i], channel: String,
		bus: ChannelBus) -> BeatBlade:
	var site := EntitySite.new()
	site.cell = cells[cells.size() - 1]
	site.cells = cells
	site.params = {"channel": channel}
	site.at = Vector2(site.cell) * 16.0 + Vector2(8.0, 16.0)
	site.bus = bus
	blade.place(site)
	autofree(blade)
	return blade


func _scythe(bus: ChannelBus, channel: String = "4") -> Scythe:
	return _place(Scythe.new(), [Vector2i(5, 4), Vector2i(5, 5)] as Array[Vector2i], channel,
		bus) as Scythe


func _slots(bus: ChannelBus, channel: String = "5") -> SpikeSlot:
	return _place(SpikeSlot.new(), [Vector2i(11, 5), Vector2i(12, 5)] as Array[Vector2i],
		channel, bus) as SpikeSlot


func _contact(body: Rect2 = Rect2()) -> Contact:
	var contact := Contact.new()
	contact.body = body
	contact.alive = true
	return contact


## Steps the bus and meets each blade, `frames` times. Returns, per blade, the
## bus frames its cut went live on.
func _run(bus: ChannelBus, blades: Array[BeatBlade], frames: int) -> Array[Array]:
	var out: Array[Array] = []
	var was: Array[bool] = []
	for blade: BeatBlade in blades:
		out.append([])
		was.append(blade.is_live())
	var contact := _contact()
	for _frame: int in frames:
		bus.step()
		for i: int in blades.size():
			blades[i].meet(contact)
			if blades[i].is_live() and not was[i]:
				out[i].append(bus.frame)
			was[i] = blades[i].is_live()
	return out


func _level(text: String) -> AsciiLevel:
	var level := AsciiLevel.new()
	level.parse(text)
	assert_eq(level.problems, PackedStringArray(), "%s parses clean" % level.name)
	return level


## --- the clock ------------------------------------------------------------------

func test_a_blade_cuts_on_frame_one_hundred_k_plus_its_phase() -> void:
	var bus := _bus()
	var cuts := _run(bus, [_scythe(bus, "4"), _slots(bus, "5")] as Array[BeatBlade], 360)
	assert_eq(cuts[0], [100, 200, 300], "on the beat: 100k")
	assert_eq(cuts[1], [50, 150, 250, 350], "off the beat: 100k + 50")


func test_the_first_cut_waits_for_a_whole_tell() -> void:
	var bus := _bus()
	var scythe := _scythe(bus, "4")
	assert_false(scythe.is_live(), "frame 0 is a cut on the clock, but nothing told it")
	var cuts := _run(bus, [scythe] as Array[BeatBlade], 99)
	assert_eq(cuts[0], [], "so the first cut is the one a tell came before")


## The display's rate is not the simulation's: with the frame rate pinned
## far from 60, several physics steps run per drawn frame, and the cuts still
## land on the same physics frames.
func test_the_cut_keeps_the_physics_clock_whatever_the_display_does() -> void:
	Engine.max_fps = 17
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_source = _level(ROOM)
	add_child_autofree(game)
	await wait_physics_frames(2)
	var scythe: Scythe = null
	for node: Node in game.get_node("Entities").get_children():
		if node is Scythe:
			scythe = node as Scythe
	assert_not_null(scythe, "the scythe is placed")
	var lives: Array[int] = []
	var was := scythe.is_live()
	for _step: int in 260:
		await wait_physics_frames(1)
		if scythe.is_live() and not was:
			lives.append(game._bus.frame)
		was = scythe.is_live()
	Engine.max_fps = 0
	assert_gt(lives.size(), 1, "it cut more than once")
	for frame: int in lives:
		assert_eq(frame % BeatBlade.PERIOD, 0, "every cut on a physics frame 100k: %d" % frame)


## --- the tell and the assist ----------------------------------------------------

func test_the_tell_is_the_sentinels_and_the_assist_widens_only_it() -> void:
	var bus := _bus()
	var scythe := _scythe(bus)
	assert_eq(scythe.tell_frames(), 27, "Patrol.WINDUP_TIME: the game's one tell")
	var ear := Ear.new()
	ear.bus = bus
	scythe.cue.connect(ear.hear)
	var plain := _run(bus, [scythe] as Array[BeatBlade], 110)

	Assist.load_saved(UserData.at("user://test_blades_assist.cfg"))
	Assist.set_longer_warnings(true)
	var wide_bus := _bus()
	var wide := _scythe(wide_bus)
	assert_eq(wide.tell_frames(), roundi(27.0 * Assist.LONGER), "41 frames with the assist on")
	var wide_ear := Ear.new()
	wide_ear.bus = wide_bus
	wide.cue.connect(wide_ear.hear)
	var assisted := _run(wide_bus, [wide] as Array[BeatBlade], 110)
	var assist_file := UserData.at("user://test_blades_assist.cfg")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(assist_file))

	assert_eq(assisted, plain, "the cut is still on the beat")
	assert_eq(wide.live(), scythe.live(), "and as long")
	assert_eq(_first_tick(wide_ear.heard), 100 - 41, "the ratchet starts 41 frames ahead")
	assert_eq(_first_tick(ear.heard), 100 - 27, "where it started 27 ahead")


func _first_tick(heard: Array[String]) -> int:
	for cue: String in heard:
		if cue.ends_with(" ladder") and not cue.ends_with("knock"):
			return int(cue.split(" ")[0])
	return -1


func test_every_tell_is_heard_on_its_own_frames() -> void:
	var bus := _bus()
	var scythe := _scythe(bus, "4")
	var slots := _slots(bus, "5")
	var ear := Ear.new()
	ear.bus = bus
	scythe.cue.connect(ear.hear)
	slots.cue.connect(ear.hear)
	_run(bus, [scythe, slots] as Array[BeatBlade], 101)
	var expected: Array[String] = [
		"23 ladder", "32 ladder", "41 ladder",   # the slots rattle three times
		"50 ladder knock",                        # the Well's escapement, once
		"50 masonry", "50 sword_hit",             # and they come up on the off-beat
		"73 ladder", "82 ladder", "91 ladder",   # the scythe's ratchet
		"100 sword",                              # and its cut, on the beat
		"100 ladder knock",
	]
	assert_eq(ear.heard, expected, "every threat heard, on the frames it happens")


## --- what a cut does ------------------------------------------------------------

func test_a_scythe_cuts_once_a_pass_and_throws_him_from_where_it_hangs() -> void:
	var bus := _bus()
	var scythe := _scythe(bus)
	var hurts: Array[float] = []
	var contact := _contact(Rect2(Vector2(5.0 * 16.0 + 2.0, 4.0 * 16.0 + 10.0),
		Vector2(Tuning.BODY_WIDTH, Tuning.BODY_HEIGHT)))
	contact.harmed = func(hearts: int, from_x: float) -> bool:
		assert_eq(hearts, 1, "a blade is a blade: one heart")
		hurts.append(from_x)
		return true
	for _frame: int in 210:
		bus.step()
		scythe.meet(contact)
	assert_eq(hurts.size(), 2, "once on each of the two passes, not once a live frame")
	assert_eq(hurts[0], 5.0 * 16.0 + 8.0, "from a lintel: from the doorway's middle")
	var run: Array[Vector2i] = [Vector2i(3, 2), Vector2i(3, 3)]
	assert_eq(Scythe.mount_of(run, Vector2i(2, 2)), Scythe.Mount.WALL_LEFT)
	assert_eq(Scythe.pivot_x(run, Scythe.Mount.WALL_LEFT), 48.0, "from a wall: from the wall")
	assert_eq(Scythe.mount_of(run, Vector2i(4, 3)), Scythe.Mount.WALL_RIGHT)
	assert_eq(Scythe.pivot_x(run, Scythe.Mount.WALL_RIGHT), 64.0)
	assert_eq(Scythe.mount_of(run, Vector2i(3, 1)), Scythe.Mount.LINTEL)


func test_a_slot_is_spikes_exactly_while_it_is_up() -> void:
	var bus := _bus()
	var slots := _slots(bus, "5")
	var spiked := 0
	var drawn := 0
	for _frame: int in 200:
		bus.step()
		slots.meet(_contact())
		if slots.current_kind() == Tiles.Kind.SPIKES:
			spiked += 1
			assert_true(slots.is_live(), "spikes only while it is up")
		if slots.spike_height() >= SpikeSlot.SPIKE_H:
			drawn += 1
			assert_eq(slots.current_kind(), Tiles.Kind.SPIKES, "drawn full only while it kills")
	assert_eq(spiked, 2 * SpikeSlot.UP, "thirty frames up, twice")
	assert_gt(drawn, 0, "and it was drawn up")


func test_a_slot_coming_up_kills_like_spikes() -> void:
	DeathWatch.expect_deaths(1)
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.level_source = _level(ON_THE_SLOTS)
	add_child_autofree(game)
	await wait_physics_frames(2)
	game.player.position = Vector2(3.0 * 16.0 + 8.0, 4.0 * 16.0)
	for _frame: int in 70:
		await wait_physics_frames(1)
		if not game.player.is_alive():
			break
	assert_false(game.player.is_alive(), "standing on the slot when it came up")
	assert_almost_eq(game._bus.frame, 51, 2, "on the off-beat, frame 50")


## --- the escapement ------------------------------------------------------------

func test_the_escapement_knocks_once_a_beat_however_many_blades() -> void:
	var bus := _bus()
	var blades: Array[BeatBlade] = []
	var ear := Ear.new()
	ear.bus = bus
	for i: int in 4:
		var blade := _scythe(bus, "4" if i % 2 == 0 else "5")
		blade.cue.connect(ear.hear)
		blades.append(blade)
	_run(bus, blades, 200)
	var knocks := ear.heard.filter(func(cue: String) -> bool: return cue.ends_with("knock"))
	assert_eq(knocks, ["50 ladder knock", "100 ladder knock", "150 ladder knock",
		"200 ladder knock"], "one knock a beat, four blades or one")


## --- the proof ------------------------------------------------------------------

func test_the_proof_measures_the_bibles_windows() -> void:
	var proof := BeatProof.prove(_level(ROOM))
	assert_true(bool(proof["ok"]), "the room proves: %s" % [proof["problems"]])
	var blades: Array[Dictionary] = []
	blades.assign(proof["blades"])
	assert_eq(blades.size(), 2, "both blades were found through their hooks")
	var scythe := blades[0] if String(blades[0]["kind"]) == "scythe" else blades[1]
	var slots := blades[1] if scythe == blades[0] else blades[0]
	assert_almost_eq(float(scythe["crossing"]), 17.0, 0.1, "a scythe's cell crossed in 17")
	assert_almost_eq(float(scythe["window"]), 74.0, 0.1, "and 74 frames to set off in")
	assert_almost_eq(float(slots["crossing"]), 28.0, 0.1, "two slots crossed in 28")
	assert_almost_eq(float(slots["window"]), 42.0, 0.1, "and 42 to set off in")
	var runs: Array[Dictionary] = []
	runs.assign(proof["runs"])
	assert_eq(runs.size(), 1, "close enough to be one rhythm")
	assert_gte(float(runs[0]["east"]), BeatProof.SLACK * BeatProof.PERIOD, "run east")
	assert_gte(float(runs[0]["west"]), BeatProof.SLACK * BeatProof.PERIOD, "and west")


func test_a_window_under_the_parrys_is_refused() -> void:
	var four := ";! channel 5 beat 50\n; Four\n\n\n  @  iiii     D\n#####5#########\n"
	var five := ";! channel 5 beat 50\n; Five\n\n\n  @  iiiii    D\n#####5#########\n"
	assert_true(bool(BeatProof.prove(_level(four))["ok"]), "four slots leave 20 frames")
	var proof := BeatProof.prove(_level(five))
	assert_false(bool(proof["ok"]), "five leave nine: under the parry's twelve")
	assert_string_contains(String(proof["problems"][0]), "under the parry's 12")


func test_a_run_without_the_races_slack_is_refused() -> void:
	var text := ";! channel 4 beat 0\n; Crowded\n\n\n  @  ii ii    D\n#####4##4######\n"
	var proof := BeatProof.prove(_level(text))
	assert_false(bool(proof["ok"]), "two pairs on one beat a tile apart cannot be run")
	for blade: Dictionary in proof["blades"]:
		assert_gte(float(blade["window"]), 12.0, "though each alone has its window")
	assert_string_contains(String(proof["problems"][0]), "less than 25% of the beat's period")


func test_a_blade_that_keeps_no_beat_is_refused() -> void:
	var held := ";! channel 4 hold 1.0\n; Held\n\n\n  @  ii   D\n#####4#####\n"
	assert_string_contains(String(BeatProof.prove(_level(held))["problems"][0]), "not a beat")
	var odd := ";! channel 4 beat 0 period=120\n; Odd\n\n\n  @  ii   D\n#####4#####\n"
	assert_string_contains(String(BeatProof.prove(_level(odd))["problems"][0]),
		"not the music's 100")


func test_a_scythe_in_a_ladder_shaft_climbs_like_the_ladder() -> void:
	var text := """;! channel 4 beat 0
; Shaft

  @  H#
#####H#
#####H#
####4z#
#####z#
#    H#
#  D H#
#######
"""
	var level := _level(text)
	var cells: Array[Vector2i] = [Vector2i(5, 4), Vector2i(5, 5)]
	assert_true(Scythe.in_ladder(cells, level), "rungs over it and under it")
	var kinds := ReachModel.for_level(level).kinds_for(0)
	for cell: Vector2i in cells:
		assert_eq(kinds.get(cell), Tiles.Kind.LADDER, "%s climbs, to the proof" % cell)
	assert_true(bool(LevelReachability.verify(level)["ok"]), "so the shaft is a way down")
	var proof := BeatProof.prove(level)
	assert_eq(String(proof["blades"][0]["way"]), "ladder", "crossed at the ladder's speed")


## The throat's rule, refused: two scythes from opposite walls on the same
## beat, a course apart, both reach a rider at once -- one cut asks him to be
## on the left half and the other on the right, in the same frame. (A row of
## travel between them keeps the shaft one lift: diagonal cells are not a run.)
func test_a_ride_that_asks_for_two_answers_at_once_is_refused() -> void:
	var text := """;! channel 4 beat 0
; Bad Ride
#######
#@    #
###[]##
###''##
###''##
##4z'##
###z'##
###''##
###'z4#
###'z##
###''D#
###''##
#######
"""
	var proof := BeatProof.prove(_level(text))
	assert_false(bool(proof["ok"]), "the ride cannot be danced")
	assert_eq(String(proof["blades"][0]["way"]), "ride", "both blades are ridden past")
	assert_lt(float(proof["rides"][0]["gap"]), BeatProof.NO_TWO_ANSWERS, "the cuts collide")
	assert_string_contains(String(proof["problems"][0]), "two cuts from opposite walls")
	var fixed := text.replace(";! channel 4 beat 0", ";! channel 4 beat 0\n;! channel 5 beat 50") \
		.replace("###'z4#", "###'z5#")
	var alternate := BeatProof.prove(_level(fixed))
	assert_true(bool(alternate["ok"]), "on alternate beats the same shaft is a dance: %s"
		% [alternate["problems"]])
