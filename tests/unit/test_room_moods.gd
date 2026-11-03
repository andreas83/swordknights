extends GutTest
## The room moods' promises (scripts/world/dresser.gd, the end of the file).
##
## The props plane is dressed over levels nobody has looked at, so the same
## safety argument has to hold for it as for the architecture: it may only
## lie over stone the terrain already has or stand in a cell the terrain left
## empty, never over an entity, and it must come out the same every time. On
## top of that, the reason it exists: neighbouring rooms must not look alike.

const LEVEL := "res://levels/level_01.txt"
## The duel's Mirror Court: the one level symmetric about its own centre now
## that the round duel's arena is retired.
const ARENA := "res://levels/zone_03.txt"
## Props that stand on a floor and must have one under them.
const STANDING := ["urn", "jars", "rubble", "grass", "palm_pot"]
## Props that lie over a wall face.
const OVER_STONE := ["crack", "worn", "ivy_top", "ivy", "ivy_end", "moss", "window"]


func _ids() -> Dictionary:
	var out := {}
	for id: String in Tiles.DECOR_ATLAS:
		out[Tiles.DECOR_ATLAS[id]] = id
	return out


func _props(level: AsciiLevel) -> Dictionary:
	return WorldDresser.dress(level)["props"]


func _generated() -> AsciiLevel:
	var result := LevelGenerator.build(20260211, 120, 0.55)
	assert_true(bool(result["ok"]), "the generator builds")
	return result["level"] as AsciiLevel


func test_neighbouring_rooms_never_share_a_mood() -> void:
	for level: AsciiLevel in [AsciiLevel.from_file(LEVEL), _generated()]:
		var seen := {}
		for room: int in range(0, level.cols / WorldDresser.ROOM_COLS + 1):
			var x := room * WorldDresser.ROOM_COLS
			seen[WorldDresser.mood_at(level, x)] = true
			if room > 0:
				assert_ne(WorldDresser.mood_at(level, x),
					WorldDresser.mood_at(level, x - WorldDresser.ROOM_COLS),
					"rooms %d and %d of %s" % [room - 1, room, level.name])
		assert_gte(seen.size(), mini(4, level.cols / WorldDresser.ROOM_COLS + 1),
			"every mood appears once there is room for it")


func test_props_sit_only_where_they_may() -> void:
	var ids := _ids()
	for level: AsciiLevel in [AsciiLevel.from_file(LEVEL), _generated()]:
		var reserved := {}
		var marks: Array[Vector2i] = [level.spawn_point]
		for mark: Dictionary in level.entities:
			marks.append(mark["cell"])
		for cell: Vector2i in marks:
			reserved[cell] = true
		var props := _props(level)
		assert_gt(props.size(), 10, "%s gets props" % level.name)
		for cell: Vector2i in props:
			var id: String = ids.get(props[cell], "?")
			var kind := level.kind_at(cell.x, cell.y)
			assert_false(reserved.has(cell), "%s at %s covers an entity" % [id, cell])
			if OVER_STONE.has(id):
				assert_eq(kind, Tiles.Kind.SOLID, "%s at %s lies over stone" % [id, cell])
			else:
				assert_eq(kind, Tiles.Kind.EMPTY, "%s at %s stands in open air" % [id, cell])
			if STANDING.has(id):
				assert_true(level.is_solid(cell.x, cell.y + 1),
					"%s at %s stands on a floor" % [id, cell])


func test_a_level_carries_several_moods_worth_of_props() -> void:
	var ids := _ids()
	var kinds := {}
	for id_coords: Vector2i in _props(AsciiLevel.from_file(LEVEL)).values():
		kinds[ids[id_coords]] = true
	assert_gte(kinds.size(), 6, "level 1 shows the variety: %s" % ", ".join(kinds.keys()))


func test_dressing_is_deterministic() -> void:
	var level := AsciiLevel.from_file(LEVEL)
	assert_eq(_props(level), _props(level), "the same level dresses the same way twice")


func test_a_symmetric_arena_gets_symmetric_props() -> void:
	var level := AsciiLevel.from_file(ARENA)
	var props := _props(level)
	for cell: Vector2i in props:
		var twin := Vector2i(level.cols - 1 - cell.x, cell.y)
		assert_true(props.has(twin), "prop at %s has a mirror twin" % cell)
