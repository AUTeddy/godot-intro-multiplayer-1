# Logger.gd
@tool
extends Node

#@onready var console: RichTextLabel = %Console
enum LogLevel { INFO, WARN, ERROR, VALIDATOR, EVENT }


func event_log(sender: String, msg: String, level: LogLevel = LogLevel.INFO) -> void:
	var time_str = Time.get_time_string_from_system(true)

	var level_color := {
		LogLevel.INFO: "green",
		LogLevel.WARN: "yellow",
		LogLevel.ERROR: "red",
		LogLevel.VALIDATOR: "#ff0fff",
		LogLevel.EVENT: "#006eff",
	}

	var level_name := {
		LogLevel.INFO: "INFO",
		LogLevel.WARN: "WARN",
		LogLevel.ERROR: "ERROR",
		LogLevel.VALIDATOR: "VALIDATOR",
		LogLevel.EVENT: "EVENT"
	}

	var output = "%s [color=%s][b][ %s ][/b][/color] [color=white][%s][/color] %s \n" % [
		time_str,
		level_color[level],
		level_name[level],
		sender,
		msg
	]

	print_rich(output)
