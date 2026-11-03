extends GutTest
## The dev channel's decisions, without a network: who asks, what counts as a
## manifest, and what counts as newer (scripts/core/dev_update.gd).
##
## Every malformed input below is fed through the real parser with GUT failing
## on engine errors, so "fails silently" is checked, not assumed: a parser that
## logged its rejection would fail these tests even with every assert passing.

const BuildStamp := preload("res://scripts/core/build_stamp.gd")
const FEED := "https://github.com/o/r/releases/download/dev/version.json"
const APK := "https://github.com/o/r/releases/download/dev/swordknights-dev.apk"


func _manifest(fields: Dictionary = {}) -> String:
	var out := {
		"code": 58, "name": "0.1.0-dev+4f2c9e1", "sha": "4f2c9e1aabbccddeeff00112233445566778899a",
		"date": "2026-11-03T10:42:32Z", "apk_url": APK,
	}
	out.merge(fields, true)
	return JSON.stringify(out)


func test_only_a_debug_build_on_the_dev_channel_with_a_feed_asks() -> void:
	assert_true(DevUpdate.should_check(true, "dev", FEED), "a stamped dev APK asks")
	assert_false(DevUpdate.should_check(false, "dev", FEED),
		"a release build never calls home, even stamped dev")
	assert_false(DevUpdate.should_check(true, "", FEED), "an unstamped run does not ask")
	assert_false(DevUpdate.should_check(true, "release", FEED), "a release channel does not")
	assert_false(DevUpdate.should_check(true, "dev", ""), "nor a build without a feed")


func test_the_committed_stamp_is_a_build_that_never_asks() -> void:
	# A stamped build_stamp.gd committed by accident would make every editor
	# run and every test call home. CI stamps its own checkout only.
	assert_eq(BuildStamp.CHANNEL, "", "build_stamp.gd is committed unstamped")
	assert_eq(BuildStamp.FEED, "", "build_stamp.gd is committed without a feed")
	assert_false(DevUpdate.should_check(OS.is_debug_build(), BuildStamp.CHANNEL,
		BuildStamp.FEED), "so the build under test does not ask")


func test_the_committed_stamp_agrees_with_the_android_preset() -> void:
	# stamp_version.sh writes both from one call; the committed placeholders
	# should say the same thing, or a local export disagrees with itself.
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK, "export_presets.cfg loads")
	var android := ""
	for section: String in presets.get_sections():
		if presets.get_value(section, "name", "") == "Android":
			android = section + ".options"
	assert_ne(android, "", "an Android preset exists")
	assert_eq(int(presets.get_value(android, "version/code", -1)), BuildStamp.CODE)
	assert_eq(String(presets.get_value(android, "version/name", "")), BuildStamp.NAME)


func test_a_manifest_is_normalised() -> void:
	var got := DevUpdate.parse(_manifest())
	assert_eq(got.get("code"), 58, "a JSON number comes back as an int")
	assert_eq(typeof(got.get("code")), TYPE_INT)
	assert_eq(got.get("apk_url"), APK)
	assert_eq(got.get("name"), "0.1.0-dev+4f2c9e1")
	assert_eq(String(got.get("sha")).length(), 40)


func test_optional_fields_may_be_missing_and_extra_ones_are_ignored() -> void:
	var got := DevUpdate.parse(JSON.stringify(
		{"code": 9, "apk_url": APK, "signer": "ab:cd", "sha": 12}))
	assert_eq(got.get("code"), 9)
	assert_eq(got.get("name"), "", "missing name reads as empty")
	assert_eq(got.get("sha"), "", "a sha of the wrong type reads as empty")
	assert_false(got.has("signer"), "fields the app does not use are dropped")


func test_broken_bodies_are_no_manifest_and_say_nothing() -> void:
	for body: String in ["", "{", "<!DOCTYPE html><title>429</title>", "[]", "null",
			"58", "\"code\"", "{\"code\": 58, \"apk_url\": "]:
		assert_eq(DevUpdate.parse(body), {}, "rejected: %s" % body)


func test_a_build_number_must_be_a_positive_whole_number() -> void:
	for code: Variant in [null, 0, -3, 1.5, "58", true, 3e12, 2100000001]:
		var fields := {"code": code}
		assert_eq(DevUpdate.parse(_manifest(fields)), {}, "rejected code %s" % str(code))
	assert_eq(DevUpdate.parse(_manifest({"code": 2100000000})).get("code"), 2100000000,
		"Android's own ceiling is allowed")


func test_only_an_https_url_is_ever_opened() -> void:
	for url: Variant in [null, "", "https://", "http://example.com/a.apk",
			"javascript:alert(1)", "file:///sdcard/a.apk", "intent://x#Intent;end",
			"https://example.com/a b.apk", "https://example.com/a.apk\n", 42]:
		assert_eq(DevUpdate.parse(_manifest({"apk_url": url})), {}, "rejected %s" % str(url))


func test_only_a_higher_build_is_offered() -> void:
	var body := _manifest().to_utf8_buffer()
	var ok := HTTPRequest.RESULT_SUCCESS
	assert_eq(DevUpdate.offer(ok, 200, body, 57).get("code"), 58, "57 -> 58 is offered")
	assert_eq(DevUpdate.offer(ok, 200, body, 58), {}, "the same build is not")
	assert_eq(DevUpdate.offer(ok, 200, body, 90), {}, "an older one is not")


func test_a_failed_or_refused_request_is_no_offer() -> void:
	var body := _manifest().to_utf8_buffer()
	assert_eq(DevUpdate.offer(HTTPRequest.RESULT_SUCCESS, 404, body, 1), {},
		"404: no dev release published yet")
	assert_eq(DevUpdate.offer(HTTPRequest.RESULT_SUCCESS, 403, body, 1), {}, "rate-limited")
	for result: int in [HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CANT_CONNECT,
			HTTPRequest.RESULT_TIMEOUT, HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR,
			HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED]:
		assert_eq(DevUpdate.offer(result, 200, body, 1), {}, "result %d" % result)


func test_the_entry_is_phrased_longest_first() -> void:
	var lines := DevUpdate.offer_phrasings(158)
	assert_eq(lines[0], "UPDATE AVAILABLE · BUILD 158")
	for i: int in range(1, lines.size()):
		assert_lt(lines[i].length(), lines[i - 1].length(), "UiFont.fit wants longest first")
		assert_true(lines[i].contains("158"), "every phrasing keeps the build number")


func test_the_running_build_shows_name_number_and_commit_once() -> void:
	assert_eq(DevUpdate.running_label("0.1.0-dev+4f2c9e1", 57, "4f2c9e1aabb"),
		"0.1.0-DEV+4F2C9E1 · BUILD 57", "a dev name already carries the commit")
	assert_eq(DevUpdate.running_label("1.2.3", 10203, "4f2c9e1aabb"),
		"1.2.3 · BUILD 10203 · 4F2C9E1", "a release adds it")
	assert_eq(DevUpdate.running_label("0.1.0", 1, ""), "0.1.0 · BUILD 1 · LOCAL",
		"an unstamped build says so")
