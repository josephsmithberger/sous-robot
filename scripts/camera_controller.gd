extends Camera3D

const FIRST_PERSON_FOV := 80.0
const MARKER_FOV := 60.0

@export var transition_duration := 0.8

@onready var first_person_target: Node3D = $"../player/Head"
@onready var marker_target: Marker3D = $"../Marker3D"

var _transition: Tween


func _ready() -> void:
	current = true
	GameControl.camera_mode_changed.connect(_move_to_mode)
	_snap_to_mode(GameControl.camera_mode)


func _process(_delta: float) -> void:
	if _transition == null and GameControl.camera_mode == GameControl.CameraMode.FIRST_PERSON:
		global_transform = first_person_target.global_transform


func _move_to_mode(mode: GameControl.CameraMode) -> void:
	if _transition:
		_transition.kill()

	var start_transform := global_transform
	var target_transform := _target_for(mode).global_transform
	var target_fov := FIRST_PERSON_FOV if mode == GameControl.CameraMode.FIRST_PERSON else MARKER_FOV

	_transition = create_tween().set_parallel(true)
	_transition.set_trans(Tween.TRANS_CUBIC)
	_transition.set_ease(Tween.EASE_IN_OUT)
	_transition.tween_method(
		func(weight: float) -> void:
			global_transform = start_transform.interpolate_with(target_transform, weight),
		0.0,
		1.0,
		transition_duration
	)
	_transition.tween_property(self, ^"fov", target_fov, transition_duration)
	_transition.finished.connect(func() -> void: _transition = null)


func _snap_to_mode(mode: GameControl.CameraMode) -> void:
	global_transform = _target_for(mode).global_transform
	fov = FIRST_PERSON_FOV if mode == GameControl.CameraMode.FIRST_PERSON else MARKER_FOV


func _target_for(mode: GameControl.CameraMode) -> Node3D:
	return first_person_target if mode == GameControl.CameraMode.FIRST_PERSON else marker_target
