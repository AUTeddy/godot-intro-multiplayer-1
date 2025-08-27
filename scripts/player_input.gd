class_name PlayerInput
extends Node

var input_dir: Vector2

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		input_dir = Input.get_vector("left", "right", "up", "down")
