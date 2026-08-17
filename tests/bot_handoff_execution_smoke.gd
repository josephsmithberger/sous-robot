extends Node

const KITCHEN_SCENE: PackedScene = preload("res://scenes/kitchen.tscn")

var _job_finished := false
var _job_succeeded := false
var _job_detail := ""
var _order_completed := false
var _completed_item_id: StringName = &""


func _ready() -> void:
	# Match the shipped game hierarchy: the kitchen and its navigation map live
	# inside a SubViewport rather than the root viewport.
	var kitchen_viewport := SubViewport.new()
	kitchen_viewport.size = Vector2i(850, 425)
	kitchen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(kitchen_viewport)
	var kitchen := KITCHEN_SCENE.instantiate()
	kitchen_viewport.add_child(kitchen)
	await get_tree().create_timer(1.0).timeout

	# Reset after kitchen startup so a clean mobile install cannot leave tutorial
	# dialogue pausing navigation or overwrite the learned recipe fixture.
	GameControl.reset_session()
	RecipeTracker.record_recipe_made(&"slice_bread")
	var nav_region := kitchen.get_node("NavigationRegion3D") as NavigationRegion3D
	assert(nav_region.navigation_mesh.get_vertices().size() > 0, "Runtime navmesh bake must produce vertices")
	assert(NavigationServer3D.map_is_active(nav_region.get_navigation_map()), "Kitchen navigation map must be active")
	_test_random_spawns_stay_in_reachable_kitchen(kitchen, nav_region)

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
	# Confirm through the same allocation signal used by the Hand Off modal so
	# this covers the shipped UI-to-dispatcher path as well as route execution.
	var dispatcher := kitchen.get_node("BotDispatchManager") as BotDispatchManager
	assert(dispatcher != null, "Kitchen must contain BotDispatchManager")
	GameControl.confirm_bot_dispatch(order_id, {&"bun": 1})

	var spawn_deadline := Time.get_ticks_msec() + 3000
	var bots := get_tree().get_nodes_in_group(&"bots")
	while (
		(bots.is_empty() or not (bots[0] as BotWorker).visible)
		and Time.get_ticks_msec() < spawn_deadline
	):
		await get_tree().process_frame
		bots = get_tree().get_nodes_in_group(&"bots")
	assert(bots.size() == 1, "Exactly one bot should spawn; found %d" % bots.size())
	assert((bots[0] as BotWorker).visible, "Bot must stay hidden until its navmesh spawn is ready")
	var bot := bots[0] as BotWorker
	assert(bot != null and bot.move_speed > 5.0, "Bot must be quicker than the player")
	assert(bot.scale.is_equal_approx(Vector3.ONE * 0.75), "Bot must remain at 0.75 scale")
	var bot_nav_point := NavigationServer3D.map_get_closest_point(
		bot.get_world_3d().navigation_map, bot.global_position
	)
	assert(
		absf(bot.global_position.y - dispatcher._floor_position_for_nav_point(bot_nav_point).y) <= 0.01,
		"Visible bot feet must align with the kitchen floor"
	)

	var initial_path := NavigationServer3D.map_get_path(
		bot.get_world_3d().navigation_map,
		bot.global_position,
		bot.nav_agent.target_position,
		true
	)
	assert(initial_path.size() >= 2, "Bot assignment must resolve a navigation path")

	var deadline := Time.get_ticks_msec() + 45000
	while not _job_finished and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	assert(_job_finished, "Bot bun job did not report a result")
	assert(_job_succeeded, "Bot did not complete its assigned bun route: %s" % _job_detail)
	assert(_completed_item_id == &"bun", "Bot completed the wrong item")
	assert(_order_completed, "Bot delivery did not complete the real order")
	assert(not GameControl.has_active_order(), "Completed bot order must close")

	await get_tree().create_timer(1.0).timeout
	assert(get_tree().get_nodes_in_group(&"bots").is_empty(), "Bot must smoke-despawn after one recipe")

	print("BOT_HANDOFF_EXECUTION_SMOKE_PASS")
	# Give physical-device stdout time to reach the editor before termination.
	await get_tree().create_timer(2.0).timeout
	get_tree().quit(0)


func _test_random_spawns_stay_in_reachable_kitchen(
	kitchen: Node,
	nav_region: NavigationRegion3D
) -> void:
	var player := kitchen.get_node("player") as Node3D
	var dispatcher := kitchen.get_node("BotDispatchManager") as BotDispatchManager
	assert(player != null and dispatcher != null, "Kitchen bot spawn dependencies must exist")

	seed(24701)
	player.global_position = Vector3.ZERO
	var nav_map := nav_region.get_navigation_map()
	var nav_origin := NavigationServer3D.map_get_closest_point(nav_map, player.global_position)
	var spawns: Array[Vector3] = []
	for serial in range(1, 7):
		var spawn := dispatcher._choose_spawn_position(serial)
		spawns.append(spawn)
		var nav_spawn := NavigationServer3D.map_get_closest_point(nav_map, spawn)
		var path := NavigationServer3D.map_get_path(nav_map, nav_origin, nav_spawn, true)
		assert(dispatcher._is_spawn_inside_kitchen(spawn), "Bot spawn must stay inside the kitchen")
		assert(
			absf(spawn.y - dispatcher._floor_position_for_nav_point(nav_spawn).y) <= 0.01,
			"Bot feet must align with the kitchen floor"
		)
		assert(not path.is_empty(), "Bot spawn must remain reachable from the player kitchen island")
		assert(
			path[path.size() - 1].distance_to(nav_spawn) <= 0.2,
			"Bot spawn path must end on the selected kitchen point"
		)

	var widest_separation := 0.0
	for first_index in spawns.size():
		for second_index in range(first_index + 1, spawns.size()):
			widest_separation = maxf(
				widest_separation,
				spawns[first_index].distance_to(spawns[second_index])
			)
	assert(widest_separation > 2.0, "Random bot spawns must use visibly different kitchen spots")


func _on_bot_task_completed(
	_order_id: int,
	item_id: StringName,
	_item_name: String,
	succeeded: bool,
	_detail: String
) -> void:
	_job_finished = true
	_job_succeeded = succeeded
	_job_detail = _detail
	_completed_item_id = item_id


func _on_order_completed(_order_id: int, _payout: float, _final_tip: float) -> void:
	_order_completed = true
