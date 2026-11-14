class_name ModelCostume
extends Costume
## The 3D figure: a lit, shaded human body built from meshes, rendered into a
## SubViewport and drawn back onto the 2D rig as one texture.
##
## ## Why a costume, and why the rig still drives it
##
## Everything that makes the game fair is in 2D: the hitbox, the tuning, the
## duel's blade rect, the netplay snapshot. A 3D figure that animated itself --
## a skeleton with its own clips -- would be a second source of truth for where
## a hand or a foot is, and the first pose added to player_art.gd would be a
## pose the model did not have. So the model has no animation of its own. Each
## frame it reads the joints PlayerArt has just placed -- hip, knee, foot,
## shoulder, elbow, hand, the torso points and the head -- lifts them into 3D
## at a fixed depth per side, and hangs a limb between each pair. Every pose
## the robed figures know is the model's, on the same frame, and the hand ends
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
## projects them back to check.)
##
## ## The light
##
## The sun is the world's, as everywhere else (docs/art-direction.md): a key
## from the left, low and a little in front, so the lit half of every form is
## the world-left half whichever way the figure faces -- the same split the
## flat figures draw by hand, here falling out of the normals. A weak warm
## light from behind the far side gives the edge the ink rim gives the flat
## figures. The ambient is a dark from the palette, so the shade side of the
## body is a colour of the world rather than a grey.
##
## ## What it costs
##
## One small SubViewport per figure, created on the first frame drawn and
## sized to the figure's real screen size (`_density()`), so it is sharp in
## the wardrobe's arch and cheap on a phone's play screen. It has a World3D of
## its own: without it every model would render every other model, since a
## SubViewport otherwise draws the world of the viewport it sits in. Meshes are
## built once; a frame only moves transforms and, during a hit, recolours.

## The region of the art's space the texture covers. The widest pose without
## the sword -- a lunge, a topple -- stays inside it.
const BOX := Rect2(-24.0, -36.0, 48.0, 44.0)
## How far the camera is turned toward the facing, in radians.
const YAW := 0.32
const CAMERA_DISTANCE := 120.0
## Screen pixels per art unit the texture is rendered at, at most and at least.
const DENSITY_MIN := 3
const DENSITY_MAX := 12

## Depth of each side from the body's centre plane; + is toward the camera.
const HIP_DEPTH := 0.85
const SHOULDER_DEPTH := 1.75

## Radii, in art units. The figure is 21 tall to the crown: about seven and a
## half heads, an adult's proportion rather than the hooded figure's.
const HEAD_R := Vector3(1.22, 1.42, 1.15)
const NECK_R := 0.52
const THIGH_R := Vector2(0.86, 0.6)
const SHIN_R := Vector2(0.6, 0.42)
const UPPER_ARM_R := Vector2(0.58, 0.46)
const FOREARM_R := Vector2(0.46, 0.36)
const HAND_R := 0.46
## How far the ink silhouette stands proud of the body, in art units.
const OUTLINE := 0.22
## The ankle sits above the rig's foot point, which is on the floor.
const ANKLE := 0.75

## The rig's head is the hood's centre; a head sits a little lower on a neck.
const HEAD_DROP := 0.35

## The materials, one per thing a colour of the look or the seat lands on.
const MATERIALS: Array[String] = [
	"cloth", "sleeve", "trousers", "boot", "skin", "hair", "hair_dark", "belt", "eye",
]

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


func take_off(art: PlayerArt) -> void:
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	_parts.clear()
	_materials.clear()
	if is_instance_valid(art):
		art.texture_filter = _art_filter


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

	_build_body()


## Every part, built once. A limb is a tapered cylinder of unit length scaled
## along its axis, with a sphere at the far joint, so a frame never rebuilds a
## mesh -- a capsule stretched along its axis would stretch its caps too.
func _build_body() -> void:
	# The ink edge: every part drawn a second time, grown and turned inside out,
	# in flat ink. It is the flat figures' rim, as a silhouette -- without it a
	# crimson body vanishes into crimson stone however well it is lit.
	_outline = StandardMaterial3D.new()
	_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline.grow = true
	_outline.grow_amount = OUTLINE
	for id: String in MATERIALS:
		var material := StandardMaterial3D.new()
		material.roughness = 0.55 if id in ["skin", "hair", "hair_dark", "eye"] else 0.85
		material.next_pass = _outline
		_materials[id] = material

	_add("head", _sphere(1.0), "skin")
	_add("hair_cap", _sphere(1.0, true), "hair")
	_add("hair_back", _sphere(1.0), "hair_dark")
	_add("nose", _sphere(0.24), "skin")
	_add("eye", _sphere(0.17), "eye")
	_add("neck", _cylinder(NECK_R, NECK_R), "skin")
	_add("chest", _sphere(1.0), "cloth")
	_add("belly", _cylinder(1.0, 1.0), "cloth")
	_add("pelvis", _sphere(1.0), "trousers")
	_add("skirt", _cylinder(1.0, 1.32), "cloth")
	_add("belt", _cylinder(1.0, 1.0), "belt")
	for side: String in ["front", "back"]:
		_add("thigh_" + side, _cylinder(THIGH_R.x, THIGH_R.y), "trousers")
		_add("knee_" + side, _sphere(THIGH_R.y), "trousers")
		_add("shin_" + side, _cylinder(SHIN_R.x, SHIN_R.y), "boot")
		_add("foot_" + side, _box(Vector3(2.1, 0.75, 0.9)), "boot")
		_add("shoulder_" + side, _sphere(UPPER_ARM_R.x * 1.12), "cloth")
		_add("upper_arm_" + side, _cylinder(UPPER_ARM_R.x, UPPER_ARM_R.y), "sleeve")
		_add("elbow_" + side, _sphere(UPPER_ARM_R.y), "sleeve")
		_add("forearm_" + side, _cylinder(FOREARM_R.x, FOREARM_R.y), "sleeve")
		_add("hand_" + side, _sphere(HAND_R), "skin")


func _add(id: String, mesh: Mesh, material: String) -> void:
	var node := MeshInstance3D.new()
	node.name = id
	node.mesh = mesh
	node.material_override = _materials[material]
	_viewport.add_child(node)
	_parts[id] = node


func _sphere(radius: float, dome: bool = false) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * (1.0 if dome else 2.0)
	mesh.is_hemisphere = dome
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


## Unit height, centred: a limb scales it along its own axis to its length.
func _cylinder(top: float, bottom: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.cap_top = true
	mesh.cap_bottom = true
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


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


## The materials take the art's colours every frame, through the art's hit
## flash, so a hit burns the model white exactly as it burns a flat figure and
## a duel seat's team colour reaches the tunic the frame it is set.
func _colour(art: PlayerArt) -> void:
	var bases := {
		"cloth": art.cloth,
		"sleeve": art.cloth_dark,
		"trousers": art.cloak_shade,
		"boot": art.ink,
		"skin": skin,
		"hair": hair,
		"hair_dark": hair_dark,
		"belt": art.accent,
		"eye": art.ink,
	}
	for id: String in bases:
		(_materials[id] as StandardMaterial3D).albedo_color = art._c(bases[id] as Color)
	_outline.albedo_color = art._c(art.ink)


## The colour a material was given on the last frame drawn, for a test.
func material_colour(id: String) -> Color:
	var material := _materials.get(id) as StandardMaterial3D
	return material.albedo_color if material != null else Color(0, 0, 0, 0)


## --- posing -----------------------------------------------------------------

## A 2D rig point at a depth, in the model's space: y up, z toward the camera,
## x pre-sheared against the camera's turn so the point projects back onto
## `p` (see the class comment).
func _lift(p: Vector2, depth: float) -> Vector3:
	return Vector3((p.x + depth * _sin) / _cos, -p.y, depth)


func _place(art: PlayerArt, pose: Dictionary) -> void:
	var f := art._f
	_sin = sin(YAW * f)
	_cos = cos(YAW)
	var target := _lift(BOX.get_center(), 0.0)
	_camera.look_at_from_position(
		target + Vector3(_sin, 0.0, _cos) * CAMERA_DISTANCE, target, Vector3.UP)

	var up := (_lift(art._shoulder, 0.0) - _lift(art._hip, 0.0)).normalized()
	var forward := Vector3(f, 0.0, 0.0)
	_place_torso(art, up, forward)
	_place_head(art, pose, up)
	_place_leg(art, "back", art._knee_back, art._foot_back, -HIP_DEPTH)
	_place_leg(art, "front", art._knee_front, art._foot_front, HIP_DEPTH)
	_place_arm(art, "back", art._hand_back, -SHOULDER_DEPTH)
	_place_arm(art, "front", art._hand_front, SHOULDER_DEPTH)


func _place_torso(art: PlayerArt, up: Vector3, forward: Vector3) -> void:
	# Depth front to back follows the rig's chest width, which the pose
	# squashes and twists; breadth across is the shoulders'.
	var chest_x := float(art._hw["chest"]) * 0.5
	var shoulder := _lift(art._shoulder, 0.0)
	var chest := _lift(art._chest, 0.0)
	var waist := _lift(art._waist, 0.0)
	var hip := _lift(art._hip, 0.0)
	var frame := _axes(up, forward)
	_put("chest", frame, shoulder.lerp(chest, 0.75) - up * 0.15,
		Vector3(chest_x, 2.05, SHOULDER_DEPTH * 0.98))
	_segment(art, "belly", chest, waist, Vector2(chest_x * 0.85, SHOULDER_DEPTH * 0.72))
	_put("pelvis", frame, hip, Vector3(1.2, 1.2, HIP_DEPTH * 1.75))
	_segment(art, "belt", waist + up * 0.35, waist - up * 0.35,
		Vector2(chest_x * 0.88, SHOULDER_DEPTH * 0.76))
	_segment(art, "skirt", waist, hip - up * 2.2,
		Vector2(chest_x * 0.86, SHOULDER_DEPTH * 0.78))


func _place_head(art: PlayerArt, pose: Dictionary, up: Vector3) -> void:
	var look: float = float(pose["hood_face"])
	var fdir: float = art._f * (1.0 if look >= 0.0 else -1.0)
	var tilt: float = float(pose["hood_tilt"])
	var centre := _lift(art._head + Vector2(0.0, HEAD_DROP), 0.0)
	# The head's up leans with the body and pitches forward with the hood's
	# tilt; the face looks the way the hood does, backwards included.
	var head_up := up.rotated(Vector3.BACK, -tilt * fdir * 0.6).normalized()
	var frame := _axes(head_up, Vector3(fdir, 0.0, 0.0))
	var face := frame.x
	_put("head", frame, centre, HEAD_R)
	_put("hair_cap", frame, centre + head_up * 0.12 - face * 0.12,
		HEAD_R * Vector3(1.1, 1.0, 1.1))
	_put("hair_back", frame, centre - face * 0.45 - head_up * 0.15,
		HEAD_R * Vector3(0.82, 0.95, 0.98))
	_put("nose", frame, centre + face * HEAD_R.x * 0.98 - head_up * 0.18, Vector3.ONE)
	# On the near side of the face, on its surface rather than inside it.
	_put("eye", frame, centre + face * HEAD_R.x * 0.9 + head_up * 0.12
		+ Vector3.BACK * 0.5, Vector3.ONE)
	(_parts["eye"] as MeshInstance3D).visible = float(pose["glint"]) > 0.0
	_segment(art, "neck", _lift(art._shoulder, 0.0), centre - head_up * HEAD_R.y * 0.6,
		Vector2.ONE)


func _place_leg(art: PlayerArt, side: String, knee2: Vector2, foot2: Vector2,
		depth: float) -> void:
	var hip := _lift(art._hip, depth)
	var knee := _lift(knee2, depth)
	var ankle := _lift(foot2 + Vector2(0.0, -ANKLE), depth)
	_segment(art, "thigh_" + side, hip, knee, Vector2.ONE)
	_put("knee_" + side, Basis.IDENTITY, knee, Vector3.ONE)
	_segment(art, "shin_" + side, knee, ankle, Vector2.ONE)
	# The foot square to the shin, toe forward, so a pointed toe on a jump and
	# a flat one on the floor both come from the leg's own angle.
	var shin_up := (knee - ankle).normalized()
	var toe := _axes(shin_up, Vector3(art._f, 0.0, 0.0))
	var foot := _lift(foot2 + Vector2(0.55 * art._f, -0.37), depth)
	_put("foot_" + side, toe, foot, Vector3.ONE)


func _place_arm(art: PlayerArt, side: String, hand2: Vector2, depth: float) -> void:
	var shoulder := _lift(art._shoulder + Vector2(0.0, 0.55), depth)
	var elbow := _lift(art._elbow(hand2), depth)
	var hand := _lift(hand2, depth)
	_put("shoulder_" + side, Basis.IDENTITY, shoulder, Vector3.ONE)
	_segment(art, "upper_arm_" + side, shoulder, elbow, Vector2.ONE)
	_put("elbow_" + side, Basis.IDENTITY, elbow, Vector3.ONE)
	_segment(art, "forearm_" + side, elbow, hand, Vector2.ONE)
	_put("hand_" + side, Basis.IDENTITY, hand, Vector3.ONE)


## A unit cylinder from `a` to `b`, its top radius at `a`, scaled across by
## `across` (forward, sideways).
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
	if id in ["head", "hair_cap", "hair_back"]:
		reach = HEAD_R.y
	drawn = drawn.expand(flat - Vector2(reach, reach)).expand(flat + Vector2(reach, reach))
