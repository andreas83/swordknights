extends SceneTree
## Compile every GDScript in the project and report the ones that fail.
##
## Why this is not `--check-only --script <file>` run per file: that mode
## compiles a script in isolation, without the project's autoload singletons
## registered. Any script that calls an autoload by name — the documented way
## to use one — is reported as "Identifier not found" even though it compiles
## and runs correctly. Checking inside a live SceneTree validates each file in
## the same context the game actually loads it in, and does it in one process
## instead of one per file.
##
## `godot --headless --import` is NOT a substitute: it exits 0 on a parse
## error. Verified on 4.5.1 with a file of deliberate garbage.
##
##     godot --headless --script tools/check_scripts.gd -- [--dir res://scripts] ...

const DEFAULT_DIRS: Array[String] = [
	"res://scripts", "res://tools", "res://tests",
]


func _initialize() -> void:
	var dirs := _dirs_from_args()
	var paths: Array[String] = []
	for dir: String in dirs:
		_collect(dir, paths)
	paths.sort()

	if paths.is_empty():
		printerr("error: no GDScript files found under %s" % str(dirs))
		quit(1)
		return

	print("Compiling %d GDScript file(s) in %s" % [paths.size(), str(dirs)])
	var failed: Array[String] = []
	for path: String in paths:
		# Plain load(): the cache is per-process and each file is visited once,
		# so caching cannot mask a failure here. Re-compiling an already
		# registered class_name script with CACHE_MODE_IGNORE segfaults the
		# engine on 4.5.1, so do not be tempted back to that.
		# load() is NOT a validity test: a script with a parse error still comes
		# back as a (broken) GDScript object, so a null check here would be a
		# no-op gate. can_instantiate() is the signal that actually flips --
		# false for a script that failed to compile, true otherwise -- and
		# unlike reload() it re-runs nothing.
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			printerr("  FAIL  %s" % path)
			failed.append(path)
			continue
		print("  ok    %s" % path)

	print("")
	if not failed.is_empty():
		printerr("FAILED: %d of %d script(s) did not compile:" % [failed.size(), paths.size()])
		for path: String in failed:
			printerr("  - " + path)
		quit(1)
		return

	print("All %d script(s) compiled cleanly." % paths.size())
	quit(0)


func _dirs_from_args() -> Array[String]:
	var args := OS.get_cmdline_user_args()
	var dirs: Array[String] = []
	var i := 0
	while i < args.size():
		if args[i] == "--dir" and i + 1 < args.size():
			dirs.append(args[i + 1])
			i += 2
		else:
			i += 1
	return dirs if not dirs.is_empty() else DEFAULT_DIRS


## Walks a directory tree. Skips nothing by hand: a .gdignore'd directory is
## already invisible to DirAccess inside a project.
func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
