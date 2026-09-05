extends SceneTree

## Exports all Experiment 008 WAVs while retaining one loaded ONNX session.

const VisemeStreamScript := preload("res://src/visemes/viseme_stream.gd")
const INPUT_DIR := "res://experiments/008-opus-robustness/private/codec"
const OUTPUT_DIR := "res://experiments/008-opus-robustness/private/onnx"
const SAMPLE_RATE := 16000
const FRAME_SIZE := 160


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("MelFrontend"):
		assert(GDExtensionManager.load_extension("res://addons/vizemes_mel/vizemes_mel.gdextension") == OK)
	if not ClassDB.class_exists("OnnxLoader"):
		assert(GDExtensionManager.load_extension("res://addons/onnx_loader/onnx_loader.gdextension") == OK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var backend := VisemeStreamScript.new()
	root.add_child(backend)
	await process_frame
	assert(backend.is_ready(), backend.get_status())
	var files := DirAccess.get_files_at(INPUT_DIR)
	files.sort()
	var completed := 0
	for filename in files:
		if not filename.ends_with(".wav") or not ("_original.wav" in filename or "_decoded.wav" in filename):
			continue
		# Reset only streaming feature/history state; retain the loaded model session.
		backend._mel.call("begin_stream")
		backend._history.clear()
		backend.levels.fill(0.0)
		backend.pcm_samples = 0
		backend.mel_contexts = 0
		backend.onnx_runs = 0
		backend.status = "ready"
		var source_path := INPUT_DIR.path_join(filename)
		var stream := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(source_path))
		assert(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == SAMPLE_RATE and not stream.stereo)
		var bytes := stream.data
		var frame_count := int(bytes.size() / 2 / FRAME_SIZE)
		var frames: Array = []
		for frame_index in frame_count:
			var pcm := PackedFloat32Array()
			pcm.resize(FRAME_SIZE)
			var byte_offset := frame_index * FRAME_SIZE * 2
			for sample_index in FRAME_SIZE:
				pcm[sample_index] = bytes.decode_s16(byte_offset + sample_index * 2) / 32768.0
			var produced := backend.push_pcm(pcm)
			frames.append({"input_start_s": frame_index * 0.01, "input_end_s": (frame_index + 1) * 0.01,
				"produced": produced, "weights": Array(backend.levels)})
		var result := {"schema":"vizemes_onnx_trace_v1", "backend":"MelFrontend + godot-onnx-loader",
			"source_wav":source_path, "sample_rate":SAMPLE_RATE, "frame_size":FRAME_SIZE,
			"frame_duration_s":0.01, "weight_state":"raw softmax; live causal Mel normalization and context",
			"runtime_status":backend.get_status(), "frames":frames}
		var output_name := filename.trim_suffix(".wav") + "_onnx.json"
		var output := FileAccess.open(OUTPUT_DIR.path_join(output_name), FileAccess.WRITE)
		assert(output != null)
		output.store_string(JSON.stringify(result, "  "))
		output.close()
		completed += 1
		print("ONNX_CODEC_TRACE ", completed, "/15 ", filename)
	print("ONNX_CODEC_BATCH_OK files=", completed)
	quit()
