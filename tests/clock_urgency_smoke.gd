extends Node

const BREAD: KitchenItem = preload("res://resources/items/bread.tres")
const CLOCK_WIDGET_SCRIPT = preload("res://scripts/clock_widget.gd")
const SENOR_FOOD_DIALOGUE: DialogueResource = preload("res://dialogue/master.dialogue")

func _ready() -> void:
	GameControl.reset_session()
	
	# Instantiate ClockWidget
	var clock: Control = Control.new()
	clock.set_script(CLOCK_WIDGET_SCRIPT)
	clock.size = Vector2(118, 118)
	add_child(clock)
	await get_tree().process_frame

	assert(not clock.is_active, "Clock must start inactive when there is no active order.")
	assert(clock.urgency == 0.0, "Clock urgency must be 0.0 initially.")
	assert(GameControl.is_order_clock_paused(), "Clock must start paused in initial MARKER overview mode.")

	# Switch to first person for active gameplay testing
	GameControl.set_camera_mode(GameControl.CameraMode.FIRST_PERSON)
	assert(not GameControl.is_order_clock_paused(), "Clock must not be paused in first person on kitchen tab.")

	# Instantiate OrderQueue with controlled fast timers
	var queue := OrderQueue.new()
	queue.use_procedural_orders = false
	queue.departure_delay = 0.0
	queue.slot_move_duration = 0.05
	queue.order_cycle = [
		{
			"items": {"bread": 1},
			"base_reward": 5.0,
			"tip": 2.0,
			"wrong_item_penalty": 1.0,
			"target_time": 0.2, # 200ms full tip window
			"max_time": 0.6,    # 600ms total decay window
		}
	]
	add_child(queue)
	await get_tree().process_frame

	# 1. Accept order
	var front_waiter: WaiterRobot = queue.get_front_waiter()
	queue._accept_front_order(front_waiter)
	await get_tree().process_frame

	assert(GameControl.has_active_order(), "Active order must be registered in GameControl.")
	assert(clock.is_active, "Clock must become active when an order starts.")
	assert(clock.max_time == 0.6, "Clock max_time should match order definition.")

	# 2. Test Pause Condition: Switch Tabs (e.g. Store Tab index 1)
	GameControl.current_tab = 1
	assert(GameControl.is_order_clock_paused(), "Order clock must pause when switching away from kitchen tab.")
	var paused_elapsed: float = clock.elapsed_time
	var paused_tip: float = clock.current_tip
	await get_tree().create_timer(0.15).timeout
	assert(
		is_equal_approx(clock.elapsed_time, paused_elapsed),
		"Elapsed time must not advance while on another tab."
	)
	assert(
		is_equal_approx(clock.current_tip, paused_tip),
		"Tip must not decay while on another tab."
	)

	# Resume Kitchen tab
	GameControl.current_tab = GameControl.KITCHEN_TAB
	assert(not GameControl.is_order_clock_paused(), "Order clock must unpause when returning to kitchen tab.")

	# 3. Test Pause Condition: Overview Mode (MARKER camera)
	GameControl.set_camera_mode(GameControl.CameraMode.MARKER)
	assert(GameControl.is_order_clock_paused(), "Order clock must pause when entering overview mode.")
	paused_elapsed = clock.elapsed_time
	paused_tip = clock.current_tip
	await get_tree().create_timer(0.15).timeout
	assert(
		is_equal_approx(clock.elapsed_time, paused_elapsed),
		"Elapsed time must not advance while in overview mode."
	)
	assert(
		is_equal_approx(clock.current_tip, paused_tip),
		"Tip must not decay while in overview mode."
	)

	# Resume First Person
	GameControl.set_camera_mode(GameControl.CameraMode.FIRST_PERSON)
	assert(not GameControl.is_order_clock_paused(), "Order clock must unpause when returning to first person.")

	# 4. Test Pause Condition: In Dialogue
	GameControl._on_dialogue_started(SENOR_FOOD_DIALOGUE)
	assert(GameControl.is_order_clock_paused(), "Order clock must pause while in dialogue.")
	paused_elapsed = clock.elapsed_time
	paused_tip = clock.current_tip
	await get_tree().create_timer(0.15).timeout
	assert(
		is_equal_approx(clock.elapsed_time, paused_elapsed),
		"Elapsed time must not advance while in dialogue."
	)
	assert(
		is_equal_approx(clock.current_tip, paused_tip),
		"Tip must not decay while in dialogue."
	)

	# End Dialogue
	GameControl._on_dialogue_ended(SENOR_FOOD_DIALOGUE)
	assert(not GameControl.is_order_clock_paused(), "Order clock must unpause when dialogue ends.")

	# 5. Check early window (fast: elapsed < target_time)
	await get_tree().create_timer(0.05).timeout
	assert(is_equal_approx(clock.current_tip, 2.0), "Tip must remain at 100% within target_time window.")
	assert(clock.urgency > 0.0 and clock.urgency < 0.35, "Urgency should be in the initial calm range.")

	# 6. Check decay window (target_time < elapsed < max_time)
	await get_tree().create_timer(0.25).timeout # around 0.3s total unpaused
	assert(clock.current_tip < 2.0 and clock.current_tip > 0.0, "Tip must decay over time.")
	assert(clock.urgency >= 0.4, "Urgency should rise as time elapses.")

	# 7. Check late window (elapsed >= max_time)
	await get_tree().create_timer(0.35).timeout # around 0.65s total unpaused
	assert(is_equal_approx(clock.current_tip, 0.0), "Tip must decay to 0.0 after max_time.")
	assert(clock.urgency >= 1.0, "Urgency must reach 1.0 at max_time.")

	# 8. Complete order
	GameControl.item_delivered.emit(BREAD)
	await get_tree().process_frame
	# Since tip is 0.0 at this point, payout is $5.00 base + $0.00 tip
	assert(is_equal_approx(GameControl.money, 5.0), "Late payout should be base reward ($5.00) with $0 tip.")
	assert(not clock.is_active, "Clock must become inactive after order completion.")
	assert(front_waiter.last_reaction == WaiterRobot.REACTION_ANGRY, "An order completed after max_time should make the waiter angry.")

	print("CLOCK_URGENCY_SMOKE_PASS balance=$%.2f urgency=%.2f" % [GameControl.money, clock.urgency])
	get_tree().quit(0)
