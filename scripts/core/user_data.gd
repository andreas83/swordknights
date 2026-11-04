class_name UserData
extends RefCounted
## Where the game keeps what it saves on the player's machine -- progress,
## audio, the assist, the wardrobe, the duel's choice, the feel settings --
## and the one seam that lets a test run keep all of it somewhere else.
##
## ## Why a seam and not a path per test
##
## Every save in the game names its file once, as a `user://` constant, and
## resolves it through `at()`. In the game `at()` is the identity: the file is
## where it always was. A test run is *sandboxed*: `at()` maps every `user://`
## path into one directory of the run's own, so
##
## - nothing a test does can write the player's real progress or settings --
##   the default a save falls back to when a test forgets to name a file of
##   its own lands in the sandbox, not in `user://progress.cfg`;
## - two runs side by side -- a developer's suite and an agent's, two CI jobs
##   on one runner -- never share a file, so neither reads what the other
##   just wrote. That was an eighth way for the suite to be unreliable: a test
##   that passed or failed by what another process had saved a moment before.
##
## A test names its own files through the same seam -- `UserData.at(
## "user://test_x.cfg")` -- so the file it writes, reads and removes is the
## one the game code under test wrote; tests/unit/test_user_data_sandbox.gd
## fails on a test that names a `user://` file any other way, and on a save
## in the game that does not go through `at()`.
##
## ## How a run is sandboxed
##
## `.github/scripts/run_tests.sh` exports SANDBOX_ENV, a fresh directory per
## run, removed when the run ends; both of its phases read it. GUT's pre-run
## hook (tests/death_watch.gd) sandboxes any run that was started without it
## -- from the editor, or by hand -- into a directory named for the process,
## so no GUT run is ever left writing the real files.

## The environment variable a test runner sets to the run's own directory.
const SANDBOX_ENV := "SWORDKNIGHTS_USER_DATA"
## Where a GUT run started without SANDBOX_ENV keeps its files.
const FALLBACK := "user://test-sandbox"

## The sandbox directory, or "" for the real user://. Unset until first asked.
static var _root := ""
static var _decided := false


## `path` as this run keeps it: unchanged in the game, inside the sandbox in a
## test run. Anything that is not a `user://` path is returned as it is.
static func at(path: String) -> String:
	_decide()
	if _root == "" or not path.begins_with("user://"):
		return path
	return _root.path_join(path.trim_prefix("user://"))


## Whether this run keeps its files in a sandbox.
static func is_sandboxed() -> bool:
	_decide()
	return _root != ""


## The sandbox directory, or "" for none.
static func root() -> String:
	_decide()
	return _root


## Keeps every file from now on under `dir` (absolute, or `user://`-rooted),
## made if it is missing.
static func sandbox(dir: String) -> void:
	_decided = true
	_root = dir.trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root))


## For a test run that has no sandbox yet: one of its own, by process.
static func sandbox_for_tests() -> void:
	if not is_sandboxed():
		sandbox(FALLBACK.path_join(str(OS.get_process_id())))


static func _decide() -> void:
	if _decided:
		return
	_decided = true
	var dir := OS.get_environment(SANDBOX_ENV)
	if dir != "":
		sandbox(dir)
