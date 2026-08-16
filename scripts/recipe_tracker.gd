extends Node
## Global recipe manager and discovery tracker for Sous Robot.
##
## Catalogs all composite assembly recipes and appliance preparation routes.
## Maintains runtime records of which recipes have been crafted, how many times,
## and exposes step-by-step creation instructions for UI and gameplay systems.

signal recipe_made(recipe_id: StringName, item: KitchenItem, total_count: int)
signal item_made(item_id: StringName, recipe_id: StringName, total_count: int)
signal automation_available(recipe_id: StringName, recipe_name: String, message: String)
signal tracker_updated()
signal tracker_reset()

const APPLIANCE_FOR_PROCESS: Dictionary = {
	&"slice_bread": "Cutting Board",
	&"chop_carrot": "Cutting Board",
	&"cut_carrot_sticks": "Cutting Board",
	&"slice_cheese": "Cutting Board",
	&"dice_cheese": "Cutting Board",
	&"tear_lettuce_leaf": "Cutting Board",
	&"shred_greens": "Cutting Board",
	&"dice_onion": "Cutting Board",
	&"ring_slice_onion": "Cutting Board",
	&"chop_fries": "Cutting Board",
	&"slice_tomato": "Cutting Board",
	&"slice_tomato_batch": "Cutting Board",
	&"sear_ham": "Stove / Grill",
	&"fry_onion_rings": "Stove / Grill",
	&"mash_potato": "Stove / Oven",
	&"sear_steak": "Stove / Grill",
	&"grill_burger_patty": "Stove / Grill",
	&"grill_veggie_patty": "Stove / Grill",
	&"simmer_stew": "Stove / Grill",
	&"toast_bun_top": "Oven",
	&"toast_bun_bottom": "Oven",
	&"roast_ham": "Oven",
	&"broil_steak": "Oven",
	&"wash_carrot": "Sink",
	&"chill_ham_cooked": "Fridge",
	&"chill_ham_roasted": "Fridge",
	&"chill_salad": "Fridge",
	&"bottle_ketchup": "Fridge",
	&"bottle_mustard": "Fridge",
	&"jar_pickles": "Fridge",
}

const APPLIANCE_CATEGORIES: Dictionary = {
	"Cutting Board": "Cutting Board",
	"Stove / Grill": "Stove / Grill",
	"Stove / Oven": "Stove / Grill",
	"Stove / Simmering": "Stove / Grill",
	"Oven": "Oven",
	"Sink": "Sink",
	"Fridge": "Fridge",
	"Assembly Counter": "Composite Meals",
}

## Explicit progression sort ordering:
## Bread and buns first, single-ingredient preps next, appliance preps follow,
## intermediate combinations, and multi-step complex meals at the end.
const RECIPE_SORT_ORDER: Dictionary = {
	# Tier 1: Starter Breads & Buns (Discovered first)
	&"slice_bread": 10,
	&"two_buns": 20,
	&"toast_bun_bottom": 30,
	&"toast_bun_top": 40,

	# Tier 2: Starter Produce & Cheese Prep (Cutting Board)
	&"slice_cheese": 100,
	&"dice_cheese": 110,
	&"tear_lettuce_leaf": 120,
	&"shred_greens": 130,
	&"slice_tomato": 140,
	&"slice_tomato_batch": 150,
	&"dice_onion": 160,
	&"ring_slice_onion": 170,
	&"chop_carrot": 180,
	&"cut_carrot_sticks": 190,
	&"chop_fries": 200,

	# Tier 3: Basic Cooking (Stove & Grill basics)
	&"grill_burger_patty": 300,
	&"sear_steak": 310,
	&"sear_ham": 320,
	&"fry_onion_rings": 330,
	&"mash_potato": 340,

	# Tier 4: Purchased Appliance Preps (Sink, Fridge, Oven)
	&"wash_carrot": 400,
	&"roast_ham": 410,
	&"broil_steak": 420,
	&"chill_ham_cooked": 430,
	&"chill_ham_roasted": 440,
	&"chill_salad": 450,
	&"bottle_ketchup": 460,
	&"bottle_mustard": 470,
	&"jar_pickles": 480,

	# Tier 5: Intermediate Assemblies & Combos (2-ingredient pre-cooked recipes)
	&"vegetableburger_uncooked": 500,
	&"grill_veggie_patty": 510,
	&"stew_base": 520,

	# Tier 6: Multi-Step Masterpieces & Gourmet Meals (Plated dinners, Slow simmered stew, Burgers)
	&"simmer_stew": 600,
	&"steak_dinner": 610,
	&"steak_dinner_broiled": 620,
	&"cheeseburger": 630,
	&"veggie_burger": 640,
}

var _made_recipes: Dictionary = {}
var _made_items: Dictionary = {}
var _alerted_automation_recipes: Dictionary = {}
var _recipe_history: Array[Dictionary] = []

var _assembly_recipes: Array[Recipe] = []
var _process_recipes: Array[ItemProcessRecipe] = []
var _items_by_id: Dictionary = {}
var _recipes_by_id: Dictionary = {}
var _recipe_details_cache: Dictionary = {}


func _ready() -> void:
	_load_all_resources()
	_build_recipe_catalog()


## Resets all recorded recipe crafting statistics.
func reset_tracker() -> void:
	_made_recipes.clear()
	_made_items.clear()
	_alerted_automation_recipes.clear()
	_recipe_history.clear()
	tracker_reset.emit()
	tracker_updated.emit()


## Records that a specific recipe was crafted.
func record_recipe_made(recipe_id: StringName, item: KitchenItem = null) -> void:
	if recipe_id.is_empty():
		return

	var current_count: int = int(_made_recipes.get(recipe_id, 0)) + 1
	_made_recipes[recipe_id] = current_count

	var resolved_item: KitchenItem = item
	if resolved_item == null and _items_by_id.has(recipe_id):
		resolved_item = _items_by_id[recipe_id] as KitchenItem
	elif resolved_item == null and _recipes_by_id.has(recipe_id):
		var rec: Variant = _recipes_by_id[recipe_id]
		if rec is Recipe:
			resolved_item = (rec as Recipe).output_item
		elif rec is ItemProcessRecipe:
			resolved_item = (rec as ItemProcessRecipe).output_item

	var item_id: StringName = resolved_item.item_id if resolved_item != null else recipe_id
	var item_count: int = int(_made_items.get(item_id, 0)) + 1
	_made_items[item_id] = item_count

	_recipe_history.append({
		"recipe_id": recipe_id,
		"item_id": item_id,
		"count": current_count,
		"timestamp": Time.get_ticks_msec(),
	})

	recipe_made.emit(recipe_id, resolved_item, current_count)
	item_made.emit(item_id, recipe_id, item_count)
	tracker_updated.emit()

	# Trigger new automation alert if this recipe is satisfied and not yet alerted
	trigger_automation_alert_if_satisfied(recipe_id)


## Records an item as made directly by item ID.
func record_item_made(item_id: StringName, recipe_id: StringName = &"") -> void:
	var r_id: StringName = recipe_id if not recipe_id.is_empty() else item_id
	var item: KitchenItem = _items_by_id.get(item_id) as KitchenItem
	record_recipe_made(r_id, item)


## Returns whether the specified recipe ID has been crafted at least once.
func has_made_recipe(recipe_id: StringName) -> bool:
	return int(_made_recipes.get(recipe_id, 0)) > 0


## Returns whether the automation alert for this recipe has already been shown.
func has_alerted_automation(recipe_id: StringName) -> bool:
	return bool(_alerted_automation_recipes.get(recipe_id, false))


## Returns the canonical user-facing name for a recipe.
func get_recipe_name(recipe_id: StringName) -> String:
	if _recipe_details_cache.has(recipe_id):
		var data: Dictionary = _recipe_details_cache[recipe_id]
		var title: String = str(data.get("title", ""))
		if not title.is_empty():
			return title
		var out_name: String = str(data.get("output_name", ""))
		if not out_name.is_empty():
			return out_name
	if _recipes_by_id.has(recipe_id):
		var rec: Variant = _recipes_by_id[recipe_id]
		if rec is Recipe and not (rec as Recipe).display_name.is_empty():
			return (rec as Recipe).display_name
		if rec is ItemProcessRecipe and (rec as ItemProcessRecipe).output_item != null:
			return (rec as ItemProcessRecipe).output_item.display_name
	if _items_by_id.has(recipe_id):
		var it: KitchenItem = _items_by_id[recipe_id] as KitchenItem
		if it != null and not it.display_name.is_empty():
			return it.display_name
	return str(recipe_id).capitalize()


## Checks if all ingredients and appliances for a recipe are currently satisfied (producible) in the kitchen.
func is_recipe_satisfied(recipe_id: StringName, tree: SceneTree = null) -> bool:
	if recipe_id.is_empty():
		return false

	var active_tree := tree
	if active_tree == null:
		active_tree = get_tree()
	if active_tree == null:
		var main_loop := Engine.get_main_loop()
		if main_loop is SceneTree:
			active_tree = main_loop as SceneTree

	var producible := OrderQueue.evaluate_producible_items(active_tree, _items_by_id)

	# 1. Composite assembly recipe
	if _recipes_by_id.has(recipe_id) and _recipes_by_id[recipe_id] is Recipe:
		var rec: Recipe = _recipes_by_id[recipe_id] as Recipe
		if rec.output_item != null and producible.has(rec.output_item.item_id):
			return true
		if not rec.ingredient_sequence.is_empty():
			var all_ings := true
			for ing in rec.ingredient_sequence:
				if ing == null or not producible.has(ing.item_id):
					all_ings = false
					break
			if all_ings and rec.output_item != null:
				return producible.has(rec.output_item.item_id)
		return false

	# 2. Single-process appliance recipe
	if _recipes_by_id.has(recipe_id) and _recipes_by_id[recipe_id] is ItemProcessRecipe:
		var proc: ItemProcessRecipe = _recipes_by_id[recipe_id] as ItemProcessRecipe
		if proc.output_item != null and producible.has(proc.output_item.item_id):
			return true
		return false

	# 3. Details cache fallback
	if _recipe_details_cache.has(recipe_id):
		var data: Dictionary = _recipe_details_cache[recipe_id]
		var out_item: KitchenItem = data.get("output_item") as KitchenItem
		if out_item != null and producible.has(out_item.item_id):
			return true

	return false


## Triggers the "new automation available: [recipe]" alert if the recipe is learned and satisfied.
func trigger_automation_alert_if_satisfied(recipe_id: StringName, tree: SceneTree = null) -> bool:
	if recipe_id.is_empty() or has_alerted_automation(recipe_id):
		return false
	if not has_made_recipe(recipe_id):
		return false
	if is_recipe_satisfied(recipe_id, tree):
		_alerted_automation_recipes[recipe_id] = true
		var rec_name := get_recipe_name(recipe_id)
		var message := "new automation available: %s" % rec_name
		automation_available.emit(recipe_id, rec_name, message)
		return true
	return false


## Evaluates all learned recipes and triggers automation alerts for any newly satisfied recipes.
func check_all_satisfied_automations(tree: SceneTree = null) -> Array[StringName]:
	var unlocked: Array[StringName] = []
	for recipe_id: StringName in _recipe_details_cache:
		if has_made_recipe(recipe_id) and not has_alerted_automation(recipe_id):
			if trigger_automation_alert_if_satisfied(recipe_id, tree):
				unlocked.append(recipe_id)
	return unlocked


## Returns whether the specified item ID has been crafted at least once.
func has_made_item(item_id: StringName) -> bool:
	return int(_made_items.get(item_id, 0)) > 0


## Returns whether an item is automated (crafted/unlocked at least once).
func is_item_automated(item_id: StringName) -> bool:
	if item_id.is_empty():
		return false
	if has_made_item(item_id) or has_made_recipe(item_id):
		return true
	for proc: ItemProcessRecipe in _process_recipes:
		if proc != null and proc.output_item != null and proc.output_item.item_id == item_id:
			if has_made_recipe(proc.recipe_id):
				return true
	for rec: Recipe in _assembly_recipes:
		if rec != null and rec.output_item != null and rec.output_item.item_id == item_id:
			if has_made_recipe(rec.recipe_id):
				return true
	return false


## Returns a dictionary of item_id -> bool automation status for all items in an order.
func get_automatable_items_for_order(order_items: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_id: Variant in order_items:
		var item_id := StringName(str(raw_id))
		result[item_id] = is_item_automated(item_id)
	return result


## Returns true if at least one item in the given order items dictionary is automated.
func has_any_automatable_item(order_items: Dictionary) -> bool:
	for raw_id: Variant in order_items:
		var item_id := StringName(str(raw_id))
		if is_item_automated(item_id):
			return true
	return false


## Returns how many times a recipe has been crafted.
func get_recipe_made_count(recipe_id: StringName) -> int:
	return int(_made_recipes.get(recipe_id, 0))


## Returns how many times an item has been crafted.
func get_item_made_count(item_id: StringName) -> int:
	return int(_made_items.get(item_id, 0))


## Returns an array of all recipe IDs that have been made so far.
func get_made_recipes() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: Variant in _made_recipes:
		if int(_made_recipes[key]) > 0:
			result.append(StringName(key))
	return result


## Returns a dictionary mapping recipe IDs to their craft counts.
func get_made_recipe_counts() -> Dictionary:
	return _made_recipes.duplicate()


## Returns an array of all item IDs that have been made so far.
func get_made_items() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: Variant in _made_items:
		if int(_made_items[key]) > 0:
			result.append(StringName(key))
	return result


## Returns total count of all recipes crafted across the session.
func get_total_recipes_made_count() -> int:
	var total := 0
	for key: Variant in _made_recipes:
		total += int(_made_recipes[key])
	return total


## Returns count of unique recipes crafted (discovered).
func get_discovered_count() -> int:
	var count := 0
	for key: Variant in _made_recipes:
		if int(_made_recipes[key]) > 0:
			count += 1
	return count


## Returns total number of recipes defined in the game catalog.
func get_total_recipe_count() -> int:
	return _recipe_details_cache.size()


## Returns all composite assembly recipes.
func get_all_assembly_recipes() -> Array[Recipe]:
	return _assembly_recipes.duplicate()


## Returns all single-process appliance recipes.
func get_all_process_recipes() -> Array[ItemProcessRecipe]:
	return _process_recipes.duplicate()


## Returns detailed entries for all recipes in the catalog, ordered by natural progression.
func get_all_recipe_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for recipe_id: StringName in _recipe_details_cache:
		var data: Dictionary = _recipe_details_cache[recipe_id].duplicate(true)
		data["made_count"] = get_recipe_made_count(recipe_id)
		data["is_made"] = has_made_recipe(recipe_id)
		entries.append(data)

	# Sort by progression sort_order (Bread & buns first -> multi-step last)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order_a: int = int(a.get("sort_order", 500))
		var order_b: int = int(b.get("sort_order", 500))
		if order_a != order_b:
			return order_a < order_b
		return str(a.get("title", "")).naturalnocasecmp_to(str(b.get("title", ""))) < 0
	)
	return entries


## Returns full details and step-by-step instructions for a specific recipe.
func get_recipe_details(recipe_id: StringName) -> Dictionary:
	if not _recipe_details_cache.has(recipe_id):
		return {}
	var data: Dictionary = _recipe_details_cache[recipe_id].duplicate(true)
	data["made_count"] = get_recipe_made_count(recipe_id)
	data["is_made"] = has_made_recipe(recipe_id)
	return data


## Returns the step list for a specific recipe.
func get_creation_steps(recipe_id: StringName) -> Array[Dictionary]:
	var details := get_recipe_details(recipe_id)
	var steps: Variant = details.get("steps", [])
	if steps is Array:
		var result: Array[Dictionary] = []
		for s: Variant in steps:
			if s is Dictionary:
				result.append(s as Dictionary)
		return result
	return []


# ==============================================================================
# Internal Resource Discovery and Step Building
# ==============================================================================

func _load_all_resources() -> void:
	_items_by_id.clear()
	_assembly_recipes.clear()
	_process_recipes.clear()
	_recipes_by_id.clear()

	# 1. Load Kitchen Items
	var items_dir := DirAccess.open("res://resources/items")
	if items_dir != null:
		items_dir.list_dir_begin()
		var file_name := items_dir.get_next()
		while not file_name.is_empty():
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var path := "res://resources/items/".path_join(file_name)
				var item := load(path) as KitchenItem
				if item != null and not item.item_id.is_empty():
					_items_by_id[item.item_id] = item
			file_name = items_dir.get_next()

	# 2. Load Assembly Recipes
	var recipes_dir := DirAccess.open("res://resources/recipes")
	if recipes_dir != null:
		recipes_dir.list_dir_begin()
		var file_name := recipes_dir.get_next()
		while not file_name.is_empty():
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var path := "res://resources/recipes/".path_join(file_name)
				var recipe := load(path) as Recipe
				if recipe != null and not recipe.recipe_id.is_empty():
					_assembly_recipes.append(recipe)
					_recipes_by_id[recipe.recipe_id] = recipe
			file_name = recipes_dir.get_next()

	# 3. Load Process Recipes
	var proc_dir := DirAccess.open("res://resources/processing")
	if proc_dir != null:
		proc_dir.list_dir_begin()
		var file_name := proc_dir.get_next()
		while not file_name.is_empty():
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var path := "res://resources/processing/".path_join(file_name)
				var proc_recipe := load(path) as ItemProcessRecipe
				if proc_recipe != null and not proc_recipe.recipe_id.is_empty():
					_process_recipes.append(proc_recipe)
					_recipes_by_id[proc_recipe.recipe_id] = proc_recipe
			file_name = proc_dir.get_next()


func _build_recipe_catalog() -> void:
	_recipe_details_cache.clear()

	# 1. Build composite assembly recipe details
	_build_composite_recipe(
		&"two_buns",
		"Two Buns Plate",
		"Assembly Counter",
		"Pair of freshly sliced artisan buns prepped for service or side orders.",
		_items_by_id.get(&"two_buns") as KitchenItem,
		[
			{"step_num": 1, "action": "SLICE BREAD", "appliance": "Cutting Board", "input": "Fresh Bread", "output": "Bun", "instruction": "Slice fresh bread at the Cutting Board and place on Assembly Counter."},
			{"step_num": 2, "action": "SLICE BREAD", "appliance": "Cutting Board", "input": "Fresh Bread", "output": "Bun", "instruction": "Slice a second fresh bread at the Cutting Board and add to the counter."},
			{"step_num": 3, "action": "COLLECT DISH", "appliance": "Assembly Counter", "input": "Two Buns", "output": "Two Buns Plate", "instruction": "Pick up the completed Two Buns Plate!"}
		],
		8.0
	)

	_build_composite_recipe(
		&"vegetableburger_uncooked",
		"Uncooked Veggie Patty",
		"Assembly Counter",
		"Raw blend of finely chopped carrots and diced onions ready for grilling.",
		_items_by_id.get(&"vegetableburger_uncooked") as KitchenItem,
		[
			{"step_num": 1, "action": "CHOP CARROT", "appliance": "Cutting Board", "input": "Fresh Carrot", "output": "Chopped Carrots", "instruction": "Chop carrot on the Cutting Board and place on Assembly Counter."},
			{"step_num": 2, "action": "DICE ONION", "appliance": "Cutting Board", "input": "Fresh Onion", "output": "Diced Onion", "instruction": "Dice onion on the Cutting Board and add to Assembly Counter."},
			{"step_num": 3, "action": "COLLECT ITEM", "appliance": "Assembly Counter", "input": "Combined Ingredients", "output": "Uncooked Veggie Patty", "instruction": "Pick up the prepared veggie patty for cooking on the stove."}
		],
		11.5
	)

	_build_composite_recipe(
		&"stew_base",
		"Hearty Stew Base",
		"Assembly Counter",
		"Seared beef steak and chopped carrots assembled in a pot, ready for slow simmering.",
		_items_by_id.get(&"stew_base") as KitchenItem,
		[
			{"step_num": 1, "action": "SEAR STEAK", "appliance": "Stove / Grill", "input": "Raw Beef Steak", "output": "Seared Steak Bites", "instruction": "Sear steak on the Stove and place into the Assembly Counter pot."},
			{"step_num": 2, "action": "CHOP CARROT", "appliance": "Cutting Board", "input": "Fresh Carrot", "output": "Chopped Carrots", "instruction": "Chop carrot on the Cutting Board and add to the pot."},
			{"step_num": 3, "action": "COLLECT ITEM", "appliance": "Assembly Counter", "input": "Combined Ingredients", "output": "Stew Base", "instruction": "Pick up the Hearty Stew Base to take to the stove for simmering."}
		],
		18.0
	)

	_build_composite_recipe(
		&"steak_dinner",
		"Plated Steak Dinner",
		"Assembly Counter",
		"Tender seared beef steak served over rich, homestyle mashed potatoes.",
		_items_by_id.get(&"steak_dinner") as KitchenItem,
		[
			{"step_num": 1, "action": "MASH POTATO", "appliance": "Stove / Oven", "input": "Raw Russet Potato", "output": "Homestyle Mashed Potatoes", "instruction": "Mash potato on the Stove or in the Oven, then place base on Assembly Counter."},
			{"step_num": 2, "action": "SEAR STEAK", "appliance": "Stove / Grill", "input": "Raw Beef Steak", "output": "Seared Steak Bites", "instruction": "Sear steak on the Stove until golden and plate onto mashed potatoes."},
			{"step_num": 3, "action": "COLLECT DISH", "appliance": "Assembly Counter", "input": "Completed Dinner", "output": "Plated Steak Dinner", "instruction": "Pick up the finished Plated Steak Dinner!"}
		],
		24.0
	)

	_build_composite_recipe(
		&"steak_dinner_broiled",
		"Broiled Steak Dinner",
		"Assembly Counter",
		"Caramelized oven-broiled steak served with creamy mashed potatoes.",
		_items_by_id.get(&"steak_dinner") as KitchenItem,
		[
			{"step_num": 1, "action": "MASH POTATO", "appliance": "Stove / Oven", "input": "Raw Russet Potato", "output": "Homestyle Mashed Potatoes", "instruction": "Mash potato on the Stove or in the Oven, place on Assembly Counter."},
			{"step_num": 2, "action": "BROIL STEAK", "appliance": "Oven", "input": "Raw Beef Steak", "output": "Oven-Broiled Steak", "instruction": "Broil steak in the Oven and place on top of mashed potatoes."},
			{"step_num": 3, "action": "COLLECT DISH", "appliance": "Assembly Counter", "input": "Completed Dinner", "output": "Broiled Steak Dinner", "instruction": "Pick up the finished Broiled Steak Dinner!"}
		],
		24.0
	)

	_build_composite_recipe(
		&"cheeseburger",
		"Classic Cheeseburger",
		"Assembly Counter",
		"A juicy grilled burger patty topped with melted cheddar on warm toasted buns.",
		_items_by_id.get(&"cheeseburger") as KitchenItem,
		[
			{"step_num": 1, "action": "TOAST BUN", "appliance": "Oven", "input": "Fresh Bread", "output": "Toasted Bun Bottom", "instruction": "Place fresh bread in the Oven to toast Bun Bottom, then place on Assembly Counter."},
			{"step_num": 2, "action": "GRILL PATTY", "appliance": "Stove / Grill", "input": "Raw Beef Steak", "output": "Cooked Burger Patty", "instruction": "Sear burger patty on the Stove and place on the bottom bun."},
			{"step_num": 3, "action": "SLICE CHEESE", "appliance": "Cutting Board", "input": "Cheese Block", "output": "Cheese Slice", "instruction": "Slice cheese block on the Cutting Board and add the slice to the burger stack."},
			{"step_num": 4, "action": "TOAST BUN", "appliance": "Oven", "input": "Fresh Bread", "output": "Toasted Bun Top", "instruction": "Toast top bun in the Oven and crown the stack to finish."},
			{"step_num": 5, "action": "COLLECT DISH", "appliance": "Assembly Counter", "input": "Completed Stack", "output": "Classic Cheeseburger", "instruction": "Pick up the finished Classic Cheeseburger!"}
		],
		22.0
	)

	_build_composite_recipe(
		&"veggie_burger",
		"Garden Veggie Burger",
		"Assembly Counter",
		"Healthy veggie patty stacked with fresh sliced tomato, crisp lettuce, and toasted buns.",
		_items_by_id.get(&"veggie_burger") as KitchenItem,
		[
			{"step_num": 1, "action": "TOAST BUN", "appliance": "Oven", "input": "Fresh Bread", "output": "Toasted Bun Bottom", "instruction": "Toast bun in the Oven to get Bun Bottom, place on Assembly Counter."},
			{"step_num": 2, "action": "PREP & GRILL PATTY", "appliance": "Stove / Grill", "input": "Uncooked Veggie Patty", "output": "Cooked Veggie Patty", "instruction": "Assemble veggie patty (Carrots + Onions on Counter), then grill on Stove and place on bun."},
			{"step_num": 3, "action": "TEAR LEAF", "appliance": "Cutting Board", "input": "Fresh Lettuce", "output": "Lettuce Leaf", "instruction": "Tear fresh lettuce leaf on the Cutting Board and place on patty."},
			{"step_num": 4, "action": "SLICE TOMATO", "appliance": "Cutting Board", "input": "Fresh Tomato", "output": "Tomato Slice", "instruction": "Slice fresh tomato on the Cutting Board and add to the stack."},
			{"step_num": 5, "action": "TOAST BUN", "appliance": "Oven", "input": "Fresh Bread", "output": "Toasted Bun Top", "instruction": "Toast top bun in the Oven and place on top of the stack."},
			{"step_num": 6, "action": "COLLECT DISH", "appliance": "Assembly Counter", "input": "Completed Stack", "output": "Garden Veggie Burger", "instruction": "Pick up the finished Garden Veggie Burger!"}
		],
		20.0
	)

	# 2. Build Single-Appliance Process Recipes
	for proc in _process_recipes:
		if proc == null or not proc.is_valid():
			continue
		var recipe_id: StringName = proc.recipe_id
		var app_name: String = str(APPLIANCE_FOR_PROCESS.get(recipe_id, "Appliance"))
		var in_name: String = proc.input_item.display_name if proc.input_item != null else str(proc.input_item.item_id).capitalize()
		var out_name: String = proc.output_item.display_name if proc.output_item != null else str(proc.output_item.item_id).capitalize()
		var verb: String = proc.get_action_label()

		var step_inst: String = "Take %s to the %s and %s into %s." % [
			in_name, app_name, verb.to_lower(), out_name
		]

		var steps: Array[Dictionary] = [
			{
				"step_num": 1,
				"action": verb,
				"appliance": app_name,
				"input": in_name,
				"output": out_name,
				"instruction": step_inst,
			}
		]

		var desc := "Transform %s into %s using the %s." % [in_name, out_name, app_name]
		if recipe_id == &"simmer_stew":
			desc = "Slow-simmered beef steak and tender carrots in rich savory broth."

		_build_process_recipe_entry(
			recipe_id,
			out_name,
			app_name,
			desc,
			proc.output_item,
			steps,
			_estimate_item_price(proc.output_item.item_id if proc.output_item != null else &"")
		)


func _build_composite_recipe(
	recipe_id: StringName,
	title: String,
	category: String,
	description: String,
	output: KitchenItem,
	steps: Array[Dictionary],
	price: float
) -> void:
	_recipe_details_cache[recipe_id] = {
		"recipe_id": recipe_id,
		"title": title,
		"category": category,
		"filter_category": APPLIANCE_CATEGORIES.get(category, "Composite Meals"),
		"description": description,
		"output_item": output,
		"output_name": output.display_name if output != null else title,
		"steps": steps,
		"price": price,
		"is_composite": true,
		"sort_order": int(RECIPE_SORT_ORDER.get(recipe_id, 500)),
	}


func _build_process_recipe_entry(
	recipe_id: StringName,
	title: String,
	appliance: String,
	description: String,
	output: KitchenItem,
	steps: Array[Dictionary],
	price: float
) -> void:
	_recipe_details_cache[recipe_id] = {
		"recipe_id": recipe_id,
		"title": title,
		"category": appliance,
		"filter_category": APPLIANCE_CATEGORIES.get(appliance, appliance),
		"description": description,
		"output_item": output,
		"output_name": output.display_name if output != null else title,
		"steps": steps,
		"price": price,
		"is_composite": false,
		"sort_order": int(RECIPE_SORT_ORDER.get(recipe_id, 500)),
	}


func _estimate_item_price(item_id: StringName) -> float:
	match item_id:
		&"bread": return 3.0
		&"bun": return 4.5
		&"two_buns": return 8.0
		&"carrot": return 3.5
		&"carrot_washed": return 5.5
		&"carrot_chopped", &"carrot_pieces": return 5.0
		&"cheese": return 4.5
		&"cheese_slice", &"cheese_chopped": return 6.0
		&"ham": return 5.0
		&"ham_cooked", &"ham_roasted": return 8.5
		&"ham_chilled": return 10.0
		&"lettuce": return 3.5
		&"lettuce_slice", &"lettuce_chopped": return 5.0
		&"salad_chilled": return 8.0
		&"onion": return 3.5
		&"onion_chopped", &"onion_rings": return 5.0
		&"onion_rings_fried": return 7.5
		&"potato": return 3.5
		&"potato_chopped": return 5.0
		&"potato_mashed": return 7.5
		&"steak": return 6.5
		&"steak_pieces": return 9.5
		&"steak_broiled": return 11.0
		&"burger_cooked": return 12.5
		&"vegetableburger_cooked": return 11.5
		&"cheeseburger": return 22.0
		&"veggie_burger": return 20.0
		&"steak_dinner": return 24.0
		&"beef_stew": return 22.0
		&"tomato": return 3.5
		&"tomato_slice", &"tomato_slices": return 5.0
		&"ketchup", &"mustard", &"pickles": return 7.5
		_: return 5.0
