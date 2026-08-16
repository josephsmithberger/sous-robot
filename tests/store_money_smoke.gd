extends Node

const STORE_SCENE: PackedScene = preload("res://scenes/store.tscn")


func _ready() -> void:
	# 1. Reset session and check starter state
	GameControl.reset_session(0.0)
	assert(is_equal_approx(GameControl.money, 0.0), "Initial session balance must be $0.00.")
	assert(GameControl.is_item_owned(&"DecoratedWall"), "DecoratedWall must be a starter owned item.")
	assert(GameControl.is_item_owned(&"BunCrate"), "BunCrate must be a starter owned item.")
	assert(not GameControl.is_item_owned(&"CarrotCrate"), "CarrotCrate must not be owned initially.")

	# 2. Instantiate the Store UI
	var store = STORE_SCENE.instantiate()
	add_child(store)
	await get_tree().process_frame

	var decorated_wall_card: Button = store.get_node("Scroll/Grid/DecoratedWall")
	var bun_card: Button = store.get_node("Scroll/Grid/BunCrate")
	var carrot_card: Button = store.get_node("Scroll/Grid/CarrotCrate")
	var cheese_card: Button = store.get_node("Scroll/Grid/CheeseCrate")
	var ham_card: Button = store.get_node("Scroll/Grid/HamCrate")
	var fridge_card: Button = store.get_node("Scroll/Grid/Fridge")

	assert(decorated_wall_card.disabled, "Decorated Wall starter card must be disabled.")
	assert(bun_card.disabled, "Bun Crate starter card must be disabled.")
	assert(not carrot_card.disabled, "Unowned Carrot Crate card should be clickable for inspection.")

	# 3. Test unaffordable state with $0.00 balance
	assert(not GameControl.can_afford(15.0), "Player cannot afford $15 with $0 balance.")
	var spend_failed := GameControl.spend_money(15.0, "ILLEGAL BUY")
	assert(not spend_failed, "spend_money must return false when balance is insufficient.")
	assert(is_equal_approx(GameControl.money, 0.0), "Balance must remain unchanged after failed spend.")

	# 4. Test clicking an unaffordable card opens insufficient funds dialog with disabled OK button
	store._on_card_pressed(carrot_card)
	var dialog: ConfirmationDialog = store.purchase_dialog
	assert(dialog.title == "Insufficient Funds", "Dialog title must be 'Insufficient Funds' when balance is too low.")
	assert(dialog.get_ok_button().disabled, "OK button must be disabled when funds are insufficient.")
	store._on_purchase_canceled()
	assert(not carrot_card.disabled, "Carrot card must remain active after cancel.")

	# 5. Earn money from gameplay / add funds
	GameControl.change_money(25.0, "ORDER PAYOUT")
	await get_tree().process_frame
	assert(is_equal_approx(GameControl.money, 25.0), "Balance must reflect $25.00 earnings.")
	assert(GameControl.can_afford(15.0), "Player must be able to afford $15.00 item with $25.00 balance.")
	assert(not GameControl.can_afford(27.50), "Player must not be able to afford $27.50 item with $25.00 balance.")

	# 6. Purchase Carrot Crate ($15.00)
	store._on_card_pressed(carrot_card)
	assert(dialog.title == "Purchase Carrot Crate", "Dialog title must prompt to purchase when affordable.")
	assert(not dialog.get_ok_button().disabled, "OK button must be enabled when affordable.")

	store._on_purchase_confirmed()
	await get_tree().process_frame

	assert(is_equal_approx(GameControl.money, 10.0), "Balance must be $10.00 after purchasing $15.00 Carrot Crate ($25 - $15).")
	assert(GameControl.is_item_owned(&"CarrotCrate"), "CarrotCrate must now be marked as owned in GameControl.")
	assert(carrot_card.disabled, "Carrot Crate card must be disabled after purchase.")
	var carrot_price_label: Label = carrot_card.get_node("Content/Price")
	assert(carrot_price_label.text == "Owned", "Carrot Crate price label must show 'Owned'.")

	# 7. Verify remaining $10.00 gates other items
	assert(not GameControl.can_afford(22.50), "Cannot afford Cheese Crate ($22.50) with $10.")
	assert(not GameControl.can_afford(150.0), "Cannot afford Fridge ($150) with $10.")

	# 8. Add more funds and buy Ham Crate ($27.50)
	GameControl.change_money(17.50, "MORE EARNINGS") # balance = $27.50
	await get_tree().process_frame
	assert(is_equal_approx(GameControl.money, 27.50), "Balance must now be $27.50 ($10 + $17.50).")
	assert(GameControl.can_afford(27.50), "Player must be able to afford $27.50 Ham Crate.")

	store._on_card_pressed(ham_card)
	store._on_purchase_confirmed()
	await get_tree().process_frame

	assert(is_equal_approx(GameControl.money, 0.0), "Balance must be $0.00 after purchasing $27.50 Ham Crate ($27.50 - $27.50).")
	assert(GameControl.is_item_owned(&"HamCrate"), "HamCrate must now be marked as owned.")
	assert(ham_card.disabled, "Ham Crate card must be disabled after purchase.")

	print("STORE_MONEY_SMOKE_PASS balance=$%.2f owned=%s" % [GameControl.money, str(GameControl.owned_items)])
	get_tree().quit(0)
