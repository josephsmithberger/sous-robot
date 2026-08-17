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

const BOT_MATERIAL: Material = preload("res://assets/robot_green_material.tres")

@export var move_speed := 5.8
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
var _desired_process_recipe_id: StringName = &""
var _walk_phase := 0.0
var _path_cursor := 0
var _navigation_map := RID()
var _navigation_path := PackedVector3Array()
var _procedural_parts: Dictionary = {}


func _ready() -> void:
	add_to_group(&"bots")
	add_to_group(&"worker_robots")
	# Workers are visual navigation actors, not moving physics obstacles. The
	# navmesh constrains their route, and zero layers prevent them from lifting
	# the player or being blocked differently across desktop and mobile physics.
	collision_layer = 0
	collision_mask = 0
	_apply_bot_material()
	_find_animation_player()
	_cache_procedural_animation_parts()
	_play_anim(&"idle")
	if nav_agent != null:
		nav_agent.path_desired_distance = 0.4
		nav_agent.target_desired_distance = 0.6
		# Runtime-baked kitchen paths sit 0.5 above actor feet. Offset returned
		# path points to the same floor height as the worker root.
		nav_agent.path_height_offset = 0.5
		nav_agent.path_max_distance = 2.0
		nav_agent.avoidance_enabled = false


func _apply_bot_material() -> void:
	if BOT_MATERIAL == null:
		return
	var robot_node := get_node_or_null("Robot")
	if robot_node == null:
		return
	for child in robot_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := child as MeshInstance3D
		if mesh_inst != null:
			mesh_inst.material_override = BOT_MATERIAL


func _find_animation_player() -> void:
	if _anim_player != null:
		return
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if GameControl.is_robot_pathfinding_paused():
		_pose_part(&"leg-left", 0.0, delta)
		_pose_part(&"leg-right", 0.0, delta)
		_pose_part(&"arm-left", 0.0, delta)
		_pose_part(&"arm-right", 0.0, delta)
		return
	_update_procedural_animation(delta)


func _physics_process(delta: float) -> void:
	velocity.y = 0.0

	if GameControl.is_robot_pathfinding_paused():
		velocity.x = 0.0
		velocity.z = 0.0
		_play_anim(&"idle")
		return

	match _state:
		State.DESPAWNING:
			velocity = Vector3.ZERO

		State.INTERACTING:
			velocity = Vector3.ZERO
			if current_target_area != null and is_instance_valid(current_target_area):
				_look_at_xz(current_target_area.global_position, delta)
			_interaction_elapsed += delta
			if _interaction_elapsed >= _required_hold_duration:
				_complete_interaction()

		State.NAVIGATING:
			_process_navigation(delta)
			# Navigation supplies a collision-free horizontal path. Moving directly
			# keeps identical behavior across desktop and mobile physics backends.
			global_position += Vector3(velocity.x, 0.0, velocity.z) * delta

		State.IDLE:
			velocity = Vector3.ZERO
			_play_anim(&"idle")


func _process_navigation(delta: float) -> void:
	if nav_agent == null:
		_state = State.IDLE
		return

	var flat_to_target := Vector2(
		global_position.x - _target_position.x,
		global_position.z - _target_position.z
	).length()
	if flat_to_target <= nav_agent.target_desired_distance:
		_on_target_reached()
		return

	# Use the path synchronously validated by NavigationServer3D at dispatch time.
	# NavigationAgent3D may expose an empty internal path for much longer on iOS.
	var navigation_path := _navigation_path
	if navigation_path.is_empty():
		navigation_path = nav_agent.get_current_navigation_path()
	var next_pos := _target_position
	if not navigation_path.is_empty():
		_path_cursor = mini(_path_cursor, navigation_path.size() - 1)
		while _path_cursor < navigation_path.size():
			var point := navigation_path[_path_cursor]
			var flat_to_point := Vector2(
				global_position.x - point.x,
				global_position.z - point.z
			).length()
			if flat_to_point > nav_agent.path_desired_distance:
				next_pos = point
				break
			_path_cursor += 1
		if _path_cursor >= navigation_path.size():
			next_pos = _target_position

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
	_navigation_path = PackedVector3Array()
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


func set_navigation_map(nav_map: RID) -> void:
	_navigation_map = nav_map
	if nav_agent != null:
		nav_agent.set_navigation_map(nav_map)


func _cache_navigation_path() -> void:
	_navigation_path = PackedVector3Array()
	var nav_map := _navigation_map
	if not nav_map.is_valid() and nav_agent != null:
		nav_map = nav_agent.get_navigation_map()
	if not nav_map.is_valid():
		var world := get_world_3d()
		nav_map = world.navigation_map if world != null else RID()
	if (
		not nav_map.is_valid()
		or not NavigationServer3D.map_is_active(nav_map)
		or NavigationServer3D.map_get_iteration_id(nav_map) == 0
	):
		return
	var nav_start := NavigationServer3D.map_get_closest_point(nav_map, global_position)
	var nav_target := NavigationServer3D.map_get_closest_point(nav_map, _target_position)
	_navigation_path = NavigationServer3D.map_get_path(nav_map, nav_start, nav_target, true)


func dispatch_to(target_area: InteractionArea, process_recipe_id: StringName = &"") -> void:
	if target_area == null or not is_instance_valid(target_area):
		return
	dispatch_to_position(
		target_area,
		target_area.get_interaction_position(global_position),
		process_recipe_id
	)


func dispatch_to_position(
	target_area: InteractionArea,
	target_position: Vector3,
	process_recipe_id: StringName = &""
) -> void:
	if target_area == null or not is_instance_valid(target_area):
		return
	_desired_process_recipe_id = process_recipe_id
	_path_cursor = 0
	current_target_area = target_area
	_target_position = target_position
	_cache_navigation_path()
	if nav_agent != null:
		nav_agent.target_position = _target_position
	_state = State.NAVIGATING


func navigate_to_position(target_pos: Vector3) -> void:
	_desired_process_recipe_id = &""
	_path_cursor = 0
	current_target_area = null
	_target_position = target_pos
	_cache_navigation_path()
	if nav_agent != null:
		nav_agent.target_position = _target_position
	_state = State.NAVIGATING


func stop_navigation() -> void:
	_desired_process_recipe_id = &""
	_navigation_path = PackedVector3Array()
	current_target_area = null
	_state = State.IDLE
	velocity = Vector3.ZERO
	_play_anim(&"idle")


func get_state() -> State:
	return _state


func get_desired_process_recipe_id() -> StringName:
	return _desired_process_recipe_id


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
		if hand != null and _held_item_visual.get_parent() == hand:
			hand.remove_child(_held_item_visual)
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
	# The imported robot model faces +Z (its face and hand are on that side).
	var target_yaw := atan2(diff.x, diff.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, rotation_speed * delta)


func _play_anim(anim_name: StringName) -> void:
	if _anim_player == null:
		_find_animation_player()
	if _anim_player != null and _anim_player.has_animation(anim_name):
		if _anim_player.current_animation != String(anim_name) or not _anim_player.is_playing():
			_anim_player.play(anim_name)


func _cache_procedural_animation_parts() -> void:
	if _anim_player != null and _anim_player.has_animation(&"walk") and _anim_player.has_animation(&"idle"):
		return
	var names := [&"leg-left", &"leg-right", &"arm-left", &"arm-right", &"torso"]
	for part_name: StringName in names:
		var part := find_child(String(part_name), true, false) as Node3D
		if part != null:
			_procedural_parts[part_name] = {
				"node": part,
				"rotation": part.rotation,
				"position": part.position,
			}


func _update_procedural_animation(delta: float) -> void:
	if _procedural_parts.is_empty():
		return
	var moving := _state == State.NAVIGATING and Vector2(velocity.x, velocity.z).length() > 0.1
	if moving:
		_walk_phase += delta * move_speed * 3.0
	var stride: float = sin(_walk_phase) * 0.55 if moving else 0.0
	var bounce: float = abs(sin(_walk_phase * 2.0)) * 0.035 if moving else 0.0
	_pose_part(&"leg-left", stride, delta)
	_pose_part(&"leg-right", -stride, delta)
	_pose_part(&"arm-left", -stride * 0.7, delta)
	_pose_part(&"arm-right", stride * 0.7, delta)
	var torso_data: Dictionary = _procedural_parts.get(&"torso", {})
	if not torso_data.is_empty():
		var torso := torso_data["node"] as Node3D
		var base_pos := torso_data["position"] as Vector3
		torso.position = torso.position.lerp(base_pos + Vector3(0.0, bounce, 0.0), minf(delta * 14.0, 1.0))


func _pose_part(part_name: StringName, x_offset: float, delta: float) -> void:
	var data: Dictionary = _procedural_parts.get(part_name, {})
	if data.is_empty():
		return
	var part := data["node"] as Node3D
	var base_rotation := data["rotation"] as Vector3
	var target := base_rotation
	target.x += x_offset
	part.rotation = part.rotation.lerp(target, minf(delta * 14.0, 1.0))


# --- Despawn / Smoke Effect ---

func despawn(fade_duration: float = 0.8) -> void:
	_state = State.DESPAWNING
	if smoke_particles != null:
		smoke_particles.emitting = true

	if get_parent() != null:
		SmokePuff.create_at(global_position + Vector3(0.0, 0.4, 0.0), get_parent())

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, ^"scale", Vector3(0.01, 0.01, 0.01), fade_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		despawn_completed.emit()
		queue_free()
	)
