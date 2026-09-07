class_name OpenXRTrackingAdapter
extends "res://src/tracking/tracking_adapter.gd"

const PoseFrameScript := preload("res://src/tracking/pose_frame.gd")
const TRACKER_CONTROLLER := 2
const TRACKER_HAND := 16
const HAND_LEFT := 1
const HAND_RIGHT := 2
const WRIST_JOINT := 1

## Reads OpenXR state directly. XRCamera3D and XRController3D are presentation
## conveniences and are deliberately not part of this adapter boundary.

@export_range(15.0, 144.0, 1.0) var sample_rate_hz := 90.0

var _interface: XRInterface
var _owns_interface := false
var _running := false
var _sample_accumulator := 0.0
var _origin_head := Transform3D.IDENTITY
var _origin_captured := false
var _tracked_hands := 0


func start() -> bool:
	_interface = XRServer.find_interface("OpenXR")
	if _interface == null:
		status = "OpenXR interface unavailable"
		return false
	if not _interface.is_initialized():
		if not _interface.initialize():
			status = "OpenXR initialization failed; check SteamVR/OpenXR runtime"
			return false
		_owns_interface = true
	_running = true
	status = "OpenXR session initialized; waiting for tracking"
	return true


func stop() -> void:
	_running = false
	if _owns_interface and _interface != null and _interface.is_initialized():
		_interface.uninitialize()
	_owns_interface = false
	_interface = null
	super.stop()


func _process(delta: float) -> void:
	if not _running or _interface == null or not _interface.is_initialized():
		return
	_sample_accumulator += delta
	if _sample_accumulator < 1.0 / sample_rate_hz:
		return
	_sample_accumulator = 0.0
	_emit_current_pose()


func _emit_current_pose() -> void:
	var head := XRServer.get_hmd_transform()
	if not _origin_captured:
		_origin_head = head
		_origin_captured = true
	var relative_head := _origin_head.affine_inverse() * head
	var frame = PoseFrameScript.new(Time.get_ticks_usec())
	frame.landmarks = {
		"head_position": _vector3_array(relative_head.origin),
		"head_rotation_quaternion": _quaternion_array(relative_head.basis.get_rotation_quaternion()),
		"head_rotation_degrees": _vector3_array(relative_head.basis.get_euler() * (180.0 / PI)),
	}
	frame.confidence = {"head": 1.0}
	_tracked_hands = 0
	_append_hand(frame, "left_hand", HAND_LEFT)
	_append_hand(frame, "right_hand", HAND_RIGHT)
	received_frames += 1
	status = "OpenXR tracking head + %d hand(s)" % _tracked_hands
	pose_received.emit(frame)


func _append_hand(frame: Variant, key: String, hand: int) -> void:
	var tracker: Variant = _find_hand_tracker(hand)
	if tracker == null:
		return
	var hand_transform := Transform3D.IDENTITY
	var valid := false
	if tracker.is_class("XRHandTracker") and tracker.call("get_has_tracking_data"):
		var flags: int = tracker.call("get_hand_joint_flags", WRIST_JOINT)
		if flags & 5:
			hand_transform = tracker.call("get_hand_joint_transform", WRIST_JOINT)
			valid = true
	else:
		for pose_name: StringName in [&"grip", &"default", &"aim"]:
			if not tracker.call("has_pose", pose_name):
				continue
			var pose: Variant = tracker.call("get_pose", pose_name)
			if pose != null and bool(pose.get("has_tracking_data")):
				hand_transform = pose.get("transform")
				valid = true
				break
	if not valid:
		return
	hand_transform = _origin_head.affine_inverse() * hand_transform
	frame.landmarks[key] = _transform_dictionary(hand_transform)
	frame.confidence[key] = 1.0
	_tracked_hands += 1


func _find_hand_tracker(hand: int) -> Variant:
	var trackers: Dictionary = XRServer.get_trackers(TRACKER_CONTROLLER | TRACKER_HAND)
	for tracker: Variant in trackers.values():
		if tracker != null and tracker.has_method("get_tracker_hand"):
			if int(tracker.call("get_tracker_hand")) == hand:
				return tracker
	return null


func _transform_dictionary(value: Transform3D) -> Dictionary:
	return {
		"position": _vector3_array(value.origin),
		"rotation_quaternion": _quaternion_array(value.basis.get_rotation_quaternion()),
	}


func _vector3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _quaternion_array(value: Quaternion) -> Array[float]:
	return [value.x, value.y, value.z, value.w]


func get_status() -> String:
	var session := "inactive"
	if _interface != null and _interface.is_initialized():
		session = "state %s" % _interface.get_session_state() if _interface.has_method("get_session_state") else "active"
	return "%s | %s | frames %d rejected %d" % [status, session, received_frames, rejected_frames]
