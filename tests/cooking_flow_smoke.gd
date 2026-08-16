extends Node

const KITCHEN := preload("res://scenes/kitchen.tscn")

var delivered_item: KitchenItem


func _ready() -> void:
	assert(InputMap.has_action(&"interact"), "interact input action is missing")
	var space_is_bound := false
	for event in InputMap.action_get_events(&"interact"):
		if event is InputEventKey and (
			(event as InputEventKey).physical_keycode == KEY_SPACE
			or (event as InputEventKey).keycode == KEY_SPACE
		):
			space_is_bound = true
	assert(space_is_bound, "Space is not bound to interact")

	var kitchen := KITCHEN.instantiate()
	add_child(kitchen)
	await get_tree().physics_frame
	GameControl.set_controllable(true)
	GameControl.give_player_control()

	var player := kitchen.get_node("player")
	var crate := kitchen.get_node("Architecture/crate_buns/buns") as InteractionArea
	var cutting_board := kitchen.get_node("Architecture/wall_decorated/cutboard") as InteractionArea
	var order_window := kitchen.get_node("Architecture/wall_orderwindow_decorated/order_window") as InteractionArea
	assert(crate != null and cutting_board != null and order_window != null, "Cooking interactables did not load")

	player._on_area_entered(crate)
	assert(GameControl.interaction_prompt == "TAKE BREAD")
	GameControl.request_interaction()
	assert(player.is_holding(&"bread"), "Crate did not place bread in the hand")
	player._on_area_exited(crate)

	player._on_area_entered(cutting_board)
	assert(GameControl.interaction_prompt == "HOLD TO SLICE BREAD")
	GameControl.request_interaction()
	await get_tree().create_timer(0.35).timeout
	var progress_before_refresh := GameControl.interaction_progress
	assert(progress_before_refresh > 0.0, "Hold progress did not start")

	# Simulate the forced target refresh caused by a noisy Area3D boundary.
	player._update_interaction_target(true)
	await get_tree().create_timer(0.2).timeout
	assert(
		GameControl.interaction_progress > progress_before_refresh,
		"Hold progress restarted when the same target refreshed"
	)

	# Simulate OS key repeats (echo events) and repeated interaction requests while holding
	var echo_event := InputEventKey.new()
	echo_event.physical_keycode = KEY_SPACE
	echo_event.pressed = true
	echo_event.echo = true
	GameControl._input(echo_event)
	GameControl.request_interaction()

	var progress_after_echo := GameControl.interaction_progress
	assert(
		progress_after_echo >= progress_before_refresh,
		"Hold progress reset on key repeat or repeated interaction request"
	)

	await get_tree().create_timer(0.8).timeout
	assert(player.is_holding(&"bun"), "Cutting board did not produce bun")
	player._on_area_exited(cutting_board)

	GameControl.item_delivered.connect(_on_item_delivered, CONNECT_ONE_SHOT)
	GameControl.begin_order(999)
	player._on_area_entered(order_window)
	assert(GameControl.interaction_prompt == "DELIVER BUN")
	GameControl.request_interaction()
	assert(not player.has_held_item(), "Order window did not clear the hand")
	assert(
		delivered_item != null and delivered_item.item_id == &"bun",
		"Order delivery signal was not emitted"
	)
	GameControl.end_order(999)

	print("COOKING_FLOW_SMOKE_OK")
	get_tree().quit()


func _on_item_delivered(item: KitchenItem) -> void:
	delivered_item = item
