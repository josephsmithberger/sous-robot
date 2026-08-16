extends Node

const KITCHEN_SCENE: PackedScene = preload("res://scenes/kitchen.tscn")
const COUNTER_SCENE: PackedScene = preload("res://assets/appliances/counter.tscn")
const BUN_ITEM: KitchenItem = preload("res://resources/items/bun.tres")
const TWO_BUNS_ITEM: KitchenItem = preload("res://resources/items/two_buns.tres")
const CARROT_ITEM: KitchenItem = preload("res://resources/items/carrot.tres")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

func _ready() -> void:
	print("Starting AssemblyCounter smoke test...")
	
	# Instantiate standalone counter and player
	var counter_node: Node3D = COUNTER_SCENE.instantiate()
	add_child(counter_node)
	
	var player: PlayerController = PLAYER_SCENE.instantiate()
	add_child(player)
	
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var spot1: AssemblyCounter = counter_node.get_node("counter") as AssemblyCounter
	var spot2: AssemblyCounter = counter_node.get_node("counter2") as AssemblyCounter
	assert(spot1 != null and spot2 != null, "Counter scene must have counter and counter2 Area3D AssemblyCounter nodes")
	
	# 1. Initially empty counter with empty player hands
	assert(not spot1.can_interact(player), "Empty counter should not allow interaction with empty hands")
	assert(spot1.get_interaction_prompt(player) == "", "Prompt should be empty")
	
	# 2. Player holding invalid starter item (e.g. carrot if no recipe starts with carrot)
	player.set_held_item(CARROT_ITEM)
	assert(not spot1.can_interact(player), "Counter should reject ingredient that does not start any recipe")
	assert(spot1.get_interaction_prompt(player) == "CANNOT COMBINE", "Prompt should indicate cannot combine")
	
	# 3. Player holding bun (valid starter ingredient)
	player.set_held_item(BUN_ITEM)
	assert(spot1.can_interact(player), "Counter should accept bun as recipe starter")
	assert(spot1.get_interaction_prompt(player) == "ADD BUN", "Prompt should be ADD BUN")
	
	# Add 1st bun
	spot1.interact(player)
	assert(not player.has_held_item(), "Player's hand should be emptied after adding bun")
	assert(spot1.is_in_progress(), "Counter should be in progress after 1 bun")
	assert(spot1.placed_items.size() == 1, "Counter should hold 1 item")
	assert(spot1.placed_items[0].item_id == &"bun", "Item on counter should be bun")
	
	# 4. Empty hands can retrieve in-progress item
	assert(spot1.can_interact(player), "Empty hands should be able to retrieve in-progress item")
	assert(spot1.get_interaction_prompt(player) == "TAKE BUN", "Prompt should be TAKE BUN to retrieve")
	spot1.interact(player)
	assert(player.is_holding(&"bun"), "Player should retrieve bun back into hands")
	assert(spot1.is_empty(), "Counter should now be empty after retrieving item")
	
	# 5. Place 1st bun again
	spot1.interact(player)
	assert(not player.has_held_item(), "Hands empty after placing 1st bun")
	assert(spot1.placed_items.size() == 1, "Counter has 1 bun")
	
	# 6. Place 2nd bun to complete Two Buns recipe
	player.set_held_item(BUN_ITEM)
	assert(spot1.can_interact(player), "Counter should accept 2nd bun")
	assert(spot1.get_interaction_prompt(player) == "ADD BUN", "Prompt should be ADD BUN")
	spot1.interact(player)
	assert(not player.has_held_item(), "Hands empty after adding 2nd bun")
	assert(spot1.is_completed(), "Counter should be completed after 2 buns")
	assert(spot1.completed_item != null, "Completed item should not be null")
	assert(spot1.completed_item.item_id == &"two_buns", "Completed item should be two_buns")
	
	# 7. Take completed Two Buns dish
	player.set_held_item(CARROT_ITEM)
	assert(not spot1.can_interact(player), "Cannot take completed dish if hands are full")
	assert(spot1.get_interaction_prompt(player) == "HANDS FULL", "Prompt should say HANDS FULL")
	player.set_held_item(null)
	
	assert(spot1.can_interact(player), "Empty hands should be able to take completed dish")
	assert(spot1.get_interaction_prompt(player) == "TAKE TWO BUNS", "Prompt should say TAKE TWO BUNS")
	spot1.interact(player)
	assert(player.is_holding(&"two_buns"), "Player should now hold two_buns")
	assert(spot1.is_empty(), "Counter should be empty after taking dish")
	
	# 8. Test spot2 (second interaction area) independently
	player.set_held_item(BUN_ITEM)
	spot2.interact(player)
	assert(spot2.placed_items.size() == 1, "Spot2 should have 1 bun")
	assert(spot1.is_empty(), "Spot1 should remain empty while Spot2 is in use")
	
	# 9. Test automatic reset on new order
	player.set_held_item(BUN_ITEM)
	spot1.interact(player) # spot1 has 1 bun
	assert(spot1.placed_items.size() == 1, "Spot1 has 1 bun before order start")
	assert(spot2.placed_items.size() == 1, "Spot2 has 1 bun before order start")
	
	# Emit order started signal
	GameControl.order_started.emit(42, {})
	assert(spot1.is_empty(), "Spot1 should be reset when order starts")
	assert(spot2.is_empty(), "Spot2 should be reset when order starts")
	assert(spot1._visual_instances.is_empty(), "Visuals on spot1 should be cleaned up")
	assert(spot2._visual_instances.is_empty(), "Visuals on spot2 should be cleaned up")
	
	print("ASSEMBLY_COUNTER_SMOKE_PASS")
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0)
