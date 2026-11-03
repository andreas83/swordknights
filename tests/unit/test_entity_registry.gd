extends GutTest
## The entity registry (scripts/entities/entity_registry.gd) is the one place a
## kind of thing is named, and Game places and meets whatever it lists.
##
## Three promises, each of which a builder adding a foe or a mechanism leans
## on without reading Game:
##
## - **The legend and the registry agree.** Every kind a glyph in
##   Tiles.ENTITY_LEGEND produces is registered, or listed in ELSEWHERE with
##   who places it instead. A glyph with neither spawns nothing, silently --
##   the exact failure this repository keeps a guard for.
## - **Every registered script keeps the protocol**: `place(site)`, and
##   `meet(contact)` for anything the prince can touch.
## - **A new kind needs no change to Game.** A kind registered here by the
##   test alone is placed from its mark -- at its feet position, with a post,
##   an ordinal and its parameters -- and met once a playing frame with the
##   prince's body, through the real game scene.

const GAME_SCENE := "res://scenes/game.tscn"
const TOY := "test_beacon"

const FLOOR := """; Registry Floor








 @     *       D
##################
##################
"""


## The smallest kind there is: it remembers where it was put and counts the
## frames the prince was met.
class Beacon extends Node2D:
	var site: EntitySite
	var met := 0
	var last_body := Rect2()

	func place(at: EntitySite) -> void:
		site = at
		position = at.at

	func meet(contact: Contact) -> void:
		met += 1
		last_body = contact.body


var _game: Game


func before_all() -> void:
	EntityRegistry.add_for_test(TOY, Beacon)


func after_all() -> void:
	EntityRegistry.remove_for_test(TOY)


func _play(extra: Array[Dictionary]) -> void:
	var data := AsciiLevel.new()
	data.parse(FLOOR)
	for mark: Dictionary in extra:
		data.entities.append(mark)
	_game = (load(GAME_SCENE) as PackedScene).instantiate() as Game
	_game.level_source = data
	add_child_autofree(_game)
	await wait_physics_frames(6)


func _of(script: Script) -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in _game.get_node("Entities").get_children():
		if node.get_script() == script and not node.is_queued_for_deletion():
			out.append(node)
	return out


func test_every_legend_kind_is_registered_or_placed_elsewhere() -> void:
	var kinds := EntityRegistry.kinds()
	var orphans: Array[String] = []
	for glyph: String in Tiles.ENTITY_LEGEND:
		var kind := String(Tiles.ENTITY_LEGEND[glyph])
		if not kinds.has(kind) and not EntityRegistry.ELSEWHERE.has(kind):
			orphans.append("'%s' -> %s" % [glyph, kind])
	assert_eq(orphans, [] as Array[String],
		"these glyphs would spawn nothing: register them, or say who places them")
	for kind: String in EntityRegistry.ELSEWHERE:
		assert_false(kinds.has(kind), "%s is placed elsewhere, not twice" % kind)


func test_the_four_original_kinds_go_through_it() -> void:
	for kind: String in ["relic", "exit", "torch", "patrol"]:
		assert_true(EntityRegistry.has_kind(kind), "%s is registered" % kind)
	assert_eq(EntityRegistry.script_for("patrol"), Patrol)


func test_every_registered_script_keeps_the_protocol() -> void:
	var kinds := EntityRegistry.kinds()
	for kind: String in kinds:
		var node := EntityRegistry.make(kind)
		assert_not_null(node, "%s makes a node" % kind)
		if node == null:
			continue
		assert_true(node.has_method(&"place"), "%s can be placed" % kind)
		assert_true(node.has_method(&"meet"), "%s can be met" % kind)
		node.free()


func test_a_kind_registered_only_here_is_placed_and_met_without_touching_game() -> void:
	var extra: Array[Dictionary] = [
		{"kind": TOY, "cell": Vector2i(4, 8)},
		{"kind": TOY, "cell": Vector2i(10, 8), "params": {"colour": "gold"}},
	]
	await _play(extra)
	var beacons := _of(Beacon)
	assert_eq(beacons.size(), 2, "both marks were placed")
	if beacons.size() != 2:
		return
	var first := beacons[0] as Beacon
	var second := beacons[1] as Beacon
	assert_eq(first.position, _game.level.entity_world_position(Vector2i(4, 8)),
		"at the feet position of its cell")
	assert_eq(first.site.post, "%s@4,8" % TOY, "with a post that names the mark")
	assert_eq([first.site.ordinal, second.site.ordinal], [0, 1], "and its place among its kind")
	assert_eq(second.site.param("colour"), "gold", "and the parameters its mark gave it")
	assert_gt(first.met, 3, "met on every playing frame")
	assert_eq(first.last_body, _game.player.body_rect(), "with the prince's body")


func test_marks_are_placed_in_the_level_order() -> void:
	var extra: Array[Dictionary] = [{"kind": TOY, "cell": Vector2i(4, 8)}]
	await _play(extra)
	var kinds: Array[String] = []
	for node: Node in _game.get_node("Entities").get_children():
		var script := node.get_script() as Script
		kinds.append(String(script.get_global_name()) if script.get_global_name() != &"" else "?")
	assert_eq(kinds, ["Relic", "ExitDoor", "?"] as Array[String],
		"the order of the marks, which is the order the pass meets them")


func test_a_kind_nobody_registered_spawns_nothing_and_breaks_nothing() -> void:
	var extra: Array[Dictionary] = [{"kind": "no_such_kind", "cell": Vector2i(4, 8)}]
	await _play(extra)
	assert_eq(_game.get_node("Entities").get_child_count(), 2,
		"the relic and the door, and nothing for a kind with no script")
	assert_eq(_game.relics_total, 1, "the level is otherwise whole")
