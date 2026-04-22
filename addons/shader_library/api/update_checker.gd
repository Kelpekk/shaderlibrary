@tool
extends RefCounted

## Update Checker for Shader Library Plugin
## Checks GitHub for new releases and manages plugin updates

signal update_available(new_version: String, current_version: String, download_url: String, changelog: String)
signal update_check_completed(has_update: bool)
signal download_progress(bytes_downloaded: int, total_bytes: int)
signal update_installed()
signal update_error(error_message: String)

# Plugin paths
const PLUGIN_PATH = "res://addons/shader_library/"

var http_request: HTTPRequest
var current_version: String = ""
var download_http: HTTPRequest
var temp_zip_path: String = ""
var github_repo: String = ""
var auto_check_enabled: bool = true

func _init():
	# Load config from plugin.cfg
	var config = ConfigFile.new()
	var err = config.load(PLUGIN_PATH + "plugin.cfg")
	if err == OK:
		current_version = config.get_value("plugin", "version", "1.0.0")
		github_repo = config.get_value("updates", "github_repo", "")
		auto_check_enabled = config.get_value("updates", "auto_check", true)
	else:
		current_version = "1.0.0"

## Get GitHub API URL
func _get_github_api_url() -> String:
	if github_repo.is_empty():
		return ""
	return "https://api.github.com/repos/" + github_repo + "/releases/latest"

## Check if there's a new version available on GitHub
func check_for_updates() -> void:
	# Check if updates are enabled and repo is configured
	if not auto_check_enabled:
		update_check_completed.emit(false)
		return
	
	var api_url = _get_github_api_url()
	if api_url.is_empty():
		update_error.emit("GitHub repository not configured in plugin.cfg")
		update_check_completed.emit(false)
		return
	
	if http_request:
		http_request.queue_free()
	
	http_request = HTTPRequest.new()
	http_request.request_completed.connect(_on_version_check_completed)
	
	# Add to scene tree temporarily
	var scene_root = Engine.get_main_loop().root
	scene_root.add_child(http_request)
	
	# GitHub API request
	var headers = ["User-Agent: Godot-Shader-Library"]
	var error = http_request.request(api_url, headers)
	
	if error != OK:
		update_error.emit("Failed to check for updates: " + str(error))
		http_request.queue_free()

## Parse GitHub API response
func _on_version_check_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		update_error.emit("Network error while checking for updates")
		update_check_completed.emit(false)
		http_request.queue_free()
		return
	
	if response_code != 200:
		update_error.emit("GitHub API error: " + str(response_code))
		update_check_completed.emit(false)
		http_request.queue_free()
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		update_error.emit("Failed to parse GitHub response")
		update_check_completed.emit(false)
		http_request.queue_free()
		return
	
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		update_error.emit("Invalid GitHub response format")
		update_check_completed.emit(false)
		http_request.queue_free()
		return
	
	# Extract version info
	var latest_version = data.get("tag_name", "")
	var changelog = data.get("body", "No changelog available")
	var download_url = ""
	
	# Find the addon zip in assets
	var assets = data.get("assets", [])
	for asset in assets:
		if typeof(asset) == TYPE_DICTIONARY:
			var name = asset.get("name", "")
			if name.ends_with(".zip") and "shader" in name.to_lower():
				download_url = asset.get("browser_download_url", "")
				break
	
	# If no specific asset, use zipball_url
	if download_url.is_empty():
		download_url = data.get("zipball_url", "")
	
	http_request.queue_free()
	
	# Compare versions
	var latest_clean = latest_version.trim_prefix("v").trim_prefix("V")
	var current_clean = current_version.trim_prefix("v").trim_prefix("V")
	
	if _is_newer_version(latest_clean, current_clean):
		update_available.emit(latest_clean, current_clean, download_url, changelog)
		update_check_completed.emit(true)
	else:
		update_check_completed.emit(false)

## Compare version strings (semantic versioning)
func _is_newer_version(new_ver: String, current_ver: String) -> bool:
	var new_parts = new_ver.split(".")
	var current_parts = current_ver.split(".")
	
	for i in range(max(new_parts.size(), current_parts.size())):
		var new_num = int(new_parts[i]) if i < new_parts.size() else 0
		var current_num = int(current_parts[i]) if i < current_parts.size() else 0
		
		if new_num > current_num:
			return true
		elif new_num < current_num:
			return false
	
	return false

## Download and install the update
func download_and_install_update(download_url: String) -> void:
	if download_http:
		download_http.queue_free()
	
	download_http = HTTPRequest.new()
	download_http.request_completed.connect(_on_download_completed)
	download_http.download_file = "user://shader_library_update.zip"
	temp_zip_path = download_http.download_file
	
	var scene_root = Engine.get_main_loop().root
	scene_root.add_child(download_http)
	
	var headers = ["User-Agent: Godot-Shader-Library"]
	var error = download_http.request(download_url, headers)
	
	if error != OK:
		update_error.emit("Failed to start download: " + str(error))
		download_http.queue_free()

## Handle download completion
func _on_download_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		update_error.emit("Download failed: " + str(response_code))
		download_http.queue_free()
		return
	
	download_http.queue_free()
	
	# Install the update
	_install_update()

## Extract and install the downloaded update
func _install_update() -> void:
	var zip_path = ProjectSettings.globalize_path(temp_zip_path)
	var plugin_path = ProjectSettings.globalize_path(PLUGIN_PATH)
	
	# Create backup first
	var backup_path = plugin_path.trim_suffix("/") + "_backup"
	var dir = DirAccess.open(plugin_path.get_base_dir())
	
	if dir:
		# Remove old backup if exists
		if dir.dir_exists(backup_path):
			_remove_directory_recursive(backup_path)
		
		# Create backup
		dir.copy_dir(plugin_path, backup_path)
	
	# Extract zip
	var reader = ZIPReader.new()
	var err = reader.open(zip_path)
	
	if err != OK:
		update_error.emit("Failed to open update zip: " + str(err))
		return
	
	var files = reader.get_files()
	
	# Find the addon folder in the zip (it might be in a subfolder)
	var addon_prefix = ""
	for file in files:
		if "addons/shader_library/" in file:
			addon_prefix = file.substr(0, file.find("addons/shader_library/"))
			break
	
	# Extract files
	for file in files:
		if not file.begins_with(addon_prefix + "addons/shader_library/"):
			continue
		
		var relative_path = file.trim_prefix(addon_prefix + "addons/shader_library/")
		if relative_path.is_empty() or file.ends_with("/"):
			continue
		
		var content = reader.read_file(file)
		var target_path = plugin_path + relative_path
		
		# Create directories
		var target_dir = target_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(target_dir):
			DirAccess.make_dir_recursive_absolute(target_dir)
		
		# Write file
		var file_writer = FileAccess.open(target_path, FileAccess.WRITE)
		if file_writer:
			file_writer.store_buffer(content)
			file_writer.close()
	
	reader.close()
	
	# Clean up zip
	DirAccess.remove_absolute(zip_path)
	
	update_installed.emit()

## Remove directory recursively
func _remove_directory_recursive(path: String) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		var file_path = path + "/" + file_name
		
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				_remove_directory_recursive(file_path)
		else:
			DirAccess.remove_absolute(file_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

## Restart the editor to apply updates
func restart_editor() -> void:
	# Save the project
	var editor_interface = Engine.get_singleton("EditorInterface")
	if editor_interface:
		editor_interface.save_all_scenes()
		editor_interface.restart_editor()
