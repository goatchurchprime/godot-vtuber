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
	assert(main.screenshot_button is Button)
	assert(main.copy_status_button is Button)
	assert(main.calibrate_hands_button is Button)
	assert(main.camera_zoom is HSlider and main.camera_yaw is HSlider and main.camera_pitch is HSlider)
	assert(main.transparent_background is CheckButton)
	assert(main.latest_pose_frame == null)
	assert(main.tracking_selector.selected == 0)
	assert(main.xr_submission_viewport == null)
	main.avatar_y.value = 0.25
	assert(is_equal_approx(main.avatar_anchor.position.y, 0.25))
	var camera: Camera3D = main.get_node("Margin/Rows/Columns/Preview/PreviewLayout/ViewportContainer/Viewport/Studio/BroadcastCamera")
	assert(camera.position.z >= 3.0, "broadcast camera is still framed as an extreme close-up")
	main.camera_zoom.value = 24.0
	assert(is_equal_approx(camera.fov, 24.0))
	main.transparent_background.button_pressed = true
	assert(main.broadcast_viewport.transparent_bg)
	assert(is_zero_approx(main.studio_environment.environment.background_color.a))
	var springs: Array = avatar._avatar_root.get("spring_bones")
	assert(springs.size() == 3, "expected two ear springs and one hair spring")
	assert(float(springs[0].stiffness_scale) > 1.1, "ear spring tuning was not applied: %s" % springs[0].stiffness_scale)
	assert(float(springs[2].stiffness_scale) > 0.8, "hair spring tuning was not applied: %s" % springs[2].stiffness_scale)
	assert(avatar._arm_ik.size() == 2, "expected standard IK chains for both arms")
	assert(avatar._spine_ik != null, "expected seated spine IK from the fixed torso to the head")
	var left_ik: SkeletonIK3D = avatar._arm_ik.left
	var right_ik: SkeletonIK3D = avatar._arm_ik.right
	assert(not left_ik.is_running(), "left IK must wait for a valid wrist target")
	assert(not right_ik.is_running(), "right IK must wait for a valid wrist target")
	var pose = PoseFrameScript.new(1)
	pose.landmarks = {
		"head_position": [0.08, 0.04, -0.10],
		"head_rotation_quaternion": [sin(0.1), 0.0, 0.0, cos(0.1)],
		"left_hand": {
			"position": [-0.45, -0.38, -0.12],
			"rotation_quaternion": [0.0, 0.0, 0.0, 1.0],
			"trigger": 1.0,
			"grip": 1.0,
		},
	}
	HumanArmSolverScript.new().enrich(pose)
	avatar.set_pose(pose)
	assert(avatar._spine_ik.is_running(), "head translation should activate seated spine IK")
	assert(avatar._spine_ik.target.origin.distance_to(avatar._head_reference_position) > 0.12)
	var head_delta: Quaternion = avatar._spine_target_basis.inverse() * avatar._spine_ik.target.basis
	assert(head_delta.get_euler().x < 0.0, "tracked nod pitch should be mirrored")
	assert(not left_ik.is_running(), "mirrored untracked left IK should remain stopped")
	assert(right_ik.is_running(), "left controller should drive screen-left/right-arm IK in mirror mode")
	assert(right_ik.target.origin.x < avatar._head_reference_position.x)
	assert(right_ik.use_magnet)
	assert(right_ik.override_tip_basis)
	assert(avatar._arm_debug_hand.size() == 2 and avatar._arm_debug_elbow.size() == 2)
	assert(avatar._arm_debug_achieved.size() == 2)
	assert(not avatar._finger_controls.right.is_empty(), "avatar finger controls should be derived from its skeleton")
	var finger_control: Dictionary = avatar._finger_controls.right[0]
	assert(not avatar._skeleton.get_bone_pose_rotation(finger_control.bone).is_equal_approx(finger_control.rest), "grip/trigger should curl finger bones")
	assert(avatar._arm_debug_target_ray.size() == 2 and avatar._arm_debug_achieved_ray.size() == 2)
	assert(avatar._arm_debug_target_palm.size() == 2 and avatar._arm_debug_achieved_palm.size() == 2)
	assert(not (avatar._arm_hand_axes.right as Vector3).is_zero_approx())
	var right_shoulder: Vector3 = avatar._skeleton.get_bone_global_pose(int(avatar._arm_root_bones.right)).origin
	assert(right_ik.magnet.y < right_shoulder.y, "pole target must stay below the shoulder")
	assert(right_ik.magnet.x < right_shoulder.x, "right-arm pole target must stay outward")
	var first_pole := right_ik.magnet
	pose.landmarks.left_hand.position[1] += 0.20
	avatar.set_pose(pose)
	assert(right_ik.magnet.distance_to(first_pole) > 0.09, "elbow pole should follow wrist motion")
	pose.landmarks.left_hand.position[1] -= 0.20
	avatar.set_pose(pose)
	var neutral_hand_basis := right_ik.target.basis
	pose.landmarks.left_hand.rotation_quaternion = [0.0, 0.0, sin(0.2), cos(0.2)]
	avatar.set_pose(pose)
	assert(not right_ik.target.basis.is_equal_approx(neutral_hand_basis), "controller rotation should rotate the avatar wrist")
	avatar.reset_hand_orientation_calibration()
	avatar.set_pose(pose)
	var calibrated_finger: Vector3 = right_ik.target.basis * avatar._arm_hand_axes.right
	var calibrated_palm: Vector3 = right_ik.target.basis * avatar._arm_palm_normal_axes.right
	assert(calibrated_finger.dot(Vector3.BACK) > 0.99, "calibrated fingers should point forward from the avatar")
	assert(calibrated_palm.dot(Vector3.DOWN) > 0.99, "calibrated palms should face down")
	await process_frame
	await process_frame
	assert(not avatar._skeleton.get_bone_pose_rotation(finger_control.bone).is_equal_approx(finger_control.rest), "finger curl should survive IK processing")
	var achieved_attachment := avatar._arm_debug_attachment.right as BoneAttachment3D
	assert(achieved_attachment.transform.origin.distance_to(right_ik.target.origin) < 0.25, "final hand attachment should follow the solved wrist")
	var environment: WorldEnvironment = main.get_node("Margin/Rows/Columns/Preview/PreviewLayout/ViewportContainer/Viewport/Studio/Environment")
	assert(environment.environment.ambient_light_energy <= 0.25, "studio ambient light is still over-bright")
	print("Main scene ready | %s | %s" % [stream.status, avatar.status])
	quit()
