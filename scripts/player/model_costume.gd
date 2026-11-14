class_name ModelCostume
extends Costume
## What every 3D figure shares: a body built from meshes in code, rendered into
## a SubViewport and drawn back onto the 2D rig as one texture. A figure
## (PrincessCostume) extends this and says only what its parts are
## (`_make()`), what colour each takes (`_tones()`) and where each goes on the
## rig (`_pose_parts()`).
##
## ## Why a costume, and why the rig still drives it
##
## Everything that makes the game fair is in 2D: the hitbox, the tuning, the
## duel's blade rect, the netplay snapshot. A 3D figure that animated itself --
## a skeleton with its own clips -- would be a second source of truth for where
## a hand or a foot is, and the first pose added to player_art.gd would be a
## pose the model did not have. So a model has no animation of its own. Each
## frame it reads the joints PlayerArt has just placed -- hip, knee, foot,
## shoulder, elbow, hand, the torso points and the head -- lifts them into 3D
## at a fixed depth per side, and hangs a limb between each pair. Every pose
## the flat figures know is the model's, on the same frame, and the hand ends
## exactly where the 2D sword's hilt starts.
##
## The sword stays the shared 2D one. In the duel it is drawn along the rect
## the simulation parries with (FighterArt._draw_weapon), and a modelled sword
## would be a picture of that rect, never the rect. Drawing the texture in the
## body layer keeps PlayerArt's order: the blade hangs behind the body at
## rest and comes round in front of it on a swing.
##
## ## The camera
##
## Orthographic, one art unit per world unit, with the figure's feet at the
## art's origin. It is turned a little toward the way the figure faces, so the
## chest shows its breadth and both shoulders read, and turned the other way
## when it faces the other way, so the figure is the mirror of itself rather
## than showing its back. A turned camera would shift every point by its depth;
## `_lift()` pre-shears x by exactly that, so on screen each joint lands on the
## 2D point it came from whatever its depth. (tests/unit/test_model_figure.gd
## projects them back to check.) A head turns its face further, toward the
## viewer (`_head()`), so both eyes show whichever way the figure runs.
##
## ## The light
##
## The sun is the world's, as everywhere else (docs/art-direction.md): a key
## from the left, low and a little in front, so the lit half of every form is
## the world-left half whichever way the figure faces -- the same split the
## flat figures draw by hand, here falling out of the normals. A weak warm
## light from behind the far side gives the edge the ink rim gives the flat
## figures, and every part is drawn a second time as an inverted hull in ink:
## without that silhouette a crimson body vanishes into crimson stone however
## well it is lit. The ambient is a dark from the palette, so the shade side of
## the body is a colour of the world rather than a grey.
##
## ## What it costs
##
## One small SubViewport per figure, created on the first frame drawn and
## sized to the figure's real screen size (`_fit()`), so it is sharp in the
## wardrobe's arch and cheap on a phone's play screen. It has a World3D of its
## own: without it every model would render every other model, since a
## SubViewport otherwise draws the world of the viewport it sits in. Meshes are
## built once; a frame only moves transforms and recolours.

## The region of the art's space the texture covers. The widest pose without
## the sword -- a lunge, a topple -- stays inside it.
const BOX := Rect2(-24.0, -36.0, 48.0, 44.0)
## How far the camera is turned toward the facing, in radians, unless a figure
## says otherwise (`_yaw()`).
const YAW := 0.32
const CAMERA_DISTANCE := 120.0
## Screen pixels per art unit the texture is rendered at, at most and at least.
const DENSITY_MIN := 3
const DENSITY_MAX := 12
## How far the ink silhouette stands proud of the body, in art units.
const OUTLINE := 0.22
## Materials that take no ink edge: an outline round a highlight or a cheek is
## a hole, not a feature. "shine" is also unlit, so it reads as a reflection.
const FLAT: Array[String] = ["shine", "blush", "mouth", "iris", "white"]

var hair: Color
var hair_dark: Color
var skin: Color

var _viewport: SubViewport
var _camera: Camera3D
var _parts := {}
var _materials := {}
var _outline: StandardMaterial3D
var _density := 0
var _sin := 0.0
var _cos := 1.0
## The texture filter the art had before this costume made it linear.
var _art_filter := CanvasItem.TEXTURE_FILTER_PARENT_NODE


## The skin's shade step is the light's to make here, so a look's shade skin
## is not taken.
func _init(hair_lit: Color = Palette.SHADOW_PIT, hair_shade: Color = Palette.INK,
		skin_lit: Color = Palette.LIGHT_WARM) -> void:
	hair = hair_lit
	hair_dark = hair_shade
	skin = skin_lit


func worn_colours() -> Array[Color]:
	return [hair, hair_dark, skin]


## The viewport the model renders in, or null before the first frame drawn.
func viewport() -> SubViewport:
	return _viewport


## A part of the model by name, for a test: "head", "hand_front", ...
func part(id: String) -> MeshInstance3D:
	return _parts.get(id) as MeshInstance3D


## The camera the model is seen through, for a test.
func camera() -> Camera3D:
	return _camera


## The colour a material was given on the last frame drawn, for a test.
func material_colour(id: String) -> Color:
	var material := _materials.get(id) as StandardMaterial3D
	return material.albedo_color if material != null else Color(0, 0, 0, 0)


func take_off(art: PlayerArt) -> void:
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	_parts.clear()
	_materials.clear()
	if is_instance_valid(art):
		art.texture_filter = _art_filter


## --- what a figure says ---------------------------------------------------------

## Adds the figure's parts with `_add()`. Called once.
func _make() -> void:
	pass


## Material id -> colour, read every frame. Called with null once, before the
## first frame, to learn the ids.
func _tones(_art: PlayerArt) -> Dictionary:
	return {}


## How far the camera turns toward the facing. More shows more of the front
## and less of the profile; the shear in `_lift()` keeps every joint on its rig
## point at any turn.
func _yaw() -> float:
	return YAW


## Puts the parts on the rig: `up` is the body's axis, hip to shoulder, and
## `forward` the way it faces.
func _pose_parts(_art: PlayerArt, _pose: Dictionary, _up: Vector3, _forward: Vector3) -> void:
	pass


## --- layers -----------------------------------------------------------------

func draw_back(art: PlayerArt, _pose: Dictionary) -> bool:
	frames_drawn += 1
	drawn = Rect2(art._hip, Vector2.ZERO)
	return true


## The model is drawn whole in the body layer; the limb and head layers are
## part of it.
func draw_leg(_art: PlayerArt, _knee: Vector2, _foot: Vector2, _back: bool) -> bool:
	return true


func draw_arm(_art: PlayerArt, _hand: Vector2, _back: bool) -> bool:
	return true


func draw_head(_art: PlayerArt, _pose: Dictionary) -> bool:
	return true


func draw_body(art: PlayerArt, pose: Dictionary) -> bool:
	_ensure(art)
	_fit(art)
	_colour(art)
	_place(art, pose)
	art.draw_texture_rect(_viewport.get_texture(), BOX, false)
	return true


## --- the stage ----------------------------------------------------------------

func _ensure(art: PlayerArt) -> void:
	if _viewport != null and is_instance_valid(_viewport):
		return
	_viewport = SubViewport.new()
	_viewport.name = "ModelView"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	art.add_child(_viewport, false, Node.INTERNAL_MODE_BACK)
	_art_filter = art.texture_filter
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Palette.SHADOW_DEEP
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = env
	_viewport.add_child(world)

	var sun := DirectionalLight3D.new()
	sun.light_color = Palette.LIGHT_SOFT
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = CAMERA_DISTANCE * 2.0
	sun.transform.basis = Basis.looking_at(Vector3(1.0, -0.45, -0.7).normalized())
	_viewport.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_color = Palette.LIGHT_WARM
	rim.light_energy = 0.6
	rim.transform.basis = Basis.looking_at(Vector3(-0.9, -0.1, 0.35).normalized())
	_viewport.add_child(rim)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.size = BOX.size.y
	_camera.near = 1.0
	_camera.far = CAMERA_DISTANCE * 2.0
	_viewport.add_child(_camera)
	_camera.current = true

	_outline = StandardMaterial3D.new()
	_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline.grow = true
	_outline.grow_amount = OUTLINE
	for id: String in _tones(null):
		var material := StandardMaterial3D.new()
		material.roughness = 0.55
		if id == "steel":
			material.metallic = 0.7
			material.roughness = 0.3
		if id == "shine":
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if not id in FLAT and id != "shine":
			material.next_pass = _outline
		_materials[id] = material
	_make()


## Renders at the figure's real size on screen, so the texture is neither
## blurred up in the wardrobe's arch nor wasted on a phone. Rounded to whole
## pixels per unit, so a tiny change of zoom does not resize the viewport.
func _fit(art: PlayerArt) -> void:
	var scale := absf(art.get_global_transform_with_canvas().get_scale().y)
	scale *= absf(art.get_viewport().get_final_transform().get_scale().y)
	var density := clampi(roundi(scale), DENSITY_MIN, DENSITY_MAX)
	if density == _density:
		return
	_density = density
	_viewport.size = Vector2i(roundi(BOX.size.x * density), roundi(BOX.size.y * density))


## The materials take their colours every frame through the art's hit flash,
## so a hit burns the model white exactly as it burns a flat figure and a duel
## seat's team colour reaches the clothes the frame it is set.
func _colour(art: PlayerArt) -> void:
	var tones := _tones(art)
	for id: String in tones:
		(_materials[id] as StandardMaterial3D).albedo_color = art._c(tones[id] as Color)
	_outline.albedo_color = art._c(art.ink)


## --- building -------------------------------------------------------------------

func _add(id: String, mesh: Mesh, material: String) -> void:
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	node.material_override = _materials[material]
	_viewport.add_child(node)
	_parts[id] = node


func _sphere(radius: float = 1.0, dome: bool = false) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * (1.0 if dome else 2.0)
	mesh.is_hemisphere = dome
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


## Unit height, centred: a limb scales it along its own axis to its length,
## so a frame never rebuilds a mesh -- a capsule stretched along its axis would
## stretch its caps too. A top radius of 0 is a cone.
func _cylinder(top: float, bottom: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 1
	return mesh


## A ring about its own y axis, unit outer radius.
func _ring(inner: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = 1.0
	mesh.rings = 16
	mesh.ring_segments = 8
	return mesh


func _box(size: Vector3 = Vector3.ONE) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Both legs and both arms, front and back: thigh, knee, shin, foot, shoulder,
## upper arm, elbow, forearm, hand. `mats` names the material of each of
## "leg", "shin", "foot", "arm", "fore" and "hand".
func _make_limbs(thigh: Vector2, shin: Vector2, upper: Vector2, fore: Vector2,
		hand: float, mats: Dictionary) -> void:
	for side: String in ["front", "back"]:
		_add("thigh_" + side, _cylinder(thigh.x, thigh.y), mats["leg"])
		_add("knee_" + side, _sphere(thigh.y), mats["leg"])
		_add("shin_" + side, _cylinder(shin.x, shin.y), mats["shin"])
		_add("foot_" + side, _sphere(), mats["foot"])
		_add("shoulder_" + side, _sphere(upper.x * 1.05), mats["arm"])
		_add("upper_arm_" + side, _cylinder(upper.x, upper.y), mats["arm"])
		_add("elbow_" + side, _sphere(upper.y), mats["fore"])
		_add("forearm_" + side, _cylinder(fore.x, fore.y), mats["fore"])
		_add("hand_" + side, _sphere(hand), mats["hand"])


## --- posing -----------------------------------------------------------------

## A 2D rig point at a depth, in the model's space: y up, z toward the camera,
## x pre-sheared against the camera's turn so the point projects back onto
## `p` (see the class comment).
func _lift(p: Vector2, depth: float) -> Vector3:
	return Vector3((p.x + depth * _sin) / _cos, -p.y, depth)


func _place(art: PlayerArt, pose: Dictionary) -> void:
	var f := art._f
	_sin = sin(_yaw() * f)
	_cos = cos(_yaw())
	var target := _lift(BOX.get_center(), 0.0)
	_camera.look_at_from_position(
		target + Vector3(_sin, 0.0, _cos) * CAMERA_DISTANCE, target, Vector3.UP)
	var up := (_lift(art._shoulder, 0.0) - _lift(art._hip, 0.0)).normalized()
	_pose_parts(art, pose, up, Vector3(f, 0.0, 0.0))


## The limbs on the rig's joints: hips and shoulders at a depth either side,
## the shoulder joint `shoulder_drop` below the rig's shoulder line, the ankle
## `ankle` above the rig's foot point, a foot of radii `foot` square to the
## shin, toe forward -- so a pointed toe on a jump and a flat one on the floor
## both come from the leg's own angle.
func _pose_limbs(art: PlayerArt, hip_depth: float, shoulder_depth: float,
		shoulder_drop: float, ankle: float, foot: Vector3) -> void:
	for leg: Array in [["back", art._knee_back, art._foot_back, -hip_depth],
			["front", art._knee_front, art._foot_front, hip_depth]]:
		var side: String = leg[0]
		var depth: float = leg[3]
		var foot2: Vector2 = leg[2]
		var hip := _lift(art._hip, depth)
		var knee := _lift(leg[1] as Vector2, depth)
		var ankle_at := _lift(foot2 + Vector2(0.0, -ankle), depth)
		_segment(art, "thigh_" + side, hip, knee, Vector2.ONE)
		_put("knee_" + side, Basis.IDENTITY, knee, Vector3.ONE)
		_segment(art, "shin_" + side, knee, ankle_at, Vector2.ONE)
		var toe := _axes((knee - ankle_at).normalized(), Vector3(art._f, 0.0, 0.0))
		_put("foot_" + side, toe,
			_lift(foot2 + Vector2(0.45 * art._f, -foot.y + 0.05), depth), foot)
	for arm: Array in [["back", art._hand_back, -shoulder_depth],
			["front", art._hand_front, shoulder_depth]]:
		var side: String = arm[0]
		var depth: float = arm[2]
		var hand2: Vector2 = arm[1]
		var shoulder := _lift(art._shoulder + Vector2(0.0, shoulder_drop), depth)
		var elbow := _lift(art._elbow(hand2), depth)
		var hand := _lift(hand2, depth)
		_put("shoulder_" + side, Basis.IDENTITY, shoulder, Vector3.ONE)
		_segment(art, "upper_arm_" + side, shoulder, elbow, Vector2.ONE)
		_put("elbow_" + side, Basis.IDENTITY, elbow, Vector3.ONE)
		_segment(art, "forearm_" + side, elbow, hand, Vector2.ONE)
		_put("hand_" + side, Basis.IDENTITY, hand, Vector3.ONE)


## A head on `base`, `rise` up its own axis: [centre, frame, side]. The frame's
## x is the face, turned `turn` from the run toward the viewer and backwards
## when the pose looks back; y leans with the body and pitches with the hood's
## tilt; `side` points across the face toward the camera.
func _head(art: PlayerArt, pose: Dictionary, up: Vector3, base: Vector3, rise: float,
		turn: float) -> Array:
	var look: float = float(pose["hood_face"])
	var fdir: float = art._f * (1.0 if look >= 0.0 else -1.0)
	var tilt: float = float(pose["hood_tilt"])
	var head_up := up.rotated(Vector3.BACK, -tilt * fdir * 0.6).normalized()
	var centre := base + head_up * rise
	var frame := _axes(head_up, Vector3(fdir * cos(turn), 0.0, sin(turn)))
	var side := frame.x.cross(head_up).normalized()
	if side.z < 0.0:
		side = -side
	return [centre, frame, side]


## A unit mesh from `a` to `b` along its y axis, its top at `a`, scaled across
## by `across` (forward, sideways).
func _segment(art: PlayerArt, id: String, a: Vector3, b: Vector3, across: Vector2) -> void:
	var along := a - b
	var length := along.length()
	var node := _parts[id] as MeshInstance3D
	node.visible = length > 0.01
	if not node.visible:
		return
	_put(id, _axes(along / length, Vector3(art._f, 0.0, 0.0)), (a + b) * 0.5,
		Vector3(across.x, length, across.y))


## A frame with y along `up` and x as near `forward` as `up` allows.
func _axes(up: Vector3, forward: Vector3) -> Basis:
	var y := up.normalized()
	var x := forward - y * forward.dot(y)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.BACK)
	x = x.normalized()
	return Basis(x, y, x.cross(y))


## Puts a part, and grows `drawn` by where it lands on screen.
func _put(id: String, frame: Basis, at: Vector3, scale: Vector3) -> void:
	var node := _parts[id] as MeshInstance3D
	node.transform = Transform3D(frame * Basis.from_scale(scale), at)
	var flat := Vector2(at.x * _cos - at.z * _sin, -at.y)
	var reach := maxf(scale.x, maxf(scale.y, scale.z)) * 0.5
	if node.mesh is SphereMesh or node.mesh is TorusMesh:
		reach *= 2.0
	drawn = drawn.expand(flat - Vector2(reach, reach)).expand(flat + Vector2(reach, reach))
