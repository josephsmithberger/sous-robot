extends Node

const BREAD: KitchenItem = preload("res://resources/items/bread.tres")
const CLOCK_WIDGET_SCRIPT = preload("res://scripts/clock_widget.gd")

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

	# Instantiate OrderQueue with controlled fast timers
	var queue := OrderQueue.new()
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

	# 2. Check early window (fast: elapsed < target_time)
	await get_tree().create_timer(0.05).timeout
	assert(is_equal_approx(clock.current_tip, 2.0), "Tip must remain at 100% within target_time window.")
	assert(clock.urgency > 0.0 and clock.urgency < 0.35, "Urgency should be in the initial calm range.")

	# 3. Check decay window (target_time < elapsed < max_time)
	await get_tree().create_timer(0.25).timeout # around 0.3s total
	assert(clock.current_tip < 2.0 and clock.current_tip > 0.0, "Tip must decay over time.")
	assert(clock.urgency >= 0.4, "Urgency should rise as time elapses.")

	# 4. Check late window (elapsed >= max_time)
	await get_tree().create_timer(0.35).timeout # around 0.65s total
	assert(is_equal_approx(clock.current_tip, 0.0), "Tip must decay to 0.0 after max_time.")
	assert(clock.urgency >= 1.0, "Urgency must reach 1.0 at max_time.")

	# 5. Complete order
	GameControl.item_delivered.emit(BREAD)
	await get_tree().process_frame
	# Since tip is 0.0 at this point, payout is $5.00 base + $0.00 tip
	assert(is_equal_approx(GameControl.money, 5.0), "Late payout should be base reward ($5.00) with $0 tip.")
	assert(not clock.is_active, "Clock must become inactive after order completion.")
	assert(front_waiter.last_reaction == WaiterRobot.REACTION_ANGRY, "An order completed after max_time should make the waiter angry.")

	print("CLOCK_URGENCY_SMOKE_PASS balance=$%.2f urgency=%.2f" % [GameControl.money, clock.urgency])
	get_tree().quit(0)
