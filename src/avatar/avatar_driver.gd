@tool
class_name AvatarDriver
extends Node3D

## Loads an external avatar and maps OVR-compatible visemes to blend shapes.

const VISEMES := [
	"sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS",
	"nn", "RR", "aa", "E", "I", "O", "U",
]

## Common names used by Ready Player Me, VRChat-compatible meshes and VRM 0.x.
## Keeping this policy here lets the audio pipeline remain avatar-format agnostic.
const VISEME_SHAPE_ALIASES := [
	["viseme_sil", "vrc.v_sil", "sil"],
	["viseme_PP", "vrc.v_pp", "PP"],
	["viseme_FF", "vrc.v_ff", "FF"],
	["viseme_TH", "vrc.v_th", "TH"],
	["viseme_DD", "vrc.v_dd", "DD"],
	["viseme_kk", "vrc.v_kk", "kk"],
	["viseme_CH", "vrc.v_ch", "CH"],
	["viseme_SS", "vrc.v_ss", "SS"],
	["viseme_nn", "vrc.v_nn", "nn"],
	["viseme_RR", "vrc.v_rr", "RR"],
	["viseme_aa", "vrc.v_aa", "aa", "AA"],
	["viseme_E", "vrc.v_e", "E", "ee"],
	["viseme_I", "vrc.v_ih", "I", "ih"],
	["viseme_O", "vrc.v_oh", "O", "OH", "oh"],
	["viseme_U", "vrc.v_ou", "U", "ou"],
]

@export_file("*.vrm", "*.tscn", "*.scn", "*.glb", "*.gltf") var avatar_path := "res://avatars/freakhound_avatar.tscn"
@export_range(0.0, 4.0, 0.05, "or_greater") var spring_stiffness_multiplier := 1.5
@export_range(0.0, 3.0, 0.05, "or_greater") var spring_drag_multiplier := 1.25
@export_range(0.0, 500.0, 5.0, "or_greater") var mouth_attack_ms := 80.0
@export_range(0.0, 500.0, 5.0, "or_greater") var mouth_release_ms := 45.0

var status := "no avatar"
var _meshes: Array[MeshInstance3D] = []
var _shape_indices: Array[PackedInt32Array] = []
var _avatar_root: Node3D
var _skeleton: Skeleton3D
var _head_bone := -1
var _head_rest_rotation := Quaternion.IDENTITY
var _target_visemes := PackedFloat32Array()
var _displayed_visemes := PackedFloat32Array()
var _head_reference_position := Vector3.ZERO
var _arm_ik: Dictionary = {}


func _ready() -> void:
	load_avatar(avatar_path)
	set_process(true)


func _process(delta: float) -> void:
	if _target_visemes.is_empty():
		return
	if _displayed_visemes.size() != _target_visemes.size():
		_displayed_visemes = _target_visemes.duplicate()
	var changed := false
	for index in _target_visemes.size():
		var target := _target_visemes[index]
		var current := _displayed_visemes[index]
		var time_ms := mouth_attack_ms if target > current else mouth_release_ms
		var alpha := 1.0 if time_ms <= 0.0 else 1.0 - exp(-delta * 1000.0 / time_ms)
		var next := lerpf(current, target, alpha)
		if not is_equal_approx(next, current):
			changed = true
		_displayed_visemes[index] = next
	if changed:
		_apply_viseme_weights(_displayed_visemes)


func load_avatar(path: String) -> bool:
	if not ResourceLoader.exists(path):
		status = "avatar absent: %s" % path
		if Engine.is_editor_hint():
			_create_editor_standin()
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		status = "avatar load failed"
		return false
	var avatar := packed.instantiate()
	avatar.name = "Avatar"
	add_child(avatar)
	_avatar_root = avatar as Node3D
	_find_head_bone(avatar)
	# Imported VRMSecondary initializes after the scene enters the tree and first
	# mirrors its original array to the root, so apply policy on the next turn.
	call_deferred("_apply_spring_tuning", avatar)
	_find_viseme_meshes(avatar)
	return not _meshes.is_empty()


func _find_head_bone(root: Node) -> void:
	_skeleton = _find_skeleton(root)
	_head_bone = -1
	if _skeleton == null:
		return
	for bone_name: StringName in [&"Head", &"head", &"HEAD"]:
		_head_bone = _skeleton.find_bone(bone_name)
		if _head_bone >= 0:
			break
	if _head_bone >= 0:
		_head_rest_rotation = _skeleton.get_bone_pose_rotation(_head_bone)
		_head_reference_position = _skeleton.get_bone_global_pose(_head_bone).origin
	_configure_arm_ik()


func _configure_arm_ik() -> void:
	_arm_ik.clear()
	if _skeleton == null:
		return
	for side: String in ["left", "right"]:
		var title := side.capitalize()
		var root_name := StringName("%sUpperArm" % title)
		var tip_name := StringName("%sHand" % title)
		if _skeleton.find_bone(root_name) < 0 or _skeleton.find_bone(tip_name) < 0:
			continue
		var ik := SkeletonIK3D.new()
		ik.name = "%sArmIK" % title
		ik.root_bone = root_name
		ik.tip_bone = tip_name
		ik.override_tip_basis = false
		ik.use_magnet = true
		ik.max_iterations = 12
		ik.min_distance = 0.002
		_skeleton.add_child(ik)
		ik.start()
		_arm_ik[side] = ik


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _apply_spring_tuning(root: Node) -> void:
	# VRMSecondary mirrors this root property. Writing both directions would let
	# the proxy overwrite our tuned resources with its original array.
	var vrm_root := _find_spring_owner(root)
	if vrm_root == null:
		return
	for spring: Resource in vrm_root.get("spring_bones"):
		if not spring.has_meta(&"vtuber_base_stiffness"):
			spring.set_meta(&"vtuber_base_stiffness", float(spring.get("stiffness_scale")))
			spring.set_meta(&"vtuber_base_drag", float(spring.get("drag_force_scale")))
		spring.set(
			"stiffness_scale",
			float(spring.get_meta(&"vtuber_base_stiffness")) * spring_stiffness_multiplier,
		)
		spring.set(
			"drag_force_scale",
			float(spring.get_meta(&"vtuber_base_drag")) * spring_drag_multiplier,
		)


func _find_spring_owner(node: Node) -> Node:
	for property: Dictionary in node.get_property_list():
		if property.name == &"spring_bones" and node.name != &"secondary":
			return node
	for child in node.get_children(true):
		var found := _find_spring_owner(child)
		if found != null:
			return found
	return null


func _create_editor_standin() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.62, 0.75)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.32
	body_mesh.height = 1.35
	var body := MeshInstance3D.new()
	body.name = "EditorStandInBody"
	body.mesh = body_mesh
	body.material_override = material
	body.position.y = 0.7
	add_child(body)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.24
	head_mesh.height = 0.48
	var head := MeshInstance3D.new()
	head.name = "EditorStandInHead"
	head.mesh = head_mesh
	head.material_override = material
	head.position.y = 1.62
	add_child(head)


func _find_viseme_meshes(root: Node) -> void:
	_meshes.clear()
	_shape_indices.clear()
	_collect_meshes(root)
	var mapped := 0
	for mesh in _meshes:
		var indices := PackedInt32Array()
		for aliases in VISEME_SHAPE_ALIASES:
			var index := _find_first_shape(mesh, aliases)
			indices.append(index)
			if index >= 0:
				mapped += 1
		_shape_indices.append(indices)
	status = "avatar ready: %d meshes, %d mappings" % [_meshes.size(), mapped]


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := node as MeshInstance3D
		for aliases in VISEME_SHAPE_ALIASES:
			if _find_first_shape(mesh, aliases) >= 0:
				_meshes.append(mesh)
				break
	for child in node.get_children():
		_collect_meshes(child)


func _find_first_shape(mesh: MeshInstance3D, aliases: Array) -> int:
	for alias: String in aliases:
		var index := mesh.find_blend_shape_by_name(alias)
		if index >= 0:
			return index
	return -1


func set_visemes(weights: PackedFloat32Array) -> void:
	_target_visemes = weights.duplicate()
	if _displayed_visemes.size() != weights.size():
		_displayed_visemes = weights.duplicate()
		_apply_viseme_weights(_displayed_visemes)


func _apply_viseme_weights(weights: PackedFloat32Array) -> void:
	for mesh_index in _meshes.size():
		var mesh := _meshes[mesh_index]
		var indices := _shape_indices[mesh_index]
		for viseme_index in mini(VISEMES.size(), weights.size()):
			var shape_index := indices[viseme_index]
			if shape_index >= 0:
				mesh.set_blend_shape_value(shape_index, clampf(weights[viseme_index], 0.0, 1.0))


func set_pose(frame: Variant) -> void:
	if _avatar_root == null:
		return
	var head_rotation := Quaternion.IDENTITY
	var has_head_rotation := false
	var quaternion_value: Variant = frame.landmarks.get("head_rotation_quaternion", [])
	if quaternion_value is Array and quaternion_value.size() == 4:
		var tracked_rotation := Quaternion(
			float(quaternion_value[0]), float(quaternion_value[1]),
			float(quaternion_value[2]), float(quaternion_value[3])
		).normalized()
		var tracked_euler := tracked_rotation.get_euler()
		tracked_euler.x = -tracked_euler.x
		head_rotation = Quaternion.from_euler(tracked_euler)
		has_head_rotation = true
	else:
		var rotation_value: Variant = frame.landmarks.get("head_rotation_degrees", [])
		if rotation_value is Array and rotation_value.size() == 3:
			head_rotation = Quaternion.from_euler(Vector3(
				-deg_to_rad(float(rotation_value[0])),
				deg_to_rad(float(rotation_value[1])),
				deg_to_rad(float(rotation_value[2])),
			))
			has_head_rotation = true
	if has_head_rotation and _skeleton != null and _head_bone >= 0:
		_skeleton.set_bone_pose_rotation(_head_bone, _head_rest_rotation * head_rotation)
	_apply_arm_pose(frame.landmarks, "left")
	_apply_arm_pose(frame.landmarks, "right")
	var shoulder_value: Variant = frame.landmarks.get("shoulder_center", [])
	if shoulder_value is Array and shoulder_value.size() >= 1:
		_avatar_root.position.x = clampf(float(shoulder_value[0]), -0.25, 0.25)


func _apply_arm_pose(landmarks: Dictionary, side: String) -> void:
	var ik := _arm_ik.get(side) as SkeletonIK3D
	if ik == null:
		return
	var hand_value: Variant = landmarks.get("%s_hand" % side, {})
	var elbow_value: Variant = landmarks.get("%s_elbow" % side, [])
	if not hand_value is Dictionary or not elbow_value is Array or elbow_value.size() != 3:
		return
	var position_value: Variant = hand_value.get("position", [])
	if not position_value is Array or position_value.size() != 3:
		return
	var hand_position := _map_human_position(position_value)
	var elbow_position := _map_human_position(elbow_value)
	ik.target = Transform3D(Basis.IDENTITY, hand_position)
	ik.magnet = elbow_position


func _map_human_position(value: Array) -> Vector3:
	# Mirror the XR user's depth into the front-facing broadcast avatar while
	# retaining screen-left/right and vertical motion.
	return _head_reference_position + Vector3(
		float(value[0]), float(value[1]), -float(value[2])
	)
