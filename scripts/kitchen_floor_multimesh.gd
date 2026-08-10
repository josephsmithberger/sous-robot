@tool
extends Node3D

const FLOOR_SCENE: PackedScene = preload("res://assets/kitchen-pack/floor_kitchen.gltf")
const GRID_SIZE := 10
const TILE_SIZE := 4.0

var floor_instance: MultiMeshInstance3D

func _ready() -> void:
	_build_floor()

func _build_floor() -> void:
	if is_instance_valid(floor_instance):
		floor_instance.queue_free()
		floor_instance = null

	var source := FLOOR_SCENE.instantiate()
	var mesh_nodes := source.find_children("*", "MeshInstance3D", true, false)
	if mesh_nodes.is_empty():
		source.free()
		push_error("floor_kitchen.gltf does not contain a MeshInstance3D")
		return

	var mesh_node := mesh_nodes[0] as MeshInstance3D
	var source_mesh: Mesh = mesh_node.mesh
	source.free()
	if source_mesh == null:
		push_error("floor_kitchen.gltf MeshInstance3D has no mesh")
		return

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source_mesh
	multimesh.instance_count = GRID_SIZE * GRID_SIZE

	var offset := (GRID_SIZE - 1) * TILE_SIZE * 0.5
	var index := 0
	for z in GRID_SIZE:
		for x in GRID_SIZE:
			var tile_position := Vector3(x * TILE_SIZE - offset, 0.0, z * TILE_SIZE - offset)
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, tile_position))
			index += 1

	floor_instance = MultiMeshInstance3D.new()
	floor_instance.name = "FloorKitchen10x10"
	floor_instance.multimesh = multimesh
	add_child(floor_instance)
	if Engine.is_editor_hint():
		floor_instance.owner = get_tree().edited_scene_root
