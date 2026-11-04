class_name SecretKeeper
extends RefCounted
## The rules of a level's secret rooms, in play: what opens one, what is in
## it, and how many have been found.
##
## Three ways in, one per seal (Tiles.SEAL_LEGEND), and each is something the
## player does on purpose once they have read the tell. The third -- a
## doorway with a sun carved in it, which only light opens -- is not checked
## here at all: its seal mechanism counts the light and calls open_at() when
## it is full (scripts/mechanisms/sun_seal.gd). The other two:
##
## - **A false wall opens to the body.** The seal was never stone, so the
##   first frame the character's body overlaps any cell of the secret, it is
##   found. Nobody presses into a wall they have no reason to doubt; somebody
##   who has noticed the doorway does.
## - **A cracked wall opens to the blade.** The seal is real stone until the
##   sword's rect overlaps it — a swing at a wall, or the plunge's point coming
##   down on a cracked floor, which then lets the character through into the
##   cellar under it, still plunging. A plunge that lands squarely on the
##   crack in a frame the blade was not checked (Player emits plunge_landed on
##   the frame it touches down) opens it too. So does a thrown sword's point
##   going into it (PrinceBlade.bite): it is the same blade, and a crack seen
##   across a gap is a crack worth throwing at. Safe by the proof already --
##   every combination of open secrets is audited never to be a trap.
##
## A hard landing does not open anything: a fall the player did not choose is
## luck, and secrets are for looking, not for luck.
##
## What a room holds is hidden until it is found, so a relic in a sealed room
## cannot glint through the stone over it. Found secrets stay found for the
## rest of the attempt, through deaths and checkpoints, like a relic picked up;
## a restart seals them all again.
##
## Kept out of Game so that file stays the arbiter of the level's *core*
## interactions; Game asks this once a physics frame and reacts to `found`.

signal found(index: int, kind: String, at: Vector2)

var level: Level
var count: int = 0
var total: int = 0

var _pristine: AsciiLevel
var _contents: Dictionary = {} ## secret index -> Array of the nodes inside
var _plunged := false


## Called once the level is built. Keeps a copy of the level as authored, so
## a restart can seal what this attempt opened.
func setup(p_level: Level, player: Player) -> void:
	level = p_level
	_pristine = level.data.copy()
	total = level.data.secrets.size()
	count = level.data.opened.size()
	if not player.plunge_landed.is_connected(_on_plunge_landed):
		player.plunge_landed.connect(_on_plunge_landed)


## Seals every secret again and rebuilds the level as authored. Game calls it
## behind the restart's wipe, and only when something was opened: a rebuild
## re-solves the shadow, which is a wipe's worth of work.
func reseal() -> void:
	if level == null or count == 0:
		return
	level.build(_pristine.copy())
	count = 0


## Spawns what only secrets have — inscriptions — into `entities`, then hides
## everything in a room not yet found. Game calls it right after it spawns
## the level's own entities.
func furnish(entities: Node) -> void:
	var data := level.data
	var order := 0
	for mark: Dictionary in data.entities:
		if String(mark["kind"]) != "inscription":
			continue
		var words := Inscription.new()
		words.position = level.entity_world_position(mark["cell"])
		words.lines = Inscription.text_for(data.name, order)
		entities.add_child(words)
		order += 1

	_contents.clear()
	for node: Node in entities.get_children():
		if not node is Node2D:
			continue
		var at := (node as Node2D).position + Vector2(0.0, -1.0)
		var index := data.secret_at(level.cell_of(at))
		if index < 0 or data.opened.has(index):
			continue
		(node as Node2D).visible = false
		if not _contents.has(index):
			_contents[index] = []
		(_contents[index] as Array).append(node)


## Checks this frame's body and blade against every unfound secret. Returns
## the index found, or -1. At most one a frame: two at once would be two
## banners over each other, and the second simply opens on the next frame.
func resolve(player: Player) -> int:
	var data := level.data
	var body := player.body_rect()
	var blade := player.attack_rect()
	var plunged := _plunged
	_plunged = false
	for index: int in data.secrets.size():
		if data.opened.has(index):
			continue
		var secret: Dictionary = data.secrets[index]
		# A sun seal opens to light and to nothing the prince does with his
		# body: its seal mechanism asks for it through open_at().
		if String(secret["kind"]) == "sun":
			continue
		if String(secret["kind"]) == "false":
			var met := _overlap(body, secret["cells"])
			if met.has_area():
				return _find(index, met.get_center())
			continue
		if blade.has_area():
			var cut := _overlap(blade, secret["seal"])
			if cut.has_area():
				return _find(index, cut.get_center())
		var thrown := _overlap(player.moves.blade.bite, secret["seal"])
		if thrown.has_area():
			return _find(index, thrown.get_center())
		if plunged:
			var point := Rect2(body.position.x, body.end.y, body.size.x, Tuning.PLUNGE_REACH)
			var bite := _overlap(point, secret["seal"])
			if bite.has_area():
				return _find(index, bite.get_center())
	return -1


## Finds the unfound secret whose seal or room holds `cell`, from `at`: the
## way in for what is not the prince's body or blade -- a sun seal that light
## has filled (scripts/mechanisms/sun_seal.gd). True when one was found now.
func open_at(cell: Vector2i, at: Vector2) -> bool:
	if level == null:
		return false
	var index := level.data.secret_at(cell)
	if index < 0 or level.data.opened.has(index):
		return false
	_find(index, at)
	return true


func _find(index: int, at: Vector2) -> int:
	level.open_secret(index, at)
	count += 1
	for node: Variant in _contents.get(index, []):
		if is_instance_valid(node):
			(node as Node2D).visible = true
	_contents.erase(index)
	found.emit(index, String(level.data.secrets[index]["kind"]), at)
	return index


## The part of `rect` over any of `cells`, or an empty rect. The first one
## found is enough: it is only used for where the reveal spreads from.
func _overlap(rect: Rect2, cells: Array) -> Rect2:
	var tile := float(Level.TILE)
	for cell: Vector2i in cells:
		var box := Rect2(Vector2(cell) * tile, Vector2(tile, tile))
		var met := rect.intersection(box)
		if met.has_area():
			return met
	return Rect2()


func _on_plunge_landed() -> void:
	_plunged = true
