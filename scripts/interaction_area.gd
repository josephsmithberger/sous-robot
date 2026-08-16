@tool
class_name InteractionArea
extends Area3D
## Base contract for anything the player can interact with.

@export var prompt := "INTERACT"
@export_range(0.0, 10.0, 0.05, "or_greater") var hold_duration := 0.0


func can_interact(_player: Node) -> bool:
	return true


func get_interaction_prompt(_player: Node) -> String:
	return prompt


func get_interaction_hold_duration(_player: Node) -> float:
	return hold_duration


func interact(_player: Node) -> void:
	pass


func get_interaction_position(from_global_pos: Vector3 = Vector3.ZERO) -> Vector3:
	var markers: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D:
			markers.append(child as Marker3D)

	if markers.is_empty():
		return global_transform * Vector3(0.0, 0.0, 1.0)

	if markers.size() == 1 or from_global_pos == Vector3.ZERO:
		return markers[0].global_position

	var world := get_world_3d()
	var nav_map := world.navigation_map if world != null else RID()
	var best_pos := markers[0].global_position
	var shortest_dist_sq := INF

	for marker in markers:
		var candidate_pos := marker.global_position
		if nav_map.is_valid():
			var nav_pos := NavigationServer3D.map_get_closest_point(nav_map, candidate_pos)
			if candidate_pos.distance_squared_to(nav_pos) < 0.4:
				candidate_pos = nav_pos

		var dist_sq := from_global_pos.distance_squared_to(candidate_pos)
		if dist_sq < shortest_dist_sq:
			shortest_dist_sq = dist_sq
			best_pos = candidate_pos

	return best_pos

