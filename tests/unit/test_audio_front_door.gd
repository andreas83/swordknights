extends GutTest
## Fails if any script names the AudioDirector autoload instead of GameAudio.
##
## A direct `AudioDirector.play(...)` compiles in the editor and in the game,
## and fails to compile under `godot --headless --script`, where autoload names
## are not in the compiler's scope. A scene whose script failed to compile
## instantiates *without* it, and a test driving that scene then measures
## nothing while reporting success -- the second of this repository's
## "silently green" failures. CLAUDE.md states the rule; this makes it a guard,
## because the rule alone was broken again within a day (touch_controls.gd).

const ROOTS: Array[String] = ["res://scripts", "res://tests"]

## The autoload itself, and its front door, legitimately name it.
const ALLOWED: Array[String] = [
	"res://scripts/audio/audio_director.gd",
	"res://scripts/audio/game_audio.gd",
]

var _pattern := RegEx.create_from_string("\\bAudioDirector\\s*\\.")


func test_no_script_calls_the_autoload_by_name() -> void:
	var files: Array[String] = []
	for root: String in ROOTS:
		_collect(root, files)

	# A scan over nothing passes trivially. That is the failure this file
	# exists to prevent, so it must not be one itself.
	assert_gt(files.size(), 50, "scanned the project's scripts")

	var offenders: Array[String] = []
	for path: String in files:
		if ALLOWED.has(path):
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			var code := lines[i].get_slice("#", 0)
			if _pattern.search(code) != null:
				offenders.append("%s:%d: %s" % [path, i + 1, lines[i].strip_edges()])

	assert_eq(offenders, [] as Array[String],
		"call GameAudio, not the AudioDirector autoload, from:\n  "
		+ "\n  ".join(offenders))


func _collect(dir_path: String, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name: String in dir.get_files():
		if name.ends_with(".gd"):
			into.append(dir_path.path_join(name))
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), into)
