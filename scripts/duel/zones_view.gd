class_name ZoneView
extends Node2D
## Puts the strip's zones into the world a few at a time, and never while a
## fight is crossing a boundary.
##
## THE PROBLEM THIS SOLVES
## A fight that crosses a zone boundary must not stutter. The naive shapes both
## fail: loading a scene per zone drops frames exactly when two fighters are
## closest, and building all five zones up front works today only because the
## strip is five zones — it is O(zones) work and O(zones) collision bodies for
## something only ever one screen wide.
##
## WHAT IS STREAMED AND WHAT IS NOT
## Only this: the TileMapLayer's cells, and therefore the physics bodies the
## engine builds from them. The GEOMETRY the simulation reads is never streamed
## — ZoneStrip answers every collision question for every zone, always, from
## four thousand integers of ASCII. A simulation whose answers depended on what
## had finished loading is a simulation two peers can disagree about, and the
## duel is checksummed.
##
## THE WORKING SET
## Three zones around the view, plus the zone each fighter is standing in, plus
## the zone each pending respawn is about to appear in. Bounded, and O(1) in the
## length of the strip: a twenty-zone strip realises the same four or five.
##
## WHY NOTHING IS EVER BUILT AT A SEAM
## The three-zone window is anchored to the NEAREST zone boundary rather than to
## the one behind the view, so it rolls forward when the view is half way across
## a zone — as far from a seam as it is possible to be. And a respawn's zone is
## realised when its two-second timer STARTS, not when the fighter appears, so
## the one build that is not triggered by travel has two seconds of warning.
## tests/zone_strip_test.gd walks a match across every seam in the strip and
## asserts that not one cell is written on a crossing frame.
##
## The decals do not live here. scripts/duel/gore.gd keeps its own bounded list
## per zone, so a zone released and realised again comes back with its history
## of who died where intact.

const TILE := ZoneStrip.TILE

## Zones either side of the window's anchor. One is enough: the window is one
## zone wide, so the anchor's neighbours always cover what is on screen.
const WINDOW_REACH := 1

var strip: ZoneStrip
var tilemap: TileMapLayer

## Zones whose cells are in the tilemap right now.
var realized: PackedInt32Array = PackedInt32Array()

## --- what the streaming test measures --------------------------------------
## Zones realised since setup, and the cells written for them.
var builds := 0
var cells_written := 0
## Zones released since setup.
var releases := 0
## True if the last focus() call wrote anything.
var built_last_focus := false

var _tile_set: TileSet = preload("res://assets/tiles.tres")
var _props: Node2D


func setup(zones: ZoneStrip) -> void:
	strip = zones

	if tilemap == null:
		tilemap = TileMapLayer.new()
		tilemap.name = "Tiles"
		tilemap.tile_set = _tile_set
		tilemap.collision_enabled = true
		add_child(tilemap)
	tilemap.clear()

	if _props == null:
		_props = Node2D.new()
		_props.name = "Props"
		add_child(_props)

	realized = PackedInt32Array()
	builds = 0
	releases = 0
	cells_written = 0


## Brings the working set up to date.
##
## `window_left` is the left edge of the view in strip coordinates — the
## authoritative scroll, so both peers realise the same zones. `interests` are
## world x values that must be standing on something: the fighters, and any
## respawn whose timer is running.
func focus(window_left: float, interests: PackedFloat32Array) -> void:
	built_last_focus = false
	if strip == null:
		return

	var wanted := _wanted_zones(window_left, interests)

	for zone: int in realized:
		if not wanted.has(zone):
			_release(zone)

	var kept := PackedInt32Array()
	for zone: int in wanted:
		if realized.has(zone):
			kept.append(zone)
		else:
			_realize(zone)
			kept.append(zone)
	realized = kept

	if built_last_focus:
		# A TileMapLayer rebuilds its collision on a deferred internal update,
		# so for one frame after a write the new zone would be scenery with
		# nothing solid in it. Forcing it means a zone realised this frame is
		# already standable this frame — which is what lets the respawn land on
		# ground that did not exist a moment ago.
		tilemap.update_internals()


## The window's three zones, anchored to the NEAREST boundary rather than the
## one behind it, plus a zone for every interest. See the class docstring.
func _wanted_zones(window_left: float, interests: PackedFloat32Array) -> PackedInt32Array:
	var last := strip.zone_count() - 1
	var anchor := clampi(roundi(window_left / strip.zone_width()), 0, last)
	var out := PackedInt32Array()
	for offset: int in range(-WINDOW_REACH, WINDOW_REACH + 1):
		var zone := anchor + offset
		if zone >= 0 and zone <= last and not out.has(zone):
			out.append(zone)
	for x: float in interests:
		var zone := strip.zone_of_x(x)
		if not out.has(zone):
			out.append(zone)
	return out


func _realize(zone: int) -> void:
	var first := zone * strip.zone_cols
	for x: int in range(first, first + strip.zone_cols):
		for y: int in strip.rows():
			var coords := strip.atlas_for(x, y)
			if coords.x >= 0:
				tilemap.set_cell(Vector2i(x, y), 0, coords)
				cells_written += 1
	for prop: Dictionary in strip.props:
		var cell: Vector2i = prop["cell"]
		if cell.x < first or cell.x >= first + strip.zone_cols:
			continue
		if String(prop["kind"]) != "torch":
			continue
		var torch := Torch.new()
		torch.name = "Torch_%d_%d" % [cell.x, cell.y]
		torch.position = Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)
		_props.add_child(torch)
	builds += 1
	built_last_focus = true


func _release(zone: int) -> void:
	var first := zone * strip.zone_cols
	for x: int in range(first, first + strip.zone_cols):
		for y: int in strip.rows():
			tilemap.erase_cell(Vector2i(x, y))
	for child: Node in _props.get_children():
		var prop := child as Node2D
		if prop == null:
			continue
		var column := floori(prop.position.x / TILE)
		if column >= first and column < first + strip.zone_cols:
			_props.remove_child(prop)
			prop.queue_free()
	releases += 1


## Is every cell of this zone in the tilemap?
func is_realized(zone: int) -> bool:
	return realized.has(zone)
