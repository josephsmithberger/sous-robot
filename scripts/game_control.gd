extends Node
## Global source of truth for whether the 3D game viewport is currently controllable.

const SENOR_FOOD_DIALOGUE: DialogueResource = preload("res://dialogue/master.dialogue")
const ORDER_DIALOGUE: DialogueResource = preload("res://dialogue/orders.dialogue")

const KITCHEN_TAB := 0

signal controllability_changed(is_controllable: bool)
signal input_mode_changed(input_mode: InputMode)
signal dialogue_activity_changed(is_active: bool)
signal camera_mode_changed(camera_mode: CameraMode)
signal look_at_requested(target_position: Vector3, duration: float)
signal ui_mode_changed(is_ui_mode: bool)
signal interact_available_changed(is_available: bool)
signal interaction_pressed
signal interaction_released
signal interaction_prompt_changed(prompt: String, hold_duration: float)
signal interaction_progress_changed(progress: float)
## Transient appliance preparation-choice lifecycle. The target is never owned by
## the picker; it is only valid while the player remains in range and holds the
## matching input item.
signal process_picker_requested(target: Node, options: Array[ItemProcessRecipe])
signal process_picker_selected(target: Node, recipe: ItemProcessRecipe)
signal process_picker_cancelled
signal process_picker_refreshed(target: Node, options: Array[ItemProcessRecipe])
@warning_ignore("unused_signal")
signal held_item_changed(item: KitchenItem)
@warning_ignore("unused_signal")
signal item_delivered(item: KitchenItem)
@warning_ignore("unused_signal")
signal item_trashed(item: KitchenItem)

@warning_ignore("unused_signal")
signal order_dialogue_confirmed
@warning_ignore("unused_signal")
signal order_started(order_id: int, order: Dictionary)
@warning_ignore("unused_signal")
signal order_timer_updated(order_id: int, elapsed_time: float, max_time: float, current_tip: float, urgency: float)
@warning_ignore("unused_signal")
signal order_item_fulfilled(order_id: int, item_id: StringName, fulfilled: int, required: int)
@warning_ignore("unused_signal")
signal order_penalized(order_id: int, remaining_tip: float, penalty: float, item_name: String)
@warning_ignore("unused_signal")
signal order_completed(order_id: int, payout: float, final_tip: float)
@warning_ignore("unused_signal")
signal money_changed(balance: float, delta: float, reason: String)
@warning_ignore("unused_signal")
signal item_unlocked(item_id: StringName)
@warning_ignore("unused_signal")
signal placement_requested(item_id: StringName)
@warning_ignore("unused_signal")
signal placement_started(item_id: StringName)
@warning_ignore("unused_signal")
signal placement_cancelled
@warning_ignore("unused_signal")
signal placement_completed(item_id: StringName, position: Vector3, rotation_y: float)
@warning_ignore("unused_signal")
signal automation_available(recipe_id: StringName, recipe_name: String, message: String)
@warning_ignore("unused_signal")
signal arrange_mode_changed(is_arranging: bool)
@warning_ignore("unused_signal")
signal tab_change_requested(tab_index: int)
@warning_ignore("unused_signal")
signal tab_changed(tab_index: int)
@warning_ignore("unused_signal")
signal order_clock_paused_changed(is_paused: bool)
@warning_ignore("unused_signal")
signal bot_dispatch_requested(order_id: int, order: Dictionary, automatable_items: Dictionary)
@warning_ignore("unused_signal")
signal bots_assigned(order_id: int, bot_allocations: Dictionary)
@warning_ignore("unused_signal")
signal bot_dispatch_cancelled(order_id: int)
@warning_ignore("unused_signal")
signal bot_dispatch_closed

const MAX_BOTS := 3

enum InputMode {
	KEYBOARD,
	TOUCH,
}

enum CameraMode {
	FIRST_PERSON,
	MARKER,
	WAITER,
}

var current_tab := KITCHEN_TAB:
	set(value):
		if current_tab == value:
			return
		current_tab = value
		tab_changed.emit(current_tab)
		_check_clock_pause_changed()

var is_controllable := false:
	set(value):
		if is_controllable == value:
			return
		is_controllable = value
		controllability_changed.emit(is_controllable)

var input_mode: InputMode = InputMode.KEYBOARD:
	set(value):
		if input_mode == value:
			return
		input_mode = value
		input_mode_changed.emit(input_mode)
		_sync_mouse_mode()

var camera_mode := CameraMode.MARKER:
	set(value):
		if camera_mode == value:
			return
		camera_mode = value
		camera_mode_changed.emit(camera_mode)
		_sync_mouse_mode()
		_check_clock_pause_changed()

var is_ui_mode := true:
	set(value):
		if is_ui_mode == value:
			return
		is_ui_mode = value
		_sync_mouse_mode()
		ui_mode_changed.emit(is_ui_mode)

var can_interact := false:
	set(value):
		if can_interact == value:
			return
		can_interact = value
		interact_available_changed.emit(can_interact)

var move_input := Vector2.ZERO
var look_input := Vector2.ZERO
var interaction_prompt := ""
var interaction_hold_duration := 0.0
var interaction_progress := 0.0
var process_picker_target: Node
var process_picker_options: Array[ItemProcessRecipe] = []
var process_picker_selected_recipe: ItemProcessRecipe
var process_picker_open := false
var bot_dispatch_open := false
var active_bot_allocations: Dictionary = {}
var active_order_data: Dictionary = {}
var money := 0.0
var active_order_id := 0
var owned_items: Array[StringName] = [&"DecoratedWall", &"BunCrate"]

var is_placing := false
var is_arranging := false
var placing_item_id: StringName = &""

var _controllability_requested := false
var _active_dialogues := 0
var _mouse_look_delta := Vector2.ZERO
var _camera_mode_before_dialogue: CameraMode = CameraMode.FIRST_PERSON
var _ui_mode_before_dialogue := false
var _dialogue_changed_camera := false
var _last_clock_paused := true
var _pending_bot_dispatch: Dictionary = {}


func is_bot_dispatch_open() -> bool:
	return bot_dispatch_open


func get_active_bot_allocations() -> Dictionary:
	return active_bot_allocations.duplicate()


func is_item_automated(item_id: StringName) -> bool:
	return RecipeTracker.is_item_automated(item_id)


func request_bot_dispatch(order_id: int = 0, order_data: Dictionary = {}) -> void:
	var target_order_id := order_id if order_id > 0 else active_order_id
	var target_order := order_data.duplicate(true) if not order_data.is_empty() else active_order_data.duplicate(true)
	if target_order.is_empty():
		return

	if is_dialogue_active():
		_pending_bot_dispatch = {
			"order_id": target_order_id,
			"order_data": target_order,
		}
		return

	_pending_bot_dispatch.clear()
	var items: Dictionary = target_order.get("items", {})
	var automatable_items := RecipeTracker.get_automatable_items_for_order(items)
	bot_dispatch_open = true
	bot_dispatch_requested.emit(target_order_id, target_order, automatable_items)


func confirm_bot_dispatch(order_id: int, allocations: Dictionary) -> void:
	active_bot_allocations = allocations.duplicate()
	bot_dispatch_open = false
	_pending_bot_dispatch.clear()
	bots_assigned.emit(order_id, active_bot_allocations)
	bot_dispatch_closed.emit()


func cancel_bot_dispatch(order_id: int = 0) -> void:
	var target_order_id := order_id if order_id > 0 else active_order_id
	bot_dispatch_open = false
	_pending_bot_dispatch.clear()
	bot_dispatch_cancelled.emit(target_order_id)
	bot_dispatch_closed.emit()


func is_process_picker_open() -> bool:
	return process_picker_open and is_instance_valid(process_picker_target) and not process_picker_options.is_empty()


func request_process_picker(target: Node, options: Array[ItemProcessRecipe]) -> void:
	if target == null or options.is_empty():
		cancel_process_picker()
		return
	process_picker_target = target
	process_picker_options = options.duplicate()
	process_picker_selected_recipe = null
	process_picker_open = true
	process_picker_requested.emit(process_picker_target, process_picker_options)


func request_process_choice(target: Node, options: Array[ItemProcessRecipe]) -> void:
	request_process_picker(target, options)


func select_process_recipe(recipe: ItemProcessRecipe) -> bool:
	if not is_process_picker_open() or recipe == null or not process_picker_options.has(recipe):
		return false
	var target := process_picker_target
	process_picker_selected_recipe = recipe
	process_picker_open = false
	process_picker_selected.emit(target, recipe)
	process_picker_refreshed.emit(target, process_picker_options)
	return true


func select_process_choice(recipe: ItemProcessRecipe) -> bool:
	return select_process_recipe(recipe)


func cancel_process_picker() -> void:
	var had_picker := process_picker_open or process_picker_target != null or not process_picker_options.is_empty()
	process_picker_open = false
	process_picker_target = null
	process_picker_options.clear()
	process_picker_selected_recipe = null
	if had_picker:
		process_picker_cancelled.emit()


func cancel_process_choice() -> void:
	cancel_process_picker()


func refresh_process_picker(target: Node = null, options: Array[ItemProcessRecipe] = []) -> void:
	var next_target := target if target != null else process_picker_target
	var next_options := options if not options.is_empty() else process_picker_options
	if next_target == null or next_options.is_empty():
		cancel_process_picker()
		return
	process_picker_target = next_target
	process_picker_options = next_options.duplicate()
	process_picker_open = true
	process_picker_refreshed.emit(process_picker_target, process_picker_options)


func refresh_process_choice(target: Node = null, options: Array[ItemProcessRecipe] = []) -> void:
	refresh_process_picker(target, options)


func _ready() -> void:
	_ensure_interact_action()
	input_mode = InputMode.TOUCH if DisplayServer.is_touchscreen_available() else InputMode.KEYBOARD
	_sync_mouse_mode()
	if not held_item_changed.is_connected(_on_held_item_changed_for_picker):
		held_item_changed.connect(_on_held_item_changed_for_picker)
	if not RecipeTracker.automation_available.is_connected(_on_recipe_tracker_automation_available):
		RecipeTracker.automation_available.connect(_on_recipe_tracker_automation_available)
	_connect_dialogue_manager()
	_last_clock_paused = is_order_clock_paused()


func _on_recipe_tracker_automation_available(recipe_id: StringName, recipe_name: String, message: String) -> void:
	automation_available.emit(recipe_id, recipe_name, message)


func _ensure_interact_action() -> void:
	if not InputMap.has_action(&"interact"):
		InputMap.add_action(&"interact")
	for event in InputMap.action_get_events(&"interact"):
		if event is InputEventKey and (
			(event as InputEventKey).physical_keycode == KEY_SPACE
			or (event as InputEventKey).keycode == KEY_SPACE
		):
			return
	var space_event := InputEventKey.new()
	space_event.physical_keycode = KEY_SPACE
	InputMap.action_add_event(&"interact", space_event)


func reset_session(starting_money: float = 0.0) -> void:
	active_order_id = 0
	active_order_data.clear()
	active_bot_allocations.clear()
	_pending_bot_dispatch.clear()
	_active_dialogues = 0
	_dialogue_changed_camera = false
	bot_dispatch_open = false
	current_tab = KITCHEN_TAB
	owned_items = [&"DecoratedWall", &"BunCrate"]
	RecipeTracker.reset_tracker()
	var delta := starting_money - money
	money = starting_money
	money_changed.emit(money, delta, "SESSION START")
	_check_clock_pause_changed()


func begin_order(order_id: int, order_data: Dictionary = {}) -> void:
	active_order_id = order_id
	active_order_data = order_data.duplicate(true)


func end_order(order_id: int) -> void:
	if active_order_id == order_id:
		active_order_id = 0
		active_order_data.clear()
		active_bot_allocations.clear()
		_pending_bot_dispatch.clear()
		if bot_dispatch_open:
			cancel_bot_dispatch(order_id)


func has_active_order() -> bool:
	return active_order_id > 0


func can_afford(cost: float) -> bool:
	return money + 0.0001 >= cost


func spend_money(cost: float, reason: String = "") -> bool:
	if cost <= 0.0 or not can_afford(cost):
		return false
	change_money(-cost, reason)
	return true


func is_item_owned(item_id: StringName) -> bool:
	return owned_items.has(item_id)


func unlock_item(item_id: StringName) -> void:
	if not owned_items.has(item_id):
		owned_items.append(item_id)
		item_unlocked.emit(item_id)


func change_money(delta: float, reason: String = "") -> void:
	if is_zero_approx(delta):
		return
	money += delta
	money_changed.emit(money, delta, reason)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if has_player_control():
			_mouse_look_delta += event.relative
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		# Mouse-to-touch emulation is useful for testing joysticks, but it should not
		# make a desktop web player look like a touchscreen device.
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			input_mode = InputMode.TOUCH
	elif event is InputEventKey and event.pressed and not event.echo:
		input_mode = InputMode.KEYBOARD
		if event.keycode == KEY_ESCAPE and _controllability_requested and not is_dialogue_active():
			if is_bot_dispatch_open():
				cancel_bot_dispatch()
				get_viewport().set_input_as_handled()
				return
			if is_process_picker_open():
				cancel_process_picker()
				get_viewport().set_input_as_handled()
				return
			if is_ui_mode or camera_mode != CameraMode.FIRST_PERSON:
				give_player_control()
			else:
				set_ui_mode(true)
			get_viewport().set_input_as_handled()

	if event.is_action_pressed(&"interact", false) and not event.is_echo():
		request_interaction()
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"interact"):
		cancel_interaction()
		get_viewport().set_input_as_handled()


func request_interaction() -> void:
	if has_player_control() and can_interact:
		interaction_pressed.emit()


func cancel_interaction() -> void:
	interaction_released.emit()
	set_interaction_progress(0.0)


func set_interaction_context(next_prompt: String, next_hold_duration: float = 0.0) -> void:
	var changed := interaction_prompt != next_prompt or not is_equal_approx(interaction_hold_duration, next_hold_duration)
	interaction_prompt = next_prompt
	interaction_hold_duration = next_hold_duration
	can_interact = not interaction_prompt.is_empty()
	if changed:
		interaction_prompt_changed.emit(interaction_prompt, interaction_hold_duration)


func clear_interaction_context() -> void:
	set_interaction_context("")
	set_interaction_progress(0.0)


func _on_held_item_changed_for_picker(_item: KitchenItem) -> void:
	# A recipe choice is tied to the item currently in the player's hand.
	if is_process_picker_open() or process_picker_selected_recipe != null:
		cancel_process_picker()


func set_interaction_progress(progress: float) -> void:
	var next_progress := clampf(progress, 0.0, 1.0)
	if is_equal_approx(interaction_progress, next_progress):
		return
	interaction_progress = next_progress
	interaction_progress_changed.emit(interaction_progress)


func set_controllable(value: bool) -> void:
	_controllability_requested = value
	if not value:
		cancel_bot_dispatch()
		cancel_process_picker()
		cancel_interaction()
		set_ui_mode(true)
	_refresh_controllability()


func set_ui_mode(value: bool) -> void:
	if not value and (not _controllability_requested or is_dialogue_active() or camera_mode != CameraMode.FIRST_PERSON):
		value = true
	is_ui_mode = value


func set_camera_mode(value: CameraMode) -> void:
	camera_mode = value
	_sync_mouse_mode()


func look_at_target(target_position: Vector3, duration: float = 0.35) -> void:
	if camera_mode != CameraMode.FIRST_PERSON:
		set_camera_mode(CameraMode.FIRST_PERSON)
	look_at_requested.emit(target_position, duration)


func give_player_control() -> void:
	if is_dialogue_active():
		return
	set_camera_mode(CameraMode.FIRST_PERSON)
	set_ui_mode(false)
	_camera_mode_before_dialogue = camera_mode
	_ui_mode_before_dialogue = is_ui_mode


func hand_off_control() -> void:
	if is_dialogue_active():
		return
	if has_active_order():
		request_bot_dispatch(active_order_id, active_order_data)


func toggle_camera_mode() -> void:
	# Repurposed for Handoff theme: trigger bot handoff
	hand_off_control()
	_camera_mode_before_dialogue = camera_mode
	_ui_mode_before_dialogue = is_ui_mode


func has_player_control() -> bool:
	return is_controllable and not is_ui_mode and camera_mode == CameraMode.FIRST_PERSON and not is_placing and not is_arranging


func start_placement(item_id: StringName) -> void:
	if item_id.is_empty():
		return
	placing_item_id = item_id
	is_placing = true
	set_camera_mode(CameraMode.MARKER)
	set_ui_mode(true)
	placement_requested.emit(item_id)
	placement_started.emit(item_id)
	_check_clock_pause_changed()


func cancel_placement() -> void:
	if not is_placing:
		return
	is_placing = false
	placing_item_id = &""
	placement_cancelled.emit()
	_check_clock_pause_changed()


func complete_placement(item_id: StringName, pos: Vector3, rot_y: float) -> void:
	is_placing = false
	placing_item_id = &""
	placement_completed.emit(item_id, pos, rot_y)
	_check_clock_pause_changed()
	RecipeTracker.call_deferred(&"check_all_satisfied_automations")


func set_arrange_mode(enabled: bool) -> void:
	if is_arranging == enabled:
		return
	is_arranging = enabled
	if is_arranging:
		set_camera_mode(CameraMode.MARKER)
		set_ui_mode(true)
	else:
		if is_placing:
			cancel_placement()
	arrange_mode_changed.emit(is_arranging)
	_check_clock_pause_changed()


func toggle_arrange_mode() -> void:
	set_arrange_mode(not is_arranging)


func request_tab_switch(tab_index: int) -> void:
	current_tab = tab_index
	tab_change_requested.emit(tab_index)


func set_virtual_input(move: Vector2, look: Vector2) -> void:
	move_input = move
	look_input = look


func get_move_input() -> Vector2:
	var keyboard_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	return (keyboard_input + move_input).limit_length()


func consume_mouse_look_delta() -> Vector2:
	var delta := _mouse_look_delta
	_mouse_look_delta = Vector2.ZERO
	return delta


func is_using_touch() -> bool:
	return input_mode == InputMode.TOUCH


func is_dialogue_active() -> bool:
	return _active_dialogues > 0


func is_kitchen_tab() -> bool:
	return current_tab == KITCHEN_TAB


func is_overview_mode() -> bool:
	return camera_mode == CameraMode.MARKER or is_arranging or is_placing


func is_order_clock_paused() -> bool:
	return not is_kitchen_tab() or is_overview_mode() or is_dialogue_active()


func _check_clock_pause_changed() -> void:
	var paused := is_order_clock_paused()
	if _last_clock_paused != paused:
		_last_clock_paused = paused
		order_clock_paused_changed.emit(paused)


func _connect_dialogue_manager() -> void:
	var dialogue_manager := get_node_or_null("/root/DialogueManager")
	if dialogue_manager == null:
		call_deferred(&"_connect_dialogue_manager")
		return

	if not dialogue_manager.dialogue_started.is_connected(_on_dialogue_started):
		dialogue_manager.dialogue_started.connect(_on_dialogue_started)
	if not dialogue_manager.dialogue_ended.is_connected(_on_dialogue_ended):
		dialogue_manager.dialogue_ended.connect(_on_dialogue_ended)


func _on_dialogue_started(resource: Resource) -> void:
	_active_dialogues += 1
	if _active_dialogues == 1:
		_camera_mode_before_dialogue = camera_mode
		_ui_mode_before_dialogue = is_ui_mode
		if resource == SENOR_FOOD_DIALOGUE:
			_dialogue_changed_camera = true
			set_camera_mode(CameraMode.MARKER)
		elif resource == ORDER_DIALOGUE:
			_dialogue_changed_camera = true
			set_camera_mode(CameraMode.WAITER)
		else:
			_dialogue_changed_camera = false
		dialogue_activity_changed.emit(true)
	_refresh_controllability()
	_check_clock_pause_changed()


func _on_dialogue_ended(resource: Resource) -> void:
	_active_dialogues = maxi(_active_dialogues - 1, 0)
	if _active_dialogues == 0:
		if _dialogue_changed_camera:
			if resource == SENOR_FOOD_DIALOGUE:
				set_camera_mode(CameraMode.FIRST_PERSON)
				_camera_mode_before_dialogue = CameraMode.FIRST_PERSON
				_ui_mode_before_dialogue = false
			else:
				set_camera_mode(_camera_mode_before_dialogue)
		_dialogue_changed_camera = false
		dialogue_activity_changed.emit(false)
	_refresh_controllability()
	if _active_dialogues == 0 and _controllability_requested:
		if resource == SENOR_FOOD_DIALOGUE:
			set_ui_mode(false)
		else:
			set_ui_mode(_ui_mode_before_dialogue)
	_check_clock_pause_changed()

	if _active_dialogues == 0 and not _pending_bot_dispatch.is_empty():
		var pending: Dictionary = _pending_bot_dispatch.duplicate(true)
		_pending_bot_dispatch.clear()
		var p_order_id: int = int(pending.get("order_id", 0))
		var p_order_data: Dictionary = pending.get("order_data", {})
		if has_active_order() and (p_order_id == 0 or p_order_id == active_order_id):
			request_bot_dispatch(p_order_id, p_order_data)


func _refresh_controllability() -> void:
	is_controllable = _controllability_requested and not is_dialogue_active()
	if not is_controllable:
		set_ui_mode(true)
	else:
		_sync_mouse_mode()


func _sync_mouse_mode() -> void:
	var should_capture := (
		input_mode == InputMode.KEYBOARD
		and is_controllable
		and not is_ui_mode
		and camera_mode == CameraMode.FIRST_PERSON
		and not is_placing
		and not is_arranging
	)
	if not should_capture:
		_mouse_look_delta = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if should_capture else Input.MOUSE_MODE_VISIBLE
