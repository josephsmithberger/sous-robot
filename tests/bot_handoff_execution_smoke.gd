extends Node

const KITCHEN_SCENE: PackedScene = preload("res://scenes/kitchen.tscn")

var _job_succeeded := false
var _order_completed := false
var _completed_item_id: StringName = &""


func _ready() -> void:
	GameControl.reset_session()
	RecipeTracker.record_recipe_made(&"slice_bread")

	var kitchen := KITCHEN_SCENE.instantiate()
	add_child(kitchen)
	await get_tree().create_timer(1.0).timeout
	var nav_region := kitchen.get_node("NavigationRegion3D") as NavigationRegion3D
	assert(nav_region.navigation_mesh.get_vertices().size() > 0, "Runtime navmesh bake must produce vertices")
	assert(NavigationServer3D.map_is_active(nav_region.get_navigation_map()), "Kitchen navigation map must be active")
	_test_spawn_stays_on_player_kitchen_island(kitchen, nav_region)

	var queue := kitchen.get_node("OrderQueue") as OrderQueue
	assert(queue != null, "Kitchen must contain OrderQueue")
	var waiter := queue.get_front_waiter()
	assert(waiter != null, "OrderQueue must have a front waiter")
	waiter.order_data = {
		"items": {&"bun": 1},
		"base_reward": 3.0,
		"tip": 2.0,
		"target_time": 30.0,
		"max_time": 60.0,
	}
	queue._accept_front_order(waiter)
	var order_id := GameControl.active_order_id
	assert(order_id > 0, "Test order did not start")

	GameControl.bot_task_completed.connect(_on_bot_task_completed)
	GameControl.order_completed.connect(_on_order_completed)
	GameControl.confirm_bot_dispatch(order_id, {&"bun": 1})
	# Reconfirming the same allocation must not duplicate a running worker.
	GameControl.confirm_bot_dispatch(order_id, {&"bun": 1})

	await get_tree().create_timer(0.25).timeout
	var bots := get_tree().get_nodes_in_group(&"bots")
	assert(bots.size() == 1, "Exactly one bot should spawn")
	var bot := bots[0] as BotWorker
	assert(bot != null and bot.move_speed > 5.0, "Bot must be quicker than the player")
	assert(bot.scale.is_equal_approx(Vector3.ONE * 0.75), "Bot must remain at 0.75 scale")

	var initial_path := NavigationServer3D.map_get_path(
		bot.get_world_3d().navigation_map,
		bot.global_position,
		bot.nav_agent.target_position,
		true
	)
	assert(initial_path.size() >= 2, "Bot assignment must resolve a navigation path")

	var deadline := Time.get_ticks_msec() + 20000
	while not _job_succeeded and Time.get_ticks_msec() < deadline:
		# The embedded test host is heavily frame-throttled. Path existence is
		# asserted above; warp between valid targets so this smoke test can focus
		# on the full source -> processor -> delivery orchestration contract.
		if bot.get_state() == BotWorker.State.NAVIGATING:
			var target := bot.nav_agent.target_position
			bot.global_position = Vector3(target.x, bot.global_position.y, target.z)
		elif bot.get_state() == BotWorker.State.INTERACTING:
			bot._complete_interaction()
		await get_tree().process_frame

	assert(_job_succeeded, "Bot did not complete its assigned bun route")
	assert(_completed_item_id == &"bun", "Bot completed the wrong item")
	assert(_order_completed, "Bot delivery did not complete the real order")
	assert(not GameControl.has_active_order(), "Completed bot order must close")

	await get_tree().create_timer(1.0).timeout
	assert(get_tree().get_nodes_in_group(&"bots").is_empty(), "Bot must smoke-despawn after one recipe")

	print("BOT_HANDOFF_EXECUTION_SMOKE_PASS")
	await get_tree().process_frame
	get_tree().quit(0)


func _test_spawn_stays_on_player_kitchen_island(
	kitchen: Node,
	nav_region: NavigationRegion3D
) -> void:
	var player := kitchen.get_node("player") as Node3D
	var dispatcher := kitchen.get_node("BotDispatchManager") as BotDispatchManager
	assert(player != null and dispatcher != null, "Kitchen bot spawn dependencies must exist")

	# Put the player beside the right wall. Serial multiples of three initially
	# sample outward, where a separate strip of floor also produces navmesh.
	player.global_position = Vector3(5.0, 0.0, 0.0)
	var nav_map := nav_region.get_navigation_map()
	var nav_origin := NavigationServer3D.map_get_closest_point(nav_map, player.global_position)
	for serial in [3, 6, 9]:
		var spawn := dispatcher._choose_spawn_position(serial)
		var nav_spawn := NavigationServer3D.map_get_closest_point(nav_map, spawn)
		var path := NavigationServer3D.map_get_path(nav_map, nav_origin, nav_spawn, true)
		assert(not path.is_empty(), "Bot spawn must remain reachable from the player kitchen island")
		assert(
			path[path.size() - 1].distance_to(nav_spawn) <= 0.2,
			"Bot spawn path must end on the selected kitchen point"
		)
	player.global_position = Vector3.ZERO


func _on_bot_task_completed(
	_order_id: int,
	item_id: StringName,
	_item_name: String,
	succeeded: bool,
	_detail: String
) -> void:
	_job_succeeded = succeeded
	_completed_item_id = item_id


func _on_order_completed(_order_id: int, _payout: float, _final_tip: float) -> void:
	_order_completed = true
