extends SceneTree
## Scratch diagnostic: dumps a level's dressing and its shadow mask.
##
##     godot --headless --script tests/world_debug.gd -- res://levels/level_01.txt /tmp/out

var _path := "res://levels/level_01.txt"
var _out := "/tmp/world_debug"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_path = args[0]
	if args.size() > 1:
		_out = args[1]

	var level: AsciiLevel = null
	if _path.begins_with("generated:"):
		var result := LevelGenerator.build(int(_path.substr(10)), 170, 0.55)
		if not bool(result["ok"]):
			printerr("generation failed: ", result["reason"])
			quit(1)
			return
		level = result["level"] as AsciiLevel
	else:
		level = AsciiLevel.from_file(_path)
	print("level %s  %dx%d  authored decor marks: %d"
		% [level.name, level.cols, level.rows, level.decorations.size()])

	var started := Time.get_ticks_usec()
	var dressing := WorldDresser.dress(level)
	print("dress: %.1f ms" % (float(Time.get_ticks_usec() - started) / 1000.0))

	var mid: Dictionary = dressing["mid"]
	var fore: Dictionary = dressing["fore"]
	print("mid decor cells: %d   fore decor cells: %d" % [mid.size(), fore.size()])
	_histogram("mid", mid)
	_histogram("fore", fore)

	var atlas := (load("res://assets/tiles.png") as Texture2D).get_image()
	started = Time.get_ticks_usec()
	var mask := SunShadow.build(level, mid, 16, atlas)
	var ms := float(Time.get_ticks_usec() - started) / 1000.0
	var image := mask.get_image()
	var shaded := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).r > 0.5:
				shaded += 1
	var total := image.get_width() * image.get_height()
	print("shadow: %dx%d solved in %.1f ms, %.1f%% of the level in shade"
		% [image.get_width(), image.get_height(), ms, 100.0 * shaded / total])
	print("  phases: ", SunShadow.timings)
	var again := Time.get_ticks_usec()
	SunShadow.build(level, mid, 16, atlas)
	print("  second build (atlas masks cached): %.1f ms"
		% (float(Time.get_ticks_usec() - again) / 1000.0))
	print("  phases: ", SunShadow.timings)

	DirAccess.make_dir_recursive_absolute(_out)
	image.save_png("%s/mask.png" % _out)
	_composite(level, mid, fore, atlas, image).save_png("%s/level.png" % _out)
	_save_plan(level, mid, fore, "%s/plan.txt" % _out)
	print("wrote %s/mask.png and %s/plan.txt" % [_out, _out])
	quit(0)


## Draws the whole level exactly as the world shader would, so a dressing
## change can be judged without walking a camera across it.
func _composite(level: AsciiLevel, mid: Dictionary, fore: Dictionary,
		atlas: Image, mask: Image) -> Image:
	var tile := 16
	var out := Image.create_empty(level.cols * tile, level.rows * tile, false, Image.FORMAT_RGBA8)
	out.fill(Color("1a0610"))
	var shade_rows := Tiles.SHADE_ROW_OFFSET
	for y: int in level.rows:
		for x: int in level.cols:
			var cell := Vector2i(x, y)
			var stack: Array[Vector2i] = []
			var coords := level.atlas_for(x, y)
			if coords.x >= 0:
				stack.append(coords)
			if mid.has(cell):
				stack.append(mid[cell])
			for source: Vector2i in stack:
				_blit(out, atlas, source, cell, tile, mask, shade_rows)
			if fore.has(cell):
				_blit(out, atlas, fore[cell], cell, tile, null, shade_rows)
	return out


func _blit(out: Image, atlas: Image, source: Vector2i, cell: Vector2i, tile: int,
		mask: Image, shade_rows: int) -> void:
	for py: int in tile:
		for px: int in tile:
			var wx := cell.x * tile + px
			var wy := cell.y * tile + py
			var shaded := mask != null and mask.get_pixel(
				mini(wx * mask.get_width() / out.get_width(), mask.get_width() - 1),
				mini(wy * mask.get_height() / out.get_height(), mask.get_height() - 1)
			).r > 0.5
			var row := source.y + (shade_rows if shaded else 0)
			var c := atlas.get_pixel(source.x * tile + px, row * tile + py)
			if c.a > 0.5:
				out.set_pixel(wx, wy, c)


func _histogram(label: String, plane: Dictionary) -> void:
	var names := {}
	for coord: Vector2i in Tiles.DECOR_ATLAS.values():
		names[coord] = ""
	for id: String in Tiles.DECOR_ATLAS:
		names[Tiles.DECOR_ATLAS[id]] = id
	var counts := {}
	for cell: Vector2i in plane:
		var id: String = names.get(plane[cell], "?")
		counts[id] = int(counts.get(id, 0)) + 1
	var keys := counts.keys()
	keys.sort()
	for id: String in keys:
		print("  %-6s %-16s %d" % [label, id, counts[id]])


func _save_plan(level: AsciiLevel, mid: Dictionary, fore: Dictionary, path: String) -> void:
	var names := {}
	for id: String in Tiles.DECOR_ATLAS:
		names[Tiles.DECOR_ATLAS[id]] = id
	var lines := PackedStringArray()
	for y: int in level.rows:
		var line := ""
		for x: int in level.cols:
			var cell := Vector2i(x, y)
			if fore.has(cell):
				line += String(names[fore[cell]]).substr(5, 1).to_upper()
			elif mid.has(cell):
				line += String(names[mid[cell]]).substr(0, 1)
			elif level.is_solid(x, y):
				line += "#"
			elif level.kind_at(x, y) != Tiles.Kind.EMPTY:
				line += "-"
			else:
				line += "."
		lines.append(line)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
