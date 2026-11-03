extends GutTest
## Every test or document that the code names must exist.
##
## A comment that says "tests/match_gore_test.gd asserts exactly that" is a
## claim of coverage. When the file is missing, the claim is false, the build
## is green, and the next reader trusts an invariant nothing guards. Five such
## references were found at once when a container restart stopped four agents
## before they wrote their tests and documents, and one had been wrong for
## weeks (grammar.gd naming a test that never existed). This makes the claim
## checkable.
##
## Scope: paths under tests/ and docs/ named in scripts/, tests/ and tools/.
## Paths under docs/ written *in* docs/ are not checked here; docs/ci.md names
## a file it proposes creating, which is legitimate in prose.

const ROOTS: Array[String] = ["res://scripts", "res://tests", "res://tools"]
const SOURCE_EXTENSIONS: Array[String] = ["gd", "py", "sh"]

## A path counts when it starts a word or follows res:// -- so that the tail of
## `.github/scripts/run_tests.sh` or `scripts/levels/generator.gd` is not read
## as a reference of its own.
var _pattern := RegEx.create_from_string(
	"(?:res://|(?<![A-Za-z0-9_./-]))((?:tests|docs)/[A-Za-z0-9_/-]+(?:\\.[A-Za-z0-9_-]+)*"
	+ "\\.(?:gd|md|png|py|txt|sh))")


func test_every_named_test_and_document_exists() -> void:
	var files: Array[String] = []
	for root: String in ROOTS:
		_collect(root, files)
	assert_gt(files.size(), 50, "scanned the project's sources")

	var seen := 0
	var missing: Array[String] = []
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		for hit: RegExMatch in _pattern.search_all(text):
			seen += 1
			var target := hit.get_string(1)
			if not FileAccess.file_exists("res://" + target):
				missing.append("%s names %s" % [path, target])

	# If the pattern ever stops matching, this test would pass on nothing.
	assert_gt(seen, 20, "found the code's references to tests and documents")
	assert_eq(missing, [] as Array[String],
		"referenced but missing -- write it, or stop claiming it:\n  "
		+ "\n  ".join(missing))


func _collect(dir_path: String, into: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name: String in dir.get_files():
		if SOURCE_EXTENSIONS.has(name.get_extension()):
			into.append(dir_path.path_join(name))
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), into)
