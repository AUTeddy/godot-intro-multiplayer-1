class_name ScoreboardComponent
extends Node

@export var player1_score: Label
@export var player2_score: Label
@export var play_again_button: Button

const player1_label = "Player 1\n%s"
const player2_label = "Player 2\n%s"

func _ready() -> void:
	play_again_button.pressed.connect(_play_again)
	
	EventManager.on_game_report_score(_update_scores)
	EventManager.on_game_game_over(_game_over)
	
	#MatchManager.scores_updated.connect(_update_scores)
	#MatchManager.game_ended.connect(_game_over)
	MatchManager.game_restarted.connect(_reset_scoreboard)
	
func _update_scores(scores):
	for player_name in scores.keys():
		if player_name == "1":
			player1_score.text = player1_label % scores["1"]
		else:
			player2_score.text = player2_label % scores[player_name]

func _game_over(winning_player_name: String, final_scores: Dictionary):
	if winning_player_name == "1":
		player1_score.text = player1_score.text + "\nWINNER!" + str(final_scores)
	else:
		player2_score.text = player2_score.text + "\nWINNER!" + str(final_scores)

	if is_multiplayer_authority():
		play_again_button.visible = true
		
func _play_again():
	play_again_button.visible = false
	MatchManager.restart_match()

func _reset_scoreboard():
	player1_score.text = player1_label % 0
	player2_score.text = player2_label % 0
