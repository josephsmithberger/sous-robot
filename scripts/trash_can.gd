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
