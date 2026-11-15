class_name RiggedCostume
extends ModelCostume
## A professionally made, textured, rigged character -- the owner's `.glb` --
## worn on the shared 2D rig. Dropping the file at `PRINCESS` is all it takes:
## CharacterLook.dress() then dresses the PRINCESS figure in it instead of the
## primitives (PrincessCostume), and falls back to them while it is missing.
##
## ## Its own clips first, the rig second
##
## Everything ModelCostume argues holds: the hitbox, the tuning, the duel's
## blade rect and the netplay snapshot are 2D, and nothing the model does may
## move them. Within that, a model the owner animated is drawn with its clips
## where it has one for what the body is doing (ModelClips says which, and
## samples it on the simulation's clock, never the engine's). The clip is
## turned to face the way the body faces, scaled to the rig, and pinned there:
## its hips stand over the rig's hip, so the picture never leaves the hitbox,
## at the clip's own height, so a crouch goes down, with the feet kept out of
## the floor when the body is on it (`_pose_clip()`). Its sword hand is
## reported to PlayerArt (`sword_hand()`), and the adventure's 2D sword leaves
## that hand.
##
## Where there is no clip -- a turn, a hang, a parry, and in the duel every
## state but death -- the skeleton is posed from the joints PlayerArt has just
## placed, lifted into 3D through the same sheared, turned camera as the
## primitives (`_lift()`). Each joint the rig names -- hip, knee, ankle,
## shoulder, elbow, hand -- is the origin of a bone set exactly on the lifted
## rig point, so the hand ends where the 2D sword's hilt starts and the feet
## stand on the floor. (tests/unit/test_rigged_figure.gd projects the bones
## back to check, and the reported hand against its bone.)
##
## ## How a bone is aimed
##
## A bone is turned, not dragged: its rest frame is carried onto its target by
## one rotation, built so its twist is anatomical rather than arbitrary.
##
## - **The body** (hips, spine, neck) turns as a whole from the model's rest
##   frame -- up from hips to neck, forward from the left and right arms --
##   onto the rig's: up from hip to shoulder, forward the way it faces. Facing
##   left is a real turn, not a mirror, so the far side of the model shows and
##   the sword changes hands as the flat figures' does.
## - **A limb** first swings from its rest direction to hanging straight down
##   the body (an arm out of the T-pose by the shortest arc, a leg hardly at
##   all), then turns with the body, then hinges about the body's left-right
##   axis onto the rig's direction. Every rig limb lies in one plane at one
##   depth, so that last turn is always a hinge and its angle is always
##   defined -- an arm raised straight overhead included, where a shortest arc
##   would pick its axis at random and twist the arm.
## - **A hand and a foot** keep their rest angle to the bone before them, so a
##   flat foot under a vertical shin and a pointed toe under a raised one both
##   follow from the leg, as they do for the primitives.
##
## ## How a limb changes length
##
## The rig's limbs change length from pose to pose -- a lunge reaches, a jump
## dangles a shin, a crouch folds the legs to nothing -- and a model's bones do
## not. Every joint still lands on its rig point; what has to give is the skin
## between two joints. Scaling the bone would do it, but only uniformly: a
## bone's pose is a position, a rotation and a scale, and a bone stretched
## along its length shears every child, which the pose cannot hold, so the
## children would land off their points. Uniform scale keeps them, but swells a
## forearm to twice its width as it doubles in length.
##
## So the bones stay rigid and the *skin* stretches (`_stretch_skins()`): each skin
## bind -- the matrix that carries a vertex into its bone's rest space -- gets
## a scale along that bone's own length, target over rest, before it. A
## vertex on the bone moves along it, a vertex beside it keeps its distance,
## and a vertex blended across a joint is carried by both bones to the same
## place. The limb spans its joints exactly at any length, as the primitives'
## cylinders do, and is never fatter than modelled. The spine is spaced out
## between the rig's hip and shoulder the same way, and its skin stretched to
## match: the rig's torso is a robe's, longer than a person's. The whole
## model is first scaled so its hip joints stand `HIP_HEIGHT` above the floor,
## as the rig's do. The model's skins are duplicated on load, because a Skin
## from a scene is shared by every instance and the two duellists stretch
## differently.
##
## ## What the file must be
##
## A humanoid skeleton with these bones, under any of these names (`ROLES`):
## Mixamo's, with or without its `mixamorig:` prefix (which Godot's importer
## turns into `mixamorig_`), Godot's SkeletonProfileHumanoid's, or Tripo's
## (`Hip`, `NeckTwist01`, `L_Clavicle`, `L_Upperarm`, `L_Forearm`, `L_Hand`,
## `L_Thigh`, `L_Calf`, `L_Foot`, ...). The spine is whatever lies between the
## hips and the neck. Twist, share, finger and toe bones are not driven: they
## keep their rest pose under the bone they hang from. Any rest pose that
## stands upright works -- a T, an A, or the hands on hips of the owner's
## first export -- because a limb is turned from its own rest direction, and the
## facing and the scale are read from the bones and the skinned mesh, not
## assumed.
##
## A prop the model holds is hidden (`PROPS`, by name): the sword the game
## fights with is the shared 2D one (ModelCostume), coloured hers by `blade`,
## and a modelled one would be a picture of it in the wrong place.
##
## ## Colour
##
## A textured model is not drawn in palette steps, so only two things are
## recoloured, through materials rather than the albedo of every part:
##
## - **The cloth** is dyed with `PlayerArt.cloth` -- the look's outfit, and in a
##   duel the seat's team colour (FighterArt.seat) -- by
##   assets/cloth_tint.gdshader, which moves only the pixels of the cloth's
##   own hue and keeps the texture's folds, trim and emblems. A part is cloth
##   when its material or surface is named for it (`CLOTH`: "cloth", "tunic",
##   "cape") or when at least `CLOTH_SHARE` of its texture is dyed in the
##   model's own cloth colour, `OWN_CLOTH`: the owner's princess is made in
##   Palette.ROYAL's blue, so her cape, tunic and sleeves are, and her skin,
##   hair, leather and steel are not. Wearing her own ROYAL she is not dyed at
##   all: the texture is that outfit already. A model with no cloth -- one
##   exported without its colour textures, all grey -- wears its team colour
##   as its ink edge instead, so two seats can still be told apart.
## - **The hit flash**, an unshaded overlay over every surface whose alpha is
##   PlayerArt's flash: the same PAPER mix as `PlayerArt._c()`, after the light,
##   so a hit burns the textured model pale as it burns a flat figure.
##
## The ink silhouette is the primitives' inverted hull, chained behind the
## overlay. The hair, skin and accent rows of the wardrobe do not reach a
## textured model; its colours are its texture's.

## Where the owner's model goes.
const PRINCESS := "res://assets/characters/princess.glb"
## Words in a material's or surface's name that make it the figure's cloth.
const CLOTH: Array[String] = ["cloth", "tunic", "cape"]
## The colour the model's own cloth is dyed in its texture: the princess's
## ROYAL. A tint to this outfit leaves the texture as it is.
const OWN_CLOTH := Palette.ROYAL
## How much of a part's texture must be the cloth's hue for the part to be
## cloth, and how near the hue a pixel must be, round the hue circle.
const CLOTH_SHARE := 0.2
const CLOTH_HUE := 0.07
## Mesh parts that are props the model holds rather than the model, hidden on
## load: any part with one of these words in its name.
const PROPS: Array[String] = ["sword", "blade", "weapon"]
const TINT := preload("res://assets/cloth_tint.gdshader")
## How far above the floor the rig's hip joints stand, in art units, at rest.
## Posed by the rig, the model is scaled to stand its hips there.
const HIP_HEIGHT := 9.0
## How tall the rig's figure is, feet to crown. Playing a clip, the model is
## scaled to this instead: a clip keeps the model's own proportions, so its
## hips land where they land, and it is the figure's size that has to match
## the rig's. The two scales differ by the model's proportions -- the owner's
## princess has short legs for her height, so her clips draw her legs longer
## and her torso shorter than the rig, which stretches her torso to its
## robe-length body.
const HEIGHT := 22.0
## How far a limb's skin may be stretched along it, least and most: only a
## guard against a rig point that has collapsed onto its neighbour. Every pose
## the rig makes is well inside it.
const STRETCH := Vector2(0.05, 4.0)
## How far the face turns from the run toward the viewer, in radians.
const FACE_TURN := 0.35
## The flash's strength, as PlayerArt._c() mixes it.
const FLASH := 0.85
## How much brighter the stage is exposed for a texture than for the
## primitives. The primitives are painted in palette steps that are already the
## lit colour; a generated texture is an albedo, and the princess's blue is a
## dark one (a mean of about a fifth in sRGB), which under the same light went
## to black at play size.
const EXPOSURE := 1.8
## A bone's role -> the names it may carry, prefix stripped, lower case, with
## no separators. "left"/"right" are the model's own sides.
const ROLES := {
	"hips": ["hips", "hip", "pelvis"],
	"neck": ["neck", "necktwist01"],
	"head": ["head"],
	"clavicle_left": ["leftshoulder", "lclavicle"],
	"arm_left": ["leftarm", "leftupperarm", "lupperarm"],
	"forearm_left": ["leftforearm", "leftlowerarm", "lforearm"],
	"hand_left": ["lefthand", "lhand"],
	"thigh_left": ["leftupleg", "leftupperleg", "lthigh"],
	"shin_left": ["leftleg", "leftlowerleg", "lcalf"],
	"foot_left": ["leftfoot", "lfoot"],
	"clavicle_right": ["rightshoulder", "rclavicle"],
	"arm_right": ["rightarm", "rightupperarm", "rupperarm"],
	"forearm_right": ["rightforearm", "rightlowerarm", "rforearm"],
	"hand_right": ["righthand", "rhand"],
	"thigh_right": ["rightupleg", "rightupperleg", "rthigh"],
	"shin_right": ["rightleg", "rightlowerleg", "rcalf"],
	"foot_right": ["rightfoot", "rfoot"],
}
## The hand the clips hold the sword in: the owner's are all "sword in right
## hand".
const SWORD_HAND := "hand_right"
## The roles a model may lack: a missing clavicle hangs the arm off the chest.
const OPTIONAL: Array[String] = ["clavicle_left", "clavicle_right"]
## The bone a limb bone aims at.
const AIMS := {
	"clavicle": "arm", "arm": "forearm", "forearm": "hand", "thigh": "shin", "shin": "foot",
}

static var _prefix := RegEx.create_from_string("^mixamorig\\d*[:_]")
## What a texture's cloth is, by texture: [share, hue, saturation, value].
## Measured once per texture, not per costume: the duel wears it twice.
static var _measured := {}

## The file to load, unless `scene` is given.
var path: String
## The model itself; loaded from `path` on the first frame drawn when null. A
## test hands in a stand-in here.
var scene: PackedScene
## The sword's colours (Costume.blade_colours()): the figure's, not the file's.
var blade := {}

var _model: Node3D
var _skeleton: Skeleton3D
## role -> bone index.
var _bones := {}
## Hips first, neck last: the bones between, in order.
var _chain: Array[int] = []
## How far up the chain each bone sits, 0 at the hips, 1 at the neck.
var _rise: Array[float] = []
## Rest pose, in the viewport's space at the model's scale, by bone index:
## where each bone is, its rotation, and its size.
var _rest_at := {}
var _rest_turn := {}
var _rest_size := {}
## Per limb bone: the turn that hangs it straight down the body at rest.
var _hang := {}
## Per stretching bone: the unit direction, in its own rest space, that its
## skin stretches along; and this frame's stretch.
var _stretch_axis := {}
var _stretch := {}
## Every skin bind of the model: [Skin, bind index, bone, rest bind].
var _binds: Array[Array] = []
var _up := Vector3.UP
var _frame := Basis.IDENTITY
var _hip_depth := 1.0
var _shoulder_depth := 2.0
var _hip_rise := 0.0
var _neck_rise := 1.0
var _ankle := 0.5
var _cloth: Array[ShaderMaterial] = []
var _overlays: Array[StandardMaterial3D] = []
var _edges: Array[StandardMaterial3D] = []
## Which of the model's sides is nearer the camera on the last frame drawn.
var _near := "right"
## The model's own clips, or null for a model without any.
var _clips: ModelClips
## The clip drawn on the last frame, [id, seconds], or [] for the rig.
var _clip: Array = []
## The model's scale on the rig and in a clip, and where its soles are at rest
## in its own space.
var _scale := 1.0
var _clip_scale := 1.0
var _sole := Vector3.ZERO
## Where the sword hand is on the last frame drawn, in the art's space; NAN
## when the rig placed it.
var _hand_at := Vector2(NAN, NAN)


func _init(file: String = PRINCESS) -> void:
	path = file


## Whether the owner's model is there to be worn.
static func available(file: String = PRINCESS) -> bool:
	return ResourceLoader.exists(file)


## The role a bone of this name plays, or "" for none: "arm_left", "hips", ...
static func role_of(bone: String) -> String:
	var key := _prefix.sub(bone.to_lower(), "")
	for mark: String in ["_", ":", ".", " ", "-"]:
		key = key.replace(mark, "")
	for role: String in ROLES:
		if key in (ROLES[role] as Array):
			return role
	return ""


func blade_colours() -> Dictionary:
	return blade


## A textured model wears no colour a player chose but the cloth, which is the
## seat's in a duel.
func worn_colours() -> Array[Color]:
	return []


## The skeleton being posed, or null before the first frame drawn.
func skeleton() -> Skeleton3D:
	return _skeleton


## Where a rig joint's bone is, in the viewport's 3D space: "hand_front",
## "knee_back", "elbow_front", "ankle_front", "shoulder_back", "hip_front".
## Front is the side nearer the camera on the last frame drawn. For a test.
func joint(id: String) -> Vector3:
	var parts := id.split("_")
	var near := parts[1] == "front"
	var side := _near if near else _far()
	var bone: String = {
		"hand": "hand", "knee": "shin", "elbow": "forearm", "ankle": "foot",
		"shoulder": "arm", "hip": "thigh",
	}[parts[0]]
	return _world(_bone(bone + "_" + side))


## How high above the rig's foot point the ankle bone is held, in art units.
func ankle_height() -> float:
	return _ankle


## The materials the cloth tint goes to. For a test.
func cloth_materials() -> Array[ShaderMaterial]:
	return _cloth


## The model's clips, or null. For a test.
func clips() -> ModelClips:
	return _clips


## The clip drawn on the last frame, [id, seconds], or [] when the rig posed it.
func clip() -> Array:
	return _clip


## The colour of the ink edge on the last frame drawn. For a test.
func edge_colour() -> Color:
	return _edges[0].albedo_color if not _edges.is_empty() else Color(0, 0, 0, 0)


func sword_hand(_art: PlayerArt) -> Vector2:
	return _hand_at


## How strongly the flash burns the model on the last frame drawn, 0 to 1.
func flash() -> float:
	return _overlays[0].albedo_color.a if not _overlays.is_empty() else 0.0


## The model is freed now, while every material it draws with is alive: left
## to go with the viewport at the end of the frame, the renderer was asked
## about a material already freed, and said so as an engine error.
func take_off(art: PlayerArt) -> void:
	if _model != null and is_instance_valid(_model):
		_model.get_parent().remove_child(_model)
		_model.free()
	super(art)
	_model = null
	_skeleton = null
	_cloth.clear()
	_overlays.clear()
	_edges.clear()


## --- loading --------------------------------------------------------------------

func _make() -> void:
	for node: Node in _viewport.get_children():
		if node is WorldEnvironment:
			(node as WorldEnvironment).environment.tonemap_exposure = EXPOSURE
	if scene == null:
		scene = ResourceLoader.load(path) as PackedScene
	if scene == null:
		push_error("RiggedCostume: %s is not a scene" % path)
		return
	_model = scene.instantiate() as Node3D
	if _model == null:
		push_error("RiggedCostume: %s has no 3D root" % path)
		return
	_strip(_model)
	_viewport.add_child(_model)
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = not _is_named(node.name, PROPS)
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("RiggedCostume: %s has no skeleton" % path)
		return
	_skeleton = found[0] as Skeleton3D
	_skeleton.reset_bone_poses()
	var missing := _map_bones()
	if not missing.is_empty():
		push_error("RiggedCostume: %s lacks bones for %s" % [path, ", ".join(missing)])
		_skeleton = null
		return
	_measure()
	_bind_skins()
	_dress()
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_clips = ModelClips.new(players[0] as AnimationPlayer)


## What an import brings that a posed costume must not have: an animation
## tree, which would play on the engine's clock (the clips are sampled through
## the AnimationPlayer instead, ModelClips), and its own camera and lights.
func _strip(model: Node) -> void:
	for type: String in ["AnimationTree", "Camera3D", "Light3D"]:
		for node: Node in model.find_children("*", type, true, false):
			node.get_parent().remove_child(node)
			node.free()


## Fills `_bones` and `_chain`; returns the roles no bone plays.
func _map_bones() -> PackedStringArray:
	for i: int in _skeleton.get_bone_count():
		var role := role_of(_skeleton.get_bone_name(i))
		if role != "" and not _bones.has(role):
			_bones[role] = i
	var missing := PackedStringArray()
	for role: String in ROLES:
		if not _bones.has(role) and not role in OPTIONAL:
			missing.append(role)
	if not missing.is_empty():
		return missing
	var at := _bone("neck")
	while at != -1:
		_chain.push_front(at)
		if at == _bone("hips"):
			return missing
		at = _skeleton.get_bone_parent(at)
	missing.append("a spine from the hips to the neck")
	return missing


## Reads the rest pose: the model's frame, its proportions, and the scale that
## stands its hips at the rig's height.
func _measure() -> void:
	_model.transform = Transform3D.IDENTITY
	var hips := _rest(_bone("hips"))
	var neck := _rest(_bone("neck"))
	_up = (neck - hips).normalized()
	var left := _rest(_bone("arm_left")) - _rest(_bone("arm_right"))
	left = (left - _up * left.dot(_up)).normalized()
	_frame = _axes(_up, left.cross(_up))
	var legs := (_rest(_bone("thigh_left")) + _rest(_bone("thigh_right"))) * 0.5
	var floor_at := _floor()
	var tall := (_reach(1.0) - floor_at).dot(_up)
	var scale := HIP_HEIGHT / maxf((legs - floor_at).dot(_up), 0.001)
	_model.scale = Vector3.ONE * scale
	_scale = scale
	_sole = floor_at
	_clip_scale = HEIGHT / maxf(tall, 0.001)
	for i: int in _skeleton.get_bone_count():
		var rest := _skeleton.global_transform * _skeleton.get_bone_global_rest(i)
		_rest_at[i] = rest.origin
		_rest_turn[i] = rest.basis.orthonormalized()
		_rest_size[i] = rest.basis.get_scale().x
	legs *= scale
	floor_at *= scale
	var arms := (_at(_bone("arm_left")) + _at(_bone("arm_right"))) * 0.5
	var feet := (_at(_bone("foot_left")) + _at(_bone("foot_right"))) * 0.5
	_hip_depth = absf((_at(_bone("thigh_left")) - legs).dot(left))
	_shoulder_depth = absf((_at(_bone("arm_left")) - arms).dot(left))
	_hip_rise = (hips * scale - legs).dot(_up)
	_neck_rise = (neck * scale - arms).dot(_up)
	_ankle = (feet - floor_at).dot(_up)
	var climbed := 0.0
	var climbs: Array[float] = [0.0]
	for i: int in range(1, _chain.size()):
		climbed += (_at(_chain[i]) - _at(_chain[i - 1])).length()
		climbs.append(climbed)
	_rise.clear()
	for c: float in climbs:
		_rise.append(c / maxf(climbed, 0.001))
	for role: String in _bones:
		var limb := role.get_slice("_", 0)
		if limb in ["arm", "forearm", "thigh", "shin"]:
			_hang[_bone(role)] = Basis(Quaternion(_aim(role).normalized(), -_up))
		if AIMS.has(limb):
			_stretches(_bone(role), _bone(String(AIMS[limb]) + "_" + role.get_slice("_", 1)))
	# The spine's skin, but not the hips': theirs reaches down over the pelvis,
	# which a stretch toward the chest would drag down the thighs.
	for i: int in range(1, _chain.size() - 1):
		_stretches(_chain[i], _chain[i + 1])


## Marks `bone`'s skin as stretching along the line to `toward`.
func _stretches(bone: int, toward: int) -> void:
	var rest := _skeleton.get_bone_global_rest(bone)
	var along := _skeleton.get_bone_global_rest(toward).origin - rest.origin
	_stretch_axis[bone] = (rest.basis.inverse() * along).normalized()


func _bone(role: String) -> int:
	return int(_bones[role])


## Where a bone stands at rest in the viewport's space, at the model's scale.
func _at(bone: int) -> Vector3:
	return _rest_at[bone]


## Where a bone stands at rest in the viewport's space, the model unscaled.
func _rest(bone: int) -> Vector3:
	return (_skeleton.global_transform * _skeleton.get_bone_global_rest(bone)).origin


## The rest vector from a limb bone to the bone it aims at.
func _aim(role: String) -> Vector3:
	var child := String(AIMS[role.get_slice("_", 0)]) + "_" + role.get_slice("_", 1)
	return _at(_bone(child)) - _at(_bone(role))


## The lowest point of the model at rest, along its up: where its soles are.
func _floor() -> Vector3:
	var low := _reach(-1.0)
	var feet := (_rest(_bone("foot_left")) + _rest(_bone("foot_right"))) * 0.5
	return feet + _up * (low - feet).dot(_up)


## The model's furthest point at rest along its up (`sign` 1) or down (-1).
## A skinned mesh's vertices are not in the skeleton's space but in the one its
## binds undo -- the owner's first princess sat half her height below her
## bones -- so a box is carried up through a bone's rest and bind, which at
## rest agree for every bone.
func _reach(sign: float) -> Vector3:
	var low := _rest(_bone("hips"))
	for mesh: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var shape := mesh as MeshInstance3D
		if not shape.visible:
			continue
		var place := shape.global_transform
		if shape.skin != null and shape.skin.get_bind_count() > 0:
			var bone := _bind_bone(shape.skin, 0)
			place = (_skeleton.global_transform * _skeleton.get_bone_global_rest(bone)
				* shape.skin.get_bind_pose(0))
		var box := place * shape.get_aabb()
		for i: int in 8:
			if box.get_endpoint(i).dot(_up) * sign > low.dot(_up) * sign:
				low = box.get_endpoint(i)
	return low


## Gives every skinned mesh a Skin of its own, and notes each bind's bone and
## rest, for `_stretch_skins()`.
func _bind_skins() -> void:
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin == null:
			continue
		var skin := mesh.skin.duplicate() as Skin
		mesh.skin = skin
		for i: int in skin.get_bind_count():
			var bone := _bind_bone(skin, i)
			if _stretch_axis.has(bone):
				_binds.append([skin, i, bone, skin.get_bind_pose(i)])


## The bone a skin's bind is for, named or numbered.
func _bind_bone(skin: Skin, bind: int) -> int:
	var bone := skin.get_bind_bone(bind)
	return bone if bone >= 0 else _skeleton.find_bone(skin.get_bind_name(bind))


## Each stretching bone's binds, scaled along the bone by this frame's
## stretch before they carry a vertex into the bone's space (class comment).
func _stretch_skins() -> void:
	for bind: Array in _binds:
		var axis: Vector3 = _stretch_axis[bind[2]]
		var by: float = _stretch.get(bind[2], 1.0) - 1.0
		# I + (stretch - 1) * axis axis^T, a column at a time.
		var along := Transform3D(Basis(Vector3.RIGHT + axis * axis.x * by,
			Vector3.UP + axis * axis.y * by, Vector3.BACK + axis * axis.z * by), Vector3.ZERO)
		(bind[0] as Skin).set_bind_pose(int(bind[1]), along * (bind[3] as Transform3D))


## The stretch a bone's skin takes this frame: `length` over its rest.
func _stretch_to(bone: int, length: float, rest: float) -> void:
	_stretch[bone] = clampf(length / maxf(rest, 0.001), STRETCH.x, STRETCH.y)


## Dyes the cloth (class comment), and hangs the flash and the ink edge on
## every mesh.
func _dress() -> void:
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.visible:
			continue
		for i: int in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i) as BaseMaterial3D
			if material == null:
				continue
			var names: String = mesh.mesh.surface_get_name(i) if mesh.mesh is ArrayMesh else ""
			names += " " + material.resource_name + " " + mesh.name
			var cloth := _cloth_in(material.albedo_texture)
			if not _is_named(names, CLOTH) and cloth[0] < CLOTH_SHARE:
				continue
			var dye := _dye(material, cloth)
			mesh.set_surface_override_material(i, dye)
			_cloth.append(dye)
		mesh.material_overlay = _overlay(absf(mesh.global_transform.basis.get_scale().x))


static func _is_named(names: String, words: Array[String]) -> bool:
	var lower := names.to_lower()
	for word: String in words:
		if lower.contains(word):
			return true
	return false


## The cloth tint over a part's own textures and finish.
func _dye(material: BaseMaterial3D, cloth: Array) -> ShaderMaterial:
	var dye := ShaderMaterial.new()
	dye.shader = TINT
	dye.resource_name = material.resource_name
	dye.set_shader_parameter("albedo_texture", material.albedo_texture)
	dye.set_shader_parameter("albedo", material.albedo_color)
	dye.set_shader_parameter("roughness", material.roughness)
	dye.set_shader_parameter("metallic", material.metallic)
	dye.set_shader_parameter("use_normal",
		material.normal_enabled and material.normal_texture != null)
	dye.set_shader_parameter("normal_texture", material.normal_texture)
	dye.set_shader_parameter("normal_depth", material.normal_scale)
	dye.set_shader_parameter("source_hue", cloth[1])
	dye.set_shader_parameter("source_saturation", cloth[2])
	dye.set_shader_parameter("source_value", cloth[3])
	dye.set_shader_parameter("hue_reach", Vector2(CLOTH_HUE * 0.6, CLOTH_HUE * 1.4))
	return dye


## How much of a texture is the model's own cloth colour, and that cloth's
## mean hue, saturation and value, in the linear space the shader samples in:
## [share, hue, saturation, value]. Read from a 32-pixel copy, once per
## texture. A texture that cannot be read back counts as no cloth.
static func _cloth_in(texture: Texture2D) -> Array:
	var own := OWN_CLOTH.srgb_to_linear()
	var none := [0.0, own.h, own.s, own.v]
	if texture == null:
		return none
	var key := texture.get_rid()
	if _measured.has(key):
		return _measured[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return none
	image = image.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return none
	image.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	var found := 0
	var hue := Vector2.ZERO
	var saturation := 0.0
	var value := 0.0
	for y: int in 32:
		for x: int in 32:
			var pixel := image.get_pixel(x, y).srgb_to_linear()
			var away := absf(fposmod(pixel.h - own.h + 0.5, 1.0) - 0.5)
			if away > CLOTH_HUE or pixel.s < 0.25:
				continue
			found += 1
			hue += Vector2.from_angle(pixel.h * TAU)
			saturation += pixel.s
			value += pixel.v
	var out := none
	if found > 0:
		out = [found / 1024.0, fposmod(hue.angle() / TAU, 1.0), saturation / found,
			value / found]
	_measured[key] = out
	return out


## The flash, with the ink edge behind it. The edge grows in the mesh's own
## units, so it is divided by the mesh's scale to stand `OUTLINE` proud in
## the art's.
func _overlay(scale: float) -> StandardMaterial3D:
	var edge := StandardMaterial3D.new()
	edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.cull_mode = BaseMaterial3D.CULL_FRONT
	edge.grow = true
	edge.grow_amount = OUTLINE / maxf(scale, 0.0001)
	var flash_pass := StandardMaterial3D.new()
	flash_pass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_pass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_pass.albedo_color = Color(Palette.PAPER, 0.0)
	flash_pass.next_pass = edge
	_overlays.append(flash_pass)
	_edges.append(edge)
	return flash_pass


## --- layers -------------------------------------------------------------------

## The model is posed in the first layer, not the body's: the sword may be
## drawn before the body, and it leaves the hand the model has just put
## somewhere (`sword_hand()`).
func draw_back(art: PlayerArt, pose: Dictionary) -> bool:
	super(art, pose)
	_ensure(art)
	_fit(art)
	_colour(art)
	_place(art, pose)
	return true


func draw_body(art: PlayerArt, _pose: Dictionary) -> bool:
	art.draw_texture_rect(_viewport.get_texture(), BOX, false)
	return true


## --- colour ---------------------------------------------------------------------

func _tones(_art: PlayerArt) -> Dictionary:
	return {}


func _colour(art: PlayerArt) -> void:
	super(art)
	for material: ShaderMaterial in _cloth:
		material.set_shader_parameter("tint", art.cloth)
		material.set_shader_parameter("amount", 0.0 if art.cloth == OWN_CLOTH else 1.0)
	var edge := art._c(art.ink if not _cloth.is_empty() else art.cloth)
	for material: StandardMaterial3D in _edges:
		material.albedo_color = edge
	for material: StandardMaterial3D in _overlays:
		material.albedo_color = Color(Palette.PAPER, clampf(art._flash, 0.0, 1.0) * FLASH)


## --- posing ---------------------------------------------------------------------

## PrincessCostume's light, for her reason: under the world's gold key and
## crimson ambient her blue goes to mud. Still a warm sun from the left.
func _sun() -> Color:
	return Palette.PAPER


func _ambient() -> Color:
	return Palette.STEEL_DARK.lerp(Palette.SHADOW_DEEP, 0.35)


func _yaw() -> float:
	return 0.55


func _pose_parts(art: PlayerArt, pose: Dictionary, up: Vector3, forward: Vector3) -> void:
	if _skeleton == null:
		return
	var moment := ModelClips.moment(art)
	_clip = _clips.pick(moment) if _clips != null else []
	_hand_at = Vector2(NAN, NAN)
	if not _clip.is_empty():
		_pose_clip(art, moment)
		return
	# The rig's pose from scratch every frame: the bones it does not drive
	# (fingers, twists) back at rest, whatever a clip left them in.
	_model.transform = Transform3D(Basis.from_scale(Vector3.ONE * _scale), Vector3.ZERO)
	_skeleton.reset_bone_poses()
	var body := _axes(up, forward) * _frame.transposed()
	# The body's left, which is the hinge every limb turns about. The rig keeps
	# each limb at one depth, so this is the camera's axis whichever way the
	# figure faces, and the near side is whichever of the model's is on it.
	var left := up.cross(forward).normalized()
	_near = "left" if left.z > 0.0 else "right"
	var top := _pose_spine(art, body, up)
	_pose_head(art, pose, body, up)
	for near: bool in [false, true]:
		var side := _near if near else _far()
		var depth := 1.0 if near else -1.0
		var foot: Vector2 = art._foot_front if near else art._foot_back
		var knee: Vector2 = art._knee_front if near else art._knee_back
		var hand: Vector2 = art._hand_front if near else art._hand_back
		var hip := _lift(art._hip, depth * _hip_depth)
		var knee_at := _lift(knee, depth * _hip_depth)
		var ankle := _lift(foot + Vector2(0.0, -_ankle), depth * _hip_depth)
		_limb("thigh_" + side, body, left, hip, knee_at)
		var shin := _limb("shin_" + side, body, left, knee_at, ankle)
		_pose_bone(_bone("foot_" + side), shin, ankle)
		var shoulder := _lift(art._shoulder, depth * _shoulder_depth)
		var elbow := _lift(art._elbow(hand), depth * _shoulder_depth)
		var hand_at := _lift(hand, depth * _shoulder_depth)
		if _bones.has("clavicle_" + side):
			_pose_clavicle(side, body, top, shoulder)
		_limb("arm_" + side, body, left, shoulder, elbow)
		var fore := _limb("forearm_" + side, body, left, elbow, hand_at)
		_pose_bone(_bone("hand_" + side), fore, hand_at)
	_stretch_skins()


## The clip, sampled, turned to face the way the body faces, its soles on the
## art's floor, its hips slid over the rig's hip, and lifted out of the floor
## if the body is on it. Its skin is unstretched: a clip's bones are the
## model's own length.
func _pose_clip(art: PlayerArt, moment: Dictionary) -> void:
	_stretch.clear()
	_stretch_skins()
	_clips.sample(_clip[0], _clip[1])
	var turn := _axes(Vector3.UP, Vector3(art._f, 0.0, 0.0)) * _axes(Vector3.UP, _frame.x).transposed()
	var basis := turn * _clip_scale
	_model.transform = Transform3D(basis, -(basis * _sole))
	var hips := _world(_bone("hips"))
	var slide := (art._hip.x - (hips.x * _cos - hips.z * _sin)) / _cos
	var lift := 0.0
	if moment["grounded"]:
		var low := minf(_world(_bone("foot_left")).y, _world(_bone("foot_right")).y)
		lift = maxf(0.0, _ankle * _clip_scale / _scale - low)
	_model.position += Vector3(slide, lift, 0.0)
	for role: String in _bones:
		_grow(_world(_bone(role)), 1.5)
	var head := _world(_bone("head"))
	_grow(head + (head - _world(_bone("neck"))) * 2.0, 0.0)
	_hand_at = _project(_world(_bone(SWORD_HAND)))


## Where a point of the viewport's space lands in the art's.
func _project(at: Vector3) -> Vector2:
	var pixel := _camera.unproject_position(at)
	return BOX.position + pixel / Vector2(_viewport.size) * BOX.size


## Grows `drawn` by a point of the viewport's space, `reach` round it.
func _grow(at: Vector3, reach: float) -> void:
	var flat := Vector2(at.x * _cos - at.z * _sin, -at.y)
	drawn = drawn.expand(flat - Vector2.ONE * reach).expand(flat + Vector2.ONE * reach)


func _far() -> String:
	return "left" if _near == "right" else "right"


## The spine spaced out from the hips to the neck, turned with the body; the
## hips stand their rest height above the rig's hip, the neck its rest height
## above the rig's shoulder. Returns the top of the chain below the neck: the
## bone the clavicles hang from.
func _pose_spine(art: PlayerArt, body: Basis, up: Vector3) -> int:
	var hips := _lift(art._hip, 0.0) + up * _hip_rise
	var neck := _lift(art._shoulder, 0.0) + up * _neck_rise
	for i: int in _chain.size() - 1:
		_pose_bone(_chain[i], body, hips.lerp(neck, _rise[i]))
	var climbed := 0.0
	for i: int in range(1, _chain.size()):
		climbed += (_at(_chain[i]) - _at(_chain[i - 1])).length()
	for i: int in range(1, _chain.size() - 1):
		_stretch_to(_chain[i], (neck - hips).length(), climbed)
	return _chain[maxi(_chain.size() - 2, 0)]


## The head looks where the rig's hood looks, its face turned toward the
## viewer (ModelCostume._head()); the neck takes half that turn.
func _pose_head(art: PlayerArt, pose: Dictionary, body: Basis, up: Vector3) -> void:
	var neck_bone := _bone("neck")
	var head_bone := _bone("head")
	var neck := _lift(art._shoulder, 0.0) + up * _neck_rise
	var frame := _head(art, pose, up, neck, 0.0, FACE_TURN)[1] as Basis
	var head := frame * _frame.transposed()
	var turn := body.slerp(head, 0.5)
	_pose_bone(neck_bone, turn, neck)
	var crown := neck + turn * (_at(head_bone) - _at(neck_bone))
	_pose_bone(head_bone, head, crown)
	# The skull above the head bone, so `drawn` covers the whole head.
	var top := crown + frame.y * 2.0 * (_at(head_bone) - _at(neck_bone)).length()
	drawn = drawn.expand(Vector2(top.x * _cos - top.z * _sin, -top.y))


## A clavicle rides on the chest where it rests, and turns from there to
## reach the shoulder.
func _pose_clavicle(side: String, body: Basis, top: int, shoulder: Vector3) -> void:
	var bone := _bone("clavicle_" + side)
	var at := _world(top) + body * (_at(bone) - _at(top))
	var rest := body * _aim("clavicle_" + side)
	var reach := shoulder - at
	var turn := Basis(Quaternion(rest.normalized(), reach.normalized())) * body
	_pose_bone(bone, turn, at)
	_stretch_to(bone, reach.length(), rest.length())


## A limb bone from `from` to `to`: hung down the body, turned with it, and
## hinged about its left-right axis onto the rig's direction (see the class
## comment). Returns the turn, for the hand or foot that follows it.
func _limb(role: String, body: Basis, left: Vector3, from: Vector3, to: Vector3) -> Basis:
	var bone := _bone(role)
	var along := to - from
	var down := body * -_up
	var angle := atan2(left.dot(down.cross(along)), down.dot(along))
	var turn := Basis(left, angle) * body * (_hang[bone] as Basis)
	_pose_bone(bone, turn, from)
	_stretch_to(bone, along.length(), _aim(role).length())
	return turn


## Puts a bone at `at` in the viewport's space, its rest frame carried round
## by `turn`, and grows `drawn` by where it lands.
func _pose_bone(bone: int, turn: Basis, at: Vector3) -> void:
	var size: float = _rest_size[bone]
	var world := Transform3D((turn * (_rest_turn[bone] as Basis)) * size, at)
	_skeleton.set_bone_global_pose(bone, _skeleton.global_transform.affine_inverse() * world)
	_grow(at, 1.5)


func _world(bone: int) -> Vector3:
	return (_skeleton.global_transform * _skeleton.get_bone_global_pose(bone)).origin
