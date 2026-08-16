class_name Recipe
extends Resource
## Data resource defining a craftable composite dish from an ordered sequence of ingredients.

@export var recipe_id: StringName
@export var display_name: String = ""
@export var output_item: KitchenItem
## Sequential ingredients required to complete the recipe
@export var ingredient_sequence: Array[KitchenItem] = []
## Optional final assembly duration (0.0 = instant on placing last ingredient)
@export_range(0.0, 10.0, 0.05) var assembly_duration: float = 0.0


func matches(items: Array[KitchenItem]) -> bool:
	if items.size() != ingredient_sequence.size():
		return false
	for i in items.size():
		if items[i] == null or ingredient_sequence[i] == null:
			return false
		if items[i].item_id != ingredient_sequence[i].item_id:
			return false
	return true


func matches_prefix(items: Array[KitchenItem]) -> bool:
	if items.size() > ingredient_sequence.size():
		return false
	for i in items.size():
		if items[i] == null or ingredient_sequence[i] == null:
			return false
		if items[i].item_id != ingredient_sequence[i].item_id:
			return false
	return true


func can_accept_next(current_items: Array[KitchenItem], next_item: KitchenItem) -> bool:
	if next_item == null or current_items.size() >= ingredient_sequence.size():
		return false
	if not matches_prefix(current_items):
		return false
	var next_idx := current_items.size()
	var expected := ingredient_sequence[next_idx]
	return expected != null and expected.item_id == next_item.item_id
