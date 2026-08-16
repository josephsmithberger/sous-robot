extends Node

const COUNTER_SCENE: PackedScene = preload("res://assets/appliances/counter.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

const BUN_ITEM: KitchenItem = preload("res://resources/items/bun.tres")
const TWO_BUNS_ITEM: KitchenItem = preload("res://resources/items/two_buns.tres")
const CARROT_ITEM: KitchenItem = preload("res://resources/items/carrot.tres")

const RECIPES: Array[Recipe] = [
	preload("res://resources/recipes/cheeseburger.tres"),
	preload("res://resources/recipes/vegetableburger_uncooked.tres"),
	preload("res://resources/recipes/veggie_burger.tres"),
	preload("res://resources/recipes/steak_dinner.tres"),
	preload("res://resources/recipes/steak_dinner_broiled.tres"),
	preload("res://resources/recipes/stew_base.tres"),
]


func _ready() -> void:
	print("Starting AssemblyCounter smoke test...")
	var counter_node: Node3D = COUNTER_SCENE.instantiate()
	add_child(counter_node)
	var player: PlayerController = PLAYER_SCENE.instantiate()
	add_child(player)
	await get_tree().physics_frame
	await get_tree().process_frame

	var spot1: AssemblyCounter = counter_node.get_node("counter") as AssemblyCounter
	var spot2: AssemblyCounter = counter_node.get_node("counter2") as AssemblyCounter
	assert(spot1 != null and spot2 != null, "Counter scene must have counter and counter2 areas")

	_test_empty_and_invalid_starter(spot1, player)
	_test_legacy_two_buns(spot1, player)
	_test_recipe_catalog()
	_test_every_composite_recipe(spot1, player)
	_test_retrieval_and_invalid_prefix(spot1, player)
	_test_second_counter_and_order_reset(spot1, spot2, player)

	print("ASSEMBLY_COUNTER_SMOKE_PASS")
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0)


func _test_empty_and_invalid_starter(counter: AssemblyCounter, player: PlayerController) -> void:
	counter.reset_counter()
	player.set_held_item(null)
	assert(not counter.can_interact(player), "Empty counter should reject empty hands")
	assert(counter.get_interaction_prompt(player) == "", "Empty counter prompt should be blank")
	player.set_held_item(CARROT_ITEM)
	assert(not counter.can_interact(player), "Counter should reject a raw carrot starter")
	assert(counter.get_interaction_prompt(player) == "CANNOT COMBINE", "Invalid starter prompt should be CANNOT COMBINE")
	player.set_held_item(null)


func _test_legacy_two_buns(counter: AssemblyCounter, player: PlayerController) -> void:
	counter.reset_counter()
	_add_item(counter, player, BUN_ITEM, "legacy first bun")
	assert(counter.is_in_progress(), "Legacy recipe should be in progress after first bun")
	assert(counter.placed_items[0].item_id == &"bun", "Legacy counter should retain bun input")

	player.set_held_item(null)
	assert(counter.get_interaction_prompt(player) == "TAKE BUN", "In-progress prompt should offer the last bun")
	counter.interact(player)
	assert(player.is_holding(&"bun"), "Player should retrieve the placed bun")
	assert(counter.is_empty(), "Counter should be empty after retrieving its only ingredient")

	_add_item(counter, player, BUN_ITEM, "legacy first bun after retrieval")
	_add_item(counter, player, BUN_ITEM, "legacy second bun")
	assert(counter.is_completed(), "Two buns should complete the legacy recipe")
	assert(counter.completed_item.item_id == &"two_buns", "Legacy recipe output should be two_buns")
	player.set_held_item(null)
	counter.interact(player)
	assert(player.is_holding(&"two_buns"), "Player should take the completed two_buns dish")
	assert(counter.is_empty(), "Counter should reset after taking two_buns")


func _test_every_composite_recipe(counter: AssemblyCounter, player: PlayerController) -> void:
	for recipe in RECIPES:
		assert(recipe != null, "Composite recipe resource must load")
		assert(not recipe.ingredient_sequence.is_empty(), "%s must define ingredients" % recipe.recipe_id)
		counter.reset_counter()
		player.set_held_item(null)
		for ingredient in recipe.ingredient_sequence:
			assert(ingredient != null, "%s contains a null ingredient" % recipe.recipe_id)
			var invalid := _find_invalid_item(counter, player, ingredient)
			if invalid != null:
				player.set_held_item(invalid)
				assert(not counter.can_interact(player), "%s should reject invalid next ingredient %s" % [recipe.recipe_id, invalid.item_id])
				player.set_held_item(null)
			_add_item(counter, player, ingredient, "%s ingredient %s" % [recipe.recipe_id, ingredient.item_id])
		assert(counter.is_completed(), "%s should complete" % recipe.recipe_id)
		assert(counter.completed_item != null and counter.completed_item.item_id == recipe.output_item.item_id, "%s output mismatch" % recipe.recipe_id)
		player.set_held_item(null)
		counter.interact(player)
		assert(player.is_holding(recipe.output_item.item_id), "%s output should be takeable" % recipe.recipe_id)


func _test_recipe_catalog() -> void:
	var expected_sequences: Dictionary = {
		&"cheeseburger": [&"bun_bottom", &"burger_cooked", &"cheese_slice", &"bun_top"],
		&"vegetableburger_uncooked": [&"carrot_chopped", &"onion_chopped"],
		&"veggie_burger": [&"bun_bottom", &"vegetableburger_cooked", &"lettuce_slice", &"tomato_slice", &"bun_top"],
		&"steak_dinner": [&"potato_mashed", &"steak_pieces"],
		&"steak_dinner_broiled": [&"potato_mashed", &"steak_broiled"],
		&"stew_base": [&"steak_pieces", &"carrot_chopped"],
	}
	for recipe in RECIPES:
		assert(expected_sequences.has(recipe.recipe_id), "Unexpected composite recipe %s" % recipe.recipe_id)
		var expected: Array = expected_sequences[recipe.recipe_id]
		assert(recipe.ingredient_sequence.size() == expected.size(), "%s sequence length mismatch" % recipe.recipe_id)
		for i in expected.size():
			assert(recipe.ingredient_sequence[i].item_id == expected[i], "%s ingredient %d mismatch" % [recipe.recipe_id, i])


func _test_retrieval_and_invalid_prefix(counter: AssemblyCounter, player: PlayerController) -> void:
	var recipe: Recipe = RECIPES[0]
	counter.reset_counter()
	player.set_held_item(null)
	_add_item(counter, player, recipe.ingredient_sequence[0], "cheeseburger first ingredient")
	var wrong: KitchenItem = _find_invalid_item(counter, player, recipe.ingredient_sequence[1])
	assert(wrong != null, "Must find an invalid cheeseburger continuation")
	player.set_held_item(wrong)
	assert(counter.get_interaction_prompt(player) == "CANNOT COMBINE", "Invalid continuation should show CANNOT COMBINE")
	assert(counter.placed_items.size() == 1, "Invalid continuation must not mutate placed ingredients")
	player.set_held_item(null)
	counter.interact(player)
	assert(player.is_holding(recipe.ingredient_sequence[0].item_id), "Counter should retrieve an in-progress ingredient")
	assert(counter.is_empty(), "Retrieval should clear the counter")


func _test_second_counter_and_order_reset(counter: AssemblyCounter, second: AssemblyCounter, player: PlayerController) -> void:
	counter.reset_counter()
	second.reset_counter()
	_add_item(counter, player, BUN_ITEM, "spot1 pre-reset bun")
	_add_item(second, player, BUN_ITEM, "spot2 pre-reset bun")
	assert(counter.is_in_progress() and second.is_in_progress(), "Both counter spots should be independently usable")
	GameControl.order_started.emit(42, {})
	assert(counter.is_empty() and second.is_empty(), "New order should reset every counter spot")
	assert(counter._visual_instances.is_empty() and second._visual_instances.is_empty(), "Reset should clean counter visuals")


func _add_item(counter: AssemblyCounter, player: PlayerController, item: KitchenItem, label: String) -> void:
	player.set_held_item(item)
	assert(counter.can_interact(player), "%s should be accepted" % label)
	counter.interact(player)
	assert(not player.has_held_item(), "%s should clear the player's hands" % label)


func _find_invalid_item(counter: AssemblyCounter, player: PlayerController, expected: KitchenItem) -> KitchenItem:
	var candidates: Array[KitchenItem] = [BUN_ITEM, CARROT_ITEM, TWO_BUNS_ITEM]
	for candidate in candidates:
		if candidate == null or expected == null or candidate.item_id == expected.item_id:
			continue
		player.set_held_item(candidate)
		if not counter.can_interact(player):
			player.set_held_item(null)
			return candidate
	player.set_held_item(null)
	return null
