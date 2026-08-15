extends CharacterBody3D

@export var move_speed := 5.0
@export var look_speed := 2.2
@export var mouse_sensitivity := 0.003
@export var idle_bob_speed := 1.0
@export var walk_bob_speed := 2.4

@onready var head: Marker3D = $Head
@onready var hand: Marker3D = $Head/Hand
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var interaction_area: Area3D = $InteractionArea

var held_item: KitchenItem
var _held_item_visual: Node3D
var _overlapping_areas: Array[InteractionArea] = []
var _active_interaction: InteractionArea
var _interaction_is_held := false
var _interaction_elapsed := 0.0


func _ready() -> void:
	interaction_area.area_entered.connect(_on_area_entered)
	interaction_area.area_exited.connect(_on_area_exited)
	GameControl.interaction_pressed.connect(_on_interaction_pressed)
	GameControl.interaction_released.connect(_on_interaction_released)
	if animation_player != null and animation_player.has_animation(&"bob"):
		animation_player.play(&"bob")
		animation_player.speed_scale = idle_bob_speed


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
	_update_hand_bob(delta)
	_update_interaction_target()
	_update_held_interaction(delta)


func _update_hand_bob(delta: float) -> void:
	if animation_player == null:
		return
	if not animation_player.is_playing() and animation_player.has_animation(&"bob"):
		animation_player.play(&"bob")

	var is_moving := is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.1
	var target_speed := walk_bob_speed if is_moving else idle_bob_speed
	animation_player.speed_scale = move_toward(animation_player.speed_scale, target_speed, delta * 4.0)


func _apply_look(amount: Vector2) -> void:
	rotate_y(-amount.x)
	head.rotation.x = clamp(head.rotation.x - amount.y, -PI * 0.45, PI * 0.45)


func has_held_item() -> bool:
	return held_item != null


func get_held_item() -> KitchenItem:
	return held_item


func is_holding(item_id: StringName) -> bool:
	return held_item != null and held_item.item_id == item_id


func set_held_item(item: KitchenItem) -> void:
	if is_instance_valid(_held_item_visual):
		_held_item_visual.queue_free()
		_held_item_visual = null

	held_item = item
	if held_item != null and held_item.held_scene != null:
		var visual := held_item.held_scene.instantiate() as Node3D
		if visual != null:
			hand.add_child(visual)
			visual.transform = Transform3D.IDENTITY
			_disable_held_collisions(visual)
			_held_item_visual = visual

	GameControl.held_item_changed.emit(held_item)
	_update_interaction_target(true)


func take_held_item() -> KitchenItem:
	var item := held_item
	set_held_item(null)
	return item


func _disable_held_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	for child in node.get_children():
		_disable_held_collisions(child)


func _on_area_entered(area: Area3D) -> void:
	if area is InteractionArea and not _overlapping_areas.has(area):
		_overlapping_areas.append(area)
		_update_interaction_target(true)


func _on_area_exited(area: Area3D) -> void:
	if area is InteractionArea:
		_overlapping_areas.erase(area)
		_update_interaction_target(true)


func _update_interaction_target(force_update := false) -> void:
	# Keep a valid hold locked to its original appliance. Area overlap events can
	# jitter at collision boundaries, but they must not restart the action.
	if (
		_interaction_is_held
		and is_instance_valid(_active_interaction)
		and _overlapping_areas.has(_active_interaction)
		and _active_interaction.can_interact(self)
	):
		return

	var nearest: InteractionArea
	var nearest_distance := INF
	for area in _overlapping_areas.duplicate():
		if not is_instance_valid(area):
			_overlapping_areas.erase(area)
			continue
		if not area.can_interact(self):
			continue
		var distance := global_position.distance_squared_to(area.global_position)
		if distance < nearest_distance:
			nearest = area
			nearest_distance = distance

	if nearest == _active_interaction:
		if force_update and nearest != null:
			GameControl.set_interaction_context(
				nearest.get_interaction_prompt(self),
				nearest.get_interaction_hold_duration(self)
			)
		return
	_cancel_held_interaction()
	_active_interaction = nearest
	if _active_interaction == null:
		GameControl.clear_interaction_context()
	else:
		GameControl.set_interaction_context(
			_active_interaction.get_interaction_prompt(self),
			_active_interaction.get_interaction_hold_duration(self)
		)


func _on_interaction_pressed() -> void:
	_update_interaction_target()
	if _active_interaction == null or not _active_interaction.can_interact(self):
		return
	var duration := _active_interaction.get_interaction_hold_duration(self)
	if duration <= 0.0:
		_complete_interaction()
		return
	_interaction_is_held = true
	_interaction_elapsed = 0.0
	GameControl.set_interaction_progress(0.0)


func _on_interaction_released() -> void:
	_cancel_held_interaction()


func _update_held_interaction(delta: float) -> void:
	if not _interaction_is_held:
		return
	if _active_interaction == null or not is_instance_valid(_active_interaction) or not _active_interaction.can_interact(self):
		_cancel_held_interaction()
		_update_interaction_target(true)
		return

	var duration := _active_interaction.get_interaction_hold_duration(self)
	_interaction_elapsed += delta
	GameControl.set_interaction_progress(_interaction_elapsed / duration)
	if _interaction_elapsed >= duration:
		_complete_interaction()


func _complete_interaction() -> void:
	var target := _active_interaction
	_cancel_held_interaction()
	if target != null and is_instance_valid(target) and target.can_interact(self):
		target.interact(self)
	_update_interaction_target(true)


func _cancel_held_interaction() -> void:
	_interaction_is_held = false
	_interaction_elapsed = 0.0
	GameControl.set_interaction_progress(0.0)


func _exit_tree() -> void:
	GameControl.clear_interaction_context()
