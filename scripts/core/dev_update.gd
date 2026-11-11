class_name DevUpdate
extends RefCounted
## Whether a newer development build exists, decided by pure functions.
##
## The owner tests debug APKs on a phone. android.yml publishes each one to a
## rolling `dev` pre-release next to a small version.json; a dev build fetches
## that file at the menu and, when it names a higher build, offers to open the
## APK's URL. Android's browser downloads it and offers to install it over the
## running copy. This file is everything in that chain that is a decision
## rather than I/O, so that every rule below has a test
## (tests/unit/test_dev_update.gd) that runs without a network.
##
## Three rules carry the weight:
##
## - **Only a dev build asks.** A release build never calls home, whatever it
##   was stamped with, and neither does a run from the editor: it carries no
##   channel. Two independent conditions, so neither a stamping mistake nor a
##   debug export of a release tag is enough on its own.
## - **Anything unexpected is "no update".** Offline, rate-limited, a 404 before
##   the first release exists, an HTML error page, a truncated body, a field of
##   the wrong type: all of them return an empty Dictionary and nothing is
##   shown or logged. A development convenience must not put an error on the
##   title screen of the game it is helping to test.
## - **Only an https URL is opened.** The URL is handed to the OS, which will
##   open whatever scheme it is given; the manifest is the owner's own file,
##   but a check that costs one line is cheaper than an argument about trust.

const CHANNEL_DEV := "dev"
## Android refuses a versionCode above this, so neither can a manifest name one.
const MAX_CODE := 2100000000
const SHORT_SHA := 7


## True when this build should fetch the manifest at all.
static func should_check(debug: bool, channel: String, feed: String) -> bool:
	return is_dev_build(debug, channel) and feed.begins_with("http")


## True for a development build: a debug export stamped for the dev channel.
## The update check asks it, and so does the title screen before listing the
## dev tools (ModeRegistry.shows_dev_tools), so the two cannot disagree about
## which build is the owner's.
static func is_dev_build(debug: bool, channel: String) -> bool:
	return debug and channel == CHANNEL_DEV


## The manifest as a normalised Dictionary, or {} if it is not one.
##
## `code` and `apk_url` are required; `name`, `sha` and `date` are carried
## through when they are strings and default to "" when they are not.
static func parse(text: String) -> Dictionary:
	# An instance rather than JSON.parse_string(): the static form reports a
	# malformed body as an engine error, and this one has to stay silent.
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var raw := data as Dictionary

	var code := _whole_number(raw.get("code"))
	if code <= 0 or code > MAX_CODE:
		return {}
	var url := _text(raw.get("apk_url"))
	if not _is_openable(url):
		return {}

	return {
		"code": code,
		"name": _text(raw.get("name")),
		"sha": _text(raw.get("sha")),
		"date": _text(raw.get("date")),
		"apk_url": url,
	}


## The manifest when it names a build newer than `running_code`, otherwise {}.
## Takes HTTPRequest's own completion values, so a failed request, a non-200
## answer and a stale manifest all come out the same way.
static func offer(result: int, status: int, body: PackedByteArray,
		running_code: int) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		return {}
	var manifest := parse(body.get_string_from_utf8())
	if not is_newer(manifest, running_code):
		return {}
	return manifest


static func is_newer(manifest: Dictionary, running_code: int) -> bool:
	return not manifest.is_empty() and int(manifest.get("code", 0)) > running_code


## The menu entry, longest first, for UiFont.fit().
static func offer_phrasings(code: int) -> PackedStringArray:
	return PackedStringArray([
		"UPDATE AVAILABLE · BUILD %d" % code,
		"UPDATE · BUILD %d" % code,
		"BUILD %d" % code,
	])


## The running build in one line: name, build number and short commit.
##
## A dev build's name already carries its commit ("0.1.0-dev+abc1234"), so the
## commit is only added when the name does not show it -- a release, or a build
## nobody stamped, which says LOCAL instead.
static func running_label(name: String, code: int, sha: String) -> String:
	var short := sha.substr(0, SHORT_SHA).to_lower()
	var parts := PackedStringArray([name.to_upper(), "BUILD %d" % code])
	if short.is_empty():
		parts.append("LOCAL")
	elif not name.to_lower().contains(short):
		parts.append(short.to_upper())
	return " · ".join(parts)


## A JSON number is a float; a build number has to be a whole one.
static func _whole_number(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			var number := float(value)
			if is_finite(number) and number == floorf(number) and absf(number) < 1e10:
				return int(number)
	return 0


static func _text(value: Variant) -> String:
	return String(value) if typeof(value) == TYPE_STRING else ""


static func _is_openable(url: String) -> bool:
	if not url.begins_with("https://") or url.length() <= "https://".length():
		return false
	for blank: String in [" ", "\t", "\n", "\r"]:
		if url.contains(blank):
			return false
	return true
