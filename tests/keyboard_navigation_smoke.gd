extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const MASTER_DIALOGUE: DialogueResource = preload("res://dialogue/master.dialogue")


func _ready() -> void:
	print("Starting KeyboardNavigationSmoke test...")
	var game_node := GAME_SCENE.instantiate()
	add_child(game_node)
	GameControl.reset_session(100.0)
	await get_tree().physics_frame
	await get_tree().process_frame

	var tabs := game_node.find_child("TabContainer", true, false) as TabContainer
	assert(tabs != null, "TabContainer must exist")
	var hand_off_btn := game_node.find_child("HandOffButton", true, false) as Button
	assert(hand_off_btn != null, "HandOffButton must exist")
	var arrange_btn := game_node.find_child("ArrangeButton", true, false) as Button
	assert(arrange_btn != null, "ArrangeButton must exist")
	var rotate_btn := game_node.find_child("RotateButton", true, false) as Button
	assert(rotate_btn != null, "RotateButton must exist")
	var place_btn := game_node.find_child("PlaceButton", true, false) as Button
	assert(place_btn != null, "PlaceButton must exist")
	var cancel_place_btn := game_node.find_child("CancelPlacementButton", true, false) as Button
	assert(cancel_place_btn != null, "CancelPlacementButton must exist")

	# --- 1. Verify Keyboard Mode Prompts ---
	GameControl.input_mode = GameControl.InputMode.KEYBOARD
	await get_tree().process_frame

	assert(tabs.get_tab_title(0) == "KITCHEN (1)", "Tab 0 title must include (1) in keyboard mode")
	assert(tabs.get_tab_title(1) == "RECIPES (2)", "Tab 1 title must include (2) in keyboard mode")
	assert(tabs.get_tab_title(2) == "STORE (3)", "Tab 2 title must include (3) in keyboard mode")
	assert(hand_off_btn.text == "HAND OFF (H)", "HandOffButton must show (H) in keyboard mode")
	assert(arrange_btn.text == "ARRANGE (G)", "ArrangeButton must show (G) in keyboard mode")
	assert(rotate_btn.text == "ROTATE (R)", "RotateButton must show (R) in keyboard mode")
	assert(place_btn.text == "PLACE (ENTER)", "PlaceButton must show (ENTER) in keyboard mode")
	assert(cancel_place_btn.text == "CANCEL (ESC)", "CancelPlacementButton must show (ESC) in keyboard mode")

	# --- 2. Verify Touch Mode (Prompts Stripped) ---
	GameControl.input_mode = GameControl.InputMode.TOUCH
	await get_tree().process_frame

	assert(tabs.get_tab_title(0) == "KITCHEN", "Tab 0 title must be 'KITCHEN' in touch mode")
	assert(tabs.get_tab_title(1) == "RECIPES", "Tab 1 title must be 'RECIPES' in touch mode")
	assert(tabs.get_tab_title(2) == "STORE", "Tab 2 title must be 'STORE' in touch mode")
	assert(hand_off_btn.text == "HAND OFF", "HandOffButton must be 'HAND OFF' in touch mode")
	assert(arrange_btn.text == "ARRANGE", "ArrangeButton must be 'ARRANGE' in touch mode")
	assert(rotate_btn.text == "ROTATE", "RotateButton must be 'ROTATE' in touch mode")
	assert(place_btn.text == "PLACE", "PlaceButton must be 'PLACE' in touch mode")
	assert(cancel_place_btn.text == "CANCEL", "CancelPlacementButton must be 'CANCEL' in touch mode")

	# Return to keyboard mode for navigation testing
	GameControl.input_mode = GameControl.InputMode.KEYBOARD
	await get_tree().process_frame

	# Dismiss introductory dialogue so keys can navigate
	GameControl._on_dialogue_ended(MASTER_DIALOGUE)
	await get_tree().process_frame

	# --- 3. Test Tab Switching with 1, 2, 3 Keys ---
	assert(tabs.current_tab == 0, "Must start on Kitchen tab")

	# Press '2' -> Recipes
	var key2 := InputEventKey.new()
	key2.pressed = true
	key2.keycode = KEY_2
	GameControl._input(key2)
	await get_tree().process_frame
	assert(tabs.current_tab == 1, "Pressing '2' must switch to Recipes tab")

	# Press '3' -> Store
	var key3 := InputEventKey.new()
	key3.pressed = true
	key3.keycode = KEY_3
	GameControl._input(key3)
	await get_tree().process_frame
	assert(tabs.current_tab == 2, "Pressing '3' must switch to Store tab")

	# Press '1' -> Kitchen
	var key1 := InputEventKey.new()
	key1.pressed = true
	key1.keycode = KEY_1
	GameControl._input(key1)
	await get_tree().process_frame
	assert(tabs.current_tab == 0, "Pressing '1' must switch to Kitchen tab")

	# Switch to Store tab and press Escape -> Returns to Kitchen
	GameControl.request_tab_switch(2)
	await get_tree().process_frame
	assert(tabs.current_tab == 2, "Tab should be Store")
	var esc_key := InputEventKey.new()
	esc_key.pressed = true
	esc_key.keycode = KEY_ESCAPE
	GameControl._input(esc_key)
	await get_tree().process_frame
	assert(tabs.current_tab == 0, "Pressing ESC on Store tab must return to Kitchen tab")

	# --- 4. Test Arrange Mode with 'G' Key ---
	assert(not GameControl.is_arranging, "Should not be arranging initially")
	var g_key := InputEventKey.new()
	g_key.pressed = true
	g_key.keycode = KEY_G
	GameControl._input(g_key)
	await get_tree().process_frame
	assert(GameControl.is_arranging, "Pressing 'G' must enter arrange mode")
	assert(arrange_btn.text == "CONFIRM (G)", "Arrange button must show CONFIRM (G) in arrange mode")

	# Press 'G' again to confirm
	GameControl._input(g_key)
	await get_tree().process_frame
	assert(not GameControl.is_arranging, "Pressing 'G' again must confirm and exit arrange mode")
	assert(arrange_btn.text == "ARRANGE (G)", "Arrange button must return to ARRANGE (G)")

	# --- 5. Test Bot Handoff with 'H' Key ---
	var modal := game_node.find_child("BotHandoff", true, false) as PanelContainer
	assert(modal != null, "BotHandoff panel must exist")
	assert(not modal.visible, "BotHandoff modal should start hidden")

	# Start an active order
	var order_data := {
		"order_id": 1,
		"items": {&"bun": 2},
		"base_reward": 5.0,
		"tip": 2.0,
	}
	GameControl.begin_order(1, order_data)

	# Press 'H' -> Opens Bot Handoff modal
	var h_key := InputEventKey.new()
	h_key.pressed = true
	h_key.keycode = KEY_H
	GameControl._input(h_key)
	await get_tree().process_frame
	assert(modal.visible, "Pressing 'H' must open Bot Handoff modal when order is active")

	# Press 'H' again -> Closes Bot Handoff modal
	GameControl._input(h_key)
	await get_tree().process_frame
	assert(not modal.visible, "Pressing 'H' again must close Bot Handoff modal")

	print("KEYBOARD_NAVIGATION_SMOKE_PASS")
	get_tree().quit(0)
