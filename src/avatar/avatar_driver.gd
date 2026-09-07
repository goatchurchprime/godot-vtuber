@tool
class_name AvatarDriver
extends Node3D

## Loads an external avatar and maps OVR-compatible visemes to blend shapes.

const VISEMES := [
	"sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS",
	"nn", "RR", "aa", "E", "I", "O", "U",
]
const HAND_CALIBRATION_PATH := "user://hand-orientation.cfg"
# Measured with Oculus Touch grips held horizontally, palms down and fingers
# toward the broadcast camera. These are only fallbacks until the user saves a
# device-specific calibration.
const DEFAULT_RAW_CONTROLLER_REFERENCE := {
	"right": Quaternion(0.44170582, -0.23425385, -0.70148587, 0.50787669),
	"left": Quaternion(0.41214713, 0.32378277, 0.62650794, 0.57687718),
}

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
@export_range(-0.5, 0.5, 0.01) var hand_height_offset := 0.12
@export_range(-0.5, 0.5, 0.01) var hand_forward_offset := 0.15
@export var mirror_controller_assignment := true
@export var show_ik_debug := true
@export_range(0.05, 1.0, 0.01) var elbow_pole_distance := 0.20
@export_range(0.0, 1.0, 0.01) var chest_follow_strength := 0.28
@export_range(0.05, 1.0, 0.01) var chest_follow_time_sec := 0.25
@export_range(0.1, 2.0, 0.05) var head_translation_scale := 1.0
@export_range(0.05, 0.6, 0.01) var maximum_head_translation := 0.35

var status := "no avatar"
var _meshes: Array[MeshInstance3D] = []
var _shape_indices: Array[PackedInt32Array] = []
var _avatar_root: Node3D
var _skeleton: Skeleton3D
var _head_bone := -1
var _head_rest_rotation := Quaternion.IDENTITY
var _head_rest_position := Vector3.ZERO
var _chest_bone := -1
var _chest_rest_rotation := Quaternion.IDENTITY
var _chest_rest_position := Vector3.ZERO
var _chest_target_delta := Quaternion.IDENTITY
var _chest_displayed_delta := Quaternion.IDENTITY
var _target_visemes := PackedFloat32Array()
var _displayed_visemes := PackedFloat32Array()
var _head_reference_position := Vector3.ZERO
var _arm_ik: Dictionary = {}
var _arm_tip_bones: Dictionary = {}
var _arm_root_bones: Dictionary = {}
var _arm_desired_target: Dictionary = {}
var _arm_desired_pole: Dictionary = {}
var _arm_tip_rest_basis: Dictionary = {}
var _arm_neutral_target_basis: Dictionary = {}
var _arm_controller_reference: Dictionary = {}
var _save_hand_calibration_pending := false
var _arm_debug_hand: Dictionary = {}
var _arm_debug_elbow: Dictionary = {}
var _arm_debug_achieved: Dictionary = {}
var _arm_hand_axes: Dictionary = {}
var _arm_palm_normal_axes: Dictionary = {}
var _arm_debug_target_ray: Dictionary = {}
var _arm_debug_achieved_ray: Dictionary = {}
var _arm_debug_target_palm: Dictionary = {}
var _arm_debug_achieved_palm: Dictionary = {}
var _arm_debug_attachment: Dictionary = {}
var _finger_controls: Dictionary = {}


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
		_head_rest_position = _skeleton.get_bone_pose_position(_head_bone)
		_head_reference_position = _skeleton.get_bone_global_pose(_head_bone).origin
	for bone_name: StringName in [&"Chest", &"chest", &"UpperChest", &"upperChest"]:
		_chest_bone = _skeleton.find_bone(bone_name)
		if _chest_bone >= 0:
			_chest_rest_rotation = _skeleton.get_bone_pose_rotation(_chest_bone)
			_chest_rest_position = _skeleton.get_bone_pose_position(_chest_bone)
			break
	_configure_arm_ik()


func _configure_arm_ik() -> void:
	_arm_ik.clear()
	_arm_tip_bones.clear()
	_arm_root_bones.clear()
	_arm_desired_target.clear()
	_arm_desired_pole.clear()
	_arm_tip_rest_basis.clear()
	_arm_neutral_target_basis.clear()
	_arm_controller_reference.clear()
	_arm_debug_hand.clear()
	_arm_debug_elbow.clear()
	_arm_debug_achieved.clear()
	_arm_hand_axes.clear()
	_arm_palm_normal_axes.clear()
	_arm_debug_target_ray.clear()
	_arm_debug_achieved_ray.clear()
	_arm_debug_target_palm.clear()
	_arm_debug_achieved_palm.clear()
	_arm_debug_attachment.clear()
	_finger_controls.clear()
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
		ik.override_tip_basis = true
		ik.use_magnet = true
		ik.max_iterations = 12
		ik.min_distance = 0.002
		_skeleton.add_child(ik)
		_arm_ik[side] = ik
		var tip_bone := _skeleton.find_bone(tip_name)
		_arm_tip_bones[side] = tip_bone
		_arm_root_bones[side] = _skeleton.find_bone(root_name)
		_arm_tip_rest_basis[side] = _skeleton.get_bone_global_pose(tip_bone).basis
		_arm_hand_axes[side] = _find_hand_forward_axis(tip_bone)
		_arm_palm_normal_axes[side] = _find_palm_normal_axis(tip_bone, _arm_hand_axes[side])
		_arm_neutral_target_basis[side] = _forward_facing_hand_basis(side)
		_create_arm_debug(side)
		_configure_finger_controls(side, tip_bone)
	_load_hand_calibration()


func _configure_finger_controls(side: String, hand_bone: int) -> void:
	var controls: Array[Dictionary] = []
	var hand_pose := _skeleton.get_bone_global_pose(hand_bone)
	var finger_forward := hand_pose.basis * (_arm_hand_axes[side] as Vector3)
	var palm_normal := hand_pose.basis * (_arm_palm_normal_axes[side] as Vector3)
	var global_flex_axis := finger_forward.cross(-palm_normal).normalized()
	for bone_index in _skeleton.get_bone_count():
		var name := String(_skeleton.get_bone_name(bone_index)).to_lower()
		if not ("proximal" in name or "intermediate" in name or "distal" in name):
			continue
		if not name.begins_with(side):
			continue
		if "thumb" in name:
			continue
		var amount := 1.13 if "proximal" in name else (1.30 if "intermediate" in name else 0.87)
		controls.append({
			"bone": bone_index,
			"rest": _skeleton.get_bone_pose_rotation(bone_index),
			"axis": (_skeleton.get_bone_global_pose(bone_index).basis.inverse() * global_flex_axis).normalized(),
			"amount": amount,
			"trigger": "index" in name,
		})
	_finger_controls[side] = controls


func _apply_hand_controls(side: String, hand_value: Dictionary) -> void:
	var grip := clampf(float(hand_value.get("grip", 0.0)), 0.0, 1.0)
	var trigger := clampf(float(hand_value.get("trigger", 0.0)), 0.0, 1.0)
	for control: Dictionary in _finger_controls.get(side, []):
		var weight := trigger if bool(control.trigger) else grip
		var rotation := control.rest as Quaternion
		rotation *= Quaternion(control.axis as Vector3, -float(control.amount) * weight)
		_skeleton.set_bone_pose_rotation(int(control.bone), rotation)


func _create_arm_debug(side: String) -> void:
	var title := side.capitalize()
	var color := Color(0.1, 0.85, 1.0, 0.8) if side == "left" else Color(1.0, 0.2, 0.7, 0.8)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var hand_box := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.06, 0.22)
	hand_box.mesh = box
	hand_box.material_override = material
	hand_box.visible = show_ik_debug
	_skeleton.add_child(hand_box)
	_arm_debug_hand[side] = hand_box
	var elbow_marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.09
	elbow_marker.mesh = sphere
	elbow_marker.material_override = material
	elbow_marker.visible = show_ik_debug
	_skeleton.add_child(elbow_marker)
	_arm_debug_elbow[side] = elbow_marker
	var achieved_box := MeshInstance3D.new()
	var achieved_mesh := BoxMesh.new()
	achieved_mesh.size = Vector3(0.10, 0.04, 0.16)
	achieved_box.mesh = achieved_mesh
	var achieved_material := StandardMaterial3D.new()
	achieved_material.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
	achieved_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	achieved_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	achieved_box.material_override = achieved_material
	achieved_box.visible = show_ik_debug
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = StringName("%sHand" % title)
	_skeleton.add_child(attachment)
	attachment.add_child(achieved_box)
	_arm_debug_achieved[side] = achieved_box
	_arm_debug_attachment[side] = attachment
	var target_ray := _create_hand_ray(material)
	_skeleton.add_child(target_ray)
	_arm_debug_target_ray[side] = target_ray
	var achieved_ray := _create_hand_ray(achieved_material)
	attachment.add_child(achieved_ray)
	achieved_ray.transform = _axis_ray_transform(Transform3D.IDENTITY, _arm_hand_axes[side])
	_arm_debug_achieved_ray[side] = achieved_ray
	var palm_material := StandardMaterial3D.new()
	palm_material.albedo_color = Color(1.0, 0.9, 0.1, 0.9)
	palm_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var target_palm := _create_hand_ray(palm_material, 0.13)
	_skeleton.add_child(target_palm)
	_arm_debug_target_palm[side] = target_palm
	var achieved_palm := _create_hand_ray(achieved_material, 0.13)
	attachment.add_child(achieved_palm)
	achieved_palm.transform = _axis_ray_transform(Transform3D.IDENTITY, _arm_palm_normal_axes[side])
	_arm_debug_achieved_palm[side] = achieved_palm


func _create_hand_ray(material: Material, length := 0.22) -> Node3D:
	var marker := Node3D.new()
	marker.visible = show_ik_debug
	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.018, 0.018, length)
	shaft.mesh = shaft_mesh
	shaft.material_override = material
	shaft.position.z = -length * 0.5
	marker.add_child(shaft)
	var tip := MeshInstance3D.new()
	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.03
	tip_mesh.height = 0.06
	tip.mesh = tip_mesh
	tip.material_override = material
	tip.position.z = -length
	marker.add_child(tip)
	return marker


func _find_hand_forward_axis(hand_bone: int) -> Vector3:
	var hand_pose := _skeleton.get_bone_global_pose(hand_bone)
	for bone_index in _skeleton.get_bone_count():
		var bone_name := String(_skeleton.get_bone_name(bone_index)).to_lower()
		if "middleproximal" not in bone_name and "middle_proximal" not in bone_name:
			continue
		var ancestor := _skeleton.get_bone_parent(bone_index)
		while ancestor >= 0 and ancestor != hand_bone:
			ancestor = _skeleton.get_bone_parent(ancestor)
		if ancestor == hand_bone:
			var finger_direction := (
				_skeleton.get_bone_global_pose(bone_index).origin - hand_pose.origin
			).normalized()
			return (hand_pose.basis.inverse() * finger_direction).normalized()
	return Vector3(0.0, 0.0, -1.0)


func _find_palm_normal_axis(hand_bone: int, forward_axis: Vector3) -> Vector3:
	var hand_pose := _skeleton.get_bone_global_pose(hand_bone)
	var index_direction := Vector3.ZERO
	var little_direction := Vector3.ZERO
	for bone_index in _skeleton.get_bone_count():
		var bone_name := String(_skeleton.get_bone_name(bone_index)).to_lower()
		var is_index := "indexproximal" in bone_name or "index_proximal" in bone_name
		var is_little := "littleproximal" in bone_name or "little_proximal" in bone_name
		if not is_index and not is_little:
			continue
		var ancestor := _skeleton.get_bone_parent(bone_index)
		while ancestor >= 0 and ancestor != hand_bone:
			ancestor = _skeleton.get_bone_parent(ancestor)
		if ancestor != hand_bone:
			continue
		var local_direction := hand_pose.basis.inverse() * (
			_skeleton.get_bone_global_pose(bone_index).origin - hand_pose.origin
		).normalized()
		if is_index:
			index_direction = local_direction
		else:
			little_direction = local_direction
	var across := (index_direction - little_direction).normalized()
	var normal := forward_axis.cross(across).normalized()
	if (hand_pose.basis * normal).dot(Vector3.DOWN) < 0.0:
		normal = -normal
	return normal if not normal.is_zero_approx() else Vector3.UP


func _hand_ray_transform(hand_transform: Transform3D, side: String) -> Transform3D:
	var local_axis: Vector3 = _arm_hand_axes.get(side, Vector3(0.0, 0.0, -1.0))
	return _axis_ray_transform(hand_transform, local_axis)


func _axis_ray_transform(hand_transform: Transform3D, local_axis: Vector3) -> Transform3D:
	var up := Vector3.UP
	if absf(local_axis.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var axis_correction := Basis.looking_at(local_axis, up)
	return hand_transform * Transform3D(axis_correction, Vector3.ZERO)


func reset_hand_orientation_calibration() -> void:
	_arm_controller_reference.clear()
	for side: String in _arm_ik:
		_arm_neutral_target_basis[side] = _forward_facing_hand_basis(side)


func begin_hand_orientation_calibration() -> void:
	_save_hand_calibration_pending = true
	reset_hand_orientation_calibration()


func _load_hand_calibration() -> void:
	var config := ConfigFile.new()
	if config.load(HAND_CALIBRATION_PATH) == OK:
		for side: String in ["left", "right"]:
			var value: Variant = config.get_value("controller_reference", side, null)
			if value is Quaternion:
				_arm_controller_reference[side] = Basis(value as Quaternion)
	for side: String in ["left", "right"]:
		if not _arm_controller_reference.has(side):
			var raw_basis := Basis(DEFAULT_RAW_CONTROLLER_REFERENCE[side] as Quaternion)
			var mirror_basis := Basis.from_scale(Vector3(1.0, 1.0, -1.0))
			_arm_controller_reference[side] = mirror_basis * raw_basis * mirror_basis


func _save_hand_calibration_if_ready() -> void:
	if not _save_hand_calibration_pending \
			or not _arm_controller_reference.has("left") \
			or not _arm_controller_reference.has("right"):
		return
	var config := ConfigFile.new()
	for side: String in ["left", "right"]:
		config.set_value(
			"controller_reference", side,
			(_arm_controller_reference[side] as Basis).get_rotation_quaternion(),
		)
	var error := config.save(HAND_CALIBRATION_PATH)
	if error == OK:
		_save_hand_calibration_pending = false
		print("OPENXR_HAND_CALIBRATION_SAVED ", ProjectSettings.globalize_path(HAND_CALIBRATION_PATH))
	else:
		push_error("Could not save hand calibration: %s" % error_string(error))


func _forward_facing_hand_basis(side: String) -> Basis:
	var local_finger: Vector3 = _arm_hand_axes.get(side, Vector3(0.0, 0.0, -1.0))
	var local_palm: Vector3 = _arm_palm_normal_axes.get(side, Vector3.DOWN)
	var local_frame := Basis.looking_at(local_finger, local_palm)
	# The imported avatar faces the broadcast camera along scene +Z.
	var desired_frame := Basis.looking_at(Vector3.BACK, Vector3.DOWN)
	return (desired_frame * local_frame.inverse()).orthonormalized()


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
		tracked_euler.y = -tracked_euler.y
		head_rotation = Quaternion.from_euler(tracked_euler)
		has_head_rotation = true
	else:
		var rotation_value: Variant = frame.landmarks.get("head_rotation_degrees", [])
		if rotation_value is Array and rotation_value.size() == 3:
			head_rotation = Quaternion.from_euler(Vector3(
				-deg_to_rad(float(rotation_value[0])),
				-deg_to_rad(float(rotation_value[1])),
				deg_to_rad(float(rotation_value[2])),
			))
			has_head_rotation = true
	if has_head_rotation and _skeleton != null and _head_bone >= 0:
		_skeleton.set_bone_pose_rotation(_head_bone, _head_rest_rotation * head_rotation)
		var head_euler := head_rotation.get_euler()
		_chest_target_delta = Quaternion.from_euler(Vector3(
			head_euler.x * chest_follow_strength * 0.65,
			head_euler.y * chest_follow_strength,
			 head_euler.z * chest_follow_strength * 0.8,
		))
	var head_position_value: Variant = frame.landmarks.get("head_position", [])
	if _skeleton != null and _head_bone >= 0 \
			and head_position_value is Array and head_position_value.size() == 3:
		var displacement := Vector3(
			float(head_position_value[0]),
			float(head_position_value[1]),
			-float(head_position_value[2]),
		) * head_translation_scale
		displacement = displacement.limit_length(maximum_head_translation)
		_apply_seated_spine_pose(displacement)
	if mirror_controller_assignment:
		_apply_arm_pose(frame.landmarks, "right", "left")
		_apply_arm_pose(frame.landmarks, "left", "right")
	else:
		_apply_arm_pose(frame.landmarks, "left", "left")
		_apply_arm_pose(frame.landmarks, "right", "right")
	_save_hand_calibration_if_ready()
	var shoulder_value: Variant = frame.landmarks.get("shoulder_center", [])
	if shoulder_value is Array and shoulder_value.size() >= 1:
		_avatar_root.position.x = clampf(float(shoulder_value[0]), -0.25, 0.25)


func _apply_seated_spine_pose(displacement: Vector3) -> void:
	# Pose the torso before arm IK. No torso modifier is allowed to run after the
	# arms, preserving the invariant that a stationary controller has a
	# stationary final wrist even while the HMD moves.
	var chest_share := 0.22
	if _chest_bone >= 0:
		var chest_parent := _skeleton.get_bone_parent(_chest_bone)
		var chest_parent_basis := _skeleton.get_bone_global_pose(chest_parent).basis \
			if chest_parent >= 0 else Basis.IDENTITY
		_skeleton.set_bone_pose_position(
			_chest_bone,
			_chest_rest_position + chest_parent_basis.inverse() * displacement * chest_share,
		)
		_chest_displayed_delta = _chest_target_delta
		_skeleton.set_bone_pose_rotation(
			_chest_bone, _chest_rest_rotation * _chest_displayed_delta,
		)
	var head_parent := _skeleton.get_bone_parent(_head_bone)
	var head_parent_basis := _skeleton.get_bone_global_pose(head_parent).basis \
		if head_parent >= 0 else Basis.IDENTITY
	_skeleton.set_bone_pose_position(
		_head_bone,
		_head_rest_position + head_parent_basis.inverse() * displacement * (1.0 - chest_share),
	)


func _apply_arm_pose(landmarks: Dictionary, target_side: String, source_side: String) -> void:
	var ik := _arm_ik.get(target_side) as SkeletonIK3D
	if ik == null:
		return
	var hand_value: Variant = landmarks.get("%s_hand" % source_side, {})
	var elbow_value: Variant = landmarks.get("%s_elbow" % source_side, [])
	if not hand_value is Dictionary or not elbow_value is Array or elbow_value.size() != 3:
		return
	var position_value: Variant = hand_value.get("position", [])
	if not position_value is Array or position_value.size() != 3:
		return
	_apply_hand_controls(target_side, hand_value)
	var hand_position := _map_human_position(position_value)
	var elbow_position := _map_human_position(elbow_value)
	var root_bone := int(_arm_root_bones.get(target_side, -1))
	var shoulder_position := _skeleton.get_bone_global_pose(root_bone).origin \
		if root_bone >= 0 else _head_reference_position
	var pole_position := _elbow_pole_target(shoulder_position, hand_position, elbow_position, target_side)
	var target_basis: Basis = _arm_neutral_target_basis.get(target_side, Basis.IDENTITY)
	var rotation_value: Variant = hand_value.get("rotation_quaternion", [])
	if rotation_value is Array and rotation_value.size() == 4:
		var tracked_basis := Basis(Quaternion(
			float(rotation_value[0]), float(rotation_value[1]),
			float(rotation_value[2]), float(rotation_value[3])
		).normalized())
		var mirror_basis := Basis.from_scale(Vector3(1.0, 1.0, -1.0))
		var controller_basis := mirror_basis * tracked_basis * mirror_basis
		if not _arm_controller_reference.has(target_side):
			_arm_controller_reference[target_side] = controller_basis
		var controller_reference: Basis = _arm_controller_reference[target_side]
		var controller_delta := controller_basis * controller_reference.inverse()
		target_basis = controller_delta * target_basis
	var desired_target := Transform3D(target_basis.orthonormalized(), hand_position)
	_arm_desired_target[target_side] = desired_target
	_arm_desired_pole[target_side] = pole_position
	ik.target = desired_target
	ik.magnet = pole_position
	var hand_debug := _arm_debug_hand.get(target_side) as MeshInstance3D
	if hand_debug != null:
		hand_debug.transform = desired_target
	var target_ray := _arm_debug_target_ray.get(target_side) as Node3D
	if target_ray != null:
		target_ray.transform = _hand_ray_transform(desired_target, target_side)
	var target_palm := _arm_debug_target_palm.get(target_side) as Node3D
	if target_palm != null:
		target_palm.transform = _axis_ray_transform(desired_target, _arm_palm_normal_axes[target_side])
	var elbow_debug := _arm_debug_elbow.get(target_side) as MeshInstance3D
	if elbow_debug != null:
		elbow_debug.position = pole_position
	if not ik.is_running():
		ik.start()


func _elbow_pole_target(shoulder: Vector3, _wrist: Vector3, elbow: Vector3, side: String) -> Vector3:
	# The canonical human solver has already chosen the anatomical bend plane.
	# Extend that direction into an IK magnet without deriving it from HMD pose.
	var direction := (elbow - shoulder).normalized()
	if direction.is_zero_approx():
		var outward := -1.0 if side == "right" else 1.0
		direction = Vector3(outward, -1.0, 0.15).normalized()
	return shoulder + direction * 0.48


func _map_human_position(value: Array) -> Vector3:
	# Preserve screen-space X in mirror mode. The opposite anatomical arm is
	# selected above so the chain does not cross through the avatar's torso.
	return _head_reference_position + Vector3(
		float(value[0]),
		float(value[1]) + hand_height_offset,
		-float(value[2]) + hand_forward_offset
	)


func get_ik_diagnostic() -> Dictionary:
	var result := {}
	for side: String in _arm_ik:
		var ik := _arm_ik[side] as SkeletonIK3D
		var attachment := _arm_debug_attachment.get(side) as BoneAttachment3D
		result[side] = {
			"running": ik != null and ik.is_running(),
			"target": _transform_array(_arm_desired_target.get(side, ik.target)) if ik != null else [],
			"achieved": _transform_array(attachment.transform) if attachment != null else [],
			"finger_axis": _vector_array(_arm_hand_axes.get(side, Vector3.ZERO)),
			"palm_normal": _vector_array(_arm_palm_normal_axes.get(side, Vector3.ZERO)),
		}
	return result


func _transform_array(value: Transform3D) -> Array:
	var quaternion := value.basis.get_rotation_quaternion()
	return [value.origin.x, value.origin.y, value.origin.z, quaternion.x, quaternion.y, quaternion.z, quaternion.w]


func _vector_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
