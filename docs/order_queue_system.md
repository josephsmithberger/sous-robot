# Robot Waiter Order Queue

The kitchen now has a deterministic, endlessly wrapping line of three robot waiters outside the order window. Only the front robot can be interacted with. Talking to that robot generates its request from order data and adds the order to the receipt. Correct deliveries cross off individual item lines; completing every line pays the order and advances the queue.

## Editing the order cycle

Open `scenes/kitchen.tscn`, select the `OrderQueue` node, and expand **Order Cycle** in the Inspector. The exported array is read in order and wraps back to index zero after the last entry.

Each array entry is a dictionary with these keys:

| Key | Type | Purpose |
| --- | --- | --- |
| `items` | Dictionary | Maps a `KitchenItem.item_id` to the required positive quantity. |
| `base_reward` | Float | Guaranteed money paid when the order is completed. |
| `tip` | Float | Starting tip paid at completion. |
| `wrong_item_penalty` | Float | Cash removed immediately and tip removed when a wrong or extra item is delivered. |

Example:

```gdscript
{
    "items": {"bread": 1, "sliced_bread": 2},
    "base_reward": 5.0,
    "tip": 2.0,
    "wrong_item_penalty": 1.0,
}
```

The visible robots already hold their assigned upcoming dictionaries. When the front robot leaves, the remaining two animate forward and that same robot node wraps to the back with the next dictionary. No random selection is involved.

## Adding a new food item

1. Create a `KitchenItem` resource with a unique `item_id`, display name, and held scene.
2. Add that resource to the `OrderQueue` node's **Item Catalog** array.
3. Add the new `item_id` and quantity to any order's `items` dictionary.
4. Add the kitchen source/processor needed to produce that item.

The dialogue text and receipt label use the catalog's display name automatically. Unknown item IDs are ignored with a warning so an invalid order cannot block the line forever.

## Runtime flow

1. `WaiterRobot` exposes interaction only when it is at slot zero.
2. `OrderQueue` assigns the next order number and generates its item text from that waiter's dictionary. Every dialogue balloon is labeled **Robot Waiter**.
3. `dialogue/orders.dialogue` uses the inline mutation `[do GameControl.emit_signal("order_dialogue_confirmed")]` while the robot speaks.
4. `OrderQueue` receives the signal, opens the active order, and emits `order_started`.
5. `OrderWindow` accepts one held item only while an order is active and emits `item_delivered`.
6. Correct items emit `order_item_fulfilled`; wrong or extra items emit `order_penalized` and update money.
7. When every required quantity is fulfilled, the payout is applied, `order_completed` crosses off the receipt, and the queue advances.

`GameControl` is the shared event boundary and money source of truth. Current order logic does not need direct references to the game UI, which makes it safe to add timers, patience, recipes, reputation, multiple fulfillment stations, or save data later.

## Main files

- `scripts/order_queue.gd`: order cycle, item validation, generated wording, fulfillment, penalties, and queue rotation.
- `scripts/waiter_robot.gd`: front-slot interaction and robot animation/tween behavior.
- `scenes/waiter_robot.tscn`: robot model and interaction volume.
- `scripts/orders_receipt.gd`: event-driven receipt rows and item strike-through state.
- `scripts/game_control.gd`: global order signals, active-order gate, and money balance.
- `dialogue/orders.dialogue`: generated waiter line and inline signal mutation.
