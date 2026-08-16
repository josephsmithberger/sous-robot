extends Node

var _player: _MockPlayer
var _processor: ItemProcessor
var _raw: KitchenItem
var _slice: KitchenItem
var _dice: KitchenItem


func _ready() -> void:
	_raw = _item(&"tomato", "Tomato")
	_slice = _item(&"tomato_slice", "Tomato Slice")
	_dice = _item(&"tomato_slices", "Diced Tomato")
	_player = _MockPlayer.new()
	add_child(_player)
	_processor = ItemProcessor.new()
	_processor.name = "TomatoBoard"
	_processor.recipes = [_recipe(&"slice", _raw, _slice, "SLICE TOMATO", 1.0), _recipe(&"dice", _raw, _dice, "DICE TOMATO", 1.5)]
	add_child(_processor)
	_player.set_held_item(_raw)

	assert(_processor.can_interact(_player), "matching input should interact")
	assert(_processor.get_interaction_prompt(_player) == "CHOOSE PREP", "ambiguous input should request choice")
	assert(is_zero_approx(_processor.get_interaction_hold_duration(_player)), "picker should not hold before selection")
	_processor.interact(_player)
	assert(GameControl.is_process_picker_open(), "processor did not open picker")
	assert(GameControl.process_picker_target == _processor, "picker target mismatch")
	assert(GameControl.process_picker_options.size() == 2, "picker option count mismatch")

	var selected := GameControl.process_picker_options[1]
	assert(GameControl.select_process_recipe(selected), "valid picker selection rejected")
	assert(not GameControl.is_process_picker_open(), "picker remained open after selection")
	assert(_processor.get_selected_recipe() == selected, "processor did not retain selection")
	assert(_processor.get_interaction_prompt(_player) == "HOLD TO DICE TOMATO")
	assert(is_equal_approx(_processor.get_interaction_hold_duration(_player), 1.5))
	_processor.interact(_player)
	assert(_player.is_holding(&"tomato_slices"), "selected route produced wrong item")
	assert(_processor.get_selected_recipe() == null, "selection was not cleared on completion")

	_player.set_held_item(_raw)
	_processor.interact(_player)
	assert(GameControl.is_process_picker_open())
	_player.set_held_item(_slice)
	assert(not GameControl.is_process_picker_open(), "cancel did not close picker")
	assert(_processor.get_selected_recipe() == null, "cancel retained selection")

	print("ITEM_PROCESSOR_PICKER_SMOKE_PASS")
	await get_tree().process_frame
	get_tree().quit(0)


func _item(id: StringName, item_name: String) -> KitchenItem:
	var result := KitchenItem.new()
	result.item_id = id
	result.display_name = item_name
	return result


func _recipe(id: StringName, input: KitchenItem, output: KitchenItem, verb: String, duration: float) -> ItemProcessRecipe:
	var result := ItemProcessRecipe.new()
	result.recipe_id = id
	result.input_item = input
	result.output_item = output
	result.action_verb = verb
	result.hold_duration = duration
	return result


class _MockPlayer extends Node:
	var held: KitchenItem

	func get_held_item() -> KitchenItem:
		return held

	func is_holding(item_id: StringName) -> bool:
		return held != null and held.item_id == item_id

	func set_held_item(item: KitchenItem) -> void:
		held = item
		GameControl.held_item_changed.emit(item)
