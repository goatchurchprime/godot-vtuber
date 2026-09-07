extends SceneTree

const AdapterScript := preload("res://src/tracking/openxr_tracking_adapter.gd")


func _init() -> void:
	var adapter: Node = AdapterScript.new()
	var transform := Transform3D(Basis.from_euler(Vector3(0.1, -0.2, 0.3)), Vector3(1.0, 2.0, 3.0))
	var encoded: Dictionary = adapter._transform_dictionary(transform)
	assert(encoded.position.size() == 3)
	assert(is_equal_approx(float(encoded.position[1]), 2.0))
	assert(encoded.rotation_quaternion.size() == 4)
	adapter._origin_head = Transform3D(Basis.from_euler(Vector3(0.0, 0.4, 0.0)), Vector3(1.0, 1.5, -2.0))
	adapter._origin_captured = true
	var controller_observation := Transform3D(Basis.IDENTITY, Vector3(1.4, 1.2, -1.7))
	var controller_in_session: Transform3D = adapter._to_session_origin(controller_observation)
	# A later HMD pose is deliberately unrelated: controller conversion must
	# depend only on the fixed session origin, never on the current head pose.
	var later_head := Transform3D(Basis.from_euler(Vector3(0.0, -0.8, 0.0)), Vector3(-2.0, 0.2, 4.0))
	assert(adapter._to_session_origin(controller_observation).is_equal_approx(controller_in_session))
	assert(not (later_head.affine_inverse() * controller_observation).is_equal_approx(controller_in_session))
	assert(adapter.get_status().contains("inactive"))
	print("OPENXR_ADAPTER_OK")
	adapter.free()
	quit()
