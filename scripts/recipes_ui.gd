class_name RecipesUI
extends Control
## Controller for the Recipes Cookbook tab.
##
## Displays all meals and preparation routes in player discovery progression order,
## with step-by-step creation instructions, made-count tracking, categories, and search.

const FONT_LILITA: FontFile = preload("res://assets/fonts/LilitaOne-Regular.ttf")

@onready var stats_label: Label = %StatsLabel
@onready var search_input: LineEdit = %SearchInput
@onready var clear_search_button: Button = %ClearSearchButton
@onready var category_bar: HBoxContainer = %CategoryBar
@onready var recipes_grid: VBoxContainer = %RecipesList
@onready var empty_search_label: Label = %EmptySearchLabel
@onready var scroll_container: ScrollContainer = %ScrollContainer

var _active_filter_category := "ALL"
var _active_search_query := ""
var _card_views: Dictionary = {}
var _filter_buttons: Dictionary = {}


func _ready() -> void:
	if search_input != null:
		search_input.text_changed.connect(_on_search_text_changed)
	if clear_search_button != null:
		clear_search_button.pressed.connect(_on_clear_search_pressed)

	_setup_category_buttons()
	_populate_recipe_cards()
	_update_stats_display()

	RecipeTracker.tracker_updated.connect(_on_tracker_updated)
	RecipeTracker.recipe_made.connect(_on_recipe_made)


func _exit_tree() -> void:
	if RecipeTracker.tracker_updated.is_connected(_on_tracker_updated):
		RecipeTracker.tracker_updated.disconnect(_on_tracker_updated)
	if RecipeTracker.recipe_made.is_connected(_on_recipe_made):
		RecipeTracker.recipe_made.disconnect(_on_recipe_made)


func _setup_category_buttons() -> void:
	if category_bar == null:
		return

	for child in category_bar.get_children():
		if child is Button:
			var btn := child as Button
			var cat_name := btn.name.to_upper()
			if btn.has_meta(&"filter_category"):
				cat_name = str(btn.get_meta(&"filter_category")).to_upper()
			_filter_buttons[cat_name] = btn
			btn.pressed.connect(_on_category_button_pressed.bind(cat_name))

	_highlight_active_category_button()


func _populate_recipe_cards() -> void:
	if recipes_grid == null:
		return

	# Clear previous cards if any
	for child in recipes_grid.get_children():
		child.queue_free()
	_card_views.clear()

	var all_entries := RecipeTracker.get_all_recipe_entries()

	# Sort by progression sort_order (Bread/Buns first -> multi-step crazy meals last)
	all_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order_a: int = int(a.get("sort_order", 500))
		var order_b: int = int(b.get("sort_order", 500))
		if order_a != order_b:
			return order_a < order_b
		return str(a.get("title", "")).naturalnocasecmp_to(str(b.get("title", ""))) < 0
	)

	for entry in all_entries:
		var card := _create_recipe_card(entry)
		recipes_grid.add_child(card)
		_card_views[entry["recipe_id"]] = {
			"card": card,
			"data": entry,
		}

	_filter_cards()


func _create_recipe_card(data: Dictionary) -> Control:
	var recipe_id: StringName = data.get("recipe_id", &"")
	var title: String = data.get("title", "Recipe")
	var category: String = data.get("category", "General")
	var desc: String = data.get("description", "")
	var price: float = float(data.get("price", 0.0))
	var is_composite: bool = bool(data.get("is_composite", false))
	var is_made: bool = bool(data.get("is_made", false))
	var made_count: int = int(data.get("made_count", 0))
	var steps: Array = data.get("steps", [])

	var panel := PanelContainer.new()
	panel.name = "RecipeCard_%s" % recipe_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Clean Godot UI card: full solid black panel with crisp border
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 1) # Full black
	if is_made:
		style.border_color = Color(0.32549, 0.721569, 0.227451, 1) # Game green border
		style.set_border_width_all(2)
	else:
		style.border_color = Color(0.25, 0.25, 0.25, 1)
		style.set_border_width_all(2)

	style.set_corner_radius_all(8)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(root_vbox)

	# --- Header Row ---
	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	header_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(header_row)

	# Recipe Name
	var name_label := Label.new()
	name_label.name = "RecipeTitle"
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_override("font", FONT_LILITA)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override(
		"font_color",
		Color(1, 0.780392, 0.172549, 1) if is_made else Color(1, 1, 1, 1)
	)
	header_row.add_child(name_label)

	# Category Badge (Themed colors)
	var cat_color := _get_category_badge_color(category, is_composite)
	var cat_badge := _create_pill_badge(category.to_upper(), cat_color)
	header_row.add_child(cat_badge)

	# Made Status Badge
	var made_badge := _create_made_badge(is_made, made_count)
	made_badge.name = "MadeBadge"
	header_row.add_child(made_badge)

	# --- Meta Row (Value & Description) ---
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 16)
	root_vbox.add_child(meta_row)

	var formatted_price := "$%.2f" % price if fmod(price, 1.0) != 0.0 else "$%d" % int(price)
	var price_label := Label.new()
	price_label.text = "💰 Est. Value: %s" % formatted_price
	price_label.add_theme_font_override("font", FONT_LILITA)
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.add_theme_color_override("font_color", Color(0.32549, 0.721569, 0.227451, 1)) # Game green
	meta_row.add_child(price_label)

	if not desc.is_empty():
		var desc_label := Label.new()
		desc_label.text = desc
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", 13)
		desc_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1))
		root_vbox.add_child(desc_label)

	# --- Creation Steps Sub-Panel ---
	var steps_panel := PanelContainer.new()
	var steps_style := StyleBoxFlat.new()
	steps_style.bg_color = Color(0.08, 0.08, 0.08, 1) # Inset dark panel
	steps_style.border_color = Color(0.2, 0.2, 0.2, 1)
	steps_style.set_border_width_all(1)
	steps_style.set_corner_radius_all(6)
	steps_style.content_margin_left = 12.0
	steps_style.content_margin_right = 12.0
	steps_style.content_margin_top = 8.0
	steps_style.content_margin_bottom = 8.0
	steps_panel.add_theme_stylebox_override("panel", steps_style)
	root_vbox.add_child(steps_panel)

	var steps_vbox := VBoxContainer.new()
	steps_vbox.add_theme_constant_override("separation", 6)
	steps_panel.add_child(steps_vbox)

	var steps_header := Label.new()
	steps_header.text = "CREATION STEPS:"
	steps_header.add_theme_font_override("font", FONT_LILITA)
	steps_header.add_theme_font_size_override("font_size", 13)
	steps_header.add_theme_color_override("font_color", Color(0.854902, 0.160784, 0.109804, 1)) # Game Diner Red
	steps_vbox.add_child(steps_header)

	for i in steps.size():
		var step_data: Dictionary = steps[i]
		var step_row := _create_step_row(i + 1, step_data)
		steps_vbox.add_child(step_row)

	return panel


func _get_category_badge_color(category: String, is_composite: bool) -> Color:
	if is_composite or category == "Assembly Counter":
		return Color(0.854902, 0.160784, 0.109804, 1) # Game Diner Red
	match category:
		"Cutting Board":
			return Color(0.32549, 0.721569, 0.227451, 1) # Game Green
		"Stove / Grill", "Stove / Oven":
			return Color(0.854902, 0.22, 0.14, 1) # Sear Red
		"Oven":
			return Color(0.92, 0.48, 0.15, 1) # Oven Orange
		"Sink":
			return Color(0.15, 0.55, 0.85, 1) # Game Blue
		"Fridge":
			return Color(0.10, 0.65, 0.75, 1) # Ice Cyan
		_:
			return Color(0.854902, 0.160784, 0.109804, 1)


func _create_step_row(step_index: int, step_data: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Step Number Badge (Game Diner Red pill with black border)
	var num_badge := PanelContainer.new()
	var num_style := StyleBoxFlat.new()
	num_style.bg_color = Color(0.854902, 0.160784, 0.109804, 1)
	num_style.border_color = Color(0, 0, 0, 1)
	num_style.set_border_width_all(1)
	num_style.set_corner_radius_all(4)
	num_style.content_margin_left = 7.0
	num_style.content_margin_right = 7.0
	num_style.content_margin_top = 2.0
	num_style.content_margin_bottom = 2.0
	num_badge.add_theme_stylebox_override("panel", num_style)

	var num_label := Label.new()
	num_label.text = str(step_index)
	num_label.add_theme_font_override("font", FONT_LILITA)
	num_label.add_theme_font_size_override("font_size", 12)
	num_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	num_badge.add_child(num_label)
	row.add_child(num_badge)

	# Step Text / Instruction
	var instruction: String = step_data.get("instruction", "")
	if instruction.is_empty():
		var action: String = step_data.get("action", "PROCESS")
		var app: String = step_data.get("appliance", "Appliance")
		var inp: String = step_data.get("input", "Ingredient")
		var outp: String = step_data.get("output", "Output")
		instruction = "Take %s to the %s and %s into %s." % [inp, app, action.to_lower(), outp]

	var step_label := Label.new()
	step_label.text = instruction
	step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_label.add_theme_font_size_override("font_size", 13)
	step_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1)) # Crisp light readable text
	row.add_child(step_label)

	return row


func _create_pill_badge(text: String, bg_color: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = bg_color
	pill_style.border_color = Color(0, 0, 0, 1)
	pill_style.set_border_width_all(1)
	pill_style.set_corner_radius_all(4)
	pill_style.content_margin_left = 8.0
	pill_style.content_margin_right = 8.0
	pill_style.content_margin_top = 2.0
	pill_style.content_margin_bottom = 2.0
	pill.add_theme_stylebox_override("panel", pill_style)

	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT_LILITA)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	pill.add_child(label)
	return pill


func _create_made_badge(is_made: bool, count: int) -> PanelContainer:
	var badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.set_corner_radius_all(4)
	badge_style.content_margin_left = 9.0
	badge_style.content_margin_right = 9.0
	badge_style.content_margin_top = 2.0
	badge_style.content_margin_bottom = 2.0

	var label := Label.new()
	label.name = "Label"
	label.add_theme_font_override("font", FONT_LILITA)
	label.add_theme_font_size_override("font_size", 12)

	if is_made:
		badge_style.bg_color = Color(0.32549, 0.721569, 0.227451, 1) # Game Green
		badge_style.border_color = Color(0, 0, 0, 1)
		badge_style.set_border_width_all(1)
		label.text = "✓ MADE (%dx)" % count
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	else:
		badge_style.bg_color = Color(0.12, 0.12, 0.12, 1)
		badge_style.border_color = Color(0.3, 0.3, 0.3, 1)
		badge_style.set_border_width_all(1)
		label.text = "NOT MADE YET"
		label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))

	badge.add_theme_stylebox_override("panel", badge_style)
	badge.add_child(label)
	return badge


# ==============================================================================
# Filtering & Search Logic
# ==============================================================================

func _on_category_button_pressed(category_name: String) -> void:
	_active_filter_category = category_name
	_highlight_active_category_button()
	_filter_cards()


func _on_search_text_changed(new_text: String) -> void:
	_active_search_query = new_text.strip_edges().to_lower()
	if clear_search_button != null:
		clear_search_button.visible = not _active_search_query.is_empty()
	_filter_cards()


func _on_clear_search_pressed() -> void:
	if search_input != null:
		search_input.text = ""
	_on_search_text_changed("")


func _highlight_active_category_button() -> void:
	for cat: String in _filter_buttons:
		var btn: Button = _filter_buttons[cat]
		if btn != null:
			var is_active := cat == _active_filter_category
			btn.button_pressed = is_active


func _filter_cards() -> void:
	var visible_count := 0
	for recipe_id: StringName in _card_views:
		var view: Dictionary = _card_views[recipe_id]
		var card: Control = view["card"]
		var data: Dictionary = view["data"]

		var matches_category := _matches_category_filter(data)
		var matches_search := _matches_search_filter(data)
		var is_visible := matches_category and matches_search

		card.visible = is_visible
		if is_visible:
			visible_count += 1

	if empty_search_label != null:
		empty_search_label.visible = visible_count == 0
		if visible_count == 0:
			empty_search_label.text = "No recipes found matching \"%s\"." % search_input.text if not _active_search_query.is_empty() else "No recipes available in this category."


func _matches_category_filter(data: Dictionary) -> bool:
	if _active_filter_category == "ALL":
		return true

	if _active_filter_category == "MADE ONLY":
		var r_id: StringName = data.get("recipe_id", &"")
		return RecipeTracker.has_made_recipe(r_id)

	var filter_cat: String = str(data.get("filter_category", "")).to_upper()
	var cat: String = str(data.get("category", "")).to_upper()

	if _active_filter_category == "COMPOSITE MEALS" or _active_filter_category == "MEALS":
		return data.get("is_composite", false) or filter_cat.containsn("COMPOSITE") or cat.containsn("ASSEMBLY")

	if _active_filter_category == "CUTTING BOARD":
		return cat.containsn("CUTTING BOARD") or filter_cat.containsn("CUTTING BOARD")

	if _active_filter_category == "STOVE / GRILL" or _active_filter_category == "STOVE":
		return cat.containsn("STOVE") or filter_cat.containsn("STOVE")

	if _active_filter_category == "OVEN":
		return cat.containsn("OVEN") or filter_cat.containsn("OVEN")

	if _active_filter_category == "SINK":
		return cat.containsn("SINK") or filter_cat.containsn("SINK")

	if _active_filter_category == "FRIDGE":
		return cat.containsn("FRIDGE") or filter_cat.containsn("FRIDGE")

	return filter_cat == _active_filter_category or cat == _active_filter_category


func _matches_search_filter(data: Dictionary) -> bool:
	if _active_search_query.is_empty():
		return true

	var title: String = str(data.get("title", "")).to_lower()
	if title.containsn(_active_search_query):
		return true

	var output_name: String = str(data.get("output_name", "")).to_lower()
	if output_name.containsn(_active_search_query):
		return true

	var category: String = str(data.get("category", "")).to_lower()
	if category.containsn(_active_search_query):
		return true

	var desc: String = str(data.get("description", "")).to_lower()
	if desc.containsn(_active_search_query):
		return true

	var steps: Array = data.get("steps", [])
	for s: Variant in steps:
		if s is Dictionary:
			var inst: String = str((s as Dictionary).get("instruction", "")).to_lower()
			if inst.containsn(_active_search_query):
				return true
			var inp: String = str((s as Dictionary).get("input", "")).to_lower()
			if inp.containsn(_active_search_query):
				return true
			var outp: String = str((s as Dictionary).get("output", "")).to_lower()
			if outp.containsn(_active_search_query):
				return true

	return false


# ==============================================================================
# Live Updates
# ==============================================================================

func _on_tracker_updated() -> void:
	_update_stats_display()
	_refresh_card_badges()


func _on_recipe_made(recipe_id: StringName, _item: KitchenItem, total_count: int) -> void:
	_update_stats_display()
	if _card_views.has(recipe_id):
		_update_card_made_state(recipe_id, total_count)


func _update_stats_display() -> void:
	if stats_label == null:
		return
	var discovered := RecipeTracker.get_discovered_count()
	var total := RecipeTracker.get_total_recipe_count()
	var crafted := RecipeTracker.get_total_recipes_made_count()
	stats_label.text = "DISCOVERED: %d / %d  ·  TOTAL CRAFTED: %d" % [discovered, total, crafted]


func _refresh_card_badges() -> void:
	for recipe_id: StringName in _card_views:
		var count := RecipeTracker.get_recipe_made_count(recipe_id)
		_update_card_made_state(recipe_id, count)
	if _active_filter_category == "MADE ONLY":
		_filter_cards()


func _update_card_made_state(recipe_id: StringName, count: int) -> void:
	if not _card_views.has(recipe_id):
		return
	var view: Dictionary = _card_views[recipe_id]
	var card: PanelContainer = view["card"] as PanelContainer
	if card == null or not is_instance_valid(card):
		return

	var is_made := count > 0

	var style := card.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		style.bg_color = Color(0, 0, 0, 1)
		if is_made:
			style.border_color = Color(0.32549, 0.721569, 0.227451, 1)
			style.set_border_width_all(2)
		else:
			style.border_color = Color(0.25, 0.25, 0.25, 1)
			style.set_border_width_all(2)

	var title_lbl := card.find_child("RecipeTitle", true, false) as Label
	if title_lbl != null:
		title_lbl.add_theme_color_override(
			"font_color",
			Color(1, 0.780392, 0.172549, 1) if is_made else Color(1, 1, 1, 1)
		)

	var made_badge := card.find_child("MadeBadge", true, false) as PanelContainer
	if made_badge != null:
		var badge_style := made_badge.get_theme_stylebox("panel") as StyleBoxFlat
		var label := made_badge.get_node_or_null("Label") as Label
		if badge_style != null and label != null:
			if is_made:
				badge_style.bg_color = Color(0.32549, 0.721569, 0.227451, 1)
				badge_style.border_color = Color(0, 0, 0, 1)
				label.text = "✓ MADE (%dx)" % count
				label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			else:
				badge_style.bg_color = Color(0.12, 0.12, 0.12, 1)
				badge_style.border_color = Color(0.3, 0.3, 0.3, 1)
				label.text = "NOT MADE YET"
				label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
