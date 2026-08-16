extends PanelContainer
## Event-driven receipt. Orders and item progress arrive from GameControl.

const MAX_VISIBLE_ORDERS := 8

@onready var orders_scroll: ScrollContainer = %OrdersScroll
@onready var orders_list: VBoxContainer = %OrdersList
@onready var empty_state: Label = %EmptyState
@onready var order_count: Label = %OrderCount
@onready var total_earnings: Label = %TotalEarnings

var _orders: Dictionary = {}
var _completed_order_ids: Array[int] = []
var _scroll_tween: Tween


func _ready() -> void:
	clear_orders()
	GameControl.order_started.connect(_on_order_started)
	GameControl.order_timer_updated.connect(_on_order_timer_updated)
	GameControl.order_item_fulfilled.connect(_on_order_item_fulfilled)
	GameControl.order_penalized.connect(_on_order_penalized)
	GameControl.order_completed.connect(_on_order_completed)
	GameControl.money_changed.connect(_on_money_changed)
	_on_money_changed(GameControl.money, 0.0, "")


func _exit_tree() -> void:
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	if GameControl.order_started.is_connected(_on_order_started):
		GameControl.order_started.disconnect(_on_order_started)
	if GameControl.order_timer_updated.is_connected(_on_order_timer_updated):
		GameControl.order_timer_updated.disconnect(_on_order_timer_updated)
	if GameControl.order_item_fulfilled.is_connected(_on_order_item_fulfilled):
		GameControl.order_item_fulfilled.disconnect(_on_order_item_fulfilled)
	if GameControl.order_penalized.is_connected(_on_order_penalized):
		GameControl.order_penalized.disconnect(_on_order_penalized)
	if GameControl.order_completed.is_connected(_on_order_completed):
		GameControl.order_completed.disconnect(_on_order_completed)
	if GameControl.money_changed.is_connected(_on_money_changed):
		GameControl.money_changed.disconnect(_on_money_changed)


func add_order(order_id: int, order: Dictionary) -> void:
	if _orders.has(order_id):
		return

	var order_panel := VBoxContainer.new()
	order_panel.name = "Order_%d" % order_id
	order_panel.add_theme_constant_override("separation", 1)

	var header := _make_line_control(20.0)
	var header_details := header.get_node("Details") as HBoxContainer
	var order_label := _make_label("ORDER #%02d" % order_id, 11)
	order_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_details.add_child(order_label)

	var total_label := _make_label("$%.2f" % _projected_total(order), 10)
	total_label.name = "OrderTotal"
	total_label.custom_minimum_size.x = 38.0
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_details.add_child(total_label)

	var tip_label := _make_label("$%.2f" % float(order.get("tip", 0.0)), 10)
	tip_label.name = "Tip"
	tip_label.custom_minimum_size.x = 30.0
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tip_label.add_theme_color_override("font_color", Color("c3472d"))
	header_details.add_child(tip_label)
	order_panel.add_child(header)

	var item_rows: Dictionary = {}
	var items: Dictionary = order.get("items", {})
	var item_names: Dictionary = order.get("item_names", {})
	for raw_id: Variant in items:
		var item_id := StringName(str(raw_id))
		var required := int(items[raw_id])
		var item_row := _make_line_control(17.0)
		var item_details := item_row.get_node("Details") as HBoxContainer
		var item_label := _make_label(
			"  0/%d · %s" % [required, str(item_names.get(item_id, str(item_id).capitalize()))],
			10
		)
		item_label.name = "ItemLabel"
		item_label.clip_text = true
		item_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_details.add_child(item_label)
		order_panel.add_child(item_row)
		item_rows[item_id] = {
			"row": item_row,
			"label": item_label,
			"required": required,
			"display_name": str(item_names.get(item_id, str(item_id).capitalize())),
		}

	var separator := HSeparator.new()
	separator.modulate = Color(0.18, 0.16, 0.14, 0.35)
	order_panel.add_child(separator)
	orders_list.add_child(order_panel)
	_orders[order_id] = {
		"row": order_panel,
		"header": header,
		"item_rows": item_rows,
		"total_label": total_label,
		"tip_label": tip_label,
		"base_reward": float(order.get("base_reward", 0.0)),
		"tip": float(order.get("tip", 0.0)),
		"completed": false,
	}
	empty_state.visible = false
	_refresh_count()
	_scroll_to_bottom(true)


func set_order_item_completed(order_id: int, item_id: StringName, fulfilled: int, required: int) -> void:
	if not _orders.has(order_id):
		return
	var item_rows: Dictionary = _orders[order_id]["item_rows"]
	if not item_rows.has(item_id):
		return
	var item_data: Dictionary = item_rows[item_id]
	var item_label := item_data["label"] as Label
	item_label.text = "  %d/%d · %s" % [fulfilled, required, str(item_data["display_name"])]
	var item_row := item_data["row"] as Control
	item_row.get_node("StrikeThrough").visible = fulfilled >= required
	item_row.modulate = Color(0.52, 0.49, 0.44, 1.0) if fulfilled >= required else Color.WHITE
	_ensure_order_visible(order_id)


func set_order_completed(order_id: int, completed: bool = true) -> void:
	if not _orders.has(order_id):
		return
	var order: Dictionary = _orders[order_id]
	order["completed"] = completed
	var header := order["header"] as Control
	header.get_node("StrikeThrough").visible = completed
	var row := order["row"] as Control
	row.modulate = Color(0.48, 0.45, 0.40, 1.0) if completed else Color.WHITE
	for item_data: Dictionary in (order["item_rows"] as Dictionary).values():
		(item_data["row"] as Control).get_node("StrikeThrough").visible = completed
	_refresh_count()
	_ensure_order_visible(order_id)


func clear_orders() -> void:
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	if is_instance_valid(orders_scroll):
		orders_scroll.scroll_vertical = 0
	for child in orders_list.get_children():
		child.queue_free()
	_orders.clear()
	_completed_order_ids.clear()
	empty_state.visible = true
	_refresh_count()


func _on_order_started(order_id: int, order: Dictionary) -> void:
	add_order(order_id, order)


func _on_order_timer_updated(order_id: int, _elapsed: float, _max_time: float, current_tip: float, _urgency: float) -> void:
	if not _orders.has(order_id):
		return
	var order: Dictionary = _orders[order_id]
	if bool(order.get("completed", false)):
		return
	order["tip"] = current_tip
	var tip_label := order["tip_label"] as Label
	tip_label.text = "$%.2f" % current_tip
	var total_label := order["total_label"] as Label
	total_label.text = "$%.2f" % (float(order["base_reward"]) + current_tip)


func _on_order_item_fulfilled(order_id: int, item_id: StringName, fulfilled: int, required: int) -> void:
	set_order_item_completed(order_id, item_id, fulfilled, required)


func _on_order_penalized(order_id: int, remaining_tip: float, _penalty: float, _item_name: String) -> void:
	if not _orders.has(order_id):
		return
	var order: Dictionary = _orders[order_id]
	order["tip"] = remaining_tip
	var tip_label := order["tip_label"] as Label
	tip_label.text = "$%.2f" % remaining_tip
	tip_label.modulate = Color("d62318")
	var total_label := order["total_label"] as Label
	total_label.text = "$%.2f" % (float(order["base_reward"]) + remaining_tip)
	_ensure_order_visible(order_id)


func _on_order_completed(order_id: int, _payout: float, final_tip: float) -> void:
	if not _orders.has(order_id):
		return
	var order: Dictionary = _orders[order_id]
	order["tip"] = final_tip
	(order["tip_label"] as Label).text = "$%.2f" % final_tip
	set_order_completed(order_id, true)
	_completed_order_ids.append(order_id)
	_prune_old_orders()


func _on_money_changed(balance: float, _delta: float, _reason: String) -> void:
	total_earnings.text = "$%.2f" % balance


func _scroll_to_bottom(animated: bool = true) -> void:
	if not is_instance_valid(orders_scroll):
		return
	await get_tree().process_frame
	if not is_instance_valid(orders_scroll) or not is_inside_tree():
		return
	var v_bar := orders_scroll.get_v_scroll_bar()
	var target: float = maxf(v_bar.max_value - v_bar.page, 0.0)
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	if animated:
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(orders_scroll, "scroll_vertical", int(target), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		orders_scroll.scroll_vertical = int(target)


func _ensure_order_visible(order_id: int) -> void:
	if not _orders.has(order_id) or not is_instance_valid(orders_scroll):
		return
	await get_tree().process_frame
	if not _orders.has(order_id) or not is_instance_valid(orders_scroll) or not is_inside_tree():
		return
	var row := _orders[order_id]["row"] as Control
	if not is_instance_valid(row):
		return
	var order_top := row.position.y
	var order_bottom := row.position.y + row.size.y
	var current_scroll := float(orders_scroll.scroll_vertical)
	var view_height := orders_scroll.size.y
	var target := current_scroll
	if order_bottom > current_scroll + view_height:
		target = order_bottom - view_height
	elif order_top < current_scroll:
		target = order_top

	var v_bar := orders_scroll.get_v_scroll_bar()
	var max_scroll := maxf(v_bar.max_value - v_bar.page, 0.0)
	target = clampf(target, 0.0, max_scroll)

	if not is_equal_approx(target, current_scroll):
		if _scroll_tween and _scroll_tween.is_valid():
			_scroll_tween.kill()
		_scroll_tween = create_tween()
		_scroll_tween.tween_property(orders_scroll, "scroll_vertical", int(target), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _make_line_control(height: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(0.0, height)

	var details := HBoxContainer.new()
	details.name = "Details"
	details.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	details.add_theme_constant_override("separation", 2)
	row.add_child(details)

	var strike := ColorRect.new()
	strike.name = "StrikeThrough"
	strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike.color = Color("2d2923")
	strike.anchor_left = 0.0
	strike.anchor_top = 0.5
	strike.anchor_right = 1.0
	strike.anchor_bottom = 0.5
	strike.offset_top = -1.0
	strike.offset_bottom = 1.0
	strike.visible = false
	row.add_child(strike)
	return row


func _make_label(label_text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("2d2923"))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _projected_total(order: Dictionary) -> float:
	return float(order.get("base_reward", 0.0)) + float(order.get("tip", 0.0))


func _refresh_count() -> void:
	var completed_count := 0
	for order: Dictionary in _orders.values():
		if bool(order.get("completed", false)):
			completed_count += 1
	order_count.text = "%d ORDERS · %d DONE" % [_orders.size(), completed_count]


func _prune_old_orders() -> void:
	while _completed_order_ids.size() > MAX_VISIBLE_ORDERS:
		var old_id: int = _completed_order_ids.pop_front()
		if not _orders.has(old_id):
			continue
		var old_row := _orders[old_id]["row"] as Control
		old_row.queue_free()
		_orders.erase(old_id)
	_refresh_count()

