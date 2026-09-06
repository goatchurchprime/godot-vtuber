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
var _source_filter: Object
var _loader: Object
var _history := PackedFloat32Array()
var _history_frames := 1
var _feature_count := 0
var _frontend_name := "mel"
var _pcm_pending := PackedFloat32Array()
var _window_samples := 0
var _hop_samples := 0
var _normalization_frames := 200
var _frontend_usec := 0
var _frontend_max_usec := 0
var _onnx_usec := 0
var _onnx_max_usec := 0


func _ready() -> void:
	levels.resize(15)
	_mel = ClassDB.instantiate("MelFrontend")
	_loader = ClassDB.instantiate("OnnxLoader")
	if _loader == null:
		status = "missing OnnxLoader"
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
	_frontend_name = str(audio.get("frontend", "mel"))
	var feature_value: Variant = contract.get("n_mels")
	if feature_value == null:
		feature_value = audio.get("input_features", contract.get("input_features", 0))
	_feature_count = int(feature_value)
	_history_frames = int(contract.get("receptive_history_hops", 1))
	var context_frames := int(contract.get("context_frames", 1))
	var sample_rate := int(audio.get("sample_rate", 0))
	var hop := int(audio.get("hop_length_samples", 0))
	var window := int(audio.get("window_length_samples", 0))
	var n_fft := int(audio.get("n_fft", 0))
	var fmin := float(audio.get("fmin", 0.0))
	var fmax := float(audio.get("fmax", 0.0))
	var n_visemes := int(contract.get("n_visemes", 15))
	var input_features := int(contract.get("input_features", context_frames * _feature_count))
	_window_samples = window
	_hop_samples = hop
	if sample_rate != 16000 or _feature_count <= 0 or _window_samples <= 0 or _hop_samples <= 0:
		status = "unsupported model audio contract"
		return
	if _frontend_name == "mel":
		if _mel == null:
			status = "Mel model needs MelFrontend"
			return
		var configured: bool = _mel.call(
			"configure", context_frames, _feature_count, sample_rate, hop, window,
			n_fft, fmin, fmax, n_visemes, input_features,
		)
		if not configured:
			status = "Mel configuration failed"
			return
		_mel.call("begin_stream")
	elif _frontend_name == "lpc-filter" or _frontend_name == "lpc-source-filter":
		if not ClassDB.class_exists("SourceFilterFrontend"):
			status = "%s model needs SourceFilterFrontend" % _frontend_name
			return
		_source_filter = ClassDB.instantiate("SourceFilterFrontend")
		if _source_filter == null:
			status = "SourceFilterFrontend creation failed"
			return
	else:
		status = "unsupported frontend: %s" % _frontend_name
		return
	levels.resize(n_visemes)
	status = "ready (%s, %d features, %d-hop history)" % [_frontend_name, _feature_count, _history_frames]


func is_ready() -> bool:
	return status.begins_with("ready") or status.begins_with("running")


func push_pcm(pcm_16khz: PackedFloat32Array) -> bool:
	if not is_ready() or pcm_16khz.is_empty():
		return false
	pcm_samples += pcm_16khz.size()
	if _frontend_name != "mel":
		return _push_source_filter_pcm(pcm_16khz)
	_mel.call("push_pcm", pcm_16khz)
	var received_context := false
	while int(_mel.call("count_available_contexts")) > 0:
		var frame: PackedFloat32Array = _mel.call("get_next_context")
		if frame.size() != _feature_count:
			continue
		mel_contexts += 1
		received_context = true
		_history.append_array(frame)
		var maximum_values := _history_frames * _feature_count
		if _history.size() > maximum_values:
			_history = _history.slice(_history.size() - maximum_values)
	if not received_context:
		return false
	return _predict_latest()


func _push_source_filter_pcm(pcm: PackedFloat32Array) -> bool:
	_pcm_pending.append_array(pcm)
	var produced := false
	while _pcm_pending.size() >= _window_samples:
		var frontend_started_usec := Time.get_ticks_usec()
		var analysis: Dictionary = _source_filter.call("analyze_frame", _pcm_pending.slice(0, _window_samples))
		var frontend_elapsed_usec := Time.get_ticks_usec() - frontend_started_usec
		_frontend_usec += frontend_elapsed_usec
		_frontend_max_usec = maxi(_frontend_max_usec, frontend_elapsed_usec)
		_pcm_pending = _pcm_pending.slice(_hop_samples)
		var feature := _source_filter_feature(analysis)
		if feature.size() != _feature_count:
			status = "%s returned %d/%d features" % [_frontend_name, feature.size(), _feature_count]
			return false
		_history.append_array(feature)
		var maximum_values := _normalization_frames * _feature_count
		if _history.size() > maximum_values:
			_history = _history.slice(_history.size() - maximum_values)
		mel_contexts += 1
		produced = true
	if not produced:
		return false
	return _predict_latest_source_filter()


func _source_filter_feature(analysis: Dictionary) -> PackedFloat32Array:
	var reflection: PackedFloat32Array = analysis.get("reflection", PackedFloat32Array())
	if reflection.size() != 16:
		return PackedFloat32Array()
	if _frontend_name == "lpc-filter":
		return reflection
	var scalars := PackedFloat32Array([
		float(analysis.get("rms_dbfs", -120.0)),
		float(analysis.get("prediction_gain_db", 0.0)),
		float(analysis.get("periodicity", 0.0)),
		float(analysis.get("pitch_hz", 0.0)),
		float(analysis.get("pitch_confidence", 0.0)),
		1.0 if bool(analysis.get("pitch_valid", false)) else 0.0,
		float(analysis.get("hnr_db", -120.0)),
		float(analysis.get("residual_tilt_db_octave", 0.0)),
	])
	var out := reflection.duplicate()
	out.append(clampf((scalars[0] + 60.0) / 60.0, 0.0, 1.0))
	out.append(clampf(scalars[1] / 30.0, 0.0, 1.0))
	out.append(scalars[2])
	out.append(clampf(log(maxf(scalars[3], 70.0) / 70.0) / log(400.0 / 70.0), 0.0, 1.0))
	out.append(scalars[4])
	out.append(scalars[5])
	out.append(clampf((scalars[6] + 5.0) / 35.0, 0.0, 1.0))
	out.append(clampf((scalars[7] + 18.0) / 36.0, 0.0, 1.0))
	return out


func _predict_latest_source_filter() -> bool:
	var frames := _history.size() / _feature_count
	var normalized := PackedFloat32Array()
	normalized.resize(_history.size())
	# Application policy: approximate training's utterance normalization with a
	# bounded two-second causal window so live capture cannot look into the future.
	for feature_index in _feature_count:
		var mean := 0.0
		for frame_index in frames:
			mean += _history[frame_index * _feature_count + feature_index]
		mean /= float(frames)
		var variance := 0.0
		for frame_index in frames:
			var difference := _history[frame_index * _feature_count + feature_index] - mean
			variance += difference * difference
		var scale := sqrt(variance / float(frames)) + 1e-5
		for frame_index in frames:
			normalized[frame_index * _feature_count + feature_index] = (
				_history[frame_index * _feature_count + feature_index] - mean
			) / scale
	var receptive_values := mini(frames, _history_frames) * _feature_count
	return _run_onnx(normalized.slice(normalized.size() - receptive_values))


func push_audio(_conditioned_48khz: PackedVector2Array, analysis_16khz: PackedFloat32Array) -> bool:
	return push_pcm(analysis_16khz)


func _predict_latest() -> bool:
	return _run_onnx(_history)


func _run_onnx(features: PackedFloat32Array) -> bool:
	var frame_count := features.size() / _feature_count
	if frame_count <= 0:
		return false
	var started_usec := Time.get_ticks_usec()
	var logits: PackedFloat32Array = _loader.call(
		"predict_shaped",
		features,
		PackedInt32Array([1, frame_count, _feature_count]),
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
	status = "running (%s)" % _frontend_name
	return true


func get_status() -> String:
	var average_ms := 0.0 if onnx_runs == 0 else float(_onnx_usec) / onnx_runs / 1000.0
	var frontend_average_ms := 0.0 if mel_contexts == 0 else float(_frontend_usec) / mel_contexts / 1000.0
	return "%s | pcm %d | features %d | onnx %d | frontend %.2f/%.2f ms | onnx %.2f/%.2f ms avg/max" % [
		status,
		pcm_samples,
		mel_contexts,
		onnx_runs,
		frontend_average_ms,
		_frontend_max_usec / 1000.0,
		average_ms,
		_onnx_max_usec / 1000.0,
	]
