class_name HazardView
extends Node2D
## Draws a strip's blades, water and crumbling stone, and rings their sounds.
## Presentation only: it reads the match's frame and `stones`, and nothing it
## holds reaches a step, a snapshot or a checksum.
##
## ## Read from the state, never from events
##
## Everything here is drawn from what the match says NOW: a blade's swing from
## the frame (StripHazards is a pure function of it), the water from the frame,
## a slab from its byte. So a client that a correction rewinds draws the
## host's blades and the host's floor on the next frame, with nothing to take
## back -- the rope's rule in docs/netplay.md, "Corrected outcomes": a thing
## that reads the state is never wrong for longer than the state is. The one
## record a correction could leave behind, a slab's fall, is a beat (the dust
## and the sound, DuelMatch.stone_fell), rung once by the ledger.
##
## The blades' own sounds -- the ratchet's three ticks, the cut -- are keyed on
## the frame too, and each frame is heard at most once however often a client
## steps it: `_heard` only moves forward.
##
## ## Steel is for blades
##
## A scythe and a slot are drawn in STEEL on INK and nothing else is
## (docs/art-direction.md). Each tells for StripHazards.TELL frames: the
## scythe is drawn back a notch at each tick and its edge catches the light,
## the slot's tips rattle at the grille. The water is teal, the one accent the
## palette gives it, with a paper line where it meets the air; its tell is the
## sluices gushing from the walls before it moves, and a tide mark on the
## stone says how high it will come. A slab of crumbling stone is the floor's
## own tile with one ink crack across its cap, the campaign's tell for stone
## that gives.
##
## The whole view is in MatchDusk.LIT: no hour of the day dims a tell.

## A scythe at rest hangs this far off the vertical, radians: well out of its
## lane, so a resting blade never reads as a cutting one.
const REST := 1.05
## The tell draws it back this much further, in three ratchet notches.
const COCK := 0.35
## Frames the swing takes to come up out of the lane to its rest after a cut.
const FOLLOW := 14
## Grit shed by a burning slab: one grain every this many frames.
const GRIT_FRAMES := 4
## Frames a fallen slab's drop and dust are drawn for.
const DROP_FRAMES := 24
## Water drawn over the fighters, so a drowned body is under it.
const WATER_Z := 1

var strip: ZoneStrip
var fight: DuelMatch
## The world shader per zone, from ZoneView, so a slab takes the sun as the
## floor beside it does. Optional: without it a slab is drawn unlit.
var zone_materials: Array[ShaderMaterial] = []

var _water: Node2D
var _stones: Array[Node2D] = []
## The newest frame whose sounds have been rung.
var _heard := -1
## index -> the frame (of this view's own count) its drop began, for the fall.
var _dropping := {}
var _last_stones := PackedByteArray()
var _ticks := 0


func setup(zones: ZoneStrip, match_node: DuelMatch, materials: Array[ShaderMaterial] = []) -> void:
	strip = zones
	fight = match_node
	zone_materials = materials
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_stones.clear()
	_dropping.clear()
	_heard = -1
	_last_stones = PackedByteArray()
	add_to_group(MatchDusk.LIT)

	_water = Node2D.new()
	_water.name = "Water"
	_water.z_index = WATER_Z
	_water.draw.connect(_draw_water)
	add_child(_water)
	if strip == null:
		return
	for zone: int in strip.zone_count():
		var layer := Node2D.new()
		layer.name = "Stone%d" % zone
		layer.show_behind_parent = true
		if zone < zone_materials.size():
			layer.material = zone_materials[zone]
		var at := zone
		layer.draw.connect(func() -> void: _draw_stone_zone(layer, at))
		add_child(layer)
		_stones.append(layer)


func is_active() -> bool:
	return strip != null and fight != null and not strip.hazards.is_empty()


func _process(_delta: float) -> void:
	if not is_active():
		return
	_ticks += 1
	_note_falls()
	_ring()
	queue_redraw()
	_water.queue_redraw()
	for layer: Node2D in _stones:
		layer.queue_redraw()


## What the camera shows, in world space, a tile wider each side.
func _seen() -> Rect2:
	var view := get_viewport_rect()
	var to_world := get_canvas_transform().affine_inverse()
	return (to_world * view).grow(ZoneStrip.TILE)


## --- sound --------------------------------------------------------------------

func _ring() -> void:
	var now := fight.frame - 1
	if _heard < 0 or now - _heard > 30:
		_heard = now - 1
	var seen := _seen()
	while _heard < now:
		_heard += 1
		for blade: Dictionary in strip.hazards.blades:
			if not seen.intersects(blade["rect"] as Rect2):
				continue
			_blade_sounds(blade, _heard)
		for flood: Dictionary in strip.hazards.floods:
			if seen.intersects(flood["rect"] as Rect2):
				_flood_sounds(flood, _heard)


func _blade_sounds(blade: Dictionary, frame: int) -> void:
	var t := StripHazards.beat_of(blade, frame)
	var start := StripHazards.PERIOD - StripHazards.TELL
	var slot := int(blade["kind"]) == StripHazards.Kind.SLOT
	for step: int in 3:
		if t == start + step * StripHazards.TELL / 3:
			GameAudio.cue(&"ladder", {"pitch": (2.5 if slot else 1.4) + 0.1 * step,
				"volume_db": -12.0})
	if t == 0 and StripHazards.is_live(blade, frame):
		if slot:
			GameAudio.cue(&"masonry", {"pitch": 2.0, "volume_db": -10.0})
		GameAudio.cue(&"sword_hit", {"pitch": 1.6 if slot else 0.8, "volume_db": -9.0})


func _flood_sounds(flood: Dictionary, frame: int) -> void:
	var t := posmod(frame - int(flood["phase"]), StripHazards.FLOOD_PERIOD)
	if t == StripHazards.FLOOD_DRY - StripHazards.SLUICE_TELL:
		GameAudio.cue(&"chain", {"pitch": 0.7, "volume_db": -6.0})
	if t >= StripHazards.FLOOD_DRY - StripHazards.SLUICE_TELL \
			and t < StripHazards.FLOOD_DRY + StripHazards.FLOOD_RISE and t % 20 == 0:
		GameAudio.cue(&"wind", {"pitch": 1.8, "volume_db": -14.0})


## A slab seen to go from holding to fallen starts its drop here: the view's
## own clock, presentation only. The state already says it is gone.
func _note_falls() -> void:
	var now := fight.stones
	for i: int in now.size():
		var was := _last_stones[i] if i < _last_stones.size() else 0
		if StripHazards.has_fallen(now[i]) and not StripHazards.has_fallen(was):
			_dropping[i] = _ticks
		elif not StripHazards.has_fallen(now[i]):
			_dropping.erase(i)
	_last_stones = now.duplicate()


## --- blades -------------------------------------------------------------------

func _draw() -> void:
	if not is_active():
		return
	var seen := _seen()
	for blade: Dictionary in strip.hazards.blades:
		var reach := (blade["rect"] as Rect2).grow(64.0)
		if not seen.intersects(reach):
			continue
		if int(blade["kind"]) == StripHazards.Kind.SLOT:
			_draw_slot(blade)
		else:
			_draw_scythe(blade)
	for flood: Dictionary in strip.hazards.floods:
		_draw_sluices(flood)
	_draw_cracks()


## The Well's spike slot: a grille cut in the floor's lip, four steel points a
## cell while up, the tips rattling at the lip through the tell.
func _draw_slot(blade: Dictionary) -> void:
	var frame := fight.frame
	var live := StripHazards.is_live(blade, frame)
	var t := StripHazards.beat_of(blade, frame)
	var height := 0.0
	if live:
		height = 11.0 * minf(1.0, float(t + 1) / 2.0)
	elif StripHazards.is_telling(blade, frame):
		height = 1.0 + float(int(StripHazards.tell_progress(blade, frame) * 3.0) % 2)
	for cell: Vector2i in blade["cut"]:
		var box := Rect2(Vector2(cell * ZoneStrip.TILE), Vector2.ONE * ZoneStrip.TILE)
		var lip := box.end.y
		draw_rect(Rect2(box.position.x + 1.0, lip, box.size.x - 2.0, 3.0), Palette.INK)
		for i: int in 4:
			draw_rect(Rect2(box.position.x + 2.0 + 4.0 * i, lip, 1.0, 3.0),
				Palette.SHADOW_DEEP)
		if height <= 0.0:
			continue
		for i: int in 4:
			var cx := box.position.x + float(i) * 4.0 + 2.0
			var h := roundf(height)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 2.0, lip), Vector2(cx, lip - h), Vector2(cx + 2.0, lip),
			]), Palette.STEEL)
			draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 2.0, lip), Vector2(cx, lip - h), Vector2(cx, lip),
			]), Palette.STEEL_DARK)
			if not live:
				draw_rect(Rect2(cx, lip - h, 1.0, 1.0), Palette.PAPER)


## A pendulum blade hung from its beam: it swings through the lane during the
## cut, one way and then, next beat, back the other, and rests well out of it
## between, drawn back a notch at each tick of the tell.
func _draw_scythe(blade: Dictionary) -> void:
	var cut: Array[Vector2i] = blade["cut"]
	var arm: Array[Vector2i] = blade["arm"]
	var top := cut[0].y
	for cell: Vector2i in arm:
		top = mini(top, cell.y)
	var tile := float(ZoneStrip.TILE)
	var pivot := Vector2(cut[0].x * tile + tile * 0.5, top * tile)
	var length := (cut[0].y - top) * tile + tile * 0.5
	var angle := scythe_angle(blade, fight.frame)
	var tip := pivot + Vector2(sin(angle), cos(angle)) * length
	# Cutting, the blade drags a darker one a few frames behind it: the swing
	# is read as a sweep across the lane, not a blade that blinks into it.
	if StripHazards.is_live(blade, fight.frame):
		var behind := scythe_angle(blade, fight.frame - 3)
		_draw_crescent(pivot + Vector2(sin(behind), cos(behind)) * length, behind, false,
			Palette.STEEL_DARK)
	# The arm, as the Well's scythe draws its own: ink on a shadow edge, so it
	# reads on the dark stone at night as well as against the sky.
	draw_line(pivot, tip, Palette.SHADOW_DEEP, 4.0)
	draw_line(pivot, tip, Palette.INK, 2.0)
	draw_circle(pivot, 3.5, Palette.SHADOW_DEEP)
	draw_circle(pivot, 2.5, Palette.INK)
	draw_rect(Rect2(pivot - Vector2(0.5, 0.5), Vector2.ONE), Palette.SHADOW_WARM)
	_draw_crescent(tip, angle, StripHazards.is_telling(blade, fight.frame))


## The swing, as an angle off the vertical (0 is the blade in its lane).
## Public so a test can hold "drawn in the lane exactly while it cuts".
static func scythe_angle(blade: Dictionary, frame: int) -> float:
	var t := StripHazards.beat_of(blade, frame)
	var cycle := floori(float(frame - int(blade["phase"])) / StripHazards.PERIOD)
	# Which way this beat's swing goes; the next beat comes back.
	var way := 1.0 if posmod(cycle, 2) == 0 else -1.0
	var live := StripHazards.live_frames(blade)
	var cross := 0.42
	if t < live:
		return way * lerpf(-cross, cross, float(t) / float(live - 1))
	if t < live + FOLLOW:
		return way * lerpf(cross, REST, float(t - live) / float(FOLLOW))
	var tell_from := StripHazards.PERIOD - StripHazards.TELL
	if t < tell_from:
		return way * REST
	# The ratchet: three notches back, then let go into the next swing, which
	# comes from this side.
	var notch := mini(3, 1 + (t - tell_from) * 3 / StripHazards.TELL)
	return way * (REST + COCK * float(notch) / 3.0)


## A crescent of steel across the end of the arm, its edge leading.
func _draw_crescent(tip: Vector2, angle: float, glint: bool,
		steel: Color = Palette.STEEL) -> void:
	var across := Vector2(cos(angle), -sin(angle))
	var down := Vector2(sin(angle), cos(angle))
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i: int in 7:
		var u := lerpf(-1.0, 1.0, float(i) / 6.0)
		var bow := 1.0 - u * u
		outer.append(tip + across * (u * 9.0) + down * (bow * 4.0 + 1.0))
		inner.append(tip + across * (u * 7.0) + down * (bow * 1.5 - 1.0))
	var shape := outer.duplicate()
	inner.reverse()
	shape.append_array(inner)
	draw_colored_polygon(shape, steel)
	draw_polyline(outer, Palette.STEEL_DARK, 1.0)
	if glint:
		draw_rect(Rect2(outer[3].round(), Vector2(1.0, 1.0)), Palette.PAPER)


## --- water -------------------------------------------------------------------

## The sluice mouths in the basin's walls, always (they are the tell's source,
## and static), and their gush while the tell runs and the water rises.
func _draw_sluices(flood: Dictionary) -> void:
	var rect: Rect2 = flood["rect"]
	var frame := fight.frame
	var gushing := StripHazards.is_gushing(flood, frame)
	var t := posmod(frame - int(flood["phase"]), StripHazards.FLOOD_PERIOD)
	var rising := t >= StripHazards.FLOOD_DRY \
		and t < StripHazards.FLOOD_DRY + StripHazards.FLOOD_RISE
	var surface := StripHazards.surface_of(flood, frame)
	# The tide mark: how high the water comes, one dark line on each wall.
	for x: float in [rect.position.x - 2.0, rect.end.x]:
		draw_rect(Rect2(x, rect.position.y, 2.0, 1.0), Palette.WATER_SHADE)
	for side: int in 2:
		var x := rect.position.x + 1.0 if side == 0 else rect.end.x - 5.0
		var mouth := Rect2(x, rect.position.y - 6.0, 4.0, 3.0)
		draw_rect(mouth, Palette.INK)
		if not (gushing or rising):
			continue
		var fall := Rect2(x + 0.5, mouth.end.y, 3.0, maxf(0.0, surface - mouth.end.y))
		draw_rect(fall, Palette.WATER)
		var fleck := float((frame * 3 + side * 7) % 9)
		for k: int in 3:
			var y := mouth.end.y + fmod(fleck + k * 9.0, maxf(1.0, fall.size.y))
			draw_rect(Rect2(x + 1.0 + (k % 2), y, 1.0, 2.0), Palette.PAPER)


func _draw_water() -> void:
	if not is_active():
		return
	var frame := fight.frame
	for flood: Dictionary in strip.hazards.floods:
		var rect: Rect2 = flood["rect"]
		var surface := roundf(StripHazards.surface_of(flood, frame))
		if surface >= rect.end.y - 0.5:
			continue
		var body := Rect2(rect.position.x, surface, rect.size.x, rect.end.y - surface)
		_water.draw_rect(body, Palette.with_alpha(Palette.WATER_DEEP, 0.82))
		_water.draw_rect(Rect2(body.position, Vector2(body.size.x, minf(3.0, body.size.y))),
			Palette.WATER)
		_water.draw_rect(Rect2(body.position, Vector2(body.size.x, 1.0)), Palette.PAPER)
		# Ripples on the surface, moving with the frame so a still pool looks
		# still and a rising one does not.
		var drift := float(frame / 6 % 12)
		var x := body.position.x + drift
		while x < body.end.x - 3.0:
			_water.draw_rect(Rect2(x, body.position.y + 1.0, 3.0, 1.0), Palette.LIGHT_SOFT)
			x += 12.0


## --- crumbling stone -----------------------------------------------------------

func _draw_stone_zone(layer: Node2D, zone: int) -> void:
	if not is_active() or strip.hazards.stone_count() == 0:
		return
	var atlas := Level.TILE_SET.get_source(0) as TileSetAtlasSource
	var tile := float(ZoneStrip.TILE)
	var first := zone * strip.zone_cols
	var last := first + strip.zone_cols
	for i: int in strip.hazards.stone_count():
		var cell: Vector2i = strip.hazards.stones[i]
		if cell.x < first or cell.x >= last:
			continue
		var box := drawn_slab(i)
		if box.size == Vector2.ZERO:
			continue
		if atlas != null and atlas.texture != null:
			var source := Rect2(Vector2(_coords(cell)) * tile, Vector2(tile, tile))
			layer.draw_texture_rect_region(atlas.texture, box, source)
		else:
			layer.draw_rect(box, Palette.MID)


## The crack and the grit over every slab, on this node rather than the slabs'
## own: those draw through the world shader, which only knows atlas texels.
func _draw_cracks() -> void:
	for i: int in strip.hazards.stone_count():
		var box := drawn_slab(i)
		if box.size == Vector2.ZERO:
			continue
		var byte := fight.stones[i] if i < fight.stones.size() else 0
		_draw_crack(self, strip.hazards.stones[i], box, byte)
		if StripHazards.is_burning(byte) and (_ticks + i) % GRIT_FRAMES == 0:
			var grain := Vector2(box.position.x + 2.0 + float((_ticks * 5 + i * 3) % 12),
				box.end.y + float(_ticks % 5))
			draw_rect(Rect2(grain, Vector2.ONE), Palette.SHADOW_DEEP)


## Where slab `index` is drawn now, or an empty rect once it has fallen and
## finished falling.
func drawn_slab(index: int) -> Rect2:
	var byte := fight.stones[index] if index < fight.stones.size() else 0
	var box := slab_rect(index, byte)
	if not StripHazards.has_fallen(byte):
		return box
	if not _dropping.has(index):
		return Rect2()
	var age := _ticks - int(_dropping[index])
	if age > DROP_FRAMES:
		return Rect2()
	box.position.y += roundf(0.5 * 900.0 * pow(float(age) / 60.0, 2.0))
	return box


## Where slab `index` is drawn: its cell, shuddering a pixel every three frames
## while its fuse burns, and settled a pixel in the last third of it.
func slab_rect(index: int, byte: int) -> Rect2:
	var cell: Vector2i = strip.hazards.stones[index]
	var box := Rect2(Vector2(cell * ZoneStrip.TILE), Vector2.ONE * ZoneStrip.TILE)
	if StripHazards.is_burning(byte):
		box.position.x += [0.0, 1.0, 0.0, -1.0][(byte / 3) % 4]
		if byte * 3 > StripHazards.FUSE * 2:
			box.position.y += 1.0
	return box


## The atlas tile the slab would be if it were the floor's stone: capped when
## nothing solid is on it, lit when nothing solid is west of it.
func _coords(cell: Vector2i) -> Vector2i:
	var above := _solid_or_stone(cell + Vector2i.UP)
	var west := _solid_or_stone(cell + Vector2i.LEFT)
	if not above:
		return Tiles.ATLAS_SOLID_CAPPED if west else Tiles.ATLAS_SOLID_CAPPED_LIT
	return Tiles.ATLAS_SOLID_BURIED if west else Tiles.ATLAS_SOLID_BURIED_LIT


func _solid_or_stone(cell: Vector2i) -> bool:
	return strip.is_solid(cell.x, cell.y) or strip.hazards.stone_index(cell) >= 0


## One ink hairline across the cap, seeded by the cell; burning, it splits.
func _draw_crack(layer: Node2D, cell: Vector2i, box: Rect2, byte: int) -> void:
	var seed_of := absi(cell.x * 7 + cell.y * 13)
	var rise := [3.0, 4.0, 5.0, 4.0]
	var points := PackedVector2Array()
	for step: int in 5:
		var x := box.position.x + 1.0 + float(step) * 3.5
		points.append(Vector2(roundf(x), box.position.y + float(rise[(seed_of + step) % 4])))
	layer.draw_polyline(points, Palette.INK, 1.0)
	if not StripHazards.is_whole(byte):
		layer.draw_line(points[2], points[2] + Vector2(0.0, 6.0), Palette.INK, 1.0)
