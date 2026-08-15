class_name ItemSource
extends InteractionArea
## Infinite ingredient source. Assign a KitchenItem resource in the inspector.

@export var item: KitchenItem


func can_interact(player: Node) -> bool:
	return item != null and player.has_method(&"has_held_item") and not player.has_held_item()


func get_interaction_prompt(_player: Node) -> String:
	return "TAKE %s" % item.display_name.to_upper()


func interact(player: Node) -> void:
	if can_interact(player):
		player.set_held_item(item)
