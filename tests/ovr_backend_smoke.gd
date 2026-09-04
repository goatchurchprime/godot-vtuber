extends SceneTree

## Windows-only smoke test for the externally supplied OVRLipSync runtime.


func _init() -> void:
	assert(ClassDB.class_exists("OvrLipSyncBackend"), "OvrLipSyncBackend is missing")
	var backend: Object = ClassDB.instantiate("OvrLipSyncBackend")
	assert(backend != null and bool(backend.call("is_available")), "OVRLipSync was not compiled in")
	var library_dir := ProjectSettings.globalize_path("res://addons/twovoip/libs")
	var error: int = backend.call("configure", 48000, 960, library_dir, 2, true)
	assert(error == OK, str(backend.call("get_status")))
	var pcm := PackedFloat32Array()
	pcm.resize(960)
	for index in pcm.size():
		pcm[index] = sin(TAU * 220.0 * index / 48000.0) * 0.1
	assert(bool(backend.call("push_pcm", pcm)), str(backend.call("get_status")))
	var levels: PackedFloat32Array = backend.call("get_levels")
	assert(levels.size() == 15, "expected 15 OVR viseme weights")
	for value in levels:
		assert(is_finite(value), "OVR returned a non-finite weight")
	print("OVR_SMOKE_OK status=", backend.call("get_status"), " levels=", levels)
	quit()
