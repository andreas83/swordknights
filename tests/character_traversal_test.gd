extends SceneTree
## Plays the feel lab with a scripted bot and asserts every station is clearable.
##
## The grammar test pins the numbers; this one pins the consequence. It drives
## the real Player through the real level with the real physics, so a retune
## that makes a 4-tile wall ungrabbable or a 3-tile gap uncrossable fails here
## even though every constant still looks reasonable in isolation.
##
##     godot --headless --script tests/character_traversal_test.gd
##
## The bot is deliberately stupid — hold right, jump at a wall, jump at a gap,
## climb a ladder, mantle a ledge. If a station needs more cleverness than
## that, it is too fiddly to be canonical.

const LAB := "res://scenes/feel_lab.tscn"
const TIMEOUT := 60.0
## A full-height jump needs the button held past the apex — release it early
## and JUMP_CUT_MULTIPLIER takes most of the rise away, which is exactly what
## stops the bot reaching a 4-tile ledge.
const JUMP_HOLD := 20
## Frames the button must be up again before the next press counts as one.
const JUMP_RELEASE := 3

var _game: Game
var _player: Player
var _level: Level
var _bot: Bot

var _elapsed := 0.0
var _furthest := 0.0
var _deaths := 0
var _seen := {}
var _failures := 0
var _done := false

## Each station is "the player stood here, at this height". The x is where the
## station is cleared, the y the surface it is cleared onto.
var _stations: Array[Dictionary] = [
	{"name": "2-tile hop", "x": 200.0, "top": 240.0},
	{"name": "3-tile platform step", "x": 360.0, "top": 224.0},
	{"name": "4-tile grab wall", "x": 560.0, "top": 208.0},
	{"name": "3-tile gap", "x": 740.0, "top": 208.0},
	{"name": "drop off the wall", "x": 864.0, "top": 272.0},
	{"name": "ladder to the terrace", "x": 960.0, "top": 160.0},
	{"name": "drop off the terrace", "x": 1136.0, "top": 272.0},
	{"name": "the exit", "x": 1370.0, "top": 272.0},
]


func _initialize() -> void:
	var packed := load(LAB) as PackedScene
	if packed == null:
		_fail("could not load " + LAB)
		_finish()
		return
	_game = packed.instantiate() as Game
	root.add_child(_game)


## The scene's own _ready() has not run while _initialize() is still going,
## so the bot is installed on the first tick instead. One frame of the default
## input before it takes over does nothing: the character starts at rest.
func _setup() -> bool:
	_player = _game.player
	_level = _game.level
	if _player == null or _level == null:
		_fail("the lab scene came up without a player or a level")
		return false
	_bot = Bot.new()
	_bot.level = _level
	_player.input = _bot
	_player.died.connect(func() -> void: _deaths += 1)
	return true


func _physics_process(delta: float) -> bool:
	if _done:
		return false
	if _bot == null and not _setup():
		_finish()
		return false
	_elapsed += delta
	_bot.decide(_player)
	_furthest = maxf(_furthest, _player.position.x)

	if _player.is_on_floor():
		for station: Dictionary in _stations:
			var name: String = station["name"]
			if _seen.has(name):
				continue
			if _player.position.x >= station["x"] \
					and absf(_player.position.y - float(station["top"])) < 2.0:
				_seen[name] = _elapsed

	# Physics steps at wall-clock 60 Hz even headless, so this test takes about
	# as long to run as it does to play. The trace is so a stuck bot is
	# diagnosable without waiting for the timeout.
	if int(_elapsed * 2.0) != int((_elapsed - delta) * 2.0) and int(_elapsed * 2.0) % 10 == 0:
		print("  %4.1fs  x=%-6.0f y=%-5.0f %s" % [_elapsed, _player.position.x,
			_player.position.y, Player.State.keys()[_player.state]])

	if _game.phase == Game.Phase.COMPLETE or _elapsed > TIMEOUT:
		_report()
		_finish()
	return false


func _process(_delta: float) -> bool:
	return _done


func _report() -> void:
	for station: Dictionary in _stations:
		var name: String = station["name"]
		if _seen.has(name):
			print("  ok    %-24s at %.1fs" % [name, _seen[name]])
		else:
			_fail("%s was never cleared (got as far as x=%.0f in %.1fs)"
				% [name, _furthest, _elapsed])
	if _deaths > 0:
		_fail("the bot died %d time(s) crossing the lab" % _deaths)
	if _game.phase != Game.Phase.COMPLETE:
		_fail("the bot never reached the exit")


func _finish() -> void:
	_done = true
	if _failures > 0:
		printerr("character_traversal_test: %d failure(s)" % _failures)
		quit(1)
		return
	print("character_traversal_test: ok (%.1fs of play)" % _elapsed)
	quit(0)


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FAIL  " + message)


## Hold right; jump at a wall; jump at a gap; climb what cannot be jumped;
## pull up from a hang. Nothing in the level may need more than this.
class Bot:
	extends PlayerInput

	var level: Level
	var _jump_frames := 0

	func decide(player: Player) -> void:
		var bits := PlayerInput.BIT_RIGHT
		var feet := player.position

		if player.state == Player.State.HANG:
			bits |= PlayerInput.BIT_UP # mantle
		elif player.state == Player.State.LADDER:
			bits |= PlayerInput.BIT_UP
		elif player.is_on_floor():
			if _wall_ahead(feet) and _climbable(player):
				bits |= PlayerInput.BIT_UP
			elif _wall_ahead(feet) or _platform_ahead(feet) or _gap_ahead(feet):
				if _jump_frames <= -JUMP_RELEASE:
					_jump_frames = JUMP_HOLD

		if _jump_frames > 0:
			bits |= PlayerInput.BIT_JUMP
		_jump_frames = maxi(_jump_frames - 1, -JUMP_RELEASE)

		apply_bits(bits)

	func poll() -> void:
		pass # the bits are pushed in, not pulled

	## Something solid within a stride, at shin or hip height.
	func _wall_ahead(feet: Vector2) -> bool:
		for probe: float in [-4.0, -12.0]:
			if level.is_solid_at(Vector2(feet.x + 11.0, feet.y + probe)):
				return true
		return false

	## A one-way platform ahead and above: the only way up a 3-tile rise.
	func _platform_ahead(feet: Vector2) -> bool:
		for ahead: float in [10.0, 22.0]:
			for up: float in [-22.0, -34.0]:
				if level.kind_at_world(Vector2(feet.x + ahead, feet.y + up)) == Tiles.Kind.PLATFORM:
					return true
		return false

	## No floor under the next step, but floor again three tiles on: a gap to	## cross rather than a ledge to walk off.
	func _gap_ahead(feet: Vector2) -> bool:
		if level.is_solid_at(Vector2(feet.x + 6.0, feet.y + 4.0)):
			return false
		return level.is_solid_at(Vector2(feet.x + 54.0, feet.y + 4.0))

	func _climbable(player: Player) -> bool:
		return level != null and level.rect_is_climbable(player.body_rect())
