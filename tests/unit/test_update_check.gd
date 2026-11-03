extends GutTest
## The update check's I/O: a release build never makes a request, and a dev
## build's request either yields a newer manifest or nothing at all
## (scripts/core/update_check.gd).
##
## The dev-build cases run the real HTTPRequest against a loopback server in
## this file, with the redirect GitHub puts in front of every release asset,
## so the path from socket to offer is exercised rather than mocked. GUT fails a
## test on any engine error, which is what makes "offline fails silently" a
## checked claim: a refused connection that logged would fail here.

const APK := "https://github.com/o/r/releases/download/dev/swordknights-dev.apk"


## A one-file HTTP server on 127.0.0.1. `/redirect` answers 302 to
## `/version.json`, as github.com does for a release asset; everything else
## gets `status` and `body`. With `silent` it accepts and never answers.
class FakeFeed:
	extends RefCounted

	var status := "200 OK"
	var body := ""
	var silent := false
	var requests := 0
	var _server := TCPServer.new()
	var _peers: Array[StreamPeerTCP] = []

	func open() -> int:
		if _server.listen(0, "127.0.0.1") != OK:
			return 0
		return _server.get_local_port()

	func poll() -> void:
		while _server.is_connection_available():
			_peers.append(_server.take_connection())
		for peer: StreamPeerTCP in _peers:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				continue
			var waiting := peer.get_available_bytes()
			if waiting <= 0 or silent:
				continue
			var head := peer.get_utf8_string(waiting)
			requests += 1
			if head.begins_with("GET /redirect "):
				_answer(peer, "302 Found", "", "Location: /version.json\r\n")
			else:
				_answer(peer, status, body, "")

	func close() -> void:
		for peer: StreamPeerTCP in _peers:
			peer.disconnect_from_host()
		_server.stop()

	func _answer(peer: StreamPeerTCP, line: String, text: String, extra: String) -> void:
		var bytes := text.to_utf8_buffer()
		var head := "HTTP/1.1 %s\r\nContent-Type: application/json\r\n" % line
		head += "Content-Length: %d\r\n%s\r\n" % [bytes.size(), extra]
		peer.put_data(head.to_utf8_buffer())
		peer.put_data(bytes)


var _feed: FakeFeed
var _port := 0


func before_each() -> void:
	_feed = FakeFeed.new()
	_port = _feed.open()
	assert_gt(_port, 0, "the loopback feed is listening")


func after_each() -> void:
	_feed.close()


## An UpdateCheck that believes it is dev build `running`, pointed at `path`.
func _dev_check(running: int, path: String) -> UpdateCheck:
	var check := UpdateCheck.new()
	check.debug = true
	check.channel = DevUpdate.CHANNEL_DEV
	check.feed = "http://127.0.0.1:%d%s" % [_port, path]
	check.running_code = running
	check.timeout = 1.0
	add_child_autofree(check)
	return check


## Starts `check` and pumps the fake server until it reports. Returns what it
## reported, or null if it never did.
func _run(check: UpdateCheck) -> Variant:
	var heard: Array = []
	check.checked.connect(func(offer: Dictionary) -> void: heard.append(offer))
	assert_true(check.start(), "a dev build starts a request")
	assert_true(check.busy(), "and it is in flight, not finished on the spot")
	var waited := 0.0
	while heard.is_empty() and waited < 4.0:
		_feed.poll()
		await wait_process_frames(1)
		waited += get_process_delta_time()
	assert_eq(heard.size(), 1, "checked is emitted exactly once")
	assert_false(check.busy(), "and the request is gone afterwards")
	return heard[0] if heard.size() == 1 else null


func _manifest(code: int) -> String:
	return JSON.stringify({"code": code, "name": "0.1.0-dev+4f2c9e1",
		"sha": "4f2c9e1", "date": "2026-11-03T10:42:32Z", "apk_url": APK})


func test_a_release_build_does_not_check() -> void:
	var check := _dev_check(57, "/version.json")
	check.debug = false
	var heard: Array = []
	check.checked.connect(func(offer: Dictionary) -> void: heard.append(offer))
	_feed.body = _manifest(58)
	assert_false(check.start(), "a release build does not start a request")
	assert_false(check.busy())
	assert_eq(check.get_child_count(), 0, "no HTTPRequest was even created")
	for _frame: int in 5:
		_feed.poll()
		await wait_process_frames(1)
	assert_eq(_feed.requests, 0, "nothing reached the server")
	assert_eq(heard, [], "and nothing was reported")


func test_the_build_under_test_does_not_check() -> void:
	# No fields set: the check describes this very build, which is unstamped.
	var check := UpdateCheck.new()
	add_child_autofree(check)
	assert_false(check.start(), "an unstamped build never asks")
	assert_eq(check.get_child_count(), 0)


func test_a_newer_build_behind_a_redirect_is_offered() -> void:
	_feed.body = _manifest(58)
	var offer: Variant = await _run(_dev_check(57, "/redirect"))
	assert_typeof(offer, TYPE_DICTIONARY)
	assert_eq((offer as Dictionary).get("code"), 58)
	assert_eq((offer as Dictionary).get("apk_url"), APK)
	assert_eq(_feed.requests, 2, "the redirect was followed")


func test_the_running_build_is_not_offered_to_itself() -> void:
	_feed.body = _manifest(58)
	assert_eq(await _run(_dev_check(58, "/version.json")), {})


func test_broken_json_is_no_offer() -> void:
	_feed.body = "{\"code\": 58, \"apk_url\": "
	assert_eq(await _run(_dev_check(1, "/version.json")), {})


func test_a_rate_limit_answer_is_no_offer() -> void:
	_feed.status = "429 Too Many Requests"
	_feed.body = _manifest(58)
	assert_eq(await _run(_dev_check(1, "/version.json")), {})


func test_a_feed_that_never_answers_times_out_into_no_offer() -> void:
	_feed.silent = true
	assert_eq(await _run(_dev_check(1, "/version.json")), {})


func test_nothing_listening_is_no_offer() -> void:
	var check := _dev_check(1, "/version.json")
	_feed.close()
	assert_eq(await _run(check), {})
