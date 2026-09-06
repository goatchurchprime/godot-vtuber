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

var status := "no avatar"
var _meshes: Array[MeshInstance3D] = []
var _shape_indices: Array[PackedInt32Array] = []
var _avatar_root: Node3D


func _ready() -> void:
	load_avatar(avatar_path)


func load_avatar(path: String) -> bool:
	if not ResourceLoader.exists(path):
		status = "avatar absent: %s" % path
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		status = "avatar load failed"
		return false
	var avatar := packed.instantiate()
	avatar.name = "Avatar"
	add_child(avatar)
	_avatar_root = avatar as Node3D
	_find_viseme_meshes(avatar)
	return not _meshes.is_empty()


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
	var rotation_value: Variant = frame.landmarks.get("head_rotation_degrees", [])
	if rotation_value is Array and rotation_value.size() == 3:
		_avatar_root.rotation_degrees = Vector3(
			float(rotation_value[0]), float(rotation_value[1]), float(rotation_value[2])
		)
	var shoulder_value: Variant = frame.landmarks.get("shoulder_center", [])
	if shoulder_value is Array and shoulder_value.size() >= 1:
		_avatar_root.position.x = clampf(float(shoulder_value[0]), -0.25, 0.25)
