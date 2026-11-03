class_name LanCode
extends RefCounted
## Pairing two phones on one Wi-Fi without anyone typing an IP address.
##
## A phone does not show its own address anywhere a player would find it, and
## typing "192.168.178.23" on an on-screen keyboard is where a duel dies before
## it starts. On a home network, or a phone's hotspot, both devices share the
## first three numbers of their address. So the host shows only the last one --
## "CODE 23" -- and the joining phone puts its own first three in front of it.
## A full address or a ws:// URL still works where the networks differ.
##
## Not automatic discovery. A UDP broadcast would find the host with no typing
## at all, but Android drops broadcast packets unless the app holds a Wi-Fi
## multicast lock, which Godot cannot take without a plugin. One number is the
## dependable version.
##
## Pure functions over strings, so the rules are testable without a network.


## This device's LAN address, or "" if it has none worth showing.
static func my_address() -> String:
	return pick(IP.get_local_addresses())


## The address to show from a list of this device's addresses: a private IPv4
## one, preferring the ranges home routers and hotspots hand out.
static func pick(addresses: PackedStringArray) -> String:
	var best := ""
	var best_rank := 99
	for address: String in addresses:
		var rank := _rank(address)
		if rank < best_rank:
			best = address
			best_rank = rank
	return best


## The short code for an address: its last number.
static func code_for(address: String) -> String:
	var parts := address.split(".")
	return parts[3] if parts.size() == 4 else ""


## What to dial for what the player typed. A bare number 1-254 is a code on
## this device's own network; anything else is passed through as an address.
static func resolve(entry: String, mine: String) -> String:
	var text := entry.strip_edges()
	if not text.is_valid_int():
		return text
	var last := text.to_int()
	var parts := mine.split(".")
	if last < 1 or last > 254 or parts.size() != 4:
		return text
	return "%s.%s.%s.%d" % [parts[0], parts[1], parts[2], last]


## Lower is better; 99 means "never show this one".
static func _rank(address: String) -> int:
	var parts := address.split(".")
	if parts.size() != 4:
		return 99 # IPv6, or not an address
	for part: String in parts:
		if not part.is_valid_int():
			return 99
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	if a == 192 and b == 168:
		return 0 # home routers, and Android hotspots
	if a == 10:
		return 1
	if a == 172 and b >= 16 and b <= 31:
		return 2
	return 99 # loopback, link-local, public: not a LAN partner
