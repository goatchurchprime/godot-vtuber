class_name VisemeFrame
extends RefCounted

## Viseme weights associated with a position on the audio sample clock.

var sample_position: int
var weights: PackedFloat32Array


func _init(
	p_sample_position: int = 0,
	p_weights: PackedFloat32Array = PackedFloat32Array(),
) -> void:
	sample_position = p_sample_position
	weights = p_weights

