class_name ItemProcessor
extends InteractionArea
## Turns one assigned KitchenItem into another after the configured hold time.

@export var input_item: KitchenItem
@export var output_item: KitchenItem
@export var action_verb := "PROCESS"


func can_interact(player: Node) -> bool:
	return (
		input_item != null
		and output_item != null
		and player.has_method(&"is_holding")
		and player.is_holding(input_item.item_id)
	)


func get_interaction_prompt(_player: Node) -> String:
	var prefix := "HOLD TO " if hold_duration > 0.0 else ""
	return "%s%s" % [prefix, action_verb.to_upper()]


func interact(player: Node) -> void:
	if can_interact(player):
		player.set_held_item(output_item)
