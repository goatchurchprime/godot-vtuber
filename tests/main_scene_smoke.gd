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
	var springs: Array = avatar._avatar_root.get("spring_bones")
	assert(springs.size() == 3, "expected two ear springs and one hair spring")
	assert(float(springs[0].stiffness_scale) > 1.1, "ear spring tuning was not applied: %s" % springs[0].stiffness_scale)
	assert(float(springs[2].stiffness_scale) > 0.8, "hair spring tuning was not applied: %s" % springs[2].stiffness_scale)
	var environment: WorldEnvironment = main.get_node("Margin/Rows/Columns/Preview/PreviewLayout/ViewportContainer/Viewport/Studio/Environment")
	assert(environment.environment.ambient_light_energy <= 0.25, "studio ambient light is still over-bright")
	print("Main scene ready | %s | %s" % [stream.status, avatar.status])
	quit()
