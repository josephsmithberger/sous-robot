extends Control

const MASTER_DIALOGUE: DialogueResource = preload("res://dialogue/master.dialogue")
const FONT_LILITA: FontFile = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const TUTORIAL_OVERLAY_SCRIPT: Script = preload("res://scripts/tutorial_overlay.gd")
const KITCHEN_TAB := 0
const TRAY_HEIGHT := 132.0
const SLIDE_DURATION := 0.28

@onready var _tabs: TabContainer = $MarginContainer/HSplitContainer/TabContainer
@onready var _game_viewport_container: SubViewportContainer = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/SubViewportContainer
@onready var _kitchen: Node3D = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/InteractionStage/SubViewportContainer/SubViewport/kitchen
@onready var _orders_panel: Control = $MarginContainer/HSplitContainer/stats/orders
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

var _alert_banner_panel: PanelContainer
var _alert_banner_label: Label
var _alert_queue: Array[Dictionary] = []
var _is_showing_alert := false
var _alert_tween: Tween

# Story beats are queued so a milestone never interrupts an order or another
# Señor Food conversation. A title is marked seen as soon as it is queued.
var _story_queue: Array[StringName] = []
var _seen_story_titles: Dictionary = {}
var _tutorial_overlay: Control
var _tutorial_finished := false

func _ready() -> void:
	_prepare_panel(_dialogue_slot, TRAY_HEIGHT)
	_prepare_panel(_control_deck, TRAY_HEIGHT)
	_create_process_picker()
	_create_alert_banner()
	_create_tutorial()

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
	GameControl.bot_task_completed.connect(_on_bot_task_completed)
	GameControl.bots_assigned.connect(_on_story_bots_assigned)
	GameControl.placement_started.connect(_on_placement_started)
	GameControl.placement_completed.connect(_on_placement_completed)
	GameControl.placement_cancelled.connect(_on_placement_cancelled)
	GameControl.arrange_mode_changed.connect(_on_arrange_mode_changed)
	GameControl.tab_change_requested.connect(_on_tab_change_requested)
	if not RecipeTracker.automation_available.is_connected(_on_recipe_automation_available):
		RecipeTracker.automation_available.connect(_on_recipe_automation_available)
	if not RecipeTracker.recipe_made.is_connected(_on_story_recipe_made):
		RecipeTracker.recipe_made.connect(_on_story_recipe_made)
	if not RecipeTracker.tracker_reset.is_connected(_on_story_tracker_reset):
		RecipeTracker.tracker_reset.connect(_on_story_tracker_reset)
	GameControl.reset_session()
	_on_interact_available_changed(GameControl.can_interact)
	_on_interaction_prompt_changed(GameControl.interaction_prompt, GameControl.interaction_hold_duration)
	_hand_off_button.pressed.connect(_on_hand_off_button_pressed)
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
	if _tutorial_overlay != null:
		_tutorial_overlay.call("arm")

	if SFX != null:
		SFX.play_bgm(SFX.BGM_GAME_JAZZ, 1.2, -16.0)


## Helper method to launch dialogue in the interaction dialogue tray.
func start_dialogue(resource: DialogueResource, title: String = "") -> Node:
	return DialogueManager.show_dialogue_balloon(resource, title)


func _process(_delta: float) -> void:
	if _move_joystick != null and _look_joystick != null:
		GameControl.set_virtual_input(_move_joystick.output, _look_joystick.output)


func _exit_tree() -> void:
	if SFX != null:
		SFX.stop_bgm(0.8)
	DialogueManager.get_current_scene = _previous_dialogue_host_resolver
	GameControl.set_virtual_input(Vector2.ZERO, Vector2.ZERO)
	GameControl.set_controllable(false)
	if RecipeTracker.automation_available.is_connected(_on_recipe_automation_available):
		RecipeTracker.automation_available.disconnect(_on_recipe_automation_available)
	if RecipeTracker.recipe_made.is_connected(_on_story_recipe_made):
		RecipeTracker.recipe_made.disconnect(_on_story_recipe_made)
	if RecipeTracker.tracker_reset.is_connected(_on_story_tracker_reset):
		RecipeTracker.tracker_reset.disconnect(_on_story_tracker_reset)
	if GameControl.bot_task_completed.is_connected(_on_bot_task_completed):
		GameControl.bot_task_completed.disconnect(_on_bot_task_completed)
	if is_instance_valid(_alert_tween):
		_alert_tween.kill()


func _create_tutorial() -> void:
	var interaction_stage := _game_viewport_container.get_parent() as Control
	if interaction_stage == null:
		return
	_tutorial_overlay = TUTORIAL_OVERLAY_SCRIPT.new() as Control
	_tutorial_overlay.name = "TutorialOverlay"
	_tutorial_overlay.call(
		"configure",
		_game_viewport_container,
		_kitchen,
		_move_joystick,
		_keyboard_hint,
		_tabs,
		_orders_panel
	)
	interaction_stage.add_child(_tutorial_overlay)
	_tutorial_overlay.connect(&"tutorial_finished", _on_tutorial_finished)


func _on_tutorial_finished() -> void:
	if _tutorial_finished:
		return
	_tutorial_finished = true
	call_deferred("_try_start_next_story_dialogue")


func _create_alert_banner() -> void:
	var interaction_stage := _game_viewport_container.get_parent() as Control
	if interaction_stage == null:
		return

	_alert_banner_panel = PanelContainer.new()
	_alert_banner_panel.name = "AlertBanner"
	_alert_banner_panel.z_index = 25
	_alert_banner_panel.visible = false
	_alert_banner_panel.modulate.a = 0.0
	_alert_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alert_banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_alert_banner_panel.position = Vector2(-220.0, -60.0)
	_alert_banner_panel.custom_minimum_size = Vector2(440.0, 42.0)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.06, 0.05, 0.95)
	panel_style.border_color = Color(1.0, 0.78, 0.17, 0.95) # Diner Gold
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 18.0
	panel_style.content_margin_right = 18.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_bottom = 8.0
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	panel_style.shadow_size = 6
	panel_style.shadow_offset = Vector2(0, 2)
	_alert_banner_panel.add_theme_stylebox_override("panel", panel_style)
	interaction_stage.add_child(_alert_banner_panel)

	_alert_banner_label = Label.new()
	_alert_banner_label.name = "AlertLabel"
	_alert_banner_label.text = ""
	_alert_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_alert_banner_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alert_banner_label.add_theme_font_override("font", FONT_LILITA)
	_alert_banner_label.add_theme_font_size_override("font_size", 17)
	_alert_banner_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.17, 1.0))
	_alert_banner_panel.add_child(_alert_banner_label)


func _resolve_alert_message(recipe_id: StringName, recipe_name: String, message: String) -> String:
	if not message.is_empty():
		return message
	if not recipe_name.is_empty():
		return "new automation available: %s" % recipe_name
	if not recipe_id.is_empty():
		return "new automation available: %s" % str(recipe_id)
	return ""


func _on_bot_task_completed(
	order_id: int,
	item_id: StringName,
	item_name: String,
	succeeded: bool,
	detail: String
) -> void:
	var display_name := item_name if not item_name.is_empty() else str(item_id).capitalize()
	var message := "BOT COMPLETED %s · ORDER #%02d" % [display_name.to_upper(), order_id]
	if not succeeded:
		message = "BOT COULD NOT MAKE %s" % display_name.to_upper()
		if not detail.is_empty():
			message += " · %s" % detail
	_on_automation_available(item_id, display_name, message)


func _on_recipe_automation_available(recipe_id: StringName, recipe_name: String, message: String) -> void:
	_on_automation_available(recipe_id, recipe_name, message)
	_queue_story_dialogue(&"story_first_automation")


func _on_story_bots_assigned(_order_id: int, allocations: Dictionary) -> void:
	if not allocations.is_empty():
		_queue_story_dialogue(&"story_first_automation")


func _on_story_recipe_made(recipe_id: StringName, _item: KitchenItem, total_count: int) -> void:
	if recipe_id == &"veggie_burger" and total_count == 1:
		_queue_story_dialogue(&"story_final_veggie_burger")


func _on_story_tracker_reset() -> void:
	_story_queue.clear()
	_seen_story_titles.clear()


func _queue_story_dialogue(title: StringName) -> void:
	if title.is_empty() or _seen_story_titles.has(title):
		return
	_seen_story_titles[title] = true
	_story_queue.append(title)
	# Signals can arrive from cooking, store, and order-completion callbacks.
	# Defer the launch so their state changes finish before dialogue takes control.
	call_deferred(&"_try_start_next_story_dialogue")


func _try_start_next_story_dialogue() -> void:
	if not _tutorial_finished:
		return
	if _story_queue.is_empty() or GameControl.is_dialogue_active():
		return
	if GameControl.is_placing or GameControl.is_arranging:
		return
	if GameControl.is_process_picker_open() or GameControl.is_bot_dispatch_open():
		return
	var title: StringName = _story_queue.pop_front()
	start_dialogue(MASTER_DIALOGUE, str(title))


func _on_automation_available(recipe_id: StringName, recipe_name: String, message: String) -> void:
	var final_message := _resolve_alert_message(recipe_id, recipe_name, message)
	if final_message.is_empty():
		return

	# If this exact alert is already showing, restart its visible duration instead of queuing duplicate
	if _is_showing_alert and _alert_banner_label != null and _alert_banner_label.text == final_message:
		_restart_alert_timer()
		return

	# If this exact alert is already in the queue, don't queue duplicate
	for item in _alert_queue:
		if item.get("resolved_message", "") == final_message:
			return

	_alert_queue.append({
		"recipe_id": recipe_id,
		"name": recipe_name,
		"message": message,
		"resolved_message": final_message,
	})
	if not _is_showing_alert:
		_process_next_alert()


func _restart_alert_timer() -> void:
	if _alert_banner_panel == null:
		return

	var parent_ctrl := _alert_banner_panel.get_parent() as Control
	var stage_width := parent_ctrl.size.x if parent_ctrl != null and parent_ctrl.size.x > 0 else 850.0
	var banner_w := _alert_banner_panel.size.x if _alert_banner_panel.size.x > 0 else 440.0
	var center_x := (stage_width - banner_w) * 0.5
	_alert_banner_panel.position = Vector2(center_x, 16.0)
	_alert_banner_panel.modulate.a = 1.0
	_alert_banner_panel.visible = true

	if is_instance_valid(_alert_tween):
		_alert_tween.kill()

	_alert_tween = create_tween()
	_alert_tween.tween_property(_alert_banner_panel, ^"position:y", 16.0, 0.08).from(12.0)
	_alert_tween.parallel().tween_property(_alert_banner_panel, ^"modulate:a", 1.0, 0.08)
	_alert_tween.tween_interval(3.0)
	_alert_tween.tween_property(_alert_banner_panel, ^"position:y", -60.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_alert_tween.parallel().tween_property(_alert_banner_panel, ^"modulate:a", 0.0, 0.2)
	_alert_tween.finished.connect(_on_alert_tween_finished)


func _process_next_alert() -> void:
	if _alert_queue.is_empty():
		_is_showing_alert = false
		return

	_is_showing_alert = true
	var alert_data: Dictionary = _alert_queue.pop_front()
	var recipe_name: String = alert_data.get("name", "")
	var recipe_id: StringName = alert_data.get("recipe_id", &"")
	var raw_message: String = alert_data.get("message", "")
	var message: String = alert_data.get("resolved_message", "")
	if message.is_empty():
		message = _resolve_alert_message(recipe_id, recipe_name, raw_message)

	if _alert_banner_label != null:
		_alert_banner_label.text = message

	if _alert_banner_panel == null:
		_is_showing_alert = false
		return

	var parent_ctrl := _alert_banner_panel.get_parent() as Control
	var stage_width := parent_ctrl.size.x if parent_ctrl != null and parent_ctrl.size.x > 0 else 850.0
	var banner_w := _alert_banner_panel.size.x if _alert_banner_panel.size.x > 0 else 440.0
	var center_x := (stage_width - banner_w) * 0.5
	_alert_banner_panel.position = Vector2(center_x, -60.0)
	_alert_banner_panel.modulate.a = 0.0
	_alert_banner_panel.visible = true

	if is_instance_valid(_alert_tween):
		_alert_tween.kill()

	_alert_tween = create_tween()
	_alert_tween.tween_property(_alert_banner_panel, ^"position:y", 16.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_alert_tween.parallel().tween_property(_alert_banner_panel, ^"modulate:a", 1.0, 0.2)
	_alert_tween.tween_interval(3.0)
	_alert_tween.tween_property(_alert_banner_panel, ^"position:y", -60.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_alert_tween.parallel().tween_property(_alert_banner_panel, ^"modulate:a", 0.0, 0.2)
	_alert_tween.finished.connect(_on_alert_tween_finished)


func _on_alert_tween_finished() -> void:
	if _alert_banner_panel != null:
		_alert_banner_panel.visible = false
	_process_next_alert()


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


func _on_hand_off_button_pressed() -> void:
	if GameControl.is_bot_dispatch_open():
		GameControl.cancel_bot_dispatch()
		return

	if GameControl.has_active_order():
		GameControl.request_bot_dispatch()
	else:
		_on_automation_available(&"", "", "No active order to hand off!")


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
	_refresh_button_prompts()
	_update_interaction_ui()


func _on_controllability_changed(_is_controllable: bool) -> void:
	_update_interaction_ui()


func _on_dialogue_activity_changed(_is_active: bool) -> void:
	_update_interaction_ui()
	if not _is_active:
		call_deferred(&"_try_start_next_story_dialogue")


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


func _on_camera_mode_changed(_mode: GameControl.CameraMode) -> void:
	_arrange_button.visible = true
	_refresh_button_prompts()


func _on_input_mode_changed(_input_mode: GameControl.InputMode) -> void:
	var using_touch := GameControl.is_using_touch()
	_joystick_row.visible = true
	_move_joystick.visible = using_touch
	_look_joystick.visible = using_touch
	_keyboard_hint.visible = not using_touch
	_refresh_button_prompts()


func _on_interact_available_changed(is_available: bool) -> void:
	_interact_button.visible = is_available


func _on_interaction_prompt_changed(prompt: String, hold_duration: float) -> void:
	_interaction_prompt = prompt if not prompt.is_empty() else "INTERACT"
	_interaction_is_hold = hold_duration > 0.0
	_set_interaction_fill(0.0)
	_refresh_button_prompts()


func _on_interaction_progress_changed(progress: float) -> void:
	_set_interaction_fill(progress if _interaction_is_hold else 0.0)


func _set_interaction_fill(progress: float) -> void:
	var fill_amount := clampf(progress, 0.0, 1.0)
	_interaction_fill.value = fill_amount
	_interaction_fill.visible = _interaction_is_hold and fill_amount > 0.0


func _refresh_button_prompts() -> void:
	var using_keyboard := not GameControl.is_using_touch()

	if _tabs != null:
		if _tabs.get_tab_count() > 0:
			_tabs.set_tab_title(0, "KITCHEN (1)" if using_keyboard else "KITCHEN")
		if _tabs.get_tab_count() > 1:
			_tabs.set_tab_title(1, "RECIPES (2)" if using_keyboard else "RECIPES")
		if _tabs.get_tab_count() > 2:
			_tabs.set_tab_title(2, "STORE (3)" if using_keyboard else "STORE")

	if _hand_off_button != null:
		_hand_off_button.text = "HAND OFF (H)" if using_keyboard else "HAND OFF"

	if _arrange_button != null:
		if GameControl.is_arranging:
			_arrange_button.text = "CONFIRM (G)" if using_keyboard else "CONFIRM"
		else:
			_arrange_button.text = "ARRANGE (G)" if using_keyboard else "ARRANGE"

	if _interact_button != null and _interaction_label != null:
		var prompt_text := _interaction_prompt
		if using_keyboard and not prompt_text.is_empty():
			var full_prompt := "%s (SPACE)" % prompt_text
			_interact_button.text = full_prompt
			_interaction_label.text = full_prompt
		else:
			_interact_button.text = prompt_text
			_interaction_label.text = prompt_text

	if _rotate_button != null:
		_rotate_button.text = "ROTATE (R)" if using_keyboard else "ROTATE"
	if _place_button != null:
		_place_button.text = "PLACE (ENTER)" if using_keyboard else "PLACE"
	if _cancel_placement_button != null:
		_cancel_placement_button.text = "CANCEL (ESC)" if using_keyboard else "CANCEL"

	if _process_picker_cancel_button != null:
		_process_picker_cancel_button.text = "CANCEL (ESC)" if using_keyboard else "CANCEL"


func _on_placement_started(item_id: StringName) -> void:
	_placement_tray.visible = true
	_placement_title.text = "PLACING: %s" % str(item_id).capitalize()
	_refresh_button_prompts()
	_update_interaction_ui()


func _on_placement_completed(item_id: StringName, _pos: Vector3, _rot_y: float) -> void:
	_placement_tray.visible = false
	_refresh_button_prompts()
	_update_interaction_ui()
	match item_id:
		&"Sink":
			_queue_story_dialogue(&"story_sink")
		&"Fridge":
			_queue_story_dialogue(&"story_fridge")
		&"Oven":
			_queue_story_dialogue(&"story_oven")


func _on_placement_cancelled() -> void:
	_placement_tray.visible = false
	_refresh_button_prompts()
	_update_interaction_ui()


func _on_arrange_mode_changed(_is_arranging: bool) -> void:
	_arrange_button.visible = true
	_refresh_button_prompts()
	_update_interaction_ui()


func _on_tab_change_requested(tab_index: int) -> void:
	_tabs.current_tab = tab_index


func _on_rotate_button_pressed() -> void:
	SFX.play_click()
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
