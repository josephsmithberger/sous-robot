class_name BotHandoffUI
extends PanelContainer
## Controller for the Bot Handoff Modal UI.
##
## Manages assigning up to 3 automated bots across automatable items in an active order.

const FONT_LILITA: FontFile = preload("res://assets/fonts/LilitaOne-Regular.ttf")
const FONT_TOMATO: FontFile = preload("res://assets/fonts/Sauce Tomato.otf")

@onready var title_label: Label = %Title
@onready var pool_label: Label = %PoolLabel
@onready var items_list: VBoxContainer = %ItemsList
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton

var _order_id: int = 0
var _spinboxes: Dictionary = {}


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

	var items: Dictionary = order_data.get("items", {})
	var item_names: Dictionary = order_data.get("item_names", {})
	var existing_allocs: Dictionary = GameControl.get_active_bot_allocations()

	for raw_id: Variant in items:
		var item_id := StringName(str(raw_id))
		var req_qty := int(items[raw_id])
		var is_auto := bool(automatable_items.get(item_id, false))
		var item_name := str(item_names.get(item_id, RecipeTracker.get_recipe_name(item_id)))

		var item_row := _create_item_row(item_id, item_name, req_qty, is_auto, int(existing_allocs.get(item_id, 0)))
		items_list.add_child(item_row)

	_update_pool_display()
	visible = true

	if confirm_button != null:
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
		var spinbox := SpinBox.new()
		spinbox.name = "SpinBox"
		spinbox.min_value = 0
		spinbox.max_value = required_qty
		spinbox.step = 1
		spinbox.value = mini(initial_val, required_qty)
		spinbox.custom_minimum_size = Vector2(96, 38)
		spinbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		spinbox.alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Theme the internal LineEdit
		var line_edit := spinbox.get_line_edit()
		if line_edit != null:
			line_edit.add_theme_font_override("font", FONT_LILITA)
			line_edit.add_theme_font_size_override("font_size", 16)
			line_edit.add_theme_color_override("font_color", Color(1.0, 0.780392, 0.172549, 1.0))
			line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER

		spinbox.value_changed.connect(_on_spinbox_value_changed.bind(item_id))
		hbox.add_child(spinbox)
		_spinboxes[item_id] = spinbox
	else:
		var lock_lbl := Label.new()
		lock_lbl.text = "🔒 Manual Only"
		lock_lbl.add_theme_font_override("font", FONT_LILITA)
		lock_lbl.add_theme_font_size_override("font_size", 13)
		lock_lbl.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58, 1.0))
		lock_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(lock_lbl)

	return row_panel


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
