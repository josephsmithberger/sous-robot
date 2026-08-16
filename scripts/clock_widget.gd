extends Control

const INK := Color("#27251F")
const FRESH_GREEN := Color("#22C55E")
const SUNFLOWER_YELLOW := Color("#FACC15")
const WARNING_ORANGE := Color("#F97316")
const URGENT_RED := Color("#DC2626")
const DANGER_PULSE_RED := Color("#FF0033")
const TRACK_BG := Color(0.15, 0.14, 0.12, 0.18)
const HAND_SHADOW := Color(0.05, 0.04, 0.03, 0.25)

var active_order_id := 0
var elapsed_time := 0.0
var max_time := 30.0
var current_tip := 0.0
var urgency := 0.0:
	set(value):
		urgency = clampf(value, 0.0, 1.0)
		queue_redraw()

var is_active := false
var _completion_anim := 0.0
var _completion_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameControl.order_started.connect(_on_order_started)
	GameControl.order_timer_updated.connect(_on_order_timer_updated)
	GameControl.order_completed.connect(_on_order_completed)
	queue_redraw()


func _exit_tree() -> void:
	if _completion_tween and _completion_tween.is_valid():
		_completion_tween.kill()
	if GameControl.order_started.is_connected(_on_order_started):
		GameControl.order_started.disconnect(_on_order_started)
	if GameControl.order_timer_updated.is_connected(_on_order_timer_updated):
		GameControl.order_timer_updated.disconnect(_on_order_timer_updated)
	if GameControl.order_completed.is_connected(_on_order_completed):
		GameControl.order_completed.disconnect(_on_order_completed)


func _process(_delta: float) -> void:
	if is_active:
		queue_redraw()


func _on_order_started(order_id: int, order: Dictionary) -> void:
	if _completion_tween and _completion_tween.is_valid():
		_completion_tween.kill()
	_completion_anim = 0.0
	active_order_id = order_id
	elapsed_time = 0.0
	max_time = maxf(float(order.get("max_time", 30.0)), 0.001)
	current_tip = float(order.get("tip", 0.0))
	urgency = 0.0
	is_active = true
	queue_redraw()


func _on_order_timer_updated(order_id: int, p_elapsed: float, p_max_time: float, p_current_tip: float, p_urgency: float) -> void:
	if active_order_id != order_id and not is_active:
		active_order_id = order_id
		is_active = true
	if active_order_id == order_id:
		elapsed_time = p_elapsed
		max_time = maxf(p_max_time, 0.001)
		current_tip = p_current_tip
		urgency = p_urgency


func _on_order_completed(order_id: int, _payout: float, _final_tip: float) -> void:
	if active_order_id == order_id or is_active:
		is_active = false
		active_order_id = 0
		_play_completion_animation()


func _play_completion_animation() -> void:
	if _completion_tween and _completion_tween.is_valid():
		_completion_tween.kill()
	_completion_anim = 1.0
	_completion_tween = create_tween()
	_completion_tween.tween_property(self, ^"_completion_anim", 0.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_completion_tween.finished.connect(queue_redraw)


func _get_urgency_color(u: float) -> Color:
	if u < 0.35:
		return FRESH_GREEN.lerp(SUNFLOWER_YELLOW, u / 0.35)
	elif u < 0.7:
		return SUNFLOWER_YELLOW.lerp(WARNING_ORANGE, (u - 0.35) / 0.35)
	else:
		return WARNING_ORANGE.lerp(URGENT_RED, (u - 0.7) / 0.3)


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var center := size * 0.5

	# 1. Outer urgency gauge track & arc
	var track_radius := radius * 0.88
	var track_width := 4.5
	draw_arc(center, track_radius, 0.0, TAU, 48, TRACK_BG, track_width, true)

	var hand_color := INK
	var pulse_offset := Vector2.ZERO

	if is_active:
		var base_color := _get_urgency_color(urgency)
		hand_color = base_color
		var fill_angle := urgency * TAU

		# Urgent pulse when late (urgency > 0.65)
		if urgency > 0.65:
			var pulse_speed := 8.0 + (urgency - 0.65) * 18.0
			var pulse_val := (sin(Time.get_ticks_msec() * 0.001 * pulse_speed) + 1.0) * 0.5
			hand_color = base_color.lerp(DANGER_PULSE_RED, pulse_val * 0.55)
			if urgency > 0.85:
				var jitter_amt := (urgency - 0.85) * 1.5
				pulse_offset = Vector2(
					randf_range(-jitter_amt, jitter_amt),
					randf_range(-jitter_amt, jitter_amt)
				)

		# Draw filled urgency arc starting from 12 o'clock (-PI/2) clockwise
		if fill_angle > 0.01:
			draw_arc(
				center,
				track_radius,
				-PI * 0.5,
				-PI * 0.5 + fill_angle,
				maxi(int(fill_angle * 16.0), 4),
				hand_color,
				track_width,
				true
			)
	elif _completion_anim > 0.0:
		# Completion success ring flash
		var success_color := FRESH_GREEN
		success_color.a = _completion_anim
		draw_arc(center, track_radius, 0.0, TAU, 48, success_color, track_width * (1.0 + _completion_anim), true)

	# 2. Single Clock Arm (Timer Pointer)
	var turns := 0.0
	if is_active:
		turns = maxf(elapsed_time / max_time, 0.0)
	var hand_length := radius * 0.72
	var hand_width := 4.0
	_draw_hand(center + pulse_offset, turns, hand_length, hand_width, hand_color)

	# 3. Center Pin & Cap
	var cap_dot_color := hand_color if is_active else (FRESH_GREEN if _completion_anim > 0.0 else INK)
	draw_circle(center, 6.0, INK)
	draw_circle(center, 3.5, cap_dot_color)


func _draw_hand(center: Vector2, turns: float, length: float, width: float, color: Color) -> void:
	var end := center + Vector2.UP.rotated(TAU * turns) * length
	var shadow_offset := Vector2(1.5, 1.5)
	draw_line(center + shadow_offset, end + shadow_offset, HAND_SHADOW, width + 1.5, true)
	draw_line(center, end, color, width, true)
