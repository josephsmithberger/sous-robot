class_name WaiterRobot
extends InteractionArea
## One reusable robot in the visible order queue.

signal departure_finished

const WINDOW_FACING := PI * 0.5

@onready var animation_player: AnimationPlayer = $Robot/AnimationPlayer

var queue_controller: Variant
var order_data: Dictionary = {}
var slot_index := -1
var order_is_accepted := false
var is_moving := false


func _ready() -> void:
	_play(&"idle")


func configure(controller: Variant, next_order: Dictionary, next_slot_index: int) -> void:
	queue_controller = controller
	order_data = next_order
	slot_index = next_slot_index
	order_is_accepted = false
	visible = true
	$Robot.rotation.y = WINDOW_FACING
	_play(&"idle")


func set_order_accepted(value: bool) -> void:
	order_is_accepted = value


func can_interact(_player: Node) -> bool:
	return (
		queue_controller != null
		and not is_moving
		and not order_is_accepted
		and queue_controller.is_front_waiter(self)
	)


func get_interaction_prompt(_player: Node) -> String:
	return "TAKE ORDER"


func interact(_player: Node) -> void:
	if can_interact(_player):
		queue_controller.request_front_dialogue(self)


func move_to_slot(target_position: Vector3, duration: float) -> void:
	is_moving = true
	_play(&"walk")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, ^"position", target_position, duration)
	await tween.finished
	is_moving = false
	_play(&"idle")


func depart(exit_offset: Vector3, duration: float) -> void:
	is_moving = true
	_play(&"jump")
	await get_tree().create_timer(minf(0.35, duration * 0.35)).timeout
	_face_direction(exit_offset)
	_play(&"walk")
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, ^"position", position + exit_offset, duration)
	await tween.finished
	visible = false
	is_moving = false
	departure_finished.emit()


func _face_direction(direction: Vector3) -> void:
	var flat_direction := Vector2(direction.x, direction.z)
	if flat_direction.length_squared() > 0.0001:
		$Robot.rotation.y = atan2(flat_direction.x, flat_direction.y)


func _play(animation_name: StringName) -> void:
	if animation_player != null and animation_player.has_animation(animation_name):
		animation_player.play(animation_name)
