extends Control
## Store UI controller for purchasing appliances and kitchen upgrades.

const DEFAULT_PRICES: Dictionary = {
	&"DecoratedWall": 0.0,
	&"BunCrate": 0.0,
	&"CarrotCrate": 15.0,
	&"CheeseCrate": 22.50,
	&"HamCrate": 27.50,
	&"LettuceCrate": 15.0,
	&"OnionCrate": 15.0,
	&"PotatoCrate": 15.0,
	&"SteakCrate": 37.50,
	&"TomatoCrate": 15.0,
	&"Fridge": 150.0,
	&"Oven": 180.0,
	&"Sink": 100.0,
	&"Counter": 50.0,
	&"TrashCan": 5.0,
}

@onready var purchase_dialog: ConfirmationDialog = $PurchaseDialog

var _pending_card: Button
var _cards: Array[Button] = []


func _ready() -> void:
	GameControl.money_changed.connect(_on_money_changed)
	GameControl.item_unlocked.connect(_on_item_unlocked)
	_setup_cards()
	_refresh_all_cards()


func _exit_tree() -> void:
	if GameControl.money_changed.is_connected(_on_money_changed):
		GameControl.money_changed.disconnect(_on_money_changed)
	if GameControl.item_unlocked.is_connected(_on_item_unlocked):
		GameControl.item_unlocked.disconnect(_on_item_unlocked)


func _setup_cards() -> void:
	_cards.clear()
	var raw_cards := get_tree().get_nodes_in_group("store_cards")
	for node in raw_cards:
		if node is not Button:
			continue
		var card := node as Button
		_cards.append(card)

		var item_id := StringName(card.name)
		var title_label := card.get_node_or_null("Content/Title") as Label
		var price_label := card.get_node_or_null("Content/Price") as Label
		var title := title_label.text if title_label != null else str(item_id).capitalize()

		var is_starter := false
		var price := 0.0

		if price_label != null and price_label.text.containsn("Owned"):
			is_starter = true
			price = 0.0
			GameControl.unlock_item(item_id)
		elif DEFAULT_PRICES.has(item_id):
			price = float(DEFAULT_PRICES[item_id])
		elif price_label != null:
			var cleaned := price_label.text.replace("$", "").strip_edges()
			price = float(cleaned) if cleaned.is_valid_float() else 0.0

		card.set_meta(&"item_id", item_id)
		card.set_meta(&"title", title)
		card.set_meta(&"price", price)
		card.set_meta(&"is_starter", is_starter)
		card.set_meta(&"price_label", price_label)

		if not card.pressed.is_connected(_on_card_pressed):
			card.pressed.connect(_on_card_pressed.bind(card))


func _refresh_all_cards() -> void:
	for card in _cards:
		_refresh_card_state(card)


func _refresh_card_state(card: Button) -> void:
	if not is_instance_valid(card) or not card.has_meta(&"item_id"):
		return

	var item_id: StringName = card.get_meta(&"item_id")
	var title: String = card.get_meta(&"title", str(item_id))
	var price: float = float(card.get_meta(&"price", 0.0))
	var is_starter: bool = bool(card.get_meta(&"is_starter", false))
	var price_label: Label = card.get_meta(&"price_label") as Label

	if GameControl.is_item_owned(item_id):
		card.disabled = true
		card.modulate = Color(0.5, 0.5, 0.5, 1.0)
		card.tooltip_text = "%s (Owned)" % title
		if price_label != null:
			price_label.text = "Owned (Starter item)" if is_starter else "Owned"
			price_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1.0))
		return

	card.disabled = false
	var formatted_price := "$%.2f" % price if fmod(price, 1.0) != 0.0 else "$%d" % int(price)

	if GameControl.can_afford(price):
		card.modulate = Color.WHITE
		card.tooltip_text = "Click to buy %s for %s" % [title, formatted_price]
		if price_label != null:
			price_label.text = formatted_price
			price_label.add_theme_color_override("font_color", Color(0.33, 0.65, 0.19, 1.0))
	else:
		card.modulate = Color(0.9, 0.9, 0.9, 0.95)
		var missing := price - GameControl.money
		card.tooltip_text = "%s: %s (Need $%.2f more)" % [title, formatted_price, missing]
		if price_label != null:
			price_label.text = formatted_price
			price_label.add_theme_color_override("font_color", Color(0.84, 0.25, 0.20, 1.0))


func _on_card_pressed(card: Button) -> void:
	SFX.play_click()
	_pending_card = card
	if not is_instance_valid(card) or not card.has_meta(&"item_id"):
		return

	var item_id: StringName = card.get_meta(&"item_id")
	if GameControl.is_item_owned(item_id):
		_pending_card = null
		return

	var title: String = card.get_meta(&"title", str(item_id))
	var price: float = float(card.get_meta(&"price", 0.0))
	card.modulate = Color(0.6, 0.6, 0.6, 1.0)

	var ok_button := purchase_dialog.get_ok_button()
	if GameControl.can_afford(price):
		purchase_dialog.title = "Purchase %s" % title
		var balance_after := maxf(GameControl.money - price, 0.0)
		purchase_dialog.dialog_text = "Would you like to buy %s for $%.2f?\n\nCurrent Balance: $%.2f\nRemaining Balance: $%.2f" % [
			title,
			price,
			GameControl.money,
			balance_after
		]
		purchase_dialog.ok_button_text = "Buy ($%.2f)" % price
		if ok_button != null:
			ok_button.disabled = false
	else:
		purchase_dialog.title = "Insufficient Funds"
		var missing := price - GameControl.money
		purchase_dialog.dialog_text = "You cannot afford %s yet!\n\nItem Price: $%.2f\nCurrent Balance: $%.2f\nMissing: $%.2f" % [
			title,
			price,
			GameControl.money,
			missing
		]
		purchase_dialog.ok_button_text = "Cannot Afford"
		if ok_button != null:
			ok_button.disabled = true

	purchase_dialog.popup_centered()


func _on_purchase_confirmed() -> void:
	if _pending_card == null or not is_instance_valid(_pending_card):
		_pending_card = null
		return

	var item_id: StringName = _pending_card.get_meta(&"item_id")
	var title: String = _pending_card.get_meta(&"title", str(item_id))
	var price: float = float(_pending_card.get_meta(&"price", 0.0))

	if GameControl.spend_money(price, "BOUGHT %s" % title.to_upper()):
		GameControl.unlock_item(item_id)
		_refresh_all_cards()
		GameControl.request_tab_switch(0)
		GameControl.start_placement(item_id)
	else:
		_refresh_card_state(_pending_card)

	_pending_card = null


func _on_purchase_canceled() -> void:
	SFX.play_click()
	if _pending_card != null and is_instance_valid(_pending_card):
		_refresh_card_state(_pending_card)
	_pending_card = null


func _on_money_changed(_balance: float, _delta: float, _reason: String) -> void:
	_refresh_all_cards()


func _on_item_unlocked(_item_id: StringName) -> void:
	_refresh_all_cards()
