class_name SunField
extends RefCounted
## The light of one level in play: its mirrors gathered, SunLight's network
## traced over the level as it stands this frame, and the answers every
## reader of the light wants from it.
##
## A mirror does not know where its beam goes until it knows which other
## mirrors are lit, and that is a question about all of them at once, so no
## one mirror can answer it alone. Rather than make one of them the owner of
## the others -- a node that has to exist first, survive a respawn and be
## found -- the field is a pure function of the nodes already in the tree:
## any reader asks `light_of(level)` and gets the same answer.
##
## The answer is traced at most once per physics step and again only when a
## mirror or a seal says something changed (`touch()`), so the mirrors, the
## seals, a Glassbearer's glass and the art all read one trace, in whatever
## order the level meets them. Keying on the physics step as well as on the
## touches means a door some other mechanism moved is seen by the next step at
## the latest.

const MIRRORS := &"sun_mirrors"
const SEALS := &"sun_seals"

## Bumped by anything that changes where light goes.
static var _version := 0
## level instance id -> {frame, version, light}
static var _cache: Dictionary = {}


## Something about the light changed: a mirror turned, a door opened.
static func touch() -> void:
	_version += 1


## SunLight.network() for `level` as it stands: its mirrors as their nodes
## have them, and the level's own cells -- overlay included, so a shut door
## stops light -- as what blocks it.
static func light_of(level: Level) -> Dictionary:
	if level == null or level.data == null:
		return {"lit": {}, "beams": [], "struck": {}}
	var key := level.get_instance_id()
	var frame := Engine.get_physics_frames()
	var held := _cache.get(key, {}) as Dictionary
	if not held.is_empty() and int(held["frame"]) == frame \
			and int(held["version"]) == _version:
		return held["light"]
	var mirrors := {}
	for mirror: SunMirror in mirrors_of(level):
		mirrors[mirror.cell()] = {
			"face": mirror.face, "turning": mirror.is_turning(), "sun": mirror.sun_reaches(),
		}
	var blocks := func(cell: Vector2i) -> bool:
		return SunField.stops_light(level.kind_at_cell(cell))
	var light := SunLight.network(mirrors, level.data.cols, level.data.rows, blocks)
	_cache[key] = {"frame": frame, "version": _version, "light": light}
	return light


## Whether the sun has gone under in `level`: a sunset mirror's count has run
## out (SunMirror, `sunset=`). From then on nothing is lit by the sun.
static func sun_is_down(level: Level) -> bool:
	if level == null or not level.is_inside_tree():
		return false
	for node: Node in level.get_tree().get_nodes_in_group(MIRRORS):
		var mirror := node as SunMirror
		if mirror != null and mirror.level == level and mirror.sunset_progress() >= 1.0:
			return true
	return false


## Whether a cell of `kind` stops a beam or a bolt: stone and one-way
## platforms do; ladders, spikes, water, backdrop and air do not.
static func stops_light(kind: Tiles.Kind) -> bool:
	return kind == Tiles.Kind.SOLID or kind == Tiles.Kind.PLATFORM


## Whether light from a beam is resting on any of `cells` now.
static func rests_on(level: Level, cells: Array[Vector2i]) -> bool:
	var struck: Dictionary = light_of(level)["struck"]
	for cell: Vector2i in cells:
		if struck.has(cell):
			return true
	return false


## Whether some beam crosses `cell` -- a Glassbearer's glass held up in one
## is lit by it.
static func beam_crosses(level: Level, cell: Vector2i) -> bool:
	for beam: Dictionary in light_of(level)["beams"]:
		if (beam["cells"] as Array).has(cell):
			return true
	return false


## Every mirror placed in `level`, in reading order of their cells.
static func mirrors_of(level: Level) -> Array[SunMirror]:
	var out: Array[SunMirror] = []
	if level == null or not level.is_inside_tree():
		return out
	for node: Node in level.get_tree().get_nodes_in_group(MIRRORS):
		var mirror := node as SunMirror
		if mirror != null and mirror.level == level and not mirror.is_queued_for_deletion():
			out.append(mirror)
	out.sort_custom(func(a: SunMirror, b: SunMirror) -> bool:
		return SunLight.reading_order(a.cell(), b.cell()))
	return out


## The mirror standing in `cell`, or null.
static func mirror_at(level: Level, cell: Vector2i) -> SunMirror:
	for mirror: SunMirror in mirrors_of(level):
		if mirror.cell() == cell:
			return mirror
	return null


## The sun seal one of whose cells is `cell`, or null.
static func seal_at(level: Level, cell: Vector2i) -> SunSeal:
	if level == null or not level.is_inside_tree():
		return null
	for node: Node in level.get_tree().get_nodes_in_group(SEALS):
		var seal := node as SunSeal
		if seal != null and seal.level == level and not seal.is_queued_for_deletion() \
				and seal.cells.has(cell):
			return seal
	return null
