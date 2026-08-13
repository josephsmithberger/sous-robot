extends Control

const INK := Color("#27251F")
const TOMATO := Color("#DA291C")
const SUNFLOWER := Color("#FFC72C")
const HAND_SHADOW := Color(0.05, 0.04, 0.03, 0.22)

var _last_second := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _process(_delta: float) -> void:
	var second := int(Time.get_time_dict_from_system()["second"])
	if second != _last_second:
		_last_second = second
		queue_redraw()

func _draw() -> void:
	var now := Time.get_time_dict_from_system()
	var seconds := float(now["second"])
	var minutes := float(now["minute"]) + seconds / 60.0
	var hours := fmod(float(now["hour"]), 12.0) + minutes / 60.0
	var radius := minf(size.x, size.y) * 0.5

	_draw_hand(hours / 12.0, radius * 0.43, 5.5, INK)
	_draw_hand(minutes / 60.0, radius * 0.65, 3.5, INK)
	_draw_hand(seconds / 60.0, radius * 0.72, 2.0, TOMATO)

	var center := size * 0.5
	draw_circle(center, 6.0, INK)
	draw_circle(center, 3.0, SUNFLOWER)

func _draw_hand(turns: float, length: float, width: float, color: Color) -> void:
	var center := size * 0.5
	var end := center + Vector2.UP.rotated(TAU * turns) * length
	var shadow_offset := Vector2(1.5, 1.5)
	draw_line(center + shadow_offset, end + shadow_offset, HAND_SHADOW, width + 1.5, true)
	draw_line(center, end, color, width, true)
