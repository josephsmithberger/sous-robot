extends Node

const ORDER_QUEUE_SCRIPT = preload("res://scripts/order_queue.gd")

func _ready() -> void:
	print("Starting RandomOrdersSmoke test...")
	GameControl.reset_session()

	# Create a container node for kitchen architecture
	var kitchen := Node3D.new()
	kitchen.name = "Architecture"
	add_child(kitchen)

	# 1. Add starter wall_decorated and crate_buns
	var wall_scene: PackedScene = preload("res://assets/appliances/wall_decorated.tscn")
	var wall = wall_scene.instantiate()
	kitchen.add_child(wall)

	var bun_crate_scene: PackedScene = preload("res://assets/appliances/crate_buns.tscn")
	var bun_crate = bun_crate_scene.instantiate()
	kitchen.add_child(bun_crate)

	# Create procedural OrderQueue
	var queue := OrderQueue.new()
	queue.use_procedural_orders = true
	queue.departure_delay = 0.0
	queue.slot_move_duration = 0.05
	add_child(queue)
	await get_tree().process_frame

	# 2. Verify catalog contains items loaded from resources/items/
	assert(queue._catalog_by_id.has(&"bread"), "Catalog should have bread")
	assert(queue._catalog_by_id.has(&"cheeseburger"), "Catalog should auto-discover cheeseburger")
	assert(queue._catalog_by_id.has(&"steak_dinner"), "Catalog should auto-discover steak_dinner")
	assert(queue._catalog_by_id.has(&"salad_chilled"), "Catalog should auto-discover salad_chilled")

	# 3. Verify starter kitchen reachability
	var starter_producible := queue.get_producible_items()
	print("Starter producible items: ", starter_producible.keys())
	assert(starter_producible.has(&"bread"), "Starter kitchen must produce bread")
	assert(starter_producible.has(&"bun"), "Starter kitchen must produce bun (via cutboard)")
	assert(not starter_producible.has(&"carrot"), "Starter kitchen must NOT produce carrot without Carrot Crate")
	assert(not starter_producible.has(&"two_buns"), "Starter kitchen must NOT produce two_buns without Counter")
	assert(not starter_producible.has(&"cheeseburger"), "Starter kitchen must NOT produce cheeseburger")

	assert(queue.is_item_producible(&"bread"), "bread should be producible")
	assert(queue.is_item_producible(&"bun"), "bun should be producible")
	assert(not queue.is_item_producible(&"cheese"), "cheese should not be producible")

	# 4. Verify random order generation in starter kitchen
	var previous_sig := ""
	var generated_sigs: Array[String] = []
	for _i in 10:
		var order := queue.generate_random_order()
		var items: Dictionary = order.get("items", {})
		assert(not items.is_empty(), "Generated order must have items")
		var current_sig := OrderQueue.compute_order_signature(items)
		assert(
			current_sig != previous_sig or previous_sig.is_empty(),
			"Consecutive orders must not be identical! Got repeated signature: %s" % current_sig
		)
		previous_sig = current_sig
		generated_sigs.append(current_sig)

		for item_id in items:
			assert(
				item_id == &"bread" or item_id == &"bun",
				"Starter order items must only be bread or bun, got: %s" % item_id
			)
		assert(float(order["base_reward"]) >= 2.0, "Base reward must be at least $2")
		assert(float(order["tip"]) >= 1.0, "Tip must be at least $1")
		assert(float(order["target_time"]) >= 10.0, "Target time must be at least 10s")
		assert(float(order["max_time"]) > float(order["target_time"]), "Max time must exceed target time")

	print("Starter kitchen generated order variety: ", generated_sigs)

	# 5. Add Carrot Crate dynamically
	var carrot_crate_scene: PackedScene = preload("res://assets/appliances/crate_carrots.tscn")
	var carrot_crate = carrot_crate_scene.instantiate()
	kitchen.add_child(carrot_crate)
	await get_tree().process_frame

	var with_carrots := queue.get_producible_items()
	print("With carrot crate producible items: ", with_carrots.keys())
	assert(with_carrots.has(&"carrot"), "Must now produce carrot")
	assert(with_carrots.has(&"carrot_chopped"), "Must now produce carrot_chopped via cutboard")
	assert(with_carrots.has(&"carrot_pieces"), "Must now produce carrot_pieces via cutboard")

	# 6. Add Counter appliance dynamically
	var counter_scene: PackedScene = preload("res://assets/appliances/counter.tscn")
	var counter = counter_scene.instantiate()
	kitchen.add_child(counter)
	await get_tree().process_frame

	var with_counter := queue.get_producible_items()
	print("With counter producible items: ", with_counter.keys())
	assert(with_counter.has(&"two_buns"), "Must now produce two_buns (bun + bun on Counter)")

	# 7. Add Oven, Steak Crate, and Cheese Crate dynamically
	var oven_scene: PackedScene = preload("res://assets/appliances/oven.tscn")
	var oven = oven_scene.instantiate()
	kitchen.add_child(oven)

	var steak_crate_scene: PackedScene = preload("res://assets/appliances/crate_steak.tscn")
	var steak_crate = steak_crate_scene.instantiate()
	kitchen.add_child(steak_crate)

	var cheese_crate_scene: PackedScene = preload("res://assets/appliances/crate_cheese.tscn")
	var cheese_crate = cheese_crate_scene.instantiate()
	kitchen.add_child(cheese_crate)
	await get_tree().process_frame

	var with_cheeseburger_deps := queue.get_producible_items()
	print("With cheeseburger deps producible items: ", with_cheeseburger_deps.keys())
	assert(with_cheeseburger_deps.has(&"bun_top"), "Oven must toast bun_top")
	assert(with_cheeseburger_deps.has(&"bun_bottom"), "Oven must toast bun_bottom")
	assert(with_cheeseburger_deps.has(&"cheese_slice"), "Cutboard must slice cheese")
	assert(with_cheeseburger_deps.has(&"steak_pieces"), "Stove must sear steak into pieces")
	assert(with_cheeseburger_deps.has(&"burger_cooked"), "Stove must grill steak pieces into burger patty")
	assert(with_cheeseburger_deps.has(&"cheeseburger"), "Counter must assemble cheeseburger!")
	assert(queue.is_item_producible(&"cheeseburger"), "cheeseburger must be producible")

	# Verify cheeseburger value estimation
	var burger_val := queue.estimate_item_value(&"cheeseburger")
	assert(burger_val >= 20.0, "Cheeseburger estimated value should be >= $20, got: $%.2f" % burger_val)

	# 8. Test fulfillment of a procedural order through GameControl
	var front_waiter: WaiterRobot = queue.get_front_waiter()
	assert(front_waiter != null, "Visible queue must have a front waiter")
	queue._accept_front_order(front_waiter)
	await get_tree().process_frame
	assert(GameControl.has_active_order(), "Order should now be active")

	var active_order := queue._active_order
	var required_items: Dictionary = active_order.get("items", {})
	print("Active procedural order: ", required_items)

	# Fulfill all required items in the order
	for item_id: StringName in required_items:
		var qty := int(required_items[item_id])
		var item_resource: KitchenItem = queue._catalog_by_id.get(item_id)
		assert(item_resource != null, "Item resource for '%s' must exist" % item_id)
		for _q in qty:
			GameControl.item_delivered.emit(item_resource)
			await get_tree().process_frame

	assert(GameControl.money > 0.0, "Fulfilling procedural order must pay money")
	assert(not GameControl.has_active_order(), "Order should be completed and inactive")

	print("RANDOM_ORDERS_SMOKE_PASS balance=$%.2f" % GameControl.money)
	get_tree().quit(0)
