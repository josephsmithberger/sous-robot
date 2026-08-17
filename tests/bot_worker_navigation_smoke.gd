@tool
extends Node
## Automated smoke test for BotWorker instantiation, navigation configuration,
## collision layer matrix, item holding contract, and generic interaction dispatch.

const BOT_WORKER_SCENE: PackedScene = preload("res://scenes/bot_worker.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const KITCHEN_SCENE: PackedScene = preload("res://scenes/kitchen.tscn")
const BREAD_ITEM: KitchenItem = preload("res://resources/items/bread.tres")
const BUN_ITEM: KitchenItem = preload("res://resources/items/bun.tres")
const COUNTER_SCENE: PackedScene = preload("res://assets/appliances/counter.tscn")
const CRATE_BUNS_SCENE: PackedScene = preload("res://assets/appliances/crate_buns.tscn")
const OVEN_SCENE: PackedScene = preload("res://assets/appliances/oven.tscn")
const FRIDGE_SCENE: PackedScene = preload("res://assets/appliances/fridge.tscn")
const SINK_SCENE: PackedScene = preload("res://assets/appliances/sink.tscn")
const TRASH_CAN_SCENE: PackedScene = preload("res://assets/appliances/trash_can.tscn")


func _ready() -> void:
	print("Starting BotWorkerNavigationSmoke test...")
	_test_bot_worker_instantiation_and_properties()
	print("Step 1 done")
	await get_tree().process_frame
	_test_bot_worker_faces_movement_direction()
	print("Step 1b done")
	await get_tree().process_frame
	_test_collision_layer_matrix()
	print("Step 2 done")
	await get_tree().process_frame
	_test_appliance_collision_layers()
	print("Step 3 done")
	await get_tree().process_frame
	_test_bot_worker_item_holding()
	print("Step 4 done")
	await get_tree().process_frame
	_test_bot_worker_dispatch_interaction()
	print("Step 5 done")
	await get_tree().process_frame
	_test_bot_worker_pathfinding_pause()
	print("Step 5b done")
	await get_tree().process_frame
	await _test_bot_worker_despawn()
	print("Step 6 done")
	await get_tree().process_frame
	print("BOT_WORKER_NAVIGATION_SMOKE_PASS")
	get_tree().quit(0)


func _test_bot_worker_instantiation_and_properties() -> void:
	var bot := BOT_WORKER_SCENE.instantiate() as BotWorker
	assert(bot != null, "scenes/bot_worker.tscn must instantiate as BotWorker")
	add_child(bot)

	# Scale test: 0.75x
	assert(is_equal_approx(bot.scale.x, 0.75), "Bot scale X must be 0.75")
	assert(is_equal_approx(bot.scale.y, 0.75), "Bot scale Y must be 0.75")
	assert(is_equal_approx(bot.scale.z, 0.75), "Bot scale Z must be 0.75")

	# Workers are non-physical navmesh actors so they cannot lift the player or
	# receive platform-dependent collision responses.
	assert(bot.collision_layer == 0, "Bot collision_layer must be disabled")
	assert(bot.collision_mask == 0, "Bot collision_mask must be disabled")

	# Groups
	assert(bot.is_in_group(&"bots"), "Bot must be in 'bots' group")
	assert(bot.is_in_group(&"worker_robots"), "Bot must be in 'worker_robots' group")

	# NavigationAgent3D configuration
	var nav := bot.nav_agent
	assert(nav != null, "Bot must have a NavigationAgent3D node")
	assert(is_equal_approx(nav.path_desired_distance, 0.4), "path_desired_distance should be 0.4")
	assert(is_equal_approx(nav.target_desired_distance, 0.6), "target_desired_distance should be 0.6")
	assert(is_equal_approx(nav.path_max_distance, 2.0), "path_max_distance should be 2.0")
	assert(is_equal_approx(nav.path_height_offset, 0.5), "path_height_offset must convert nav height to actor feet")
	assert(not nav.avoidance_enabled, "avoidance_enabled must be false")

	# Hand marker & Smoke particles
	assert(bot.hand != null, "Bot must have a Hand Marker3D node")
	assert(bot.smoke_particles != null, "Bot must have SmokeParticles GPUParticles3D")

	bot.queue_free()


func _test_bot_worker_faces_movement_direction() -> void:
	var bot := BOT_WORKER_SCENE.instantiate() as BotWorker
	add_child(bot)

	# robot.glb presents its face toward local +Z, so that axis must turn toward
	# the direction of travel rather than Godot default visual forward (-Z).
	bot.rotation.y = 0.0
	bot._look_at_xz(bot.global_position + Vector3.BACK, 1.0)
	var visual_forward := bot.global_basis.z.normalized()
	assert(
		visual_forward.dot(Vector3.BACK) > 0.99,
		"Bot visual forward (+Z) must face its movement target"
	)

	bot.queue_free()


func _test_collision_layer_matrix() -> void:
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	add_child(player)

	# Player CharacterBody3D collides only with the static world.
	assert(player.collision_layer == 2, "Player collision_layer must be 2 (Layer 2 Player)")
	assert(player.collision_mask == 1, "Player collision_mask must contain only Layer 1 World")

	# Player InteractionArea: Layer 0, Mask 8 (Layer 4 Interactions)
	var p_interact := player.find_child("InteractionArea", true, false) as Area3D
	assert(p_interact != null, "Player must have an InteractionArea")
	assert(p_interact.collision_layer == 0, "Player InteractionArea collision_layer should be 0")
	assert(p_interact.collision_mask == 8, "Player InteractionArea collision_mask must be 8 (Layer 4 Interactions)")

	var bot := BOT_WORKER_SCENE.instantiate() as BotWorker
	add_child(bot)

	# Neither actor includes the other in its collision matrix.
	assert(bot.collision_layer == 0 and bot.collision_mask == 0, "Bot physics must be disabled")
	assert((player.collision_mask & (1 << (3 - 1))) == 0, "Player must not collide with bots")

	player.queue_free()
	bot.queue_free()


func _test_appliance_collision_layers() -> void:
	var scenes_to_check: Array[PackedScene] = [
		COUNTER_SCENE,
		CRATE_BUNS_SCENE,
		OVEN_SCENE,
		FRIDGE_SCENE,
		SINK_SCENE,
		TRASH_CAN_SCENE,
	]

	for scn: PackedScene in scenes_to_check:
		var inst: Node = scn.instantiate()
		add_child(inst)

		# Check all StaticBody3D have layer 1 and mask 0
		var static_bodies: Array[Node] = []
		_find_nodes_of_class(inst, "StaticBody3D", static_bodies)
		assert(not static_bodies.is_empty(), "%s must contain at least one StaticBody3D" % scn.resource_path)
		for node: Node in static_bodies:
			var sb: StaticBody3D = node as StaticBody3D
			assert(sb.collision_layer == 1, "%s StaticBody3D collision_layer must be 1 (World)" % scn.resource_path)
			assert(sb.collision_mask == 0, "%s StaticBody3D collision_mask must be 0" % scn.resource_path)

		# Check all InteractionArea (Area3D) have layer 8 (Layer 4) and mask 0
		var area_nodes: Array[Node] = []
		_find_nodes_of_class(inst, "Area3D", area_nodes)
		assert(not area_nodes.is_empty(), "%s must contain at least one Area3D" % scn.resource_path)
		for node: Node in area_nodes:
			var a: Area3D = node as Area3D
			assert(a.collision_layer == 8, "%s Area3D collision_layer must be 8 (Layer 4 Interactions)" % scn.resource_path)
			assert(a.collision_mask == 0, "%s Area3D collision_mask must be 0" % scn.resource_path)

		inst.queue_free()


func _test_bot_worker_item_holding() -> void:
	var bot := BOT_WORKER_SCENE.instantiate() as BotWorker
	add_child(bot)

	assert(not bot.has_held_item(), "Bot should start with empty hands")
	assert(bot.get_held_item() == null, "get_held_item() should return null")
	assert(not bot.is_holding(&"bread"), "is_holding('bread') should be false")

	# Set held item
	bot.set_held_item(BREAD_ITEM)
	assert(bot.has_held_item(), "Bot should now have held item")
	assert(bot.get_held_item() == BREAD_ITEM, "get_held_item() should return BREAD_ITEM")
	assert(bot.is_holding(&"bread"), "is_holding('bread') should be true")
	assert(not bot.is_holding(&"bun"), "is_holding('bun') should be false")

	# Verify visual child instantiated in hand
	assert(bot.hand.get_child_count() > 0, "Hand must contain visual model for held item")

	# Take held item
	var taken: KitchenItem = bot.take_held_item()
	assert(taken == BREAD_ITEM, "take_held_item() should return BREAD_ITEM")
	assert(not bot.has_held_item(), "Bot hands should be empty after taking item")
	assert(bot.hand.get_child_count() == 0, "Visual model should be removed from hand")

	bot.queue_free()


func _test_bot_worker_dispatch_interaction() -> void:
	var crate_node: Node = CRATE_BUNS_SCENE.instantiate()
	add_child(crate_node)
	crate_node.global_position = Vector3(5, 0, 5)

	var source_area := crate_node.find_child("buns", true, false) as ItemSource
	assert(source_area != null, "buns ItemSource must exist")

	var bot := BOT_WORKER_SCENE.instantiate() as BotWorker
	add_child(bot)
	bot.global_position = Vector3(0, 0, 0)

	# Dispatch bot to crate
	bot.dispatch_to(source_area)

	assert(bot.is_navigating(), "Bot should be in NAVIGATING state after dispatch")
	assert(bot.current_target_area == source_area, "current_target_area should be source_area")

	# Target position should match get_interaction_position
	var expected_pos := source_area.get_interaction_position(bot.global_position)
	assert(bot.nav_agent.target_position.distance_to(expected_pos) < 0.01, "Target position should match interaction position")

	# Simulate bot arriving at interaction position and executing interact
	bot.global_position = expected_pos
	bot._on_target_reached()

	# Since source_area hold duration is 0, interact should complete immediately
	assert(bot.has_held_item(), "Bot should have taken bread from crate")
	assert(bot.is_holding(&"bread"), "Bot should be holding bread")
	assert(bot.get_state() == BotWorker.State.IDLE, "Bot should return to IDLE state after interaction")

	crate_node.queue_free()
	bot.queue_free()


func _test_bot_worker_pathfinding_pause() -> void:
	GameControl.reset_session()
	assert(not GameControl.is_robot_pathfinding_paused(), "Robot pathfinding should not be paused initially")

	var bot := BOT_WORKER_SCENE.instantiate() as BotWorker
	add_child(bot)
	bot.global_position = Vector3.ZERO
	bot.navigate_to_position(Vector3(10.0, 0.0, 10.0))

	assert(bot.is_navigating(), "Bot should be in NAVIGATING state")

	# Physics process while unpaused should generate velocity toward target
	bot._physics_process(0.016)
	assert(Vector2(bot.velocity.x, bot.velocity.z).length() > 0.0, "Bot should have non-zero horizontal velocity while navigating unpaused")

	# Test 1: Pause on tab switch (switching away from kitchen tab)
	GameControl.current_tab = 1
	assert(GameControl.is_robot_pathfinding_paused(), "Robot pathfinding should be paused on non-kitchen tab")

	bot._physics_process(0.016)
	assert(is_zero_approx(bot.velocity.x) and is_zero_approx(bot.velocity.z), "Bot velocity should be zero while tab is switched away")
	assert(bot.is_navigating(), "Bot should still retain NAVIGATING state while paused")

	# Return to kitchen tab
	GameControl.current_tab = GameControl.KITCHEN_TAB
	assert(not GameControl.is_robot_pathfinding_paused(), "Robot pathfinding should unpause when returning to kitchen tab")

	bot._physics_process(0.016)
	assert(Vector2(bot.velocity.x, bot.velocity.z).length() > 0.0, "Bot should resume movement after returning to kitchen tab")

	# Test 2: Pause during dialogue
	GameControl._active_dialogues = 1
	GameControl._check_robot_pathfinding_pause_changed()
	assert(GameControl.is_robot_pathfinding_paused(), "Robot pathfinding should be paused when dialogue is active")

	bot._physics_process(0.016)
	assert(is_zero_approx(bot.velocity.x) and is_zero_approx(bot.velocity.z), "Bot velocity should be zero while dialogue is active")

	# Dialogue ends
	GameControl._active_dialogues = 0
	GameControl._check_robot_pathfinding_pause_changed()
	assert(not GameControl.is_robot_pathfinding_paused(), "Robot pathfinding should unpause when dialogue ends")

	bot._physics_process(0.016)
	assert(Vector2(bot.velocity.x, bot.velocity.z).length() > 0.0, "Bot should resume movement after dialogue ends")

	bot.queue_free()


func _test_bot_worker_despawn() -> void:
	var bot := BOT_WORKER_SCENE.instantiate() as BotWorker
	add_child(bot)

	var despawn_data := {"emitted": false}
	bot.despawn_completed.connect(func() -> void:
		despawn_data["emitted"] = true
	)

	bot.despawn(0.05)
	assert(bot.get_state() == BotWorker.State.DESPAWNING, "Bot state should be DESPAWNING")
	assert(bot.smoke_particles.emitting, "Smoke particles should start emitting on despawn")

	await get_tree().create_timer(0.1).timeout
	assert(despawn_data["emitted"], "despawn_completed signal should have fired")


func _find_nodes_of_class(node: Node, class_to_find: String, out_nodes: Array[Node]) -> void:
	if node.is_class(class_to_find):
		out_nodes.append(node)
	for child in node.get_children():
		_find_nodes_of_class(child, class_to_find, out_nodes)
