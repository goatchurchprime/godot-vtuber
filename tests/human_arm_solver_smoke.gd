extends SceneTree

const SolverScript := preload("res://src/tracking/human_arm_solver.gd")


func _init() -> void:
	var solver := SolverScript.new()
	var shoulder := Vector3(-0.19, -0.23, 0.0)
	var wrist := Vector3(-0.48, -0.38, -0.15)
	var elbow: Vector3 = solver.solve_elbow(shoulder, wrist, -1.0)
	assert(absf(shoulder.distance_to(elbow) - solver.upper_arm_length) < 0.001)
	assert(absf(elbow.distance_to(wrist) - solver.forearm_length) < 0.001)
	assert(elbow.x < shoulder.x, "left elbow pole should point outwards")
	print("HUMAN_ARM_SOLVER_OK elbow=", elbow)
	quit()
