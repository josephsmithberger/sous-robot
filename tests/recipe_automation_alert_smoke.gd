extends Node
## Automated smoke test for recipe creation and satisfaction automation alerts.

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const KITCHEN_SCENE: PackedScene = preload("res://scenes/kitchen.tscn")
const BREAD_ITEM: KitchenItem = preload("res://resources/items/bread.tres")
const BUN_BOTTOM_ITEM: KitchenItem = preload("res://resources/items/bun_bottom.tres")
const BUN_TOP_ITEM: KitchenItem = preload("res://resources/items/bun_top.tres")
const BURGER_COOKED_ITEM: KitchenItem = preload("res://resources/items/burger_cooked.tres")
const CHEESE_SLICE_ITEM: KitchenItem = preload("res://resources/items/cheese_slice.tres")

const COUNTER_SCENE: PackedScene = preload("res://assets/appliances/counter.tscn")
const OVEN_SCENE: PackedScene = preload("res://assets/appliances/oven.tscn")
const STEAK_CRATE_SCENE: PackedScene = preload("res://assets/appliances/crate_steak.tscn")
const CHEESE_CRATE_SCENE: PackedScene = preload("res://assets/appliances/crate_cheese.tscn")


func _ready() -> void:
	print("Starting RecipeAutomationAlertSmoke test...")
	_test_recipe_name_helper()
	_test_starter_kitchen_recipe_satisfaction()
	await get_tree().process_frame
	_test_learn_satisfied_recipe_emits_alert()
	await get_tree().process_frame
	_test_duplicate_craft_does_not_re_alert()
	await get_tree().process_frame
	_test_unsatisfied_recipe_alerts_when_dependencies_satisfied()
	await get_tree().process_frame
	_test_game_ui_alert_banner_lifecycle()
	await get_tree().process_frame
	_test_game_ui_alert_banner_spam_restarts_timer()
	await get_tree().process_frame
	print("RECIPE_AUTOMATION_ALERT_SMOKE_PASS")
	get_tree().quit(0)


func _test_recipe_name_helper() -> void:
	RecipeTracker.reset_tracker()
	assert(RecipeTracker.get_recipe_name(&"slice_bread") == "Bun", "slice_bread name should be 'Bun'")
	assert(RecipeTracker.get_recipe_name(&"two_buns") == "Two Buns Plate", "two_buns name should be 'Two Buns Plate'")
	assert(RecipeTracker.get_recipe_name(&"cheeseburger") == "Classic Cheeseburger", "cheeseburger name should be 'Classic Cheeseburger'")
	assert(RecipeTracker.get_recipe_name(&"veggie_burger") == "Garden Veggie Burger", "veggie_burger name should be 'Garden Veggie Burger'")


func _test_starter_kitchen_recipe_satisfaction() -> void:
	RecipeTracker.reset_tracker()
	var kitchen := KITCHEN_SCENE.instantiate()
	add_child(kitchen)

	# Starter kitchen has BunCrate, DecoratedWall (Cutting Board + Stove)
	assert(RecipeTracker.is_recipe_satisfied(&"slice_bread", get_tree()), "slice_bread should be satisfied in starter kitchen")
	assert(not RecipeTracker.is_recipe_satisfied(&"two_buns", get_tree()), "two_buns should NOT be satisfied without AssemblyCounter")
	assert(not RecipeTracker.is_recipe_satisfied(&"cheeseburger", get_tree()), "cheeseburger should NOT be satisfied without all ingredients & Oven/Counter")

	kitchen.queue_free()


func _test_learn_satisfied_recipe_emits_alert() -> void:
	RecipeTracker.reset_tracker()
	var kitchen := KITCHEN_SCENE.instantiate()
	add_child(kitchen)

	var signal_data := {
		"emitted": false,
		"recipe_id": &"",
		"recipe_name": "",
		"message": "",
	}

	var cb := func(r_id: StringName, r_name: String, msg: String) -> void:
		signal_data["emitted"] = true
		signal_data["recipe_id"] = r_id
		signal_data["recipe_name"] = r_name
		signal_data["message"] = msg

	RecipeTracker.automation_available.connect(cb)

	assert(not RecipeTracker.has_alerted_automation(&"slice_bread"), "Should not have alerted slice_bread initially")

	# Craft slice_bread for the first time
	RecipeTracker.record_recipe_made(&"slice_bread")

	assert(signal_data["emitted"], "automation_available signal must emit when crafting satisfied recipe")
	assert(signal_data["recipe_id"] == &"slice_bread", "recipe_id should be slice_bread")
	assert(signal_data["recipe_name"] == "Bun", "recipe_name should be Bun")
	assert(signal_data["message"] == "new automation available: Bun", "message must say 'new automation available: Bun'")
	assert(RecipeTracker.has_alerted_automation(&"slice_bread"), "has_alerted_automation must be true")

	RecipeTracker.automation_available.disconnect(cb)
	kitchen.queue_free()


func _test_duplicate_craft_does_not_re_alert() -> void:
	RecipeTracker.reset_tracker()
	var kitchen := KITCHEN_SCENE.instantiate()
	add_child(kitchen)

	var tracker := {"emit_count": 0}
	var cb := func(_r_id: StringName, _r_name: String, _msg: String) -> void:
		tracker["emit_count"] = int(tracker["emit_count"]) + 1

	RecipeTracker.automation_available.connect(cb)

	# First craft
	RecipeTracker.record_recipe_made(&"slice_bread")
	assert(tracker["emit_count"] == 1, "First craft must emit 1 alert")

	# Second and third craft of same recipe
	RecipeTracker.record_recipe_made(&"slice_bread")
	RecipeTracker.record_recipe_made(&"slice_bread")
	assert(tracker["emit_count"] == 1, "Subsequent crafts must NOT emit additional alerts")

	RecipeTracker.automation_available.disconnect(cb)
	kitchen.queue_free()


func _test_unsatisfied_recipe_alerts_when_dependencies_satisfied() -> void:
	RecipeTracker.reset_tracker()
	var kitchen := KITCHEN_SCENE.instantiate()
	add_child(kitchen)

	var alerted_recipes: Array[StringName] = []
	var cb := func(r_id: StringName, _r_name: String, _msg: String) -> void:
		alerted_recipes.append(r_id)

	RecipeTracker.automation_available.connect(cb)

	# Learn/craft two_buns (suppose created before having counter)
	RecipeTracker.record_recipe_made(&"two_buns")

	# In starter kitchen, AssemblyCounter is missing so two_buns is not satisfied
	assert(not alerted_recipes.has(&"two_buns"), "two_buns must not alert while unsatisfied")
	assert(not RecipeTracker.has_alerted_automation(&"two_buns"), "has_alerted_automation must be false")

	# Now place AssemblyCounter in kitchen
	var counter := COUNTER_SCENE.instantiate()
	kitchen.add_child(counter)

	# Check satisfaction
	var newly_unlocked := RecipeTracker.check_all_satisfied_automations(get_tree())
	assert(newly_unlocked.has(&"two_buns"), "two_buns should now be unlocked and satisfied")
	assert(alerted_recipes.has(&"two_buns"), "automation_available must emit for two_buns once satisfied")
	assert(RecipeTracker.has_alerted_automation(&"two_buns"), "has_alerted_automation must now be true")

	RecipeTracker.automation_available.disconnect(cb)
	counter.queue_free()
	kitchen.queue_free()


func _test_game_ui_alert_banner_lifecycle() -> void:
	RecipeTracker.reset_tracker()
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)

	var alert_panel := game_node.find_child("AlertBanner", true, false) as PanelContainer
	assert(alert_panel != null, "AlertBanner panel container must exist in Kitchen InteractionStage")
	assert(not alert_panel.visible, "AlertBanner should start hidden")

	var alert_label := alert_panel.find_child("AlertLabel", true, false) as Label
	assert(alert_label != null, "AlertLabel must exist")
	assert(alert_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "Alert text must be centered")

	# Trigger alert signal directly
	RecipeTracker.automation_available.emit(&"cheeseburger", "Classic Cheeseburger", "new automation available: Classic Cheeseburger")

	assert(alert_panel.visible, "AlertBanner should become visible after automation_available signal")
	assert(alert_label.text == "new automation available: Classic Cheeseburger", "AlertLabel text should show centered 'new automation available: [recipe]'")

	game_node.queue_free()


func _test_game_ui_alert_banner_spam_restarts_timer() -> void:
	RecipeTracker.reset_tracker()
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)

	var alert_panel := game_node.find_child("AlertBanner", true, false) as PanelContainer
	assert(alert_panel != null, "AlertBanner panel must exist")
	var alert_label := alert_panel.find_child("AlertLabel", true, false) as Label
	assert(alert_label != null, "AlertLabel must exist")

	var hand_off_btn := game_node.find_child("HandOffButton", true, false) as Button
	assert(hand_off_btn != null, "HandOffButton must exist")

	# First press with no active order
	hand_off_btn.emit_signal("pressed")
	assert(alert_panel.visible, "AlertBanner should be visible")
	assert(alert_label.text == "No active order to hand off!", "Alert should indicate no active order")
	assert(game_node.get("_alert_queue").size() == 0, "Alert queue should be empty after popping initial alert")

	# Spam press multiple times
	for _i in range(10):
		hand_off_btn.emit_signal("pressed")

	# Alert queue must NOT grow when spammed
	assert(game_node.get("_alert_queue").size() == 0, "Spamming the button should NOT queue multiple alerts")
	assert(alert_panel.visible, "AlertBanner should remain visible and restart timer")

	game_node.queue_free()

