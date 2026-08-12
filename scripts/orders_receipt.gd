extends PanelContainer

@onready var orders_list: VBoxContainer = %OrdersList
@onready var empty_state: Label = %EmptyState
@onready var order_count: Label = %OrderCount
@onready var total_earnings: Label = %TotalEarnings

var _next_order_id := 1
var _orders: Dictionary = {}


func _ready() -> void:
	clear_orders()


func add_order(dish_name: String, total: float, tip: float) -> int:
	var order_id := _next_order_id
	_next_order_id += 1

	var row := Control.new()
	row.name = "Order_%d" % order_id
	row.custom_minimum_size = Vector2(0.0, 34.0)
	row.set_meta("completed", false)

	var details := HBoxContainer.new()
	details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	details.add_theme_constant_override("separation", 3)
	row.add_child(details)

	var dish_label := Label.new()
	dish_label.name = "DishName"
	dish_label.text = dish_name
	dish_label.clip_text = true
	dish_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	dish_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dish_label.add_theme_font_size_override("font_size", 13)
	dish_label.add_theme_color_override("font_color", Color("2d2923"))
	details.add_child(dish_label)

	var total_label := Label.new()
	total_label.name = "OrderTotal"
	total_label.custom_minimum_size.x = 42.0
	total_label.text = "$%.2f" % total
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_label.add_theme_font_size_override("font_size", 12)
	total_label.add_theme_color_override("font_color", Color("2d2923"))
	details.add_child(total_label)

	var tip_label := Label.new()
	tip_label.name = "Tip"
	tip_label.custom_minimum_size.x = 36.0
	tip_label.text = "$%.2f" % tip
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip_label.add_theme_font_size_override("font_size", 12)
	tip_label.add_theme_color_override("font_color", Color("c3472d"))
	details.add_child(tip_label)

	var strike := ColorRect.new()
	strike.name = "StrikeThrough"
	strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike.color = Color("2d2923")
	strike.set_anchors_preset(Control.PRESET_CENTER)
	strike.anchor_left = 0.0
	strike.anchor_right = 1.0
	strike.offset_top = -1.0
	strike.offset_bottom = 1.0
	strike.visible = false
	row.add_child(strike)

	orders_list.add_child(row)
	_orders[order_id] = {
		"row": row,
		"total": maxf(total, 0.0),
		"tip": maxf(tip, 0.0),
	}
	empty_state.visible = false
	_recalculate_earnings()
	return order_id


func set_order_completed(order_id: int, completed: bool = true) -> void:
	if not _orders.has(order_id):
		push_warning("Receipt order %d does not exist." % order_id)
		return

	var row := _orders[order_id]["row"] as Control
	row.set_meta("completed", completed)
	row.get_node("StrikeThrough").visible = completed
	row.modulate = Color(0.48, 0.45, 0.40, 1.0) if completed else Color.WHITE
	_recalculate_earnings()


func clear_orders() -> void:
	for child in orders_list.get_children():
		child.queue_free()
	_orders.clear()
	_next_order_id = 1
	empty_state.visible = true
	_recalculate_earnings()


func _recalculate_earnings() -> void:
	var earnings := 0.0
	var completed_count := 0
	for order: Dictionary in _orders.values():
		var row := order["row"] as Control
		if row.get_meta("completed", false):
			completed_count += 1
			earnings += float(order["total"]) + float(order["tip"])
	order_count.text = "%d ORDERS · %d DONE" % [_orders.size(), completed_count]
	total_earnings.text = "$%.2f" % earnings
