class_name HumanArmSolver
extends RefCounted

## Reconstructs a stable, canonical human arm before avatar retargeting.
## OpenXR joint bases are observations; positions define this rig's geometry.

var shoulder_half_width := 0.19
var shoulder_drop := 0.23
var upper_arm_length := 0.30
var forearm_length := 0.27


func enrich(frame: Variant) -> void:
	_solve_side(frame.landmarks, "left", -1.0)
	_solve_side(frame.landmarks, "right", 1.0)


func _solve_side(landmarks: Dictionary, side: String, sign_x: float) -> void:
	var hand_value: Variant = landmarks.get("%s_hand" % side, {})
	if not hand_value is Dictionary:
		return
	var wrist_value: Variant = hand_value.get("position", [])
	if not wrist_value is Array or wrist_value.size() != 3:
		return
	var shoulder := Vector3(sign_x * shoulder_half_width, -shoulder_drop, 0.0)
	var wrist := Vector3(float(wrist_value[0]), float(wrist_value[1]), float(wrist_value[2]))
	var elbow := solve_elbow(shoulder, wrist, sign_x)
	landmarks["%s_shoulder" % side] = _vector3_array(shoulder)
	landmarks["%s_elbow" % side] = _vector3_array(elbow)


func solve_elbow(shoulder: Vector3, wrist: Vector3, sign_x: float) -> Vector3:
	var shoulder_to_wrist := wrist - shoulder
	var distance := clampf(
		shoulder_to_wrist.length(),
		absf(upper_arm_length - forearm_length) + 0.001,
		upper_arm_length + forearm_length - 0.001,
	)
	var forward := shoulder_to_wrist.normalized()
	if forward.is_zero_approx():
		forward = Vector3.DOWN
	var along := (
		upper_arm_length * upper_arm_length
		- forearm_length * forearm_length
		+ distance * distance
	) / (2.0 * distance)
	var height := sqrt(maxf(0.0, upper_arm_length * upper_arm_length - along * along))
	# Elbows prefer outwards and slightly behind the palms. Projecting this
	# reference off the shoulder/wrist line gives the deterministic pole plane.
	var pole_reference := Vector3(sign_x, -0.35, 0.45).normalized()
	var pole := (pole_reference - forward * pole_reference.dot(forward)).normalized()
	if pole.is_zero_approx():
		pole = Vector3(sign_x, 0.0, 0.0)
	return shoulder + forward * along + pole * height


func _vector3_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
