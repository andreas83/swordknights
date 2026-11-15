extends RefCounted
## A stand-in for the owner's rigged character: a skinned, textured humanoid
## built in code, in the shape an auto-rigger's `.glb` arrives in, so the
## pipeline that will pose the real one (scripts/player/rigged_costume.gd)
## is exercised before the real one exists.
##
## Deliberately not a `class_name`, like the other support files: load it with
##
##     const RiggedSupport := preload("res://tests/rigged_support.gd")
##     var scene := RiggedSupport.build()
##
## ## Why it is built awkwardly on purpose
##
## A stand-in that happened to share every convenient assumption with the
## costume would prove nothing about the next file the owner drops in (the
## current one, a Tripo export, is tested on its own in
## test_rigged_figure.gd). So it carries the awkward parts of a real Mixamo
## export:
##
## - **Mixamo names as Godot imports them.** `mixamorig:Hips` reaches the
##   skeleton as `mixamorig_Hips` (a bone name may not hold a colon).
## - **An armature that is turned and scaled.** Blender exports Z-up in
##   centimetres under an `Armature` node rotated a quarter turn and scaled by
##   0.01. Bones and vertices here are authored in that space, so a costume
##   that read rest positions without the node's transform would be a hundred
##   times too big and lying on its back.
## - **Rolled bones.** Each bone's +Y runs to its child, as Mixamo's do, but
##   its X is rolled by an arbitrary amount: a costume that assumed a bone's
##   local axes meant anything anatomical would twist the limbs.
## - **A T-pose rest**, arms straight out, feet flat, facing +Z.
## - **A skinned, blended torso** (weights shared between neighbouring spine
##   bones) and rigid limbs, both textured, with the cloth in a material named
##   for it (`Tunic_cloth`) and the rest not.
## - **An AnimationPlayer**, which an import carries and the costume must
##   take away: the model has no animation of its own.
##
## Its proportions are a person's, 1.78 m tall, hip joints at 0.93 m: not the
## rig's, so the costume's scaling and stretching are exercised too.

## The bones in parent-first order: name, parent, world position in metres
## (Y up, facing +Z, the character's left at +X), and the child its +Y aims at.
const BONES: Array[Array] = [
	["Hips", "", Vector3(0.0, 0.98, 0.0), "Spine"],
	["Spine", "Hips", Vector3(0.0, 1.08, 0.0), "Spine1"],
	["Spine1", "Spine", Vector3(0.0, 1.20, 0.0), "Spine2"],
	["Spine2", "Spine1", Vector3(0.0, 1.32, 0.0), "Neck"],
	["Neck", "Spine2", Vector3(0.0, 1.46, 0.0), "Head"],
	["Head", "Neck", Vector3(0.0, 1.56, 0.0), "HeadTop_End"],
	["HeadTop_End", "Head", Vector3(0.0, 1.78, 0.0), ""],
	["LeftShoulder", "Spine2", Vector3(0.04, 1.42, -0.01), "LeftArm"],
	["LeftArm", "LeftShoulder", Vector3(0.17, 1.42, 0.0), "LeftForeArm"],
	["LeftForeArm", "LeftArm", Vector3(0.45, 1.42, 0.0), "LeftHand"],
	["LeftHand", "LeftForeArm", Vector3(0.71, 1.42, 0.0), "LeftHandMiddle1"],
	["LeftHandMiddle1", "LeftHand", Vector3(0.80, 1.42, 0.0), ""],
	["RightShoulder", "Spine2", Vector3(-0.04, 1.42, -0.01), "RightArm"],
	["RightArm", "RightShoulder", Vector3(-0.17, 1.42, 0.0), "RightForeArm"],
	["RightForeArm", "RightArm", Vector3(-0.45, 1.42, 0.0), "RightHand"],
	["RightHand", "RightForeArm", Vector3(-0.71, 1.42, 0.0), "RightHandMiddle1"],
	["RightHandMiddle1", "RightHand", Vector3(-0.80, 1.42, 0.0), ""],
	["LeftUpLeg", "Hips", Vector3(0.09, 0.93, 0.0), "LeftLeg"],
	["LeftLeg", "LeftUpLeg", Vector3(0.09, 0.51, 0.01), "LeftFoot"],
	["LeftFoot", "LeftLeg", Vector3(0.09, 0.085, -0.02), "LeftToeBase"],
	["LeftToeBase", "LeftFoot", Vector3(0.09, 0.015, 0.11), "LeftToe_End"],
	["LeftToe_End", "LeftToeBase", Vector3(0.09, 0.015, 0.18), ""],
	["RightUpLeg", "Hips", Vector3(-0.09, 0.93, 0.0), "RightLeg"],
	["RightLeg", "RightUpLeg", Vector3(-0.09, 0.51, 0.01), "RightFoot"],
	["RightFoot", "RightLeg", Vector3(-0.09, 0.085, -0.02), "RightToeBase"],
	["RightToeBase", "RightFoot", Vector3(-0.09, 0.015, 0.11), "RightToe_End"],
	["RightToe_End", "RightToeBase", Vector3(-0.09, 0.015, 0.18), ""],
]
const PREFIX := "mixamorig_"
## The armature node's transform, as Blender exports it: Z up in centimetres.
const ARMATURE := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5) * 0.01, Vector3.ZERO)
## The materials, by name: the cloth one is recoloured, the others are not.
const CLOTH := "Tunic_cloth"
const SKIN := "Skin"
const LEATHER := "Leather"
const HAIR := "Hair"


## The stand-in, packed as an imported `.glb` would be.
static func build() -> PackedScene:
	var root := Node3D.new()
	root.name = "StandIn"
	var armature := Node3D.new()
	armature.name = "Armature"
	armature.transform = ARMATURE
	root.add_child(armature)
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	armature.add_child(skeleton)
	var rests := _skeleton(skeleton)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _mesh(rests)
	body.skin = _skin(skeleton, rests)
	skeleton.add_child(body)
	body.skeleton = NodePath("..")
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	for node: Node in [armature, skeleton, body, player]:
		node.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


## Where a bone sits, by its unprefixed name, in metres, Y up: for a test
## that wants the stand-in's own proportions.
static func rest_position(bone: String) -> Vector3:
	for spec: Array in BONES:
		if spec[0] == bone:
			return spec[2]
	return Vector3.ZERO


## Adds the bones; returns each one's rest in skeleton space, by index.
static func _skeleton(skeleton: Skeleton3D) -> Array[Transform3D]:
	var into := ARMATURE.affine_inverse()
	var turn := into.basis.orthonormalized()
	var globals: Array[Transform3D] = []
	for i: int in BONES.size():
		var spec: Array = BONES[i]
		var at: Vector3 = spec[2]
		var aim := Vector3.UP
		if spec[3] != "":
			aim = (rest_position(spec[3]) - at).normalized()
		# +Y down the bone, X rolled by an angle that differs per bone.
		var across := aim.cross(Vector3.BACK if absf(aim.z) < 0.9 else Vector3.RIGHT)
		var frame := Basis(across.normalized(), aim, across.normalized().cross(aim))
		frame = Basis(aim, 0.4 + 0.37 * i) * frame
		globals.append(Transform3D(turn * frame.orthonormalized(), into * at))
		var index := skeleton.add_bone(PREFIX + String(spec[0]))
		var parent := -1 if spec[1] == "" else _index(String(spec[1]))
		skeleton.set_bone_parent(index, parent)
		var local := globals[i] if parent < 0 else globals[parent].affine_inverse() * globals[i]
		skeleton.set_bone_rest(index, local)
	skeleton.reset_bone_poses()
	return globals


static func _index(bone: String) -> int:
	for i: int in BONES.size():
		if BONES[i][0] == bone:
			return i
	return -1


static func _skin(skeleton: Skeleton3D, rests: Array[Transform3D]) -> Skin:
	var skin := Skin.new()
	for i: int in rests.size():
		skin.add_named_bind(skeleton.get_bone_name(i), rests[i].affine_inverse())
	return skin


## A weighting that puts every vertex wholly on `bone`.
static func _rigid(bone: String) -> Callable:
	var index := _index(bone)
	return func(_at: Vector3) -> Array: return [[index, 1.0]]


## Shared between the two spine bones a vertex lies between, by height.
static func _spine_weights(at: Vector3) -> Array:
	var chain: Array[String] = ["Hips", "Spine", "Spine1", "Spine2", "Neck"]
	for i: int in chain.size() - 1:
		var low := rest_position(chain[i]).y
		var high := rest_position(chain[i + 1]).y
		if at.y <= high or i == chain.size() - 2:
			var t := clampf((at.y - low) / (high - low), 0.0, 1.0)
			return [[_index(chain[i]), 1.0 - t], [_index(chain[i + 1]), t]]
	return [[0, 1.0]]


## --- the body -----------------------------------------------------------------

## One surface per material. Each piece is a primitive mesh's arrays, moved
## into place in metres and then into the armature's space.
static func _mesh(_rests: Array[Transform3D]) -> ArrayMesh:
	var surfaces := {}
	for material: String in [CLOTH, SKIN, LEATHER, HAIR]:
		surfaces[material] = Surface.new()
	var cloth: Surface = surfaces[CLOTH]
	var skin: Surface = surfaces[SKIN]
	var leather: Surface = surfaces[LEATHER]
	var hair: Surface = surfaces[HAIR]
	# The torso, blended up the spine so a stretched spine stretches it.
	cloth.add(_cylinder(0.13, 0.15, 16, 6), _between(Vector3(0, 0.86, 0),
		Vector3(0, 1.47, 0), Vector2(1.0, 0.68)), func(at: Vector3) -> Array: return _spine_weights(at))
	cloth.add(_cylinder(0.15, 0.2, 16, 1), _between(Vector3(0, 0.98, 0),
		Vector3(0, 0.74, 0), Vector2(1.0, 0.85)), _rigid("Hips"))
	skin.add(_cylinder(0.05, 0.05, 8, 1), _between(Vector3(0, 1.44, 0),
		Vector3(0, 1.58, 0), Vector2.ONE), _rigid("Neck"))
	skin.add(_sphere(0.115), Transform3D(Basis.from_scale(Vector3(0.95, 1.1, 1.0)),
		Vector3(0, 1.66, 0.01)), _rigid("Head"))
	# A nose, so which way the face points shows on a render.
	skin.add(_sphere(0.03), Transform3D(Basis.IDENTITY, Vector3(0, 1.65, 0.12)),
		_rigid("Head"))
	hair.add(_sphere(0.125), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.05)),
		Vector3(0, 1.71, -0.02)), _rigid("Head"))
	for side: String in ["Left", "Right"]:
		var x := 1.0 if side == "Left" else -1.0
		cloth.add(_sphere(0.065), Transform3D(Basis.IDENTITY, Vector3(0.17 * x, 1.42, 0)),
			_rigid(side + "Shoulder"))
		_limb(cloth, side + "Arm", side + "ForeArm", 0.055, 0.045)
		_limb(leather, side + "ForeArm", side + "Hand", 0.045, 0.035)
		skin.add(_sphere(0.05), Transform3D(Basis.IDENTITY, Vector3(0.75 * x, 1.42, 0)),
			_rigid(side + "Hand"))
		_limb(cloth, side + "UpLeg", side + "Leg", 0.08, 0.06)
		_limb(leather, side + "Leg", side + "Foot", 0.06, 0.045)
		leather.add(_box(Vector3(0.09, 0.08, 0.26)), Transform3D(Basis.IDENTITY,
			Vector3(0.09 * x, 0.04, 0.06)), _rigid(side + "Foot"))
	var mesh := ArrayMesh.new()
	for material: String in surfaces:
		(surfaces[material] as Surface).commit(mesh, _material(material))
	return mesh


static func _limb(into: Surface, bone: String, child: String, top: float,
		bottom: float) -> void:
	var a := rest_position(bone)
	var b := rest_position(child)
	into.add(_cylinder(top, bottom, 10, 1), _between(a, b, Vector2.ONE),
		_rigid(bone))


## A unit-height primitive's transform that runs it from `a` to `b`,
## `squash` scaling its two cross axes.
static func _between(a: Vector3, b: Vector3, squash: Vector2) -> Transform3D:
	var along := a - b
	var y := along.normalized()
	var x := y.cross(Vector3.BACK)
	if x.length_squared() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x * squash.x, along, z * squash.y), (a + b) * 0.5)


static func _cylinder(top: float, bottom: float, sides: int, rings: int) -> Array:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = 1.0
	mesh.radial_segments = sides
	mesh.rings = rings
	return mesh.get_mesh_arrays()


static func _sphere(radius: float) -> Array:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return mesh.get_mesh_arrays()


static func _box(size: Vector3) -> Array:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh.get_mesh_arrays()


## Textured as a generated model is: the cloth a weave in the princess's blue,
## the skin a texture too, so that only the cloth's is seen to change.
static func _material(name: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.roughness = 0.7
	match name:
		CLOTH:
			material.albedo_texture = _weave(Color("2f4fa8"), Color("6f8fe0"))
		SKIN:
			material.albedo_texture = _weave(Color("f0c8a8"), Color("e8b898"))
		LEATHER:
			material.albedo_color = Color("6b4428")
		HAIR:
			material.albedo_color = Color("4a2c18")
	return material


static func _weave(dark: Color, light: Color) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y: int in 16:
		for x: int in 16:
			image.set_pixel(x, y, light if (x + y) % 4 < 2 else dark)
	return ImageTexture.create_from_image(image)


## The vertices of one material, skinned, in the armature's space.
class Surface:
	extends RefCounted

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()

	## Adds a primitive's arrays, placed by `place` (metres, Y up), weighted
	## by `weigh` (a world position -> [[bone, weight], ...]).
	func add(arrays: Array, place: Transform3D, weigh: Callable) -> void:
		var into := ARMATURE.affine_inverse()
		var turn := place.basis.inverse().transposed()
		var base := vertices.size()
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var faces: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var maps: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for i: int in points.size():
			var at := place * points[i]
			vertices.append(into * at)
			normals.append((into.basis * (turn * faces[i])).normalized())
			uvs.append(maps[i])
			var pairs: Array = weigh.call(at)
			for slot: int in 4:
				var pair: Array = pairs[slot] if slot < pairs.size() else [0, 0.0]
				bones.append(int(pair[0]))
				weights.append(float(pair[1]))
		for index: int in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
			indices.append(base + index)

	func commit(mesh: ArrayMesh, material: Material) -> void:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surface := mesh.get_surface_count() - 1
		mesh.surface_set_material(surface, material)
		mesh.surface_set_name(surface, material.resource_name)
