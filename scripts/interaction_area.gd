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
