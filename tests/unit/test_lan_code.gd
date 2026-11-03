extends GutTest
## The one-number pairing code: which address a host shows, and what a typed
## code turns into on the joining phone.


func test_a_home_network_address_is_preferred() -> void:
	var picked := LanCode.pick(PackedStringArray([
		"127.0.0.1", "fe80::1c2a:4bff:fe11:2233", "10.0.2.15", "192.168.178.23",
	]))
	assert_eq(picked, "192.168.178.23")


func test_loopback_link_local_and_public_are_never_shown() -> void:
	assert_eq(LanCode.pick(PackedStringArray(["127.0.0.1", "169.254.3.4", "8.8.8.8"])), "")


func test_the_code_is_the_last_number() -> void:
	assert_eq(LanCode.code_for("192.168.178.23"), "23")
	assert_eq(LanCode.code_for(""), "")


func test_a_code_is_completed_from_the_joiners_own_network() -> void:
	assert_eq(LanCode.resolve("23", "192.168.178.40"), "192.168.178.23")
	assert_eq(LanCode.resolve(" 7 ", "10.0.0.5"), "10.0.0.7")


func test_anything_else_passes_through() -> void:
	assert_eq(LanCode.resolve("192.168.1.9", "192.168.178.40"), "192.168.1.9")
	assert_eq(LanCode.resolve("ws://host:45678", "192.168.178.40"), "ws://host:45678")
	assert_eq(LanCode.resolve("0", "192.168.178.40"), "0", "0 is not a host")
	assert_eq(LanCode.resolve("255", "192.168.178.40"), "255", "nor is 255")
	assert_eq(LanCode.resolve("23", ""), "23", "with no network of our own, no guess")
