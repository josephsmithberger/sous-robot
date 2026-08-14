extends CharacterBody3D

@export var move_speed := 5.0
@export var look_speed := 2.2
@export var mouse_sensitivity := 0.003

@onready var head: Marker3D = $Head


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
