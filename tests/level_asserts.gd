extends RefCounted
## The assert helper the level generator suites share.
##
## There is no test framework in the repo yet, so each suite is a standalone
## headless script — `extends SceneTree`, run with
## `godot --headless --script tests/<name>.gd`, non-zero exit on failure — and
## this is the only thing they have in common. Loaded with `preload` rather
## than registered with `class_name` so it cannot collide with a real framework
## landing in tests/ later.
##
##     const Asserts := preload("res://tests/level_asserts.gd")
##     var check := Asserts.new("level_thing_test")
##     check.equal(got, want, "what it was")
##     quit(0 if check.report() else 1)

## How many failures to print in full before summarising the rest. A suite that
## breaks for 200 seeds should say so without burying the first failure.
const MAX_REPORTED := 12

var failures: int = 0
var checks: int = 0

var _suite: String
var _reported: int = 0


func _init(suite_name: String) -> void:
	_suite = suite_name


func is_true(condition: bool, what: String) -> bool:
	checks += 1
	if condition:
		return true
	_fail(what)
	return false


func is_false(condition: bool, what: String) -> bool:
	return is_true(not condition, what)


func equal(actual: Variant, expected: Variant, what: String) -> bool:
	checks += 1
	if actual == expected:
		return true
	_fail("%s: expected %s, got %s" % [what, str(expected), str(actual)])
	return false


func not_equal(actual: Variant, unwanted: Variant, what: String) -> bool:
	checks += 1
	if actual != unwanted:
		return true
	_fail("%s: expected anything but %s" % [what, str(unwanted)])
	return false


func greater(actual: float, floor_value: float, what: String) -> bool:
	checks += 1
	if actual > floor_value:
		return true
	_fail("%s: expected more than %s, got %s" % [what, str(floor_value), str(actual)])
	return false


func fail(what: String) -> void:
	checks += 1
	_fail(what)


func _fail(message: String) -> void:
	failures += 1
	_reported += 1
	if _reported <= MAX_REPORTED:
		printerr("  FAIL  " + message)
	elif _reported == MAX_REPORTED + 1:
		printerr("  ...   further failures suppressed")


## True when the suite passed. Prints the one line a CI log should carry.
func report() -> bool:
	# A suite that checked nothing has measured nothing; it must not pass.
	if checks == 0:
		printerr("%s: no checks ran" % _suite)
		return false
	if failures > 0:
		printerr("%s: %d failure(s) in %d checks" % [_suite, failures, checks])
		return false
	print("%s: ok (%d checks)" % [_suite, checks])
	return true
