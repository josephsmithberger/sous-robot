@tool
class_name ItemSource
extends InteractionArea
## Infinite ingredient source. Assign a KitchenItem resource in the inspector.

@export var item: KitchenItem


func _ready() -> void:
	add_to_group(&"item_sources")



func can_interact(player: Node) -> bool:
	return item != null and player.has_method(&"has_held_item") and not player.has_held_item()


func get_interaction_prompt(_player: Node) -> String:
	return "TAKE %s" % item.display_name.to_upper()


const SIDE_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.0, 1.35),   # South / Front
	Vector3(0.0, 0.0, -1.35),  # North / Back
	Vector3(1.35, 0.0, 0.0),   # East / Right
	Vector3(-1.35, 0.0, 0.0),  # West / Left
]


func interact(player: Node) -> void:
	if can_interact(player):
		player.set_held_item(item)


func get_interaction_position(from_global_pos: Vector3 = Vector3.ZERO) -> Vector3:
	# If manual Marker3Ds were placed, defer to them
	for child in get_children():
		if child is Marker3D:
			return super.get_interaction_position(from_global_pos)

	# Otherwise, compute the closest unblocked side dynamically in code (no scene markers needed!)
	var world := get_world_3d()
	var nav_map := world.navigation_map if world != null else RID()
	var best_pos := global_position
	var shortest_dist_sq := INF

	for offset in SIDE_OFFSETS:
		var candidate_pos := global_transform * offset
		if nav_map.is_valid():
			var nav_pos := NavigationServer3D.map_get_closest_point(nav_map, candidate_pos)
			if candidate_pos.distance_squared_to(nav_pos) < 0.45:
				candidate_pos = nav_pos

		var dist_sq := from_global_pos.distance_squared_to(candidate_pos)
		if dist_sq < shortest_dist_sq:
			shortest_dist_sq = dist_sq
			best_pos = candidate_pos

	return best_pos

