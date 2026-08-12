@tool
extends Node3D

const WALL_SCENE: PackedScene = preload("res://assets/kitchen-pack/wall.gltf")
const TABLE_ROUND_B_SCENE: PackedScene = preload("res://assets/kitchen-pack/table_round_B.gltf")

const TOON_FILTER_SHADER := """
shader_type canvas_item;

// Canvas screen-read pass: compatible with the WebGL 2 Compatibility renderer.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float color_steps : hint_range(2.0, 12.0) = 6.0;
uniform float edge_threshold : hint_range(0.01, 0.5) = 0.20;
uniform vec3 ink_color : source_color = vec3(0.08, 0.055, 0.10);

float luminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec2 pixel = SCREEN_PIXEL_SIZE;
	vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;
	vec3 toon_color = floor(screen_color * color_steps + 0.5) / color_steps;

	float center = luminance(screen_color);
	float edge = 0.0;
	edge += abs(center - luminance(texture(screen_texture, SCREEN_UV + vec2(pixel.x, 0.0)).rgb));
	edge += abs(center - luminance(texture(screen_texture, SCREEN_UV - vec2(pixel.x, 0.0)).rgb));
	edge += abs(center - luminance(texture(screen_texture, SCREEN_UV + vec2(0.0, pixel.y)).rgb));
	edge += abs(center - luminance(texture(screen_texture, SCREEN_UV - vec2(0.0, pixel.y)).rgb));

	float outline = smoothstep(edge_threshold, edge_threshold * 2.0, edge);
	COLOR = vec4(mix(toon_color, ink_color, outline * 0.48), 1.0);
}
"""

func _ready() -> void:
	_build_static_batches()
	_add_toon_filter()


func _add_toon_filter() -> void:
	if get_node_or_null("ToonFilter") != null:
		return

	# A CanvasLayer screen pass works in the WebGL 2 Compatibility renderer.
	var layer := CanvasLayer.new()
	layer.name = "ToonFilter"
	layer.layer = 1

	var filter := ColorRect.new()
	filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	filter.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := Shader.new()
	shader.code = TOON_FILTER_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	filter.material = material

	layer.add_child(filter)
	add_child(layer)


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
