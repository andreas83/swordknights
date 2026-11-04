extends GutTest
## The blood ramp (Palette.BLOOD, BLOOD_DRIED, BLOOD_WET) is blood's alone,
## blood is drawn in nothing else, and the ramp stays far enough from the
## world it is spilled on to be seen there.
##
## Three halves of one rule (docs/art-direction.md, "Colour discipline"):
##
## - Rationed. The ramp is named in palette.gd, scripts/duel/gore.gd and
##   scripts/world/bloodshed.gd and nowhere else in what ships -- scanned for
##   by name and by hex value, so a copied literal is caught as well as a
##   reference. A banner that borrowed the blood red would make a death harder
##   to read everywhere that banner hangs.
## - Exclusive. The two blood files name no other Palette tone and build no
##   colour of their own, and a spilled kill's decals and stains carry only
##   ramp tones. This is how the old blood, the architecture's own crimson,
##   would be caught coming back.
## - Visible. The numbers docs/art-direction.md gives are recomputed here, in
##   OKLab (Bjorn Ottosson's), against the stone as the world shader draws it
##   and against the same tones under every hour's multiply. Each threshold is
##   set a little under the value the ramp reaches, so a retune can move, but
##   not back into the stone.
##
## Seen to fail: with BLOOD set back to CLOTH_DARK's value, every contrast
## test goes red (the two-tone worst case falls from 17.0 to 11.2, the chroma
## margin goes negative, the hue gap to 1.5 degrees); with a `Palette.CLOTH`
## pool in gore.gd, the exclusive scan and the duel kill's decals do; with
## BLOOD named in scripts/duel/match_hud.gd, the rationed scan does.

const RAMP_FILES: Array[String] = [
	"res://scripts/core/palette.gd",
	"res://scripts/duel/gore.gd",
	"res://scripts/world/bloodshed.gd",
]
const DRAWERS: Array[String] = ["res://scripts/duel/gore.gd", "res://scripts/world/bloodshed.gd"]
const ROOTS: Array[String] = ["res://scripts", "res://scenes", "res://tools", "res://assets"]
const KINDS: Array[String] = ["gd", "gdshader", "tscn", "tres", "py"]

## Thresholds. OKLab distance is x 100: about 2 is just noticeable, 10 is
## plainly different, 20 is a glance.
## Whatever a mark lands on, one of its two tones is at least this far from it.
const TWO_TONE_MIN := 15.0
## BLOOD's chroma above the most saturated stone tone: the axis it is set
## apart on.
const CHROMA_MARGIN := 0.02
## BLOOD's hue from the crimson stone's, in degrees: red, not crimson.
const HUE_MIN := 12.0
## The glint against the mid and deep crimson, where BLOOD is weakest.
const GLINT_MIN := 15.0

const DUEL_STRIP := "res://levels/duel_zones.txt"


func _ramp() -> Array[Color]:
	return [Palette.BLOOD, Palette.BLOOD_DRIED, Palette.BLOOD_WET]


## The tones stone is drawn in: the duotone ramp, not the accents.
func _stone() -> Dictionary:
	return {
		"INK": Palette.INK, "SHADOW_PIT": Palette.SHADOW_PIT,
		"SHADOW_DEEP": Palette.SHADOW_DEEP, "SHADOW": Palette.SHADOW,
		"SHADOW_WARM": Palette.SHADOW_WARM, "MID": Palette.MID,
		"LIGHT_WARM": Palette.LIGHT_WARM, "LIGHT": Palette.LIGHT,
		"LIGHT_SOFT": Palette.LIGHT_SOFT,
	}


## The stone, and every stone tone under every hour's multiply: the duel's
## dusk and each stop of the campaign's grade, night included.
func _surfaces() -> Dictionary:
	var out := _stone()
	var hours := {"dusk": MatchDusk.DUSK, "night": TimeOfDay.NIGHT}
	for stop: String in ["golden", "sunset"]:
		var level := AsciiLevel.new()
		level.parse("; t\n;! time %s\n#\n" % stop)
		hours[stop] = TimeOfDay.grade_of(level)["world"]
	for hour: String in hours:
		var k: Color = hours[hour]
		for name: String in _stone():
			var c: Color = _stone()[name]
			out["%s x %s" % [name, hour]] = Color(c.r * k.r, c.g * k.g, c.b * k.b)
	return out


## --- rationed ----------------------------------------------------------------

func test_only_the_blood_files_name_the_ramp() -> void:
	var by_name := RegEx.create_from_string("\\bBLOOD(_DRIED|_WET)?\\b")
	var hexes: Array[String] = []
	for tone: Color in _ramp():
		hexes.append(tone.to_html(false).to_lower())
	var scanned := 0
	var named_in: Array[String] = []
	var strays: Array[String] = []
	for root: String in ROOTS:
		for path: String in _files(root):
			scanned += 1
			var text := FileAccess.get_file_as_string(path)
			var lower := text.to_lower()
			var hit := by_name.search(text) != null
			for hex: String in hexes:
				hit = hit or lower.contains(hex)
			if not hit:
				continue
			named_in.append(path)
			if not RAMP_FILES.has(path):
				strays.append(path)
	assert_gt(scanned, 100, "the scan read the project (%d files)" % scanned)
	for path: String in RAMP_FILES:
		assert_has(named_in, path, "the scan finds the ramp where it is meant to be")
	assert_eq(strays, [] as Array[String], "nothing else names the blood ramp")


## --- exclusive ---------------------------------------------------------------

func test_the_blood_files_draw_with_the_ramp_and_nothing_else() -> void:
	var other_tone := RegEx.create_from_string("Palette\\.(?!BLOOD(_DRIED|_WET)?\\b)\\w+")
	var made := RegEx.create_from_string("\\bColor8?\\s*\\(|\\bColor\\.(?!WHITE\\b)[A-Z]")
	for path: String in DRAWERS:
		var text := FileAccess.get_file_as_string(path)
		assert_gt(text.length(), 0, "%s read" % path)
		var lines := text.split("\n")
		for i: int in lines.size():
			var line := lines[i]
			if line.strip_edges().begins_with("#"):
				continue
			var tone := other_tone.search(line)
			assert_null(tone, "%s:%d draws with %s" % [
				path, i + 1, tone.get_string() if tone != null else ""])
			var colour := made.search(line)
			assert_null(colour, "%s:%d makes a colour of its own: %s" % [
				path, i + 1, line.strip_edges()])


func test_a_duel_kill_is_only_ramp_tones() -> void:
	var field := GoreField.new()
	add_child_autofree(field)
	field.setup(ZoneStrip.from_manifest(DUEL_STRIP))
	var strip := field.strip
	var seen := 0
	for slot: int in 2:
		for blow: int in [-1, 0, 1]:
			var x := strip.zone_left(2) + strip.zone_width() * (0.3 + 0.2 * (blow + 1))
			var at := Vector2(x, strip.ground_row(floori(x / ZoneStrip.TILE)) * ZoneStrip.TILE)
			field.spill(at, slot, 300 + slot * 50 + blow, blow)
	for lists: Array[Array] in [field._marks, field._drops]:
		for list: Array in lists:
			for decal: Dictionary in list:
				for key: String in ["colour", "dried", "sheen"]:
					if decal.has(key):
						seen += 1
						assert_has(_ramp(), decal[key] as Color, "a %s's %s" % [
							decal.get("kind", "droplet"), key])
				for tone: Color in decal.get("tones", PackedColorArray()):
					seen += 1
					assert_has(_ramp(), tone, "a droplet's stain")
	assert_gt(seen, 100, "the kills' decals were all looked at (%d)" % seen)


func test_an_adventure_kill_is_only_ramp_tones() -> void:
	var data := AsciiLevel.new()
	data.parse("; Blood Floor\n\n\n\n\n\n\n  t @         #\n##############\n")
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Game
	game.level_source = data
	add_child_autofree(game)
	await wait_physics_frames(3)
	var blood := game.blood
	var floor_y := 8.0 * Level.TILE
	blood.burst(Vector2(120.0, floor_y - 12.0), 1.0, Bloodshed.KILL_DROPS)
	blood.burst(Vector2(120.0, floor_y - 12.0), -1.0, Bloodshed.KILL_DROPS)
	blood.pool(Vector2(120.0, floor_y - 2.0), Bloodshed.POOL_MAX)
	await wait_physics_frames(100)
	assert_gt(blood.stain_count(), 10, "the bursts landed")
	assert_eq(blood.pool_count(), 1, "and the pool is down")
	var colours := blood.stain_colours()
	assert_gt(colours.size(), 1, "in two tones")
	for colour: Color in colours:
		assert_has(_ramp(), colour, "a stain is a ramp tone")


## --- visible -----------------------------------------------------------------

func test_every_surface_is_far_from_one_of_the_two_tones() -> void:
	var surfaces := _surfaces()
	assert_gt(surfaces.size(), 40, "the stone and the graded stone (%d)" % surfaces.size())
	var worst := INF
	var worst_name := ""
	for name: String in surfaces:
		var tone: Color = surfaces[name]
		var best := maxf(_de(Palette.BLOOD, tone), _de(Palette.BLOOD_DRIED, tone))
		if best < worst:
			worst = best
			worst_name = name
	assert_gte(worst, TWO_TONE_MIN, "the nearest surface, %s, is %.1f from the blood's best tone"
		% [worst_name, worst])


## In a level the hour lands on the blood and on the stone alike (WorldGrade:
## the canvas multiply on the one, the world shader's tint on the other), so
## what the eye compares at each hour is the blood graded beside the stone
## graded. The two-tone rule holds there too, hour by hour, scaled by the
## light the hour leaves: a contrast is seen in the light there is.
func test_graded_alike_the_blood_still_stands_off_the_stone() -> void:
	var hours := {"dusk": MatchDusk.DUSK, "night": TimeOfDay.NIGHT}
	for stop: String in ["golden", "sunset"]:
		var level := AsciiLevel.new()
		level.parse("; t\n;! time %s\n#\n" % stop)
		hours[stop] = TimeOfDay.grade_of(level)["world"]
	for hour: String in hours:
		var k: Color = hours[hour]
		var worst := INF
		var worst_name := ""
		for name: String in _stone():
			var tone: Color = _stone()[name] * k
			var best := maxf(_de(Palette.BLOOD * k, tone), _de(Palette.BLOOD_DRIED * k, tone))
			if best < worst:
				worst = best
				worst_name = name
		gut.p("%s: the nearest graded stone, %s, is %.1f off" % [hour, worst_name, worst])
		assert_gte(worst, TWO_TONE_MIN * clampf(k.get_luminance(), 0.0, 1.0),
			"%s: %s graded is %.1f from the blood graded" % [hour, worst_name, worst])


func test_blood_is_set_apart_by_chroma_and_hue() -> void:
	var most := 0.0
	for tone: Color in _stone().values():
		most = maxf(most, _lch(tone).y)
	var blood := _lch(Palette.BLOOD)
	assert_gte(blood.y - most, CHROMA_MARGIN,
		"BLOOD's chroma %.3f against the stone's most, %.3f" % [blood.y, most])
	for name: String in ["SHADOW_PIT", "SHADOW_DEEP", "SHADOW"]:
		var gap := _hue_gap(blood.z, _lch(_stone()[name]).z)
		assert_gte(gap, HUE_MIN, "BLOOD is %.1f degrees of hue from %s" % [gap, name])


func test_the_glint_reads_where_the_body_is_weakest() -> void:
	for name: String in ["SHADOW", "SHADOW_DEEP"]:
		var gap := _de(Palette.BLOOD_WET, _stone()[name])
		assert_gte(gap, GLINT_MIN, "BLOOD_WET is %.1f from %s" % [gap, name])


func test_the_old_blood_would_fail_this() -> void:
	# The guard is only trusted if the colours it replaced do not pass it.
	var worst := INF
	for tone: Color in _surfaces().values():
		worst = minf(worst, maxf(_de(Palette.CLOTH_DARK, tone), _de(Palette.SHADOW_PIT, tone)))
	assert_lt(worst, TWO_TONE_MIN, "the cloth crimson and the pit: %.1f" % worst)
	assert_lt(_hue_gap(_lch(Palette.CLOTH_DARK).z, _lch(Palette.SHADOW).z), HUE_MIN,
		"and crimson's hue is the stone's")


## --- OKLab -------------------------------------------------------------------

## OKLab distance, x 100.
static func _de(a: Color, b: Color) -> float:
	return (_oklab(a) - _oklab(b)).length() * 100.0


## (L, C, h in degrees).
static func _lch(c: Color) -> Vector3:
	var lab := _oklab(c)
	return Vector3(lab.x, Vector2(lab.y, lab.z).length(),
		fposmod(rad_to_deg(atan2(lab.z, lab.y)), 360.0))


static func _hue_gap(a: float, b: float) -> float:
	var d := fposmod(absf(a - b), 360.0)
	return minf(d, 360.0 - d)


static func _oklab(c: Color) -> Vector3:
	var r := _linear(c.r)
	var g := _linear(c.g)
	var b := _linear(c.b)
	var l := pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m := pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s := pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


static func _files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file: String in dir.get_files():
		if KINDS.has(file.get_extension()):
			out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		out.append_array(_files(dir_path.path_join(sub)))
	return out
