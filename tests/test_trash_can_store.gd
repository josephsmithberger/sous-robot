extends Node

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")

func _ready() -> void:
	var game = GAME_SCENE.instantiate()
	add_child(game)
	GameControl.reset_session(20.0)
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var tabs: TabContainer = game.get_node("MarginContainer/HSplitContainer/TabContainer")
	var store = tabs.get_node("Store")
	var kitchen = tabs.get_node("Kitchen/PanelContainer/VBoxContainer/InteractionStage/SubViewportContainer/SubViewport/kitchen")
	var placement_manager: PlacementManager = kitchen.get_node("PlacementManager") as PlacementManager
	
	tabs.current_tab = 1 # Switch to Store tab
	await get_tree().process_frame
	
	var trash_card: Button = store.get_node("Scroll/Grid/TrashCan")
	assert(trash_card != null, "TrashCan card must exist in Store grid.")
	assert(not trash_card.disabled, "TrashCan card must be enabled when unowned.")
	
	var title_lbl: Label = trash_card.get_node("Content/Title")
	var price_lbl: Label = trash_card.get_node("Content/Price")
	var desc_lbl: Label = trash_card.get_node("Content/Description")
	var thumb: TextureRect = trash_card.get_node("Content/Thumbnail")
	
	assert(title_lbl.text == "Trash Can", "Title must be 'Trash Can'.")
	assert(price_lbl.text == "$5", "Price must be '$5'.")
	assert(desc_lbl.text.containsn("trash") or desc_lbl.text.containsn("discarding"), "Description must mention discarding/trash.")
	assert(thumb.texture != null, "Thumbnail texture must not be null.")
	
	# Press TrashCan card
	store._on_card_pressed(trash_card)
	assert(store.purchase_dialog.visible or store.purchase_dialog.title.containsn("Trash Can"), "Purchase dialog must be active for Trash Can.")
	
	# Confirm purchase ($5.00)
	store._on_purchase_confirmed()
	await get_tree().process_frame
	
	assert(is_equal_approx(GameControl.money, 15.0), "Balance should be $15 ($20 - $5).")
	assert(GameControl.is_item_owned(&"TrashCan"), "TrashCan must be marked owned.")
	assert(GameControl.is_placing, "GameControl should be in placement mode.")
	assert(placement_manager.active_ghost != null, "Active ghost should exist for TrashCan.")
	assert(placement_manager.active_item_id == &"TrashCan", "Active placing item should be TrashCan.")
	
	# Place TrashCan at valid location
	var valid_spot := Vector3(1.0, 0.0, -3.0)
	placement_manager.set_ghost_position(valid_spot)
	var confirmed := placement_manager.confirm_placement()
	assert(confirmed, "Placement of TrashCan should be confirmed.")
	assert(not GameControl.is_placing, "Placement mode should be finished.")
	
	# Verify placed item in scene
	var placed_items := get_tree().get_nodes_in_group(&"placed_items")
	var found_trash := false
	var placed_trash_node: Node3D = null
	for node in placed_items:
		if node is Node3D and node.get_meta(&"item_id", &"") == &"TrashCan":
			found_trash = true
			placed_trash_node = node as Node3D
			assert(node.global_position.distance_to(valid_spot) < 0.6, "TrashCan position must match placement spot.")
	assert(found_trash, "TrashCan must be found in placed_items group.")
	
	# Test picking up and rearranging the placed trash can
	var picked := placement_manager.pick_up_item(placed_trash_node)
	assert(picked, "Placed TrashCan must be pickable in edit/rearrange mode.")
	assert(GameControl.is_placing, "Must enter placement mode on pick up.")
	
	var new_spot := Vector3(1.0, 0.0, -5.0)
	placement_manager.set_ghost_position(new_spot)
	var moved := placement_manager.confirm_placement()
	assert(moved, "TrashCan should be repositionable to new spot.")
	assert(placed_trash_node.global_position.distance_to(new_spot) < 0.6, "TrashCan must move to new position.")

	# Test interacting with the placed trash can to clear hands
	var trash_area: TrashCan = placed_trash_node.get_node_or_null("trash") as TrashCan
	assert(trash_area != null, "Placed TrashCan node must have 'trash' Area3D of type TrashCan.")

	var player: PlayerController = kitchen.get_node("player") as PlayerController
	assert(player != null, "Player must exist in kitchen scene.")

	# Give player a bun from crate
	var bun_item: KitchenItem = preload("res://resources/items/bread.tres")
	player.set_held_item(bun_item)
	assert(player.has_held_item(), "Player should be holding an item.")
	assert(trash_area.can_interact(player), "TrashCan should be interactable when player holds an item.")
	assert(trash_area.get_interaction_prompt(player) == "TRASH BREAD", "Prompt should be 'TRASH BREAD'.")

	trash_area.interact(player)
	await get_tree().process_frame

	assert(not player.has_held_item(), "Player hands should be cleared after interacting with trash can.")
	assert(not trash_area.can_interact(player), "TrashCan should no longer be interactable when hands are empty.")
	
	print("TEST_TRASH_CAN_STORE_PASS")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0)
