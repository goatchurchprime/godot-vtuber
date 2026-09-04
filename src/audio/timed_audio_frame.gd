class_name TimedAudioFrame
extends RefCounted

## One conditioned PCM frame located on the application's audio sample clock.

var first_sample: int
var sample_rate: int
var samples: PackedVector2Array


func _init(
	p_first_sample: int = 0,
	p_sample_rate: int = 48000,
	p_samples: PackedVector2Array = PackedVector2Array(),
) -> void:
	first_sample = p_first_sample
	sample_rate = p_sample_rate
	samples = p_samples


func duration_samples() -> int:
	return samples.size()

