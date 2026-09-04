extends Control

@onready var audio_status: Label = %Audio
@onready var viseme_status: Label = %Visemes
@onready var pose_status: Label = %Pose


func _ready() -> void:
	audio_status.text = _availability("Audio conditioning", "TwovoipOpusEncoder")
	viseme_status.text = _availability("Viseme inference", "OnnxModel")
	pose_status.text = "Webcam pose: adapter not installed"


func _availability(label: String, native_class: StringName) -> String:
	if ClassDB.class_exists(native_class):
		return "%s: available" % label
	return "%s: optional dependency absent" % label
