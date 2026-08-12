extends Node
## Global source of truth for whether the 3D game viewport is currently controllable.

signal controllability_changed(is_controllable: bool)

var is_controllable := false:
	set(value):
		if is_controllable == value:
			return
		is_controllable = value
		controllability_changed.emit(is_controllable)


func set_controllable(value: bool) -> void:
	is_controllable = value
