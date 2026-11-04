class_name SunBeamArt
extends Node2D
## A mirror's light: its polished face and the beam it throws, drawn hard.
##
## docs/art-direction.md allows no glow, no blur and no gradient, and the
## bible says what a beam is instead: two pixels of LIGHT_SOFT round a
## one-pixel PAPER core -- paper white is kept for the brightest specular, and
## a reflected sun is exactly that -- ending in a 3 x 3 lit diamond where it
## meets the stone. What makes it read as a shaft of light rather than a
## painted line is the dust: motes that drift across the beam and are drawn
## only while they are in it, the way LevelAmbience draws dust only where the
## mask says the air is lit. Nothing marks the edge of the light; the motes
## find it.
##
## Lifted out of the hour's grade (MatchDusk.LIT): a beam that dims at dusk is
## a beam nobody can follow, and Chapter IV is set at dusk. The mirror's
## bronze stays in the grade with the stone (SunMirror).
##
## Presentation only. It reads the level's traced light (SunField) and the
## mirror's turn, and it animates the dust on the display clock, which is the
## only clock a node that touches nothing should use.

## Half the beam's width either side of its core, in pixels.
const HALF := 1.0
## How far a beam into the sky is drawn past the top of the level.
const SKY_REACH := 240.0
## Motes per pixel of beam, and how far either side of it they wander.
const MOTE_DENSITY := 1.0 / 20.0
const MOTE_ROAM := 5.0
## How far past the band's edge a mote still catches the light.
const MOTE_GLINT := 2.5

var mirror: SunMirror

var _time := 0.0


func _ready() -> void:
	add_to_group(MatchDusk.LIT)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if mirror == null or mirror.level == null:
		return
	var light := SunField.light_of(mirror.level)
	var lit := (light["lit"] as Dictionary).has(mirror.cell())
	_draw_face(lit)
	if not lit or mirror.is_turning():
		return
	for beam: Dictionary in light["beams"]:
		if beam["from"] == mirror.cell():
			_draw_beam(beam)
			return


## The polished face: a lens on the side the light leaves by. PAPER when it
## is throwing the sun, a dull bronze when it is not.
func _draw_face(lit: bool) -> void:
	var r := SunMirror.GREAT_R if mirror.great else SunMirror.DISC_R
	var angle := mirror.face_angle()
	var normal := Vector2(cos(angle), sin(angle))
	var along := Vector2(-normal.y, normal.x)
	var lens := PackedVector2Array()
	for i: int in 7:
		var a := PI * float(i) / 6.0
		lens.append(along * cos(a) * r + normal * sin(a) * 1.6)
	var colour := Palette.LIGHT_SOFT if lit else Palette.MID
	draw_colored_polygon(lens, colour)
	if lit:
		draw_line(along * (r - 1.0), -along * (r - 1.0), Palette.PAPER, 1.0)


func _draw_beam(beam: Dictionary) -> void:
	var dir := Vector2(SunLight.step_of(int(beam["face"])))
	var length := _length(beam)
	if length <= 0.0:
		return
	var side := Vector2(absf(dir.y), absf(dir.x))
	# The beam: LIGHT_SOFT edges, a PAPER core, on whole pixels. It starts
	# at the rim of the disc rather than its axle, so the face stays legible.
	var r := SunMirror.GREAT_R if mirror.great else SunMirror.DISC_R
	var from := dir * (r - 1.0)
	var to := dir * length
	# The great mirror's is the last ray of the day, and broader for it: the
	# same two tones, a pixel wider each.
	var half := HALF + (1.0 if mirror.great else 0.0)
	_band(from, to, side, half, Palette.LIGHT_SOFT)
	_band(from, to, side, half - 1.0, Palette.PAPER)
	if String(beam["ends"]) == SunLight.ENDS_STONE:
		_diamond(to)
	_draw_dust(from, to, dir, side)


## How far from the pivot the beam runs: to the face of the stone it ends
## on, to the pivot of the mirror it lights, or off the level.
func _length(beam: Dictionary) -> float:
	var tile := float(Level.TILE)
	var cells: Array = beam["cells"]
	var span := float(cells.size()) * tile
	match String(beam["ends"]):
		SunLight.ENDS_MIRROR:
			return span + tile
		SunLight.ENDS_SKY:
			return span + tile * 0.5 + SKY_REACH
		_:
			return span + tile * 0.5


## One strip of the beam, `half` pixels either side of its centre line.
func _band(from: Vector2, to: Vector2, side: Vector2, half: float, colour: Color) -> void:
	var a := (from - side * half).floor()
	var b := (to + side * (half + 1.0)).floor()
	var rect := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)),
		Vector2(absf(b.x - a.x), absf(b.y - a.y)))
	if side.x > 0.0:
		rect.size.x = half * 2.0 + 1.0
	else:
		rect.size.y = half * 2.0 + 1.0
	draw_rect(rect, colour)


## The 3 x 3 lit diamond where light meets stone.
func _diamond(at: Vector2) -> void:
	var c := at.floor()
	draw_rect(Rect2(c.x - 1.0, c.y, 3.0, 1.0), Palette.PAPER)
	draw_rect(Rect2(c.x, c.y - 1.0, 1.0, 3.0), Palette.PAPER)


## Dust turning in the light: each mote drifts across the line of the beam
## and is drawn only while it is in the light's reach -- the air a pixel or
## two either side of the band, where a speck catching the sun shows against
## the dark. Inside the band it is lost in the beam; further out it is in
## shade. The motes find the edge of the light without anything drawing it.
func _draw_dust(from: Vector2, to: Vector2, dir: Vector2, side: Vector2) -> void:
	var length := (to - from).length()
	var count := maxi(1, int(length * MOTE_DENSITY))
	var seed_base := float(mirror.cell().x * 31 + mirror.cell().y * 17)
	for i: int in count:
		var s := fposmod(sin(seed_base + float(i) * 12.9898) * 43758.5453, 1.0)
		var speed := 0.35 + fposmod(s * 7.13, 1.0) * 0.5
		var along := fposmod(s + _time * speed * 0.04, 1.0) * length
		var drift := sin(_time * speed + s * TAU) * MOTE_ROAM
		if absf(drift) <= HALF + 0.5 or absf(drift) > HALF + MOTE_GLINT:
			continue
		var at := (from + dir * along + side * drift).floor()
		draw_rect(Rect2(at, Vector2.ONE), Palette.LIGHT_SOFT)
