extends SceneTree
## Gore is presentation: it never reaches the match's state, and it is bounded.
##
## scripts/duel/gore.gd promises both, and points here for the proof. The first
## matters because the match is checksummed: a presentation field that found
## its way into the snapshot would make the splatter pattern something two
## peers could diverge over, and a desync detector that fires on a blood spot
## is one nobody believes. The second is the reason gore is a list and not a
## render target (docs/duel-spec.md, engineering note 2), so the bound is the
## design and has to hold.
##
## A standalone SceneTree test like its siblings match_respawn_test and
## match_initiative_test, because the match steps inside physics frames and
## shares their harness.
##
##     godot --headless --path . --script res://tests/match_gore_test.gd

const Support := preload("res://tests/duel_support.gd")
const MANIFEST := "res://levels/duel_zones.txt"
const FRAMES := 240

## The files that make up the simulation. Not one of them may know gore exists.
const SIMULATION: Array[String] = [
	"res://scripts/duel/match.gd",
	"res://scripts/duel/match_sim.gd",
	"res://scripts/duel/match_seat.gd",
	"res://scripts/duel/zones.gd",
	"res://scripts/net/session.gd",
	"res://scripts/net/protocol.gd",
]

var _s := Support.new()
var _strip: ZoneStrip
var _warm := 0


func _initialize() -> void:
	_strip = ZoneStrip.from_manifest(MANIFEST)


func _physics_process(_delta: float) -> bool:
	_warm += 1
	if _warm < 3:
		return false
	if not _s.check(_strip != null, "the strip loads"):
		quit(_s.report("match_gore"))
		return true

	_the_simulation_does_not_name_gore()
	_spilling_does_not_move_the_checksum()
	_the_list_is_bounded()

	quit(_s.report("match_gore"))
	return true


## The cheap guard, and the one that names the file when it breaks.
func _the_simulation_does_not_name_gore() -> void:
	var pattern := RegEx.create_from_string("\\b(GoreField|gore\\.gd|spill\\s*\\()")
	for path: String in SIMULATION:
		var text := FileAccess.get_file_as_string(path)
		if not _s.check(not text.is_empty(), "%s is readable" % path):
			continue
		# Code only: match.gd's docstring names gore.gd to say it is NOT here.
		var code := PackedStringArray()
		for line: String in text.split("\n"):
			code.append(line.get_slice("#", 0))
		var hit := pattern.search("\n".join(code))
		_s.check(hit == null, "%s does not reach into gore%s" % [
			path, "" if hit == null else " (found '%s')" % hit.get_string()])


## Two matches, same inputs, frame for frame. One of them has a gore field
## taking a spill every frame and every death. Their state must not differ by
## a byte, and their checksums must not differ at all.
func _spilling_does_not_move_the_checksum() -> void:
	var plain := _open_match("Plain")
	var gory := _open_match("Gory")
	if plain == null or gory == null:
		return

	var field := GoreField.new()
	field.name = "Gore"
	root.add_child(field)
	field.setup(_strip)
	gory.fighter_died.connect(
		func(victim: int, _killer: int, at: Vector2) -> void:
			field.spill(at, victim, gory.frame))

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var diverged_at := -1
	for i: int in FRAMES:
		var a := rng.randi() & 0xff
		var b := rng.randi() & 0xff
		plain.step(a, b)
		gory.step(a, b)
		field.spill(gory.fighter_position(i % 2), i % 2, gory.frame)
		if diverged_at < 0 and (
				plain.checksum() != gory.checksum()
				or plain.write_state() != gory.write_state()):
			diverged_at = i

	_s.check(field.total() > 0, "the gore field actually received spills")
	_s.equal(diverged_at, -1, "%d frames with gore spilling: state and checksum identical"
		% FRAMES)

	field.queue_free()
	plain.queue_free()
	gory.queue_free()


## Far more spills than the bound allows, into every zone.
func _the_list_is_bounded() -> void:
	var field := GoreField.new()
	root.add_child(field)
	field.setup(_strip)
	var width := float(_strip.zone_width())
	var spills := GoreField.MAX_PER_ZONE * 4
	for zone: int in _strip.zone_count():
		for i: int in spills:
			var x := width * zone + fmod(float(i) * 7.3, width)
			field.spill(Vector2(x, 64.0), i % 2, i)
	for zone: int in _strip.zone_count():
		var n := field.count_in(zone)
		_s.check(n > 0, "zone %d kept some gore" % zone)
		_s.check(n <= GoreField.MAX_PER_ZONE,
			"zone %d holds %d decals, bound is %d" % [zone, n, GoreField.MAX_PER_ZONE])
	field.queue_free()


func _open_match(label: String) -> DuelMatch:
	var fight := DuelMatch.new()
	fight.name = label
	root.add_child(fight)
	if not _s.check(fight.build(_strip), "%s match builds" % label):
		return null
	while fight.phase == DuelMatch.Phase.COUNTDOWN:
		fight.step(0, 0)
	return fight
