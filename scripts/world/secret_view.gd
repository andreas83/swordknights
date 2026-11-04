class_name SecretView
extends Node2D
## How a level's secret rooms look: hidden, hinted at, and found.
##
## A secret is a seal and a room behind it (AsciiLevel, "secrets"). In play
## the room is already there — BACKDROP behind a false seal, behind a cracked
## one too — so the character's world needs no second copy. What has to lie
## is the picture, and this node owns every lie and its undoing:
##
## **The cover.** Every unfound secret is drawn as the stone it pretends to be,
## on a layer of its own over the terrain: the level's facade (AsciiLevel.
## facade()) supplies the tiles, so a wall with a room in it gets the caps,
## the lit edges and the dressing of a wall. The terrain layer underneath is
## painted as the level really is, so lifting the cover is the whole reveal.
##
## **The light.** The shadow is solved twice at build: once for the facade,
## which is what everybody sees until a secret is found, and once with every
## secret open. The masks differ only near the secrets, so each differing
## pixel is assigned to its nearest secret, and finding one copies its pixels
## from the open solve into the live mask. A found room is in its own shade
## with a shaft through the doorway, and nothing is re-solved in play: the
## cost is paid behind the wipe, as the first solve is (docs/world.md).
##
## **The tell.** The seal is drawn as a bricked-up doorway (straight joints
## down both jambs, smaller courses that never line up with the wall's), and
## it moves: air comes out of a false wall's joints, grit trickles out of a
## cracked one. Motion is what the eye catches at the edge of the frame, and
## one pixel at a time is little enough that a player who has not learned to
## look for it walks past. Ruin rooms crack walls too (WorldDresser), so the
## doorway's shape is the half of the tell that cannot be confused; the
## dresser's marks are cleared off every secret and the cells in front of it.
##
## **The reveal.** The cover drops out in an ordered dither spreading from the
## point of entry (assets/world_shadow.gdshader, `dissolve`), the room's light
## swaps in, and a cracked seal throws its stones. All presentation: it runs
## in `_process` and nothing the character can touch waits on it.

const DISSOLVE_FALSE := 0.55
const DISSOLVE_CRACKED := 0.32
## Seconds between puffs of draught from one seam, and between grains of grit.
const DRAUGHT_PERIOD := 2.6
const GRIT_PERIOD := 1.9
const DRAUGHT_TRAVEL := 13.0
const DEBRIS_TIME := 0.9
const DEBRIS_GRAVITY := 520.0

var data: AsciiLevel
## The level as currently drawn: unfound secrets solid.
var seen: AsciiLevel

var _level: Level
var _tile: int = 16
var _covers: Array[TileMapLayer] = []
var _tells: Array[TileMapLayer] = []
var _dissolving: Dictionary = {} ## secret index -> seconds into the reveal
## Each secret's seams: [cell, outward direction] for the tell to breathe from.
var _seams: Array = []
var _live: Image
var _open: Image
var _live_texture: ImageTexture
var _diff: Array[PackedInt32Array] = []
var _debris: Array[Dictionary] = []
var _time: float = 0.0


## Called by Level.build() after the terrain is painted and the sealed shadow
## solved. `dressing` is the facade's dressing, already cleared of secrets.
func setup(level: Level, physical: AsciiLevel, facade: AsciiLevel, dressing: Dictionary,
		live_mask: Image, live_texture: ImageTexture, atlas: Image) -> void:
	_level = level
	_tile = Level.TILE
	data = physical
	seen = facade
	_live = live_mask
	_live_texture = live_texture
	z_index = 1

	var sealed_texture: Texture2D = live_texture
	if live_mask != null:
		sealed_texture = ImageTexture.create_from_image(live_mask.duplicate() as Image)
		var everything := physical.copy()
		for index: int in physical.secrets.size():
			everything.open_secret(index)
		SunShadow.build(everything, dressing["mid"], _tile, atlas, dressing["props"])
		_open = SunShadow.last_mask
		# The open solve must not be the mask anyone else reads.
		SunShadow.last_mask = live_mask
		_diff = _split_diff(live_mask, _open)

	var covers_rect := Rect2(Vector2.ZERO, level.world_size())
	for index: int in physical.secrets.size():
		var cover := Level.new_layer("Secret%d" % index, false, 0)
		var tell := Level.new_layer("Tell%d" % index, false, 0)
		for layer: TileMapLayer in [cover, tell]:
			if sealed_texture != null:
				layer.material = Level.sun_material(sealed_texture, covers_rect)
			add_child(layer)
		_covers.append(cover)
		_tells.append(tell)
		_seams.append([])
		if physical.opened.has(index):
			continue
		_paint_cover(index)
		_paint_tells(index)


## Whether secret `index` is still drawn as stone.
func is_hidden(index: int) -> bool:
	return index >= 0 and index < _covers.size() and not seen.opened.has(index)


## Lifts secret `index`, spreading from `from` (world pixels). The level data
## must already be open (AsciiLevel.open_secret); this is only the picture.
func reveal(index: int, from: Vector2) -> void:
	if not is_hidden(index):
		return
	var secret: Dictionary = data.secrets[index]
	seen.opened[index] = true
	for cell: Vector2i in secret["cells"]:
		seen.set_kind(cell.x, cell.y, data.kind_at(cell.x, cell.y))
	_repaint_around(secret["cells"])

	if index < _diff.size() and _live != null:
		var bytes := _live.get_data()
		var open_bytes := _open.get_data()
		for i: int in _diff[index]:
			bytes[i] = open_bytes[i]
		_live.set_data(_live.get_width(), _live.get_height(), false, Image.FORMAT_L8, bytes)
		_live_texture.update(_live)

	var reach := 16.0
	for cell: Vector2i in secret["cells"]:
		var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * _tile
		reach = maxf(reach, centre.distance_to(from) + _tile)
	for layer: TileMapLayer in [_covers[index], _tells[index]]:
		var material := layer.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("dissolve_from", from)
			material.set_shader_parameter("dissolve_reach", reach)
	_tells[index].clear()
	_dissolving[index] = 0.0
	if String(secret["kind"]) == "cracked":
		_throw_stones(secret)


## Seconds a reveal of this kind takes to finish drawing.
static func reveal_time(kind: String) -> float:
	return DISSOLVE_CRACKED if kind == "cracked" else DISSOLVE_FALSE


## Drops the dresser's marks from every cell of every secret and from the open
## cells in front of its seal: a jar standing in a doorway hides the doorway,
## and a ruin room's crack painted on the seal would be a second tell telling
## a different story. Static, because Level runs it before anything is drawn.
static func clear_dressing(level: AsciiLevel, dressing: Dictionary) -> void:
	var keep_clear := {}
	for secret: Dictionary in level.secrets:
		for cell: Vector2i in secret["cells"]:
			keep_clear[cell] = true
		for cell: Vector2i in secret["seal"]:
			for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
				keep_clear[cell + step] = true
	for plane: String in ["mid", "props"]:
		var cells: Dictionary = dressing[plane]
		for cell: Vector2i in keep_clear:
			cells.erase(cell)


## --- drawing the lie -----------------------------------------------------------

func _paint_cover(index: int) -> void:
	var secret: Dictionary = data.secrets[index]
	for cell: Vector2i in secret["cells"]:
		# A cracked seal is real stone, painted and collided on the terrain
		# layer; only what is not really there needs a cover.
		if data.is_solid(cell.x, cell.y):
			continue
		_covers[index].set_cell(cell, 0, seen.atlas_for(cell.x, cell.y))


## The doorway over the seal, and the seams its tell breathes from. A seal
## column of two or more gets the crowned upper cell; a seal under open sky is
## a floor and gets the crack across its cap.
func _paint_tells(index: int) -> void:
	var secret: Dictionary = data.secrets[index]
	# A sun seal's tell is the sun carved in it, which its own mechanism
	# draws and fills (scripts/mechanisms/sun_seal.gd). A false wall's
	# breathing doorway on it would say "walk through", and it does not open
	# to a body.
	if String(secret["kind"]) == "sun":
		return
	var cracked := String(secret["kind"]) == "cracked"
	var seal_cells := {}
	for cell: Vector2i in secret["seal"]:
		seal_cells[cell] = true
	for cell: Vector2i in secret["seal"]:
		var below := seal_cells.has(cell + Vector2i.DOWN)
		var above := seal_cells.has(cell + Vector2i.UP)
		var capped := not seen.is_solid(cell.x, cell.y - 1)
		var id := ""
		if capped:
			id = "crack_cap" if cracked else ""
		elif below and not above:
			id = "crack_top" if cracked else "seal_top"
		else:
			id = "crack_foot" if cracked else "seal_foot"
		if id != "":
			_tells[index].set_cell(cell, 0, Tiles.DECOR_ATLAS[id])
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var out := cell + step
			if seal_cells.has(out) or seen.is_solid(out.x, out.y):
				continue
			if seen.kind_at(out.x, out.y) == Tiles.Kind.EMPTY:
				(_seams[index] as Array).append([cell, step])


## Repaints the terrain in and around a found secret from the level as it is
## now: a floor that had a room's facade over it gets its gold cap, the stone
## right of a doorway gets its lit edge, a cracked seal loses its collision.
func _repaint_around(cells: Array) -> void:
	var touched := {}
	for cell: Vector2i in cells:
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				touched[cell + Vector2i(dx, dy)] = true
	var tilemap := _level.tilemap
	for cell: Vector2i in touched:
		var other := seen.secret_at(cell)
		if other >= 0 and is_hidden(other) and not data.is_solid(cell.x, cell.y):
			continue
		var coords := seen.atlas_for(cell.x, cell.y)
		if coords.x >= 0:
			tilemap.set_cell(cell, 0, coords)
		else:
			tilemap.erase_cell(cell)
	# Now, not at the end of the frame: a plunge that opened a floor this
	# frame has to fall through it this frame, not land on its collision.
	tilemap.update_internals()


## Which differing mask pixels belong to which secret: the nearest one, by
## distance to its cells' bounding box. Secrets are rooms apart and a shadow
## reaches three tiles, so in practice no pixel is contested.
func _split_diff(sealed: Image, open: Image) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	var boxes: Array[Rect2] = []
	for secret: Dictionary in data.secrets:
		var box := Rect2((secret["cells"] as Array)[0] * _tile, Vector2.ZERO)
		for cell: Vector2i in secret["cells"]:
			box = box.expand(Vector2(cell) * _tile).expand(Vector2(cell + Vector2i.ONE) * _tile)
		boxes.append(box)
		out.append(PackedInt32Array())
	var a := sealed.get_data()
	var b := open.get_data()
	var w := sealed.get_width()
	var scale := float(data.cols * _tile) / float(w)
	for i: int in a.size():
		if a[i] == b[i]:
			continue
		var at := Vector2(float(i % w) + 0.5, float(i / w) + 0.5) * scale
		var best := 0
		var best_d := INF
		for k: int in boxes.size():
			var d := _distance_to_box(at, boxes[k])
			if d < best_d:
				best_d = d
				best = k
		out[best].append(i)
	return out


static func _distance_to_box(at: Vector2, box: Rect2) -> float:
	var dx := maxf(maxf(box.position.x - at.x, 0.0), at.x - box.end.x)
	var dy := maxf(maxf(box.position.y - at.y, 0.0), at.y - box.end.y)
	return Vector2(dx, dy).length()


## --- motion -------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	for index: int in _dissolving.keys():
		var t: float = float(_dissolving[index]) + delta
		_dissolving[index] = t
		var kind := String(data.secrets[index]["kind"])
		var amount := clampf(t / reveal_time(kind), 0.0, 1.0)
		for layer: TileMapLayer in [_covers[index], _tells[index]]:
			var material := layer.material as ShaderMaterial
			if material != null:
				material.set_shader_parameter("dissolve", maxf(amount, 0.001))
		if amount >= 1.0:
			_covers[index].clear()
			_dissolving.erase(index)
	for chunk: Dictionary in _debris:
		chunk["t"] = float(chunk["t"]) + delta
		var v: Vector2 = chunk["v"]
		v.y += DEBRIS_GRAVITY * delta
		chunk["v"] = v
		chunk["at"] = (chunk["at"] as Vector2) + v * delta
	_debris = _debris.filter(func(c: Dictionary) -> bool: return float(c["t"]) < DEBRIS_TIME)
	queue_redraw()


func _draw() -> void:
	for index: int in _seams.size():
		if not is_hidden(index):
			continue
		var cracked := String(data.secrets[index]["kind"]) == "cracked"
		var seams: Array = _seams[index]
		for n: int in seams.size():
			var cell: Vector2i = seams[n][0]
			var step: Vector2i = seams[n][1]
			if cracked:
				_draw_grit(cell, step, float(n) * 0.83 + float(index) * 0.37)
			else:
				_draw_draught(cell, step, float(n) * 1.1 + float(index) * 0.53)
	for chunk: Dictionary in _debris:
		var at := (chunk["at"] as Vector2).round()
		draw_rect(Rect2(at, chunk["size"]), chunk["colour"])


## Air leaving a false wall: a mote comes out of a joint and drifts away from
## the face, rising a little, then is gone. Two seams of one doorway breathe
## out of step, so it never looks like a pattern.
func _draw_draught(cell: Vector2i, step: Vector2i, phase: float) -> void:
	var cycle := fposmod(_time + phase, DRAUGHT_PERIOD) / DRAUGHT_PERIOD
	if cycle > 0.62:
		return
	var t := cycle / 0.62
	var origin := _seam_point(cell, step, phase)
	var drift := Vector2(step) * DRAUGHT_TRAVEL * t
	if step.y != 0:
		drift = Vector2(sin(t * 5.0 + phase) * 2.0, -DRAUGHT_TRAVEL * t)
	var at := (origin + drift + Vector2(0.0, -3.0 * t * t)).round()
	draw_rect(Rect2(at, Vector2.ONE), _dust_colour(at))


## Grit leaving a cracked wall: a grain works loose from the crack and drops
## down the face. On a cracked floor the crack breathes instead: the room
## below is air, and a floor over air is the one place dust rises.
func _draw_grit(cell: Vector2i, step: Vector2i, phase: float) -> void:
	if step.y != 0:
		_draw_draught(cell, step, phase)
		return
	var cycle := fposmod(_time + phase, GRIT_PERIOD) / GRIT_PERIOD
	if cycle > 0.4:
		return
	var t := cycle / 0.4
	var x := float(cell.x) * _tile + (_tile - 2.0 if step.x > 0 else 1.0)
	x += float(step.x) * 1.0
	var top := float(cell.y) * _tile + 6.0 + fposmod(phase * 7.0, 6.0)
	var at := Vector2(x, top + t * t * 14.0).round()
	draw_rect(Rect2(at, Vector2.ONE), _dust_colour(at))


func _seam_point(cell: Vector2i, step: Vector2i, phase: float) -> Vector2:
	var base := Vector2(cell) * _tile
	var along := 3.0 + fposmod(phase * 5.3, float(_tile) - 6.0)
	if step.x > 0:
		return base + Vector2(_tile, along)
	if step.x < 0:
		return base + Vector2(-1.0, along)
	return base + Vector2(along, -1.0)


## Lit air gets the ambience's dust colour, shaded air a tone the shade can
## carry: a LIGHT_SOFT pixel in crimson shadow would be a spark, not dust.
func _dust_colour(at: Vector2) -> Color:
	if _live == null:
		return Palette.LIGHT_SOFT
	var scale := float(_live.get_width()) / float(data.cols * _tile)
	var mx := int(at.x * scale)
	var my := int(at.y * scale)
	if mx < 0 or my < 0 or mx >= _live.get_width() or my >= _live.get_height():
		return Palette.LIGHT_SOFT
	return Palette.SHADOW_WARM if _live.get_pixel(mx, my).r > 0.5 else Palette.LIGHT_SOFT


## The seal's stones, thrown away from the blow: a few per cell, in the
## wall's own tones, falling under gravity and gone in under a second.
func _throw_stones(secret: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(secret["seal"])
	var colours := [Palette.SHADOW, Palette.SHADOW_DEEP, Palette.SHADOW_WARM, Palette.MID]
	for cell: Vector2i in secret["seal"]:
		var away := Vector2.ZERO
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			if not seen.is_solid(cell.x + step.x, cell.y + step.y) \
					and seen.secret_at(cell + step) < 0:
				away += Vector2(step)
		for i: int in 7:
			var at := (Vector2(cell) + Vector2(rng.randf(), rng.randf())) * _tile
			var v := Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-120.0, -20.0))
			v += away * rng.randf_range(30.0, 90.0)
			var size := 2.0 if i % 3 == 0 else 1.0
			_debris.append({"at": at, "v": v, "t": rng.randf() * 0.15,
				"size": Vector2(size, size), "colour": colours[i % colours.size()]})
