extends SceneTree

## Exports live MEL/ONNX viseme weights from a raw WAV at 10 ms cadence.

const VisemeStreamScript := preload("res://src/visemes/viseme_stream.gd")
const VISEMES := [
	"sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS",
	"nn", "RR", "aa", "E", "ih", "oh", "ou",
]
const SAMPLE_RATE := 16000
const FRAME_SIZE := 160
const FRAME_SECONDS := 0.01
const DEFAULT_FIXTURE := "res://fixtures/ovr_temporal_probe.wav"
const DEFAULT_OUTPUT := "res://fixtures/onnx_temporal_probe_trace_10ms.json"


func _init() -> void:
	call_deferred("_run")


func _option(name: String, fallback: String) -> String:
	var prefix := "--%s=" % name
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


func _run() -> void:
	if not ClassDB.class_exists("MelFrontend"):
		var mel_error := GDExtensionManager.load_extension("res://addons/vizemes_mel/vizemes_mel.gdextension")
		assert(mel_error == OK, "could not load MelFrontend")
	if not ClassDB.class_exists("OnnxLoader"):
		var onnx_error := GDExtensionManager.load_extension("res://addons/onnx_loader/onnx_loader.gdextension")
		assert(onnx_error == OK, "could not load OnnxLoader")
	var fixture_path := _option("fixture", DEFAULT_FIXTURE)
	var output_path := _option("output", DEFAULT_OUTPUT)
	var paced := _option("paced", "false") == "true"
	var stream := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(fixture_path))
	assert(
		stream != null
		and stream.format == AudioStreamWAV.FORMAT_16_BITS
		and stream.mix_rate == SAMPLE_RATE
		and not stream.stereo,
		"fixture must be 16-bit, 16 kHz mono PCM WAV"
	)
	var backend := VisemeStreamScript.new()
	root.add_child(backend)
	await process_frame
	assert(backend.is_ready(), backend.get_status())
	var sample_bytes := stream.data
	var frame_count := int(sample_bytes.size() / 2 / FRAME_SIZE)
	var trace_frames: Array = []
	var timing_usec: Array[int] = []
	for frame_index in frame_count:
		var pcm := PackedFloat32Array()
		pcm.resize(FRAME_SIZE)
		var byte_offset := frame_index * FRAME_SIZE * 2
		for sample_index in FRAME_SIZE:
			pcm[sample_index] = sample_bytes.decode_s16(byte_offset + sample_index * 2) / 32768.0
		var started_usec := Time.get_ticks_usec()
		var produced: bool = backend.push_pcm(pcm)
		var elapsed_usec := int(Time.get_ticks_usec() - started_usec)
		if produced:
			timing_usec.append(elapsed_usec)
		trace_frames.append({
			"input_start_s": frame_index * FRAME_SECONDS,
			"input_end_s": (frame_index + 1) * FRAME_SECONDS,
			"produced": produced,
			"weights": Array(backend.levels),
		})
		if paced:
			await create_timer(FRAME_SECONDS).timeout
	assert(not timing_usec.is_empty(), "ONNX produced no frames")
	timing_usec.sort()
	var timing_total := 0
	for timing in timing_usec:
		timing_total += timing
	var p95_index := mini(timing_usec.size() - 1, ceili(timing_usec.size() * 0.95) - 1)
	var result := {
		"schema": "vizemes_onnx_trace_v1",
		"backend": "MelFrontend + godot-onnx-loader",
		"source_wav": fixture_path,
		"sample_rate": SAMPLE_RATE,
		"frame_size": FRAME_SIZE,
		"frame_duration_s": FRAME_SECONDS,
		"viseme_names": VISEMES,
		"weight_state": "raw softmax; live causal Mel normalization and context",
		"paced": paced,
		"timing": {
			"frames": timing_usec.size(),
			"average_ms": float(timing_total) / timing_usec.size() / 1000.0,
			"p95_ms": timing_usec[p95_index] / 1000.0,
			"maximum_ms": timing_usec[-1] / 1000.0,
		},
		"runtime_status": backend.get_status(),
		"frames": trace_frames,
	}
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	assert(output != null, "could not open trace output")
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	print("ONNX_TRACE_OK output=", output_path, " frames=", trace_frames.size(), " timing=", result["timing"])
	quit()
