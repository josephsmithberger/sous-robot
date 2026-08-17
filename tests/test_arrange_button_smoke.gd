extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const MASTER_DIALOGUE: DialogueResource = preload("res://dialogue/master.dialogue")

func _ready() -> void:
	var game = GAME_SCENE.instantiate()
	add_child(game)
	GameControl.reset_session(0.0)
	GameControl.input_mode = GameControl.InputMode.KEYBOARD
	await get_tree().physics_frame
	await get_tree().process_frame

	var tabs: TabContainer = game.get_node("MarginContainer/HSplitContainer/TabContainer")
	var action_buttons = tabs.get_node("Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/DeckMargin/JoystickRow/Spacer/ActionButtons")
	
	# 1. Verify ResetButton has been removed
	var reset_button = action_buttons.get_node_or_null("ResetButton")
	assert(reset_button == null, "ResetButton must be removed from ActionButtons.")

	# 2. Verify ArrangeButton exists, is visible, and starts with proper prompt
	var arrange_button: Button = action_buttons.get_node_or_null("ArrangeButton")
	assert(arrange_button != null, "ArrangeButton must exist in ActionButtons.")
	assert(arrange_button.visible, "ArrangeButton must be visible.")
	assert(arrange_button.text == "ARRANGE (G)", "ArrangeButton text must start as 'ARRANGE (G)' on keyboard.")

	# End intro dialogue and give player first-person control
	GameControl._on_dialogue_ended(MASTER_DIALOGUE)
	await get_tree().process_frame
	assert(GameControl.camera_mode == GameControl.CameraMode.FIRST_PERSON, "Camera must be in FIRST_PERSON.")
	assert(arrange_button.visible, "ArrangeButton must remain visible in FIRST_PERSON mode.")

	# 3. Click ArrangeButton to enter Arrange Mode
	arrange_button.pressed.emit()
	await get_tree().process_frame
	assert(GameControl.is_arranging, "GameControl.is_arranging must be true after clicking ARRANGE.")
	assert(GameControl.camera_mode == GameControl.CameraMode.MARKER, "Camera mode must be MARKER (overhead view).")
	assert(GameControl.is_ui_mode, "UI mode must be enabled for arranging objects.")
	assert(arrange_button.visible, "ArrangeButton must remain visible in arrange mode.")
	assert(arrange_button.text == "CONFIRM (G)", "ArrangeButton text must change to 'CONFIRM (G)'.")

	# 4. Click ArrangeButton again (CONFIRM) to return to First Person Mode
	arrange_button.pressed.emit()
	await get_tree().process_frame
	assert(not GameControl.is_arranging, "GameControl.is_arranging must be false after confirming.")
	assert(GameControl.camera_mode == GameControl.CameraMode.FIRST_PERSON, "Camera mode must return to FIRST_PERSON.")
	assert(not GameControl.is_ui_mode, "UI mode must be disabled (returning to FPS controls).")
	assert(arrange_button.visible, "ArrangeButton must remain visible.")
	assert(arrange_button.text == "ARRANGE (G)", "ArrangeButton text must return to 'ARRANGE (G)'.")

	# 5. Verify touch mode strips the keyboard prompt
	GameControl.input_mode = GameControl.InputMode.TOUCH
	await get_tree().process_frame
	assert(arrange_button.text == "ARRANGE", "ArrangeButton text must be 'ARRANGE' on touch mode.")
	arrange_button.pressed.emit()
	await get_tree().process_frame
	assert(arrange_button.text == "CONFIRM", "ArrangeButton text must be 'CONFIRM' on touch mode when arranging.")
	arrange_button.pressed.emit()
	await get_tree().process_frame
	assert(arrange_button.text == "ARRANGE", "ArrangeButton text must return to 'ARRANGE' on touch mode.")

	print("ARRANGE_BUTTON_SMOKE_PASS")
	get_tree().quit(0)
