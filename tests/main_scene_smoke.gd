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
	var avatar: Node = main.get_node("%Avatar")
	assert(avatar.status.begins_with("avatar ready"), avatar.status)
	print("Main scene ready | %s | %s" % [stream.status, avatar.status])
	quit()
