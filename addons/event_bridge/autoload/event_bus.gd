@tool
class_name EventBusAutoload
extends Node

const JSON_PATH = "res://addons/event_bridge/generated/event_registry.json"

#var DEBUG := ProjectSettings.get_setting("event_bridge/debug")
var DEBUG := false 

#enum LogLevel { INFO, WARN, ERROR }

var EVENTS: Dictionary = {}
var _namespace_cache: Dictionary = {}
var _connected_handlers: Dictionary = {}



# Global static guard
static var global_initialized := false

# ==============================
# Custom Namespace Class
# ==============================
class Namespace extends RefCounted:
	var ns_name: String
	var parent: Node

	func _init(name: String, parent_node: Node):
		ns_name = name
		parent = parent_node


	func on(event_name: String, callable: Callable):
		if !parent._validate_event(ns_name, event_name):
			return

		var signal_name = parent._signal_name(ns_name, event_name)
		var key = "%s::%s" % [ns_name, event_name]

		if !parent._connected_handlers.has(key):
			parent._connected_handlers[key] = []

		var list = parent._connected_handlers[key]
		if callable in list:
			return # avoid duplicate

		list.append(callable)
		parent.connect(signal_name, callable)


	func off(event_name: String, callable: Callable):
		var key = "%s::%s" % [ns_name, event_name]
		if !parent._connected_handlers.has(key):
			return

		var list = parent._connected_handlers[key]
		if typeof(list) != TYPE_ARRAY:
			return

		if callable in list:
			var signal_name = parent._signal_name(ns_name, event_name)
			if parent.is_connected(signal_name, callable):
				parent.disconnect(signal_name, callable)
			list.erase(callable)

		if list.is_empty():
			parent._connected_handlers.erase(key)


	func off_all():
		for key in parent._connected_handlers.keys():
			var parts = key.split("::")
			if parts.size() != 2 or parts[0] != ns_name:
				continue

			var signal_name = parent._signal_name(parts[0], parts[1])
			var callables = parent._connected_handlers[key]

			for c in callables:
				if parent.is_connected(signal_name, c):
					parent.disconnect(signal_name, c)

			parent._connected_handlers.erase(key)


	func emit(event_name: String, args: Array = []):
		parent._invoke_event(ns_name, event_name, args)


	func to_server(event_name: String, args: Array = []):
		if parent.multiplayer.is_server():
			parent._invoke_event(ns_name, event_name, args)
		else:
			#parent._apply_rpc_config_for(ns_name, event_name)
			parent.rpc_id(1, "rpc_event", ns_name, event_name, args)


	func to_all(event_name: String, args: Array = []):
		#parent._apply_rpc_config_for(ns_name, event_name)
		parent.rpc("rpc_event", ns_name, event_name, args)

	# same as signal so no need for this
	#func only_me(event_name: String, args: Array = []):
		#emit(event_name, args)

	func to_id(peer_id: int, event_name: String, args: Array = []):
		#parent._apply_rpc_config_for(ns_name, event_name)
		parent.rpc_id(peer_id, "rpc_event", ns_name, event_name, args)

# ==============================
# Lifecycle
# ==============================
func _ready():

	if Engine.is_editor_hint():
		return

	if global_initialized:
		return

	global_initialized = true
	_initialize_event_bus()
	
	print(DEBUG)


func _initialize_event_bus():
	_load_registry()
	_register_signals()
	_preconfigure_rpc()
	_log_initialization_summary()

# ==============================
# Load registry
# ==============================
# --- add this helper once (near the top is fine) ---
func _eb_log(sender: String, msg: String, level: int) -> void:
	# Try to find the autoload by path; avoid compile-time reference to its identifier
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		var root: Node = (tree as SceneTree).root
		if root and root.has_node("/root/EventBridgeLogger"):
			var logger := root.get_node("/root/EventBridgeLogger")
			if logger and logger.has_method("event_log"):
				logger.call("event_log", sender, msg, level)
				return
		# Fallback (only if you want debug output when logger missing)
		else:
			print("[EventBridge][%d] %s: %s" % [level, sender, msg])



func _load_registry():
	if FileAccess.file_exists(JSON_PATH):
		var file = FileAccess.open(JSON_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			EVENTS = parsed
		else:
			#_log("Event Bus", "Failed to parse event registry JSON", LogLevel.ERROR)
			_eb_log(str(self), "Failed to parse event registry JSON", 2)
	else:
		#_log("Event Bus", "Registry file missing at: %s" % JSON_PATH, LogLevel.ERROR)
		_eb_log(str(self), "Registry file missing at: %s" % JSON_PATH, 2)


# ==============================
# Register all signals
# ==============================
func _register_signals():
	for ns_name in EVENTS.keys():
		for ev in EVENTS[ns_name]:
			var signal_name = _signal_name(ns_name, ev["name"])
			if !has_signal(signal_name):
				add_user_signal(signal_name)


# ==============================
# Pre-configure RPC settings
# ==============================
func _preconfigure_rpc():
	for ns_name in EVENTS.keys():
		for ev in EVENTS[ns_name]:
			var mode = ev.get("mode", "any_peer")
			var sync = ev.get("sync", "call_remote")
			var transfer_mode = ev.get("transfer_mode", "reliable")
			var transfer_channel = int(ev.get("transfer_channel", 0))

			var rpc_mode = MultiplayerAPI.RPC_MODE_AUTHORITY if mode == "authority" else MultiplayerAPI.RPC_MODE_ANY_PEER
			var call_local = (sync == "call_local")

			var transfer_enum: int
			match transfer_mode:
				"unreliable":
					transfer_enum = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
				"unreliable_ordered":
					transfer_enum = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
				_:
					transfer_enum = MultiplayerPeer.TRANSFER_MODE_RELIABLE

			rpc_config("rpc_event", {
				"rpc_mode": rpc_mode,
				"call_local": call_local,
				"transfer_mode": transfer_enum,
				"channel": transfer_channel
			})


# ==============================
# Public API
# ==============================
func get_namespace(name: String) -> Namespace:
	if !_namespace_cache.has(name):
		if !EVENTS.has(name):
			# _log("Event Bus", "Namespace '%s' not found in registry" % name, LogLevel.ERROR)
			# _eb_log(str(self), "Namespace '%s' not found in registry" % name, 2)
			_namespace_cache[name] = Namespace.new(name, self)
		else:
			_namespace_cache[name] = Namespace.new(name, self)
	return _namespace_cache[name]


func print_handler_summary():
	var grouped := {}
	for key in _connected_handlers.keys():
		var parts = key.split("::")
		if !grouped.has(parts[0]):
			grouped[parts[0]] = []
		grouped[parts[0]].append(parts[1])
	#_log("Event Bus", "Handlers connected: %s" % [grouped])
	_eb_log(str(self), "Handlers connected: %s" % [grouped], 0)


# ==============================
# Event Invocation
# ==============================
func _invoke_event(ns_name: String, event_name: String, args: Array, peer_id: int = -1) -> void:
	if !_validate_event(ns_name, event_name):
		#_log("Event Bus", "Invalid event: %s::%s" % [ns_name, event_name], LogLevel.ERROR)
		_eb_log(str(self), "Invalid event: %s::%s" % [ns_name, event_name], 2)
		return

	if !_validate_args(ns_name, event_name, args):
		#_log("Event Bus", "Argument validation failed for %s::%s" % [ns_name, event_name], LogLevel.ERROR)
		_eb_log(str(self), "Argument validation failed for %s::%s" % [ns_name, event_name], 2)
		return

	#  Call custom validator if exists
	if has_node("/root/EventManager"):
		var event_manager = get_node("/root/EventManager")
		if not event_manager._validate_event(event_name, args): # This calls your validator
			#_log("Event Bus", "Validator blocked %s::%s with args %s" % [ns_name, event_name, args], LogLevel.WARN)
			_eb_log(str(self), "Validator blocked %s::%s with args %s" % [ns_name, event_name, args], 1)
			return

	var signal_name = _signal_name(ns_name, event_name)
	if has_signal(signal_name):
		callv("emit_signal", [signal_name] + args)

	if DEBUG:
		#_log("Trigger Local", "Emit Local %s::%s %s" % [ns_name, event_name, args])
		_eb_log(str(self), "Emit Local %s::%s %s" % [ns_name, event_name, args], 0)


# ==============================
# RPC Handler (with Invoke log added)
# ==============================
@rpc("any_peer", "call_local", "reliable")
func rpc_event(ns_name: String, event_name: String, args: Array) -> void:
	if !_validate_event(ns_name, event_name):
		#_log("Event Bus", "Invalid RPC event: %s::%s" % [ns_name, event_name], LogLevel.ERROR)
		_eb_log(str(self), "Invalid RPC event: %s::%s" % [ns_name, event_name], 2)
		return

	if !_validate_args(ns_name, event_name, args):
		#_log("Event Bus", "RPC argument mismatch for %s::%s" % [ns_name, event_name], LogLevel.ERROR)
		_eb_log(str(self), "RPC argument mismatch for %s::%s" % [ns_name, event_name], 2)
		return

	# Call custom validator if exists
	if has_node("/root/EventManager"):
		var event_manager = get_node("/root/EventManager")
		if not event_manager._validate_event(event_name, args):
			#_log("Event Bus", "Validator blocked RPC %s::%s with args %s" % [ns_name, event_name, args], LogLevel.WARN)
			_eb_log(str(self), "Validator blocked RPC %s::%s with args %s" % [ns_name, event_name, args], 1)
			return

	var signal_name = _signal_name(ns_name, event_name)
	if has_signal(signal_name):
		callv("emit_signal", [signal_name] + args)
		if DEBUG:
			#_log("Trigger Remote", "Emit Local %s::%s %s" % [ns_name, event_name, args])
			_eb_log(str(self), "Emit Local -> %s::%s = %s" % [ns_name, event_name, args], 4)

	if DEBUG:
		#_log("Event Bus", "RPC processed: %s::%s %s" % [ns_name, event_name, args])
		_eb_log(str(self), "RPC processed -> %s::%s = %s" % [ns_name, event_name, args], 4)


# ==============================
# Validation Helpers
# ==============================
func _validate_event(ns_name: String, event_name: String) -> bool:
	return EVENTS.has(ns_name) and EVENTS[ns_name].any(func(e): return e["name"] == event_name)


func _validate_args(ns_name: String, event_name: String, args: Array) -> bool:
	var schema_list = EVENTS.get(ns_name, [])
	var event_schema = schema_list.filter(func(e): return e["name"] == event_name)
	if event_schema.is_empty():
		return false

	var expected_args: Array = event_schema[0].get("args", [])
	if args.size() != expected_args.size():
		return false

	for i in range(args.size()):
		var expected_type: String = expected_args[i].get("type", "Variant")
		var actual_type: int = typeof(args[i])
		if !_is_type_match(expected_type, actual_type):
			return false

	return true


func _is_type_match(expected: String, actual_type: int) -> bool:
	match expected:
		"int": return actual_type == TYPE_INT
		"float": return actual_type == TYPE_FLOAT
		"String": return actual_type == TYPE_STRING
		"bool": return actual_type == TYPE_BOOL
		"Array": return actual_type == TYPE_ARRAY
		"Dictionary": return actual_type == TYPE_DICTIONARY
		_: return true


func _signal_name(ns: String, ev: String) -> String:
	return ns + "_" + ev


func _log_initialization_summary():
	if DEBUG:
		var namespaces = EVENTS.keys()
		var rpc_counts := {}
		for ns_name in EVENTS.keys():
			rpc_counts[ns_name] = EVENTS[ns_name].size()

		_eb_log(str(self), "Initialized | Namespaces: %s" % [namespaces], 4)
		_eb_log(str(self), "RPC Config -> Event Counts: %s" % [rpc_counts], 4)


func _get_event_schema(ns_name: String, event_name: String) -> Dictionary:
	if !EVENTS.has(ns_name):
		return {}
	for ev in EVENTS[ns_name]:
		if ev.get("name", "") == event_name:
			return ev
	return {}

# Did not work as a remote sync error happens: remote sender mismatch, can`t change rpc configs on the fly so to say
# E 0:00:38:215   process_simplify_path: The rpc node checksum failed. Make sure to have the same methods on both nodes. Node path: EventBus
#  <C++ Source>  modules/multiplayer/scene_cache_interface.cpp:121 @ process_simplify_path()

#func _apply_rpc_config_for(ns_name: String, event_name: String) -> void:
	#var ev := _get_event_schema(ns_name, event_name)
	#if ev.is_empty():
		#return
#
	#var mode := ev.get("mode", "any_peer")
	#var sync := ev.get("sync", "call_remote")
	#var transfer_mode := ev.get("transfer_mode", "reliable")
	#var transfer_channel := int(ev.get("transfer_channel", 0))
#
	#var rpc_mode := (MultiplayerAPI.RPC_MODE_AUTHORITY
		#if mode == "authority"
		#else MultiplayerAPI.RPC_MODE_ANY_PEER)
#
	#var call_local = (sync == "call_local")
#
	#var transfer_enum: int
	#match transfer_mode:
		#"unreliable":
			#transfer_enum = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		#"unreliable_ordered":
			#transfer_enum = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		#_:
			#transfer_enum = MultiplayerPeer.TRANSFER_MODE_RELIABLE
#
	#rpc_config("rpc_event", {
		#"rpc_mode": rpc_mode,
		#"call_local": call_local,
		#"transfer_mode": transfer_enum,
		#"channel": transfer_channel
	#})
