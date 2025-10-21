extends Node

const WINNING_SCORE: int = 5

signal scores_updated
signal game_ended
signal game_restarted

var game_paused = false

var _player_scores = {}

func _ready() -> void:
	EventManager.on_game_play_again(_play_again)
	EventManager.on_game_game_over(_game_over)

func player_died(killed_player_name: String):
	print("Player %s died" % killed_player_name)
	
	for player_name in _player_scores.keys():
		if player_name != killed_player_name:
			_player_scores[player_name] = _player_scores[player_name] + 1

			if _player_scores[player_name] >= WINNING_SCORE:
				#_game_over.rpc(player_name, _player_scores)
				EventManager.game_game_over(player_name, _player_scores)
				return 

	#_report_score.rpc(_player_scores)
	EventManager.game_report_score(_player_scores)
	

#@rpc("authority", "call_local", "reliable")
func _report_score(scores):
	scores_updated.emit(scores)

#@rpc("authority", "call_local", "reliable")
func _game_over(winning_player_name: String, final_scores: Dictionary):
	game_paused = true
	scores_updated.emit(final_scores)
	game_ended.emit(winning_player_name)

#@rpc("authority", "call_local", "reliable")
func _play_again():
	game_restarted.emit()
	game_paused = false

func _reset_scores():
	for player_name in _player_scores.keys():
		_player_scores[player_name] = 0

func restart_match():
	_reset_scores()
	#_play_again.rpc()
	EventManager.game_play_again()

func add_player_to_score_keeping(player_name: String):
	_player_scores[player_name] = 0

func remove_player_from_score_keeping(player_name: String):
	_player_scores.erase(player_name)

func player_left_game(player_name: String):
	remove_player_from_score_keeping(player_name)
