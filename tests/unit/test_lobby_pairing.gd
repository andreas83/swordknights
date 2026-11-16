extends GutTest
## The host's pairing code survives the host opening its port.
##
## HOST ON THIS WI-FI showed "CODE 23", then opened the port, and the
## transport's "listening on port 45678" -- emitted inside that same call --
## replaced it on the one line both shared. On two phones the host's screen
## never showed a code, and the other phone had nothing to type. These run the
## real online scene and its real transport, because the fault was in the
## order the two wrote, not in either alone.

## Not the default port, so a game left running on the machine does not
## refuse the listen and send the test down the fallback path instead.
const PORT := 45991

var _store := UserData.at("user://test_lobby_pairing.cfg")


func after_each() -> void:
	if FileAccess.file_exists(_store):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_store))


func test_the_host_still_shows_its_code_once_it_listens() -> void:
	var scene := await _online()
	var lobby := _lobby(scene)
	lobby.my_address = func() -> String: return "192.168.178.23"
	lobby._on_host_direct()
	await wait_physics_frames(3)
	assert_not_null(scene.get("transport"), "the port opened, not the fallback")
	assert_eq(lobby.page, DuelLobby.Page.BUSY, "still waiting for the other phone")
	assert_eq(lobby.headline(), "CODE 23", "the code is what the host's screen says")
	assert_string_contains(lobby._subline, "192.168.178.23")
	assert_string_contains(lobby._status, "listening", "the link's state, underneath")


func test_a_device_with_no_address_says_so() -> void:
	var scene := await _online()
	var lobby := _lobby(scene)
	lobby.my_address = func() -> String: return ""
	lobby._on_host_direct()
	await wait_physics_frames(3)
	assert_eq(lobby.headline(), "NO WI-FI ADDRESS")
	assert_string_contains(lobby._subline, str(PORT))


func test_a_relay_room_code_is_the_headline() -> void:
	var scene := await _online()
	var lobby := _lobby(scene)
	lobby.show_room("ABCD", true)
	lobby.set_status("waiting for the other player")
	assert_eq(lobby.headline(), "ROOM ABCD", "a status line does not replace it")
	assert_eq(lobby._subline, "TELL THE OTHER PLAYER")


func test_the_list_has_no_headline() -> void:
	var scene := await _online()
	var lobby := _lobby(scene)
	lobby.show_busy("CODE 23")
	lobby.show_menu()
	assert_eq(lobby.headline(), "", "a stale code is not left over the list")


func _online() -> Node:
	var scene := (load("res://scenes/duel_match_online.tscn") as PackedScene).instantiate()
	scene.set("wardrobe_path", _store)
	scene.set("choice_path", _store)
	scene.set("leave", func() -> void: pass)
	add_child_autofree(scene)
	await wait_physics_frames(3)
	return scene


func _lobby(scene: Node) -> DuelLobby:
	var lobby := scene.get_node(^"LobbyLayer/Lobby") as DuelLobby
	lobby.direct_port = PORT
	return lobby
