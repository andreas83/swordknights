extends GutHookScript
## Fails any GUT test in which the prince dies without the test having said
## he would. Installed for the whole run as GUT's pre-run hook
## (.gutconfig.json, "pre_run_script"), so no test opts in and none can forget.
##
## Why it exists: `Game` answers a death with a checkpoint respawn -- full
## health, back on the floor at the last torch, guards reset (Game._respawn()).
## A test that plays a level and then asserts "alive", "whole" or "on the
## floor" is satisfied just as well by a prince who died and came back as by
## one who never died. Two backstep tests, one for spikes and one for a cut
## from behind, passed that way until they were fixed by hand. A per-test
## `assert_eq(_game.deaths, 0)` is the symptom fixed; this is the guard.
##
## Why a hook and not a base class or a helper: a helper is a convention, and
## the failure it guards against is exactly a test that did not know it needed
## guarding. The hook listens to the scene tree for every Player that enters a
## Game -- whichever way the test built it, generated, hand-written or the
## Endless wrapper -- and counts `died`, which fires once per death and which,
## unlike Game.deaths, a restart does not reset.
##
## Why it fails at the moment of death and not at teardown: the failure then
## carries where and on which physics frame it happened, while the respawn has
## not yet moved the body. Fewer deaths than were expected is only knowable at
## the end, so that is checked when GUT reports the test over (`end_test`,
## after `after_each`), which no test can override.
##
## A test that means the prince to die says so, with the exact count:
##
##     const DeathWatch := preload("res://tests/death_watch.gd")
##     DeathWatch.expect_deaths(1)
##
## ## The run's one hook, so it also sandboxes the run's saves
##
## GUT takes a single pre-run script, and this is it, so the other thing every
## test must have from before its first line lives here too: the run's own
## user data (UserData.sandbox_for_tests()). A run started by
## .github/scripts/run_tests.sh is sandboxed already; one started from the
## editor or by hand is sandboxed here, so no GUT run writes the player's real
## progress, settings, assist or wardrobe, and no two runs share a file.
## tests/unit/test_user_data_sandbox.gd fails a run that is not sandboxed.
##
## Not a `class_name`, for the reason tests/duel_support.gd gives: test support
## has no business in the project's class registry. tests/unit/test_death_watch.gd
## proves the hook is installed and that its verdicts go red.

## The installed instance, so that a test can reach it by the script alone.
static var _installed: Object = null

## Where a verdict goes. For the installed watch, the current GUT test.
var _report := Callable()
var _tree: SceneTree = null
var _expected := 0
var _deaths: Array[String] = []


## GUT's entry point: watch the run's tree and report into the running test.
func run() -> void:
	UserData.sandbox_for_tests()
	attach(gut.get_tree() as SceneTree, _fail_current_test)
	gut.end_test.connect(close_test)
	_installed = self


## Whether this run has the watch installed. Without it nothing is guarded,
## and tests/unit/test_death_watch.gd says so.
static func is_installed() -> bool:
	return _installed != null


## Declares that the running test kills the prince exactly `count` times.
## Counted from the start of the test (its before_each included), so call it
## before the deaths, not after. Errors -- which fails the test -- when no
## watch is installed: a test that expects a death is relying on the guard.
static func expect_deaths(count: int) -> void:
	if _installed == null:
		push_error("expect_deaths(): no death watch is installed; see tests/death_watch.gd")
		return
	_installed.call(&"expect", count)


## The installed watch's deaths so far in this test.
static func deaths_so_far() -> int:
	return 0 if _installed == null else int(_installed.call(&"seen"))


## Starts watching `tree`: every Player that enters a Game from now on is
## counted, and each verdict is handed to `report` as a sentence.
func attach(tree: SceneTree, report: Callable) -> void:
	_tree = tree
	_report = report
	tree.node_added.connect(_on_node_added)


func detach() -> void:
	if _tree != null and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
	_tree = null


func expect(count: int) -> void:
	_expected = count


func seen() -> int:
	return _deaths.size()


## The end of a test: a death that was expected and never came is as wrong as
## one that came unannounced. Then the count starts again for the next test.
func close_test() -> void:
	if _deaths.size() < _expected:
		_report.call(
			"the test expected the prince to die %d time(s) and he died %d"
			% [_expected, _deaths.size()]
		)
	_expected = 0
	_deaths.clear()


func _on_node_added(node: Node) -> void:
	if not node is Player or not node.get_parent() is Game:
		return
	var player := node as Player
	var on_died := _on_died.bind(player)
	if not player.died.is_connected(on_died):
		player.died.connect(on_died)


func _on_died(player: Player) -> void:
	var game := player.get_parent() as Game
	var level := "" if game == null or game.level == null else game.level.data.name
	_deaths.append(
		"%s at (%.0f, %.0f), physics frame %d"
		% [level, player.position.x, player.position.y, Engine.get_physics_frames()]
	)
	if _deaths.size() > _expected:
		_report.call(
			(
				"the prince died (%s): death %d where %d were expected. The checkpoint "
				+ "respawn brings him back whole, so no assert after this can tell. "
				+ "A test that means him to die says DeathWatch.expect_deaths(n)."
			)
			% [_deaths[-1], _deaths.size(), _expected]
		)


func _fail_current_test(text: String) -> void:
	var test: Object = gut.get_current_script_object()
	if test != null and test.has_method(&"fail_test"):
		test.call(&"fail_test", "death watch: " + text)
	else:
		push_error("death watch: " + text)
