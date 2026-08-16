class_name WaiterRobot
extends InteractionArea
## One reusable robot in the visible order queue.

signal departure_finished
signal reaction_changed(reaction: StringName)

const WINDOW_FACING := PI * 0.5
const REACTION_HAPPY: StringName = &"happy"
const REACTION_NORMAL: StringName = &"normal"
const REACTION_ANGRY: StringName = &"angry"
const REACTION_COLORS := {
	REACTION_HAPPY: Color(0.35, 1.0, 0.45),
	REACTION_NORMAL: Color(1.0, 0.84, 0.26),
	REACTION_ANGRY: Color(1.0, 0.25, 0.2),
}

@onready var animation_player: AnimationPlayer = $Robot/AnimationPlayer

@export var look_target_offset := Vector3(0.0, 1.35, 0.0)
@export var turn_speed := 7.5

var queue_controller: Variant
var order_data: Dictionary = {}
var slot_index := -1
var order_is_accepted := false
var is_moving := false
var last_reaction: StringName = REACTION_NORMAL
var reaction_label: Label3D
var _face_background: MeshInstance3D
var _face_features: MeshInstance3D
var _reaction_tween: Tween
var _cached_player: Node3D


func get_look_target() -> Vector3:
	return global_position + look_target_offset


func _ready() -> void:
	_setup_reaction_face()
	_setup_reaction_label()
	_reset_reaction()
	_play(&"idle")


func _process(delta: float) -> void:
	_update_look_at_player(delta)


func configure(controller: Variant, next_order: Dictionary, next_slot_index: int) -> void:
	queue_controller = controller
	order_data = next_order
	slot_index = next_slot_index
	order_is_accepted = false
	visible = true
	$Robot.position = Vector3.ZERO
	$Robot.rotation = Vector3(0.0, WINDOW_FACING, 0.0)
	_reset_reaction()
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


func show_reaction(reaction_name: StringName) -> void:
	if not REACTION_COLORS.has(reaction_name):
		reaction_name = REACTION_NORMAL
	last_reaction = reaction_name
	reaction_changed.emit(last_reaction)
	_apply_reaction_face(last_reaction)
	if reaction_label == null:
		return

	if _reaction_tween != null:
		_reaction_tween.kill()
	reaction_label.text = str(reaction_name).to_upper()
	reaction_label.modulate = REACTION_COLORS[reaction_name]
	reaction_label.visible = true
	reaction_label.scale = Vector3.ONE * 0.65
	reaction_label.position.y = 2.1

	var robot := $Robot as Node3D
	if robot == null:
		return
	_reaction_tween = create_tween()
	_reaction_tween.set_trans(Tween.TRANS_QUAD)
	_reaction_tween.set_ease(Tween.EASE_OUT)
	_reaction_tween.parallel().tween_property(reaction_label, ^"scale", Vector3.ONE, 0.16)
	_reaction_tween.parallel().tween_property(reaction_label, ^"position:y", 2.45, 0.2)
	if reaction_name == REACTION_HAPPY:
		_reaction_tween.tween_property(robot, ^"position:y", 0.18, 0.12)
		_reaction_tween.tween_property(robot, ^"position:y", 0.0, 0.16)
	elif reaction_name == REACTION_ANGRY:
		_reaction_tween.tween_property(robot, ^"rotation:z", 0.14, 0.06)
		_reaction_tween.tween_property(robot, ^"rotation:z", -0.14, 0.12)
		_reaction_tween.tween_property(robot, ^"rotation:z", 0.0, 0.06)


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


func _setup_reaction_label() -> void:
	reaction_label = Label3D.new()
	reaction_label.name = "ReactionLabel"
	reaction_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reaction_label.no_depth_test = true
	reaction_label.font_size = 48
	reaction_label.outline_size = 12
	reaction_label.outline_modulate = Color(0.06, 0.04, 0.05, 1.0)
	reaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reaction_label.position = Vector3(0.0, 2.1, 0.0)
	reaction_label.pixel_size = 0.004
	reaction_label.visible = false
	add_child(reaction_label)


func _setup_reaction_face() -> void:
	var robot := $Robot as Node3D
	if robot == null:
		return
	var torso := robot.find_child("torso", true, false) as MeshInstance3D
	if torso == null or torso.mesh == null:
		return

	var robot_material: Material = torso.get_active_material(0)
	if robot_material == null:
		robot_material = torso.mesh.surface_get_material(0)

	_face_background = MeshInstance3D.new()
	_face_background.name = "ReactionFaceBackground"
	_face_background.mesh = _build_face_background_mesh()
	if robot_material != null:
		_face_background.material_override = robot_material
	_face_background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torso.add_child(_face_background)

	_face_features = MeshInstance3D.new()
	_face_features.name = "ReactionFaceFeatures"
	if robot_material != null:
		_face_features.material_override = robot_material
	_face_features.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	torso.add_child(_face_features)



func _build_face_background_mesh() -> ArrayMesh:
	# Covers the original face features across the entire orange face screen
	# while keeping the animated torso material and lighting seamless.
	var z := 0.342
	var triangles: Array[Vector3] = [
		Vector3(0.11, 0.10, z), Vector3(-0.11, 0.10, z), Vector3(-0.1775, 0.1225, z),
		Vector3(-0.1775, 0.1225, z), Vector3(0.1775, 0.1225, z), Vector3(0.11, 0.10, z),
		Vector3(-0.1775, 0.1225, z), Vector3(-0.20, 0.19, z), Vector3(0.1775, 0.1225, z),
		Vector3(-0.20, 0.19, z), Vector3(0.20, 0.19, z), Vector3(0.1775, 0.1225, z),
		Vector3(-0.20, 0.19, z), Vector3(-0.20, 0.41, z), Vector3(0.20, 0.19, z),
		Vector3(-0.20, 0.41, z), Vector3(0.20, 0.41, z), Vector3(0.20, 0.19, z),
		Vector3(-0.20, 0.41, z), Vector3(0.1775, 0.4775, z), Vector3(0.20, 0.41, z),
		Vector3(-0.20, 0.41, z), Vector3(-0.1775, 0.4775, z), Vector3(0.1775, 0.4775, z),
		Vector3(-0.1775, 0.4775, z), Vector3(0.11, 0.50, z), Vector3(0.1775, 0.4775, z),
		Vector3(-0.1775, 0.4775, z), Vector3(-0.11, 0.50, z), Vector3(0.11, 0.50, z),
	]
	var vertices := PackedVector3Array(triangles)
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(vertices.size()):
		uvs.append(Vector2(0.344, 0.58))
		indices.append(i)
	return _build_face_mesh(vertices, uvs, indices)


func _apply_reaction_face(reaction_name: StringName) -> void:
	if _face_features == null:
		return
	_face_features.mesh = _build_face_features_mesh(reaction_name)


func _build_face_features_mesh(reaction_name: StringName) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	if reaction_name == REACTION_HAPPY:
		_add_rect(vertices, uvs, indices, Rect2(-0.145, 0.32, 0.08, 0.028))
		_add_rect(vertices, uvs, indices, Rect2(0.065, 0.32, 0.08, 0.028))
		_add_segment(vertices, uvs, indices, Vector2(-0.105, 0.245), Vector2(-0.052, 0.218), 0.018)
		_add_segment(vertices, uvs, indices, Vector2(-0.052, 0.218), Vector2(0.0, 0.211), 0.018)
		_add_segment(vertices, uvs, indices, Vector2(0.0, 0.211), Vector2(0.052, 0.218), 0.018)
		_add_segment(vertices, uvs, indices, Vector2(0.052, 0.218), Vector2(0.105, 0.245), 0.018)
	elif reaction_name == REACTION_ANGRY:
		_add_slanted_rect(vertices, uvs, indices, Vector2(-0.145, 0.37), Vector2(-0.065, 0.34), 0.028)
		_add_slanted_rect(vertices, uvs, indices, Vector2(0.065, 0.34), Vector2(0.145, 0.37), 0.028)
		_add_segment(vertices, uvs, indices, Vector2(-0.105, 0.22), Vector2(-0.052, 0.245), 0.018)
		_add_segment(vertices, uvs, indices, Vector2(-0.052, 0.245), Vector2(0.0, 0.251), 0.018)
		_add_segment(vertices, uvs, indices, Vector2(0.0, 0.251), Vector2(0.052, 0.245), 0.018)
		_add_segment(vertices, uvs, indices, Vector2(0.052, 0.245), Vector2(0.105, 0.22), 0.018)
	else:
		_add_rect(vertices, uvs, indices, Rect2(-0.145, 0.32, 0.08, 0.06))
		_add_rect(vertices, uvs, indices, Rect2(0.065, 0.32, 0.08, 0.06))
		_add_segment(vertices, uvs, indices, Vector2(-0.085, 0.225), Vector2(0.085, 0.225), 0.018)

	return _build_face_mesh(vertices, uvs, indices)


func _add_rect(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, rect: Rect2) -> void:
	_add_quad(vertices, uvs, indices, [
		Vector3(rect.position.x, rect.position.y, 0.344),
		Vector3(rect.end.x, rect.position.y, 0.344),
		Vector3(rect.end.x, rect.end.y, 0.344),
		Vector3(rect.position.x, rect.end.y, 0.344),
	])


func _add_slanted_rect(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, outer: Vector2, inner: Vector2, thickness: float) -> void:
	var direction := inner - outer
	var normal := direction.normalized() * thickness * 0.5
	normal = Vector2(-normal.y, normal.x)
	_add_quad(vertices, uvs, indices, [
		Vector3(outer.x - normal.x, outer.y - normal.y, 0.344),
		Vector3(inner.x - normal.x, inner.y - normal.y, 0.344),
		Vector3(inner.x + normal.x, inner.y + normal.y, 0.344),
		Vector3(outer.x + normal.x, outer.y + normal.y, 0.344),
	])


func _add_segment(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, start: Vector2, end: Vector2, thickness: float) -> void:
	var direction := end - start
	var normal := direction.normalized() * thickness * 0.5
	normal = Vector2(-normal.y, normal.x)
	_add_quad(vertices, uvs, indices, [
		Vector3(start.x - normal.x, start.y - normal.y, 0.344),
		Vector3(end.x - normal.x, end.y - normal.y, 0.344),
		Vector3(end.x + normal.x, end.y + normal.y, 0.344),
		Vector3(start.x + normal.x, start.y + normal.y, 0.344),
	])


func _add_quad(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, quad: Array) -> void:
	var start_index := vertices.size()
	for vertex: Vector3 in quad:
		vertices.append(vertex)
		uvs.append(Vector2(0.094, 0.90))
	indices.append_array(PackedInt32Array([
		start_index,
		start_index + 1,
		start_index + 2,
		start_index,
		start_index + 2,
		start_index + 3,
	]))


func _build_face_mesh(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	var normals := PackedVector3Array()
	for _vertex: Vector3 in vertices:
		normals.append(Vector3.BACK)
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _reset_reaction() -> void:
	last_reaction = REACTION_NORMAL
	_apply_reaction_face(last_reaction)
	if _reaction_tween != null:
		_reaction_tween.kill()
	_reaction_tween = null
	if reaction_label != null:
		reaction_label.visible = false
		reaction_label.scale = Vector3.ONE
		reaction_label.position.y = 2.1
	var robot := $Robot as Node3D
	if robot != null:
		robot.position = Vector3.ZERO
		robot.rotation.z = 0.0


func _face_direction(direction: Vector3) -> void:
	var flat_direction := Vector2(direction.x, direction.z)
	if flat_direction.length_squared() > 0.0001:
		$Robot.rotation.y = atan2(flat_direction.x, flat_direction.y)


func _play(animation_name: StringName) -> void:
	if animation_player != null and animation_player.has_animation(animation_name):
		animation_player.play(animation_name)


func _update_look_at_player(delta: float) -> void:
	if is_moving or not is_inside_tree():
		return

	var target_yaw := WINDOW_FACING
	if _is_front_in_queue():
		var player := _get_player()
		if player != null and is_instance_valid(player):
			var local_target := to_local(player.global_position)
			var flat_target := Vector2(local_target.x, local_target.z)
			if flat_target.length_squared() > 0.0001:
				target_yaw = atan2(flat_target.x, flat_target.y)

	var robot := $Robot as Node3D
	if robot == null:
		return

	robot.rotation.y = rotate_toward(robot.rotation.y, target_yaw, turn_speed * delta)


func _is_front_in_queue() -> bool:
	if queue_controller != null:
		if queue_controller.has_method(&"get_front_waiter"):
			return queue_controller.get_front_waiter() == self
		if "slot_index" in self:
			return slot_index == 0
	return slot_index == 0


func _get_player() -> Node3D:
	if _cached_player != null and is_instance_valid(_cached_player) and _cached_player.is_inside_tree():
		return _cached_player
	var player_node := get_tree().get_first_node_in_group(&"player") as Node3D
	if player_node != null and is_instance_valid(player_node):
		_cached_player = player_node
		return _cached_player
	var root := get_tree().current_scene
	if root != null:
		var named_player := root.find_child("player", true, false) as Node3D
		if named_player != null:
			_cached_player = named_player
			return _cached_player
	return null

