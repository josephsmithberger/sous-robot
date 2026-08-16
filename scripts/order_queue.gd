class_name OrderQueue
extends Node3D
## Deterministic, endlessly wrapping queue of editor-authored order dictionaries.

const WAITER_SCENE: PackedScene = preload("res://scenes/waiter_robot.tscn")
const ORDER_DIALOGUE: DialogueResource = preload("res://dialogue/orders.dialogue")
const BREAD: KitchenItem = preload("res://resources/items/bread.tres")
const BUN: KitchenItem = preload("res://resources/items/bun.tres")
const CARROT: KitchenItem = preload("res://resources/items/carrot.tres")
const CHEESE: KitchenItem = preload("res://resources/items/cheese.tres")
const HAM: KitchenItem = preload("res://resources/items/ham.tres")
const LETTUCE: KitchenItem = preload("res://resources/items/lettuce.tres")
const ONION: KitchenItem = preload("res://resources/items/onion.tres")
const POTATO: KitchenItem = preload("res://resources/items/potato.tres")
const STEAK: KitchenItem = preload("res://resources/items/steak.tres")
const TOMATO: KitchenItem = preload("res://resources/items/tomato.tres")
const TWO_BUNS: KitchenItem = preload("res://resources/items/two_buns.tres")

@export_category("Visible Queue")
@export_range(1, 8, 1) var visible_waiter_count := 3
@export var waiter_spacing := Vector3(-2.5, 0.0, 0.0)
@export_range(0.1, 3.0, 0.05) var slot_move_duration := 0.55
@export_range(0.0, 3.0, 0.05) var departure_delay := 0.65
@export var departure_offset := Vector3(0.0, 0.0, -3.2)

@export_category("Item Catalog")
@export var item_catalog: Array[KitchenItem] = [
	BREAD,
	BUN,
	CARROT,
	CHEESE,
	HAM,
	LETTUCE,
	ONION,
	POTATO,
	STEAK,
	TOMATO,
	TWO_BUNS,
]

@export_category("Order Generation")
@export var use_procedural_orders: bool = true

@export_category("Order Cycle")
## Used when use_procedural_orders is false.
## Each dictionary supports: items, base_reward, tip, wrong_item_penalty, target_time, max_time.
## Item keys match KitchenItem.item_id values. This array wraps in fixed order.
@export var order_cycle: Array[Dictionary] = [
	{
		"items": {"bread": 1},
		"base_reward": 3.0,
		"tip": 1.0,
		"wrong_item_penalty": 0.5,
		"target_time": 10.0,
		"max_time": 25.0,
	},
	{
		"items": {"bun": 2},
		"base_reward": 4.0,
		"tip": 1.5,
		"wrong_item_penalty": 0.75,
		"target_time": 16.0,
		"max_time": 35.0,
	},
	{
		"items": {"bread": 1, "bun": 1},
		"base_reward": 5.0,
		"tip": 2.0,
		"wrong_item_penalty": 1.0,
		"target_time": 18.0,
		"max_time": 40.0,
	},
	{
		"items": {"bread": 2, "bun": 2},
		"base_reward": 7.0,
		"tip": 2.5,
		"wrong_item_penalty": 1.0,
		"target_time": 25.0,
		"max_time": 50.0,
	},
]

var dialogue_order_number := 1
var dialogue_order_text := ""

var _waiters: Array[WaiterRobot] = []
var _catalog_by_id: Dictionary = {}
var _item_names: Dictionary = {}
var _cycle_index := 0
var _next_order_id := 1
var _active_order: Dictionary = {}
var _dialogue_waiter: WaiterRobot
var _is_advancing := false

var _recent_order_signatures: Array[String] = []
var _recent_primary_items: Array[StringName] = []
const MAX_RECENT_HISTORY := 6


func _ready() -> void:
	_build_catalog()
	GameControl.order_dialogue_confirmed.connect(_on_order_dialogue_confirmed)
	GameControl.item_delivered.connect(_on_item_delivered)
	_spawn_visible_queue()


func _exit_tree() -> void:
	if GameControl.order_dialogue_confirmed.is_connected(_on_order_dialogue_confirmed):
		GameControl.order_dialogue_confirmed.disconnect(_on_order_dialogue_confirmed)
	if GameControl.item_delivered.is_connected(_on_item_delivered):
		GameControl.item_delivered.disconnect(_on_item_delivered)


func _process(delta: float) -> void:
	if _active_order.is_empty() or _is_advancing:
		return

	var elapsed := float(_active_order.get("elapsed_time", 0.0)) + delta
	_active_order["elapsed_time"] = elapsed

	var target_time := float(_active_order.get("target_time", 12.0))
	var max_time := float(_active_order.get("max_time", 30.0))
	var base_tip := float(_active_order.get("base_tip", 0.0))
	var penalties := float(_active_order.get("penalties", 0.0))

	var decay_mult := 1.0
	if elapsed > target_time:
		decay_mult = clampf(1.0 - (elapsed - target_time) / maxf(max_time - target_time, 0.001), 0.0, 1.0)

	var current_tip := maxf(base_tip * decay_mult - penalties, 0.0)
	_active_order["tip"] = current_tip
	var urgency := clampf(elapsed / maxf(max_time, 0.001), 0.0, 1.0)

	GameControl.order_timer_updated.emit(
		int(_active_order["order_id"]),
		elapsed,
		max_time,
		current_tip,
		urgency
	)


func is_front_waiter(waiter: WaiterRobot) -> bool:
	return not _is_advancing and not _waiters.is_empty() and _waiters[0] == waiter


func get_front_waiter() -> WaiterRobot:
	return null if _waiters.is_empty() else _waiters[0]


func reaction_for_order(order: Dictionary) -> StringName:
	if bool(order.get("had_wrong_item", false)):
		return WaiterRobot.REACTION_ANGRY

	var elapsed := float(order.get("elapsed_time", 0.0))
	var target_time := maxf(float(order.get("target_time", 12.0)), 0.001)
	var max_time := maxf(float(order.get("max_time", target_time + 15.0)), target_time + 0.001)
	if elapsed <= target_time:
		return WaiterRobot.REACTION_HAPPY
	if elapsed >= max_time:
		return WaiterRobot.REACTION_ANGRY
	return WaiterRobot.REACTION_NORMAL


func request_front_dialogue(waiter: WaiterRobot) -> void:
	if not is_front_waiter(waiter) or GameControl.is_dialogue_active():
		return

	_dialogue_waiter = waiter
	dialogue_order_number = _next_order_id
	if _active_order.is_empty():
		dialogue_order_text = "I'd like %s, please." % _format_items(_required_items(waiter.order_data))
	else:
		dialogue_order_text = "I'm still waiting for %s, please." % _format_remaining_items()

	GameControl.look_at_target(waiter.get_look_target())
	DialogueManager.show_dialogue_balloon(ORDER_DIALOGUE, "take_order", [self])


func _on_order_dialogue_confirmed() -> void:
	var waiter := _dialogue_waiter
	_dialogue_waiter = null
	if waiter == null or not is_instance_valid(waiter) or not is_front_waiter(waiter):
		return
	if _active_order.is_empty():
		_accept_front_order(waiter)


func _accept_front_order(waiter: WaiterRobot) -> void:
	var definition := waiter.order_data
	var required := _required_items(definition)
	if required.is_empty():
		push_warning("Skipped an order with no valid item quantities.")
		return

	var fulfilled: Dictionary = {}
	var total_items := 0
	for item_id: StringName in required:
		var qty := int(required[item_id])
		fulfilled[item_id] = 0
		total_items += qty

	var target_time := maxf(float(definition.get("target_time", 8.0 + float(total_items) * 4.0)), 0.001)
	var max_time := maxf(float(definition.get("max_time", target_time + 15.0 + float(total_items) * 6.0)), target_time + 0.001)
	var base_tip := maxf(float(definition.get("tip", 0.0)), 0.0)

	var order_id := _next_order_id
	_next_order_id += 1
	_active_order = {
		"order_id": order_id,
		"items": required,
		"fulfilled": fulfilled,
		"item_names": _item_names.duplicate(),
		"base_reward": maxf(float(definition.get("base_reward", 0.0)), 0.0),
		"base_tip": base_tip,
		"tip": base_tip,
		"penalties": 0.0,
		"wrong_item_penalty": maxf(float(definition.get("wrong_item_penalty", 1.0)), 0.0),
		"had_wrong_item": false,
		"elapsed_time": 0.0,
		"target_time": target_time,
		"max_time": max_time,
	}
	waiter.set_order_accepted(true)
	GameControl.begin_order(order_id)
	GameControl.order_started.emit(order_id, _active_order.duplicate(true))


func _on_item_delivered(item: KitchenItem) -> void:
	if item == null or _active_order.is_empty() or _is_advancing:
		return

	var item_id := item.item_id
	var required: Dictionary = _active_order["items"]
	var fulfilled: Dictionary = _active_order["fulfilled"]
	if required.has(item_id) and int(fulfilled.get(item_id, 0)) < int(required[item_id]):
		fulfilled[item_id] = int(fulfilled.get(item_id, 0)) + 1
		_active_order["fulfilled"] = fulfilled
		GameControl.order_item_fulfilled.emit(
			int(_active_order["order_id"]),
			item_id,
			int(fulfilled[item_id]),
			int(required[item_id])
		)
		if _all_items_fulfilled():
			_finish_active_order()
		return

	_apply_wrong_item_penalty(item)


func _apply_wrong_item_penalty(item: KitchenItem) -> void:
	_active_order["had_wrong_item"] = true
	var front_waiter := get_front_waiter()
	if front_waiter != null:
		front_waiter.show_reaction(WaiterRobot.REACTION_ANGRY)

	var penalty := float(_active_order["wrong_item_penalty"])
	var penalties := float(_active_order.get("penalties", 0.0)) + penalty
	_active_order["penalties"] = penalties

	var elapsed := float(_active_order.get("elapsed_time", 0.0))
	var target_time := float(_active_order.get("target_time", 12.0))
	var max_time := float(_active_order.get("max_time", 30.0))
	var base_tip := float(_active_order.get("base_tip", 0.0))
	var decay_mult := 1.0
	if elapsed > target_time:
		decay_mult = clampf(1.0 - (elapsed - target_time) / maxf(max_time - target_time, 0.001), 0.0, 1.0)

	var remaining_tip := maxf(base_tip * decay_mult - penalties, 0.0)
	_active_order["tip"] = remaining_tip
	# Wrong deliveries are accepted and consumed, but never pay out directly.
	# They can still reduce the order tip through the existing penalty model.
	GameControl.order_penalized.emit(
		int(_active_order["order_id"]),
		remaining_tip,
		penalty,
		item.display_name
	)


func _finish_active_order() -> void:
	if _active_order.is_empty() or _is_advancing:
		return
	_is_advancing = true
	var finished_order := _active_order.duplicate(true)
	var order_id := int(finished_order["order_id"])
	var payout := float(finished_order["base_reward"]) + float(finished_order["tip"])
	var front_waiter := get_front_waiter()
	if front_waiter != null:
		front_waiter.show_reaction(reaction_for_order(finished_order))
	GameControl.end_order(order_id)
	GameControl.change_money(payout, "ORDER %d COMPLETE" % order_id)
	GameControl.order_completed.emit(order_id, payout, float(finished_order["tip"]))
	_active_order.clear()
	await get_tree().create_timer(departure_delay).timeout
	await _advance_queue()
	_is_advancing = false


func _advance_queue() -> void:
	if _waiters.is_empty():
		return
	var departing: WaiterRobot = _waiters.pop_front()
	await departing.depart(departure_offset, slot_move_duration)

	for index in _waiters.size():
		var waiter := _waiters[index]
		waiter.slot_index = index
		waiter.move_to_slot(_slot_position(index), slot_move_duration)

	departing.position = _slot_position(visible_waiter_count)
	departing.configure(self, _next_order_definition(), visible_waiter_count - 1)
	_waiters.append(departing)
	await departing.move_to_slot(_slot_position(visible_waiter_count - 1), slot_move_duration)


func _spawn_visible_queue() -> void:
	for index in maxi(visible_waiter_count, 1):
		var waiter := WAITER_SCENE.instantiate() as WaiterRobot
		if waiter == null:
			push_error("waiter_robot.tscn must instantiate a WaiterRobot.")
			return
		add_child(waiter)
		waiter.position = _slot_position(index)
		waiter.configure(self, _next_order_definition(), index)
		_waiters.append(waiter)


const NON_ORDERABLE_ITEMS: Array[StringName] = [
	&"vegetableburger_uncooked",
	&"stew_base",
	&"bun_top",
	&"bun_bottom",
]


func _next_order_definition() -> Dictionary:
	if use_procedural_orders:
		return generate_random_order()

	if order_cycle.is_empty():
		return {
			"items": {"bread": 1},
			"base_reward": 1.0,
			"tip": 0.0,
			"wrong_item_penalty": 0.5,
			"target_time": 10.0,
			"max_time": 25.0,
		}
	var definition: Dictionary = order_cycle[_cycle_index % order_cycle.size()].duplicate(true)
	_cycle_index = (_cycle_index + 1) % order_cycle.size()
	return definition


static func compute_order_signature(items_dict: Dictionary) -> String:
	var keys: Array = items_dict.keys()
	keys.sort()
	var parts: Array[String] = []
	for k: Variant in keys:
		parts.append("%s:%d" % [str(k), int(items_dict[k])])
	return ",".join(parts)


func get_active_waiter_signatures() -> Array[String]:
	var signatures: Array[String] = []
	for w: WaiterRobot in _waiters:
		if w != null and is_instance_valid(w) and w.order_data != null:
			var items: Variant = w.order_data.get("items", {})
			if items is Dictionary and not items.is_empty():
				signatures.append(compute_order_signature(items))
	return signatures


func clear_order_history() -> void:
	_recent_order_signatures.clear()
	_recent_primary_items.clear()


func _calculate_item_weight(item_id: StringName, queue_item_counts: Dictionary) -> float:
	var val := estimate_item_value(item_id)

	var base_w := 1.0
	if val >= 18.0:
		base_w = 1.8
	elif val >= 8.0:
		base_w = 1.4
	else:
		base_w = 1.0

	var active_count: int = int(queue_item_counts.get(item_id, 0))
	if active_count > 0:
		base_w *= 0.15 / float(active_count)

	var history_len := _recent_primary_items.size()
	for i in range(history_len):
		var rec_idx := history_len - 1 - i
		if _recent_primary_items[rec_idx] == item_id:
			if i == 0:
				base_w *= 0.15
			elif i == 1:
				base_w *= 0.35
			elif i == 2:
				base_w *= 0.60
			break

	return maxf(base_w, 0.01)


func _pick_weighted(items: Array[StringName], weights: Dictionary) -> StringName:
	var total := 0.0
	for it: StringName in items:
		total += float(weights.get(it, 1.0))
	if total <= 0.0:
		return items[randi() % items.size()]
	var roll := randf_range(0.0, total)
	var accum := 0.0
	for it: StringName in items:
		accum += float(weights.get(it, 1.0))
		if roll <= accum:
			return it
	return items.back()


func _generate_candidate_items(eligible_ids: Array[StringName], queue_item_counts: Dictionary) -> Dictionary:
	var items_dict: Dictionary = {}
	var n_eligible := eligible_ids.size()

	var distinct_count := 1
	var roll := randf()
	if n_eligible >= 5:
		if roll < 0.20:
			distinct_count = 3
		elif roll < 0.70:
			distinct_count = 2
		else:
			distinct_count = 1
	elif n_eligible >= 3:
		if roll < 0.50:
			distinct_count = 2
		else:
			distinct_count = 1
	elif n_eligible >= 2:
		if roll < 0.40:
			distinct_count = 2
		else:
			distinct_count = 1

	distinct_count = mini(distinct_count, n_eligible)

	var weights: Dictionary = {}
	for it: StringName in eligible_ids:
		weights[it] = _calculate_item_weight(it, queue_item_counts)

	var pool := eligible_ids.duplicate()
	for _i in range(distinct_count):
		if pool.is_empty():
			break
		var chosen_id := _pick_weighted(pool, weights)
		pool.erase(chosen_id)

		var val := estimate_item_value(chosen_id)
		var qty := 1

		if distinct_count == 1:
			if val < 6.0:
				var q_roll := randf()
				if q_roll < 0.45:
					qty = 1
				elif q_roll < 0.85:
					qty = 2
				else:
					qty = 3
			elif val < 15.0:
				if randf() < 0.35:
					qty = 2
				else:
					qty = 1
			else:
				if randf() < 0.10:
					qty = 2
				else:
					qty = 1
		else:
			if val < 6.0 and randf() < 0.25:
				qty = 2
			else:
				qty = 1

		items_dict[chosen_id] = qty

	return items_dict


func _record_order_history(signature: String, items_dict: Dictionary) -> void:
	_recent_order_signatures.append(signature)
	while _recent_order_signatures.size() > MAX_RECENT_HISTORY:
		_recent_order_signatures.pop_front()

	for item_id: StringName in items_dict:
		_recent_primary_items.append(item_id)
	while _recent_primary_items.size() > MAX_RECENT_HISTORY * 2:
		_recent_primary_items.pop_front()


func generate_random_order() -> Dictionary:
	var producible: Dictionary = get_producible_items()
	var eligible_ids: Array[StringName] = []
	for item_id: StringName in producible:
		if not NON_ORDERABLE_ITEMS.has(item_id):
			eligible_ids.append(item_id)

	if eligible_ids.is_empty():
		if producible.is_empty():
			eligible_ids.append(&"bread")
		else:
			for item_id: StringName in producible:
				eligible_ids.append(item_id)

	eligible_ids.sort()

	var active_signatures := get_active_waiter_signatures()
	var queue_item_counts: Dictionary = {}
	for w: WaiterRobot in _waiters:
		if w != null and is_instance_valid(w) and w.order_data != null:
			var items: Variant = w.order_data.get("items", {})
			if items is Dictionary:
				for k: Variant in items:
					var sid := StringName(str(k))
					queue_item_counts[sid] = int(queue_item_counts.get(sid, 0)) + 1

	var best_items_dict: Dictionary = {}
	var best_signature := ""
	var best_score := -999999.0

	for _attempt in range(12):
		var cand_items := _generate_candidate_items(eligible_ids, queue_item_counts)
		var cand_sig := compute_order_signature(cand_items)

		var score := 0.0
		if active_signatures.has(cand_sig):
			score -= 1000.0
		if not _recent_order_signatures.is_empty() and _recent_order_signatures.back() == cand_sig:
			score -= 500.0
		elif _recent_order_signatures.has(cand_sig):
			score -= 100.0

		for cand_id: StringName in cand_items:
			if not queue_item_counts.has(cand_id):
				score += 50.0
			if not _recent_primary_items.has(cand_id):
				score += 30.0

		score += randf() * 10.0

		if score > best_score or best_items_dict.is_empty():
			best_score = score
			best_items_dict = cand_items
			best_signature = cand_sig

		if score >= 50.0:
			break

	_record_order_history(best_signature, best_items_dict)

	var total_base_reward := 0.0
	var total_prep_time := 0.0

	for chosen_id: StringName in best_items_dict:
		var qty := int(best_items_dict[chosen_id])
		var val := estimate_item_value(chosen_id)
		var prep := estimate_item_prep_time(chosen_id)
		total_base_reward += val * float(qty)
		total_prep_time += prep * float(qty)

	var base_reward := maxf(roundf(total_base_reward), 2.0)
	var tip := maxf(roundf(base_reward * randf_range(0.25, 0.35)), 1.0)
	var wrong_penalty := maxf(roundf(base_reward * 0.20), 0.5)
	var target_time := maxf(10.0, roundf(total_prep_time + 8.0))
	var max_time := maxf(target_time + 15.0, roundf(target_time * 2.2 + 5.0))

	return {
		"items": best_items_dict,
		"base_reward": base_reward,
		"tip": tip,
		"wrong_item_penalty": wrong_penalty,
		"target_time": target_time,
		"max_time": max_time,
	}


func get_producible_items() -> Dictionary:
	return OrderQueue.evaluate_producible_items(get_tree(), _catalog_by_id)


func is_item_producible(item_id: StringName) -> bool:
	var producible := get_producible_items()
	return producible.has(item_id)


func estimate_item_value(item_id: StringName) -> float:
	match item_id:
		&"bread": return 3.0
		&"bun": return 4.5
		&"two_buns": return 8.0
		&"carrot": return 3.5
		&"carrot_washed": return 5.5
		&"carrot_chopped", &"carrot_pieces": return 5.0
		&"cheese": return 4.5
		&"cheese_slice", &"cheese_chopped": return 6.0
		&"ham": return 5.0
		&"ham_cooked", &"ham_roasted": return 8.5
		&"ham_chilled": return 10.0
		&"lettuce": return 3.5
		&"lettuce_slice", &"lettuce_chopped": return 5.0
		&"salad_chilled": return 8.0
		&"onion": return 3.5
		&"onion_chopped", &"onion_rings": return 5.0
		&"onion_rings_fried": return 7.5
		&"potato": return 3.5
		&"potato_chopped": return 5.0
		&"potato_mashed": return 7.5
		&"steak": return 6.5
		&"steak_pieces": return 9.5
		&"steak_broiled": return 11.0
		&"burger_cooked": return 12.5
		&"vegetableburger_cooked": return 11.5
		&"cheeseburger": return 22.0
		&"veggie_burger": return 20.0
		&"steak_dinner": return 24.0
		&"beef_stew": return 22.0
		&"tomato": return 3.5
		&"tomato_slice", &"tomato_slices": return 5.0
		&"ketchup", &"mustard", &"pickles": return 7.5
		_: return 5.0


func estimate_item_prep_time(item_id: StringName) -> float:
	match item_id:
		&"bread", &"carrot", &"cheese", &"ham", &"lettuce", &"onion", &"potato", &"steak", &"tomato":
			return 4.0
		&"bun", &"carrot_washed", &"carrot_chopped", &"carrot_pieces", &"cheese_slice", &"cheese_chopped", &"lettuce_slice", &"lettuce_chopped", &"onion_chopped", &"onion_rings", &"potato_chopped", &"tomato_slice", &"tomato_slices":
			return 6.0
		&"two_buns", &"ham_cooked", &"ham_roasted", &"ham_chilled", &"onion_rings_fried", &"potato_mashed", &"steak_pieces", &"steak_broiled", &"salad_chilled", &"ketchup", &"mustard", &"pickles":
			return 8.0
		&"burger_cooked", &"vegetableburger_cooked":
			return 10.0
		&"cheeseburger", &"veggie_burger", &"steak_dinner", &"beef_stew":
			return 16.0
		_:
			return 6.0


static func evaluate_producible_items(tree: SceneTree, catalog_by_id: Dictionary = {}) -> Dictionary:
	var producible: Dictionary = {}

	if tree == null:
		if catalog_by_id.has(&"bread"):
			producible[&"bread"] = catalog_by_id[&"bread"]
		return producible

	# 1. Collect all active ItemSources
	var sources: Array[ItemSource] = []
	for node in tree.get_nodes_in_group(&"item_sources"):
		if _is_workstation_active(node) and node is ItemSource:
			sources.append(node)

	if sources.is_empty():
		_find_nodes_of_type(tree.root, ItemSource, sources)

	for source in sources:
		if source.item != null and not source.item.item_id.is_empty():
			producible[source.item.item_id] = source.item

	# If no sources found in tree, fallback to starter bread
	if producible.is_empty():
		if catalog_by_id.has(&"bread"):
			producible[&"bread"] = catalog_by_id[&"bread"]
		elif not catalog_by_id.is_empty():
			var first_key: StringName = catalog_by_id.keys()[0]
			producible[first_key] = catalog_by_id[first_key]

	# 2. Collect all active ItemProcessors and AssemblyCounters
	var processors: Array[ItemProcessor] = []
	for node in tree.get_nodes_in_group(&"item_processors"):
		if _is_workstation_active(node) and node is ItemProcessor:
			processors.append(node)
	if processors.is_empty():
		_find_nodes_of_type(tree.root, ItemProcessor, processors)

	var assembly_counters: Array[AssemblyCounter] = []
	for node in tree.get_nodes_in_group(&"assembly_counters"):
		if _is_workstation_active(node) and node is AssemblyCounter:
			assembly_counters.append(node)
	if assembly_counters.is_empty():
		_find_nodes_of_type(tree.root, AssemblyCounter, assembly_counters)

	# 3. Fixed-point reachability propagation
	var changed := true
	var iterations := 0
	const MAX_ITERATIONS := 12

	while changed and iterations < MAX_ITERATIONS:
		changed = false
		iterations += 1

		# Single-item transformations
		for proc in processors:
			for recipe in proc.get_process_recipes():
				if recipe != null and recipe.is_valid():
					var in_id := recipe.input_item.item_id
					var out_id := recipe.output_item.item_id
					if producible.has(in_id) and not producible.has(out_id):
						producible[out_id] = recipe.output_item
						changed = true

		# Multi-item composite assembly recipes
		for counter in assembly_counters:
			for recipe in counter.available_recipes:
				if recipe != null and recipe.output_item != null:
					var out_id := recipe.output_item.item_id
					if not producible.has(out_id) and not recipe.ingredient_sequence.is_empty():
						var all_available := true
						for ing in recipe.ingredient_sequence:
							if ing == null or not producible.has(ing.item_id):
								all_available = false
								break
						if all_available:
							producible[out_id] = recipe.output_item
							changed = true

	return producible


static func _is_workstation_active(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return false

	# If the top-level placed appliance or node is hidden (e.g. while being moved in placement mode), it is inactive
	var top_node: Node = node
	while top_node.get_parent() != null and top_node.get_parent() != node.get_tree().root:
		if top_node.get_parent().name == "Architecture" or top_node.get_parent().is_in_group(&"placed_items"):
			break
		top_node = top_node.get_parent()

	if top_node is Node3D and not (top_node as Node3D).visible:
		return false
	if top_node is CanvasItem and not (top_node as CanvasItem).visible:
		return false

	# Area3D check - active if monitorable or monitoring
	if node is Area3D:
		var area := node as Area3D
		if not area.monitorable and not area.monitoring:
			return false

	var curr: Node = node
	while curr != null:
		if curr.name.containsn("ghost") or (curr.name.containsn("PlacementManager") and curr.get_parent() != null and curr.name != "PlacementManager"):
			return false
		curr = curr.get_parent()
	return true


static func _find_nodes_of_type(root: Node, type_class: Variant, out_array: Array) -> void:
	if root == null:
		return
	if is_instance_of(root, type_class) and _is_workstation_active(root):
		out_array.append(root)
	for child in root.get_children():
		_find_nodes_of_type(child, type_class, out_array)


func _required_items(definition: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	var items_value: Variant = definition.get("items", {})
	if items_value is not Dictionary:
		return normalized
	for raw_id: Variant in items_value:
		var item_id := StringName(str(raw_id))
		var quantity := maxi(int(items_value[raw_id]), 0)
		if quantity <= 0:
			continue
		if not _catalog_by_id.has(item_id):
			push_warning("Order references unknown KitchenItem id '%s'." % item_id)
			continue
		normalized[item_id] = quantity
	return normalized


func _build_catalog() -> void:
	_catalog_by_id.clear()
	_item_names.clear()

	# Auto-discover all KitchenItems in resources/items
	var items_dir := DirAccess.open("res://resources/items")
	if items_dir != null:
		items_dir.list_dir_begin()
		var file_name := items_dir.get_next()
		while not file_name.is_empty():
			if file_name.ends_with(".tres") or file_name.ends_with(".res"):
				var resource_path := "res://resources/items/".path_join(file_name)
				var loaded_item := load(resource_path) as KitchenItem
				if loaded_item != null and not loaded_item.item_id.is_empty():
					_catalog_by_id[loaded_item.item_id] = loaded_item
					_item_names[loaded_item.item_id] = loaded_item.display_name
			file_name = items_dir.get_next()

	for item in item_catalog:
		if item == null or item.item_id.is_empty():
			continue
		_catalog_by_id[item.item_id] = item
		_item_names[item.item_id] = item.display_name


func _all_items_fulfilled() -> bool:
	var required: Dictionary = _active_order["items"]
	var fulfilled: Dictionary = _active_order["fulfilled"]
	for item_id: StringName in required:
		if int(fulfilled.get(item_id, 0)) < int(required[item_id]):
			return false
	return true


func _format_remaining_items() -> String:
	var remaining: Dictionary = {}
	var required: Dictionary = _active_order["items"]
	var fulfilled: Dictionary = _active_order["fulfilled"]
	for item_id: StringName in required:
		var amount := int(required[item_id]) - int(fulfilled.get(item_id, 0))
		if amount > 0:
			remaining[item_id] = amount
	return _format_items(remaining)


func _format_items(items: Dictionary) -> String:
	var parts: Array[String] = []
	for raw_id: Variant in items:
		var item_id := StringName(str(raw_id))
		var display_name := str(_item_names.get(item_id, str(item_id).capitalize()))
		parts.append("%d %s" % [int(items[raw_id]), display_name])
	if parts.is_empty():
		return "nothing else"
	if parts.size() == 1:
		return parts[0]
	var last_part: String = parts.pop_back()
	return ", ".join(parts) + " and " + last_part


func _slot_position(index: int) -> Vector3:
	return waiter_spacing * float(index)
