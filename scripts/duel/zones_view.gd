class_name ZoneView
extends Node2D
## Puts the strip's zones into the world a few at a time, dressed and lit the
## way every other level is, and never while a fight is crossing a boundary.
##
## THE PROBLEM THIS SOLVES
## A fight that crosses a zone boundary must not stutter. The naive shapes both
## fail: loading a scene per zone drops frames exactly when two fighters are
## closest, and building all five zones up front works today only because the
## strip is five zones — it is O(zones) work and O(zones) collision bodies for
## something only ever one screen wide.
##
## WHAT IS STREAMED AND WHAT IS NOT
## Only this: the drawn tile layers. It builds no collision. The GEOMETRY the
## simulation reads is never streamed — ZoneStrip answers every query for every
## zone, always, from four thousand integers of ASCII, and the physics a fighter
## moves against is DuelMatch's ground layer, built whole once per match. A
## simulation whose answers depended on what had finished loading is a
## simulation two peers can disagree about, and the duel is checksummed.
##
## THE LEVEL PATH, NOT A SECOND ONE
## A zone is drawn exactly as scripts/world/level.gd draws a level: terrain,
## mid-ground architecture from WorldDresser, a foreground plane in front of the
## fighters, and the cast shadow from SunShadow sampled by the world shader. The
## layers, the paint and the shader material are Level's own static helpers;
## this file only decides WHEN, and over which cells.
##
## The strip is dressed ONCE, whole, at setup — `ZoneStrip.as_level()` is the
## five zones stitched into one AsciiLevel — so a terrace running across a seam
## gets one colonnade rather than two half ones, and the strip's mirror symmetry
## (tests/zone_strip_test.gd) gives a mirrored dressing for free, which is the
## same promise WorldDresser makes a duelling arena.
##
## The shadow is solved once per zone, also at setup, not per realise. The whole
## strip is 2400 px wide, and GL ES3 only promises a 2048 px texture, so one
## mask would be stored at half resolution (SunShadow.MAX_MASK_PX). A zone's
## mask is solved over the zone plus SHADOW_LEAD columns to its west: the sun
## is low in the west, shadows only ever fall east, and SunShadow cuts a shadow
## after REACH_TILES of travel, so what lands in a zone is cast inside that
## lead. tests/unit/test_zone_dressing.gd checks every zone's mask against a
## solve over everything to its west, pixel for pixel. The shader reads the
## mask through `mask_origin`, which is zero for a level.
##
## Nothing here can change a match. Decoration has no collision and no kind,
## every layer has collision switched off, and the strip is read, never
## written: the same strip, dressed or not, has the same identity() and the
## same checksum.
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

## Columns west of a zone that its shadow mask is solved over. The sun only
## casts east and SunShadow cuts a shadow after REACH_TILES (3) of travel; the
## margin past that is for a shadow that lands on stone and is carried on along
## it. The test compares against an unbounded lead, so a lead that is too short
## fails rather than looks slightly wrong.
const SHADOW_LEAD := 8

## How much of the foreground plane is drawn. In the adventure a column in
## front of the prince hides him for a step and costs nothing; in a duel it
## hides the other fighter's stance at the moment it is being read, and seeing
## your opponent at all times is the mode. So the plane stays -- it is the third
## depth plane, and the strip is flat without it -- but a fighter always reads
## through it.
const FORE_ALPHA := 0.55

var strip: ZoneStrip

## Zones whose layers are in the tree right now.
var realized: PackedInt32Array = PackedInt32Array()

## --- what the streaming test measures --------------------------------------
## Zones realised since setup, and the cells written for them.
var builds := 0
var cells_written := 0
## Zones released since setup.
var releases := 0
## True if the last focus() call wrote anything.
var built_last_focus := false

## --- what the dressing test and docs/world.md read -------------------------
## The strip's architecture, in strip cells: cell -> atlas coords, per plane.
var mid_decor: Dictionary = {}
var fore_decor: Dictionary = {}
## One shadow material per zone, its mask solved at setup.
var zone_materials: Array[ShaderMaterial] = []
## Milliseconds setup() spent dressing and solving shadows.
var dress_ms := 0.0
var shadow_ms := 0.0

## zone -> the Node2D holding that zone's layers and props.
var _zone_nodes: Dictionary = {}


func setup(zones: ZoneStrip) -> void:
	strip = zones
	for node: Node in _zone_nodes.values():
		remove_child(node)
		node.queue_free()
	_zone_nodes.clear()
	realized = PackedInt32Array()
	builds = 0
	releases = 0
	cells_written = 0

	var started := Time.get_ticks_usec()
	var whole := strip.as_level()
	var dressing := WorldDresser.dress(whole)
	# Architecture and the foreground only. The dresser's room moods (its
	# "props" plane: ivy, urns, rubble, lanterns) are left out of the duel on
	# purpose -- the duelling ground is a stage, not a lived-in street.
	mid_decor = dressing["mid"]
	fore_decor = dressing["fore"]
	dress_ms = float(Time.get_ticks_usec() - started) / 1000.0

	started = Time.get_ticks_usec()
	zone_materials.clear()
	for zone: int in strip.zone_count():
		zone_materials.append(_light_zone(zone))
	shadow_ms = float(Time.get_ticks_usec() - started) / 1000.0


## The columns a zone's shadow is solved over: [from, to) in strip cells.
func shadow_window(zone: int) -> Vector2i:
	var first := zone * strip.zone_cols
	return Vector2i(maxi(0, first - SHADOW_LEAD), first + strip.zone_cols)


## Solves one zone's cast shadow over its window and wraps it in the world
## shader, placed where the window sits in the strip.
func _light_zone(zone: int) -> ShaderMaterial:
	var window := shadow_window(zone)
	var level := strip.as_level(window.x, window.y)
	var mask := SunShadow.build(
		level, shift_cells(mid_decor, window.x, window.y), TILE, Level.atlas_image()
	)
	return Level.sun_material(mask, Rect2(
		float(window.x * TILE), 0.0,
		float(level.cols * TILE), float(level.rows * TILE)
	))


## The cells of `plane` in columns [from, to), where they are.
static func cells_between(plane: Dictionary, from: int, to: int) -> Dictionary:
	var out := {}
	for cell: Vector2i in plane:
		if cell.x >= from and cell.x < to:
			out[cell] = plane[cell]
	return out


## The cells of `plane` in columns [from, to), moved so `from` is column 0.
static func shift_cells(plane: Dictionary, from: int, to: int) -> Dictionary:
	var out := {}
	for cell: Vector2i in cells_between(plane, from, to):
		out[cell - Vector2i(from, 0)] = plane[cell]
	return out


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
		if not realized.has(zone):
			_realize(zone)
		kept.append(zone)
	realized = kept


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


## The zone's three planes, drawn as Level draws a level, and its torches.
## Collision is off on every layer: the ground a fighter stands on is
## DuelMatch's, built whole, and a streamed copy is one two peers could hold
## differently.
func _realize(zone: int) -> void:
	var node := Node2D.new()
	node.name = "Zone%d" % zone
	var tiles := Level.new_layer("Tiles", false, 0)
	var decor := Level.new_layer("Decor", false, 0)
	var fore := Level.new_layer("Fore", false, Level.FOREGROUND_Z)
	fore.self_modulate = Color(1.0, 1.0, 1.0, FORE_ALPHA)
	tiles.material = zone_materials[zone]
	decor.material = zone_materials[zone]
	for layer: TileMapLayer in [tiles, decor, fore]:
		node.add_child(layer)

	var first := zone * strip.zone_cols
	var last := first + strip.zone_cols
	for x: int in range(first, last):
		for y: int in strip.rows():
			var coords := strip.atlas_for(x, y)
			if coords.x >= 0:
				tiles.set_cell(Vector2i(x, y), 0, coords)
				cells_written += 1
	var mid := cells_between(mid_decor, first, last)
	var front := cells_between(fore_decor, first, last)
	Level.paint(decor, mid)
	Level.paint(fore, front)
	cells_written += mid.size() + front.size()

	for prop: Dictionary in strip.props:
		var cell: Vector2i = prop["cell"]
		if cell.x < first or cell.x >= last or String(prop["kind"]) != "torch":
			continue
		var torch := Torch.new()
		torch.name = "Torch_%d_%d" % [cell.x, cell.y]
		torch.position = Vector2(cell.x * TILE + TILE * 0.5, (cell.y + 1) * TILE)
		# A flame keeps its own light when dusk falls on the room around it.
		torch.add_to_group(MatchDusk.LIT)
		node.add_child(torch)

	add_child(node)
	_zone_nodes[zone] = node
	builds += 1
	built_last_focus = true


func _release(zone: int) -> void:
	var node: Node = _zone_nodes.get(zone)
	if node != null:
		remove_child(node)
		node.queue_free()
		_zone_nodes.erase(zone)
	releases += 1


## Is every cell of this zone in the tree?
func is_realized(zone: int) -> bool:
	return realized.has(zone)


## The drawn layers of a realised zone, by name ("Tiles", "Decor", "Fore"), or
## null. For tests and tools.
func layer(zone: int, layer_name: String) -> TileMapLayer:
	var node: Node = _zone_nodes.get(zone)
	return null if node == null else node.get_node_or_null(layer_name) as TileMapLayer
