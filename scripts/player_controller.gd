extends CharacterBody3D

@export var move_speed := 5.0
@export var look_speed := 2.2
@export var mouse_sensitivity := 0.003

@onready var head: Marker3D = $Head
@onready var interaction_area: Area3D = $InteractionArea

var _overlapping_areas := 0


func _ready() -> void:
	interaction_area.area_entered.connect(_on_area_entered)
	interaction_area.area_exited.connect(_on_area_exited)


func _physics_process(delta: float) -> void:
	var can_move := GameControl.has_player_control()
	var input_vector := GameControl.get_move_input() if can_move else Vector2.ZERO
	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if not is_on_floor():
		velocity += get_gravity() * delta

	if can_move:
		_apply_look(GameControl.look_input * look_speed * delta)
		_apply_look(GameControl.consume_mouse_look_delta() * mouse_sensitivity)

	move_and_slide()


func _apply_look(amount: Vector2) -> void:
	rotate_y(-amount.x)
	head.rotation.x = clamp(head.rotation.x - amount.y, -PI * 0.45, PI * 0.45)


func _on_area_entered(_area: Area3D) -> void:
	_overlapping_areas += 1
	GameControl.can_interact = true


func _on_area_exited(_area: Area3D) -> void:
	_overlapping_areas = maxi(_overlapping_areas - 1, 0)
	GameControl.can_interact = _overlapping_areas > 0


func _exit_tree() -> void:
	GameControl.can_interact = false
