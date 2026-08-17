class_name BotDispatchManager
extends Node
## Turns Bot Handoff allocations into finite autonomous kitchen jobs.

const BOT_WORKER_SCENE: PackedScene = preload("res://scenes/bot_worker.tscn")
const MAX_ROUTE_DEPTH := 16
const NAVIGATION_TIMEOUT := 45.0
const ASSEMBLY_STEP_MINIMUM := 0.35
const SPAWN_ATTEMPTS := 12
const SPAWN_ANGLE_STEP := PI * (3.0 - sqrt(5.0))
const SPAWN_NAV_TOLERANCE := 0.2
const MIN_PLAYER_SPAWN_DISTANCE := 1.25
const MIN_BOT_SPAWN_DISTANCE := 0.85

@export var spawn_radius := 2.2
@export var spawn_height := 0.05

var _active_bots: Dictionary = {}
var _requirements_by_order: Dictionary = {}
var _fulfilled_by_order: Dictionary = {}
var _cancelled_orders: Dictionary = {}
var _spawn_serial := 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	GameControl.bots_assigned.connect(_on_bots_assigned)
	GameControl.order_started.connect(_on_order_started)
	GameControl.order_item_fulfilled.connect(_on_order_item_fulfilled)
	GameControl.order_completed.connect(_on_order_completed)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if GameControl.bots_assigned.is_connected(_on_bots_assigned):
		GameControl.bots_assigned.disconnect(_on_bots_assigned)
	if GameControl.order_started.is_connected(_on_order_started):
		GameControl.order_started.disconnect(_on_order_started)
	if GameControl.order_item_fulfilled.is_connected(_on_order_item_fulfilled):
		GameControl.order_item_fulfilled.disconnect(_on_order_item_fulfilled)
	if GameControl.order_completed.is_connected(_on_order_completed):
		GameControl.order_completed.disconnect(_on_order_completed)


func _on_order_started(order_id: int, order: Dictionary) -> void:
	_cancelled_orders.erase(order_id)
	_requirements_by_order[order_id] = (order.get("items", {}) as Dictionary).duplicate()
	_fulfilled_by_order[order_id] = (order.get("fulfilled", {}) as Dictionary).duplicate()


func _on_order_item_fulfilled(order_id: int, item_id: StringName, fulfilled: int, _required: int) -> void:
	var fulfilled_items: Dictionary = _fulfilled_by_order.get(order_id, {})
	fulfilled_items[item_id] = fulfilled
	_fulfilled_by_order[order_id] = fulfilled_items


func _on_order_completed(order_id: int, _payout: float, _final_tip: float) -> void:
	_cancelled_orders[order_id] = true
	_requirements_by_order.erase(order_id)
	_fulfilled_by_order.erase(order_id)


func _on_bots_assigned(order_id: int, allocations: Dictionary) -> void:
	if order_id <= 0 or order_id != GameControl.active_order_id:
		return
	if not _requirements_by_order.has(order_id):
		var order := GameControl.active_order_data
		_requirements_by_order[order_id] = (order.get("items", {}) as Dictionary).duplicate()
		_fulfilled_by_order[order_id] = (order.get("fulfilled", {}) as Dictionary).duplicate()

	var slots_available := maxi(GameControl.MAX_BOTS - _active_bots.size(), 0)
	for raw_item_id: Variant in allocations:
		if slots_available <= 0:
			break
		var item_id := StringName(str(raw_item_id))
		if not RecipeTracker.is_item_automated(item_id):
			continue
		var requested := maxi(int(allocations[raw_item_id]), 0)
		var running := _count_active_jobs(order_id, item_id)
		var requirements: Dictionary = _requirements_by_order[order_id]
		var fulfilled: Dictionary = _fulfilled_by_order.get(order_id, {})
		var remaining_needed := maxi(
			int(requirements.get(item_id, 0)) - int(fulfilled.get(item_id, 0)),
			0
		)
		var count := mini(
			mini(maxi(requested - running, 0), maxi(remaining_needed - running, 0)),
			slots_available
		)
		for _index in count:
			_start_bot_job(order_id, item_id)
			slots_available -= 1
	_sync_active_allocations(order_id)


func _start_bot_job(order_id: int, item_id: StringName) -> void:
	var bot := BOT_WORKER_SCENE.instantiate() as BotWorker
	if bot == null:
		_emit_job_result(order_id, item_id, false, "worker scene could not be created")
		return

	add_child(bot)
	_spawn_serial += 1
	bot.name = "Bot_%02d_%s" % [_spawn_serial, item_id]
	bot.set_meta(&"order_id", order_id)
	bot.set_meta(&"item_id", item_id)
	bot.global_position = _choose_spawn_position(_spawn_serial)
	_active_bots[bot.get_instance_id()] = bot

	await get_tree().physics_frame
	await get_tree().physics_frame

	var succeeded := await _produce_item(bot, item_id, order_id, true, 0)
	if succeeded and _is_item_still_needed(order_id, item_id):
		var order_window := _find_order_window()
		if order_window != null:
			succeeded = await _travel_and_interact(bot, order_window)
			if succeeded:
				succeeded = not bot.has_held_item()
		else:
			succeeded = false

	if succeeded:
		_emit_job_result(order_id, item_id, true, "")
	elif _is_task_active(order_id):
		_emit_job_result(order_id, item_id, false, "route unavailable")

	_active_bots.erase(bot.get_instance_id())
	_sync_active_allocations(order_id)
	if is_instance_valid(bot):
		bot.despawn()


func _produce_item(
	bot: BotWorker,
	item_id: StringName,
	order_id: int,
	require_learned_recipe: bool,
	depth: int
) -> bool:
	if not _is_task_active(order_id) or depth > MAX_ROUTE_DEPTH:
		return false

	var source := _find_item_source(item_id)
	if source != null:
		if bot.has_held_item():
			bot.set_held_item(null)
		var took_item := await _travel_and_interact(bot, source)
		return took_item and bot.is_holding(item_id)

	var process_recipe := _find_process_recipe(item_id, require_learned_recipe)
	if process_recipe != null:
		if not await _produce_item(bot, process_recipe.input_item.item_id, order_id, false, depth + 1):
			return false
		if not _is_task_active(order_id):
			return false
		var processor := _find_processor(process_recipe.recipe_id)
		if processor == null:
			return false
		var processed := await _travel_and_interact(bot, processor, process_recipe.recipe_id)
		return processed and bot.is_holding(item_id)

	var assembly_recipe := _find_assembly_recipe(item_id, require_learned_recipe)
	if assembly_recipe != null:
		var counter := _find_assembly_counter()
		if counter == null:
			return false
		for ingredient in assembly_recipe.ingredient_sequence:
			if ingredient == null:
				return false
			if not await _produce_item(bot, ingredient.item_id, order_id, false, depth + 1):
				return false
			if not await _travel_to_area(bot, counter):
				return false
			var wait_time := maxf(counter.get_interaction_hold_duration(bot), ASSEMBLY_STEP_MINIMUM)
			await get_tree().create_timer(wait_time).timeout
			if not _is_task_active(order_id):
				return false
			bot.set_held_item(null)
		bot.set_held_item(assembly_recipe.output_item)
		return bot.is_holding(item_id)

	return false


func _travel_and_interact(
	bot: BotWorker,
	target: InteractionArea,
	process_recipe_id: StringName = &""
) -> bool:
	if bot == null or not is_instance_valid(bot) or target == null or not is_instance_valid(target):
		return false
	bot.dispatch_to(target, process_recipe_id)
	return await _wait_for_bot(bot)


func _travel_to_area(bot: BotWorker, target: InteractionArea) -> bool:
	if bot == null or not is_instance_valid(bot) or target == null or not is_instance_valid(target):
		return false
	bot.navigate_to_position(target.get_interaction_position(bot.global_position))
	return await _wait_for_bot(bot)


func _wait_for_bot(bot: BotWorker) -> bool:
	var started := Time.get_ticks_msec()
	while is_instance_valid(bot) and (
		bot.get_state() == BotWorker.State.NAVIGATING
		or bot.get_state() == BotWorker.State.INTERACTING
	):
		if float(Time.get_ticks_msec() - started) / 1000.0 > NAVIGATION_TIMEOUT:
			bot.stop_navigation()
			return false
		await get_tree().physics_frame
	return is_instance_valid(bot) and bot.get_state() == BotWorker.State.IDLE


func _find_item_source(item_id: StringName) -> ItemSource:
	var best: ItemSource
	for node in get_tree().get_nodes_in_group(&"item_sources"):
		var source := node as ItemSource
		if source != null and source.item != null and source.item.item_id == item_id:
			best = source
			break
	return best


func _find_process_recipe(item_id: StringName, learned_only: bool) -> ItemProcessRecipe:
	var fallback: ItemProcessRecipe = null
	for recipe in RecipeTracker.get_all_process_recipes():
		if recipe == null or recipe.output_item == null or recipe.output_item.item_id != item_id:
			continue
		if _find_processor(recipe.recipe_id) == null:
			continue
		if RecipeTracker.has_made_recipe(recipe.recipe_id):
			return recipe
		if not learned_only and fallback == null:
			fallback = recipe
	return fallback


func _find_assembly_recipe(item_id: StringName, learned_only: bool) -> Recipe:
	var fallback: Recipe = null
	for recipe in RecipeTracker.get_all_assembly_recipes():
		if recipe == null or recipe.output_item == null or recipe.output_item.item_id != item_id:
			continue
		if RecipeTracker.has_made_recipe(recipe.recipe_id):
			return recipe
		if not learned_only and fallback == null:
			fallback = recipe
	return fallback


func _find_processor(recipe_id: StringName) -> ItemProcessor:
	for node in get_tree().get_nodes_in_group(&"item_processors"):
		var processor := node as ItemProcessor
		if processor == null:
			continue
		for recipe in processor.get_process_recipes():
			if recipe != null and recipe.recipe_id == recipe_id:
				return processor
	return null


func _find_assembly_counter() -> AssemblyCounter:
	var counters := get_tree().get_nodes_in_group(&"assembly_counters")
	for node in counters:
		var counter := node as AssemblyCounter
		if counter != null:
			return counter
	return null


func _find_order_window() -> OrderWindow:
	return _find_order_window_below(get_tree().current_scene)


func _find_order_window_below(node: Node) -> OrderWindow:
	if node == null:
		return null
	if node is OrderWindow:
		return node as OrderWindow
	for child in node.get_children():
		var found := _find_order_window_below(child)
		if found != null:
			return found
	return null


func _choose_spawn_position(serial: int) -> Vector3:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var center := player.global_position if player != null else Vector3.ZERO
	var world := get_viewport().world_3d
	if world == null:
		return center + Vector3.UP * spawn_height

	var nav_map := world.navigation_map
	if not nav_map.is_valid() or not NavigationServer3D.map_is_active(nav_map):
		return center + Vector3.UP * spawn_height

	var nav_origin := NavigationServer3D.map_get_closest_point(nav_map, center)
	var base_angle := float(serial) * TAU / float(GameControl.MAX_BOTS)
	for attempt in SPAWN_ATTEMPTS:
		# Sweep around the player so a sample across a wall is replaced by one
		# inside the same reachable kitchen island. The jitter keeps repeated
		# handoffs from appearing in an identical formation.
		var angle := (
			base_angle
			+ float(attempt) * SPAWN_ANGLE_STEP
			+ randf_range(-0.18, 0.18)
		)
		var radius := spawn_radius + randf_range(-0.25, 0.25)
		var desired := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var nav_point := NavigationServer3D.map_get_closest_point(nav_map, desired)
		if not _is_reachable_spawn(nav_map, nav_origin, nav_point):
			continue
		if not _is_spawn_position_clear(nav_point, player):
			continue
		return nav_point + Vector3.UP * spawn_height

	# This remains on the player connected navmesh even in very cramped
	# layouts. Normal kitchen geometry finds a separated point in the loop.
	return nav_origin + Vector3.UP * spawn_height


func _is_reachable_spawn(nav_map: RID, origin: Vector3, candidate: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(nav_map, origin, candidate, true)
	return (
		not path.is_empty()
		and path[0].distance_to(origin) <= SPAWN_NAV_TOLERANCE
		and path[path.size() - 1].distance_to(candidate) <= SPAWN_NAV_TOLERANCE
	)


func _is_spawn_position_clear(candidate: Vector3, player: Node3D) -> bool:
	if player != null and _flat_distance(candidate, player.global_position) < MIN_PLAYER_SPAWN_DISTANCE:
		return false
	for active_bot: BotWorker in _active_bots.values():
		if (
			is_instance_valid(active_bot)
			and _flat_distance(candidate, active_bot.global_position) < MIN_BOT_SPAWN_DISTANCE
		):
			return false
	return true


func _flat_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _count_active_jobs(order_id: int, item_id: StringName) -> int:
	var count := 0
	for bot_node: BotWorker in _active_bots.values():
		if not is_instance_valid(bot_node):
			continue
		if int(bot_node.get_meta(&"order_id", 0)) == order_id and StringName(
			bot_node.get_meta(&"item_id", &"")
		) == item_id:
			count += 1
	return count


func _sync_active_allocations(order_id: int) -> void:
	if GameControl.active_order_id != order_id:
		return
	var active: Dictionary = {}
	for bot_node: BotWorker in _active_bots.values():
		if not is_instance_valid(bot_node):
			continue
		if int(bot_node.get_meta(&"order_id", 0)) != order_id:
			continue
		var item_id := StringName(bot_node.get_meta(&"item_id", &""))
		active[item_id] = int(active.get(item_id, 0)) + 1
	GameControl.active_bot_allocations = active


func _is_task_active(order_id: int) -> bool:
	return (
		order_id > 0
		and not bool(_cancelled_orders.get(order_id, false))
		and GameControl.active_order_id == order_id
	)


func _is_item_still_needed(order_id: int, item_id: StringName) -> bool:
	if not _is_task_active(order_id):
		return false
	var requirements: Dictionary = _requirements_by_order.get(order_id, {})
	var fulfilled: Dictionary = _fulfilled_by_order.get(order_id, {})
	return int(fulfilled.get(item_id, 0)) < int(requirements.get(item_id, 0))


func _emit_job_result(order_id: int, item_id: StringName, succeeded: bool, detail: String) -> void:
	var item_name := RecipeTracker.get_recipe_name(item_id)
	GameControl.bot_task_completed.emit(order_id, item_id, item_name, succeeded, detail)
