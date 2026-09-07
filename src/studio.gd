@tool
extends Node3D


func _ready() -> void:
	var preview := get_node_or_null("EditorLightingStandIn") as Node3D
	if preview != null:
		preview.visible = Engine.is_editor_hint()
