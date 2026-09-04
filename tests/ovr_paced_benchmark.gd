extends SceneTree

## Runs OVRLipSync at its real 20 ms cadence against a local 16 kHz mono WAV.

const FIXTURE := "res://fixtures/benchmark_speech.wav"
const SAMPLE_RATE := 16000
const FRAME_SIZE := 320
const WARMUP_FRAMES := 25


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("OvrLipSyncBackend"):
		var load_error := GDExtensionManager.load_extension("res://addons/twovoip/twovoip.gdextension")
		assert(load_error == OK, "could not load the TwoVoIP extension")
	var backend: Object = ClassDB.instantiate("OvrLipSyncBackend")
	var library_dir := ProjectSettings.globalize_path("res://addons/twovoip/libs")
	var error: int = backend.call("configure", SAMPLE_RATE, FRAME_SIZE, library_dir, 2, true)
	assert(error == OK, str(backend.call("get_status")))
	var stream := load(FIXTURE) as AudioStreamWAV
	assert(stream != null and stream.mix_rate == SAMPLE_RATE and not stream.stereo, "fixture must be 16 kHz mono WAV")
	var bytes := stream.data
	var frame_count := bytes.size() / 2 / FRAME_SIZE
	assert(frame_count > WARMUP_FRAMES, "fixture is too short")
	var timings_usec: Array[int] = []
	for frame_index in frame_count:
		var pcm := PackedFloat32Array()
		pcm.resize(FRAME_SIZE)
		var byte_offset := frame_index * FRAME_SIZE * 2
		for sample_index in FRAME_SIZE:
			pcm[sample_index] = bytes.decode_s16(byte_offset + sample_index * 2) / 32768.0
		var started_usec := Time.get_ticks_usec()
		assert(bool(backend.call("push_pcm", pcm)), str(backend.call("get_status")))
		var elapsed_usec := int(Time.get_ticks_usec() - started_usec)
		if frame_index >= WARMUP_FRAMES:
			timings_usec.append(elapsed_usec)
		await create_timer(0.02).timeout
	timings_usec.sort()
	var total_usec := 0
	for timing in timings_usec:
		total_usec += timing
	var p95_index := mini(timings_usec.size() - 1, ceili(timings_usec.size() * 0.95) - 1)
	print("OVR_PACED_RESULT frames=", timings_usec.size(),
		" avg_ms=", float(total_usec) / timings_usec.size() / 1000.0,
		" p95_ms=", timings_usec[p95_index] / 1000.0,
		" max_ms=", timings_usec[-1] / 1000.0)
	quit()
