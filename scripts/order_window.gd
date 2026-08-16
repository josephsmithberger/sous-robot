@tool
class_name OrderWindow
extends InteractionArea
## Delivery endpoint for the currently accepted front-of-line order.


func can_interact(player: Node) -> bool:
	return (
		GameControl.has_active_order()
		and player.has_method(&"has_held_item")
		and player.has_held_item()
	)


func get_interaction_prompt(player: Node) -> String:
	var item: KitchenItem = player.get_held_item()
	return "DELIVER %s" % item.display_name.to_upper()


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	var item: KitchenItem = player.take_held_item()
	GameControl.item_delivered.emit(item)
