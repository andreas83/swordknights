class_name TimeOfDay
extends RefCounted
## The hours a level can be set at, as a grade over the one atlas and palette.
##
## docs/art-direction.md requires that re-lighting the world "stay a palette
## edit", and MatchDusk already walks one axis of it in the duel: a multiply
## over the world that keeps red and takes green and blue, with the sky
## painting its own dusk. The campaign walks the same axis by stops, and adds
## one endpoint past it for night (docs/campaign.md, "Time of day"):
##
## | Stop        | World multiply   | Sky dusk | Shadow reach | Sun            |
## | ----------- | ---------------- | -------- | ------------ | -------------- |
## | `afternoon` | none             | 0        | 3 tiles      | as it was      |
## | `golden`    | DUSK at 25%      | 0.25     | 3.5          |                |
## | `sunset`    | DUSK at 55%      | 0.6      | 4            |                |
## | `dusk`      | DUSK             | 1.0      | 5            |                |
## | `night`     | NIGHT            | night    | --           | none: no solve |
##
## A level says its hour with `;! time <stop>`, or with a number from 0 to 1
## for a point along the afternoon-to-dusk axis; none is the afternoon, the
## look the game has always had -- and for that, nothing here does anything at
## all. `;! horizon <row>` puts every row from that one down in the far city's
## shadow: one fill after the solve.
##
## The sun's *slope* is not a grade value and never will be: thin casters are
## two pixels wide because the lanes run at (2, 1), and any other integer slope
## would dot every balustrade's shadow (docs/world.md). Only the reach moves.
##
## WorldGrade applies the multiply and the sky; SunShadow.build() reads
## light_of() for the reach, the horizon and whether there is a sun.

const STOPS: Array[String] = ["afternoon", "golden", "sunset", "dusk", "night"]
const DEFAULT := "afternoon"

## The night's multiply: the world's crimson kept as a low violet, its gold
## taken almost to nothing -- the duotone still two tones, at a fraction of
## their light.
const NIGHT := Color(0.50, 0.30, 0.46)

## `world` is how far along MatchDusk.DUSK the world multiply goes, `sky` how
## far ParallaxSky.dusk does, `reach` the shadow's in tiles; night is its own.
const _GRADES := {
	"afternoon": {"label": "Late afternoon", "world": 0.0, "sky": 0.0, "reach": 3.0},
	"golden": {"label": "Golden hour", "world": 0.25, "sky": 0.25, "reach": 3.5},
	"sunset": {"label": "Sunset", "world": 0.55, "sky": 0.6, "reach": 4.0},
	"dusk": {"label": "Dusk", "world": 1.0, "sky": 1.0, "reach": 5.0},
	"night": {"label": "Night", "world": 1.0, "sky": 1.0, "reach": 0.0},
}


static func is_stop(name: String) -> bool:
	return _GRADES.has(name)


## Whether `word` is something `;! time` accepts: a stop, or a number from 0
## to 1 along the afternoon-to-dusk axis.
static func is_valid(word: String) -> bool:
	if is_stop(word):
		return true
	return word.is_valid_float() and float(word) >= 0.0 and float(word) <= 1.0


## The stop's name as the chapter select prints it.
static func label(stop: String) -> String:
	return String((_GRADES.get(stop, _GRADES[DEFAULT]) as Dictionary)["label"])


## The stop a level is set at: its `;! time` directive, or the default.
static func stop_of(level: AsciiLevel) -> String:
	if level == null:
		return DEFAULT
	var args: PackedStringArray = level.directive("time").get("args", PackedStringArray())
	if args.size() != 1 or not is_valid(args[0]):
		return DEFAULT
	return args[0]


## What the grade does to a level: `{world: Color, sky: float, night: float}`
## -- the multiply over the world, ParallaxSky.dusk and ParallaxSky.night.
static func grade_of(level: AsciiLevel) -> Dictionary:
	var stop := stop_of(level)
	if stop == "night":
		return {"world": NIGHT, "sky": 1.0, "night": 1.0}
	var world := 0.0
	var sky := 0.0
	if is_stop(stop):
		world = float(_GRADES[stop]["world"])
		sky = float(_GRADES[stop]["sky"])
	else:
		world = float(stop)
		sky = world
	return {"world": Color.WHITE.lerp(MatchDusk.DUSK, world), "sky": sky, "night": 0.0}


## True for a grade that changes nothing: the afternoon, the game as it was.
static func is_plain(grade: Dictionary) -> bool:
	var unlit := is_zero_approx(float(grade["sky"])) and is_zero_approx(float(grade["night"]))
	return unlit and grade["world"] == Color.WHITE


## The light the shadow solve works in: `{sun: bool, reach: float (tiles),
## horizon: int (row, -1 for none)}`.
static func light_of(level: AsciiLevel) -> Dictionary:
	var stop := stop_of(level)
	var horizon := -1
	if level != null:
		var args: PackedStringArray = level.directive("horizon").get("args", PackedStringArray())
		if args.size() == 1 and args[0].is_valid_int():
			horizon = int(args[0])
	if stop == "night":
		return {"sun": false, "reach": 0.0, "horizon": horizon}
	var reach := SunShadow.REACH_TILES
	if is_stop(stop):
		reach = float(_GRADES[stop]["reach"])
	else:
		reach = lerpf(float(_GRADES["afternoon"]["reach"]), float(_GRADES["dusk"]["reach"]),
			float(stop))
	return {"sun": true, "reach": reach, "horizon": horizon}
