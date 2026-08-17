extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const MASTER_DIALOGUE: DialogueResource = preload("res://dialogue/master.dialogue")
const BREAD: KitchenItem = preload("res://resources/items/bread.tres")
const BUN: KitchenItem = preload("res://resources/items/bun.tres")


func _ready() -> void:
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var tutorial := game.find_child("TutorialOverlay", true, false) as Control
	assert(tutorial != null, "Game must create the tutorial overlay.")
	assert(not tutorial.visible, "Tutorial must stay hidden during the intro dialogue.")

	GameControl._on_dialogue_ended(MASTER_DIALOGUE)
	await get_tree().process_frame
	assert(tutorial.visible, "Tutorial must appear when the intro dialogue ends.")
	assert(_tutorial_heading(tutorial).contains("1/4"), "Tutorial must begin at movement step 1/4.")
	var controls_arrow := tutorial.find_child("TargetArrow", true, false) as Label
	assert(controls_arrow != null and not controls_arrow.visible, "Controls must not show a misaligned tutorial arrow.")

	tutorial.set("_movement_time", 0.5)
	tutorial.call("_process", 0.01)
	assert(_tutorial_heading(tutorial).contains("2/4"), "Movement must advance to take-order step 2/4.")

	var order := {
		"items": {&"bread": 1, &"bun": 1},
		"fulfilled": {&"bread": 0, &"bun": 0},
		"item_names": {&"bread": "Bread", &"bun": "Bun"},
		"base_reward": 3.0,
		"tip": 1.0,
	}
	GameControl.begin_order(1, order)
	GameControl.order_started.emit(1, order)
	assert(_tutorial_heading(tutorial).contains("3/4"), "Starting an order must advance to ingredient step 3/4.")

	GameControl.held_item_changed.emit(BREAD)
	assert(_tutorial_heading(tutorial).contains("3/4"), "Bread must advance to the cutting-board prep instruction.")

	GameControl.held_item_changed.emit(BUN)
	assert(_tutorial_heading(tutorial).contains("4/4"), "The prepared bun must advance to delivery step 4/4.")

	GameControl.order_completed.emit(1, 4.0, 1.0)
	assert(_tutorial_heading(tutorial) == "TRAINING COMPLETE", "Completing the order must show the progression summary.")
	var dismiss := tutorial.find_child("DismissButton", true, false) as Button
	assert(dismiss != null and dismiss.text == "GOT IT", "Final tutorial action must be a GOT IT button.")
	dismiss.pressed.emit()
	await get_tree().process_frame
	assert(not tutorial.visible, "GOT IT must dismiss the tutorial.")
	assert(GameControl.is_dialogue_active(), "The first story beat must begin after the tutorial is acknowledged.")

	print("TUTORIAL_OVERLAY_SMOKE_PASS")
	get_tree().quit(0)


func _tutorial_heading(tutorial: Control) -> String:
	for label in tutorial.find_children("", "Label", true, false):
		if label is Label and (label as Label).text.begins_with("TRAINING"):
			return (label as Label).text
	return ""
