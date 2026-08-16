class_name AssemblyCounter
extends InteractionArea
## Interactive workstation appliance for assembling composite recipes from individual ingredients.

const DEFAULT_TWO_BUNS_RECIPE: Recipe = preload("res://resources/recipes/two_buns.tres")
const DEFAULT_CHEESEBURGER_RECIPE: Recipe = preload("res://resources/recipes/cheeseburger.tres")
const DEFAULT_VEGGIE_BURGER_RECIPE: Recipe = preload("res://resources/recipes/veggie_burger.tres")
const DEFAULT_VEGETABLEBURGER_UNCOOKED_RECIPE: Recipe = preload("res://resources/recipes/vegetableburger_uncooked.tres")
const DEFAULT_STEAK_DINNER_RECIPE: Recipe = preload("res://resources/recipes/steak_dinner.tres")
const DEFAULT_STEAK_DINNER_BROILED_RECIPE: Recipe = preload("res://resources/recipes/steak_dinner_broiled.tres")
const DEFAULT_STEW_BASE_RECIPE: Recipe = preload("res://resources/recipes/stew_base.tres")

@export var available_recipes: Array[Recipe] = []
@export var assembly_plate_path: NodePath = NodePath("AssemblyPlate")
@export var stack_vertical_spacing: float = 0.05

var placed_items: Array[KitchenItem] = []
var completed_item: KitchenItem = null

var _visual_instances: Array[Node3D] = []
var _plate_node: Node3D


func _ready() -> void:
	add_to_group(&"assembly_counters")
	if available_recipes.is_empty():
		available_recipes = [
			DEFAULT_TWO_BUNS_RECIPE,
			DEFAULT_CHEESEBURGER_RECIPE,
			DEFAULT_VEGGIE_BURGER_RECIPE,
			DEFAULT_VEGETABLEBURGER_UNCOOKED_RECIPE,
			DEFAULT_STEAK_DINNER_RECIPE,
			DEFAULT_STEAK_DINNER_BROILED_RECIPE,
			DEFAULT_STEW_BASE_RECIPE,
		]

	_init_plate_node()
	GameControl.order_started.connect(_on_order_started)


func _exit_tree() -> void:
	if GameControl.order_started.is_connected(_on_order_started):
		GameControl.order_started.disconnect(_on_order_started)
	_clear_visuals()


func _init_plate_node() -> void:
	if has_node(assembly_plate_path):
		_plate_node = get_node(assembly_plate_path) as Node3D
	else:
		var marker: Marker3D = Marker3D.new()
		marker.name = "AssemblyPlate"
		marker.position = Vector3(0.0, 0.28, -0.42)
		add_child(marker)
		_plate_node = marker


func _on_order_started(_order_id: int, _order: Dictionary) -> void:
	reset_counter()


func reset_counter() -> void:
	placed_items.clear()
	completed_item = null
	_clear_visuals()


func is_empty() -> bool:
	return placed_items.is_empty() and completed_item == null


func is_completed() -> bool:
	return completed_item != null


func is_in_progress() -> bool:
	return not placed_items.is_empty() and completed_item == null


func can_interact(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false

	var has_held: bool = player.has_method(&"has_held_item") and player.has_held_item()
	var held_item: KitchenItem = player.get_held_item() if has_held and player.has_method(&"get_held_item") else null

	if is_completed():
		# Can take completed dish only if hands are empty
		return not has_held

	if is_empty():
		# Can add starter ingredient if it matches any recipe
		return has_held and held_item != null and _can_start_any_recipe(held_item)

	if is_in_progress():
		if has_held and held_item != null:
			return _can_continue_any_recipe(placed_items, held_item)
		# If hands empty, player can retrieve the last placed ingredient
		return true

	return false


func get_interaction_prompt(player: Node) -> String:
	if player == null or not is_instance_valid(player):
		return prompt

	var has_held: bool = player.has_method(&"has_held_item") and player.has_held_item()
	var held_item: KitchenItem = player.get_held_item() if has_held and player.has_method(&"get_held_item") else null

	if is_completed():
		if not has_held:
			var dish_name: String = completed_item.display_name if completed_item != null else "DISH"
			return "TAKE %s" % dish_name.to_upper()
		return "HANDS FULL"

	if is_empty():
		if has_held and held_item != null:
			if _can_start_any_recipe(held_item):
				return "ADD %s" % held_item.display_name.to_upper()
			return "CANNOT COMBINE"
		return ""

	if is_in_progress():
		if has_held and held_item != null:
			if _can_continue_any_recipe(placed_items, held_item):
				return "ADD %s" % held_item.display_name.to_upper()
			return "CANNOT COMBINE"
		var top_item: KitchenItem = placed_items.back() if not placed_items.is_empty() else null
		if top_item != null:
			return "TAKE %s" % top_item.display_name.to_upper()
		return "CLEAR COUNTER"

	return ""


func interact(player: Node) -> void:
	if not can_interact(player):
		return

	var has_held: bool = player.has_method(&"has_held_item") and player.has_held_item()
	var held_item: KitchenItem = player.get_held_item() if has_held and player.has_method(&"get_held_item") else null

	if is_completed():
		if not has_held and player.has_method(&"set_held_item"):
			var dish: KitchenItem = completed_item
			reset_counter()
			player.set_held_item(dish)
		return

	if has_held and held_item != null:
		var can_add: bool = (is_empty() and _can_start_any_recipe(held_item)) or (is_in_progress() and _can_continue_any_recipe(placed_items, held_item))
		if can_add:
			if player.has_method(&"take_held_item"):
				player.take_held_item()
			add_ingredient(held_item)
		return

	if is_in_progress() and not has_held:
		var retrieved: KitchenItem = pop_ingredient()
		if retrieved != null and player.has_method(&"set_held_item"):
			player.set_held_item(retrieved)


func add_ingredient(item: KitchenItem) -> void:
	if item == null:
		return
	placed_items.append(item)
	_update_visuals()
	_check_recipes()


func pop_ingredient() -> KitchenItem:
	if placed_items.is_empty():
		return null
	var item: KitchenItem = placed_items.pop_back()
	_update_visuals()
	return item


func _check_recipes() -> void:
	for recipe in available_recipes:
		if recipe != null and recipe.matches(placed_items):
			completed_item = recipe.output_item
			_show_completed_visual(completed_item)
			return


func _can_start_any_recipe(item: KitchenItem) -> bool:
	if item == null:
		return false
	for recipe in available_recipes:
		if recipe != null and recipe.can_accept_next([], item):
			return true
	return false


func _can_continue_any_recipe(current: Array[KitchenItem], next_item: KitchenItem) -> bool:
	if next_item == null:
		return false
	for recipe in available_recipes:
		if recipe != null and recipe.can_accept_next(current, next_item):
			return true
	return false


func _clear_visuals() -> void:
	for v in _visual_instances:
		if is_instance_valid(v):
			v.queue_free()
	_visual_instances.clear()


func _update_visuals() -> void:
	_clear_visuals()
	if _plate_node == null:
		return

	if completed_item != null:
		_show_completed_visual(completed_item)
		return

	for i in placed_items.size():
		var item: KitchenItem = placed_items[i]
		if item == null or item.held_scene == null:
			continue
		var visual: Node3D = item.held_scene.instantiate() as Node3D
		if visual != null:
			_plate_node.add_child(visual)
			visual.position = Vector3(0.0, float(i) * stack_vertical_spacing, 0.0)
			_disable_collisions(visual)
			_visual_instances.append(visual)


func _show_completed_visual(dish: KitchenItem) -> void:
	_clear_visuals()
	if _plate_node == null or dish == null or dish.held_scene == null:
		return
	var visual: Node3D = dish.held_scene.instantiate() as Node3D
	if visual != null:
		_plate_node.add_child(visual)
		visual.position = Vector3.ZERO
		_disable_collisions(visual)
		_visual_instances.append(visual)


func _disable_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	for child in node.get_children():
		_disable_collisions(child)
