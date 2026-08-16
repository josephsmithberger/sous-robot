class_name PlacementManager
extends Node3D
## Manages purchasing placement and anytime editing/repositioning of kitchen appliances and crates from the overhead camera.

signal placement_validity_changed(is_valid: bool)
signal item_picked_up(item_id: StringName, node: Node3D)

const ITEM_SCENES: Dictionary = {
	&"DecoratedWall": preload("res://assets/appliances/wall_decorated.tscn"),
	&"BunCrate": preload("res://assets/appliances/crate_buns.tscn"),
	&"CarrotCrate": preload("res://assets/appliances/crate_carrots.tscn"),
	&"CheeseCrate": preload("res://assets/appliances/crate_cheese.tscn"),
	&"HamCrate": preload("res://assets/appliances/crate_ham.tscn"),
	&"LettuceCrate": preload("res://assets/appliances/crate_lettuce.tscn"),
	&"OnionCrate": preload("res://assets/appliances/crate_onions.tscn"),
	&"PotatoCrate": preload("res://assets/appliances/crate_potatoes.tscn"),
	&"SteakCrate": preload("res://assets/appliances/crate_steak.tscn"),
	&"TomatoCrate": preload("res://assets/appliances/crate_tomatoes.tscn"),
	&"Fridge": preload("res://assets/appliances/fridge.tscn"),
	&"Oven": preload("res://assets/appliances/oven.tscn"),
	&"Sink": preload("res://assets/appliances/sink.tscn"),
	&"Counter": preload("res://assets/appliances/counter.tscn"),
}

const MIN_X := -4.5
const MAX_X := 4.5
const MIN_Z := -10.5
const MAX_Z := 6.5
const GRID_STEP := 0.5
const MIN_ITEM_DISTANCE := 1.6

@export var placed_items_container: Node3D

var active_ghost: Node3D
var active_item_id: StringName = &""
var ghost_rotation_y := 0.0
var is_valid_placement := true
var editing_node: Node3D
var editing_original_pos := Vector3.ZERO
var editing_original_rot := 0.0

var _hovered_node: Node3D
var _footprint_mesh: MeshInstance3D
var _valid_material: StandardMaterial3D
var _invalid_material: StandardMaterial3D


func _ready() -> void:
	_init_materials()
	_init_starter_items()
	GameControl.placement_requested.connect(start_placement)
	GameControl.placement_cancelled.connect(cancel_placement)


func _exit_tree() -> void:
	if GameControl.placement_requested.is_connected(start_placement):
		GameControl.placement_requested.disconnect(start_placement)
	if GameControl.placement_cancelled.is_connected(cancel_placement):
		GameControl.placement_cancelled.disconnect(cancel_placement)
	_cleanup_ghost()


func _init_materials() -> void:
	_valid_material = StandardMaterial3D.new()
	_valid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_valid_material.albedo_color = Color(0.2, 0.85, 0.3, 0.45)
	_valid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_valid_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_invalid_material = StandardMaterial3D.new()
	_invalid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_invalid_material.albedo_color = Color(0.95, 0.2, 0.2, 0.55)
	_invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_invalid_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _init_starter_items() -> void:
	if placed_items_container == null:
		placed_items_container = get_node_or_null("../Architecture")
		if placed_items_container == null:
			placed_items_container = self

	var decorated_wall := get_node_or_null("../Architecture/wall_decorated")
	if decorated_wall != null:
		decorated_wall.set_meta(&"item_id", &"DecoratedWall")
		decorated_wall.set_meta(&"is_fixed", true)

	var bun_crate := get_node_or_null("../Architecture/crate_buns")
	if bun_crate != null:
		bun_crate.set_meta(&"item_id", &"BunCrate")
		bun_crate.set_meta(&"is_fixed", false)
		bun_crate.add_to_group(&"placed_items")


func _process(_delta: float) -> void:
	if GameControl.is_placing and active_ghost != null:
		_update_ghost_transform()
	elif GameControl.camera_mode == GameControl.CameraMode.MARKER and not GameControl.has_player_control():
		_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if not GameControl.is_placing:
		if GameControl.camera_mode == GameControl.CameraMode.MARKER and TouchUI.is_primary_press(event):
			_try_pick_up_at_mouse()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			rotate_ghost()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			cancel_placement()
			get_viewport().set_input_as_handled()
	elif TouchUI.is_primary_press(event):
		if is_valid_placement:
			confirm_placement()
			get_viewport().set_input_as_handled()


func start_placement(item_id: StringName) -> void:
	if not ITEM_SCENES.has(item_id):
		push_warning("PlacementManager: Unknown item_id '%s'" % item_id)
		return

	_cleanup_ghost()
	active_item_id = item_id
	GameControl.is_placing = true
	GameControl.placing_item_id = item_id
	GameControl.set_camera_mode(GameControl.CameraMode.MARKER)
	GameControl.set_ui_mode(true)

	var scene: PackedScene = ITEM_SCENES[item_id]
	active_ghost = scene.instantiate() as Node3D
	if active_ghost == null:
		push_error("Failed to instantiate ghost for %s" % item_id)
		return

	_disable_ghost_collisions(active_ghost)
	_create_footprint_mesh()
	add_child(active_ghost)
	_update_ghost_transform()


func pick_up_item(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if bool(node.get_meta(&"is_fixed", false)) or node.name == "wall_decorated" or node.get_meta(&"item_id", &"") == &"DecoratedWall":
		return false

	var item_id: StringName = node.get_meta(&"item_id", &"")
	if item_id.is_empty():
		var clean_name := StringName(node.name.replace("@", "").capitalize().replace(" ", ""))
		if ITEM_SCENES.has(clean_name):
			item_id = clean_name
		else:
			for key: StringName in ITEM_SCENES:
				if node.name.containsn(str(key).to_snake_case()) or node.name.containsn(str(key)):
					item_id = key
					break

	if item_id.is_empty() or not ITEM_SCENES.has(item_id):
		return false

	editing_node = node
	editing_original_pos = node.global_position
	editing_original_rot = node.rotation.y
	ghost_rotation_y = node.rotation.y

	node.visible = false
	_disable_node_collisions(node, true)

	start_placement(item_id)
	item_picked_up.emit(item_id, node)
	return true


func rotate_ghost() -> void:
	ghost_rotation_y = wrapf(ghost_rotation_y + PI * 0.5, 0.0, TAU)
	if active_ghost != null:
		active_ghost.rotation.y = ghost_rotation_y
		_update_ghost_transform()


func confirm_placement() -> bool:
	if not is_valid_placement or active_ghost == null:
		return false

	var target_pos := active_ghost.global_position
	var target_rot := ghost_rotation_y
	var item_id := active_item_id

	if editing_node != null and is_instance_valid(editing_node):
		editing_node.global_position = target_pos
		editing_node.rotation.y = target_rot
		editing_node.visible = true
		_disable_node_collisions(editing_node, false)
		_play_placement_bounce(editing_node)
		editing_node = null
	else:
		var scene: PackedScene = ITEM_SCENES[item_id]
		var new_item := scene.instantiate() as Node3D
		if new_item != null:
			if placed_items_container != null:
				placed_items_container.add_child(new_item)
			else:
				add_child(new_item)
			new_item.global_position = target_pos
			new_item.rotation.y = target_rot
			new_item.set_meta(&"item_id", item_id)
			new_item.set_meta(&"is_fixed", false)
			new_item.add_to_group(&"placed_items")
			_play_placement_bounce(new_item)

	_cleanup_ghost()
	GameControl.complete_placement(item_id, target_pos, target_rot)
	return true


func cancel_placement() -> void:
	if editing_node != null and is_instance_valid(editing_node):
		editing_node.global_position = editing_original_pos
		editing_node.rotation.y = editing_original_rot
		editing_node.visible = true
		_disable_node_collisions(editing_node, false)
		editing_node = null

	_cleanup_ghost()
	GameControl.cancel_placement()


func check_placement_valid(pos: Vector3, _item_id: StringName, ignore_node: Node3D = null) -> bool:
	if pos.x < MIN_X or pos.x > MAX_X or pos.z < MIN_Z or pos.z > MAX_Z:
		return false

	# Fixed decorated wall footprint (South wall center)
	if pos.x >= -2.6 and pos.x <= 2.6 and pos.z >= 6.0:
		return false

	# Order window footprint (West wall center)
	if pos.x <= -4.2 and pos.z >= -3.8 and pos.z <= -0.2:
		return false

	# North closed window area
	if pos.x >= -5.2 and pos.x <= -2.8 and pos.z <= -10.2:
		return false

	# Check overlap with existing placed items
	var items := get_tree().get_nodes_in_group(&"placed_items")
	for node in items:
		if node is not Node3D:
			continue
		var item_node := node as Node3D
		if item_node == ignore_node or not item_node.is_inside_tree() or not item_node.visible:
			continue
		var dist_sq := Vector2(pos.x - item_node.global_position.x, pos.z - item_node.global_position.z).length_squared()
		if dist_sq < (MIN_ITEM_DISTANCE * MIN_ITEM_DISTANCE):
			return false

	return true


func set_ghost_position(pos: Vector3) -> void:
	if active_ghost == null:
		return

	var snapped_x := clampf(snappedf(pos.x, GRID_STEP), MIN_X, MAX_X)
	var snapped_z := clampf(snappedf(pos.z, GRID_STEP), MIN_Z, MAX_Z)
	var snapped_pos := Vector3(snapped_x, 0.04, snapped_z)

	active_ghost.global_position = snapped_pos
	active_ghost.rotation.y = ghost_rotation_y

	var valid := check_placement_valid(snapped_pos, active_item_id, editing_node)
	if valid != is_valid_placement:
		is_valid_placement = valid
		placement_validity_changed.emit(is_valid_placement)
		_update_ghost_visual(is_valid_placement)


func _update_ghost_transform() -> void:
	if active_ghost == null:
		return
	var floor_pos := _get_floor_hit_under_mouse()
	set_ghost_position(floor_pos)


func _update_ghost_visual(valid: bool) -> void:
	if _footprint_mesh != null:
		_footprint_mesh.material_override = _valid_material if valid else _invalid_material

	var tint := Color(0.7, 1.0, 0.7, 0.8) if valid else Color(1.0, 0.4, 0.4, 0.8)
	_apply_ghost_tint(active_ghost, tint)


func _apply_ghost_tint(node: Node, tint: Color) -> void:
	if node is VisualInstance3D and node != _footprint_mesh:
		(node as VisualInstance3D).set(&"modulate", tint)
	for child in node.get_children():
		_apply_ghost_tint(child, tint)


func _create_footprint_mesh() -> void:
	if active_ghost == null:
		return
	_footprint_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	_footprint_mesh.mesh = plane
	_footprint_mesh.position = Vector3(0, 0.05, 0)
	_footprint_mesh.material_override = _valid_material
	active_ghost.add_child(_footprint_mesh)


func _disable_ghost_collisions(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	elif node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is Area3D:
		(node as Area3D).monitoring = false
		(node as Area3D).monitorable = false
	for child in node.get_children():
		_disable_ghost_collisions(child)


func _disable_node_collisions(node: Node, disable: bool) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = disable
	elif node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0 if disable else 1
		(node as CollisionObject3D).collision_mask = 0 if disable else 1
	if node is Area3D:
		(node as Area3D).monitoring = not disable
		(node as Area3D).monitorable = not disable
	for child in node.get_children():
		_disable_node_collisions(child, disable)


func _cleanup_ghost() -> void:
	if is_instance_valid(active_ghost):
		active_ghost.queue_free()
	active_ghost = null
	_footprint_mesh = null
	active_item_id = &""
	GameControl.is_placing = false
	GameControl.placing_item_id = &""


func _play_placement_bounce(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var initial_scale := node.scale
	node.scale = initial_scale * Vector3(1.18, 0.82, 1.18)
	var tween := node.create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(node, ^"scale", initial_scale, 0.28)


func _get_floor_hit_under_mouse() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var floor_plane := Plane(Vector3.UP, 0.0)
	var hit: Variant = floor_plane.intersects_ray(ray_origin, ray_dir)
	if hit is Vector3:
		return hit as Vector3
	return Vector3.ZERO


func _update_hover() -> void:
	var target := _find_placed_item_under_mouse()
	if target != _hovered_node:
		_hovered_node = target


func _try_pick_up_at_mouse() -> void:
	var target := _find_placed_item_under_mouse()
	if target != null:
		pick_up_item(target)


func _find_placed_item_under_mouse() -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var space_state := get_world_3d().direct_space_state
	if space_state == null:
		return null

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 100.0)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# Fallback: check floor hit distance to placed items
		var floor_hit := _get_floor_hit_under_mouse()
		var candidate: Node3D
		var closest_dist := 1.5 * 1.5
		for node in get_tree().get_nodes_in_group(&"placed_items"):
			if node is Node3D and node.visible and not bool(node.get_meta(&"is_fixed", false)):
				var d := Vector2(floor_hit.x - node.global_position.x, floor_hit.z - node.global_position.z).length_squared()
				if d < closest_dist:
					closest_dist = d
					candidate = node
		return candidate

	var collider := result.get("collider") as Node
	var current: Node = collider
	while current != null and current != self and current != get_tree().root:
		if current.is_in_group(&"placed_items") or current.has_meta(&"item_id"):
			if bool(current.get_meta(&"is_fixed", false)) or current.name == "wall_decorated" or current.get_meta(&"item_id", &"") == &"DecoratedWall":
				return null
			return current as Node3D
		current = current.get_parent()

	return null
