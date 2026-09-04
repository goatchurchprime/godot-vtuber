extends SceneTree

const EXTENSIONS := [
	["res://addons/vizemes_mel/vizemes_mel.gdextension", "MelFrontend"],
	["res://addons/onnx_loader/onnx_loader.gdextension", "OnnxLoader"],
]
const VisemeStreamScript := preload("res://src/visemes/viseme_stream.gd")
const AvatarDriverScript := preload("res://src/avatar/avatar_driver.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for extension in EXTENSIONS:
		if not ClassDB.class_exists(extension[1]):
			var error: int = GDExtensionManager.load_extension(extension[0])
			assert(error == OK, "%s: %s" % [extension[0], error_string(error)])
	var stream: Node = VisemeStreamScript.new()
	root.add_child(stream)
	await process_frame
	assert(stream.is_ready(), stream.status)
	var phase := 0.0
	for packet in 30:
		var pcm := PackedFloat32Array()
		pcm.resize(320)
		var frequency := 180.0 + packet * 7.0
		for sample in pcm.size():
			pcm[sample] = sin(phase) * 0.15
			phase += TAU * frequency / 16000.0
		stream.push_pcm(pcm)
	assert(stream.onnx_runs >= 29, "expected a run after Mel warmup, got %d" % stream.onnx_runs)
	var avatar: Node3D = AvatarDriverScript.new()
	root.add_child(avatar)
	await process_frame
	assert(avatar.status.begins_with("avatar ready"), avatar.status)
	avatar.set_visemes(stream.levels)
	print("%s | %s" % [stream.get_status(), avatar.status])
	quit()
