class_name TutorialOverlay
extends Control

## Event-driven first-order tutorial with screen-space pointers for both UI and
## 3D kitchen targets. It observes normal gameplay instead of locking controls.

enum Step {
	WAITING_FOR_INTRO,
	MOVE_AND_LOOK,
	TAKE_ORDER,
	GET_INGREDIENT,
	PREP_BUN,
	DELIVER_ORDER,
	COMPLETE,
	DISMISSED,
}

const GOLD := Color(1.0, 0.78, 0.17, 1.0)
const INK := Color(0.07, 0.06, 0.05, 0.97)
const TARGET_MARGIN := 34.0

signal tutorial_finished

var _viewport_container: SubViewportContainer
var _kitchen: Node3D
var _move_joystick: Control
var _keyboard_hint: Control
var _tabs: TabContainer
var _orders_panel: Control
var _camera: Camera3D
var _player: Node3D

var _card: PanelContainer
var _eyebrow: Label
var _message: Label
var _dismiss_button: Button
var _arrow: Label
var _target_ring: Panel

var _step := Step.WAITING_FOR_INTRO
var _armed := false
var _movement_origin := Vector3.ZERO
var _movement_time := 0.0
var _bounce_time := 0.0
var _world_target: Node3D
var _world_target_height := 1.2
var _ui_target: Control


func configure(
	viewport_container: SubViewportContainer,
	kitchen: Node3D,
	move_joystick: Control,
	keyboard_hint: Control,
	tabs: TabContainer,
	orders_panel: Control
) -> void:
	_viewport_container = viewport_container
	_kitchen = kitchen
	_move_joystick = move_joystick
	_keyboard_hint = keyboard_hint
	_tabs = tabs
	_orders_panel = orders_panel
	if _kitchen != null:
		_camera = _kitchen.get_node_or_null("Camera3D") as Camera3D
		_player = _kitchen.get_node_or_null("player") as Node3D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 22
	_build_card()
	_build_pointer()
	visible = false

	GameControl.dialogue_activity_changed.connect(_on_dialogue_activity_changed)
	GameControl.input_mode_changed.connect(_on_input_mode_changed)
	GameControl.order_started.connect(_on_order_started)
	GameControl.held_item_changed.connect(_on_held_item_changed)
	GameControl.item_delivered.connect(_on_item_delivered)
	GameControl.order_completed.connect(_on_order_completed)


func arm() -> void:
	_armed = true
	if not GameControl.is_dialogue_active():
		_begin_tutorial()


func _process(delta: float) -> void:
	if not _armed or _step == Step.DISMISSED:
		return
	_bounce_time += delta

	if _step == Step.MOVE_AND_LOOK and GameControl.has_player_control():
		if GameControl.get_move_input().length_squared() > 0.04:
			_movement_time += delta
		else:
			_movement_time = maxf(_movement_time - delta * 0.5, 0.0)
		var floor_movement := 0.0
		if _player != null:
			floor_movement = Vector2(
				_player.global_position.x - _movement_origin.x,
				_player.global_position.z - _movement_origin.z
			).length()
		if floor_movement > 0.55 or _movement_time >= 0.45:
			_show_take_order()

	_refresh_dynamic_target()
	_update_pointer()


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "TutorialCard"
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.position = Vector2(-285.0, 16.0)
	_card.custom_minimum_size = Vector2(570.0, 94.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = INK
	card_style.border_color = GOLD
	card_style.set_border_width_all(3)
	card_style.set_corner_radius_all(12)
	card_style.content_margin_left = 18.0
	card_style.content_margin_right = 12.0
	card_style.content_margin_top = 10.0
	card_style.content_margin_bottom = 10.0
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	card_style.shadow_size = 7
	card_style.shadow_offset = Vector2(0.0, 3.0)
	_card.add_theme_stylebox_override("panel", card_style)
	add_child(_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_card.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	row.add_child(copy)

	_eyebrow = Label.new()
	_eyebrow.text = "TRAINING RUN"
	_eyebrow.add_theme_color_override("font_color", GOLD)
	_eyebrow.add_theme_font_size_override("font_size", 16)
	copy.add_child(_eyebrow)

	_message = Label.new()
	_message.text = ""
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.add_theme_color_override("font_color", Color.WHITE)
	_message.add_theme_font_size_override("font_size", 17)
	copy.add_child(_message)

	_dismiss_button = Button.new()
	_dismiss_button.name = "DismissButton"
	_dismiss_button.text = "SKIP"
	_dismiss_button.custom_minimum_size = Vector2(74.0, 44.0)
	_dismiss_button.focus_mode = Control.FOCUS_NONE
	_dismiss_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_dismiss_button.pressed.connect(_dismiss)
	row.add_child(_dismiss_button)


func _build_pointer() -> void:
	_target_ring = Panel.new()
	_target_ring.name = "TargetRing"
	_target_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_ring.size = Vector2(62.0, 62.0)
	_target_ring.pivot_offset = _target_ring.size * 0.5
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(1.0, 0.78, 0.17, 0.08)
	ring_style.border_color = GOLD
	ring_style.set_border_width_all(4)
	ring_style.set_corner_radius_all(31)
	_target_ring.add_theme_stylebox_override("panel", ring_style)
	add_child(_target_ring)

	_arrow = Label.new()
	_arrow.name = "TargetArrow"
	_arrow.text = "➤"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.size = Vector2(52.0, 52.0)
	_arrow.pivot_offset = _arrow.size * 0.5
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_arrow.add_theme_color_override("font_color", GOLD)
	_arrow.add_theme_color_override("font_outline_color", Color(0.07, 0.06, 0.05, 1.0))
	_arrow.add_theme_constant_override("outline_size", 8)
	_arrow.add_theme_font_size_override("font_size", 42)
	add_child(_arrow)


func _begin_tutorial() -> void:
	if _step != Step.WAITING_FOR_INTRO:
		visible = true
		return
	_step = Step.MOVE_AND_LOOK
	_movement_origin = _player.global_position if _player != null else Vector3.ZERO
	_movement_time = 0.0
	visible = true
	_dismiss_button.text = "SKIP"
	_eyebrow.text = "TRAINING RUN · 1/4"
	_message.text = _movement_copy()
	_set_ui_target(_move_joystick if GameControl.is_using_touch() else _keyboard_hint)


func _show_take_order() -> void:
	if _step >= Step.TAKE_ORDER:
		return
	_step = Step.TAKE_ORDER
	_eyebrow.text = "TRAINING RUN · 2/4"
	_message.text = "Follow the arrow to the robot at the front of the line. When TAKE ORDER appears, use INTERACT."
	_set_world_target(_front_waiter(), 1.65)


func _show_get_ingredient() -> void:
	_step = Step.GET_INGREDIENT
	_eyebrow.text = "TRAINING RUN · 3/4"
	_message.text = "The receipt needs bread and a bun. Follow the arrow to the bun crate and TAKE BREAD."
	_set_world_target(_bun_crate(), 1.15)


func _show_prep_bun() -> void:
	_step = Step.PREP_BUN
	_eyebrow.text = "TRAINING RUN · 3/4"
	_message.text = "Follow the arrow to the cutting board and SLICE BREAD to make the bun."
	_set_world_target(_cutting_board(), 1.15)


func _show_delivery() -> void:
	_step = Step.DELIVER_ORDER
	_eyebrow.text = "TRAINING RUN · 4/4"
	_update_delivery_instruction(true)


func _show_complete() -> void:
	_step = Step.COMPLETE
	_eyebrow.text = "TRAINING COMPLETE"
	_message.text = "Order complete! Earnings appear on the receipt. Spend them in STORE for ingredients and appliances; RECIPES tracks what you make and what the robots can automate."
	_dismiss_button.text = "GOT IT"
	_set_ui_target(_tabs.get_tab_bar())


func _on_dialogue_activity_changed(is_active: bool) -> void:
	if not _armed:
		return
	if is_active:
		visible = false
	elif _step == Step.WAITING_FOR_INTRO:
		_begin_tutorial()
	elif _step != Step.DISMISSED:
		visible = true


func _on_input_mode_changed(_mode: GameControl.InputMode) -> void:
	if _step == Step.MOVE_AND_LOOK:
		_message.text = _movement_copy()
		_set_ui_target(_move_joystick if GameControl.is_using_touch() else _keyboard_hint)


func _on_order_started(_order_id: int, _order: Dictionary) -> void:
	if not _armed or _step == Step.DISMISSED:
		return
	_show_get_ingredient()


func _on_held_item_changed(item: KitchenItem) -> void:
	if not _armed or _step == Step.DISMISSED:
		return
	if _step == Step.GET_INGREDIENT and item != null:
		if item.item_id == &"bread":
			_show_prep_bun()
	elif _step == Step.PREP_BUN and item != null:
		if item.item_id == &"bun":
			_show_delivery()
	elif _step == Step.DELIVER_ORDER:
		_update_delivery_instruction(item != null)


func _on_item_delivered(_item: KitchenItem) -> void:
	if _step == Step.DELIVER_ORDER:
		call_deferred("_update_delivery_instruction", false)


func _on_order_completed(_order_id: int, _payout: float, _final_tip: float) -> void:
	if _armed and _step != Step.DISMISSED:
		_show_complete()


func _update_delivery_instruction(is_holding: bool) -> void:
	if GameControl.has_active_order() and is_holding:
		_message.text = "Carry it to the service window and use DELIVER. Repeat until every line on the receipt is complete."
		_set_world_target(_order_window(), 1.15)
	elif GameControl.has_active_order():
		_message.text = "The receipt still needs food. Return to the bun crate, grab another bread, and deliver it at the window."
		_set_world_target(_bun_crate(), 1.15)


func _refresh_dynamic_target() -> void:
	if _step == Step.TAKE_ORDER:
		var waiter := _front_waiter()
		if waiter != _world_target:
			_set_world_target(waiter, 1.65)


func _set_world_target(target: Node3D, height: float) -> void:
	_world_target = target
	_world_target_height = height
	_ui_target = null


func _set_ui_target(target: Control) -> void:
	_ui_target = target
	_world_target = null
	if _arrow != null:
		_arrow.visible = false


func _update_pointer() -> void:
	if _arrow == null or _target_ring == null or not visible:
		return
	var target_position := Vector2.ZERO
	var has_target := false
	var target_is_on_screen := true

	if _ui_target != null and is_instance_valid(_ui_target) and _ui_target.is_visible_in_tree():
		var target_rect := _ui_target.get_global_rect()
		target_position = target_rect.get_center() - get_global_rect().position
		has_target = true
	elif _world_target != null and is_instance_valid(_world_target) and _camera != null and _viewport_container != null:
		var world_position := _world_target.global_position + Vector3.UP * _world_target_height
		var projected := _camera.unproject_position(world_position)
		var viewport_size := _camera.get_viewport().get_visible_rect().size
		var scale_factor := Vector2(
			_viewport_container.size.x / maxf(viewport_size.x, 1.0),
			_viewport_container.size.y / maxf(viewport_size.y, 1.0)
		)
		target_position = _viewport_container.position + projected * scale_factor
		has_target = true
		target_is_on_screen = not _camera.is_position_behind(world_position)

	if not has_target:
		_arrow.visible = false
		_target_ring.visible = false
		return

	var bounds := Rect2(Vector2.ZERO, size).grow(-TARGET_MARGIN)
	var clamped := Vector2(
		clampf(target_position.x, bounds.position.x, bounds.end.x),
		clampf(target_position.y, bounds.position.y, bounds.end.y)
	)
	if not target_is_on_screen:
		var center := size * 0.5
		var direction := target_position - center
		if direction.length_squared() < 0.01:
			direction = Vector2.DOWN
		clamped = center + direction.normalized() * minf(size.x, size.y) * 0.42
		clamped.x = clampf(clamped.x, bounds.position.x, bounds.end.x)
		clamped.y = clampf(clamped.y, bounds.position.y, bounds.end.y)

	var on_screen := target_is_on_screen and target_position.distance_to(clamped) < 2.0
	var pulse := 1.0 + sin(_bounce_time * 5.0) * 0.08
	_target_ring.visible = on_screen
	_target_ring.position = clamped - _target_ring.size * 0.5
	_target_ring.scale = Vector2.ONE * pulse

	# The card already identifies movement controls; a floating arrow is
	# visually misleading because the controls move with the responsive layout.
	_arrow.visible = _ui_target == null
	if not _arrow.visible:
		return
	if on_screen:
		_arrow.position = clamped + Vector2(-_arrow.size.x * 0.5, -92.0 + sin(_bounce_time * 6.0) * 7.0)
		_arrow.rotation = PI * 0.5
	else:
		var direction := clamped - size * 0.5
		_arrow.position = clamped - _arrow.size * 0.5
		_arrow.rotation = direction.angle()


func _movement_copy() -> String:
	if GameControl.is_using_touch():
		return "Use the left stick to move and the right stick to look around. Move a few steps to begin."
	return "Use WASD to move and the mouse to look around. Move a few steps to begin."


func _front_waiter() -> Node3D:
	if _kitchen == null:
		return null
	var queue := _kitchen.get_node_or_null("OrderQueue")
	if queue != null and queue.has_method("get_front_waiter"):
		return queue.call("get_front_waiter") as Node3D
	return null


func _bun_crate() -> Node3D:
	return _kitchen.get_node_or_null("Architecture/crate_buns") as Node3D if _kitchen != null else null


func _cutting_board() -> Node3D:
	return _kitchen.get_node_or_null("Architecture/wall_decorated/cutboard") as Node3D if _kitchen != null else null


func _order_window() -> Node3D:
	return _kitchen.get_node_or_null("Architecture/wall_orderwindow_decorated/order_window") as Node3D if _kitchen != null else null


func _dismiss() -> void:
	var completed := _step == Step.COMPLETE
	_step = Step.DISMISSED
	_armed = false
	visible = false
	if completed:
		tutorial_finished.emit()

