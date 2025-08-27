extends Control


func _on_host_game_pressed() -> void:
	NetworkManager.create_server()
	NetworkManager.load_game_scene()

func _on_join_game_pressed() -> void:
	NetworkManager.load_game_scene()
	NetworkManager.create_client()

func _on_send_test_message_pressed() -> void:
	_send_test_message.rpc("Hello there!")

@rpc("any_peer", "call_remote")
func _send_test_message(message: String):
	print("Message [%s] received on peer [%s], from peer [%s]." % 
		[message, 
		get_tree().get_multiplayer().get_unique_id(), 
		get_tree().get_multiplayer().get_remote_sender_id()])
	
