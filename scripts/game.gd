extends Node2D

func _on_main_menu_pressed() -> void:
	NetworkManager.terminate_connection_load_main_menu()
