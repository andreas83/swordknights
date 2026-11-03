class_name TimeOfDay
extends RefCounted
## The hours a level can be set at, as a grade over the one atlas and palette.
##
## docs/art-direction.md requires that re-lighting the world "stay a palette
## edit", and MatchDusk already walks one axis of it in the duel: a multiply
## over the world that keeps red and takes green and blue, with the sky
## painting its own dusk. The campaign walks the same axis, by stops, and adds
## one endpoint past it for night (docs/campaign.md, "Time of day"):
##
## | Stop        | World multiply   | Sky dusk | Shadow reach | Sun          |
## | ----------- | ---------------- | -------- | ------------ | ------------ |
## | `afternoon` | none             | 0        | 3 tiles      | as it was    |
## | `golden`    | DUSK at 25%      | 0.25     | 3.5          |              |
## | `sunset`    | DUSK at 55%      | 0.6      | 4            |              |
## | `dusk`      | DUSK             | 1.0      | 5            |              |
## | `night`     | NIGHT            | night    | --           | none at all  |
##
## A level says its hour with `;! time <stop>`, or with a number from 0 to 1
## for a point along the afternoon-to-dusk axis; none is afternoon, which is
## the look the game has always had. `;! horizon <row>` puts every row below
## it in the city's shadow. WorldGrade applies all of it.

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
