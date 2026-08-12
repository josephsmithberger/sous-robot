extends Node
## Global source of truth for whether the 3D game viewport is currently controllable.

signal controllability_changed(is_controllable: bool)
signal input_mode_changed(input_mode: InputMode)
signal dialogue_activity_changed(is_active: bool)
signal camera_mode_changed(camera_mode: CameraMode)

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

var camera_mode := CameraMode.FIRST_PERSON:
	set(value):
		if camera_mode == value:
			return
		camera_mode = value
		camera_mode_changed.emit(camera_mode)

var move_input := Vector2.ZERO
var look_input := Vector2.ZERO

var _controllability_requested := false
var _active_dialogues := 0


func _ready() -> void:
	input_mode = InputMode.TOUCH if DisplayServer.is_touchscreen_available() else InputMode.KEYBOARD
	_connect_dialogue_manager.call_deferred()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# Mouse-to-touch emulation is useful for testing joysticks, but it should not
		# make a desktop web player look like a touchscreen device.
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			input_mode = InputMode.TOUCH
	elif event is InputEventKey and event.pressed and not event.echo:
		input_mode = InputMode.KEYBOARD


func set_controllable(value: bool) -> void:
	_controllability_requested = value
	_refresh_controllability()


func set_camera_mode(value: CameraMode) -> void:
	camera_mode = value


func give_player_control() -> void:
	set_camera_mode(CameraMode.FIRST_PERSON)


func hand_off_control() -> void:
	set_camera_mode(CameraMode.MARKER)


func toggle_camera_mode() -> void:
	set_camera_mode(
		CameraMode.MARKER
		if camera_mode == CameraMode.FIRST_PERSON
		else CameraMode.FIRST_PERSON
	)


func has_player_control() -> bool:
	return is_controllable and camera_mode == CameraMode.FIRST_PERSON


func set_virtual_input(move: Vector2, look: Vector2) -> void:
	move_input = move
	look_input = look


func get_move_input() -> Vector2:
	var keyboard_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	return (keyboard_input + move_input).limit_length()


func is_using_touch() -> bool:
	return input_mode == InputMode.TOUCH


func is_dialogue_active() -> bool:
	return _active_dialogues > 0


func _connect_dialogue_manager() -> void:
	var dialogue_manager := get_node_or_null("/root/DialogueManager")
	if dialogue_manager == null:
		push_error("DialogueManager autoload is missing")
		return

	dialogue_manager.connect(&"dialogue_started", _on_dialogue_started)
	dialogue_manager.connect(&"dialogue_ended", _on_dialogue_ended)


func _on_dialogue_started(_resource: Resource) -> void:
	_active_dialogues += 1
	if _active_dialogues == 1:
		dialogue_activity_changed.emit(true)
	_refresh_controllability()


func _on_dialogue_ended(_resource: Resource) -> void:
	_active_dialogues = maxi(_active_dialogues - 1, 0)
	if _active_dialogues == 0:
		dialogue_activity_changed.emit(false)
	_refresh_controllability()


func _refresh_controllability() -> void:
	is_controllable = _controllability_requested and not is_dialogue_active()
