# Bot Navigation & Appliance Setup Guide

This guide details how the Navigation Mesh (`NavigationRegion3D`), Kitchen Appliances, Crates, Counters, Trash Cans, Collision Layers, and Bot Agents are set up and interact in **Sous-Robot**.

---

## 1. Kitchen NavMesh Overview

The kitchen scene (`res://scenes/kitchen.tscn`) contains a `NavigationRegion3D` with a tuned `NavigationMesh`:

- **Agent Radius**: `0.35` (optimized for `0.75x` scaled bots).
- **Agent Height**: `1.5`
- **Agent Max Climb**: `0.25`
- **Agent Max Slope**: `45.0°`
- **Parsed Geometry**: `PARSED_GEOMETRY_BOTH` (Meshes and Static Colliders).
- **Collision Mask**: `Layer 1` (World / Static Obstacles).

### Dynamic NavMesh Rebaking
Whenever the player purchases or moves an appliance/crate in **Arrange Mode** (`PlacementManager`), `GameControl.placement_completed` automatically triggers `bake_navmesh()`, ensuring pathfinding routes dynamically adapt to kitchen changes in real-time.

---

## 2. Interaction Points & Access Rules

Bots should never navigate to an appliance's center coordinate because the center is inside the solid `StaticBody3D` collider (which is unnavigable). Instead, every object provides an **Interaction Position** situated on the walkable floor.

```
                  ┌────────────────────────────────────────────────────────┐
                  │                 INTERACTION POINT TYPES                │
                  └────────────────────────────────────────────────────────┘

    A) Specific Station / Appliance (with Marker3D)     B) 4-Sided Crates & Trash Can (Zero Markers!)
    wall_decorated (Node3D)                             crate_buns / trash_can (Node3D)
    ├── StaticBody3D (Layer 1)                          ├── StaticBody3D (Layer 1)
    ├── stove (Area3D - Layer 4)                        └── Area3D (Layer 4)
    │   └── InteractionPoint (Marker3D: -1.44, 0, 2.8)      └── [Dynamic 4-Side NavMesh Resolution]
    └── cutboard (Area3D - Layer 4)
        └── InteractionPoint (Marker3D: 0.83, 0, 2.9)
```

---

### Type A: Specific-Station & Single-Facing Appliances (`wall_decorated`, `oven`, `fridge`, `sink`, `counter`)
- Place an `InteractionPoint` (`Marker3D`) as a child of each specific `Area3D`.
- **Counter (`counter.tscn`)**:
  - Left station (`counter` Area3D): `InteractionPoint` is at `(-2.135, 0, 1.212)` in front of plate 1.
  - Right station (`counter2` Area3D): `InteractionPoint` is at `(0.056, 0, 1.212)` in front of plate 2.
- **Wall Decorated (`wall_decorated.tscn`)**:
  - `stove` Area3D: `InteractionPoint` is at `(-1.44, 0, 2.80)`.
  - `cutboard` Area3D: `InteractionPoint` is at `(0.83, 0, 2.91)`.

---

### Type B: Multi-Sided Accessible (Crates & Trash Can — **No Markers Needed!**)
Both ingredient crates (`ItemSource`) and trash cans (`TrashCan`) can be approached from **North, South, East, or West**.

- **Zero markers needed in the scenes.**
- `ItemSource.gd` and `TrashCan.gd` automatically calculate all 4 cardinal offsets and choose the **closest side that is unblocked on the NavMesh**:

```gdscript
# Built directly into res://scripts/trash_can.gd & item_source.gd:
const SIDE_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.0, 1.1),   # South / Front
	Vector3(0.0, 0.0, -1.1),  # North / Back
	Vector3(1.1, 0.0, 0.0),   # East / Right
	Vector3(-1.1, 0.0, 0.0),  # West / Left
]

func get_interaction_position(from_global_pos: Vector3 = Vector3.ZERO) -> Vector3:
	var world := get_world_3d()
	var nav_map := world.navigation_map if world != null else RID()
	var best_pos := global_position
	var shortest_dist_sq := INF

	for offset in SIDE_OFFSETS:
		var candidate_pos := global_transform * offset
		if nav_map.is_valid():
			var nav_pos := NavigationServer3D.map_get_closest_point(nav_map, candidate_pos)
			if candidate_pos.distance_squared_to(nav_pos) < 0.45:
				candidate_pos = nav_pos

		var dist_sq := from_global_pos.distance_squared_to(candidate_pos)
		if dist_sq < shortest_dist_sq:
			shortest_dist_sq = dist_sq
			best_pos = candidate_pos

	return best_pos
```

---

## 3. Appliance Setup Checklist

Every appliance and interactable in the kitchen requires:

```
ApplianceRoot (Node3D)
├── VisualModel (MeshInstance3D / glTF)
├── StaticBody3D (Physical Obstacle & NavMesh Blocker)
│   └── CollisionShape3D (BoxShape3D / CapsuleShape3D)
│       - Collision Layer: 1 (World)
│       - Collision Mask: 0
└── InteractionArea (Area3D - Trigger Zone)
    ├── CollisionShape3D (Slightly larger / extends into walkway)
    │   - Collision Layer: 4 (Interactions)
    │   - Collision Mask: 2 (Player) + 3 (Bots)
    └── InteractionPoint (Marker3D - Child of Area3D for fixed stations)
```

---

## 4. Collision Layer Matrix

To satisfy the design requirement:
> *"The bots will pass through each other, but collide with the player and walls."*

Set up the project collision layers in **Project Settings -> Layer Names -> 3D Physics**:

| Layer # | Name | Description |
| :--- | :--- | :--- |
| **Layer 1** | `World` | Static walls, floors, appliance `StaticBody3D` colliders |
| **Layer 2** | `Player` | Player `CharacterBody3D` |
| **Layer 3** | `Bots` | Bot `CharacterBody3D` instances |
| **Layer 4** | `Interactions` | `Area3D` triggers on crates, appliances, counters, trash can, window |

### Collision Layer / Mask Configuration:

- **Walls & Floor**:
  - `Collision Layer`: `1`
  - `Collision Mask`: `0`

- **Appliance `StaticBody3D`**:
  - `Collision Layer`: `1`
  - `Collision Mask`: `0`

- **Player (`CharacterBody3D`)**:
  - `Collision Layer`: `2`
  - `Collision Mask`: `1, 3` (Collides with World + Bots)

- **Bot (`CharacterBody3D`)**:
  - `Collision Layer`: `3`
  - `Collision Mask`: `1, 2` (Collides with World + Player — **excludes Layer 3 so bots pass through each other!**)

- **Appliance `Area3D` (Interaction Zone)**:
  - `Collision Layer`: `4`
  - `Collision Mask`: `0` (or monitoring for Layer 2 & 3)

---

## 5. Bot Entity Setup (`bot_worker.tscn`)

When creating the worker bot scene:

1. **Root**: `CharacterBody3D`
   - `Scale`: `Vector3(0.75, 0.75, 0.75)`
   - `Collision Layer`: `3` (Bots)
   - `Collision Mask`: `1, 2` (World + Player)
2. **Model**: Robot visual model (`robot.glb` / `AnimationPlayer`)
3. **`NavigationAgent3D`**:
   - `path_desired_distance`: `0.4`
   - `target_desired_distance`: `0.6`
   - `path_max_distance`: `2.0`
   - `avoidance_enabled`: `false` (bots pass through each other via collision layers)
4. **Smoke Particle / Despawn Effect**: `GPUParticles3D` with smoke texture + fade tween when completing an order.

### Unified Bot Navigation Call:

Because every `InteractionArea` (`Area3D`) implements `get_interaction_position(global_position)`, the bot navigation code is completely generic:

```gdscript
func dispatch_to(target_area: InteractionArea) -> void:
	nav_agent.target_position = target_area.get_interaction_position(global_position)
```

---

## 6. Potential Navigation Blockers Checklist

| Object | Potential Blocker Issue | Solution |
| :--- | :--- | :--- |
| **Counters / Tables** | If gap between counter and wall is $< 0.7\text{m}$, bots cannot squeeze through. | Keep walkways $\ge 1.0\text{m}$ wide (Grid Step 0.5 helps maintain clearance). |
| **Crate / Trash Hitboxes** | `Area3D` interaction box might be placed on Layer 1 by mistake. | Keep `Area3D` strictly on Layer 4 (Interactions) and only `StaticBody3D` on Layer 1. |
| **Order Window** | Delivery counter must have a reachable target point inside the kitchen. | Place an `InteractionPoint` Marker on the kitchen side of the window Area3D. |
| **Spawning Overlap** | Multiple bots spawned at once can stack in the exact same coordinates. | Stagger spawn coordinates with random small offsets (e.g. `Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))`). |
