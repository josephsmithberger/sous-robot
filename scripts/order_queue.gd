class_name OrderQueue
extends Node3D
## Deterministic, endlessly wrapping queue of editor-authored order dictionaries.

const WAITER_SCENE: PackedScene = preload("res://scenes/waiter_robot.tscn")
const ORDER_DIALOGUE: DialogueResource = preload("res://dialogue/orders.dialogue")
const BREAD: KitchenItem = preload("res://resources/items/bread.tres")
const SLICED_BREAD: KitchenItem = preload("res://resources/items/sliced_bread.tres")

@export_category("Visible Queue")
@export_range(1, 8, 1) var visible_waiter_count := 3
@export var waiter_spacing := Vector3(-2.5, 0.0, 0.0)
@export_range(0.1, 3.0, 0.05) var slot_move_duration := 0.55
@export_range(0.0, 3.0, 0.05) var departure_delay := 0.65
@export var departure_offset := Vector3(0.0, 0.0, -3.2)

@export_category("Item Catalog")
@export var item_catalog: Array[KitchenItem] = [BREAD, SLICED_BREAD]

@export_category("Order Cycle")
## Each dictionary supports: items, base_reward, tip, wrong_item_penalty.
## Item keys match KitchenItem.item_id values. This array wraps in fixed order.
@export var order_cycle: Array[Dictionary] = [
	{
		"items": {"bread": 1},
		"base_reward": 3.0,
		"tip": 1.0,
		"wrong_item_penalty": 0.5,
	},
	{
		"items": {"sliced_bread": 2},
		"base_reward": 4.0,
		"tip": 1.5,
		"wrong_item_penalty": 0.75,
	},
	{
		"items": {"bread": 1, "sliced_bread": 1},
		"base_reward": 5.0,
		"tip": 2.0,
		"wrong_item_penalty": 1.0,
	},
	{
		"items": {"bread": 2, "sliced_bread": 2},
		"base_reward": 7.0,
		"tip": 2.5,
		"wrong_item_penalty": 1.0,
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


func is_front_waiter(waiter: WaiterRobot) -> bool:
	return not _is_advancing and not _waiters.is_empty() and _waiters[0] == waiter


func get_front_waiter() -> WaiterRobot:
	return null if _waiters.is_empty() else _waiters[0]


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
	for item_id: StringName in required:
		fulfilled[item_id] = 0

	var order_id := _next_order_id
	_next_order_id += 1
	_active_order = {
		"order_id": order_id,
		"items": required,
		"fulfilled": fulfilled,
		"item_names": _item_names.duplicate(),
		"base_reward": maxf(float(definition.get("base_reward", 0.0)), 0.0),
		"tip": maxf(float(definition.get("tip", 0.0)), 0.0),
		"wrong_item_penalty": maxf(float(definition.get("wrong_item_penalty", 1.0)), 0.0),
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
	var penalty := float(_active_order["wrong_item_penalty"])
	var remaining_tip := maxf(float(_active_order["tip"]) - penalty, 0.0)
	_active_order["tip"] = remaining_tip
	GameControl.change_money(-penalty, "WRONG %s" % item.display_name.to_upper())
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


func _next_order_definition() -> Dictionary:
	if order_cycle.is_empty():
		return {
			"items": {"bread": 1},
			"base_reward": 1.0,
			"tip": 0.0,
			"wrong_item_penalty": 0.5,
		}
	var definition: Dictionary = order_cycle[_cycle_index % order_cycle.size()].duplicate(true)
	_cycle_index = (_cycle_index + 1) % order_cycle.size()
	return definition


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
