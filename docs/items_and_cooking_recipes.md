# Store Items & Cooking Recipes Catalog

This catalog outlines all possible sellable items, ingredient transformations, and menu tiers designed for the current 1-to-1 hold-and-process interaction loop (`ItemProcessor`).

---

## 1. Appliance Function Matrix

In the current cooking loop, the player brings an item to an appliance, holds the interact button for a specified duration, and receives a transformed item.

| Appliance | Gameplay Role | Action Verbs | Culinary Purpose |
| :--- | :--- | :--- | :--- |
| **Cutting Board** *(Decorated Wall / Counters)* | Mechanical Prep | `SLICE`, `CHOP`, `DICE`, `SHRED` | Breaks down raw produce, meats, and breads into component pieces or slices. |
| **Stove / Griddle** *(Decorated Wall / Multi-Stove)* | High Heat Cooking | `GRILL`, `SEAR`, `FRY`, `SAUTÉ` | Fast-cooks raw meats, patties, and prepped vegetables. |
| **Oven** *(Purchased Appliance)* | Slow Heat & Roasting | `BAKE`, `ROAST`, `MELT`, `TOAST` | Toasts bread, melts cheese toppings, roasts whole vegetables and meats. |
| **Sink** *(Purchased Appliance)* | Cleaning & Soaking | `WASH`, `RINSE`, `PEEL`, `SOAK` | Washes farm produce into crisp greens and thaws ingredients. |
| **Fridge** *(Purchased Appliance)* | Cold Prep & Setting | `CHILL`, `SET`, `PRESERVE`, `FREEZE` | Transforms salads into crisp dishes, sets chilled desserts/dips, and chills cold cuts. |

---

## 2. Version 1: Direct Crate Items (Raw / As-Is)

These are baseline items retrieved directly from the 9 store crates (`ItemSource`) without any appliance processing. They can be sold as raw groceries or simple ingredient orders.

| Item ID | Display Name | Source Crate | Store Cost | 3D Model Asset |
| :--- | :--- | :--- | :--- | :--- |
| `bread` | Fresh Bread / Bun | `BunCrate` | Owned ($0) | `assets/kitchen-pack/food_ingredient_bun.gltf` |
| `carrot` | Fresh Carrot | `CarrotCrate` | $30.00 | `assets/kitchen-pack/food_ingredient_carrot.gltf` |
| `cheese` | Cheese Block | `CheeseCrate` | $45.00 | `assets/kitchen-pack/food_ingredient_cheese.gltf` |
| `ham` | Raw Ham Cut | `HamCrate` | $55.00 | `assets/kitchen-pack/food_ingredient_ham.gltf` |
| `lettuce` | Fresh Lettuce Head | `LettuceCrate` | $30.00 | `assets/kitchen-pack/food_ingredient_lettuce.gltf` |
| `onion` | Fresh Onion | `OnionCrate` | $30.00 | `assets/kitchen-pack/food_ingredient_onion.gltf` |
| `potato` | Raw Russet Potato | `PotatoCrate` | $30.00 | `assets/kitchen-pack/food_ingredient_potato.gltf` |
| `steak` | Raw Beef Steak | `SteakCrate` | $75.00 | `assets/kitchen-pack/food_ingredient_steak.gltf` |
| `tomato` | Fresh Tomato | `TomatoCrate` | $30.00 | `assets/kitchen-pack/food_ingredient_tomato.gltf` |

---

## 3. Version 2: Processed Items with Existing Models (Zero 3D Modeling)

These recipes transform crate ingredients using kitchen appliances. Every item in this section uses a **pre-existing 3D model** located in `assets/kitchen-pack/`.

### 3.1 Single-Ingredient Prepped & Cooked Items

| Output Item Name | Input Item | Appliance | Action Verb | Hold Time | 3D Model Asset |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Sliced Bread** | Fresh Bread | Cutting Board | `SLICE BREAD` | 1.25s | `assets/kitchen-pack/food_ingredient_bread_slice.glb` |
| **Toasted Bun Top** | Fresh Bread | Oven | `TOAST BUN` | 2.00s | `assets/kitchen-pack/food_ingredient_bun_top.gltf` |
| **Toasted Bun Bottom** | Fresh Bread | Oven | `TOAST BUN` | 2.00s | `assets/kitchen-pack/food_ingredient_bun_bottom.gltf` |
| **Chopped Carrots** | Fresh Carrot | Cutting Board | `CHOP CARROT` | 1.50s | `assets/kitchen-pack/food_ingredient_carrot_chopped.gltf` |
| **Carrot Sticks** | Fresh Carrot | Cutting Board | `CUT STICKS` | 1.50s | `assets/kitchen-pack/food_ingredient_carrot_pieces.gltf` |
| **Washed Crisp Carrot** | Fresh Carrot | Sink | `WASH CARROT` | 1.00s | `assets/kitchen-pack/food_ingredient_carrot.gltf` |
| **Cheese Slice** | Cheese Block | Cutting Board | `SLICE CHEESE` | 1.25s | `assets/kitchen-pack/food_ingredient_cheese_slice.gltf` |
| **Diced Cheese** | Cheese Block | Cutting Board | `DICE CHEESE` | 1.25s | `assets/kitchen-pack/food_ingredient_cheese_chopped.gltf` |
| **Cooked Sliced Ham** | Raw Ham Cut | Stove | `SEAR HAM` | 2.50s | `assets/kitchen-pack/food_ingredient_ham_cooked.gltf` |
| **Glazed Roast Ham** | Raw Ham Cut | Oven | `ROAST HAM` | 3.50s | `assets/kitchen-pack/food_ingredient_ham_cooked.gltf` |
| **Chilled Deli Ham** | Cooked Ham | Fridge | `CHILL HAM` | 1.50s | `assets/kitchen-pack/food_ingredient_ham_cooked.gltf` |
| **Lettuce Leaf** | Lettuce Head | Cutting Board | `TEAR LEAF` | 1.00s | `assets/kitchen-pack/food_ingredient_lettuce_slice.gltf` |
| **Shredded Salad Greens** | Lettuce Head | Cutting Board | `SHRED GREENS` | 1.25s | `assets/kitchen-pack/food_ingredient_lettuce_chopped.gltf` |
| **Crisp Chilled Salad** | Shredded Salad | Fridge | `CHILL SALAD` | 1.50s | `assets/kitchen-pack/food_ingredient_lettuce_chopped.gltf` |
| **Diced Onions** | Fresh Onion | Cutting Board | `DICE ONION` | 1.25s | `assets/kitchen-pack/food_ingredient_onion_chopped.gltf` |
| **Fresh Onion Rings** | Fresh Onion | Cutting Board | `RING SLICE` | 1.50s | `assets/kitchen-pack/food_ingredient_onion_rings.gltf` |
| **Crispy Fried Onion Rings** | Onion Rings | Stove | `FRY RINGS` | 2.50s | `assets/kitchen-pack/food_ingredient_onion_rings.gltf` |
| **Potato Wedges / Fries** | Raw Potato | Cutting Board | `CHOP FRIES` | 1.50s | `assets/kitchen-pack/food_ingredient_potato_chopped.gltf` |
| **Homestyle Mashed Potatoes** | Raw Potato | Stove / Oven | `MASH POTATO` | 3.00s | `assets/kitchen-pack/food_ingredient_potato_mashed.gltf` |
| **Seared Steak Bites** | Raw Beef Steak | Stove | `SEAR STEAK` | 3.00s | `assets/kitchen-pack/food_ingredient_steak_pieces.gltf` |
| **Oven-Broiled Steak** | Raw Beef Steak | Oven | `BROIL STEAK` | 4.00s | `assets/kitchen-pack/food_ingredient_steak_pieces.gltf` |
| **Tomato Slice** | Fresh Tomato | Cutting Board | `SLICE TOMATO` | 1.00s | `assets/kitchen-pack/food_ingredient_tomato_slice.gltf` |
| **Plated Tomato Slices** | Fresh Tomato | Cutting Board | `SLICE BATCH` | 1.50s | `assets/kitchen-pack/food_ingredient_tomato_slices.gltf` |

### 3.2 Plated & Composite Dishes (Using Existing Pack Models)

| Output Dish | Base Input Item | Appliance | Action Verb | 3D Model Asset |
| :--- | :--- | :--- | :--- | :--- |
| **Classic Cheeseburger** | Cooked Burger Patty / Bread | Counter / Oven | `ASSEMBLE BURGER` | `assets/kitchen-pack/food_burger.gltf` |
| **Garden Veggie Burger** | Chopped Veggies / Veggie Patty | Stove / Counter | `ASSEMBLE VEGGIE BURGER` | `assets/kitchen-pack/food_vegetableburger.gltf` |
| **Plated Steak Dinner** | Seared Steak / Mash | Oven / Counter | `PLATE DINNER` | `assets/kitchen-pack/food_dinner.gltf` |
| **Hearty Beef & Carrot Stew** | Steak Bites / Carrot | Stove | `SIMMER STEW` | `assets/kitchen-pack/food_stew.gltf` / `pot_A_stew.gltf` |
| **House Tomato Ketchup** | Fresh Tomato | Fridge | `BOTTLE SAUCE` | `assets/kitchen-pack/ketchup.gltf` |
| **Spicy Mustard** | Onion / Seasoning | Fridge | `BOTTLE MUSTARD` | `assets/kitchen-pack/mustard.gltf` |
| **Chilled Pickles / Preserves** | Sliced Onion / Veggies | Fridge | `JAR PRESERVE` | `assets/kitchen-pack/jar_A_small.gltf` ... `jar_D_large.gltf` |

---

## 4. Version 3: Concept Items (Requiring Custom 3D Models)

These menu items expand the culinary variety using the 9 store ingredients and appliances, but will require authoring or importing new 3D model meshes.

### 4.1 Oven Specialties (Baking, Roasting & Melting)
* **Baked Jacket Potato with Cheese**
  * *Recipe:* Raw Potato $\to$ Oven (`BAKE JACKET POTATO`)
  * *Mesh Description:* A split russet potato topped with melted cheddar, butter, and chives.
* **Toasted Ham & Cheese Melt (Croque Monsieur)**
  * *Recipe:* Sliced Bread $\to$ Oven (`BAKE MELT`)
  * *Mesh Description:* Golden toasted sandwich with broiled browned cheese and ham layers.
* **Rustic Tomato & Cheese Flatbread / Mini Pizza**
  * *Recipe:* Fresh Bread $\to$ Oven (`BAKE FLATBREAD`)
  * *Mesh Description:* Crisp mini round crust topped with tomato sauce, melted cheese circles, and herbs.
* **Roasted Root Vegetable Medley**
  * *Recipe:* Chopped Carrot $\to$ Oven (`ROAST MEDLEY`)
  * *Mesh Description:* Ceramic baking dish loaded with caramelized roasted carrot chunks, potatoes, and onions.
* **Garlic Butter Herb Toast**
  * *Recipe:* Sliced Bread $\to$ Oven (`BAKE GARLIC TOAST`)
  * *Mesh Description:* Golden baguette slices in a basket with herb butter and parsley.

### 4.2 Fridge Specialties (Chilling, Setting & Cold Delis)
* **Chilled Gazpacho Cup**
  * *Recipe:* Fresh Tomato $\to$ Fridge (`CHILL GAZPACHO`)
  * *Mesh Description:* Glass bowl of vibrant red cold tomato soup garnished with diced onion and cucumber.
* **Creamy Potato Salad**
  * *Recipe:* Mashed / Chopped Potato $\to$ Fridge (`CHILL POTATO SALAD`)
  * *Mesh Description:* Deli bowl of creamy potato salad dusted with smoked paprika.
* **Charcuterie Deli Platter**
  * *Recipe:* Cooked Ham $\to$ Fridge (`CHILL DELI PLATTER`)
  * *Mesh Description:* Wooden board with folded cold-cut ham ribbons, cheese cubes, and pickled garnishes.
* **Sweet Pickled Red Onions**
  * *Recipe:* Diced Onion $\to$ Fridge (`PICKLE ONIONS`)
  * *Mesh Description:* Clear glass jar containing bright magenta pickled onion rings in brine.
* **Cold Herb Butter Tub**
  * *Recipe:* Cheese Block $\to$ Fridge (`SET BUTTER`)
  * *Mesh Description:* Ceramic ramekin with a piped swirl of compound herb butter.

### 4.3 Stovetop & Skillet Specialties (Searing, Frying & Simmering)
* **Fast-Food Crispy French Fries**
  * *Recipe:* Potato Wedges $\to$ Stove (`DEEP FRY`)
  * *Mesh Description:* Classic red paper fry box filled with thin golden crispy french fries.
* **Loaded Breakfast Skillet**
  * *Recipe:* Ham / Potato $\to$ Stove (`FRY SKILLET`)
  * *Mesh Description:* Mini black cast-iron skillet with browned potato hash, diced ham, onions, and cheese.
* **French Onion Soup Crock**
  * *Recipe:* Diced Onion $\to$ Stove (`CARAMELIZE SOUP`)
  * *Mesh Description:* Ceramic soup crock topped with a toasted crouton and melted gruyere cheese crust.
* **Salisbury Steak Platter**
  * *Recipe:* Steak $\to$ Stove (`GLAZE SALISBURY`)
  * *Mesh Description:* Oval dinner plate with beef cut smothered in rich brown onion mushroom gravy.

### 4.4 Sink & Fresh Prep Specialties
* **Chilled Crudité Veggie Platter**
  * *Recipe:* Fresh Carrot $\to$ Sink (`WASH & CRISP`)
  * *Mesh Description:* Glass cup or platter of chilled washed carrot and celery batons with dip.
* **Fresh Tomato Bruschetta**
  * *Recipe:* Fresh Tomato $\to$ Sink / Counter (`MARINATE BRUSCHETTA`)
  * *Mesh Description:* Two toasted crostini topped with diced marinated red tomatoes and basil.

---

## 5. Recommended Gameplay Menu Progression

| Tier | Unlocks Required | Typical Customer Orders | Payout Range |
| :--- | :--- | :--- | :--- |
| **Tier 1: Starter Bakery** | Bun Crate, Decorated Wall | Whole Bread, Sliced Bread | $3.00 – $7.00 |
| **Tier 2: Fresh Produce & Salads** | Carrot Crate, Tomato Crate, Lettuce Crate, Sink | Washed Carrots, Tossed Salad, Tomato Slices | $8.00 – $14.00 |
| **Tier 3: Deli & Cookhouse** | Ham Crate, Cheese Crate, Onion Crate, Potato Crate, Stove | Sliced Ham, Fried Onion Rings, Mashed Potatoes, Cheese Slices | $15.00 – $24.00 |
| **Tier 4: Fine Dining & Oven Bakes** | Steak Crate, Fridge, Oven | Steak Platter, Beef Stew, Classic Burger, Roast Medley | $25.00 – $45.00+ |
