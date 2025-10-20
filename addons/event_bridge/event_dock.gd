@tool
extends Control

var DEBUG := ProjectSettings.get_setting("event_bridge/debug")

const DATA_PATH = "res://addons/event_bridge/generated/event_data.tres"
const JSON_PATH = "res://addons/event_bridge/generated/event_registry.json"
const API_PATH = "res://addons/event_bridge/generated/EventManager.gd"
const EXCLUDED_DIRS = ["addons", ".import", ".godot"]

#region Icons
#  Loaded icons
var icon_remove: Texture2D
var icon_add: Texture2D
var icon_edit: Texture2D
var icon_category: Texture2D
var icon_event_default: Texture2D
var icon_rpc_local: Texture2D
var icon_rpc_remote: Texture2D
var icon_rpc_to_all: Texture2D
var icon_rpc_to_id: Texture2D
var icon_debug: Texture2D
var icon_open: Texture2D
var icon_close: Texture2D
var icon_folder: Texture2D
var icon_subscriber: Texture2D
var icon_subscriber_file: Texture2D
var icon_emitter: Texture2D
var icon_emitter_file: Texture2D
#endregion

@onready var networking_warning: RichTextLabel = %NetworkingWarning

@onready var event_bridge_tab_container: TabContainer = %EventBridgeTabContainer
@onready var connections_tree = %"Connections Tree"
@onready var connections_filter: LineEdit = %ConnectionsFilter

@onready var context_menu: PopupMenu = %"ContextMenu"
@onready var category_btn: Button = %Category
@onready var event_btn: Button = %Event
@onready var generate_btn: Button = %"Generate Registry"
@onready var load_json_btn: Button = %"Load JSON"
@onready var debug_check: CheckBox = %Debug
@onready var event_tree: Tree = %"Event Categories & Events"
@onready var event_name_input: LineEdit = %LineEdit

@onready var rpc_targets: OptionButton = %"Target"
@onready var mode_dropdown: OptionButton = %"Mode"
@onready var sync_dropdown: OptionButton = %"Sync"
@onready var transfer_mode_dropdown: OptionButton = %"Transfer Mode"
@onready var transfer_channel_spinbox: SpinBox = %"Transfer Channel"

@onready var input_dialog:AcceptDialog = %InputDialog
@onready var name_field: LineEdit = %NameField
@onready var add_arg_btn: Button = %"Add Arg"
@onready var args_list: VBoxContainer = %"ArgsList"

#@onready var toast_panel: Panel = %ToastPanel
#@onready var toast_label: RichTextLabel = %ToastLabel
#@onready var toast_close_btn: Button = %ToastCloseBtn
#@onready var toast_timer: Timer = %ToastTimer

#@onready var validator_field: LineEdit = %ValidatorField
#@onready var target_label: Label = %TargetLabel

var categories = {}
var debug_mode = false
var pending_action = ""  # "category", "event", "rename"
var selected_category = null
var selected_event_index = -1
var selected_item = null
var category_order: Array = []
var event_orders: Dictionary = {}  # key: category name, value: Array of event names
var event_line_map: Dictionary = {} # Stores event_name -> line number in EventManager.gd

func _ready():
	_load_icons()
	_configure_ui()
	_connect_signals()
	_generate_context_menu()
	_load_data()
	_clear_event_details()
	_update_preview()

func _notification(what):
	if what == NOTIFICATION_EDITOR_POST_SAVE:
		print("save")
		refresh_all()
		pass

# =========================================================
# Network Warning Stack (one place for all user/editor msgs)
# =========================================================
var _warning_stack: Array[String] = []

func _warn_render() -> void:
	if _warning_stack.is_empty():
		networking_warning.clear()
		networking_warning.visible = false
		return

	# Reverse the stack so newest is first
	var lines: Array[String] = []
	for w in _warning_stack:
		lines.insert(0, "• " + w)  # insert at start instead of append

	networking_warning.text = "[color=orange]" + "\n\n".join(lines) + "[/color]"
	networking_warning.visible = true

	await get_tree().create_timer(7).timeout
	await _warn_clear()

func _warn_push(msg: String, kind: String = "info") -> void:
	# Normalize wording for end users
	match kind:
		"error":
			msg = "Error: " + msg
		"warning":
			msg = "Warning: " + msg
		_:
			pass
	# Avoid back-to-back duplicates
	if _warning_stack.is_empty() or _warning_stack.back() != msg:
		_warning_stack.append(msg)
		_warn_render()

func _warn_clear() -> void:
	_warning_stack.clear()
	_warn_render()

func refresh_all():
	print("[EventBridge] Refreshing Event Dock...")
	await _save_data()
	await _on_generate()
	await _refresh_tree()
	await _refresh_connections()

func _setup_event_tree():
	event_tree.set_drag_forwarding(
		Callable(self, "_get_drag_data"),
		Callable(self, "_can_drop_data"),
		Callable(self, "_drop_data")
	)
	event_tree.set_column_title(0, "Event Registry")
	event_tree.create_item()

func _load_icons():
	icon_remove          = _ed_icon("Remove")
	icon_edit            = _ed_icon("Edit")
	icon_add             = _ed_icon("Add")
	icon_category        = _ed_icon("Folder")

	# Generic / defaults
	icon_event_default   = _ed_icon("Folder")
	icon_folder          = _ed_icon("Folder")
	icon_open            = _ed_icon("Help")
	icon_close           = _ed_icon("Close")
	icon_debug           = _ed_icon("DebugNext")

	# RPC-ish / signals
	icon_rpc_local       = _ed_icon("Slot")
	icon_rpc_remote      = _ed_icon("Signal")
	icon_rpc_to_all      = _ed_icon("SignalsAndGroups")
	icon_rpc_to_id       = _ed_icon("MemberSignal")

	# Subscriber / emitter
	icon_subscriber      = _ed_icon("MemberMethod")
	icon_subscriber_file = _ed_icon("ExternalLink")
	icon_emitter         = _ed_icon("MemberMethod")
	icon_emitter_file    = _ed_icon("ExternalLink")

func _configure_ui():
	_setup_event_tree()
	category_btn.text = "Category"
	category_btn.icon = _ed_icon("EditorHandleAdd")
	event_btn.text = "Event"
	event_btn.icon = _ed_icon("EditorHandleAdd")

	generate_btn.text = "Generate"
	generate_btn.icon = _ed_icon("New")
	generate_btn.tooltip_text = "Generate Registry File"

	add_arg_btn.text = "Arg"
	add_arg_btn.icon = _ed_icon("Add")

	rpc_targets.clear()
	rpc_targets.add_icon_item(icon_rpc_local, "emit_local" ,0)
	rpc_targets.add_icon_item(icon_rpc_remote, "to_server" ,1)
	rpc_targets.add_icon_item(icon_rpc_to_id, "to_id" ,2)
	rpc_targets.add_icon_item(icon_rpc_to_all, "to_all" ,3)

	mode_dropdown.clear()
	mode_dropdown.add_item("authority")
	mode_dropdown.add_item("any_peer")

	sync_dropdown.clear()
	sync_dropdown.add_item("call_remote")
	sync_dropdown.add_item("call_local")

	transfer_mode_dropdown.clear()
	transfer_mode_dropdown.add_item("reliable")
	transfer_mode_dropdown.add_item("unreliable")
	transfer_mode_dropdown.add_item("unreliable_ordered")

	transfer_channel_spinbox.min_value = 0
	transfer_channel_spinbox.max_value = 32

	# After creating controls
	#rpc_targets.tooltip_text = "TARGET_TT"
	#mode_dropdown.tooltip_text = "MODE_TT"
	#sync_dropdown.tooltip_text = "SYNC_TT"
	#transfer_mode_dropdown.tooltip_text = "TRANSFER_MODE_TT"
	#transfer_channel_spinbox.tooltip_text = "TRANSFER_CHANNEL_TT"

	event_bridge_tab_container.set_tab_icon(0, icon_category)
	event_bridge_tab_container.set_tab_icon(1, icon_debug)

	# Repurpose the old toast close button as "Clear"
	#toast_close_btn.text = "Clear"
	#if not toast_close_btn.pressed.is_connected(_warn_clear):
		#toast_close_btn.pressed.connect(_warn_clear)

	# don't use floating toasts anymore
	#editor_custom_massages.visible = false
	#toast_timer.stop()

func _connect_signals():

	category_btn.pressed.connect(func():
		pending_action = "category"
		_open_input_dialog("Enter a category name")
	)

	event_btn.pressed.connect(func():
		if _get_selected_category() == null:
			_warn_push("Select a category first.", "warning")
			return
		pending_action = "event"
		_open_input_dialog("Enter an event name")
	)

	generate_btn.pressed.connect(refresh_all)
	load_json_btn.pressed.connect(_on_load_json_pressed)
	add_arg_btn.pressed.connect(_on_add_arg)
	event_tree.button_clicked.connect(_on_event_tree_button_clicked)
	input_dialog.confirmed.connect(_on_input_confirmed)
	event_tree.item_selected.connect(_on_tree_selection_changed)
	event_name_input.text_changed.connect(_on_event_name_changed)
	rpc_targets.item_selected.connect(_on_target_changed)
	mode_dropdown.item_selected.connect(_on_mode_changed)
	sync_dropdown.item_selected.connect(_on_sync_changed)
	transfer_mode_dropdown.item_selected.connect(_on_transfer_mode_changed)
	transfer_channel_spinbox.value_changed.connect(_on_transfer_channel_changed)
	event_tree.gui_input.connect(_on_tree_gui_input)

	#validator_field.text_changed.connect(func(new_text):
		#if selected_category != null and selected_event_index >= 0:
			#categories[selected_category][selected_event_index]["validator"] = new_text.strip_edges()
			#_save_data()
			#_update_preview()
	#)

	event_bridge_tab_container.tab_changed.connect(func(idx: int):
		if event_bridge_tab_container.get_tab_title(idx) == "Connections":
			_refresh_connections()
	)

	connections_filter.text_changed.connect(func(new_text):
		_refresh_connections(new_text)
	)



func _get_drag_data(at_position):
	var item = event_tree.get_item_at_position(at_position)
	if not item or item == event_tree.get_root():
		return null
	var is_category = (item.get_parent() == event_tree.get_root())
	var data = {"text": item.get_text(0), "is_category": is_category}
	var preview = Label.new()
	preview.text = data["text"]
	set_drag_preview(preview)
	return data

func _can_drop_data(at_position, data):
	var target = event_tree.get_item_at_position(at_position)
	if not target:
		return false
	var is_target_category = (target.get_parent() == event_tree.get_root())
	if data["is_category"]:
		return is_target_category
	return not is_target_category

func _drop_data(at_position, data):
	var target_item = event_tree.get_item_at_position(at_position)
	if not target_item:
		return
	if data["is_category"]:
		var cat_names = categories.keys()
		var from_idx = cat_names.find(data["text"])
		var to_idx = cat_names.find(target_item.get_text(0))
		if from_idx == -1 or to_idx == -1:
			return
		var moved_cat = cat_names[from_idx]
		cat_names.remove_at(from_idx)
		cat_names.insert(to_idx, moved_cat)
		var new_dict = {}
		for cat_name in cat_names:
			new_dict[cat_name] = categories[cat_name]
		categories = new_dict
	else:
		var parent = target_item.get_parent()
		if parent == event_tree.get_root():
			return
		var cat = parent.get_text(0)
		var events = categories[cat]
		var from_idx = events.find(events.filter(func(e): return e["name"] == data["text"])[0])
		var to_idx = target_item.get_index()
		if from_idx != -1 and to_idx != -1:
			events.insert(to_idx, events.pop_at(from_idx))
	_refresh_tree()
	_save_data()
	_on_generate()

func _open_input_dialog(title: String):
	input_dialog.title = title
	name_field.text = ""
	input_dialog.popup_centered()
	name_field.grab_focus()

func _on_input_confirmed():
	var name = name_field.text.strip_edges()
	if name == "":
		return

	if pending_action == "category":
		if !categories.has(name):
			categories[name] = []
		else:
			_warn_push("That category already exists.", "warning")

	elif pending_action == "event":
		var cat = _get_selected_category()
		if cat != null:
			if !categories[cat].any(func(e): return e["name"] == name):
				categories[cat].append({
					"name": name,
					"target": "emit_local",
					"args": []
				})
			else:
				_warn_push("This event already exists in the selected category.", "warning")

	elif pending_action == "rename":
		if selected_item:
			var parent = selected_item.get_parent()
			if parent == event_tree.get_root():
				var old_name = selected_item.get_text(0)
				if categories.has(old_name):
					categories[name] = categories[old_name]
					categories.erase(old_name)
			else:
				var cat = parent.get_text(0)
				for e in categories[cat]:
					if e["name"] == selected_item.get_text(0):
						e["name"] = name
						break

	#_warn_render()
	_refresh_tree()
	_save_data()

#func _on_debug_toggle(pressed):
	#debug_mode = pressed
	## Keep UI calm: no editor toaster; show a gentle note in the stack
	#_warn_push("Debug overlay is " + ("ON" if pressed else "OFF") + ".", "info")

	# Hide old floating panel
	#editor_custom_massages.visible = false

# Generate JSON Force reload in Editor
func _on_generate():
	var json_data = {}
	for category in categories.keys():
		json_data[category] = []
		for e in categories[category]:
			var entry = {
				"name": e.get("name", ""),
				"target": e.get("target", "emit_local"),
				"mode": e.get("mode", "any_peer"),
				"sync": e.get("sync", "call_remote"),
				"transfer_mode": e.get("transfer_mode", "reliable"),
				"transfer_channel": int(e.get("transfer_channel", 0)),
				"args": e.get("args", [])
			}
			json_data[category].append(entry)

	var json_string = JSON.stringify(json_data, "\t")

	if !FileAccess.file_exists(JSON_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(JSON_PATH))
	var file_json = FileAccess.open(JSON_PATH, FileAccess.WRITE)
	file_json.store_string(json_string)
	file_json.close()

	_generate_api_file()
	_save_data()
	_force_editor_reload()


# Generate EventManager.gd
func _generate_api_file() -> void:
	var content: String = "# Auto-generated by EventBridge. DO NOT EDIT MANUALLY.\n"
	content += "# This file will be overwritten each time 'Generate Registry' is used.\n\n"
	content += "@tool\n"
	content += "class_name EventBridgeManager\n"
	content += "extends Node\n\n"

	content += "var DEBUG := ProjectSettings.get_setting(\"event_bridge/debug\")\n\n"

	# --- Namespace properties ---
	for ns in categories.keys():
		content += "var %s: EventBusAutoload.Namespace\n" % ns

	content += "\nfunc _ready() -> void:\n"
	for ns in categories.keys():
		content += "\t%s = EventBus.get_namespace(\"%s\")\n" % [ns, ns]

	content += "\n# --- Event API ---\n"

	for ns in categories.keys():
		for e in categories[ns]:
			var func_name: String = e.get("name", "")
			var target: String = e.get("target", "emit_local")
			var mode: String = e.get("mode", "any_peer")
			var sync: String = e.get("sync", "call_remote")
			var transfer_mode: String = e.get("transfer_mode", "reliable")
			var transfer_channel: int = e.get("transfer_channel", 0)
			var args: Array = e.get("args", [])

			# --- Build arg lists ---
			var arg_defs: Array[String] = []
			var arg_names: Array[String] = []
			for arg in args:
				arg_defs.append("%s: %s" % [arg["name"], arg["type"]])
				arg_names.append(arg["name"])

			var arg_defs_str: String = ", ".join(arg_defs)     # "player_id: int, msg: String"
			var arg_names_str: String = ", ".join(arg_names)   # "player_id, msg"
			var args_array: String = "[%s]" % arg_names_str if arg_names.size() > 0 else "[]"

			# --- Namespacing: mangle symbol to avoid collisions ---
			var ns_snake = ns.to_lower()
			var mangled := "%s_%s" % [ns_snake, func_name]     # e.g. "admin_send_something_to_client"

			# ---------- Doc Block ----------
			content += "\n## Event: %s::%s ---[br]\n" % [ns, func_name]
			content += "## Target: %s | Mode: %s | Sync: %s | Transfer: %s | Channel: %d [br][br]\n" % [
				target, mode, sync, transfer_mode, transfer_channel
			]

			# Emit usage (call the generated emitter)
			content += "## Usage (emit): [br]\n"
			if target == "to_id":
				var usage_args = arg_names_str
				if usage_args != "":
					usage_args += ", "
				usage_args += "peer_id"
				content += "##     EventManager.%s(%s)\n" % [mangled, usage_args]
			else:
				content += "##     EventManager.%s(%s)\n" % [mangled, arg_names_str]

			# ---------- Emit function ----------
			var full_arg_defs = arg_defs_str
			if target == "to_id":
				if full_arg_defs != "":
					full_arg_defs += ", "
				full_arg_defs += "peer_id: int"
			content += "func %s(%s) -> void:\n" % [mangled, full_arg_defs]

			match target:
				"emit_local":
					content += "\t%s.emit(\"%s\", %s)\n" % [ns, func_name, args_array]
				"to_server":
					content += "\t%s.to_server(\"%s\", %s)\n" % [ns, func_name, args_array]
				"to_all":
					content += "\t%s.to_all(\"%s\", %s)\n" % [ns, func_name, args_array]
				"to_id":
					content += "\t%s.to_id(peer_id, \"%s\", %s)\n" % [ns, func_name, args_array]
				_:
					content += "\t%s.emit(\"%s\", %s)\n" % [ns, func_name, args_array]

			# ---------- Subscription helpers ----------
			content += "\n# Subscribe with callback signature: func(%s) -> void" % (arg_defs_str if arg_defs_str != "" else "")
			content += "\n## Usage (subscribe):[br]\n"
			if arg_defs_str == "":
				content += "##     var cb := func() -> void:\n"
			else:
				content += "##     var cb := func(%s) -> void:\n" % arg_defs_str
			content += "##     EventManager.on_%s(cb)[br]\n" % mangled
			content += "##     [br]Later, to unsubscribe (keep the same Callable reference):[br]\n"
			content += "##     EventManager.off_%s(cb)\n" % mangled
			content += "##     [br][br]One-liner subscribe example:[br]\n"
			if arg_defs_str == "":
				content += "##     EventManager.on_%s(func() -> void: print(\"%s fired\"))[br]\n" % [mangled, mangled]
			else:
				content += "##     EventManager.on_%s(func(%s) -> void: print(\"%s:\", %s))[br]\n" % [
					mangled, arg_defs_str, mangled, (arg_names_str if arg_names_str != "" else "\"\"")
				]

			content += "func on_%s(callback: Callable) -> void:\n" % mangled
			content += "\t%s.on(\"%s\", callback)\n" % [ns, func_name]

			content += "\n# Unsubscribe the same Callable you used in on_%s\n" % mangled
			content += "func off_%s(callback: Callable) -> void:\n" % mangled
			content += "\t%s.off(\"%s\", callback)\n" % [ns, func_name]

	# ---------- Global disconnect helpers ----------
	content += "\n# --- Disconnect all handlers across all namespaces ---\n"
	content += "func off_all() -> void:\n"

	var ns_list: String = ""
	var keys = categories.keys()
	for i in range(keys.size()):
		var key = keys[i]
		ns_list += "\"" + key + "\""
		if i < keys.size() - 1:
			ns_list += ", "

	content += "\tfor ns in [%s]:\n" % ns_list
	content += "\t\tif get(ns) != null:\n"
	content += "\t\t\tget(ns).off_all()\n"

	content += "\n# --- Disconnect all handlers for a specific namespace ---\n"
	content += "func off_namespace(ns_name: String) -> void:\n"
	content += "\tif get(ns_name) != null:\n"
	content += "\t\tget(ns_name).off_all()\n"

	content += "\n# --- Namespace-specific disconnect helpers ---\n"
	for ns in categories.keys():
		content += "func off_%s() -> void:\n" % ns
		content += "\tif %s != null:\n" % ns
		content += "\t\t%s.off_all()\n" % ns

	# ---------- Validator Handling ----------
	content += "\n# --- Validator Handling ---\n"
	content += "func _validate_event(event_name: String, args: Array) -> bool:\n"
	content += "\tif DEBUG:\n"
	content += "\t\tEventBridgeLogger.event_log(str(self), \"Fired for: %s with args: %s\" % [event_name, args], 3)\n\n"
	content += "\tvar validator_name = \"validate_\" + event_name\n"
	content += "\tif not has_method(validator_name):\n"
	content += "\t\treturn true\n\n"
	content += "\tvar method_info = get_method_list().filter(func(m): return m.name == validator_name)\n"
	content += "\tif method_info.is_empty():\n"
	content += "\t\tpush_warning(\"Validator method '%s' not found in method list, but has_method returned true.\" % validator_name)\n"
	content += "\t\treturn false\n\n"
	content += "\tvar method = method_info[0]\n"
	content += "\tvar result = true\n\n"
	content += "\tvar expects_array = (\n"
	content += "\t\tmethod.args.size() == 1\n"
	content += "\t\tand method.args[0].type == TYPE_ARRAY\n"
	content += "\t)\n\n"
	content += "\tif expects_array:\n"
	content += "\t\tresult = call(validator_name, args)\n"
	content += "\telse:\n"
	content += "\t\tif method.args.size() != args.size():\n"
	content += "\t\t\tpush_warning(\"Validator '%s' expected %d arguments but got %d: %s\" % [\n"
	content += "\t\t\t\tvalidator_name,\n"
	content += "\t\t\t\tmethod.args.size(),\n"
	content += "\t\t\t\targs.size(),\n"
	content += "\t\t\t\targs\n"
	content += "\t\t\t])\n"
	content += "\t\t\treturn false\n"
	content += "\t\tvar c := Callable(self, validator_name)\n"
	content += "\t\tvar result_variant = c.callv(args)\n"
	content += "\t\tif result_variant == null:\n"
	content += "\t\t\tpush_warning(\"Validator '%s' callv returned null with args: %s\" % [validator_name, args])\n"
	content += "\t\t\treturn false\n"
	content += "\t\tresult = result_variant\n\n"
	content += "\tif not result:\n"
	content += "\t\tpush_warning(\"Validation failed for event '%s'. Ignored.\" % event_name)\n"
	content += "\t\treturn false\n\n"
	content += "\treturn true\n"

	# Write file
	if FileAccess.file_exists(API_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(API_PATH))
	var file_api = FileAccess.open(API_PATH, FileAccess.WRITE)
	file_api.store_string(content)
	file_api.close()

	_build_event_line_map()


# Force Godot to reload scripts & filesystem
func _force_editor_reload():
	EditorInterface.get_resource_filesystem().scan()
	if debug_mode:
		print("[EventBridge] Filesystem refreshed.")

func _refresh_tree():
	event_tree.clear()
	event_tree.set_columns(2)
	event_tree.set_column_title(0, "Event Registry")
	event_tree.set_column_title(1, "Channel")
	event_tree.set_column_title_alignment(0, 0)
	event_tree.set_column_title_alignment(1, 0)
	event_tree.set_column_expand(1, 0)

	var root = event_tree.create_item()

	for category in categories.keys():
		var cat_item = event_tree.create_item(root)
		cat_item.set_text(0, category)
		cat_item.set_icon(0, icon_category)
		cat_item.set_selectable(1, false)

		for i in range(categories[category].size()):
			var event_data = categories[category][i]
			var event_name = event_data["name"]
			var channel = int(event_data.get("transfer_channel", 0))

			var ev_item = event_tree.create_item(cat_item)
			ev_item.set_text(0, event_name)
			ev_item.set_text(1, str(channel))
			ev_item.set_text_alignment(1, 1)
			ev_item.set_icon(0, _get_icon_for_target(event_data["target"]))

			# NEW: store mangled name so the editor jumps to the right function
			var ns_snake = category.to_lower()
			var mangled := "%s_%s" % [ns_snake, event_name]
			ev_item.set_metadata(0, mangled)
			ev_item.add_button(0, icon_open, false, 0, "Open in EventManager.gd")

func _on_tree_selection_changed():
	selected_item = event_tree.get_selected()
	if selected_item == null:
		_clear_event_details()
		return

	var parent = selected_item.get_parent()
	if parent == null or parent == event_tree.get_root():
		_clear_event_details()
		return

	selected_category = parent.get_text(0)
	var event_name = selected_item.get_text(0)

	if not categories.has(selected_category):
		_clear_event_details()
		return

	selected_event_index = -1
	for i in range(categories[selected_category].size()):
		if categories[selected_category][i].get("name", "") == event_name:
			selected_event_index = i
			break

	if selected_event_index == -1:
		_clear_event_details()
		return

	event_name_input.text = event_name
	event_name_input.set_right_icon(_ed_icon("Edit"))

	var event_data: Dictionary = categories[selected_category][selected_event_index]

	var target_value = event_data.get("target", "emit_local")
	var target_idx = 0
	for i in range(rpc_targets.item_count):
		if rpc_targets.get_item_text(i) == target_value:
			target_idx = i
			break
	rpc_targets.select(target_idx)

	var mode_value = event_data.get("mode", "any_peer")
	var mode_idx = 0
	for i in range(mode_dropdown.item_count):
		if mode_dropdown.get_item_text(i) == mode_value:
			mode_idx = i
			break
	mode_dropdown.select(mode_idx)

	var sync_value = event_data.get("sync", "call_remote")
	var sync_idx = 0
	for i in range(sync_dropdown.item_count):
		if sync_dropdown.get_item_text(i) == sync_value:
			sync_idx = i
			break
	sync_dropdown.select(sync_idx)

	var transfer_value = event_data.get("transfer_mode", "reliable")
	var transfer_idx = 0
	for i in range(transfer_mode_dropdown.item_count):
		if transfer_mode_dropdown.get_item_text(i) == transfer_value:
			transfer_idx = i
			break
	transfer_mode_dropdown.select(transfer_idx)

	transfer_channel_spinbox.value = event_data.get("transfer_channel", 0)

	#validator_field.text = event_data.get("validator", "")

	_refresh_args_list()
	_update_preview()

func _refresh_args_list() -> void:
	for child in args_list.get_children():
		child.queue_free()
	if selected_category == null or selected_event_index < 0:
		return
	var args = categories[selected_category][selected_event_index]["args"]
	for i in range(args.size()):
		var hbox = HBoxContainer.new()

		var arg_edit = LineEdit.new()
		arg_edit.text = args[i]["name"]
		arg_edit.placeholder_text = "arg%d" % (i + 1)
		arg_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		arg_edit.set_right_icon(_ed_icon("ArrowLeft"))
		arg_edit.text_changed.connect(func(new_text, idx := i):
			if selected_category != null and selected_event_index >= 0:
				categories[selected_category][selected_event_index]["args"][idx]["name"] = new_text
				_save_data()
				_update_preview()
		)

		var type_dropdown = OptionButton.new()
		#TODO: Check This
		var types = ["String", "int", "float", "bool", "Array", "Vector2", "Vector3", "Dictionary", "NodePath"]
		for t in types:
			type_dropdown.add_item(t)
		var current_type = args[i].get("type", "String")
		var selected_idx = types.find(current_type)
		type_dropdown.select(selected_idx if selected_idx != -1 else 0)
		type_dropdown.item_selected.connect(func(idx, arg_idx := i):
			categories[selected_category][selected_event_index]["args"][arg_idx]["type"] = type_dropdown.get_item_text(idx)
			_save_data()
			_update_preview()
		)

		var remove_btn = Button.new()
		remove_btn.icon = icon_close
		remove_btn.pressed.connect(func(idx := i):
			_on_remove_arg(idx)
		)

		hbox.add_child(arg_edit)
		hbox.add_child(type_dropdown)
		hbox.add_child(remove_btn)
		args_list.add_child(hbox)

func _on_event_name_changed(new_text):
	if selected_category != null and selected_event_index >= 0:
		categories[selected_category][selected_event_index]["name"] = new_text
		_refresh_tree()
		_save_data()
		_update_preview()

func _on_target_changed(index):
	if selected_category == null or selected_event_index < 0:
		return
	categories[selected_category][selected_event_index]["target"] = rpc_targets.get_item_text(index)

	if rpc_targets.get_item_text(index) == "to_id":
		_warn_push("When target is 'to_id', the handler also receives 'peer_id: int' as the last argument.", "info")
		print("When target is 'to_id', the handler also receives 'peer_id: int' as the last argument. No need to set a 'peer_id' as custom argument", "info")

	#_warn_render()
	_save_data()
	_update_preview()

func _on_mode_changed(index):
	if selected_category == null or selected_event_index < 0:
		return
	categories[selected_category][selected_event_index]["mode"] = mode_dropdown.get_item_text(index)

	_save_data()
	_update_preview()
	if debug_mode:
		print("[EventBridge] Mode changed to:", mode_dropdown.get_item_text(index))

func _on_sync_changed(index):

	if selected_category == null or selected_event_index < 0:
		return
	categories[selected_category][selected_event_index]["sync"] = sync_dropdown.get_item_text(index)

	_save_data()
	_update_preview()
	if debug_mode:
		print("[EventBridge] Sync changed to:", sync_dropdown.get_item_text(index))

func _on_transfer_mode_changed(index):
	if selected_category == null or selected_event_index < 0:
		return
	categories[selected_category][selected_event_index]["transfer_mode"] = transfer_mode_dropdown.get_item_text(index)

	_save_data()
	_update_preview()
	if debug_mode:
		print("[EventBridge] Transfer Mode changed to:", transfer_mode_dropdown.get_item_text(index))

func _on_transfer_channel_changed(value):
	if selected_category == null or selected_event_index < 0:
		return
	if not categories.has(selected_category):
		return
	categories[selected_category][selected_event_index]["transfer_channel"] = int(value)

	_save_data()
	_update_preview()
	if debug_mode:
		print("[EventBridge] Transfer Channel changed to:", value)

func _on_add_arg():
	if selected_category != null and selected_event_index >= 0:
		var args = categories[selected_category][selected_event_index]["args"]
		args.append({"name": "arg%d" % (args.size() + 1), "type": "String"})
		_refresh_args_list()
		_save_data()
		_update_preview()

func _on_remove_arg(idx):
	if selected_category != null and selected_event_index >= 0:
		var args = categories[selected_category][selected_event_index]["args"]
		if idx >= 0 and idx < args.size():
			args.remove_at(idx)
	_refresh_args_list()
	_save_data()
	_update_preview()

func _update_preview() -> void:
	if selected_category == null or selected_event_index < 0:
		#TODO Check this
		networking_warning.visible = false
		return

	var ns: String = selected_category
	var event_data: Dictionary = categories[ns][selected_event_index]
	var event_name: String = event_data["name"]

	var target: String = event_data.get("target", "emit_local")
	var mode: String = event_data.get("mode", "any_peer")
	var sync: String = event_data.get("sync", "call_remote")
	var transfer_mode: String = event_data.get("transfer_mode", "reliable")
	var transfer_channel: int = event_data.get("transfer_channel", 0)
	var args: Array = event_data.get("args", [])

	var typed_args: Array[String] = []
	var arg_names: Array[String] = []
	for arg in args:
		typed_args.append("%s: %s" % [arg["name"], arg.get("type", "Variant")])
		arg_names.append(arg["name"])

	var typed_args_str: String = ", ".join(typed_args)
	var arg_names_str: String = ", ".join(arg_names)
	var args_array_str: String = "[%s]" % arg_names_str if arg_names.size() > 0 else "[]"

	var func_signature = "func %s(%s) -> void:" % [event_name, typed_args_str]

	var call_example: String = ""
	match target:
		"emit_local":
			call_example = "%s.emit(\"%s\", %s)" % [ns, event_name, args_array_str]
		"to_server":
			call_example = "%s.to_server(\"%s\", %s)" % [ns, event_name, args_array_str]
		"to_all":
			call_example = "%s.to_all(\"%s\", %s)" % [ns, event_name, args_array_str]
		"to_id":
			call_example = "%s.to_id(peer_id, \"%s\", %s)" % [ns, event_name, args_array_str]
		_:
			call_example = "%s.emit(\"%s\", %s)" % [ns, event_name, args_array_str]


func _get_selected_category():
	if selected_item == null:
		return null
	var parent = selected_item.get_parent()
	if parent == null:
		return null
	if parent == event_tree.get_root():
		return selected_item.get_text(0)
	else:
		return parent.get_text(0)

func _clear_event_details():
	event_name_input.text = ""
	rpc_targets.select(0)
	selected_category = null
	selected_event_index = -1
	for child in args_list.get_children():
		child.queue_free()

func _save_data():
	var data = EventBridgeData.new()
	data.categories = categories
	data.category_order = categories.keys()
	data.event_orders = {}
	for cat in categories.keys():
		data.event_orders[cat] = categories[cat].map(func(e): return e["name"])
	ResourceSaver.save(data, DATA_PATH)

func _load_data():
	if FileAccess.file_exists(DATA_PATH):
		var data = ResourceLoader.load(DATA_PATH)
		if data and data is EventBridgeData:
			categories = {}
			if data.category_order:
				for cat in data.category_order:
					if data.categories.has(cat):
						var events = data.categories[cat]
						var ordered_events = []
						if data.event_orders.has(cat):
							for ev_name in data.event_orders[cat]:
								var ev = events.filter(func(e): return e["name"] == ev_name)
								if ev.size() > 0:
									ordered_events.append(ev[0])
						categories[cat] = ordered_events
				_refresh_tree()

#region Context Menu Functions

func _generate_context_menu():
	context_menu.clear()
	context_menu.add_icon_item(icon_add, "Category", 1)
	context_menu.add_separator()
	context_menu.add_icon_item(icon_add, "Event", 2)
	context_menu.add_separator()
	context_menu.add_icon_item(icon_edit, "Rename", 3)
	context_menu.add_separator()
	context_menu.add_icon_item(icon_remove, "Delete", 4)

	context_menu.id_pressed.connect(_on_context_action)
	context_menu.about_to_popup.connect(_on_context_menu_open)

func _on_tree_gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var local_pos = event.position
		var item = event_tree.get_item_at_position(local_pos)
		if item:
			event_tree.set_selected(item, 0)
			selected_item = item
			var global_pos = get_viewport().get_mouse_position()
			var rect = Rect2i(global_pos, Vector2i.ZERO)
			context_menu.popup_on_parent(rect)

func _on_context_action(id):
	match id:
		1: _add_category()
		2: _add_event_here()
		3: _start_rename_selected()
		4: _delete_selected()

func _on_context_menu_open():
	context_menu.clear()
	var selected = event_tree.get_selected()
	if selected:
		var parent = selected.get_parent()
		if parent == event_tree.get_root():
			context_menu.add_icon_item(icon_add, "Category", 1)
			context_menu.add_icon_item(icon_add, "Event", 2)
		else:
			context_menu.add_icon_item(icon_add, "Event", 2)
		context_menu.add_separator()
		context_menu.add_icon_item(icon_edit, "Rename", 3)
		context_menu.add_separator()
		context_menu.add_icon_item(icon_remove, "Delete", 4)
	else:
		context_menu.add_icon_item(icon_add, "Category", 1)

func _start_rename_selected():
	if selected_item == null:
		return
	pending_action = "rename"
	input_dialog.title = "Rename"
	name_field.text = selected_item.get_text(0)
	input_dialog.popup_centered()
	name_field.grab_focus()

func _delete_selected():
	if selected_item == null:
		return
	var parent = selected_item.get_parent()
	if parent == event_tree.get_root():
		categories.erase(selected_item.get_text(0))
	else:
		var cat = parent.get_text(0)
		var ev_name = selected_item.get_text(0)
		categories[cat] = categories[cat].filter(func(e): return e["name"] != ev_name)
	_refresh_tree()
	_save_data()

func _add_event_here():
	var selected = event_tree.get_selected()
	if selected == null:
		return
	var parent = selected.get_parent()
	if parent == event_tree.get_root():
		pending_action = "event"
		_open_input_dialog("Add Event to " + selected.get_text(0))
	else:
		var category = parent.get_text(0)
		pending_action = "event"
		_open_input_dialog("Add Event to " + category)

func _add_category():
	pending_action = "category"
	_open_input_dialog("Add New Category")

#endregion

func _refresh_connections(filter: String = "") -> void:
	connections_tree.clear()
	var root = connections_tree.create_item()
	connections_tree.set_column_title(0, "Static Event Usage Map")

	var event_registry: Dictionary = {}
	if FileAccess.file_exists(JSON_PATH):
		var file = FileAccess.open(JSON_PATH, FileAccess.READ)
		event_registry = JSON.parse_string(file.get_as_text())
		file.close()

	var result: Dictionary = {}
	_scan_project_for_connections(result)

	for ns_name in event_registry.keys():
		var ns_item = connections_tree.create_item(root)
		ns_item.set_text(0, ns_name)
		ns_item.set_icon(0, icon_folder)

		var ns_snake = ns_name.to_lower()

		for event_data in event_registry[ns_name]:
			var event_name: String = event_data["name"]
			var target_mode: String = event_data.get("target", "emit_local")

			# NEW: use namespaced key to match what the parser stores
			var mangled_key := "%s_%s" % [ns_snake, event_name]

			if not result.has(mangled_key):
				continue

			if filter != "" and not event_name.to_lower().contains(filter.to_lower()):
				continue

			var event_item = connections_tree.create_item(ns_item)
			event_item.set_text(0, event_name)
			event_item.set_icon(0, _get_icon_for_target(target_mode))
			event_item.set_tooltip_text(0, "RPC: " + target_mode)
			_apply_bold_default_font(event_item, 0, 30, Color(1, 1, 0))

			var subscribers = result[mangled_key].get("subscribers", [])
			var emitters    = result[mangled_key].get("emitters", [])

			if subscribers.size() > 0:
				var sub_root = connections_tree.create_item(event_item)
				sub_root.set_text(0, "Subscribers")
				sub_root.set_icon(0, icon_subscriber)
				sub_root.set_custom_color(0, Color(0.4, 0.8, 1))
				for sub in subscribers:
					var sub_item = connections_tree.create_item(sub_root)
					sub_item.set_text(0, "%s (line %d)" % [sub["file"], sub["line"]])
					sub_item.set_icon(0, icon_subscriber_file)
					sub_item.set_tooltip_text(0, "Double Click to open")
					sub_item.set_metadata(0, sub)

			if emitters.size() > 0:
				var emit_root = connections_tree.create_item(event_item)
				emit_root.set_text(0, "Emitters")
				emit_root.set_icon(0, icon_emitter)
				emit_root.set_custom_color(0, Color(0.4, 1, 0.4))
				for em in emitters:
					var emit_item = connections_tree.create_item(emit_root)
					emit_item.set_text(0, "%s (line %d)" % [em["file"], em["line"]])
					emit_item.set_icon(0, icon_emitter_file)
					emit_item.set_tooltip_text(0, "Emitter in:\n" + em["file"])
					emit_item.set_metadata(0, em)

	if not connections_tree.item_activated.is_connected(_on_connections_item_activated):
		connections_tree.item_activated.connect(_on_connections_item_activated)

func _on_connections_item_activated():
	var selected = connections_tree.get_selected()
	if not selected:
		return
	var data = selected.get_metadata(0)
	if typeof(data) == TYPE_DICTIONARY and data.has("file") and data.has("line"):
		var file_path = data["file"]
		var line_number = data["line"]
		var script = load(file_path)
		EditorInterface.edit_script(script, line_number)

func _scan_project_for_connections(result: Dictionary) -> void:
	var dir = DirAccess.open("res://")
	_scan_directory(dir, result)


func _scan_directory(dir: DirAccess, result: Dictionary) -> void:
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			var file_path = dir.get_current_dir() + "/" + file_name
			_parse_script(file_path, result)
	for sub_dir in dir.get_directories():
		if sub_dir.begins_with(".") or sub_dir in EXCLUDED_DIRS:
			continue
		_scan_directory(DirAccess.open(dir.get_current_dir() + "/" + sub_dir), result)

func _parse_script(path: String, result: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()

	var lines = content.split("\n")

	var regex_sub = RegEx.new()
	regex_sub.compile(r"EventManager\.on_([a-zA-Z0-9_]+)")
	for i in range(lines.size()):
		if regex_sub.search(lines[i]):
			for match in regex_sub.search_all(lines[i]):
				var event_name = match.get_string(1) # already mangled (e.g. clients_press_key_h)
				if not result.has(event_name):
					result[event_name] = {"subscribers": [], "emitters": []}
				result[event_name]["subscribers"].append({"file": path, "line": i + 1})

	var regex_emit = RegEx.new()
	# NEW: exclude on_ / off_ from emitter matches
	regex_emit.compile(r"EventManager\.(?!on_|off_)([a-zA-Z0-9_]+)\(")
	for i in range(lines.size()):
		if regex_emit.search(lines[i]):
			for match in regex_emit.search_all(lines[i]):
				var event_name = match.get_string(1) # already mangled (e.g. clients_press_key_h)
				if not result.has(event_name):
					result[event_name] = {"subscribers": [], "emitters": []}
				result[event_name]["emitters"].append({"file": path, "line": i + 1})

# so we know where to jump in EventManager.gd
func _build_event_line_map() -> void:
	event_line_map.clear()
	if not FileAccess.file_exists(API_PATH):
		return
	var file = FileAccess.open(API_PATH, FileAccess.READ)
	var lines = file.get_as_text().split("\n")
	file.close()
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.begins_with("func "):
			var func_name = line.replace("func ", "").split("(")[0]
			if func_name.begins_with("on_"):
				func_name = func_name.substr(3)
			event_line_map[func_name] = i + 1

func _on_event_tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button: int):
	var event_name = item.get_metadata(0)
	if event_name and event_line_map.has(event_name):
		if FileAccess.file_exists(API_PATH):
			EditorInterface.edit_script(load(API_PATH), event_line_map[event_name])
		else:
			_warn_push("Generate EventManager.gd first.", "warning")
	#_warn_render()

func _apply_bold_default_font(item: TreeItem, column: int, font_size: int = 18, color: Color = Color(1, 1, 0)):
	var system_font := SystemFont.new()
	system_font.font_names = ["Sans", "Arial", "Roboto"]
	system_font.font_weight = 900
	item.set_custom_font(column, system_font)

func _on_load_json_pressed():
	var file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.json"]
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	add_child(file_dialog)
	file_dialog.popup_centered()
	file_dialog.connect("file_selected", Callable(self, "_on_json_file_selected"))

func _on_json_file_selected(path: String):
	if not FileAccess.file_exists(path):
		_warn_push("File not found: " + path, "error")
		#_warn_render()
		return

	var file = FileAccess.open(path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_warn_push("The JSON structure is invalid.", "error")
		#_warn_render()
		return

	for cat_name in parsed.keys():
		if typeof(parsed[cat_name]) != TYPE_ARRAY:
			_warn_push("Invalid schema in category: " + cat_name, "error")
			#_warn_render()
			return
		for event in parsed[cat_name]:
			if !event.has("name") or !event.has("target"):
				_warn_push("Invalid event entry in " + cat_name, "error")
				#_warn_render()
				return

	categories = parsed

	_refresh_tree()
	if selected_category != null and selected_event_index >= 0:
		_refresh_dropdowns_from_event(categories[selected_category][selected_event_index])

	_update_preview()


func _get_option_index(dropdown: OptionButton, text: String) -> int:
	for i in range(dropdown.item_count):
		if dropdown.get_item_text(i) == text:
			return i
	return -1

func _refresh_dropdowns_from_event(event: Dictionary):
	var target_idx = _get_option_index(rpc_targets, event.get("target", "emit_local"))
	if target_idx != -1:
		rpc_targets.select(target_idx)

	var mode_idx = _get_option_index(mode_dropdown, event.get("mode", "any_peer"))
	if mode_idx != -1:
		mode_dropdown.select(mode_idx)

	var sync_idx = _get_option_index(sync_dropdown, event.get("sync", "call_remote"))
	if sync_idx != -1:
		sync_dropdown.select(sync_idx)

	var transfer_idx = _get_option_index(transfer_mode_dropdown, event.get("transfer_mode", "reliable"))
	if transfer_idx != -1:
		transfer_mode_dropdown.select(transfer_idx)

	transfer_channel_spinbox.value = int(event.get("transfer_channel", 0))

#region Helpers
# Helper to choose the right event icon
func _get_icon_for_target(rpc: String) -> Texture2D:
	match rpc:
		"emit_local": return icon_rpc_local
		"to_server": return icon_rpc_remote
		"to_all": return icon_rpc_to_all
		"to_id": return icon_rpc_to_id
		_: return icon_event_default

# Helper to get Godot EditorIcons
func _ed_icon(name: String) -> Texture2D:
	var root := get_tree().get_root() # EditorNode in the editor

	if Engine.is_editor_hint() and root and root.has_theme_icon(name, "EditorIcons"):
		return root.get_theme_icon(name, "EditorIcons")

	return null
#endregion
