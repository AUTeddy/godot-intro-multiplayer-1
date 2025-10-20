#event_bridge.gd
@tool
class_name EventBridge extends EditorPlugin

#var DEBUG := ProjectSettings.get_setting("event_bridge/debug")


const AUTOLOAD_EVENT_BUS = "EventBus"
const AUTOLOAD_EVENT_MANAGER = "EventManager.gd"
const AUTOLOAD_EVENT_BRIDGE_LOGGER = "EventBridgeLogger"

const AUTOLOAD_EVENT_BUS_PATH = "res://addons/event_bridge/autoload/event_bus.gd"
const AUTOLOAD_EVENT_MANAGER_PATH = "res://addons/event_bridge/generated/EventManager.gd"
const AUTOLOAD_EVENT_BRIDGE_LOGGER_PATH = "res://addons/event_bridge/autoload/event_bridge_logger.gd"

var dock

func _enter_tree():

	ProjectSettings.set("addons/event_bridge/debug", false)
	
	#if not ProjectSettings.has_setting("addons/event_bridge/debug"):
		#ProjectSettings.set_setting("addons/event_bridge/debug", false)


	dock = preload("res://addons/event_bridge/event_dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UR, dock)
	dock.name = "Event Bridge"

	# Ensure EventManager is an autoload
	_ensure_autoloads()


func _exit_tree():
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


# Check and add autoload if missing
func _ensure_autoloads():
	#if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_EVENT_BUS):
		# Add fresh autoload if missing
	add_autoload_singleton(AUTOLOAD_EVENT_BUS, AUTOLOAD_EVENT_BUS_PATH)
	#print("[EventBridge] Added new autoload:", AUTOLOAD_EVENT_BUS)

	#if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_EVENT_BRIDGE_LOGGER):
		# Add fresh autoload if missing
	add_autoload_singleton(AUTOLOAD_EVENT_BRIDGE_LOGGER, AUTOLOAD_EVENT_BRIDGE_LOGGER_PATH)
	#print("[EventBridge] Added new autoload:", AUTOLOAD_EVENT_BRIDGE_LOGGER)

	# Manager Autload
	#if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_EVENT_MANAGER):
		#notify to add
	print("[EventBridge] Add %s to your autoloads after generating the Event Registry" % AUTOLOAD_EVENT_MANAGER_PATH)
