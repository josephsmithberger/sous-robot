extends Node
## Global source of truth for whether the 3D game viewport is currently controllable.

signal controllability_changed(is_controllable: bool)
signal input_mode_changed(input_mode: InputMode)
signal dialogue_activity_changed(is_active: bool)
signal camera_mode_changed(camera_mode: CameraMode)
signal ui_mode_changed(is_ui_mode: bool)
signal interact_available_changed(is_available: bool)
signal interaction_pressed
signal interaction_released
signal interaction_prompt_changed(prompt: String, hold_duration: float)
signal interaction_progress_changed(progress: float)
@warning_ignore("unused_signal")
signal held_item_changed(item: KitchenItem)
@warning_ignore("unused_signal")
signal item_delivered(item: KitchenItem)

enum InputMode {
	KEYBOARD,
	TOUCH,
}

enum CameraMode {
	FIRST_PERSON,
	MARKER,
}

var is_controllable := false:
	set(value):
		if is_controllable == value:
			return
		is_controllable = value
		controllability_changed.emit(is_controllable)

var input_mode: InputMode = InputMode.KEYBOARD:
	set(value):
		if input_mode == value:
			return
		input_mode = value
		input_mode_changed.emit(input_mode)
		_sync_mouse_mode()

var camera_mode := CameraMode.MARKER:
	set(value):
		if camera_mode == value:
			return
		camera_mode = value
		camera_mode_changed.emit(camera_mode)
		_sync_mouse_mode()

var is_ui_mode := true:
	set(value):
		if is_ui_mode == value:
			return
		is_ui_mode = value
		_sync_mouse_mode()
		ui_mode_changed.emit(is_ui_mode)

var can_interact := false:
	set(value):
		if can_interact == value:
			return
		can_interact = value
		interact_available_changed.emit(can_interact)

var move_input := Vector2.ZERO
var look_input := Vector2.ZERO
var interaction_prompt := ""
var interaction_hold_duration := 0.0
var interaction_progress := 0.0

var _controllability_requested := false
var _active_dialogues := 0
var _mouse_look_delta := Vector2.ZERO
var _camera_mode_before_dialogue: CameraMode = CameraMode.FIRST_PERSON
var _ui_mode_before_dialogue := false


func _ready() -> void:
	_ensure_interact_action()
	input_mode = InputMode.TOUCH if DisplayServer.is_touchscreen_available() else InputMode.KEYBOARD
	_sync_mouse_mode()
	_connect_dialogue_manager()


func _ensure_interact_action() -> void:
	if not InputMap.has_action(&"interact"):
		InputMap.add_action(&"interact")
	for event in InputMap.action_get_events(&"interact"):
		if event is InputEventKey and (
			(event as InputEventKey).physical_keycode == KEY_SPACE
			or (event as InputEventKey).keycode == KEY_SPACE
		):
			return
	var space_event := InputEventKey.new()
	space_event.physical_keycode = KEY_SPACE
	InputMap.action_add_event(&"interact", space_event)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if has_player_control():
			_mouse_look_delta += event.relative
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		# Mouse-to-touch emulation is useful for testing joysticks, but it should not
		# make a desktop web player look like a touchscreen device.
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			input_mode = InputMode.TOUCH
	elif event is InputEventKey and event.pressed and not event.echo:
		input_mode = InputMode.KEYBOARD
		if event.keycode == KEY_ESCAPE and _controllability_requested and not is_dialogue_active():
			if is_ui_mode or camera_mode != CameraMode.FIRST_PERSON:
				give_player_control()
			else:
				set_ui_mode(true)
			get_viewport().set_input_as_handled()

	if event.is_action_pressed(&"interact", false):
		request_interaction()
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"interact"):
		cancel_interaction()
		get_viewport().set_input_as_handled()


func request_interaction() -> void:
	if has_player_control() and can_interact:
		interaction_pressed.emit()


func cancel_interaction() -> void:
	interaction_released.emit()
	set_interaction_progress(0.0)


func set_interaction_context(next_prompt: String, next_hold_duration: float = 0.0) -> void:
	var changed := interaction_prompt != next_prompt or not is_equal_approx(interaction_hold_duration, next_hold_duration)
	interaction_prompt = next_prompt
	interaction_hold_duration = next_hold_duration
	can_interact = not interaction_prompt.is_empty()
	if changed:
		interaction_prompt_changed.emit(interaction_prompt, interaction_hold_duration)


func clear_interaction_context() -> void:
	set_interaction_context("")
	set_interaction_progress(0.0)


func set_interaction_progress(progress: float) -> void:
	var next_progress := clampf(progress, 0.0, 1.0)
	if is_equal_approx(interaction_progress, next_progress):
		return
	interaction_progress = next_progress
	interaction_progress_changed.emit(interaction_progress)


func set_controllable(value: bool) -> void:
	_controllability_requested = value
	if not value:
		cancel_interaction()
		set_ui_mode(true)
	_refresh_controllability()


func set_ui_mode(value: bool) -> void:
	if not value and (not _controllability_requested or is_dialogue_active() or camera_mode != CameraMode.FIRST_PERSON):
		value = true
	is_ui_mode = value


func set_camera_mode(value: CameraMode) -> void:
	camera_mode = value
	_sync_mouse_mode()


func give_player_control() -> void:
	if is_dialogue_active():
		return
	set_camera_mode(CameraMode.FIRST_PERSON)
	set_ui_mode(false)
	_camera_mode_before_dialogue = camera_mode
	_ui_mode_before_dialogue = is_ui_mode


func hand_off_control() -> void:
	if is_dialogue_active():
		return
	set_camera_mode(CameraMode.MARKER)
	_camera_mode_before_dialogue = camera_mode
	_ui_mode_before_dialogue = is_ui_mode


func toggle_camera_mode() -> void:
	if is_dialogue_active():
		return
	if camera_mode == CameraMode.FIRST_PERSON:
		set_camera_mode(CameraMode.MARKER)
		set_ui_mode(true)
	else:
		give_player_control()
	_camera_mode_before_dialogue = camera_mode
	_ui_mode_before_dialogue = is_ui_mode


func has_player_control() -> bool:
	return is_controllable and not is_ui_mode and camera_mode == CameraMode.FIRST_PERSON


func set_virtual_input(move: Vector2, look: Vector2) -> void:
	move_input = move
	look_input = look


func get_move_input() -> Vector2:
	var keyboard_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	return (keyboard_input + move_input).limit_length()


func consume_mouse_look_delta() -> Vector2:
	var delta := _mouse_look_delta
	_mouse_look_delta = Vector2.ZERO
	return delta


func is_using_touch() -> bool:
	return input_mode == InputMode.TOUCH


func is_dialogue_active() -> bool:
	return _active_dialogues > 0


func _connect_dialogue_manager() -> void:
	var dialogue_manager := get_node_or_null("/root/DialogueManager")
	if dialogue_manager == null:
		call_deferred(&"_connect_dialogue_manager")
		return

	if not dialogue_manager.dialogue_started.is_connected(_on_dialogue_started):
		dialogue_manager.dialogue_started.connect(_on_dialogue_started)
	if not dialogue_manager.dialogue_ended.is_connected(_on_dialogue_ended):
		dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)


func _on_dialogue_started(_resource: Resource) -> void:
	_active_dialogues += 1
	if _active_dialogues == 1:
		if camera_mode == CameraMode.FIRST_PERSON:
			_camera_mode_before_dialogue = camera_mode
			_ui_mode_before_dialogue = is_ui_mode
		set_camera_mode(CameraMode.MARKER)
		dialogue_activity_changed.emit(true)
	_refresh_controllability()


func _on_dialogue_ended(_resource: Resource) -> void:
	_active_dialogues = maxi(_active_dialogues - 1, 0)
	if _active_dialogues == 0:
		set_camera_mode(_camera_mode_before_dialogue)
		dialogue_activity_changed.emit(false)
	_refresh_controllability()
	if _active_dialogues == 0 and _controllability_requested:
		set_ui_mode(_ui_mode_before_dialogue)


func _refresh_controllability() -> void:
	is_controllable = _controllability_requested and not is_dialogue_active()
	if not is_controllable:
		set_ui_mode(true)
	else:
		_sync_mouse_mode()


func _sync_mouse_mode() -> void:
	var should_capture := (
		input_mode == InputMode.KEYBOARD
		and is_controllable
		and not is_ui_mode
		and camera_mode == CameraMode.FIRST_PERSON
	)
	if not should_capture:
		_mouse_look_delta = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if should_capture else Input.MOUSE_MODE_VISIBLE
