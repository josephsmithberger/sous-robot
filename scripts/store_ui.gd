extends Control

var _pending_card: Button


func _ready() -> void:
	for card: Button in get_tree().get_nodes_in_group("store_cards"):
		card.pressed.connect(_on_card_pressed.bind(card))


func _on_card_pressed(card: Button) -> void:
	_pending_card = card
	card.disabled = true
	card.modulate = Color(0.5, 0.5, 0.5, 1.0)
	$PurchaseDialog.popup_centered()


func _on_purchase_confirmed() -> void:
	_pending_card = null


func _on_purchase_canceled() -> void:
	if _pending_card != null:
		_pending_card.disabled = false
		_pending_card.modulate = Color.WHITE
	_pending_card = null
