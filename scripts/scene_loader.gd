extends Node
## Autoload responsible for asynchronously loading and changing scenes.

signal load_started(path: String)
signal load_progress_changed(progress: float)
signal load_failed(path: String, error: Error)
signal scene_changed(path: String)

var _loading_path := ""
var _is_loading := false


func is_loading() -> bool:
	return _is_loading


func load_scene(path: String) -> Error:
	if _is_loading:
		return ERR_BUSY

	if not ResourceLoader.exists(path):
		load_failed.emit(path, ERR_FILE_NOT_FOUND)
		return ERR_FILE_NOT_FOUND

	var error := ResourceLoader.load_threaded_request(path, "PackedScene", true)
	if error != OK:
		load_failed.emit(path, error)
		return error

	_loading_path = path
	_is_loading = true
	load_started.emit(path)
	return OK


func _process(_delta: float) -> void:
	if not _is_loading:
		return

	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_loading_path, progress)
	if not progress.is_empty():
		load_progress_changed.emit(progress[0])

	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return

	var path := _loading_path
	_is_loading = false
	_loading_path = ""

	if status != ResourceLoader.THREAD_LOAD_LOADED:
		load_failed.emit(path, FAILED)
		return

	var packed_scene := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed_scene == null:
		load_failed.emit(path, FAILED)
		return

	var error := get_tree().change_scene_to_packed(packed_scene)
	if error != OK:
		load_failed.emit(path, error)
		return

	scene_changed.emit(path)
