@tool
class_name BotWorker
extends CharacterBody3D
## Autonomous kitchen worker robot with NavigationAgent3D pathfinding, item handling,
## station interaction execution, and visual effects.

enum State {
	IDLE,
	NAVIGATING,
	INTERACTING,
	DESPAWNING,
}

signal destination_reached(target_area: InteractionArea)
signal interaction_completed(target_area: InteractionArea)
signal item_held_changed(item: KitchenItem)
signal despawn_completed

@export var move_speed := 3.5
@export var rotation_speed := 10.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var hand: Marker3D = $Hand
@onready var smoke_particles: GPUParticles3D = get_node_or_null("SmokeParticles")

var held_item: KitchenItem
var current_target_area: InteractionArea

var _state: State = State.IDLE
var _target_position := Vector3.ZERO
var _interaction_elapsed := 0.0
var _required_hold_duration := 0.0
var _held_item_visual: Node3D
var _anim_player: AnimationPlayer


func _ready() -> void:
	add_to_group(&"bots")
	add_to_group(&"worker_robots")
	_find_animation_player()
	_play_anim(&"idle")
	if nav_agent != null:
		nav_agent.path_desired_distance = 0.4
		nav_agent.target_desired_distance = 0.6
		nav_agent.path_max_distance = 2.0
		nav_agent.avoidance_enabled = false


func _find_animation_player() -> void:
	if _anim_player != null:
		return
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	match _state:
		State.DESPAWNING:
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			return

		State.INTERACTING:
			velocity.x = 0.0
			velocity.z = 0.0
			if current_target_area != null and is_instance_valid(current_target_area):
				_look_at_xz(current_target_area.global_position, delta)
			_interaction_elapsed += delta
			if _interaction_elapsed >= _required_hold_duration:
				_complete_interaction()
			move_and_slide()
			return

		State.NAVIGATING:
			_process_navigation(delta)

		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, move_speed * 5.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, move_speed * 5.0 * delta)
			_play_anim(&"idle")

	move_and_slide()


func _process_navigation(delta: float) -> void:
	if nav_agent == null:
		_state = State.IDLE
		return

	var dist_to_target := global_position.distance_to(_target_position)
	var is_reached := (
		nav_agent.is_navigation_finished()
		or nav_agent.is_target_reached()
		or dist_to_target <= nav_agent.target_desired_distance
	)

	if is_reached:
		_on_target_reached()
		return

	var next_pos := nav_agent.get_next_path_position()
	var move_dir := next_pos - global_position
	move_dir.y = 0.0

	if move_dir.length_squared() > 0.001:
		move_dir = move_dir.normalized()
		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed
		_look_at_xz(global_position + move_dir, delta)
		_play_anim(&"walk")
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_play_anim(&"idle")


func _on_target_reached() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var target_area := current_target_area
	destination_reached.emit(target_area)

	if target_area != null and is_instance_valid(target_area):
		_look_at_xz(target_area.global_position, 1.0)
		if target_area.can_interact(self):
			_required_hold_duration = target_area.get_interaction_hold_duration(self)
			if _required_hold_duration <= 0.0:
				_complete_interaction()
			else:
				_state = State.INTERACTING
				_interaction_elapsed = 0.0
				_play_anim(&"idle")
		else:
			_state = State.IDLE
			_play_anim(&"idle")
	else:
		_state = State.IDLE
		_play_anim(&"idle")


func _complete_interaction() -> void:
	var target := current_target_area
	_state = State.IDLE
	_interaction_elapsed = 0.0
	_play_anim(&"idle")
	if target != null and is_instance_valid(target) and target.can_interact(self):
		target.interact(self)
		interaction_completed.emit(target)


func dispatch_to(target_area: InteractionArea) -> void:
	if target_area == null or not is_instance_valid(target_area):
		return
	current_target_area = target_area
	_target_position = target_area.get_interaction_position(global_position)
	if nav_agent != null:
		nav_agent.target_position = _target_position
	_state = State.NAVIGATING


func navigate_to_position(target_pos: Vector3) -> void:
	current_target_area = null
	_target_position = target_pos
	if nav_agent != null:
		nav_agent.target_position = _target_position
	_state = State.NAVIGATING


func stop_navigation() -> void:
	current_target_area = null
	_state = State.IDLE
	velocity = Vector3.ZERO
	_play_anim(&"idle")


func get_state() -> State:
	return _state


func is_navigating() -> bool:
	return _state == State.NAVIGATING


func is_interacting() -> bool:
	return _state == State.INTERACTING


# --- Item Holding Interface (matches PlayerController contract) ---

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
	if held_item != null and held_item.held_scene != null and hand != null:
		var visual := held_item.held_scene.instantiate() as Node3D
		if visual != null:
			hand.add_child(visual)
			visual.transform = Transform3D.IDENTITY
			_disable_held_collisions(visual)
			_held_item_visual = visual

	item_held_changed.emit(held_item)


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


func _look_at_xz(target_pos: Vector3, delta: float) -> void:
	var diff := target_pos - global_position
	diff.y = 0.0
	if diff.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-diff.x, -diff.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, rotation_speed * delta)


func _play_anim(anim_name: StringName) -> void:
	if _anim_player == null:
		_find_animation_player()
	if _anim_player != null and _anim_player.has_animation(anim_name):
		if _anim_player.current_animation != String(anim_name) or not _anim_player.is_playing():
			_anim_player.play(anim_name)


# --- Despawn / Smoke Effect ---

func despawn(fade_duration: float = 0.8) -> void:
	_state = State.DESPAWNING
	if smoke_particles != null:
		smoke_particles.emitting = true

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, ^"scale", Vector3(0.01, 0.01, 0.01), fade_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		despawn_completed.emit()
		queue_free()
	)
