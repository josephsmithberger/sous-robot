extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")


func _ready() -> void:
	# 1. Reset session and check starter state
	GameControl.reset_session(0.0)
	assert(is_equal_approx(GameControl.money, 0.0), "Initial session balance must be $0.00.")
	assert(GameControl.is_item_owned(&"DecoratedWall"), "DecoratedWall must be a starter item.")
	assert(GameControl.is_item_owned(&"BunCrate"), "BunCrate must be a starter item.")
	assert(not GameControl.is_item_owned(&"CarrotCrate"), "CarrotCrate must not be owned initially.")

	# 2. Instantiate full game UI scene
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().physics_frame
	await get_tree().process_frame

	var tabs: TabContainer = game.get_node("MarginContainer/HSplitContainer/TabContainer")
	var store = tabs.get_node("Store")
	var kitchen = tabs.get_node("Kitchen/PanelContainer/VBoxContainer/InteractionStage/SubViewportContainer/SubViewport/kitchen")
	var placement_manager: PlacementManager = kitchen.get_node("PlacementManager") as PlacementManager
	var carrot_card: Button = store.get_node("Scroll/Grid/CarrotCrate")
	var bun_crate: Node3D = kitchen.get_node("Architecture/crate_buns")
	var wall_decorated: Node3D = kitchen.get_node("Architecture/wall_decorated")

	assert(placement_manager != null, "PlacementManager must be present in kitchen scene.")
	assert(bun_crate != null, "Starter crate_buns must be present in kitchen scene.")
	assert(wall_decorated != null, "Starter wall_decorated must be present in kitchen scene.")

	# 3. Add money and switch to Store tab
	GameControl.change_money(100.0, "INITIAL FUNDS")
	tabs.current_tab = 1 # Store tab
	await get_tree().process_frame

	# 4. Buy Carrot Crate ($15.00)
	store._on_card_pressed(carrot_card)
	store._on_purchase_confirmed()
	await get_tree().process_frame

	assert(is_equal_approx(GameControl.money, 85.0), "Balance must be $85.00 after buying Carrot Crate ($100 - $15).")
	assert(GameControl.is_item_owned(&"CarrotCrate"), "CarrotCrate must now be owned.")
	assert(tabs.current_tab == 0, "Buying item must switch active tab back to Kitchen (tab 0).")
	assert(GameControl.camera_mode == GameControl.CameraMode.MARKER, "Buying item must switch camera to overhead MARKER mode.")
	assert(GameControl.is_placing, "GameControl.is_placing must be true during placement.")
	assert(placement_manager.active_ghost != null, "PlacementManager must have an active ghost preview.")
	assert(placement_manager.active_item_id == &"CarrotCrate", "Active placing item must be CarrotCrate.")

	# 5. Test rotating ghost
	var initial_rot := placement_manager.ghost_rotation_y
	placement_manager.rotate_ghost()
	assert(
		is_equal_approx(placement_manager.ghost_rotation_y, wrapf(initial_rot + PI * 0.5, 0.0, TAU)),
		"Rotating ghost must increment rotation by 90 degrees."
	)

	# 6. Test placement validation
	var invalid_out_of_bounds := Vector3(12.0, 0.0, 15.0)
	assert(not placement_manager.check_placement_valid(invalid_out_of_bounds, &"CarrotCrate"), "Outside kitchen bounds must be invalid.")

	var invalid_decorated_wall := Vector3(0.0, 0.0, 8.0)
	assert(not placement_manager.check_placement_valid(invalid_decorated_wall, &"CarrotCrate"), "Overlapping decorated wall must be invalid.")

	var valid_spot := Vector3(2.0, 0.0, -4.0)
	assert(placement_manager.check_placement_valid(valid_spot, &"CarrotCrate"), "Spot (2, 0, -4) must be valid.")

	# 7. Place Carrot Crate at (2.0, 0.0, -4.0)
	placement_manager.set_ghost_position(valid_spot)
	var placed_ok := placement_manager.confirm_placement()
	assert(placed_ok, "confirm_placement must succeed on valid spot.")
	assert(not GameControl.is_placing, "is_placing must be false after placement.")
	assert(placement_manager.active_ghost == null, "Ghost must be freed after placement.")

	# Verify placed item exists in scene
	var placed_items := get_tree().get_nodes_in_group(&"placed_items")
	var found_carrot := false
	for node in placed_items:
		if node is Node3D and node.get_meta(&"item_id", &"") == &"CarrotCrate":
			found_carrot = true
			assert(node.global_position.distance_to(valid_spot) < 0.6, "Carrot crate position must match placement spot.")
	assert(found_carrot, "Carrot crate must be found in placed_items group.")

	# 8. Test Edit / Arrange: Pick up Bun Crate and move it
	var bun_picked := placement_manager.pick_up_item(bun_crate)
	assert(bun_picked, "Movable starter Bun Crate must be pickable for editing.")
	assert(GameControl.is_placing, "Picking up an item must enter placement mode.")
	assert(placement_manager.editing_node == bun_crate, "Editing node must be bun_crate.")

	var new_bun_spot := Vector3(-2.0, 0.0, -6.0)
	placement_manager.set_ghost_position(new_bun_spot)
	placement_manager.confirm_placement()

	assert(bun_crate.visible, "Bun crate must be visible after repositioning.")
	assert(bun_crate.global_position.distance_to(new_bun_spot) < 0.6, "Bun crate must move to new position.")

	# 9. Test Decorated Wall CANNOT be moved
	var wall_picked := placement_manager.pick_up_item(wall_decorated)
	assert(not wall_picked, "Decorated Wall must NOT be movable/pickable in edit mode.")
	assert(not GameControl.is_placing, "Decorated Wall pick attempt must not enter placement mode.")

	# 10. Buy Cheese Crate ($22.50) and place it
	tabs.current_tab = 1
	await get_tree().process_frame
	var cheese_card: Button = store.get_node("Scroll/Grid/CheeseCrate")
	store._on_card_pressed(cheese_card)
	store._on_purchase_confirmed()
	await get_tree().process_frame

	assert(is_equal_approx(GameControl.money, 62.50), "Balance must be $62.50 after buying Cheese Crate ($85 - $22.50).")
	assert(GameControl.is_placing, "Must enter placement mode for Cheese Crate.")
	var cheese_spot := Vector3(0.0, 0.0, -6.0)
	placement_manager.set_ghost_position(cheese_spot)
	placement_manager.confirm_placement()

	var placed_items_after := get_tree().get_nodes_in_group(&"placed_items")
	var found_cheese := false
	for node in placed_items_after:
		if node is Node3D and node.get_meta(&"item_id", &"") == &"CheeseCrate":
			found_cheese = true
	assert(found_cheese, "Cheese crate must be present after purchase and placement.")

	print("PLACING_BUYING_SMOKE_PASS balance=$%.2f placed_items=%d" % [GameControl.money, placed_items_after.size()])
	get_tree().quit(0)
