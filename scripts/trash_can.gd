@tool
class_name TrashCan
extends InteractionArea
## Interactive appliance for discarding held items and clearing player hands.

@warning_ignore("unused_signal")
signal trashed(item: KitchenItem)


func _ready() -> void:
	add_to_group(&"trash_cans")
	if prompt.is_empty() or prompt == "INTERACT":
		prompt = "TRASH"


func can_interact(player: Node) -> bool:
	return (
		player != null
		and is_instance_valid(player)
		and player.has_method(&"has_held_item")
		and player.has_held_item()
	)


func get_interaction_prompt(player: Node) -> String:
	if player != null and is_instance_valid(player) and player.has_method(&"get_held_item"):
		var item: KitchenItem = player.get_held_item()
		if item != null and not item.display_name.is_empty():
			return "TRASH %s" % item.display_name.to_upper()
	return prompt


const SIDE_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.0, 1.1),   # South / Front
	Vector3(0.0, 0.0, -1.1),  # North / Back
	Vector3(1.1, 0.0, 0.0),   # East / Right
	Vector3(-1.1, 0.0, 0.0),  # West / Left
]


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var item: KitchenItem = null
	if player.has_method(&"take_held_item"):
		item = player.take_held_item()
	elif player.has_method(&"set_held_item"):
		if player.has_method(&"get_held_item"):
			item = player.get_held_item()
		player.set_held_item(null)

	if item != null:
		trashed.emit(item)
		if GameControl.has_signal(&"item_trashed"):
			GameControl.emit_signal(&"item_trashed", item)


func get_interaction_position(from_global_pos: Vector3 = Vector3.ZERO) -> Vector3:
	for child in get_children():
		if child is Marker3D:
			return super.get_interaction_position(from_global_pos)

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

