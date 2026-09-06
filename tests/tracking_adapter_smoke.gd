extends SceneTree

const AdapterScript := preload("res://src/tracking/mediapipe_udp_adapter.gd")


func _init() -> void:
	var adapter: Node = AdapterScript.new()
	root.add_child(adapter)
	var received: Array = []
	adapter.pose_received.connect(func(frame: Variant) -> void: received.append(frame))
	assert(adapter.ingest_packet('{"schema_version":1,"capture_timestamp_usec":123,"landmarks":{"head_rotation_degrees":[1,2,3],"shoulder_center":[0.1,0,0]},"confidence":{"face":0.9},"face_blend_shapes":{}}'))
	assert(received.size() == 1)
	assert(received[0].timestamp_usec == 123)
	assert(not adapter.ingest_packet('{"schema_version":2}'))
	assert(adapter.rejected_frames == 1)
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color.DARK_GREEN)
	var preview := PackedByteArray([86, 84, 80, 74])
	preview.append_array(image.save_jpg_to_buffer(0.7))
	assert(adapter.ingest_preview_packet(preview))
	assert(adapter.preview_frames == 1)
	print("TRACKING_ADAPTER_OK")
	quit()
