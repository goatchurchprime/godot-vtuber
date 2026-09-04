class_name PoseFrame
extends RefCounted

## Backend-neutral observations from a timestamped webcam frame.

var timestamp_usec: int
var landmarks: Dictionary
var confidence: Dictionary
var face_blend_shapes: Dictionary


func _init(p_timestamp_usec: int = 0) -> void:
	timestamp_usec = p_timestamp_usec

