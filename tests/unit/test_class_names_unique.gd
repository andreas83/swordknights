extends GutTest
## Every `class_name` in the project names exactly one script.
##
## Two scripts that declare the same class name do not fail to load. Godot
## keeps one of them in the global class cache, silently, and every script
## that meant the other is the one that breaks -- as a parse error in a file
## nobody touched. The parse check passed through exactly that: a new
## `GateArt` for the portcullis shadowed the duel's gate (match_gate.gd), and
## the duel scene stopped parsing while the stage that exists to catch a
## script that does not parse reported it clean. Only two duel tests, which
## happened to build that scene, went red. This finds the clash itself, by
## name, before anything has to happen to load the loser.

const ROOTS: Array[String] = ["res://scripts", "res://tools", "res://tests"]


func test_no_two_scripts_declare_the_same_class_name() -> void:
	var owners := {}
	var clashes: Array[String] = []
	var seen := 0
	for root: String in ROOTS:
		for path: String in _scripts(root):
			var name := _class_name(path)
			if name == "":
				continue
			seen += 1
			if owners.has(name):
				clashes.append("%s: %s and %s" % [name, owners[name], path])
			else:
				owners[name] = path
	assert_gt(seen, 50, "the scan found the project's classes (%d)" % seen)
	assert_eq(clashes, [] as Array[String], "every class name names one script")


static func _scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(sub)))
	return out


static func _class_name(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	for line: String in text.split("\n", false, 8):
		if line.begins_with("class_name "):
			return line.trim_prefix("class_name ").strip_edges()
	return ""
