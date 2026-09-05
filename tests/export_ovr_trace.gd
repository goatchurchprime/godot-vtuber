extends SceneTree

## Exports raw OVRLipSync weights at their real streaming cadence for timeline comparison.

const VISEMES := [
	"sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS",
	"nn", "RR", "aa", "E", "ih", "oh", "ou",
]
const SAMPLE_RATE := 16000
const DEFAULT_FIXTURE := "res://fixtures/benchmark_speech.wav"
const DEFAULT_OUTPUT := "res://fixtures/ovr_trace.json"
const WARMUP_SECONDS := 0.5


func _init() -> void:
	call_deferred("_run")


func _option(name: String, fallback: String) -> String:
	var prefix := "--%s=" % name
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return fallback


func _configured_backend(frame_size: int, library_dir: String, smoothing: int) -> Object:
	var backend: Object = ClassDB.instantiate("OvrLipSyncBackend")
	assert(backend != null and bool(backend.call("is_available")), "OVRLipSync was not compiled in")
	var error: int = backend.call("configure", SAMPLE_RATE, frame_size, library_dir, 2, true)
	assert(error == OK, str(backend.call("get_status")))
	if smoothing >= 1:
		error = backend.call("set_smoothing", smoothing)
		assert(error == OK, str(backend.call("get_status")))
	return backend


func _run() -> void:
	if not ClassDB.class_exists("OvrLipSyncBackend"):
		var load_error := GDExtensionManager.load_extension("res://addons/twovoip/twovoip.gdextension")
		assert(load_error == OK, "could not load the TwoVoIP extension")
	var frame_ms := int(_option("frame-ms", "20"))
	assert(frame_ms == 10 or frame_ms == 20, "frame-ms must be 10 or 20")
	var frame_size := int(SAMPLE_RATE * frame_ms / 1000)
	var fixture_path := _option("fixture", DEFAULT_FIXTURE)
	var output_path := _option("output", DEFAULT_OUTPUT)
	var paced := _option("paced", "true") == "true"
	var smoothing := int(_option("smoothing", "-1"))
	var reset_after_silence_ms := int(_option("reset-after-silence-ms", "0"))
	var library_dir := ProjectSettings.globalize_path("res://addons/twovoip/libs")
	var backend := _configured_backend(frame_size, library_dir, smoothing)
	# Read the source WAV itself. A normal Godot import may QOA-compress it, in
	# which case AudioStreamWAV.data contains compressed bytes rather than PCM.
	var stream := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(fixture_path))
	assert(
		stream != null
		and stream.format == AudioStreamWAV.FORMAT_16_BITS
		and stream.mix_rate == SAMPLE_RATE
		and not stream.stereo,
		"fixture must be 16-bit, 16 kHz mono PCM WAV"
	)
	var sample_bytes := stream.data
	var frame_count := int(sample_bytes.size() / 2 / frame_size)
	assert(frame_count > 0, "fixture contains no complete frames")
	var trace_frames: Array = []
	var timing_usec: Array[int] = []
	var warmup_frames := ceili(WARMUP_SECONDS * 1000.0 / frame_ms)
	var silent_frames := 0
	var reset_during_current_silence := false
	for frame_index in frame_count:
		var pcm := PackedFloat32Array()
		pcm.resize(frame_size)
		var byte_offset := frame_index * frame_size * 2
		for sample_index in frame_size:
			pcm[sample_index] = sample_bytes.decode_s16(byte_offset + sample_index * 2) / 32768.0
		var frame_is_silent := true
		for sample in pcm:
			if sample != 0.0:
				frame_is_silent = false
				break
		if frame_is_silent:
			silent_frames += 1
		else:
			silent_frames = 0
			reset_during_current_silence = false
		var context_reset := false
		if (
			reset_after_silence_ms > 0
			and not reset_during_current_silence
			and silent_frames * frame_ms >= reset_after_silence_ms
		):
			var reset_error: int = backend.call("configure", SAMPLE_RATE, frame_size, library_dir, 2, true)
			assert(reset_error == OK, str(backend.call("get_status")))
			if smoothing >= 1:
				reset_error = backend.call("set_smoothing", smoothing)
				assert(reset_error == OK, str(backend.call("get_status")))
			reset_during_current_silence = true
			context_reset = true
		var started_usec := Time.get_ticks_usec()
		assert(bool(backend.call("push_pcm", pcm)), str(backend.call("get_status")))
		var elapsed_usec := int(Time.get_ticks_usec() - started_usec)
		if frame_index >= warmup_frames:
			timing_usec.append(elapsed_usec)
		trace_frames.append({
			"input_start_s": frame_index * frame_ms / 1000.0,
			"input_end_s": (frame_index + 1) * frame_ms / 1000.0,
			"reported_frame_delay_ms": int(backend.call("get_frame_delay_ms")),
			"context_reset": context_reset,
			"weights": Array(backend.call("get_levels")),
		})
		if paced:
			await create_timer(frame_ms / 1000.0).timeout
	assert(not timing_usec.is_empty(), "fixture is shorter than the timing warmup")
	timing_usec.sort()
	var timing_total := 0
	for timing in timing_usec:
		timing_total += timing
	var p95_index := mini(timing_usec.size() - 1, ceili(timing_usec.size() * 0.95) - 1)
	var result := {
		"schema": "ovrlipsync_trace_v1",
		"backend": "OVRLipSync 1.61 EnhancedWithLaughter",
		"source_wav": fixture_path,
		"sample_rate": SAMPLE_RATE,
		"frame_size": frame_size,
		"frame_duration_s": frame_ms / 1000.0,
		"viseme_names": VISEMES,
		"weight_state": "SDK output; persistent context",
		"smoothing": "sdk_default" if smoothing < 1 else smoothing,
		"paced": paced,
		"reset_after_silence_ms": reset_after_silence_ms,
		"timing_warmup_s": WARMUP_SECONDS,
		"timing": {
			"frames": timing_usec.size(),
			"average_ms": float(timing_total) / timing_usec.size() / 1000.0,
			"p95_ms": timing_usec[p95_index] / 1000.0,
			"maximum_ms": timing_usec[-1] / 1000.0,
		},
		"frames": trace_frames,
	}
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	assert(output != null, "could not open trace output")
	output.store_string(JSON.stringify(result, "  "))
	output.close()
	print("OVR_TRACE_OK output=", output_path, " frames=", trace_frames.size(), " timing=", result["timing"])
	quit()
