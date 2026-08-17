class_name BotHandoffUI
extends PanelContainer
## Controller for the Bot Handoff Modal UI.
##
## Manages assigning up to 3 automated bots across automatable items in an active order.
## Provides full mouse and keyboard accessibility.

const FONT_LILITA: FontFile = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const FONT_TOMATO: FontFile = preload("res://assets/fonts/Sauce Tomato.otf")

@onready var title_label: Label = %Title
@onready var pool_label: Label = %PoolLabel
@onready var items_list: VBoxContainer = %ItemsList
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton
@onready var key_hint_label: Label = %KeyHintLabel

var _order_id: int = 0
var _spinboxes: Dictionary = {}
var _row_panels: Dictionary = {}
var _ordered_auto_item_ids: Array[StringName] = []
var _selected_auto_index: int = 0


func _ready() -> void:
	visible = false
	if confirm_button != null:
		confirm_button.pressed.connect(_on_confirm_pressed)
	if cancel_button != null:
		cancel_button.pressed.connect(_on_cancel_pressed)

	GameControl.bot_dispatch_requested.connect(_on_bot_dispatch_requested)
	GameControl.bot_dispatch_closed.connect(hide_modal)


func _exit_tree() -> void:
	if GameControl.bot_dispatch_requested.is_connected(_on_bot_dispatch_requested):
		GameControl.bot_dispatch_requested.disconnect(_on_bot_dispatch_requested)
	if GameControl.bot_dispatch_closed.is_connected(hide_modal):
		GameControl.bot_dispatch_closed.disconnect(hide_modal)


func _on_bot_dispatch_requested(order_id: int, order_data: Dictionary, automatable_items: Dictionary) -> void:
	_order_id = order_id
	if items_list == null:
		return

	if title_label != null:
		title_label.text = "BOT HANDOFF — ORDER #%02d" % order_id if order_id > 0 else "BOT HANDOFF"

	for child in items_list.get_children():
		child.queue_free()
	_spinboxes.clear()
	_row_panels.clear()
	_ordered_auto_item_ids.clear()
	_selected_auto_index = 0

	var items: Dictionary = order_data.get("items", {})
	var item_names: Dictionary = order_data.get("item_names", {})
	var existing_allocs: Dictionary = GameControl.get_active_bot_allocations()

	for raw_id: Variant in items:
		var item_id := StringName(str(raw_id))
		var req_qty := int(items[raw_id])
		var is_auto := bool(automatable_items.get(item_id, false))
		var item_name := str(item_names.get(item_id, RecipeTracker.get_recipe_name(item_id)))

		if is_auto:
			_ordered_auto_item_ids.append(item_id)

		var item_row := _create_item_row(item_id, item_name, req_qty, is_auto, int(existing_allocs.get(item_id, 0)))
		items_list.add_child(item_row)

	_update_pool_display()
	_refresh_row_highlights()
	visible = true

	# Set focus on first interactive control
	if not _ordered_auto_item_ids.is_empty():
		var first_id := _ordered_auto_item_ids[0]
		var sb := _spinboxes.get(first_id) as SpinBox
		if sb != null:
			sb.grab_focus.call_deferred()
	elif confirm_button != null:
		confirm_button.grab_focus.call_deferred()


func _create_item_row(item_id: StringName, item_name: String, required_qty: int, is_automated: bool, initial_val: int) -> Control:
	var row_panel := PanelContainer.new()
	row_panel.name = "Row_%s" % item_id
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.152941, 0.145098, 0.121569, 0.96)
	row_style.border_color = Color(1.0, 0.780392, 0.172549, 1.0) if is_automated else Color(0.152941, 0.145098, 0.121569, 1.0)
	row_style.set_border_width_all(2)
	row_style.set_corner_radius_all(14)
	row_style.content_margin_left = 12.0
	row_style.content_margin_right = 12.0
	row_style.content_margin_top = 8.0
	row_style.content_margin_bottom = 8.0
	row_style.shadow_color = Color(0.152941, 0.145098, 0.121569, 0.35)
	row_style.shadow_size = 3
	row_style.shadow_offset = Vector2(0, 2)
	row_panel.add_theme_stylebox_override("panel", row_style)
	_row_panels[item_id] = row_panel

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	row_panel.add_child(hbox)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(left_vbox)

	var name_lbl := Label.new()
	name_lbl.text = "%dx  %s" % [required_qty, item_name]
	name_lbl.add_theme_font_override("font", FONT_LILITA)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	left_vbox.add_child(name_lbl)

	var badge := _create_status_badge(is_automated)
	left_vbox.add_child(badge)

	if is_automated:
		var stepper_hbox := HBoxContainer.new()
		stepper_hbox.add_theme_constant_override("separation", 6)
		stepper_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(stepper_hbox)

		# Minus Button
		var minus_btn := Button.new()
		minus_btn.name = "MinusButton"
		minus_btn.text = "−"
		minus_btn.custom_minimum_size = Vector2(34, 34)
		minus_btn.add_theme_font_override("font", FONT_LILITA)
		minus_btn.add_theme_font_size_override("font_size", 18)
		minus_btn.focus_mode = Control.FOCUS_NONE
		minus_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_apply_stepper_button_style(minus_btn)
		minus_btn.pressed.connect(func() -> void:
			_adjust_spinbox(item_id, -1)
		)
		stepper_hbox.add_child(minus_btn)

		# SpinBox
		var spinbox := SpinBox.new()
		spinbox.name = "SpinBox"
		spinbox.min_value = 0
		spinbox.max_value = required_qty
		spinbox.step = 1
		spinbox.value = mini(initial_val, required_qty)
		spinbox.custom_minimum_size = Vector2(76, 38)
		spinbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		spinbox.alignment = HORIZONTAL_ALIGNMENT_CENTER
		spinbox.focus_mode = Control.FOCUS_ALL

		# Theme the internal LineEdit
		var line_edit := spinbox.get_line_edit()
		if line_edit != null:
			line_edit.add_theme_font_override("font", FONT_LILITA)
			line_edit.add_theme_font_size_override("font_size", 16)
			line_edit.add_theme_color_override("font_color", Color(1.0, 0.780392, 0.172549, 1.0))
			line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
			line_edit.focus_entered.connect(func() -> void:
				_set_selected_item_by_id(item_id)
			)

		spinbox.focus_entered.connect(func() -> void:
			_set_selected_item_by_id(item_id)
		)
		spinbox.value_changed.connect(_on_spinbox_value_changed.bind(item_id))
		stepper_hbox.add_child(spinbox)
		_spinboxes[item_id] = spinbox

		# Plus Button
		var plus_btn := Button.new()
		plus_btn.name = "PlusButton"
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(34, 34)
		plus_btn.add_theme_font_override("font", FONT_LILITA)
		plus_btn.add_theme_font_size_override("font_size", 18)
		plus_btn.focus_mode = Control.FOCUS_NONE
		plus_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_apply_stepper_button_style(plus_btn)
		plus_btn.pressed.connect(func() -> void:
			_adjust_spinbox(item_id, 1)
		)
		stepper_hbox.add_child(plus_btn)
	else:
		var lock_lbl := Label.new()
		lock_lbl.text = "🔒 Manual Only"
		lock_lbl.add_theme_font_override("font", FONT_LILITA)
		lock_lbl.add_theme_font_size_override("font_size", 13)
		lock_lbl.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58, 1.0))
		lock_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(lock_lbl)

	return row_panel


func _apply_stepper_button_style(btn: Button) -> void:
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.24, 0.22, 0.20, 1.0)
	style_normal.border_color = Color(1.0, 0.78, 0.17, 0.8)
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.38, 0.34, 0.28, 1.0)
	style_hover.border_color = Color(1.0, 0.9, 0.3, 1.0)
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.16, 0.14, 0.12, 1.0)
	style_pressed.border_color = Color(1.0, 0.78, 0.17, 1.0)
	style_pressed.set_border_width_all(2)
	style_pressed.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("pressed", style_pressed)


func _create_status_badge(is_automated: bool) -> PanelContainer:
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(0.152941, 0.145098, 0.121569, 1.0)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0

	var label := Label.new()
	label.add_theme_font_override("font", FONT_LILITA)
	label.add_theme_font_size_override("font_size", 11)

	if is_automated:
		style.bg_color = Color(0.32549, 0.721569, 0.227451, 1.0)
		label.text = "✓ AUTOMATED"
		label.add_theme_color_override("font_color", Color(0.152941, 0.145098, 0.121569, 1.0))
	else:
		style.bg_color = Color(0.22, 0.20, 0.18, 1.0)
		label.text = "🔒 NOT AUTOMATED"
		label.add_theme_color_override("font_color", Color(0.68, 0.65, 0.62, 1.0))

	badge.add_theme_stylebox_override("panel", style)
	badge.add_child(label)
	return badge


func _adjust_spinbox(item_id: StringName, delta: int) -> void:
	var sb := _spinboxes.get(item_id) as SpinBox
	if sb == null:
		return
	sb.value = clampf(sb.value + delta, sb.min_value, sb.max_value)
	_set_selected_item_by_id(item_id)


func _set_spinbox_value(item_id: StringName, new_val: int) -> void:
	var sb := _spinboxes.get(item_id) as SpinBox
	if sb == null:
		return
	sb.value = clampf(float(new_val), sb.min_value, sb.max_value)
	_set_selected_item_by_id(item_id)


func _set_selected_item_by_id(item_id: StringName) -> void:
	var idx := _ordered_auto_item_ids.find(item_id)
	if idx != -1:
		_selected_auto_index = idx
		_refresh_row_highlights()


func _refresh_row_highlights() -> void:
	for i in range(_ordered_auto_item_ids.size()):
		var it_id := _ordered_auto_item_ids[i]
		var panel := _row_panels.get(it_id) as PanelContainer
		if panel == null:
			continue
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			if i == _selected_auto_index:
				style.border_color = Color(1.0, 0.92, 0.35, 1.0)
				style.set_border_width_all(3)
			else:
				style.border_color = Color(1.0, 0.780392, 0.172549, 1.0)
				style.set_border_width_all(2)


func _on_spinbox_value_changed(_new_val: float, changed_item_id: StringName) -> void:
	var total := 0
	for it_id: StringName in _spinboxes:
		var sb := _spinboxes[it_id] as SpinBox
		if sb != null:
			total += int(sb.value)

	if total > GameControl.MAX_BOTS:
		var other_sum := 0
		for it_id: StringName in _spinboxes:
			if it_id != changed_item_id:
				var sb := _spinboxes[it_id] as SpinBox
				if sb != null:
					other_sum += int(sb.value)
		var max_allowed := maxi(0, GameControl.MAX_BOTS - other_sum)
		var changed_sb := _spinboxes.get(changed_item_id) as SpinBox
		if changed_sb != null:
			changed_sb.value = max_allowed

	_update_pool_display()


func _update_pool_display() -> void:
	var total := 0
	for it_id: StringName in _spinboxes:
		var sb := _spinboxes[it_id] as SpinBox
		if sb != null:
			total += int(sb.value)
	var remaining := maxi(0, GameControl.MAX_BOTS - total)
	if pool_label != null:
		pool_label.text = "BOTS ASSIGNED: %d / %d  (%d Available)" % [
			total, GameControl.MAX_BOTS, remaining
		]
		if total == GameControl.MAX_BOTS:
			pool_label.add_theme_color_override("font_color", Color(0.32549, 0.721569, 0.227451, 1.0))
		else:
			pool_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.17, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.is_echo():
		match event.keycode:
			KEY_ESCAPE:
				_on_cancel_pressed()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				if cancel_button != null and cancel_button.has_focus():
					_on_cancel_pressed()
				else:
					_on_confirm_pressed()
				get_viewport().set_input_as_handled()
			KEY_UP, KEY_W:
				_navigate_item_selection(-1)
				get_viewport().set_input_as_handled()
			KEY_DOWN, KEY_S:
				# If on bottom row and presses S / Down, can move to buttons
				if not _ordered_auto_item_ids.is_empty() and _selected_auto_index == _ordered_auto_item_ids.size() - 1:
					if confirm_button != null:
						confirm_button.grab_focus()
						get_viewport().set_input_as_handled()
				else:
					_navigate_item_selection(1)
					get_viewport().set_input_as_handled()
			KEY_LEFT, KEY_A, KEY_MINUS, KEY_KP_SUBTRACT:
				if cancel_button != null and cancel_button.has_focus():
					pass # Normal UI navigation
				elif confirm_button != null and confirm_button.has_focus():
					if event.keycode == KEY_LEFT or event.keycode == KEY_A:
						cancel_button.grab_focus()
						get_viewport().set_input_as_handled()
				elif not _ordered_auto_item_ids.is_empty():
					var cur_id := _ordered_auto_item_ids[_selected_auto_index]
					_adjust_spinbox(cur_id, -1)
					get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_D, KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				if cancel_button != null and cancel_button.has_focus():
					if event.keycode == KEY_RIGHT or event.keycode == KEY_D:
						confirm_button.grab_focus()
						get_viewport().set_input_as_handled()
				elif confirm_button != null and confirm_button.has_focus():
					pass # Normal UI navigation
				elif not _ordered_auto_item_ids.is_empty():
					var cur_id := _ordered_auto_item_ids[_selected_auto_index]
					_adjust_spinbox(cur_id, 1)
					get_viewport().set_input_as_handled()
			KEY_0, KEY_KP_0:
				_set_current_spinbox_value(0)
				get_viewport().set_input_as_handled()
			KEY_1, KEY_KP_1:
				_set_current_spinbox_value(1)
				get_viewport().set_input_as_handled()
			KEY_2, KEY_KP_2:
				_set_current_spinbox_value(2)
				get_viewport().set_input_as_handled()
			KEY_3, KEY_KP_3:
				_set_current_spinbox_value(3)
				get_viewport().set_input_as_handled()


func _navigate_item_selection(delta: int) -> void:
	if _ordered_auto_item_ids.is_empty():
		return
	_selected_auto_index = clampi(_selected_auto_index + delta, 0, _ordered_auto_item_ids.size() - 1)
	_refresh_row_highlights()
	var cur_id := _ordered_auto_item_ids[_selected_auto_index]
	var sb := _spinboxes.get(cur_id) as SpinBox
	if sb != null:
		sb.grab_focus()


func _set_current_spinbox_value(val: int) -> void:
	if _ordered_auto_item_ids.is_empty():
		return
	var cur_id := _ordered_auto_item_ids[_selected_auto_index]
	_set_spinbox_value(cur_id, val)


func _on_confirm_pressed() -> void:
	var allocations: Dictionary = {}
	for it_id: StringName in _spinboxes:
		var sb := _spinboxes[it_id] as SpinBox
		if sb != null:
			var val := int(sb.value)
			if val > 0:
				allocations[it_id] = val
	GameControl.confirm_bot_dispatch(_order_id, allocations)
	hide_modal()


func _on_cancel_pressed() -> void:
	GameControl.cancel_bot_dispatch(_order_id)
	hide_modal()


func hide_modal() -> void:
	_order_id = 0
	visible = false
