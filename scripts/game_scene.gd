@tool
extends Node3D

const WALL_SCENE: PackedScene = preload("res://assets/kitchen-pack/wall.gltf")
const TABLE_ROUND_B_SCENE: PackedScene = preload("res://assets/kitchen-pack/table_round_B.gltf")

const TOON_FILTER_SHADER := """
shader_type canvas_item;

// A lightweight screen-space toon grade. It only uses SCREEN_TEXTURE, so it
// remains compatible with the WebGL 2 Compatibility renderer.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// Keep these as material uniforms so the look can be tuned without changing
// the overlay architecture. The defaults aim for soft, animated-film bands.
uniform float tone_steps : hint_range(2.0, 8.0, 1.0) = 5.0;
uniform float posterize_strength : hint_range(0.0, 1.0) = 0.58;
uniform float saturation : hint_range(0.0, 2.0) = 1.12;
uniform float contrast : hint_range(0.5, 1.5) = 1.06;
// Neighbor-based screen-space outlines shimmer on thin, distant geometry
// (notably the window mullions), so keep them opt-in. The stable toon grade
// below does not need extra texture reads and works well with FXAA.
uniform bool outlines_enabled = false;
uniform float edge_threshold : hint_range(0.02, 0.8) = 0.28;
uniform float edge_softness : hint_range(0.01, 0.4) = 0.10;
uniform float edge_strength : hint_range(0.0, 1.0) = 0.30;
uniform vec3 ink_color : source_color = vec3(0.11, 0.075, 0.09);

float luminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec3 adjust_saturation(vec3 color, float amount) {
	float lightness = luminance(color);
	return mix(vec3(lightness), color, amount);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 pixel = SCREEN_PIXEL_SIZE;
	vec3 source = texture(screen_texture, uv).rgb;

	// Quantize lightness rather than RGB channels. This preserves the art color
	// relationships and avoids the noisy, videogame-posterized look.
	float source_lightness = luminance(source);
	float banded_lightness = floor(source_lightness * tone_steps + 0.5) / tone_steps;
	float lightness_gain = banded_lightness / max(source_lightness, 0.001);
	vec3 banded = clamp(source * lightness_gain, 0.0, 1.0);
	vec3 toon_color = mix(source, banded, posterize_strength);
	toon_color = adjust_saturation(toon_color, saturation);
	toon_color = clamp((toon_color - 0.5) * contrast + 0.5, 0.0, 1.0);

	if (outlines_enabled) {
		// This optional pass is intentionally disabled by default: comparing
		// neighboring screen pixels makes sub-pixel window lines turn into
		// camera-dependent dotted outlines at a distance.
		float center = source_lightness;
		float edge = 0.0;
		edge = max(edge, abs(center - luminance(texture(screen_texture, uv + vec2(pixel.x, 0.0)).rgb)));
		edge = max(edge, abs(center - luminance(texture(screen_texture, uv - vec2(pixel.x, 0.0)).rgb)));
		edge = max(edge, abs(center - luminance(texture(screen_texture, uv + vec2(0.0, pixel.y)).rgb)));
		edge = max(edge, abs(center - luminance(texture(screen_texture, uv - vec2(0.0, pixel.y)).rgb)));

		float outline = smoothstep(edge_threshold, edge_threshold + edge_softness, edge);
		toon_color = mix(toon_color, ink_color, outline * edge_strength);
	}

	COLOR = vec4(toon_color, 1.0);
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
