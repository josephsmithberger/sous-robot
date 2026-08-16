extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")

func _ready() -> void:
	GameControl.reset_session(100.0)
	var game = GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var tabs: TabContainer = game.get_node("MarginContainer/HSplitContainer/TabContainer")
	var store = tabs.get_node("Store")
	var kitchen = tabs.get_node("Kitchen/PanelContainer/VBoxContainer/InteractionStage/SubViewportContainer/SubViewport/kitchen")
	var placement_manager: PlacementManager = kitchen.get_node("PlacementManager") as PlacementManager
	
	tabs.current_tab = 1 # Switch to Store tab
	await get_tree().process_frame
	
	var counter_card: Button = store.get_node("Scroll/Grid/Counter")
	assert(counter_card != null, "Counter card must exist in Store grid.")
	assert(not counter_card.disabled, "Counter card must be enabled when unaffiliated/unowned.")
	
	var title_lbl: Label = counter_card.get_node("Content/Title")
	var price_lbl: Label = counter_card.get_node("Content/Price")
	var desc_lbl: Label = counter_card.get_node("Content/Description")
	assert(title_lbl.text == "Counter", "Title must be Counter.")
	assert(price_lbl.text == "$50", "Price must be $50.")
	assert(desc_lbl.text.containsn("combining"), "Description must mention combining.")
	
	# Press counter card
	store._on_card_pressed(counter_card)
	assert(store.purchase_dialog.visible or store.purchase_dialog.title.containsn("Counter"), "Purchase dialog must be active for Counter.")
	
	store._on_purchase_confirmed()
	await get_tree().process_frame
	
	assert(is_equal_approx(GameControl.money, 50.0), "Balance should be $50 ($100 - $50).")
	assert(GameControl.is_item_owned(&"Counter"), "Counter must be marked owned.")
	assert(GameControl.is_placing, "GameControl should be in placement mode.")
	assert(placement_manager.active_ghost != null, "Active ghost should exist for Counter.")
	
	# Place counter at valid location
	var valid_spot := Vector3(0.0, 0.0, -2.0)
	placement_manager.set_ghost_position(valid_spot)
	var confirmed := placement_manager.confirm_placement()
	assert(confirmed, "Placement of Counter should be confirmed.")
	assert(not GameControl.is_placing, "Placement mode should be finished.")
	
	print("TEST_COUNTER_STORE_PASS")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
