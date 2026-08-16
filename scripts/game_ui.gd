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
@onready var _arrange_button: Button = %ArrangeButton
@onready var _interact_button: Button = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/DeckMargin/JoystickRow/Spacer/ActionButtons/InteractButton
@onready var _interaction_fill: ProgressBar = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/DeckMargin/JoystickRow/Spacer/ActionButtons/InteractButton/HoldFill
@onready var _interaction_label: Label = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/ControlTray/ControlDeck/DeckMargin/JoystickRow/Spacer/ActionButtons/InteractButton/InteractionLabel
@onready var _money_label: Label = $MarginContainer/HSplitContainer/stats/money
@onready var _placement_tray: Control = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/PlacementTray
@onready var _placement_title: Label = %PlacementTitle
@onready var _rotate_button: Button = %RotateButton
@onready var _place_button: Button = %PlaceButton
@onready var _cancel_placement_button: Button = %CancelPlacementButton

var _previous_dialogue_host_resolver: Callable
var _interaction_tween: Tween
var _dialogue_slot_is_open := false
var _control_deck_is_open := false
var _interaction_prompt := "INTERACT"
var _interaction_is_hold := false
var _process_picker_panel: PanelContainer
var _process_picker_options_box: VBoxContainer
var _process_picker_cancel_button: Button
var _process_picker_target: Node


func _ready() -> void:
	_prepare_panel(_dialogue_slot, TRAY_HEIGHT)
	_prepare_panel(_control_deck, TRAY_HEIGHT)
	_create_process_picker()

	_tabs.tab_changed.connect(_on_tab_changed)
	GameControl.controllability_changed.connect(_on_controllability_changed)
	GameControl.input_mode_changed.connect(_on_input_mode_changed)
	GameControl.dialogue_activity_changed.connect(_on_dialogue_activity_changed)
	GameControl.camera_mode_changed.connect(_on_camera_mode_changed)
	GameControl.interact_available_changed.connect(_on_interact_available_changed)
	GameControl.interaction_prompt_changed.connect(_on_interaction_prompt_changed)
	GameControl.interaction_progress_changed.connect(_on_interaction_progress_changed)
	GameControl.process_picker_requested.connect(_on_process_picker_requested)
	GameControl.process_picker_selected.connect(_on_process_picker_selected)
	GameControl.process_picker_cancelled.connect(_on_process_picker_cancelled)
	GameControl.process_picker_refreshed.connect(_on_process_picker_refreshed)
	GameControl.money_changed.connect(_on_money_changed)
	GameControl.placement_started.connect(_on_placement_started)
	GameControl.placement_completed.connect(_on_placement_completed)
	GameControl.placement_cancelled.connect(_on_placement_cancelled)
	GameControl.arrange_mode_changed.connect(_on_arrange_mode_changed)
	GameControl.tab_change_requested.connect(_on_tab_change_requested)
	GameControl.reset_session()
	_on_interact_available_changed(GameControl.can_interact)
	_on_interaction_prompt_changed(GameControl.interaction_prompt, GameControl.interaction_hold_duration)
	_hand_off_button.pressed.connect(GameControl.toggle_camera_mode)
	_arrange_button.pressed.connect(GameControl.toggle_arrange_mode)
	_interact_button.button_down.connect(GameControl.request_interaction)
	_interact_button.button_up.connect(GameControl.cancel_interaction)
	_rotate_button.pressed.connect(_on_rotate_button_pressed)
	_place_button.pressed.connect(_on_place_button_pressed)
	_cancel_placement_button.pressed.connect(GameControl.cancel_placement)
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


func _create_process_picker() -> void:
	var interaction_stage := _game_viewport_container.get_parent() as Control
	if interaction_stage == null:
		return
	_process_picker_panel = PanelContainer.new()
	_process_picker_panel.name = "ProcessPicker"
	_process_picker_panel.z_index = 20
	_process_picker_panel.visible = false
	_process_picker_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_process_picker_panel.set_anchors_preset(Control.PRESET_CENTER)
	_process_picker_panel.position = Vector2(-190.0, -150.0)
	_process_picker_panel.size = Vector2(380.0, 300.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.06, 0.05, 0.97)
	panel_style.border_color = Color(1.0, 0.78, 0.17, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 18.0
	panel_style.content_margin_right = 18.0
	panel_style.content_margin_top = 14.0
	panel_style.content_margin_bottom = 14.0
	_process_picker_panel.add_theme_stylebox_override("panel", panel_style)
	interaction_stage.add_child(_process_picker_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 2)
	margin.add_theme_constant_override("margin_right", 2)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	_process_picker_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var title := Label.new()
	title.name = "Title"
	title.text = "CHOOSE PREP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.17))
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var hint := Label.new()
	hint.text = "Select a preparation"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.7))
	column.add_child(hint)
	_process_picker_options_box = VBoxContainer.new()
	_process_picker_options_box.name = "Options"
	_process_picker_options_box.add_theme_constant_override("separation", 6)
	column.add_child(_process_picker_options_box)
	_process_picker_cancel_button = Button.new()
	_process_picker_cancel_button.name = "Cancel"
	_process_picker_cancel_button.text = "CANCEL (ESC)"
	_process_picker_cancel_button.custom_minimum_size = Vector2(0, 42)
	_process_picker_cancel_button.focus_mode = Control.FOCUS_ALL
	_process_picker_cancel_button.pressed.connect(GameControl.cancel_process_picker)
	column.add_child(_process_picker_cancel_button)


func _on_process_picker_requested(target: Node, options: Array[ItemProcessRecipe]) -> void:
	_process_picker_target = target
	if _process_picker_panel == null or _process_picker_options_box == null:
		return
	for child in _process_picker_options_box.get_children():
		child.free()
	for recipe in options:
		if recipe == null:
			continue
		var option := Button.new()
		option.custom_minimum_size = Vector2(0, 48)
		option.focus_mode = Control.FOCUS_ALL
		option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		option.text = "%s  ·  %.1fs" % [recipe.get_output_name(), recipe.hold_duration]
		option.tooltip_text = recipe.get_action_label()
		option.pressed.connect(_on_process_option_pressed.bind(recipe))
		_process_picker_options_box.add_child(option)
	_process_picker_panel.visible = true
		# Focus makes the same overlay usable without a mouse or touch screen.
	if _process_picker_options_box.get_child_count() > 0:
		(_process_picker_options_box.get_child(0) as Button).grab_focus.call_deferred()


func _on_process_option_pressed(recipe: ItemProcessRecipe) -> void:
	GameControl.select_process_recipe(recipe)


func _on_process_picker_selected(_target: Node, _recipe: ItemProcessRecipe) -> void:
	_hide_process_picker()


func _on_process_picker_cancelled() -> void:
	_hide_process_picker()


func _on_process_picker_refreshed(target: Node, options: Array[ItemProcessRecipe]) -> void:
	if GameControl.is_process_picker_open():
		_on_process_picker_requested(target, options)


func _hide_process_picker() -> void:
	_process_picker_target = null
	if _process_picker_panel != null:
		_process_picker_panel.visible = false


func _on_game_viewport_gui_input(event: InputEvent) -> void:
	if GameControl.is_placing or GameControl.is_arranging:
		return
	if TouchUI.is_primary_press(event) and GameControl.camera_mode != GameControl.CameraMode.FIRST_PERSON:
		GameControl.give_player_control()


func _on_virtual_joystick_touch_started() -> void:
	if GameControl.is_placing or GameControl.is_arranging:
		return
	GameControl.give_player_control()


func _on_tab_changed(tab_index: int) -> void:
	GameControl.current_tab = tab_index
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
	var is_first_person := mode == GameControl.CameraMode.FIRST_PERSON
	_hand_off_button.text = "HAND OFF" if is_first_person else "TAKE CONTROL"
	_arrange_button.visible = not is_first_person
	_arrange_button.text = "DONE" if GameControl.is_arranging else "ARRANGE"


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


func _on_placement_started(item_id: StringName) -> void:
	_placement_tray.visible = true
	_placement_title.text = "PLACING: %s" % str(item_id).capitalize()
	_update_interaction_ui()


func _on_placement_completed(_item_id: StringName, _pos: Vector3, _rot_y: float) -> void:
	_placement_tray.visible = false
	_update_interaction_ui()


func _on_placement_cancelled() -> void:
	_placement_tray.visible = false
	_update_interaction_ui()


func _on_arrange_mode_changed(is_arranging: bool) -> void:
	_arrange_button.text = "DONE" if is_arranging else "ARRANGE"
	if is_arranging:
		_hand_off_button.text = "TAKE CONTROL"
	_update_interaction_ui()


func _on_tab_change_requested(tab_index: int) -> void:
	_tabs.current_tab = tab_index


func _on_rotate_button_pressed() -> void:
	var pm := _get_placement_manager()
	if pm != null:
		pm.rotate_ghost()


func _on_place_button_pressed() -> void:
	var pm := _get_placement_manager()
	if pm != null:
		pm.confirm_placement()


func _get_placement_manager() -> PlacementManager:
	var kitchen_node := $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/SubViewportContainer/SubViewport/kitchen
	if kitchen_node != null:
		return kitchen_node.get_node_or_null("PlacementManager") as PlacementManager
	return null
