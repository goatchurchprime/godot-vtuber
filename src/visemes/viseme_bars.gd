class_name VisemeBars
extends GridContainer

## Compact raw-weight display shared by all 15-viseme recognizer backends.

const NAMES := [
	"sil", "PP", "FF", "TH", "DD", "kk", "CH", "SS",
	"nn", "RR", "aa", "E", "I", "O", "U",
]

var _bars: Array[ProgressBar] = []


func _ready() -> void:
	columns = 6
	for viseme_name in NAMES:
		var label := Label.new()
		label.text = viseme_name
		label.custom_minimum_size.x = 28.0
		label.add_theme_font_size_override("font_size", 11)
		add_child(label)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(65.0, 10.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 1.0
		bar.show_percentage = false
		add_child(bar)
		_bars.append(bar)


func set_levels(levels: PackedFloat32Array) -> void:
	for index in _bars.size():
		_bars[index].value = levels[index] if index < levels.size() else 0.0
