extends Node

const BREAD: KitchenItem = preload("res://resources/items/bread.tres")
const SLICED_BREAD: KitchenItem = preload("res://resources/items/sliced_bread.tres")
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
	queue.departure_delay = 0.0
	queue.slot_move_duration = 0.1
	add_child(queue)
	await get_tree().process_frame

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
	assert(not GameControl.has_active_order(), "Completed order should close delivery access.")

	await get_tree().create_timer(0.45).timeout
	queue._accept_front_order(queue.get_front_waiter())
	GameControl.item_delivered.emit(BREAD)
	await get_tree().process_frame
	assert(is_equal_approx(GameControl.money, 3.25), "Wrong bread should immediately deduct $0.75.")

	GameControl.item_delivered.emit(SLICED_BREAD)
	GameControl.item_delivered.emit(SLICED_BREAD)
	await get_tree().process_frame
	assert(is_equal_approx(GameControl.money, 8.0), "Second payout should include its reduced $0.75 tip.")

	print("ORDER_QUEUE_SMOKE_PASS balance=$%.2f visible_waiters=%d" % [GameControl.money, queue.get_child_count()])
	get_tree().quit(0)
