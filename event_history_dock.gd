@tool
extends MarginContainer

const EventHistoryConfig = preload("res://addons/TAB_EventHistoryLog/event_history_config.gd")

var _is_refreshing := false
var _last_log_position := 0
var _loaded_log_file_path := ""
var _rendered_lines: PackedStringArray = []
var _rendered_event_ids := {}
var _log_output: RichTextLabel
var _event_history: Node

@onready var _tabs: TabContainer = %Tabs
@onready var _log_output_host: Control = %LogOutputHost
@onready var _clear_log_button: Button = %ClearLogButton
@onready var _log_file_path_input: LineEdit = %LogFilePathInput
@onready var _text_node_class_input: LineEdit = %TextNodeClassInput
@onready var _pick_text_node_class_button: Button = %PickTextNodeClassButton
@onready var _clear_text_node_class_button: Button = %ClearTextNodeClassButton
@onready var _sync_interval_input: SpinBox = %SyncIntervalInput
@onready var _write_log_only_in_debug_checkbox: CheckBox = %WriteLogOnlyInDebugCheckbox
@onready var _poll_timer := Timer.new()


func _ready() -> void:
	EventHistoryConfig.ensure_project_settings()
	_style_tabs()
	_connect_signals()
	_connect_event_history()
	_setup_poll_timer()
	_rebuild_log_output()
	_load_settings()
	_poll_log_file()


func _exit_tree() -> void:
	if _poll_timer.timeout.is_connected(_on_poll_timer_timeout):
		_poll_timer.timeout.disconnect(_on_poll_timer_timeout)

	if _event_history != null:
		if _event_history.event_buffered.is_connected(_on_event_history_event_buffered):
			_event_history.event_buffered.disconnect(_on_event_history_event_buffered)
		if _event_history.history_cleared.is_connected(_on_event_history_history_cleared):
			_event_history.history_cleared.disconnect(_on_event_history_history_cleared)


func _connect_signals() -> void:
	if not _clear_log_button.pressed.is_connected(_on_clear_log_button_pressed):
		_clear_log_button.pressed.connect(_on_clear_log_button_pressed)
	if not _log_file_path_input.text_submitted.is_connected(_on_log_file_path_input_text_submitted):
		_log_file_path_input.text_submitted.connect(_on_log_file_path_input_text_submitted)
	if not _log_file_path_input.focus_exited.is_connected(_on_log_file_path_input_focus_exited):
		_log_file_path_input.focus_exited.connect(_on_log_file_path_input_focus_exited)
	if not _pick_text_node_class_button.pressed.is_connected(_on_pick_text_node_class_button_pressed):
		_pick_text_node_class_button.pressed.connect(_on_pick_text_node_class_button_pressed)
	if not _clear_text_node_class_button.pressed.is_connected(_on_clear_text_node_class_button_pressed):
		_clear_text_node_class_button.pressed.connect(_on_clear_text_node_class_button_pressed)
	if not _sync_interval_input.value_changed.is_connected(_on_sync_interval_input_value_changed):
		_sync_interval_input.value_changed.connect(_on_sync_interval_input_value_changed)
	if not _write_log_only_in_debug_checkbox.toggled.is_connected(_on_write_log_only_in_debug_checkbox_toggled):
		_write_log_only_in_debug_checkbox.toggled.connect(_on_write_log_only_in_debug_checkbox_toggled)


func _connect_event_history() -> void:
	if not Engine.is_editor_hint():
		return

	_event_history = get_node_or_null("/root/EventHistory")
	if _event_history == null:
		return

	if not _event_history.event_buffered.is_connected(_on_event_history_event_buffered):
		_event_history.event_buffered.connect(_on_event_history_event_buffered)
	if not _event_history.history_cleared.is_connected(_on_event_history_history_cleared):
		_event_history.history_cleared.connect(_on_event_history_history_cleared)


func _setup_poll_timer() -> void:
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_on_poll_timer_timeout)
	add_child(_poll_timer)
	_apply_sync_interval()
	_poll_timer.start()


func _style_tabs() -> void:
	_tabs.add_theme_font_size_override(&"font_size", 18)

	for style_name in [&"tab_selected", &"tab_unselected", &"tab_hovered", &"tab_focus", &"tab_disabled"]:
		var style := _tabs.get_theme_stylebox(style_name).duplicate()
		style.content_margin_left = maxf(style.content_margin_left, 14.0)
		style.content_margin_right = maxf(style.content_margin_right, 14.0)
		style.content_margin_top = maxf(style.content_margin_top, 8.0)
		style.content_margin_bottom = maxf(style.content_margin_bottom, 8.0)
		_tabs.add_theme_stylebox_override(style_name, style)


func _load_settings() -> void:
	_is_refreshing = true
	_log_file_path_input.text = EventHistoryConfig.get_log_file_path()
	_text_node_class_input.text = EventHistoryConfig.get_text_node_class()
	_sync_interval_input.value = EventHistoryConfig.get_sync_interval_ms()
	_write_log_only_in_debug_checkbox.button_pressed = EventHistoryConfig.get_write_log_only_in_debug()
	_clear_text_node_class_button.disabled = _text_node_class_input.text == EventHistoryConfig.DEFAULT_TEXT_NODE_CLASS
	_is_refreshing = false
	_apply_sync_interval()


func _commit_log_file_path() -> void:
	if _is_refreshing:
		return

	var value := _log_file_path_input.text.strip_edges()
	if value.is_empty():
		value = EventHistoryConfig.DEFAULT_LOG_FILE_PATH

	EventHistoryConfig.set_log_file_path(value)

	_is_refreshing = true
	_log_file_path_input.text = value
	_is_refreshing = false

	_loaded_log_file_path = ""
	_last_log_position = 0
	_clear_rendered_log()
	_poll_log_file()


func _save_text_node_class(text_node_class: String) -> void:
	EventHistoryConfig.set_text_node_class(text_node_class)

	_is_refreshing = true
	_text_node_class_input.text = text_node_class
	_clear_text_node_class_button.disabled = text_node_class == EventHistoryConfig.DEFAULT_TEXT_NODE_CLASS
	_is_refreshing = false

	_rebuild_log_output()


func _apply_sync_interval() -> void:
	_poll_timer.wait_time = maxf(float(EventHistoryConfig.get_sync_interval_ms()) / 1000.0, 0.001)


func _rebuild_log_output() -> void:
	var current_text := "\n".join(_rendered_lines)

	for child in _log_output_host.get_children():
		_log_output_host.remove_child(child)
		child.queue_free()

	_log_output = EventHistoryConfig.instantiate_text_node()
	_log_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_output.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_log_output.bbcode_enabled = false
	_log_output.scroll_following = true
	_log_output.text = current_text
	_log_output_host.add_child(_log_output)


func _clear_rendered_log() -> void:
	_rendered_lines = PackedStringArray()
	_rendered_event_ids.clear()
	if _log_output != null:
		_log_output.text = ""


func _append_rendered_line(line: String) -> void:
	_rendered_lines.append(line)
	if _log_output == null:
		return

	if _log_output.text.is_empty():
		_log_output.text = line
	else:
		_log_output.text += "\n" + line


func _poll_log_file() -> void:
	var log_file_path := EventHistoryConfig.get_log_file_path()
	if log_file_path != _loaded_log_file_path:
		_loaded_log_file_path = log_file_path
		_last_log_position = 0
		_clear_rendered_log()

	if not FileAccess.file_exists(log_file_path):
		return

	var file := FileAccess.open(log_file_path, FileAccess.READ)
	if file == null:
		return

	if file.get_length() < _last_log_position:
		_last_log_position = 0
		_clear_rendered_log()

	file.seek(_last_log_position)

	while file.get_position() < file.get_length():
		var line := file.get_line()
		if line.is_empty():
			continue
		_append_log_line_from_file(line)

	_last_log_position = file.get_position()
	file.close()


func _format_log_line(line: String) -> String:
	var parsed = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		return line

	var event_data: Dictionary = parsed
	return _format_event_data(event_data)


func _format_event_data(event_data: Dictionary) -> String:
	return "#%s [%s] %s/%s %s" % [
		str(event_data.get("id", "?")),
		str(event_data.get("timestamp", "")),
		str(event_data.get("category", "")),
		str(event_data.get("event_name", "")),
		JSON.stringify(event_data.get("data", {})),
	]


func _append_log_line_from_file(line: String) -> void:
	var parsed = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		_append_rendered_line(line)
		return

	var event_data: Dictionary = parsed
	var event_id := str(event_data.get("id", ""))
	if not event_id.is_empty() and _rendered_event_ids.has(event_id):
		return

	if not event_id.is_empty():
		_rendered_event_ids[event_id] = true
	_append_rendered_line(_format_event_data(event_data))


func _on_log_file_path_input_text_submitted(_new_text: String) -> void:
	_commit_log_file_path()


func _on_log_file_path_input_focus_exited() -> void:
	_commit_log_file_path()


func _on_clear_log_button_pressed() -> void:
	if _event_history != null and _event_history.has_method("clear_history"):
		_event_history.clear_history()
	else:
		EventHistoryConfig.clear_history_file()

	_loaded_log_file_path = ""
	_last_log_position = 0
	_clear_rendered_log()


func _on_pick_text_node_class_button_pressed() -> void:
	EditorInterface.popup_create_dialog(
		_on_text_node_class_selected,
		&"RichTextLabel",
		_text_node_class_input.text,
		"Select RichTextLabel Class"
	)


func _on_clear_text_node_class_button_pressed() -> void:
	_save_text_node_class(EventHistoryConfig.DEFAULT_TEXT_NODE_CLASS)


func _on_text_node_class_selected(selected_type: StringName) -> void:
	if selected_type.is_empty():
		return

	_save_text_node_class(str(selected_type))


func _on_sync_interval_input_value_changed(new_value: float) -> void:
	if _is_refreshing:
		return

	var interval_ms := maxi(int(new_value), 1)
	EventHistoryConfig.set_sync_interval_ms(interval_ms)

	if interval_ms != int(new_value):
		_is_refreshing = true
		_sync_interval_input.value = interval_ms
		_is_refreshing = false

	_apply_sync_interval()


func _on_write_log_only_in_debug_checkbox_toggled(button_pressed: bool) -> void:
	if _is_refreshing:
		return

	EventHistoryConfig.set_write_log_only_in_debug(button_pressed)


func _on_event_history_event_buffered(event_data: Dictionary) -> void:
	if not Engine.is_editor_hint():
		return

	var event_id := str(event_data.get("id", ""))
	if not event_id.is_empty() and _rendered_event_ids.has(event_id):
		return

	if not event_id.is_empty():
		_rendered_event_ids[event_id] = true
	_append_rendered_line(_format_event_data(event_data))


func _on_event_history_history_cleared() -> void:
	_loaded_log_file_path = ""
	_last_log_position = 0
	_clear_rendered_log()


func _on_poll_timer_timeout() -> void:
	if _event_history == null and Engine.is_editor_hint():
		_connect_event_history()
	_poll_log_file()
