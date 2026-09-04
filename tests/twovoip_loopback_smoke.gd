extends SceneTree

const EXTENSION := "res://addons/twovoip/twovoip.gdextension"


func _init() -> void:
	if not ClassDB.class_exists("TwovoipOpusEncoder"):
		var load_error: int = GDExtensionManager.load_extension(EXTENSION)
		assert(load_error == OK, error_string(load_error))
	var encoder: Object = ClassDB.instantiate("TwovoipOpusEncoder")
	assert(encoder != null)
	assert(encoder.has_method("get_current_chunk"))
	var configure_error: int = encoder.call("create_sampler", 48000, 48000, 1, 0, 0, 960)
	assert(configure_error == OK, error_string(configure_error))
	var input := PackedVector2Array()
	input.resize(960)
	assert(encoder.call("process_chunk", input) == 960)
	var output: PackedVector2Array = encoder.call("get_current_chunk")
	var analysis: PackedFloat32Array = encoder.call("get_current_chunk_16khz")
	assert(output.size() == 960)
	assert(analysis.size() == 320)
	print("TwoVoIP loopback boundary: 960 conditioned frames, 320 analysis samples")
	quit()
