@tool
extends EditorPlugin

const EVENT_HISTORY_DOCK_SCENE := preload("res://addons/TAB_EventHistoryLog/event_history_dock.tscn")
const EventHistoryConfig = preload("res://addons/TAB_EventHistoryLog/event_history_config.gd")

const AUTOLOAD_NAME := "EventHistory"
const AUTOLOAD_PATH := "res://addons/TAB_EventHistoryLog/event_history.gd"

var _event_history_dock: Control


func _enter_tree() -> void:
	EventHistoryConfig.ensure_project_settings()
	_ensure_autoload_singleton()

	_event_history_dock = EVENT_HISTORY_DOCK_SCENE.instantiate() as Control
	_event_history_dock.name = "EventHistory"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _event_history_dock)


func _exit_tree() -> void:
	if _event_history_dock == null:
		return

	remove_control_from_docks(_event_history_dock)
	_event_history_dock.queue_free()
	_event_history_dock = null


func _enable_plugin() -> void:
	EventHistoryConfig.ensure_project_settings()
	_ensure_autoload_singleton()


func _disable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/%s" % AUTOLOAD_NAME):
		return

	remove_autoload_singleton(AUTOLOAD_NAME)


func _ensure_autoload_singleton() -> void:
	var autoload_key := "autoload/%s" % AUTOLOAD_NAME
	if ProjectSettings.has_setting(autoload_key):
		return

	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
