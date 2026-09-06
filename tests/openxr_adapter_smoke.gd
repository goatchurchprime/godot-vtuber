extends SceneTree

const AdapterScript := preload("res://src/tracking/openxr_tracking_adapter.gd")


func _init() -> void:
	var adapter: Node = AdapterScript.new()
	var transform := Transform3D(Basis.from_euler(Vector3(0.1, -0.2, 0.3)), Vector3(1.0, 2.0, 3.0))
	var encoded: Dictionary = adapter._transform_dictionary(transform)
	assert(encoded.position.size() == 3)
	assert(is_equal_approx(float(encoded.position[1]), 2.0))
	assert(encoded.rotation_quaternion.size() == 4)
	assert(adapter.get_status().contains("inactive"))
	print("OPENXR_ADAPTER_OK")
	adapter.free()
	quit()
