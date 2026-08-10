@tool
extends Node3D

const WALL_SCENE: PackedScene = preload("res://assets/kitchen-pack/wall.gltf")
const TABLE_ROUND_B_SCENE: PackedScene = preload("res://assets/kitchen-pack/table_round_B.gltf")

func _ready() -> void:
	_build_static_batches()


func _build_static_batches() -> void:
	var static_geometry := get_node_or_null("StaticGeometry") as Node3D
	if static_geometry == null:
		push_error("StaticGeometry container is missing")
		return

	for child in static_geometry.get_children():
		child.queue_free()

	_add_batch(static_geometry, "PlainWalls", WALL_SCENE, _wall_transforms())
	_add_batch(static_geometry, "RoundTablesB", TABLE_ROUND_B_SCENE, _round_table_b_transforms())


func _add_batch(container: Node3D, batch_name: String, source_scene: PackedScene, transforms: Array[Transform3D]) -> void:
	var source := source_scene.instantiate()
	var mesh_node := source.find_child("*", true, false) as MeshInstance3D
	if mesh_node == null or mesh_node.mesh == null:
		source.free()
		push_error("%s does not contain a MeshInstance3D" % source_scene.resource_path)
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh_node.mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
	source.free()

	var batch := MultiMeshInstance3D.new()
	batch.name = batch_name
	batch.multimesh = multimesh
	container.add_child(batch)


func _wall_transforms() -> Array[Transform3D]:
	return [
		_transform(Vector3(4, 0, -12), 0.0),
		_transform(Vector3(0, 0, -12), 0.0),
		_transform(Vector3(-6, 0, -10), PI * 0.5),
		_transform(Vector3(6, 0, -10), PI * 0.5),
		_transform(Vector3(6, 0, -6), PI * 0.5),
		_transform(Vector3(6, 0, -2), PI * 0.5),
		_transform(Vector3(6, 0, 2), PI * 0.5),
		_transform(Vector3(-6, 0, -6), PI * 0.5),
		_transform(Vector3(-6, 0, 2), PI * 0.5),
		_transform(Vector3(6, 0, 6), PI * 0.5),
		_transform(Vector3(-6, 0, 6), PI * 0.5),
		_transform(Vector3(-4, 0, 8), PI),
		_transform(Vector3(4, 0, 8), PI),
	]


func _round_table_b_transforms() -> Array[Transform3D]:
	return [
		_transform(Vector3(-12, 0, 3), PI),
		_transform(Vector3(-9, 0, -8), PI),
	]


func _transform(instance_position: Vector3, rotation_y: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rotation_y), instance_position)
