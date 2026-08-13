extends Node
## Adds native touchscreen behavior to desktop-style Controls without generating
## InputEventMouse events. Gameplay touch handlers (such as virtual joysticks)
## continue to receive their original InputEventScreenTouch/Drag events.

const DRAG_THRESHOLD_SQUARED := 64.0

var _touches: Dictionary = {}
var _claimed_touch_indices: Dictionary = {}
var _wired_controls: Dictionary = {}


func _ready() -> void:
	Input.emulate_mouse_from_touch = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	_wire_branch(get_tree().root)



func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Use this in project-specific gui_input handlers that should respond to either
## a physical left click or a real touchscreen press.
func is_primary_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	return (
		event is InputEventScreenTouch
		and event.pressed
		and event.device != InputEvent.DEVICE_ID_EMULATION
	)


## Call this when a custom Control handles a native touch itself. This prevents
## the general adapter from also activating that touch when the finger lifts.
func claim_touch(event: InputEvent) -> void:
	if event is not InputEventScreenTouch or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event.pressed:
		_claimed_touch_indices[event.index] = true
		_touches.erase(event.index)
	else:
		_claimed_touch_indices.erase(event.index)


func _on_node_added(node: Node) -> void:
	_wire_branch.call_deferred(node)


func _wire_branch(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is Control:
		_wire_control(node)
	for child in node.get_children(true):
		_wire_branch(child)


func _wire_control(control: Control) -> void:
	var instance_id := control.get_instance_id()
	if _wired_controls.has(instance_id):
		return
	_wired_controls[instance_id] = true
	var gui_input_callback := _on_control_gui_input.bind(control)
	if not control.gui_input.is_connected(gui_input_callback):
		control.gui_input.connect(gui_input_callback)
	var exit_callback := _on_control_tree_exited.bind(instance_id)
	if not control.tree_exited.is_connected(exit_callback):
		control.tree_exited.connect(exit_callback, CONNECT_ONE_SHOT)


func _on_control_tree_exited(instance_id: int) -> void:
	_wired_controls.erase(instance_id)


func _on_control_gui_input(event: InputEvent, source: Control) -> void:
	# Mouse-generated test touches arrive alongside the original mouse event. The
	# mouse event already drives Controls, so handling those touches would double-fire.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return

	# A SubViewportContainer owns coordinate conversion and delivery to its child
	# viewport. Treating it as a focusable UI target steals native touch from the
	# controls inside that viewport.
	if source is SubViewportContainer:
		return

	if event is InputEventScreenTouch and _claimed_touch_indices.has(event.index):
		if not event.pressed:
			_claimed_touch_indices.erase(event.index)
		return
	if event is InputEventScreenDrag and _claimed_touch_indices.has(event.index):
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_touch(event, source)
		else:
			_end_touch(event, source)
	elif event is InputEventScreenDrag:
		_drag_touch(event, source)


func _begin_touch(event: InputEventScreenTouch, source: Control) -> void:
	if _touches.has(event.index):
		return

	var viewport_position := _to_viewport_position(source, event.position)
	var target := _find_activation_target(source)
	var scroll_container := _find_scroll_container(source)
	if target == null and scroll_container == null:
		return
	if target is BaseButton and target.disabled:
		target = null

	_touches[event.index] = {
		"target": target,
		"scroll": scroll_container,
		"start_position": viewport_position,
		"last_position": viewport_position,
		"dragged": false,
		"activated": false,
	}

	if target is BaseButton:
		_focus_if_possible(target)
		target.button_down.emit()
		if target.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS:
			_activate_button(target)
			_touches[event.index]["activated"] = true
	elif target is Slider:
		_set_slider_from_touch(target, viewport_position)

	source.accept_event()


func _drag_touch(event: InputEventScreenDrag, source: Control) -> void:
	if not _touches.has(event.index):
		return

	var state: Dictionary = _touches[event.index]
	var viewport_position := _to_viewport_position(source, event.position)
	var viewport_relative: Vector2 = viewport_position - state["last_position"]
	state["last_position"] = viewport_position
	if viewport_position.distance_squared_to(state["start_position"]) >= DRAG_THRESHOLD_SQUARED:
		state["dragged"] = true

	var target: Control = state["target"]
	if target is Slider and is_instance_valid(target):
		_set_slider_from_touch(target, viewport_position)
	else:
		var scroll_container: ScrollContainer = state["scroll"]
		if is_instance_valid(scroll_container):
			scroll_container.scroll_horizontal -= roundi(viewport_relative.x)
			scroll_container.scroll_vertical -= roundi(viewport_relative.y)

	source.accept_event()


func _end_touch(event: InputEventScreenTouch, source: Control) -> void:
	if not _touches.has(event.index):
		return

	var state: Dictionary = _touches[event.index]
	var viewport_position := _to_viewport_position(source, event.position)
	_touches.erase(event.index)
	var target: Control = state["target"]
	if not is_instance_valid(target):
		source.accept_event()
		return

	if target is BaseButton:
		target.button_up.emit()
		if (
			not state["activated"]
			and not state["dragged"]
			and _control_contains_point(target, viewport_position)
		):
			_activate_button(target)
	elif target is TabBar:
		if not state["dragged"]:
			_activate_tab(target, viewport_position)
	elif target is LineEdit or target is TextEdit:
		if not state["dragged"]:
			_focus_if_possible(target)
	elif target is Slider:
		_set_slider_from_touch(target, viewport_position)

	source.accept_event()


func _find_activation_target(source: Control) -> Control:
	var current: Node = source
	while current is Control:
		if current is BaseButton or current is TabBar or current is Slider:
			return current
		if current is LineEdit or current is TextEdit:
			return current
		current = current.get_parent()
	# Custom focusable Controls own their gui_input. Guessing how to activate them
	# steals events from controls such as the dialogue balloon.
	return null


func _find_scroll_container(source: Control) -> ScrollContainer:
	var current: Node = source
	while current is Control:
		if current is ScrollContainer:
			return current
		current = current.get_parent()
	return null


func _activate_button(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	if button.toggle_mode:
		var should_press := not button.button_pressed
		if button.button_group != null and button.button_pressed and not button.button_group.allow_unpress:
			should_press = true
		button.button_pressed = should_press
	if button.has_method(&"_pressed"):
		button.call(&"_pressed")
	button.pressed.emit()


func _activate_tab(tab_bar: TabBar, viewport_position: Vector2) -> void:
	var local_position := tab_bar.get_global_transform_with_canvas().affine_inverse() * viewport_position
	for tab_index in range(tab_bar.tab_count):
		if tab_bar.is_tab_disabled(tab_index) or tab_bar.is_tab_hidden(tab_index):
			continue
		if tab_bar.get_tab_rect(tab_index).has_point(local_position):
			tab_bar.current_tab = tab_index
			tab_bar.tab_clicked.emit(tab_index)
			return


func _focus_if_possible(control: Control) -> void:
	if control.focus_mode != Control.FOCUS_NONE:
		control.grab_focus()


func _to_viewport_position(source: Control, local_position: Vector2) -> Vector2:
	return source.get_global_transform_with_canvas() * local_position


func _set_slider_from_touch(slider: Slider, viewport_position: Vector2) -> void:
	var local_position := slider.get_global_transform_with_canvas().affine_inverse() * viewport_position
	var ratio: float
	if slider is VSlider:
		ratio = 1.0 - clampf(local_position.y / maxf(slider.size.y, 1.0), 0.0, 1.0)
	else:
		ratio = clampf(local_position.x / maxf(slider.size.x, 1.0), 0.0, 1.0)
	slider.value = lerpf(slider.min_value, slider.max_value, ratio)


func _control_contains_point(control: Control, viewport_position: Vector2) -> bool:
	var local_position := control.get_global_transform_with_canvas().affine_inverse() * viewport_position
	return Rect2(Vector2.ZERO, control.size).has_point(local_position)
