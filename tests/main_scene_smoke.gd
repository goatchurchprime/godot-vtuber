extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn") as PackedScene
	assert(scene != null)
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var stream: Variant = main.viseme_stream
	assert(stream != null, "main scene did not create VizemeStream")
	assert(stream.is_ready(), stream.status)
	var avatar: Node = main.avatar
	assert(avatar.status.begins_with("avatar ready"), avatar.status)
	assert(main.avatar_y != null)
	main.avatar_y.value = 0.25
	assert(is_equal_approx(main.avatar_anchor.position.y, 0.25))
	var camera: Camera3D = main.get_node("Margin/Rows/Columns/Preview/PreviewLayout/ViewportContainer/Viewport/Studio/BroadcastCamera")
	assert(camera.position.z >= 3.0, "broadcast camera is still framed as an extreme close-up")
	print("Main scene ready | %s | %s" % [stream.status, avatar.status])
	quit()
