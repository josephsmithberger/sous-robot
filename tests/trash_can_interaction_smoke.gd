extends Node

const TRASH_CAN_SCENE: PackedScene = preload("res://assets/appliances/trash_can.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

const ITEM_BREAD: KitchenItem = preload("res://resources/items/bread.tres")
const ITEM_CHEESE: KitchenItem = preload("res://resources/items/cheese.tres")
const ITEM_CHEESEBURGER: KitchenItem = preload("res://resources/items/cheeseburger.tres")
const ITEM_STEAK_DINNER: KitchenItem = preload("res://resources/items/steak_dinner.tres")
const ITEM_CARROT_WASHED: KitchenItem = preload("res://resources/items/carrot_washed.tres")


func _ready() -> void:
	GameControl.reset_session()
	GameControl.set_controllable(true)
	GameControl.give_player_control()

	var player: PlayerController = PLAYER_SCENE.instantiate() as PlayerController
	add_child(player)
	await get_tree().physics_frame

	var trash_instance: Node3D = TRASH_CAN_SCENE.instantiate() as Node3D
	add_child(trash_instance)
	await get_tree().physics_frame

	var trash_area: TrashCan = trash_instance.get_node_or_null("trash") as TrashCan
	assert(trash_area != null, "Trash can scene must contain 'trash' node of type TrashCan.")
	assert(trash_area.is_in_group(&"trash_cans"), "TrashCan must belong to 'trash_cans' group.")

	# 1. Verify empty hands cannot interact
	assert(not player.has_held_item(), "Player should start with empty hands.")
	assert(not trash_area.can_interact(player), "TrashCan should not be interactable when player hands are empty.")
	assert(trash_area.get_interaction_hold_duration(player) == 0.0, "TrashCan interaction should be instantaneous (hold duration 0).")

	# Test items sequence
	var test_items: Array[KitchenItem] = [
		ITEM_BREAD,
		ITEM_CHEESE,
		ITEM_CHEESEBURGER,
		ITEM_STEAK_DINNER,
		ITEM_CARROT_WASHED,
	]

	for item in test_items:
		var trashed_from_can: Array[KitchenItem] = []
		var trashed_from_game: Array[KitchenItem] = []

		var on_can_trashed := func(t_item: KitchenItem) -> void:
			trashed_from_can.append(t_item)
		var on_game_trashed := func(t_item: KitchenItem) -> void:
			trashed_from_game.append(t_item)

		trash_area.trashed.connect(on_can_trashed)
		GameControl.item_trashed.connect(on_game_trashed)

		# Give player item
		player.set_held_item(item)
		assert(player.has_held_item(), "Player should be holding item %s." % item.display_name)
		assert(player.get_held_item() == item, "Held item should match %s." % item.display_name)
		assert(player._held_item_visual != null, "Held item visual should be present for %s." % item.display_name)

		# Check trash can interact state and prompt
		assert(trash_area.can_interact(player), "TrashCan should be interactable when player holds %s." % item.display_name)
		var expected_prompt := "TRASH %s" % item.display_name.to_upper()
		assert(trash_area.get_interaction_prompt(player) == expected_prompt, "Expected prompt '%s', got '%s'" % [expected_prompt, trash_area.get_interaction_prompt(player)])

		# Simulate player entering trash can interaction area
		player._on_area_entered(trash_area)
		assert(GameControl.can_interact, "GameControl can_interact should be true when near trash can with held item.")
		assert(GameControl.interaction_prompt == expected_prompt, "GameControl prompt mismatch: expected '%s', got '%s'" % [expected_prompt, GameControl.interaction_prompt])

		# Trigger interaction to clear hands
		GameControl.request_interaction()
		await get_tree().physics_frame

		# Verify player hands are cleared
		assert(not player.has_held_item(), "Player hands must be empty after interacting with trash can.")
		assert(player.get_held_item() == null, "player.get_held_item() must be null after trashing.")
		assert(player._held_item_visual == null, "player._held_item_visual must be null after trashing.")

		# Verify signals fired
		assert(trashed_from_can.size() == 1 and trashed_from_can[0] == item, "TrashCan trashed signal not fired correctly.")
		assert(trashed_from_game.size() == 1 and trashed_from_game[0] == item, "GameControl item_trashed signal not fired correctly.")

		# Verify trash can can no longer be interacted with now that hands are empty
		assert(not trash_area.can_interact(player), "TrashCan must not be interactable after clearing hands.")
		assert(not GameControl.can_interact, "GameControl can_interact should be false after clearing hands.")
		assert(GameControl.interaction_prompt == "", "GameControl prompt should be cleared.")

		# Clean up connections
		trash_area.trashed.disconnect(on_can_trashed)
		GameControl.item_trashed.disconnect(on_game_trashed)
		player._on_area_exited(trash_area)

	trash_instance.queue_free()
	player.queue_free()

	print("TEST_TRASH_CAN_INTERACTION_SMOKE_PASS")
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0)
