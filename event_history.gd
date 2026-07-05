@tool
extends Node

signal event_buffered(event_data: Dictionary)
signal history_cleared

const EventHistoryConfig = preload("res://addons/TAB_EventHistoryLog/event_history_config.gd")

var _buffer: Array[String] = []
var _pending_batches: Array[PackedStringArray] = []
var _buffer_mutex := Mutex.new()
var _worker_mutex := Mutex.new()
var _worker_semaphore := Semaphore.new()
var _worker_thread := Thread.new()
var _clear_requested := false
var _stop_requested := false
var _next_event_id := 1

@onready var _flush_timer := Timer.new()


func _ready() -> void:
	EventHistoryConfig.ensure_project_settings()

	_flush_timer.one_shot = false
	_flush_timer.wait_time = maxf(float(EventHistoryConfig.get_sync_interval_ms()) / 1000.0, 0.001)
	_flush_timer.timeout.connect(_on_flush_timer_timeout)
	add_child(_flush_timer)
	_flush_timer.start()

	_worker_thread.start(_worker_loop)


func _exit_tree() -> void:
	_flush_buffer_to_worker()

	_worker_mutex.lock()
	_stop_requested = true
	_worker_mutex.unlock()
	_worker_semaphore.post()

	if _worker_thread.is_started():
		_worker_thread.wait_to_finish()


func emit_event(category: String, event_name: String, data: Dictionary = {}) -> void:
	_buffer_mutex.lock()
	var event_id := _next_event_id
	_next_event_id += 1
	_buffer_mutex.unlock()

	var event_data := {
		"id": event_id,
		"timestamp": Time.get_datetime_string_from_system(true, true),
		"frame": Engine.get_process_frames(),
		"category": category,
		"event_name": event_name,
		"data": data.duplicate(true),
	}

	var serialized_event := JSON.stringify(event_data)

	_buffer_mutex.lock()
	_buffer.append(serialized_event)
	_buffer_mutex.unlock()

	event_buffered.emit(event_data)


func clear_history() -> void:
	_buffer_mutex.lock()
	_buffer.clear()
	_buffer_mutex.unlock()

	_worker_mutex.lock()
	_pending_batches.clear()
	_clear_requested = true
	_worker_mutex.unlock()

	_buffer_mutex.lock()
	_next_event_id = 1
	_buffer_mutex.unlock()
	_worker_semaphore.post()
	history_cleared.emit()


func _on_flush_timer_timeout() -> void:
	var sync_interval := maxf(float(EventHistoryConfig.get_sync_interval_ms()) / 1000.0, 0.001)
	if not is_equal_approx(_flush_timer.wait_time, sync_interval):
		_flush_timer.wait_time = sync_interval

	_flush_buffer_to_worker()


func _flush_buffer_to_worker() -> void:
	_buffer_mutex.lock()
	if _buffer.is_empty():
		_buffer_mutex.unlock()
		return

	var batch := PackedStringArray(_buffer)
	_buffer.clear()
	_buffer_mutex.unlock()

	_worker_mutex.lock()
	_pending_batches.append(batch)
	_worker_mutex.unlock()

	_worker_semaphore.post()


func _worker_loop() -> void:
	while true:
		_worker_semaphore.wait()

		_worker_mutex.lock()
		var should_clear := _clear_requested
		var should_stop := _stop_requested
		var batches: Array[PackedStringArray] = _pending_batches.duplicate()
		_clear_requested = false
		_pending_batches.clear()
		_worker_mutex.unlock()

		if should_clear:
			_clear_history_file()

		for batch in batches:
			_append_batch_to_file(batch)

		if should_stop:
			break


func _append_batch_to_file(batch: PackedStringArray) -> void:
	if batch.is_empty():
		return
	if EventHistoryConfig.get_write_log_only_in_debug() and not Engine.is_editor_hint():
		return

	var log_file_path := EventHistoryConfig.get_log_file_path()
	_ensure_parent_directory(log_file_path)

	if not FileAccess.file_exists(log_file_path):
		var create_file := FileAccess.open(log_file_path, FileAccess.WRITE)
		if create_file != null:
			create_file.close()

	var file := FileAccess.open(log_file_path, FileAccess.READ_WRITE)
	if file == null:
		return

	file.seek_end()
	for line in batch:
		file.store_line(line)
	file.close()


func _clear_history_file() -> void:
	EventHistoryConfig.clear_history_file()


func _ensure_parent_directory(file_path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(file_path)
	var base_dir := absolute_path.get_base_dir()
	if base_dir.is_empty():
		return

	DirAccess.make_dir_recursive_absolute(base_dir)
