class_name ItemProcessor
extends InteractionArea
## Turns one assigned KitchenItem into another after the configured hold time.
##
## New appliances should populate `recipes`. The legacy input/output exports are
## intentionally retained so existing scenes continue to run while they migrate.

@export var recipes: Array[ItemProcessRecipe] = []

# Legacy one-route scene properties. They are converted to a transient recipe by
# get_process_recipes() when `recipes` is empty.
@export var input_item: KitchenItem
@export var output_item: KitchenItem
@export var action_verb := "PROCESS"

var _selected_recipe: ItemProcessRecipe


func _ready() -> void:
	add_to_group(&"item_processors")
	if not GameControl.process_picker_selected.is_connected(_on_process_picker_selected):
		GameControl.process_picker_selected.connect(_on_process_picker_selected)
	if not GameControl.process_picker_cancelled.is_connected(_on_process_picker_cancelled):
		GameControl.process_picker_cancelled.connect(_on_process_picker_cancelled)
	if not GameControl.held_item_changed.is_connected(_on_held_item_changed):
		GameControl.held_item_changed.connect(_on_held_item_changed)


func get_process_recipes() -> Array[ItemProcessRecipe]:
	var valid: Array[ItemProcessRecipe] = []
	for recipe in recipes:
		if recipe != null and recipe.is_valid():
			valid.append(recipe)
	if not valid.is_empty():
		return valid
	if input_item == null or output_item == null:
		return valid
	var legacy := ItemProcessRecipe.new()
	legacy.recipe_id = StringName("legacy_%s_to_%s" % [input_item.item_id, output_item.item_id])
	legacy.input_item = input_item
	legacy.output_item = output_item
	legacy.action_verb = action_verb
	legacy.hold_duration = hold_duration
	valid.append(legacy)
	return valid


func get_matching_recipes(player: Node) -> Array[ItemProcessRecipe]:
	var matches: Array[ItemProcessRecipe] = []
	if player == null or not player.has_method(&"get_held_item"):
		return matches
	var held := player.get_held_item() as KitchenItem
	if held == null:
		return matches
	for recipe in get_process_recipes():
		if recipe.matches_item(held.item_id):
			matches.append(recipe)
	return matches


func get_selected_recipe() -> ItemProcessRecipe:
	return _selected_recipe


func can_interact(player: Node) -> bool:
	if GameControl.is_process_picker_open() and GameControl.process_picker_target != self:
		return false
	var matches := get_matching_recipes(player)
	if matches.is_empty():
		_clear_selection()
		return false
	if _selected_recipe != null:
		if not matches.has(_selected_recipe):
			_clear_selection()
			return false
	return true


func get_interaction_prompt(player: Node) -> String:
	var matches := get_matching_recipes(player)
	if matches.is_empty():
		return ""
	var recipe := _get_active_recipe(matches)
	if recipe != null:
		return "HOLD TO %s" % recipe.get_action_label() if recipe.hold_duration > 0.0 else recipe.get_action_label()
	if matches.size() > 1:
		return "CHOOSE PREP"
	return matches[0].get_action_label()


func get_interaction_hold_duration(player: Node) -> float:
	var matches := get_matching_recipes(player)
	var recipe := _get_active_recipe(matches)
	return recipe.hold_duration if recipe != null else 0.0


func interact(player: Node) -> void:
	var matches := get_matching_recipes(player)
	if matches.is_empty():
		_clear_selection()
		return

	var recipe := _get_active_recipe(matches)
	if recipe == null:
		if matches.size() > 1:
			GameControl.request_process_picker(self, matches)
		else:
			_apply_recipe(player, matches[0])
		return

	_apply_recipe(player, recipe)


func clear_process_selection() -> void:
	_clear_selection()


func _get_active_recipe(matches: Array[ItemProcessRecipe]) -> ItemProcessRecipe:
	if _selected_recipe != null:
		if matches.has(_selected_recipe):
			return _selected_recipe
		_clear_selection()
	return matches[0] if matches.size() == 1 else null


func _apply_recipe(player: Node, recipe: ItemProcessRecipe) -> void:
	if player == null or not player.has_method(&"get_held_item") or player.get_held_item() == null:
		_clear_selection()
		return
	if recipe == null or not recipe.is_valid() or not recipe.matches_item(player.get_held_item().item_id):
		_clear_selection()
		return
	_clear_selection()
	if player.has_method(&"set_held_item"):
		player.set_held_item(recipe.output_item)


func _on_process_picker_selected(target: Node, recipe: ItemProcessRecipe) -> void:
	if target != self:
		return
	var available := get_process_recipes()
	if not available.has(recipe):
		_clear_selection()
		return
	_selected_recipe = recipe


func _on_process_picker_cancelled() -> void:
	_clear_selection()


func _on_held_item_changed(_item: KitchenItem) -> void:
	_clear_selection()


func _clear_selection() -> void:
	_selected_recipe = null


func _exit_tree() -> void:
	if GameControl.process_picker_selected.is_connected(_on_process_picker_selected):
		GameControl.process_picker_selected.disconnect(_on_process_picker_selected)
	if GameControl.process_picker_cancelled.is_connected(_on_process_picker_cancelled):
		GameControl.process_picker_cancelled.disconnect(_on_process_picker_cancelled)
	if GameControl.held_item_changed.is_connected(_on_held_item_changed):
		GameControl.held_item_changed.disconnect(_on_held_item_changed)
