extends Node

const ITEM_IDS := [
	"bun_top", "bun_bottom", "carrot_chopped", "carrot_pieces", "carrot_washed",
	"cheese_slice", "cheese_chopped", "ham_cooked", "ham_roasted", "ham_chilled",
	"lettuce_slice", "lettuce_chopped", "salad_chilled", "onion_chopped", "onion_rings",
	"onion_rings_fried", "potato_chopped", "potato_mashed", "steak_pieces", "steak_broiled",
	"tomato_slice", "tomato_slices", "burger_cooked", "vegetableburger_uncooked",
	"vegetableburger_cooked", "stew_base", "cheeseburger", "veggie_burger", "steak_dinner",
	"beef_stew", "ketchup", "mustard", "pickles",
]

const ROUTES := [
	["cutboard", "slice_bread", "bread", "bun", "SLICE BREAD", 1.25],
	["cutboard", "chop_carrot", "carrot", "carrot_chopped", "CHOP CARROT", 1.50],
	["cutboard", "cut_carrot_sticks", "carrot", "carrot_pieces", "CUT STICKS", 1.50],
	["cutboard", "slice_cheese", "cheese", "cheese_slice", "SLICE CHEESE", 1.25],
	["cutboard", "dice_cheese", "cheese", "cheese_chopped", "DICE CHEESE", 1.25],
	["cutboard", "tear_lettuce_leaf", "lettuce", "lettuce_slice", "TEAR LEAF", 1.00],
	["cutboard", "shred_greens", "lettuce", "lettuce_chopped", "SHRED GREENS", 1.25],
	["cutboard", "dice_onion", "onion", "onion_chopped", "DICE ONION", 1.25],
	["cutboard", "ring_slice_onion", "onion", "onion_rings", "RING SLICE", 1.50],
	["cutboard", "chop_fries", "potato", "potato_chopped", "CHOP FRIES", 1.50],
	["cutboard", "slice_tomato", "tomato", "tomato_slice", "SLICE TOMATO", 1.00],
	["cutboard", "slice_tomato_batch", "tomato", "tomato_slices", "SLICE BATCH", 1.50],
	["stove", "sear_ham", "ham", "ham_cooked", "SEAR HAM", 2.50],
	["stove", "fry_onion_rings", "onion_rings", "onion_rings_fried", "FRY RINGS", 2.50],
	["stove", "mash_potato", "potato", "potato_mashed", "MASH POTATO", 3.00],
	["stove", "sear_steak", "steak", "steak_pieces", "SEAR STEAK", 3.00],
	["stove", "grill_burger_patty", "steak", "burger_cooked", "GRILL PATTY", 3.00],
	["stove", "grill_veggie_patty", "vegetableburger_uncooked", "vegetableburger_cooked", "GRILL VEGGIE PATTY", 3.00],
	["stove", "simmer_stew", "stew_base", "beef_stew", "SIMMER STEW", 3.00],
	["oven", "toast_bun_top", "bread", "bun_top", "TOAST BUN", 2.00],
	["oven", "toast_bun_bottom", "bread", "bun_bottom", "TOAST BUN", 2.00],
	["oven", "roast_ham", "ham", "ham_roasted", "ROAST HAM", 3.50],
	["oven", "mash_potato", "potato", "potato_mashed", "MASH POTATO", 3.00],
	["oven", "broil_steak", "steak", "steak_broiled", "BROIL STEAK", 4.00],
	["sink", "wash_carrot", "carrot", "carrot_washed", "WASH CARROT", 1.00],
	["fridge", "chill_ham_cooked", "ham_cooked", "ham_chilled", "CHILL HAM", 1.50],
	["fridge", "chill_ham_roasted", "ham_roasted", "ham_chilled", "CHILL HAM", 1.50],
	["fridge", "chill_salad", "lettuce_chopped", "salad_chilled", "CHILL SALAD", 1.50],
	["fridge", "bottle_ketchup", "tomato", "ketchup", "BOTTLE SAUCE", 1.50],
	["fridge", "bottle_mustard", "onion", "mustard", "BOTTLE MUSTARD", 1.50],
	["fridge", "jar_pickles", "onion_rings", "pickles", "JAR PRESERVE", 1.50],
]


func _ready() -> void:
	_validate_items()
	_validate_appliances()
	print("COOKING_CATALOG_SMOKE_PASS")
	await get_tree().process_frame
	get_tree().quit(0)


func _validate_items() -> void:
	var all_ids: Array = ["bread", "bun", "carrot", "cheese", "ham", "lettuce", "onion", "potato", "steak", "tomato", "two_buns"]
	all_ids.append_array(ITEM_IDS)
	var unique_ids := {}
	for item_id: String in all_ids:
		var item := load("res://resources/items/%s.tres" % item_id) as KitchenItem
		assert(item != null, "Item resource failed to load: %s" % item_id)
		assert(item.item_id == StringName(item_id), "Item ID mismatch for %s" % item_id)
		assert(not unique_ids.has(item.item_id), "Duplicate item ID: %s" % item_id)
		unique_ids[item.item_id] = true
		assert(item.held_scene != null, "Held scene missing for %s" % item_id)
		var visual := item.held_scene.instantiate() as Node3D
		assert(visual != null, "Held scene did not instantiate for %s" % item_id)
		assert(_count_meshes(visual) > 0, "Held scene has no meshes for %s" % item_id)
		visual.free()


func _validate_appliances() -> void:
	var wall := preload("res://assets/appliances/wall_decorated.tscn").instantiate()
	var oven_scene := preload("res://assets/appliances/oven.tscn").instantiate()
	var sink_scene := preload("res://assets/appliances/sink.tscn").instantiate()
	var fridge_scene := preload("res://assets/appliances/fridge.tscn").instantiate()
	add_child(wall)
	add_child(oven_scene)
	add_child(sink_scene)
	add_child(fridge_scene)
	var processors := {
		"cutboard": wall.get_node("cutboard") as ItemProcessor,
		"stove": wall.get_node("stove") as ItemProcessor,
		"oven": oven_scene.get_node("OvenProcessor") as ItemProcessor,
		"sink": sink_scene.get_node("sink") as ItemProcessor,
		"fridge": fridge_scene.get_node("fridge") as ItemProcessor,
	}
	for appliance: String in processors:
		assert(processors[appliance] != null, "Processor missing for %s" % appliance)

	var player := _MockPlayer.new()
	add_child(player)
	for route: Array in ROUTES:
		var processor: ItemProcessor = processors[route[0]]
		var recipe := _find_recipe(processor, StringName(route[1]))
		assert(recipe != null, "%s missing from %s" % [route[1], route[0]])
		assert(recipe.input_item.item_id == StringName(route[2]), "Input mismatch for %s" % route[1])
		assert(recipe.output_item.item_id == StringName(route[3]), "Output mismatch for %s" % route[1])
		assert(recipe.get_action_label() == route[4], "Action mismatch for %s" % route[1])
		assert(is_equal_approx(recipe.hold_duration, route[5]), "Duration mismatch for %s" % route[1])

		player.set_held_item(recipe.input_item)
		assert(processor.can_interact(player), "%s rejected its configured input" % route[1])
		var matching := processor.get_matching_recipes(player)
		if matching.size() > 1:
			assert(processor.get_interaction_prompt(player) == "CHOOSE PREP", "%s should require the picker" % route[1])
			processor.interact(player)
			assert(GameControl.is_process_picker_open(), "%s did not open the picker" % route[1])
			assert(GameControl.select_process_recipe(recipe), "%s could not be selected" % route[1])
		assert(is_equal_approx(processor.get_interaction_hold_duration(player), recipe.hold_duration), "%s exposed the wrong hold duration" % route[1])
		processor.interact(player)
		assert(player.get_held_item() == recipe.output_item, "%s did not produce its configured output" % route[1])
		GameControl.cancel_process_picker()
		processor.clear_process_selection()


func _find_recipe(processor: ItemProcessor, recipe_id: StringName) -> ItemProcessRecipe:
	for recipe in processor.get_process_recipes():
		if recipe.recipe_id == recipe_id:
			return recipe
	return null


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count


class _MockPlayer extends Node:
	var held_item: KitchenItem

	func get_held_item() -> KitchenItem:
		return held_item

	func set_held_item(item: KitchenItem) -> void:
		held_item = item
		GameControl.held_item_changed.emit(item)
