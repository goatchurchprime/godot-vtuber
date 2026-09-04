class_name OvrLipSyncStream
extends Node

## Optional Windows OVRLipSync adapter. The native SDK remains outside this repository.

const SAMPLE_RATE := 48000
const FRAME_SIZE := 960

var levels := PackedFloat32Array()
var status := "not started"
var _backend: Object


func _ready() -> void:
	levels.resize(15)
	levels[0] = 1.0
	if not ClassDB.class_exists("OvrLipSyncBackend"):
		status = "native OVRLipSync backend absent"
		return
	_backend = ClassDB.instantiate("OvrLipSyncBackend")
	if _backend == null or not bool(_backend.call("is_available")):
		status = "TwoVoIP was built without OVRLipSync"
		return
	var error: int = _backend.call("configure", SAMPLE_RATE, FRAME_SIZE, 2, true)
	if error != OK:
		status = "configuration failed: %s" % _backend.call("get_status")
		return
	status = "ready"


func is_ready() -> bool:
	return _backend != null and bool(_backend.call("is_ready"))


func push_audio(conditioned_48khz: PackedVector2Array, _analysis_16khz: PackedFloat32Array) -> bool:
	if not is_ready():
		return false
	if not bool(_backend.call("push_stereo_pcm", conditioned_48khz)):
		status = str(_backend.call("get_status"))
		return false
	levels = _backend.call("get_levels")
	status = "running"
	return true


func get_status() -> String:
	if _backend == null:
		return status
	return "%s | runs %d | %.3f ms avg %.3f max | delay %d ms" % [
		status,
		int(_backend.call("get_run_count")),
		float(_backend.call("get_average_run_ms")),
		float(_backend.call("get_maximum_run_ms")),
		int(_backend.call("get_frame_delay_ms")),
	]
