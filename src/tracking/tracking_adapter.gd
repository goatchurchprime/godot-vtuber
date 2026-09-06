class_name TrackingAdapter
extends Node

## Replaceable boundary for timestamped canonical face/head/body observations.

signal pose_received(frame)

var status := "not started"
var received_frames := 0
var rejected_frames := 0


func start() -> bool:
	status = "ready"
	return true


func stop() -> void:
	status = "stopped"


func get_status() -> String:
	return "%s | received %d | rejected %d" % [status, received_frames, rejected_frames]
