extends RefCounted

const LOG_FILE_PATH_SETTING := "tab_event_history_log/log_file_path"
const TEXT_NODE_CLASS_SETTING := "tab_event_history_log/text_node_class"
const SYNC_INTERVAL_MS_SETTING := "tab_event_history_log/sync_interval_ms"
const WRITE_LOG_ONLY_IN_DEBUG_SETTING := "tab_event_history_log/write_log_only_in_debug"

const DEFAULT_LOG_FILE_PATH := "user://event_history_log.txt"
const DEFAULT_TEXT_NODE_CLASS := "RichTextLabel"
const DEFAULT_SYNC_INTERVAL_MS := 1000
const DEFAULT_WRITE_LOG_ONLY_IN_DEBUG := true


static func ensure_project_settings() -> void:
	if not ProjectSettings.has_setting(LOG_FILE_PATH_SETTING):
		ProjectSettings.set_setting(LOG_FILE_PATH_SETTING, DEFAULT_LOG_FILE_PATH)
	if not ProjectSettings.has_setting(TEXT_NODE_CLASS_SETTING):
		ProjectSettings.set_setting(TEXT_NODE_CLASS_SETTING, DEFAULT_TEXT_NODE_CLASS)
	if not ProjectSettings.has_setting(SYNC_INTERVAL_MS_SETTING):
		ProjectSettings.set_setting(SYNC_INTERVAL_MS_SETTING, DEFAULT_SYNC_INTERVAL_MS)
	if not ProjectSettings.has_setting(WRITE_LOG_ONLY_IN_DEBUG_SETTING):
		ProjectSettings.set_setting(WRITE_LOG_ONLY_IN_DEBUG_SETTING, DEFAULT_WRITE_LOG_ONLY_IN_DEBUG)


static func get_log_file_path() -> String:
	ensure_project_settings()
	return str(ProjectSettings.get_setting(LOG_FILE_PATH_SETTING))


static func set_log_file_path(value: String) -> void:
	ProjectSettings.set_setting(LOG_FILE_PATH_SETTING, value)
	_save_project_settings()


static func get_text_node_class() -> String:
	ensure_project_settings()
	return str(ProjectSettings.get_setting(TEXT_NODE_CLASS_SETTING))


static func set_text_node_class(value: String) -> void:
	ProjectSettings.set_setting(TEXT_NODE_CLASS_SETTING, value)
	_save_project_settings()


static func get_sync_interval_ms() -> int:
	ensure_project_settings()
	return int(ProjectSettings.get_setting(SYNC_INTERVAL_MS_SETTING))


static func set_sync_interval_ms(value: int) -> void:
	ProjectSettings.set_setting(SYNC_INTERVAL_MS_SETTING, maxi(value, 1))
	_save_project_settings()


static func get_write_log_only_in_debug() -> bool:
	ensure_project_settings()
	return bool(ProjectSettings.get_setting(WRITE_LOG_ONLY_IN_DEBUG_SETTING))


static func set_write_log_only_in_debug(value: bool) -> void:
	ProjectSettings.set_setting(WRITE_LOG_ONLY_IN_DEBUG_SETTING, value)
	_save_project_settings()


static func clear_history_file() -> void:
	ensure_project_settings()

	var log_file_path := get_log_file_path()
	var absolute_path := ProjectSettings.globalize_path(log_file_path)
	var base_dir := absolute_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)

	var file := FileAccess.open(log_file_path, FileAccess.WRITE)
	if file != null:
		file.close()


static func instantiate_text_node() -> RichTextLabel:
	var selected_class := get_text_node_class()
	var instance = _instantiate_class(selected_class)

	if instance is RichTextLabel:
		return instance as RichTextLabel

	return RichTextLabel.new()


static func _instantiate_class(selected_class: String):
	if selected_class.is_empty():
		return null

	if selected_class.begins_with("res://"):
		var script_resource := load(selected_class)
		if script_resource == null:
			return null
		return script_resource.new()

	if ClassDB.class_exists(selected_class):
		return ClassDB.instantiate(selected_class)

	for entry in ProjectSettings.get_global_class_list():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("class", "")) != selected_class:
			continue

		var script_path := str(entry.get("path", ""))
		if script_path.is_empty():
			return null

		var script_resource := load(script_path)
		if script_resource == null:
			return null
		return script_resource.new()

	return null


static func _save_project_settings() -> void:
	if Engine.is_editor_hint():
		ProjectSettings.save()
