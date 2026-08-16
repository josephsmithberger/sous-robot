extends Node3D
## Isolated runtime tint for imported kitchen-pack materials.
@export var tint := Color(1, 1, 1, 1)
@export_range(0.0, 1.0, 0.01) var tint_strength := 0.0
func _ready() -> void:
    if tint_strength > 0.0:
        _tint_meshes(self)
func _tint_meshes(node: Node) -> void:
    if node is MeshInstance3D and node.mesh:
        for surface in node.mesh.get_surface_count():
            var source: Material = node.mesh.surface_get_material(surface)
            if source == null:
                source = node.mesh.surface_get_material(surface)
            if source is BaseMaterial3D:
                var material: BaseMaterial3D = source.duplicate() as BaseMaterial3D
                material.albedo_color = material.albedo_color.lerp(tint, tint_strength)
                node.set_surface_override_material(surface, material)
    for child in node.get_children():
        _tint_meshes(child)
