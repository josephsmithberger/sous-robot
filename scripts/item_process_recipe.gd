class_name ItemProcessRecipe
extends Resource
## A single one-input, one-output appliance preparation route.

@export var recipe_id: StringName = &""
@export var input_item: KitchenItem
@export var output_item: KitchenItem
@export var action_verb := "PROCESS"
@export_range(0.0, 60.0, 0.05, "or_greater") var hold_duration := 0.0


func is_valid() -> bool:
	return input_item != null and output_item != null and not input_item.item_id.is_empty()


func matches_item(item_id: StringName) -> bool:
	return is_valid() and input_item.item_id == item_id


func get_output_name() -> String:
	if output_item == null:
		return "OUTPUT"
	if not output_item.display_name.is_empty():
		return output_item.display_name
	return str(output_item.item_id).capitalize()


func get_action_label() -> String:
	return action_verb.strip_edges().to_upper() if not action_verb.strip_edges().is_empty() else "PROCESS"
