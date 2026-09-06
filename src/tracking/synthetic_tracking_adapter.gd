class_name SyntheticTrackingAdapter
extends "res://src/tracking/tracking_adapter.gd"

const PoseFrameScript := preload("res://src/tracking/pose_frame.gd")

## Dependency-free acceptance source using the exact canonical adapter output.

var _elapsed := 0.0
var _emit_elapsed := 0.0


func start() -> bool:
	status = "synthetic 30 fps"
	return true


func _process(delta: float) -> void:
	_elapsed += delta
	_emit_elapsed += delta
	if _emit_elapsed < 1.0 / 30.0:
		return
	_emit_elapsed = 0.0
	var frame = PoseFrameScript.new(Time.get_ticks_usec())
	frame.landmarks = {
		"head_rotation_degrees": [4.0 * sin(_elapsed * 0.7), 12.0 * sin(_elapsed * 0.45), 3.0 * sin(_elapsed)],
		"shoulder_center": [0.04 * sin(_elapsed * 0.4), 0.0, 0.0],
	}
	frame.confidence = {"face": 1.0, "pose": 1.0}
	received_frames += 1
	pose_received.emit(frame)
