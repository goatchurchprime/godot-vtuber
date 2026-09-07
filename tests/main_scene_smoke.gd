extends SceneTree

const PoseFrameScript := preload("res://src/tracking/pose_frame.gd")
const HumanArmSolverScript := preload("res://src/tracking/human_arm_solver.gd")


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
	assert(main.mouth_attack != null)
	assert(main.microphone_starts_enabled, "microphone startup policy should default to enabled")
	main.mouth_attack.value = 135.0
	assert(is_equal_approx(avatar.mouth_attack_ms, 135.0))
	assert(Engine.max_fps == 60)
	assert(main.performance_status != null)
	assert(main.tracking_selector.item_count == 4)
	assert(main.pose_status is LineEdit and not main.pose_status.editable)
	assert(main.tracking_selector.selected == 0)
	assert(main.xr_submission_viewport == null)
	main.avatar_y.value = 0.25
	assert(is_equal_approx(main.avatar_anchor.position.y, 0.25))
	var camera: Camera3D = main.get_node("Margin/Rows/Columns/Preview/PreviewLayout/ViewportContainer/Viewport/Studio/BroadcastCamera")
	assert(camera.position.z >= 3.0, "broadcast camera is still framed as an extreme close-up")
	var springs: Array = avatar._avatar_root.get("spring_bones")
	assert(springs.size() == 3, "expected two ear springs and one hair spring")
	assert(float(springs[0].stiffness_scale) > 1.1, "ear spring tuning was not applied: %s" % springs[0].stiffness_scale)
	assert(float(springs[2].stiffness_scale) > 0.8, "hair spring tuning was not applied: %s" % springs[2].stiffness_scale)
	assert(avatar._arm_ik.size() == 2, "expected standard IK chains for both arms")
	var left_ik: SkeletonIK3D = avatar._arm_ik.left
	var right_ik: SkeletonIK3D = avatar._arm_ik.right
	assert(not left_ik.is_running(), "left IK must wait for a valid wrist target")
	assert(not right_ik.is_running(), "right IK must wait for a valid wrist target")
	var pose = PoseFrameScript.new(1)
	pose.landmarks = {
		"head_rotation_quaternion": [sin(0.1), 0.0, 0.0, cos(0.1)],
		"left_hand": {
			"position": [-0.45, -0.38, -0.12],
			"rotation_quaternion": [0.0, 0.0, 0.0, 1.0],
		},
	}
	HumanArmSolverScript.new().enrich(pose)
	avatar.set_pose(pose)
	var head_delta: Quaternion = avatar._head_rest_rotation.inverse() * avatar._skeleton.get_bone_pose_rotation(avatar._head_bone)
	assert(head_delta.get_euler().x < 0.0, "tracked nod pitch should be mirrored")
	assert(left_ik.is_running(), "left IK should start after its first valid target")
	assert(not right_ik.is_running(), "untracked right IK should remain stopped")
	assert(left_ik.target.origin.x > avatar._head_reference_position.x)
	assert(left_ik.use_magnet)
	assert(left_ik.override_tip_basis)
	var neutral_hand_basis := left_ik.target.basis
	pose.landmarks.left_hand.rotation_quaternion = [0.0, 0.0, sin(0.2), cos(0.2)]
	avatar.set_pose(pose)
	assert(not left_ik.target.basis.is_equal_approx(neutral_hand_basis), "controller rotation should rotate the avatar wrist")
	var environment: WorldEnvironment = main.get_node("Margin/Rows/Columns/Preview/PreviewLayout/ViewportContainer/Viewport/Studio/Environment")
	assert(environment.environment.ambient_light_energy <= 0.25, "studio ambient light is still over-bright")
	print("Main scene ready | %s | %s" % [stream.status, avatar.status])
	quit()
