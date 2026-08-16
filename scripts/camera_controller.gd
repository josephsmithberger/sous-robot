extends Camera3D

const FIRST_PERSON_FOV := 80.0
const MARKER_FOV := 60.0
const WAITER_FOV := 50.0

@export var transition_duration := 0.6

@onready var first_person_target: Node3D = $"../player/Head"
@onready var marker_target: Marker3D = $"../Marker3D"
@onready var waiter_target: Marker3D = $"../WaiterCameraMarker"

var _transition: Tween


func _ready() -> void:
	current = true
	GameControl.camera_mode_changed.connect(_move_to_mode)
	_snap_to_mode(GameControl.camera_mode)


func _process(_delta: float) -> void:
	if _transition == null and GameControl.camera_mode == GameControl.CameraMode.FIRST_PERSON and first_person_target != null:
		global_transform = first_person_target.global_transform


func _move_to_mode(mode: GameControl.CameraMode) -> void:
	if _transition:
		_transition.kill()

	var start_transform := global_transform
	var target_node := _target_for(mode)
	if target_node == null:
		return
	var target_fov := _target_fov_for(mode)

	_transition = create_tween().set_parallel(true)
	_transition.set_trans(Tween.TRANS_CUBIC)
	_transition.set_ease(Tween.EASE_IN_OUT)
	_transition.tween_method(
		func(weight: float) -> void:
			global_transform = start_transform.interpolate_with(target_node.global_transform, weight),
		0.0,
		1.0,
		transition_duration
	)
	_transition.tween_property(self, ^"fov", target_fov, transition_duration)
	_transition.finished.connect(func() -> void: _transition = null)


func _snap_to_mode(mode: GameControl.CameraMode) -> void:
	var target_node := _target_for(mode)
	if target_node != null:
		global_transform = target_node.global_transform
	fov = _target_fov_for(mode)


func _target_for(mode: GameControl.CameraMode) -> Node3D:
	match mode:
		GameControl.CameraMode.FIRST_PERSON:
			return first_person_target
		GameControl.CameraMode.MARKER:
			return marker_target
		GameControl.CameraMode.WAITER:
			if waiter_target != null and is_instance_valid(waiter_target):
				return waiter_target
			var fallback_waiter := _find_fallback_waiter_target()
			if fallback_waiter != null:
				return fallback_waiter
			return first_person_target if first_person_target != null else marker_target
		_:
			return marker_target


func _target_fov_for(mode: GameControl.CameraMode) -> float:
	match mode:
		GameControl.CameraMode.FIRST_PERSON:
			return FIRST_PERSON_FOV
		GameControl.CameraMode.MARKER:
			return MARKER_FOV
		GameControl.CameraMode.WAITER:
			return WAITER_FOV
		_:
			return MARKER_FOV


func _find_fallback_waiter_target() -> Node3D:
	var queue := get_node_or_null("../OrderQueue")
	if queue != null and queue.has_method(&"get_front_waiter"):
		var front_waiter = queue.get_front_waiter()
		if front_waiter != null:
			return front_waiter
	return null
