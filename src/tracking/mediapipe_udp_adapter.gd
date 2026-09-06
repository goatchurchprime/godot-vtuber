class_name MediaPipeUdpAdapter
extends "res://src/tracking/tracking_adapter.gd"

const PoseFrameScript := preload("res://src/tracking/pose_frame.gd")
const PREVIEW_MAGIC := "VTPJ"

signal preview_received(image: Image, timestamp_usec: int)

## Receives newline-free JSON datagrams from tools/mediapipe_tracking_bridge.py.

@export var listen_address := "127.0.0.1"
@export var listen_port := 7007

var _socket := PacketPeerUDP.new()
var preview_frames := 0
var rejected_previews := 0


func start() -> bool:
	var error := _socket.bind(listen_port, listen_address)
	if error != OK:
		status = "bind %s:%d failed: %s" % [listen_address, listen_port, error_string(error)]
		return false
	status = "listening on %s:%d" % [listen_address, listen_port]
	return true


func stop() -> void:
	_socket.close()
	super.stop()


func _process(_delta: float) -> void:
	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if packet.size() >= 4 and packet.slice(0, 4).get_string_from_ascii() == PREVIEW_MAGIC:
			ingest_preview_packet(packet)
		else:
			ingest_packet(packet.get_string_from_utf8())


func ingest_preview_packet(packet: PackedByteArray) -> bool:
	if packet.size() <= 4:
		rejected_previews += 1
		return false
	var image := Image.new()
	var error := image.load_jpg_from_buffer(packet.slice(4))
	if error != OK:
		rejected_previews += 1
		status = "preview decode failed: %s" % error_string(error)
		return false
	preview_frames += 1
	preview_received.emit(image, Time.get_ticks_usec())
	return true


func ingest_packet(text: String) -> bool:
	var value: Variant = JSON.parse_string(text)
	if typeof(value) != TYPE_DICTIONARY:
		rejected_frames += 1
		status = "invalid JSON packet"
		return false
	var packet := value as Dictionary
	if int(packet.get("schema_version", 0)) != 1:
		rejected_frames += 1
		status = "unsupported schema_version"
		return false
	var frame = PoseFrameScript.new(int(packet.get("capture_timestamp_usec", Time.get_ticks_usec())))
	frame.landmarks = packet.get("landmarks", {})
	frame.confidence = packet.get("confidence", {})
	frame.face_blend_shapes = packet.get("face_blend_shapes", {})
	received_frames += 1
	status = "receiving"
	pose_received.emit(frame)
	return true


func get_status() -> String:
	return "%s | pose %d rejected %d | preview %d rejected %d" % [
		status, received_frames, rejected_frames, preview_frames, rejected_previews,
	]
