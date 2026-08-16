extends Node
## Automated smoke test for Recipes Tab UI, creation steps, progression sorting, and RecipeTracker.

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const RECIPES_SCENE: PackedScene = preload("res://scenes/recipes.tscn")
const COUNTER_SCENE: PackedScene = preload("res://assets/appliances/counter.tscn")
const WALL_SCENE: PackedScene = preload("res://assets/appliances/wall_decorated.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

const BREAD_ITEM: KitchenItem = preload("res://resources/items/bread.tres")
const BUN_ITEM: KitchenItem = preload("res://resources/items/bun.tres")
const BUN_BOTTOM_ITEM: KitchenItem = preload("res://resources/items/bun_bottom.tres")
const BUN_TOP_ITEM: KitchenItem = preload("res://resources/items/bun_top.tres")
const BURGER_COOKED_ITEM: KitchenItem = preload("res://resources/items/burger_cooked.tres")
const CHEESE_SLICE_ITEM: KitchenItem = preload("res://resources/items/cheese_slice.tres")


func _ready() -> void:
	print("Starting RecipesTabSmoke test...")
	_test_recipe_tracker_catalog()
	_test_progression_sorting()
	_test_recipe_tracker_recording_and_queries()
	_test_creation_steps_content()
	_test_assembly_counter_recording()
	_test_item_processor_recording()
	_test_recipes_ui_scene()
	_test_game_scene_tabs_integration()
	print("RECIPES_TAB_SMOKE_PASS")
	await get_tree().process_frame
	get_tree().quit(0)


func _test_recipe_tracker_catalog() -> void:
	RecipeTracker.reset_tracker()
	assert(RecipeTracker.get_total_recipe_count() >= 35, "Catalog should have at least 35 recipes (composite + processes)")
	assert(RecipeTracker.get_discovered_count() == 0, "Discovered count should start at 0")
	assert(RecipeTracker.get_total_recipes_made_count() == 0, "Total crafted should start at 0")
	assert(RecipeTracker.get_made_recipes().is_empty(), "Made recipes list should start empty")

	var assembly_recipes := RecipeTracker.get_all_assembly_recipes()
	assert(assembly_recipes.size() >= 6, "Should discover at least 6 assembly recipes")

	var process_recipes := RecipeTracker.get_all_process_recipes()
	assert(process_recipes.size() >= 25, "Should discover at least 25 process recipes")


func _test_progression_sorting() -> void:
	var entries := RecipeTracker.get_all_recipe_entries()
	assert(entries.size() >= 35, "Entries must have all recipes")

	# The first entries must be bread and bun recipes
	var first_ids: Array[StringName] = []
	for i in mini(4, entries.size()):
		first_ids.append(entries[i]["recipe_id"])

	assert(first_ids.has(&"slice_bread") or first_ids.has(&"two_buns"), "Bread/buns should appear at the top of the progression list")

	# The last entries must be complex multi-step dishes
	var last_ids: Array[StringName] = []
	for i in range(maxi(0, entries.size() - 5), entries.size()):
		last_ids.append(entries[i]["recipe_id"])

	assert(last_ids.has(&"cheeseburger") or last_ids.has(&"veggie_burger") or last_ids.has(&"steak_dinner"), "Complex multi-step dishes should appear at the end of the progression list")


func _test_recipe_tracker_recording_and_queries() -> void:
	RecipeTracker.reset_tracker()

	var signal_data := {
		"emitted": false,
		"recipe_id": &"",
		"count": 0,
		"tracker_updated": false,
	}

	var cb_recipe := func(r_id: StringName, _item: KitchenItem, cnt: int) -> void:
		signal_data["emitted"] = true
		signal_data["recipe_id"] = r_id
		signal_data["count"] = cnt

	var cb_update := func() -> void:
		signal_data["tracker_updated"] = true

	RecipeTracker.recipe_made.connect(cb_recipe)
	RecipeTracker.tracker_updated.connect(cb_update)

	assert(not RecipeTracker.has_made_recipe(&"cheeseburger"), "Cheeseburger should not be made initially")
	assert(RecipeTracker.get_recipe_made_count(&"cheeseburger") == 0, "Cheeseburger count should be 0")

	# Record first craft
	RecipeTracker.record_recipe_made(&"cheeseburger")
	assert(signal_data["emitted"], "recipe_made signal should emit")
	assert(signal_data["recipe_id"] == &"cheeseburger", "Signal recipe_id should match")
	assert(signal_data["count"] == 1, "Signal count should be 1")
	assert(signal_data["tracker_updated"], "tracker_updated signal should emit")
	assert(RecipeTracker.has_made_recipe(&"cheeseburger"), "Cheeseburger should now be made")
	assert(RecipeTracker.get_recipe_made_count(&"cheeseburger") == 1, "Cheeseburger count should be 1")
	assert(RecipeTracker.get_made_recipes().has(&"cheeseburger"), "get_made_recipes should contain cheeseburger")
	assert(RecipeTracker.get_discovered_count() == 1, "Discovered count should be 1")
	assert(RecipeTracker.get_total_recipes_made_count() == 1, "Total crafted count should be 1")

	# Record second craft of same recipe
	RecipeTracker.record_recipe_made(&"cheeseburger")
	assert(RecipeTracker.get_recipe_made_count(&"cheeseburger") == 2, "Cheeseburger count should now be 2")
	assert(RecipeTracker.get_discovered_count() == 1, "Discovered count should remain 1")
	assert(RecipeTracker.get_total_recipes_made_count() == 2, "Total crafted count should be 2")

	# Record another recipe
	RecipeTracker.record_recipe_made(&"slice_bread")
	assert(RecipeTracker.has_made_recipe(&"slice_bread"), "slice_bread should now be made")
	assert(RecipeTracker.get_discovered_count() == 2, "Discovered count should now be 2")
	assert(RecipeTracker.get_total_recipes_made_count() == 3, "Total crafted count should now be 3")

	var made_counts := RecipeTracker.get_made_recipe_counts()
	assert(made_counts[&"cheeseburger"] == 2, "Made counts cheeseburger mismatch")
	assert(made_counts[&"slice_bread"] == 1, "Made counts slice_bread mismatch")

	RecipeTracker.recipe_made.disconnect(cb_recipe)
	RecipeTracker.tracker_updated.disconnect(cb_update)


func _test_creation_steps_content() -> void:
	# Test Cheeseburger steps
	var cb_steps := RecipeTracker.get_creation_steps(&"cheeseburger")
	assert(cb_steps.size() >= 4, "Cheeseburger must have multiple creation steps")
	var found_bun_toast := false
	var found_patty_grill := false
	var found_cheese_slice := false

	for step in cb_steps:
		assert(step.has("action") and step.has("appliance") and step.has("instruction"), "Step dictionary must have required keys")
		var inst: String = step["instruction"]
		if inst.containsn("Oven") or inst.containsn("Toast"):
			found_bun_toast = true
		if inst.containsn("Stove") or inst.containsn("Sear") or inst.containsn("Grill"):
			found_patty_grill = true
		if inst.containsn("Cutting Board") or inst.containsn("Slice"):
			found_cheese_slice = true

	assert(found_bun_toast, "Cheeseburger steps must instruct toasting bun in Oven")
	assert(found_patty_grill, "Cheeseburger steps must instruct grilling patty on Stove")
	assert(found_cheese_slice, "Cheeseburger steps must instruct slicing cheese on Cutting Board")

	# Test Veggie Burger steps
	var vb_steps := RecipeTracker.get_creation_steps(&"veggie_burger")
	assert(vb_steps.size() >= 5, "Veggie burger must have multiple creation steps")

	# Test Steak Dinner steps
	var sd_steps := RecipeTracker.get_creation_steps(&"steak_dinner")
	assert(sd_steps.size() >= 2, "Steak dinner must have multiple creation steps")

	# Test Slice Bread process step
	var sb_steps := RecipeTracker.get_creation_steps(&"slice_bread")
	assert(sb_steps.size() == 1, "Single-process recipe should have 1 step")
	assert(sb_steps[0]["appliance"] == "Cutting Board", "slice_bread appliance should be Cutting Board")


func _test_assembly_counter_recording() -> void:
	RecipeTracker.reset_tracker()
	var counter_node: Node3D = COUNTER_SCENE.instantiate()
	add_child(counter_node)
	var player: PlayerController = PLAYER_SCENE.instantiate()
	add_child(player)

	var spot1: AssemblyCounter = counter_node.get_node("counter") as AssemblyCounter
	assert(spot1 != null, "Counter spot must exist")
	spot1.reset_counter()

	# Craft cheeseburger: bun_bottom -> burger_cooked -> cheese_slice -> bun_top
	player.set_held_item(BUN_BOTTOM_ITEM)
	spot1.interact(player)
	player.set_held_item(BURGER_COOKED_ITEM)
	spot1.interact(player)
	player.set_held_item(CHEESE_SLICE_ITEM)
	spot1.interact(player)
	player.set_held_item(BUN_TOP_ITEM)
	spot1.interact(player)

	assert(spot1.is_completed(), "Counter should be completed")
	assert(spot1.completed_item.item_id == &"cheeseburger", "Counter output should be cheeseburger")
	assert(RecipeTracker.has_made_recipe(&"cheeseburger"), "AssemblyCounter should have recorded cheeseburger to RecipeTracker")
	assert(RecipeTracker.get_recipe_made_count(&"cheeseburger") == 1, "Cheeseburger craft count should be 1")

	counter_node.queue_free()
	player.queue_free()


func _test_item_processor_recording() -> void:
	RecipeTracker.reset_tracker()
	var wall_node: Node3D = WALL_SCENE.instantiate()
	add_child(wall_node)
	var player: PlayerController = PLAYER_SCENE.instantiate()
	add_child(player)

	var cutboard: ItemProcessor = wall_node.get_node("cutboard") as ItemProcessor
	assert(cutboard != null, "Cutboard processor must exist")

	player.set_held_item(BREAD_ITEM)
	assert(cutboard.can_interact(player), "Cutboard should accept bread")
	cutboard.interact(player)

	assert(player.is_holding(&"bun"), "Player should now hold bun")
	assert(RecipeTracker.has_made_recipe(&"slice_bread"), "ItemProcessor should have recorded slice_bread to RecipeTracker")
	assert(RecipeTracker.get_recipe_made_count(&"slice_bread") == 1, "slice_bread craft count should be 1")

	wall_node.queue_free()
	player.queue_free()


func _test_recipes_ui_scene() -> void:
	RecipeTracker.reset_tracker()
	var ui: RecipesUI = RECIPES_SCENE.instantiate() as RecipesUI
	add_child(ui)

	var stats: Label = ui.get_node("%StatsLabel") as Label
	var search: LineEdit = ui.get_node("%SearchInput") as LineEdit
	var list: VBoxContainer = ui.get_node("%RecipesList") as VBoxContainer
	var empty_lbl: Label = ui.get_node("%EmptySearchLabel") as Label

	assert(stats != null and search != null and list != null and empty_lbl != null, "Recipes UI components must exist")
	assert(list.get_child_count() >= 30, "RecipesList should contain cards for all recipes")

	# Test that prep time label is NOT present on cards
	var first_card: PanelContainer = list.get_child(0) as PanelContainer
	assert(first_card != null, "First card must exist")
	for child in first_card.find_children("", "Label", true, false):
		if child is Label:
			assert(not (child as Label).text.containsn("Prep:"), "Cards must not display prep time")

	# Test category filter: COMPOSITE
	var comp_btn: Button = ui.get_node("%CategoryBar/COMPOSITE") as Button
	assert(comp_btn != null, "COMPOSITE filter button must exist")
	comp_btn.pressed.emit()

	var visible_composite_count := 0
	for child in list.get_children():
		if (child as Control).visible:
			visible_composite_count += 1
	assert(visible_composite_count >= 6, "Composite filter should show at least 6 composite recipes")

	# Test search filter
	search.text = "Cheeseburger"
	search.text_changed.emit("Cheeseburger")
	var visible_search_count := 0
	for child in list.get_children():
		if (child as Control).visible:
			visible_search_count += 1
	assert(visible_search_count == 1, "Searching for Cheeseburger should show exactly 1 card")

	# Test search with no matches
	search.text = "NonExistentDish12345"
	search.text_changed.emit("NonExistentDish12345")
	assert(empty_lbl.visible, "Empty label should be visible when no search matches")

	# Clear search and reset category to ALL
	search.text = ""
	search.text_changed.emit("")
	var all_btn: Button = ui.get_node("%CategoryBar/ALL") as Button
	all_btn.pressed.emit()
	assert(not empty_lbl.visible, "Empty label should be hidden after clearing search")

	# Test live badge update when a recipe is crafted
	var cb_card: PanelContainer = list.get_node("RecipeCard_cheeseburger") as PanelContainer
	assert(cb_card != null, "Cheeseburger card must exist in list")
	var made_badge: PanelContainer = cb_card.find_child("MadeBadge", true, false) as PanelContainer
	var badge_label: Label = made_badge.get_node("Label") as Label
	assert(badge_label.text == "NOT MADE YET", "Initial badge should be NOT MADE YET")

	RecipeTracker.record_recipe_made(&"cheeseburger")
	assert(badge_label.text.containsn("MADE"), "Badge text should update to MADE after crafting")
	assert(stats.text.containsn("DISCOVERED: 1"), "Stats label should update discovered count")

	ui.queue_free()


func _test_game_scene_tabs_integration() -> void:
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)

	var tabs: TabContainer = game_node.get_node("MarginContainer/HSplitContainer/TabContainer") as TabContainer
	assert(tabs != null, "TabContainer must exist in game scene")
	assert(tabs.get_tab_count() == 3, "TabContainer should have 3 tabs (Kitchen, Recipes, Store)")
	assert(tabs.get_tab_title(0) == "KITCHEN", "Tab 0 should be KITCHEN")
	assert(tabs.get_tab_title(1) == "RECIPES", "Tab 1 should be RECIPES")
	assert(tabs.get_tab_title(2) == "STORE", "Tab 2 should be STORE")

	var recipes_tab: Node = tabs.get_node("Recipes")
	assert(recipes_tab is RecipesUI, "Recipes tab should be an instance of RecipesUI")

	game_node.queue_free()
