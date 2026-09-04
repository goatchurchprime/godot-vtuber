extends Control

const OUTPUT_RATE := 48000
const CHUNK_DURATION_MS := 20
const OUTPUT_CHUNK_FRAMES := 960
const TWOVOIP_EXTENSION := "res://addons/twovoip/twovoip.gdextension"
const MEL_EXTENSION := "res://addons/vizemes_mel/vizemes_mel.gdextension"
const ONNX_EXTENSION := "res://addons/onnx_loader/onnx_loader.gdextension"
const VISEME_MODEL := "res://models/viseme.onnx"
const VisemeStreamScript := preload("res://src/visemes/viseme_stream.gd")
const OvrLipSyncStreamScript := preload("res://src/visemes/ovr_lipsync_stream.gd")
const VisemeFrameScript := preload("res://src/visemes/viseme_frame.gd")
const GATE_HYSTERESIS_DB := 6.0
const GATE_RELEASE_CHUNKS := 6

@onready var audio_status: Label = %Audio
@onready var viseme_status: Label = %Visemes
@onready var pose_status: Label = %Pose
@onready var avatar_status: Label = %AvatarStatus
@onready var clock_status: Label = %Clock
@onready var buffer_status: Label = %Buffer
@onready var level: ProgressBar = %Level
@onready var level_text: Label = %LevelText
@onready var microphone: CheckButton = %Microphone
@onready var monitor: CheckButton = %Monitor
@onready var delay: SpinBox = %Delay
@onready var gate_db: SpinBox = %GateDb
@onready var backend_selector: OptionButton = %Backend
@onready var input_device: OptionButton = %InputDevice
@onready var monitor_player: AudioStreamPlayer = %MonitorPlayer
@onready var avatar: Node = %Avatar

var encoder: Object
var viseme_stream: Variant
var onnx_viseme_stream: Variant
var ovr_viseme_stream: Variant
var playback: AudioStreamGeneratorPlayback
var pending_input := PackedVector2Array()
var playout_queue: Array[PackedVector2Array] = []
var queued_frames := 0
var processed_sample_position := 0
var submitted_sample_position := 0
var playback_capacity_frames := 0
var required_input_frames := 0
var processing_enabled := false
var viseme_queue: Array = []
var speech_active := false
var quiet_chunks := 0


func _ready() -> void:
	_load_optional_extension(TWOVOIP_EXTENSION, "TwovoipOpusEncoder")
	_load_optional_extension(MEL_EXTENSION, "MelFrontend")
	_load_optional_extension(ONNX_EXTENSION, "OnnxLoader")
	_configure_audio_bus()
	_populate_input_devices()
	microphone.toggled.connect(_set_microphone_enabled)
	monitor.toggled.connect(_set_monitor_enabled)
	delay.value_changed.connect(_restart_playout.bind())
	input_device.item_selected.connect(_select_input_device)
	audio_status.text = _availability("Audio conditioning", "TwovoipOpusEncoder")
	viseme_status.text = _availability("Viseme inference", "OnnxLoader")
	pose_status.text = "Webcam pose: adapter not installed"
	avatar_status.text = "Avatar: %s" % avatar.status
	if ClassDB.class_exists("TwovoipOpusEncoder"):
		_configure_encoder()
	else:
		microphone.disabled = true
		monitor.disabled = true
		input_device.disabled = true
	_configure_visemes()


func _process(_delta: float) -> void:
	if not processing_enabled:
		return
	_capture_conditioned_chunks()
	_start_playout_when_ready()
	_drain_playout_queue()
	_apply_synchronized_visemes()
	_update_diagnostics()


func _load_optional_extension(path: String, provided_class: StringName) -> void:
	if ClassDB.class_exists(provided_class):
		return
	if not FileAccess.file_exists(path):
		return
	var error := GDExtensionManager.load_extension(path)
	if error != OK:
		push_warning("Could not load optional extension %s: %s" % [path, error_string(error)])


func _configure_encoder() -> void:
	encoder = ClassDB.instantiate("TwovoipOpusEncoder")
	if encoder == null or not encoder.has_method("get_current_chunk"):
		audio_status.text = "Audio conditioning: TwoVoIP needs get_current_chunk()"
		microphone.disabled = true
		monitor.disabled = true
		return
	var error: int = encoder.call(
		"create_sampler",
		AudioServer.get_input_mix_rate(),
		OUTPUT_RATE,
		1,
		0,
		0,
		OUTPUT_CHUNK_FRAMES,
	)
	if error != OK:
		audio_status.text = "Audio conditioning: %s" % error_string(error)
		microphone.disabled = true
		monitor.disabled = true
		return
	required_input_frames = encoder.call("get_required_input_chunk_size")
	audio_status.text = "Audio conditioning: ready (%d → %d Hz)" % [
		AudioServer.get_input_mix_rate(), OUTPUT_RATE,
	]


func _configure_visemes() -> void:
	backend_selector.clear()
	backend_selector.add_item("Our Mel + ONNX", 0)
	backend_selector.add_item("OVRLipSync 1.61", 1)
	backend_selector.item_selected.connect(_select_viseme_backend)
	if ClassDB.class_exists("MelFrontend") and ClassDB.class_exists("OnnxLoader") and FileAccess.file_exists(VISEME_MODEL):
		onnx_viseme_stream = VisemeStreamScript.new()
		onnx_viseme_stream.model_path = VISEME_MODEL
		add_child(onnx_viseme_stream)
	ovr_viseme_stream = OvrLipSyncStreamScript.new()
	add_child(ovr_viseme_stream)
	_select_viseme_backend(0)


func _select_viseme_backend(index: int) -> void:
	viseme_queue.clear()
	speech_active = false
	quiet_chunks = 0
	viseme_stream = onnx_viseme_stream if index == 0 else ovr_viseme_stream
	if viseme_stream == null:
		viseme_status.text = "Viseme inference: selected backend unavailable"
		return
	viseme_status.text = "Viseme inference: %s" % viseme_stream.get_status()


func _configure_audio_bus() -> void:
	if AudioServer.get_bus_index("VTuberMonitor") >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, "VTuberMonitor")


func _populate_input_devices() -> void:
	input_device.clear()
	for device in AudioServer.get_input_device_list():
		input_device.add_item(device)


func _select_input_device(index: int) -> void:
	if index >= 0:
		AudioServer.set_input_device(input_device.get_item_text(index))


func _set_microphone_enabled(enabled: bool) -> void:
	var error := AudioServer.set_input_device_active(enabled)
	if error != OK:
		audio_status.text = "Microphone: %s" % error_string(error)
		microphone.set_pressed_no_signal(false)
		return
	processing_enabled = enabled
	if not enabled:
		pending_input.clear()
		speech_active = false
		quiet_chunks = 0
		_restart_playout()


func _set_monitor_enabled(enabled: bool) -> void:
	if not enabled:
		_restart_playout()
	elif processing_enabled:
		_start_playout_when_ready()


func _restart_playout(_unused: Variant = null) -> void:
	monitor_player.stop()
	playback = null
	playback_capacity_frames = 0
	playout_queue.clear()
	queued_frames = 0
	submitted_sample_position = processed_sample_position
	viseme_queue.clear()


func _capture_conditioned_chunks() -> void:
	while true:
		var needed := required_input_frames - pending_input.size()
		if needed > 0:
			var incoming := AudioServer.get_input_frames(needed)
			if incoming.is_empty():
				break
			pending_input.append_array(incoming)
		if pending_input.size() < required_input_frames:
			break
		var consumed: int = encoder.call("process_chunk", pending_input)
		if consumed <= 0:
			break
		pending_input = pending_input.slice(consumed)
		var conditioned: PackedVector2Array = encoder.call("get_current_chunk")
		if conditioned.is_empty():
			break
		var chunk_end := processed_sample_position + conditioned.size()
		if viseme_stream != null:
			var analysis: PackedFloat32Array = encoder.call("get_current_chunk_16khz")
			if viseme_stream.push_audio(conditioned, analysis):
				var gated_levels := _gate_visemes(
					viseme_stream.levels,
					float(encoder.call("get_rms")),
				)
				var frame: Variant = VisemeFrameScript.new(
					chunk_end,
					gated_levels,
				)
				if monitor.button_pressed:
					viseme_queue.append(frame)
				else:
					avatar.set_visemes(frame.weights)
		processed_sample_position = chunk_end
		if monitor.button_pressed:
			playout_queue.append(conditioned)
			queued_frames += conditioned.size()
		else:
			submitted_sample_position = processed_sample_position


func _gate_visemes(raw_levels: PackedFloat32Array, rms: float) -> PackedFloat32Array:
	var rms_db := linear_to_db(maxf(rms, 0.000001))
	if not speech_active and rms_db >= gate_db.value:
		speech_active = true
		quiet_chunks = 0
	elif speech_active:
		if rms_db < gate_db.value - GATE_HYSTERESIS_DB:
			quiet_chunks += 1
			if quiet_chunks >= GATE_RELEASE_CHUNKS:
				speech_active = false
		else:
			quiet_chunks = 0
	if speech_active:
		return raw_levels.duplicate()
	var silence := PackedFloat32Array()
	silence.resize(raw_levels.size())
	if not silence.is_empty():
		silence[0] = 1.0
	return silence


func _start_playout_when_ready() -> void:
	if not monitor.button_pressed or playback != null:
		return
	var target_frames := roundi(delay.value * OUTPUT_RATE / 1000.0)
	if queued_frames < target_frames:
		return
	monitor_player.play()
	playback = monitor_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback != null:
		playback_capacity_frames = playback.get_frames_available()


func _drain_playout_queue() -> void:
	if playback == null:
		return
	while not playout_queue.is_empty():
		var chunk: PackedVector2Array = playout_queue.front()
		if playback.get_frames_available() < chunk.size():
			break
		playback.push_buffer(chunk)
		playout_queue.pop_front()
		queued_frames -= chunk.size()
		submitted_sample_position += chunk.size()


func _apply_synchronized_visemes() -> void:
	if playback == null:
		return
	var playout_position := _get_playout_sample_position()
	while not viseme_queue.is_empty():
		var frame: Variant = viseme_queue.front()
		if frame.sample_position > playout_position:
			break
		avatar.set_visemes(frame.weights)
		viseme_queue.pop_front()


func _get_playout_sample_position() -> int:
	if playback == null:
		return submitted_sample_position
	var generator_frames := playback_capacity_frames - playback.get_frames_available()
	return submitted_sample_position - generator_frames


func _update_diagnostics() -> void:
	level.value = encoder.call("get_peak") if encoder != null else 0.0
	var rms := float(encoder.call("get_rms")) if encoder != null else 0.0
	level_text.text = "RMS: %.1f dBFS · %s" % [
		linear_to_db(maxf(rms, 0.000001)),
		"speech" if speech_active else "silence",
	]
	var generator_frames := 0
	if playback != null:
		generator_frames = playback_capacity_frames - playback.get_frames_available()
	var buffered_frames := queued_frames + generator_frames
	buffer_status.text = "Buffered: %.1f ms (%d queued chunks)" % [
		buffered_frames * 1000.0 / OUTPUT_RATE,
		playout_queue.size(),
	]
	var playout_sample_position := _get_playout_sample_position()
	clock_status.text = "Processed: %d · playout: %d" % [
		processed_sample_position,
		playout_sample_position,
	]
	if viseme_stream != null:
		viseme_status.text = "Viseme inference: %s" % viseme_stream.get_status()
	avatar_status.text = "Avatar: %s" % avatar.status


func _availability(label: String, native_class: StringName) -> String:
	if ClassDB.class_exists(native_class):
		return "%s: available" % label
	return "%s: optional dependency absent" % label
