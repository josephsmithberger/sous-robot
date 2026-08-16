extends Node

const BREAD: KitchenItem = preload("res://resources/items/bread.tres")
const BUN: KitchenItem = preload("res://resources/items/bun.tres")
const ORDER_DIALOGUE: DialogueResource = preload("res://dialogue/orders.dialogue")
const SENOR_FOOD_DIALOGUE: DialogueResource = preload("res://dialogue/master.dialogue")


func _ready() -> void:
	GameControl.reset_session()
	GameControl.set_camera_mode(GameControl.CameraMode.FIRST_PERSON)
	GameControl._on_dialogue_started(ORDER_DIALOGUE)
	assert(
		GameControl.camera_mode == GameControl.CameraMode.WAITER,
		"Robot waiter dialogue must switch to the waiter camera mode."
	)
	GameControl._on_dialogue_ended(ORDER_DIALOGUE)
	assert(GameControl.camera_mode == GameControl.CameraMode.FIRST_PERSON)
	GameControl._on_dialogue_started(SENOR_FOOD_DIALOGUE)
	assert(
		GameControl.camera_mode == GameControl.CameraMode.MARKER,
		"Señor Food dialogue must retain the marker-camera behavior."
	)
	GameControl._on_dialogue_ended(SENOR_FOOD_DIALOGUE)
	assert(GameControl.camera_mode == GameControl.CameraMode.FIRST_PERSON)

	var queue := OrderQueue.new()
	queue.use_procedural_orders = false
	queue.departure_delay = 0.0
	queue.slot_move_duration = 0.1
	add_child(queue)
	await get_tree().process_frame
	assert(queue.reaction_for_order({"elapsed_time": 5.0, "target_time": 4.0, "max_time": 10.0}) == WaiterRobot.REACTION_NORMAL, "A correct order between target and max time should be normal.")

	var player_scene: PackedScene = preload("res://scenes/player.tscn")
	var player = player_scene.instantiate()
	player.position = Vector3(3.0, 1.0, 2.0)
	add_child(player)
	await get_tree().process_frame

	var front_waiter: WaiterRobot = queue.get_front_waiter()
	var look_target: Vector3 = front_waiter.get_look_target()
	var target_received: Array[Vector3] = [Vector3.ZERO]
	var look_connected := func(target: Vector3, _dur: float) -> void: target_received[0] = target
	GameControl.look_at_requested.connect(look_connected)

	queue.request_front_dialogue(front_waiter)
	assert(target_received[0].is_equal_approx(look_target), "Requesting front dialogue must emit look_at_requested for the waiter robot.")
	GameControl.look_at_requested.disconnect(look_connected)

	# Verify instant look_at_target aligns the player's head directly at the waiter robot
	player.look_at_target(look_target, 0.0)
	var head_node: Marker3D = player.get_node("Head")
	var diff: Vector3 = (look_target - head_node.global_position).normalized()
	var head_forward: Vector3 = -head_node.global_transform.basis.z
	assert(
		head_forward.is_equal_approx(diff),
		"Player head forward vector must point at the waiter robot target position."
	)

	# Verify front waiter turns to watch the player
	front_waiter.turn_speed = 100.0 # Instant turn for test
	for _frame in 5:
		await get_tree().process_frame
	var to_player: Vector3 = player.global_position - front_waiter.global_position
	var expected_yaw: float = atan2(to_player.x, to_player.z)
	var front_robot_node: Node3D = front_waiter.get_node("Robot")
	assert(
		is_equal_approx(front_robot_node.rotation.y, expected_yaw),
		"Front waiter robot should rotate to watch the player."
	)

	# Verify non-front waiters remain facing the window
	for i in range(1, queue._waiters.size()):
		var rear_waiter: WaiterRobot = queue._waiters[i]
		var rear_robot_node: Node3D = rear_waiter.get_node("Robot")
		assert(
			is_equal_approx(rear_robot_node.rotation.y, WaiterRobot.WINDOW_FACING),
			"Waiters behind the front robot should remain facing WINDOW_FACING in line."
		)

	# Move player to another position and verify front waiter updates look direction
	player.position = Vector3(2.0, 1.0, -3.0)
	for _frame in 5:
		await get_tree().process_frame
	to_player = player.global_position - front_waiter.global_position
	expected_yaw = atan2(to_player.x, to_player.z)
	assert(
		is_equal_approx(front_robot_node.rotation.y, expected_yaw),
		"Front waiter robot should update its look direction as player moves."
	)

	front_waiter.turn_speed = 7.5
	player.queue_free()

	assert(queue.get_child_count() == 3, "The visible queue must contain exactly three robots.")
	queue._accept_front_order(queue.get_front_waiter())
	assert(GameControl.has_active_order(), "Talking to the front robot should open an order.")
	assert(
		not queue.get_front_waiter().can_interact(null),
		"An accepted waiter must not offer a repeat-order interaction before delivery."
	)

	GameControl.item_delivered.emit(BREAD)
	await get_tree().process_frame
	assert(is_equal_approx(GameControl.money, 4.0), "First order should pay $3 base + $1 tip.")
	assert(front_waiter.last_reaction == WaiterRobot.REACTION_HAPPY, "A quick correct order should make the waiter happy.")
	assert(not GameControl.has_active_order(), "Completed order should close delivery access.")

	await get_tree().create_timer(0.45).timeout
	var second_waiter: WaiterRobot = queue.get_front_waiter()
	queue._accept_front_order(second_waiter)
	GameControl.item_delivered.emit(BREAD)
	await get_tree().process_frame
	assert(is_equal_approx(GameControl.money, 4.0), "Wrong items should be accepted without an immediate charge.")
	assert(second_waiter.last_reaction == WaiterRobot.REACTION_ANGRY, "A wrong item should make the waiter angry.")

	GameControl.item_delivered.emit(BUN)
	GameControl.item_delivered.emit(BUN)
	await get_tree().process_frame
	assert(is_equal_approx(GameControl.money, 8.75), "Second payout should include the base reward and reduced tip, without charging for the wrong item.")
	assert(second_waiter.last_reaction == WaiterRobot.REACTION_ANGRY, "A wrong item should keep the waiter angry through completion.")

	print("ORDER_QUEUE_SMOKE_PASS balance=$%.2f visible_waiters=%d" % [GameControl.money, queue.get_child_count()])
	get_tree().quit(0)
