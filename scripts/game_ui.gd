extends Control

const MASTER_DIALOGUE: DialogueResource = preload("res://dialogue/master.dialogue")
const KITCHEN_TAB := 0
const TRAY_HEIGHT := 132.0
const SLIDE_DURATION := 0.28

@onready var _tabs: TabContainer = $MarginContainer/HSplitContainer/TabContainer
@onready var _game_viewport_container: SubViewportContainer = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/SubViewportContainer
@onready var _dialogue_slot: Control = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/DialogueTray/DialogueSlot
@onready var _control_deck: Control = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck
@onready var _joystick_row: Control = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/DeckMargin/JoystickRow
@onready var _keyboard_hint: Control = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/KeyboardHint
@onready var _move_joystick: Control = %MoveJoystick
@onready var _look_joystick: Control = %LookJoystick
@onready var _hand_off_button: Button = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/DeckMargin/JoystickRow/Spacer/ActionButtons/HandOffButton
@onready var _interact_button: Button = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/DeckMargin/JoystickRow/Spacer/ActionButtons/InteractButton
@onready var _interaction_fill: ProgressBar = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/DeckMargin/JoystickRow/Spacer/ActionButtons/InteractButton/HoldFill
@onready var _interaction_label: Label = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/DeckMargin/JoystickRow/Spacer/ActionButtons/InteractButton/InteractionLabel
@onready var _money_label: Label = $MarginContainer/HSplitContainer/stats/money

var _previous_dialogue_host_resolver: Callable
var _interaction_tween: Tween
var _dialogue_slot_is_open := false
var _control_deck_is_open := false
var _interaction_prompt := "INTERACT"
var _interaction_is_hold := false


func _ready() -> void:
	_prepare_panel(_dialogue_slot, TRAY_HEIGHT)
	_prepare_panel(_control_deck, TRAY_HEIGHT)

	_tabs.tab_changed.connect(_on_tab_changed)
	GameControl.controllability_changed.connect(_on_controllability_changed)
	GameControl.input_mode_changed.connect(_on_input_mode_changed)
	GameControl.dialogue_activity_changed.connect(_on_dialogue_activity_changed)
	GameControl.camera_mode_changed.connect(_on_camera_mode_changed)
	GameControl.interact_available_changed.connect(_on_interact_available_changed)
	GameControl.interaction_prompt_changed.connect(_on_interaction_prompt_changed)
	GameControl.interaction_progress_changed.connect(_on_interaction_progress_changed)
	GameControl.money_changed.connect(_on_money_changed)
	GameControl.reset_session()
	_on_interact_available_changed(GameControl.can_interact)
	_on_interaction_prompt_changed(GameControl.interaction_prompt, GameControl.interaction_hold_duration)
	_hand_off_button.pressed.connect(GameControl.toggle_camera_mode)
	_interact_button.button_down.connect(GameControl.request_interaction)
	_interact_button.button_up.connect(GameControl.cancel_interaction)
	_move_joystick.touch_started.connect(_on_virtual_joystick_touch_started)
	_look_joystick.touch_started.connect(_on_virtual_joystick_touch_started)
	_game_viewport_container.gui_input.connect(_on_game_viewport_gui_input)

	_previous_dialogue_host_resolver = DialogueManager.get_current_scene
	DialogueManager.get_current_scene = _get_dialogue_host

	_on_input_mode_changed(GameControl.input_mode)
	_on_camera_mode_changed(GameControl.camera_mode)
	_on_tab_changed(_tabs.current_tab)

	start_dialogue(MASTER_DIALOGUE, "intro")


## Helper method to launch dialogue in the interaction dialogue tray.
func start_dialogue(resource: DialogueResource, title: String = "") -> Node:
	return DialogueManager.show_dialogue_balloon(resource, title)


func _on_money_changed(balance: float, delta: float, reason: String) -> void:
	_money_label.text = "$%.2f" % balance
	if is_zero_approx(delta):
		return
	_money_label.modulate = Color("55a630") if delta > 0.0 else Color("d62318")
	var tween := create_tween()
	tween.tween_property(_money_label, ^"modulate", Color.WHITE, 0.45)
	if not reason.is_empty():
		_money_label.tooltip_text = reason


func _process(_delta: float) -> void:
	if _move_joystick != null and _look_joystick != null:
		GameControl.set_virtual_input(_move_joystick.output, _look_joystick.output)


func _exit_tree() -> void:
	DialogueManager.get_current_scene = _previous_dialogue_host_resolver
	GameControl.set_virtual_input(Vector2.ZERO, Vector2.ZERO)
	GameControl.set_controllable(false)


func _on_game_viewport_gui_input(event: InputEvent) -> void:
	if TouchUI.is_primary_press(event):
		GameControl.give_player_control()



func _on_virtual_joystick_touch_started() -> void:
	GameControl.give_player_control()


func _on_tab_changed(tab_index: int) -> void:
	var kitchen_is_active := tab_index == KITCHEN_TAB
	GameControl.set_controllable(kitchen_is_active)
	_update_interaction_ui()


func _on_controllability_changed(_is_controllable: bool) -> void:
	_update_interaction_ui()


func _on_dialogue_activity_changed(_is_active: bool) -> void:
	_update_interaction_ui()


func _update_interaction_ui() -> void:
	var kitchen_is_active := _tabs.current_tab == KITCHEN_TAB
	var show_dialogue := kitchen_is_active and GameControl.is_dialogue_active()
	var show_controls := kitchen_is_active and GameControl.is_controllable
	_animate_interaction_ui(show_dialogue, show_controls)


func _prepare_panel(panel: Control, hidden_y: float) -> void:
	panel.position.y = hidden_y
	panel.modulate.a = 0.0
	panel.visible = false


func _animate_interaction_ui(show_dialogue: bool, show_controls: bool) -> void:
	if show_dialogue == _dialogue_slot_is_open and show_controls == _control_deck_is_open:
		return

	_dialogue_slot_is_open = show_dialogue
	_control_deck_is_open = show_controls

	if is_instance_valid(_interaction_tween):
		_interaction_tween.kill()

	if show_dialogue:
		_dialogue_slot.visible = true
	if show_controls:
		_control_deck.visible = true

	_interaction_tween = create_tween()
	_interaction_tween.set_parallel(true)
	_interaction_tween.set_trans(Tween.TRANS_CUBIC)
	_interaction_tween.set_ease(Tween.EASE_IN_OUT)
	_interaction_tween.tween_property(
		_dialogue_slot,
		^"position:y",
		0.0 if show_dialogue else TRAY_HEIGHT,
		SLIDE_DURATION
	)
	_interaction_tween.tween_property(
		_dialogue_slot,
		^"modulate:a",
		1.0 if show_dialogue else 0.0,
		SLIDE_DURATION * 0.75
	)
	_interaction_tween.tween_property(
		_control_deck,
		^"position:y",
		0.0 if show_controls else TRAY_HEIGHT,
		SLIDE_DURATION
	)
	_interaction_tween.tween_property(
		_control_deck,
		^"modulate:a",
		1.0 if show_controls else 0.0,
		SLIDE_DURATION * 0.75
	)
	_interaction_tween.finished.connect(_on_interaction_tween_finished)


func _on_interaction_tween_finished() -> void:
	if not _dialogue_slot_is_open:
		_dialogue_slot.visible = false
	if not _control_deck_is_open:
		_control_deck.visible = false
	_interaction_tween = null


func _get_dialogue_host() -> Node:
	return _dialogue_slot


func _on_camera_mode_changed(mode: GameControl.CameraMode) -> void:
	_hand_off_button.text = "HAND OFF" if mode == GameControl.CameraMode.FIRST_PERSON else "TAKE CONTROL"


func _on_input_mode_changed(_input_mode: GameControl.InputMode) -> void:
	var using_touch := GameControl.is_using_touch()
	_joystick_row.visible = true
	_move_joystick.visible = using_touch
	_look_joystick.visible = using_touch
	_keyboard_hint.visible = not using_touch


func _on_interact_available_changed(is_available: bool) -> void:
	_interact_button.visible = is_available


func _on_interaction_prompt_changed(prompt: String, hold_duration: float) -> void:
	_interaction_prompt = prompt if not prompt.is_empty() else "INTERACT"
	_interaction_is_hold = hold_duration > 0.0
	_interact_button.text = _interaction_prompt
	_interaction_label.text = _interaction_prompt
	_set_interaction_fill(0.0)


func _on_interaction_progress_changed(progress: float) -> void:
	_set_interaction_fill(progress if _interaction_is_hold else 0.0)


func _set_interaction_fill(progress: float) -> void:
	var fill_amount := clampf(progress, 0.0, 1.0)
	_interaction_fill.value = fill_amount
	_interaction_fill.visible = _interaction_is_hold and fill_amount > 0.0
