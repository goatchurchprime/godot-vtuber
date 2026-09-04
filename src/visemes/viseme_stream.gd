class_name VisemeStream
extends Node

## Live 16 kHz PCM to viseme bridge. The ONNX metadata is its runtime contract.

@export_file("*.onnx") var model_path := "res://models/viseme.onnx"

var levels := PackedFloat32Array()
var pcm_samples := 0
var mel_contexts := 0
var onnx_runs := 0
var status := "not started"

var _mel: Object
var _loader: Object
var _history := PackedFloat32Array()
var _history_frames := 1
var _n_mels := 0
var _onnx_usec := 0
var _onnx_max_usec := 0


func _ready() -> void:
	levels.resize(15)
	_mel = ClassDB.instantiate("MelFrontend")
	_loader = ClassDB.instantiate("OnnxLoader")
	if _mel == null or _loader == null:
		status = "missing MelFrontend or OnnxLoader"
		return
	if not _loader.call("load_model", model_path):
		status = "model load failed: %s" % model_path
		return
	var metadata_value: Variant = _loader.call("get_metadata_value", "vizemes_meta_json")
	var metadata: Variant = JSON.parse_string(str(metadata_value))
	if typeof(metadata) != TYPE_DICTIONARY:
		status = "model has no vizemes_meta_json"
		return
	var contract := metadata as Dictionary
	var audio: Dictionary = contract.get("audio", {})
	_n_mels = int(contract.get("n_mels", audio.get("n_mels", 0)))
	_history_frames = int(contract.get("receptive_history_hops", 1))
	var context_frames := int(contract.get("context_frames", 1))
	var sample_rate := int(audio.get("sample_rate", 0))
	var hop := int(audio.get("hop_length_samples", 0))
	var window := int(audio.get("window_length_samples", 0))
	var n_fft := int(audio.get("n_fft", 0))
	var fmin := float(audio.get("fmin", 0.0))
	var fmax := float(audio.get("fmax", 0.0))
	var n_visemes := int(contract.get("n_visemes", 15))
	var input_features := int(contract.get("input_features", context_frames * _n_mels))
	if sample_rate != 16000 or _n_mels <= 0:
		status = "unsupported model audio contract"
		return
	var configured: bool = _mel.call(
		"configure",
		context_frames,
		_n_mels,
		sample_rate,
		hop,
		window,
		n_fft,
		fmin,
		fmax,
		n_visemes,
		input_features,
	)
	if not configured:
		status = "Mel configuration failed"
		return
	levels.resize(n_visemes)
	_mel.call("begin_stream")
	status = "ready"


func is_ready() -> bool:
	return status == "ready" or status == "running"


func push_pcm(pcm_16khz: PackedFloat32Array) -> bool:
	if not is_ready() or pcm_16khz.is_empty():
		return false
	pcm_samples += pcm_16khz.size()
	_mel.call("push_pcm", pcm_16khz)
	var received_context := false
	while int(_mel.call("count_available_contexts")) > 0:
		var frame: PackedFloat32Array = _mel.call("get_next_context")
		if frame.size() != _n_mels:
			continue
		mel_contexts += 1
		received_context = true
		_history.append_array(frame)
		var maximum_values := _history_frames * _n_mels
		if _history.size() > maximum_values:
			_history = _history.slice(_history.size() - maximum_values)
	if not received_context:
		return false
	return _predict_latest()


func _predict_latest() -> bool:
	var frame_count := _history.size() / _n_mels
	if frame_count <= 0:
		return false
	var started_usec := Time.get_ticks_usec()
	var logits: PackedFloat32Array = _loader.call(
		"predict_shaped",
		_history,
		PackedInt32Array([1, frame_count, _n_mels]),
	)
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	_onnx_usec += elapsed_usec
	_onnx_max_usec = maxi(_onnx_max_usec, elapsed_usec)
	if logits.size() < levels.size():
		status = "ONNX returned no output"
		return false
	var row_start := logits.size() - levels.size()
	var maximum := logits[row_start]
	for i in range(1, levels.size()):
		maximum = maxf(maximum, logits[row_start + i])
	var total := 0.0
	for i in levels.size():
		levels[i] = exp(logits[row_start + i] - maximum)
		total += levels[i]
	if total > 0.0:
		for i in levels.size():
			levels[i] /= total
	onnx_runs += 1
	status = "running"
	return true


func get_status() -> String:
	var average_ms := 0.0 if onnx_runs == 0 else float(_onnx_usec) / onnx_runs / 1000.0
	return "%s | pcm %d | mel %d | onnx %d | %.2f ms avg %.2f max" % [
		status,
		pcm_samples,
		mel_contexts,
		onnx_runs,
		average_ms,
		_onnx_max_usec / 1000.0,
	]
