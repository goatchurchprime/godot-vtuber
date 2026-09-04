class_name AvatarDriver
extends Node3D

## Loads an external avatar and maps OVR-compatible visemes to blend shapes.

const VISEMES := [
	"sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS",
	"nn", "RR", "aa", "E", "I", "O", "U",
]

@export_file("*.glb", "*.gltf") var avatar_path := "res://avatars/readyplayerme_avatar.glb"

var status := "no avatar"
var _meshes: Array[MeshInstance3D] = []
var _shape_indices: Array[PackedInt32Array] = []


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
	_find_viseme_meshes(avatar)
	return not _meshes.is_empty()


func _find_viseme_meshes(root: Node) -> void:
	_meshes.clear()
	_shape_indices.clear()
	_collect_meshes(root)
	var mapped := 0
	for mesh in _meshes:
		var indices := PackedInt32Array()
		for viseme in VISEMES:
			var index := mesh.find_blend_shape_by_name("viseme_%s" % viseme)
			indices.append(index)
			if index >= 0:
				mapped += 1
		_shape_indices.append(indices)
	status = "avatar ready: %d meshes, %d mappings" % [_meshes.size(), mapped]


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := node as MeshInstance3D
		for viseme in VISEMES:
			if mesh.find_blend_shape_by_name("viseme_%s" % viseme) >= 0:
				_meshes.append(mesh)
				break
	for child in node.get_children():
		_collect_meshes(child)


func set_visemes(weights: PackedFloat32Array) -> void:
	for mesh_index in _meshes.size():
		var mesh := _meshes[mesh_index]
		var indices := _shape_indices[mesh_index]
		for viseme_index in mini(VISEMES.size(), weights.size()):
			var shape_index := indices[viseme_index]
			if shape_index >= 0:
				mesh.set_blend_shape_value(shape_index, clampf(weights[viseme_index], 0.0, 1.0))
