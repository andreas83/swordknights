class_name UpdateCheck
extends Node
## Fetches the dev channel's version.json once, in the background, and says
## whether it names a newer build.
##
## The menu owns one of these. Everything it decides is in DevUpdate; this node
## is only the I/O around it, kept small enough that the part a test cannot
## reach without a network is the HTTPRequest call itself.
##
## Not blocking: HTTPRequest is polled by the engine in the idle frame, so the
## menu draws and answers input while the request is in flight, and `TIMEOUT`
## bounds how long it can be in flight at all. A phone in a lift waits that long
## and then hears nothing.
##
## The environment fields are filled from the build itself and exist as fields
## only so a test can describe a build it is not running as -- a dev build, or
## a release one -- and wait less than a phone would. The menu never sets them.

## Emitted exactly once per `start()` that returned true: the manifest when it
## names a newer build, an empty Dictionary for every other outcome.
signal checked(offer: Dictionary)

const BuildStamp := preload("res://scripts/core/build_stamp.gd")

## Seconds. Generous for a 200-byte file on a slow mobile link, short enough
## that a dead connection does not leave a request open for the whole session.
const TIMEOUT := 8.0
## version.json is a few hundred bytes. Anything a hundred times that is not it.
const BODY_LIMIT := 32 * 1024

var debug := OS.is_debug_build()
var channel: String = BuildStamp.CHANNEL
var feed: String = BuildStamp.FEED
var running_code: int = BuildStamp.CODE
var timeout := TIMEOUT

var _request: HTTPRequest


## Starts the check if this build is one that checks. Returns whether it did.
## Must be called once the node is in the tree.
func start() -> bool:
	if _request != null or not DevUpdate.should_check(debug, channel, feed):
		return false
	_request = HTTPRequest.new()
	_request.name = "Request"
	_request.timeout = timeout
	_request.body_size_limit = BODY_LIMIT
	# The feed is a release-asset URL, which answers with a redirect to the
	# storage host; follow it, but not round a loop.
	_request.max_redirects = 4
	_request.request_completed.connect(_on_completed)
	add_child(_request)
	if _request.request(feed, PackedStringArray(["Accept: application/json"])) != OK:
		_request.queue_free()
		_request = null
		return false
	return true


## True while a request is in flight. For tests.
func busy() -> bool:
	return _request != null


func _on_completed(result: int, status: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	_finish(DevUpdate.offer(result, status, body, running_code))


func _finish(offer: Dictionary) -> void:
	if _request != null:
		_request.queue_free()
		_request = null
	checked.emit(offer)
