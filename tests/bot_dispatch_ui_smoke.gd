extends Node
## Automated smoke test for Bot Dispatch UI and automation handoff system.

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const BOT_HANDOFF_SCENE: PackedScene = preload("res://scenes/bot_handoff.tscn")
const KITCHEN_SCENE: PackedScene = preload("res://scenes/kitchen.tscn")
const BREAD_ITEM: KitchenItem = preload("res://resources/items/bread.tres")
const BUN_ITEM: KitchenItem = preload("res://resources/items/bun.tres")
const ORDER_DIALOGUE: DialogueResource = preload("res://dialogue/orders.dialogue")
const SENOR_FOOD_DIALOGUE: DialogueResource = preload("res://dialogue/master.dialogue")


func _ready() -> void:
	print("Starting BotDispatchUISmoke test...")
	_test_item_automation_tracking()
	await get_tree().process_frame
	_test_has_any_automatable_item()
	await get_tree().process_frame
	_test_bot_handoff_standalone_scene()
	await get_tree().process_frame
	_test_bot_dispatch_modal_creation_and_lifecycle()
	await get_tree().process_frame
	_test_spinbox_clamping_to_three_bots()
	await get_tree().process_frame
	_test_confirm_and_cancel_bot_dispatch()
	await get_tree().process_frame
	_test_order_queue_conditional_dispatch_trigger()
	await get_tree().process_frame
	_test_bot_handoff_deferred_until_dialogue_ends()
	await get_tree().process_frame
	_test_mouse_mode_visible_during_handoff()
	await get_tree().process_frame
	_test_stepper_buttons_and_keyboard_interaction()
	await get_tree().process_frame
	print("BOT_DISPATCH_UI_SMOKE_PASS")
	get_tree().quit(0)


func _test_item_automation_tracking() -> void:
	RecipeTracker.reset_tracker()
	assert(not RecipeTracker.is_item_automated(&"bun"), "bun should NOT be automated initially")
	assert(not RecipeTracker.is_item_automated(&"bread"), "bread should NOT be automated initially")
	assert(not RecipeTracker.is_item_automated(&"cheeseburger"), "cheeseburger should NOT be automated initially")

	# Craft slice_bread (produces bun)
	RecipeTracker.record_recipe_made(&"slice_bread")

	assert(RecipeTracker.is_item_automated(&"bun"), "bun should BE automated after crafting slice_bread")
	assert(not RecipeTracker.is_item_automated(&"cheeseburger"), "cheeseburger should still NOT be automated")

	# Craft cheese_slice directly
	RecipeTracker.record_recipe_made(&"slice_cheese")
	assert(RecipeTracker.is_item_automated(&"cheese_slice"), "cheese_slice should be automated after slice_cheese")


func _test_has_any_automatable_item() -> void:
	RecipeTracker.reset_tracker()

	var order_items := {
		&"bun": 4,
		&"bread": 2,
	}

	assert(not RecipeTracker.has_any_automatable_item(order_items), "Should have 0 automatable items before crafting")

	var auto_map := RecipeTracker.get_automatable_items_for_order(order_items)
	assert(not auto_map[&"bun"], "bun should not be marked automatable")
	assert(not auto_map[&"bread"], "bread should not be marked automatable")

	# Now craft slice_bread
	RecipeTracker.record_recipe_made(&"slice_bread")

	assert(RecipeTracker.has_any_automatable_item(order_items), "Should have automatable items after bun is crafted")
	auto_map = RecipeTracker.get_automatable_items_for_order(order_items)
	assert(auto_map[&"bun"], "bun should now be marked automatable")
	assert(not auto_map[&"bread"], "bread should still not be automatable")


func _test_bot_handoff_standalone_scene() -> void:
	var handoff_node := BOT_HANDOFF_SCENE.instantiate() as BotHandoffUI
	assert(handoff_node != null, "scenes/bot_handoff.tscn must instantiate as BotHandoffUI")
	add_child(handoff_node)
	assert(not handoff_node.visible, "BotHandoff should start hidden")
	assert(handoff_node.confirm_button != null, "ConfirmButton must be wired via @onready")
	assert(handoff_node.cancel_button != null, "CancelButton must be wired via @onready")
	assert(handoff_node.items_list != null, "ItemsList must be wired via @onready")
	handoff_node.queue_free()


func _test_bot_dispatch_modal_creation_and_lifecycle() -> void:
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)
	GameControl._on_dialogue_ended(SENOR_FOOD_DIALOGUE)

	# Craft bun after instantiating game_node
	RecipeTracker.record_recipe_made(&"slice_bread")

	var modal := game_node.find_child("BotHandoff", true, false) as PanelContainer
	assert(modal != null, "BotHandoff panel must exist in Kitchen InteractionStage")
	assert(not modal.visible, "BotHandoff should start hidden")

	var hand_off_btn := game_node.find_child("HandOffButton", true, false) as Button
	assert(hand_off_btn != null, "HandOffButton must exist")
	assert(hand_off_btn.text == "HAND OFF", "HandOffButton should be labeled 'HAND OFF'")

	# Request bot dispatch for order
	var order_data := {
		"order_id": 1,
		"items": {&"bun": 4, &"bread": 2},
		"base_reward": 5.0,
		"tip": 2.0,
	}

	GameControl.begin_order(1, order_data)
	GameControl.request_bot_dispatch(1, order_data)

	assert(modal.visible, "Modal should become visible after request_bot_dispatch")
	assert(GameControl.is_bot_dispatch_open(), "GameControl.is_bot_dispatch_open() must be true")

	var title_lbl := modal.find_child("Title", true, false) as Label
	assert(title_lbl != null and title_lbl.text.containsn("BOT HANDOFF"), "Title should show BOT HANDOFF")

	var items_list := modal.find_child("ItemsList", true, false) as VBoxContainer
	assert(items_list != null, "ItemsList container must exist")
	assert(items_list.get_child_count() == 2, "ItemsList should have 2 rows for the 2 ordered items")

	# Check the row for bun
	var bun_row := items_list.find_child("Row_bun", true, false) as PanelContainer
	assert(bun_row != null, "Row_bun must exist")
	var bun_spinbox := bun_row.find_child("SpinBox", true, false) as SpinBox
	assert(bun_spinbox != null, "SpinBox must exist for automated bun item")
	assert(bun_spinbox.max_value == 4, "bun spinbox max_value should equal required quantity 4")

	# Check the row for bread (unlocked=false)
	var bread_row := items_list.find_child("Row_bread", true, false) as PanelContainer
	assert(bread_row != null, "Row_bread must exist")
	var bread_spinbox := bread_row.find_child("SpinBox", true, false) as SpinBox
	assert(bread_spinbox == null, "Bread should not have an active SpinBox because it is not automated yet")

	game_node.queue_free()


func _test_spinbox_clamping_to_three_bots() -> void:
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)
	GameControl._on_dialogue_ended(SENOR_FOOD_DIALOGUE)

	# Craft both bun and cheese_slice
	RecipeTracker.record_recipe_made(&"slice_bread")
	RecipeTracker.record_recipe_made(&"slice_cheese")

	var order_data := {
		"order_id": 2,
		"items": {&"bun": 4, &"cheese_slice": 3},
		"base_reward": 10.0,
		"tip": 3.0,
	}

	GameControl.begin_order(2, order_data)
	GameControl.request_bot_dispatch(2, order_data)

	var modal := game_node.find_child("BotHandoff", true, false) as PanelContainer
	var items_list := modal.find_child("ItemsList", true, false) as VBoxContainer

	var bun_spinbox := items_list.find_child("Row_bun", true, false).find_child("SpinBox", true, false) as SpinBox
	var cheese_spinbox := items_list.find_child("Row_cheese_slice", true, false).find_child("SpinBox", true, false) as SpinBox

	assert(bun_spinbox != null and cheese_spinbox != null, "Both spinboxes must exist")

	# Set bun to 2 bots
	bun_spinbox.value = 2
	assert(bun_spinbox.value == 2, "Bun bots should be 2")

	# Set cheese to 1 bot -> total = 3
	cheese_spinbox.value = 1
	assert(cheese_spinbox.value == 1, "Cheese bots should be 1")

	# Try to increase cheese to 2 bots -> total would be 4 -> must clamp cheese to 1 bot!
	cheese_spinbox.value = 2
	assert(cheese_spinbox.value == 1, "Cheese bots must clamp to 1 so total bots does not exceed 3")

	# Now decrease bun to 1 bot -> cheese can now be increased to 2 bots!
	bun_spinbox.value = 1
	cheese_spinbox.value = 2
	assert(bun_spinbox.value == 1 and cheese_spinbox.value == 2, "Bun=1, Cheese=2 should sum to 3")

	# Try to set bun to 3 bots -> total would be 5 -> must clamp bun to 1!
	bun_spinbox.value = 3
	assert(bun_spinbox.value == 1, "Bun bots must clamp to 1 (3 - 2) so total does not exceed 3")

	game_node.queue_free()


func _test_confirm_and_cancel_bot_dispatch() -> void:
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)
	GameControl._on_dialogue_ended(SENOR_FOOD_DIALOGUE)

	RecipeTracker.record_recipe_made(&"slice_bread")

	var order_data := {
		"order_id": 3,
		"items": {&"bun": 4},
		"base_reward": 5.0,
		"tip": 2.0,
	}

	GameControl.begin_order(3, order_data)
	GameControl.request_bot_dispatch(3, order_data)

	var modal := game_node.find_child("BotHandoff", true, false) as PanelContainer
	var items_list := modal.find_child("ItemsList", true, false) as VBoxContainer
	var bun_spinbox := items_list.find_child("Row_bun", true, false).find_child("SpinBox", true, false) as SpinBox

	bun_spinbox.value = 3

	var received_allocations: Dictionary = {}
	var cb := func(o_id: int, allocs: Dictionary) -> void:
		received_allocations.merge(allocs, true)

	GameControl.bots_assigned.connect(cb)

	var confirm_btn := modal.find_child("ConfirmButton", true, false) as Button
	confirm_btn.pressed.emit()

	assert(not modal.visible, "Modal must hide on confirm")
	assert(not GameControl.is_bot_dispatch_open(), "is_bot_dispatch_open must be false")
	assert(received_allocations.has(&"bun"), "Allocations should include bun")
	assert(int(received_allocations[&"bun"]) == 3, "Bun allocation should be 3")
	assert(int(GameControl.get_active_bot_allocations().get(&"bun", 0)) == 3, "GameControl should store active allocation")

	GameControl.bots_assigned.disconnect(cb)
	game_node.queue_free()


func _test_order_queue_conditional_dispatch_trigger() -> void:
	GameControl.reset_session()
	RecipeTracker.reset_tracker()
	var kitchen := KITCHEN_SCENE.instantiate()
	add_child(kitchen)

	var queue := kitchen.find_child("OrderQueue", true, false) as OrderQueue
	assert(queue != null, "OrderQueue must exist in kitchen scene")

	var front_waiter := queue.get_front_waiter()
	assert(front_waiter != null, "Front waiter must exist")

	var dispatch_data := {"received": false}
	var cb := func(_id: int, _order: Dictionary, _auto: Dictionary) -> void:
		dispatch_data["received"] = true

	GameControl.bot_dispatch_requested.connect(cb)

	# Case 1: Order with items that are NOT automated yet
	front_waiter.order_data = {
		"items": {&"steak_dinner": 1},
		"base_reward": 24.0,
		"tip": 6.0,
	}

	queue._accept_front_order(front_waiter)

	assert(not dispatch_data["received"], "Bot dispatch should NOT trigger if requested items are not automated")
	assert(not GameControl.is_bot_dispatch_open(), "Bot dispatch modal must stay closed")

	# Finish order & clear queue active order
	GameControl.end_order(1)
	queue._active_order.clear()
	dispatch_data["received"] = false

	# Case 2: Player crafts bun, now bun is automated
	RecipeTracker.record_recipe_made(&"slice_bread")

	# Waiter asks for bun
	front_waiter.order_data = {
		"items": {&"bun": 2},
		"base_reward": 4.0,
		"tip": 1.5,
	}

	queue._accept_front_order(front_waiter)

	assert(dispatch_data["received"], "Bot dispatch MUST trigger when ordered item is automated")
	assert(GameControl.is_bot_dispatch_open(), "Bot dispatch modal must be open")

	GameControl.bot_dispatch_requested.disconnect(cb)
	kitchen.queue_free()


func _test_bot_handoff_deferred_until_dialogue_ends() -> void:
	GameControl.reset_session()
	RecipeTracker.reset_tracker()
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)
	GameControl._on_dialogue_ended(SENOR_FOOD_DIALOGUE)

	RecipeTracker.record_recipe_made(&"slice_bread")

	var modal := game_node.find_child("BotHandoff", true, false) as PanelContainer
	assert(modal != null, "BotHandoff modal must exist")
	assert(not modal.visible, "Modal starts hidden")

	# Start dialogue
	GameControl._on_dialogue_started(ORDER_DIALOGUE)
	assert(GameControl.is_dialogue_active(), "Dialogue should be active")

	# Accept order with automated item during dialogue
	var order_data := {
		"order_id": 4,
		"items": {&"bun": 2},
		"base_reward": 5.0,
		"tip": 2.0,
	}
	GameControl.begin_order(4, order_data)
	GameControl.request_bot_dispatch(4, order_data)

	# Verify handoff UI did NOT pop up during dialogue
	assert(not modal.visible, "Bot handoff modal MUST NOT come up during dialogue")
	assert(not GameControl.is_bot_dispatch_open(), "is_bot_dispatch_open must be false during dialogue")

	# End dialogue
	GameControl._on_dialogue_ended(ORDER_DIALOGUE)
	assert(not GameControl.is_dialogue_active(), "Dialogue should have ended")

	# Verify handoff UI pops up after dialogue ends
	assert(modal.visible, "Bot handoff modal MUST come up after dialogue completes")
	assert(GameControl.is_bot_dispatch_open(), "is_bot_dispatch_open must be true after dialogue completes")

	# Dismiss modal
	GameControl.cancel_bot_dispatch(4)
	assert(not modal.visible, "Modal should hide after cancel")
	assert(not GameControl.is_bot_dispatch_open(), "is_bot_dispatch_open should be false after cancel")

	game_node.queue_free()


func _test_mouse_mode_visible_during_handoff() -> void:
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)
	GameControl._on_dialogue_ended(SENOR_FOOD_DIALOGUE)
	RecipeTracker.record_recipe_made(&"slice_bread")

	# Simulate first person gameplay with captured mouse
	GameControl.set_controllable(true)
	GameControl.give_player_control()
	assert(GameControl.has_player_control(), "Player should have control before handoff")

	var order_data := {
		"order_id": 10,
		"items": {&"bun": 2},
		"base_reward": 5.0,
		"tip": 2.0,
	}
	GameControl.begin_order(10, order_data)
	GameControl.request_bot_dispatch(10, order_data)

	assert(GameControl.is_bot_dispatch_open(), "Bot dispatch modal should be open")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Mouse mode MUST be VISIBLE while bot dispatch modal is open")
	assert(not GameControl.has_player_control(), "Player must not control 3D player while modal is open")

	GameControl.cancel_bot_dispatch(10)
	assert(not GameControl.is_bot_dispatch_open(), "Modal closed")

	game_node.queue_free()


func _test_stepper_buttons_and_keyboard_interaction() -> void:
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)
	GameControl._on_dialogue_ended(SENOR_FOOD_DIALOGUE)
	RecipeTracker.record_recipe_made(&"slice_bread")

	var modal := game_node.find_child("BotHandoff", true, false) as BotHandoffUI
	assert(modal != null, "BotHandoffUI should exist")

	var order_data := {
		"order_id": 11,
		"items": {&"bun": 3},
		"base_reward": 5.0,
		"tip": 2.0,
	}
	GameControl.begin_order(11, order_data)
	GameControl.request_bot_dispatch(11, order_data)

	var bun_row := modal.items_list.find_child("Row_bun", true, false)
	assert(bun_row != null, "Row_bun should exist")

	var plus_btn := bun_row.find_child("PlusButton", true, false) as Button
	var minus_btn := bun_row.find_child("MinusButton", true, false) as Button
	var spinbox := bun_row.find_child("SpinBox", true, false) as SpinBox

	assert(plus_btn != null and minus_btn != null and spinbox != null, "Plus/Minus buttons and SpinBox must exist")
	assert(spinbox.value == 0, "Initial value should be 0")

	# Test mouse button press (+ and -)
	plus_btn.pressed.emit()
	assert(spinbox.value == 1, "Clicking plus button should increment value to 1")
	plus_btn.pressed.emit()
	assert(spinbox.value == 2, "Clicking plus button again should increment value to 2")
	minus_btn.pressed.emit()
	assert(spinbox.value == 1, "Clicking minus button should decrement value to 1")

	# Test keyboard shortcut events (Right arrow, Left arrow, Number keys, Enter)
	var right_event := InputEventKey.new()
	right_event.pressed = true
	right_event.keycode = KEY_RIGHT
	modal._unhandled_input(right_event)
	assert(spinbox.value == 2, "Right arrow key should increment bot assignment to 2")

	var left_event := InputEventKey.new()
	left_event.pressed = true
	left_event.keycode = KEY_LEFT
	modal._unhandled_input(left_event)
	assert(spinbox.value == 1, "Left arrow key should decrement bot assignment to 1")

	var num_event := InputEventKey.new()
	num_event.pressed = true
	num_event.keycode = KEY_3
	modal._unhandled_input(num_event)
	assert(spinbox.value == 3, "Pressing key '3' should set bot assignment to 3")

	# Test Enter key confirms bot dispatch
	var enter_event := InputEventKey.new()
	enter_event.pressed = true
	enter_event.keycode = KEY_ENTER
	modal._unhandled_input(enter_event)

	assert(not modal.visible, "Modal should close after pressing Enter")
	assert(not GameControl.is_bot_dispatch_open(), "Bot dispatch is closed")
	assert(int(GameControl.get_active_bot_allocations().get(&"bun", 0)) == 3, "Bots allocated should be 3")

	game_node.queue_free()

