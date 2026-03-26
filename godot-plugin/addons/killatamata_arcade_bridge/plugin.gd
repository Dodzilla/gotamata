@tool
extends EditorPlugin

const AgentCommandServer = preload("res://addons/killatamata_arcade_bridge/agent_command_server.gd")
const ArcadeBridgeDock = preload("res://addons/killatamata_arcade_bridge/arcade_bridge_dock.gd")
const ArcadeProjectConfig = preload("res://addons/killatamata_arcade_bridge/arcade_project_config.gd")
const ArcadeValidationService = preload("res://addons/killatamata_arcade_bridge/arcade_validation_service.gd")
const ArcadeExportService = preload("res://addons/killatamata_arcade_bridge/arcade_export_service.gd")

const BRIDGE_CONTRACT_PATH := "res://addons/killatamata_arcade_bridge/bridge_contract.json"
const SETTING_BIND_ADDRESS := "killatamata/arcade_bridge/bind_address"
const SETTING_PORT := "killatamata/arcade_bridge/port"
const SETTING_AUTOSTART := "killatamata/arcade_bridge/autostart"
const SETTING_AUTH_TOKEN := "killatamata/arcade_bridge/auth_token"

var _server: AgentCommandServer
var _config_store: ArcadeProjectConfig
var _validation_service: ArcadeValidationService
var _export_service: ArcadeExportService
var _dock: Control
var _last_log: String = ""
var _last_command: String = ""
var _last_response: Dictionary = {}
var _last_connection_time: String = "never"
var _logs: Array = []

func _enter_tree() -> void:
	_register_settings()

	_config_store = ArcadeProjectConfig.new()
	_validation_service = ArcadeValidationService.new(_config_store)
	_validation_service.message_logged.connect(_append_log)
	_export_service = ArcadeExportService.new(_config_store, _validation_service)
	_export_service.message_logged.connect(_append_log)

	_server = AgentCommandServer.new()
	_server.command_handler = Callable(self, "_execute_agent_command")
	_server.message_logged.connect(_on_server_log)
	_server.command_processed.connect(_on_command_processed)
	_server.status_changed.connect(_on_server_status_changed)

	_dock = ArcadeBridgeDock.new()
	if _dock.has_method("attach_plugin"):
		_dock.call("attach_plugin", self)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	set_process(true)
	_sync_server_from_settings(false)
	_refresh_dock()

func _exit_tree() -> void:
	set_process(false)
	if _server != null:
		_server.stop()
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

func _process(_delta: float) -> void:
	if _server != null:
		_server.process()

func _get_plugin_name() -> String:
	return "KillaTamata Arcade"

func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_base_control().get_theme_icon("Node", "EditorIcons")

func get_known_commands() -> PackedStringArray:
	var parsed: Variant = JSON.parse_string(_read_file(BRIDGE_CONTRACT_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return PackedStringArray()
	var commands: PackedStringArray = PackedStringArray()
	for command in parsed.get("commands", []):
		commands.append(str(command.get("name", "")))
	return commands

func get_server_status() -> Dictionary:
	if _server == null:
		return {
			"running": false,
			"bind_address": "127.0.0.1",
			"port": 47891,
			"auth_token_set": false,
			"last_log": _last_log,
			"last_command": _last_command,
			"last_response": _last_response,
			"last_connection_time": _last_connection_time,
		}
	return {
		"running": _server.is_running(),
		"bind_address": _server.bind_address,
		"port": _server.port,
		"auth_token_set": not _server.auth_token.is_empty(),
		"last_log": _last_log,
		"last_command": _last_command,
		"last_response": _last_response,
		"last_connection_time": _last_connection_time,
	}

func get_settings_snapshot() -> Dictionary:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	return {
		"bind_address": str(settings.get_setting(SETTING_BIND_ADDRESS)),
		"port": int(settings.get_setting(SETTING_PORT)),
		"autostart": bool(settings.get_setting(SETTING_AUTOSTART)),
		"auth_token": str(settings.get_setting(SETTING_AUTH_TOKEN)),
	}

func get_recent_logs_payload(limit: int = 20) -> Array:
	if limit <= 0:
		return []
	if _logs.size() <= limit:
		return _logs.duplicate()
	return _logs.slice(_logs.size() - limit, _logs.size())

func get_dock_snapshot() -> Dictionary:
	return {
		"server": get_server_status(),
		"project": _project_summary(),
		"logs": get_recent_logs_payload(40),
		"lastCommand": _last_command,
		"lastResponse": _last_response,
	}

func run_validate_action() -> Dictionary:
	var response: Dictionary = _ok(_validation_service.validate_arcade_project(true))
	_record_local_response("validate_arcade_project", response)
	return response

func run_ensure_preset_action() -> Dictionary:
	var response: Dictionary = ensure_arcade_web_export_preset()
	_record_local_response("ensure_arcade_web_export_preset", response)
	return response

func run_manifest_preview_action() -> Dictionary:
	var response: Dictionary = _ok({"manifest": _export_service.generate_manifest_preview()})
	_record_local_response("generate_arcade_manifest_preview", response)
	return response

func run_build_action() -> Dictionary:
	var response: Dictionary = _cmd_build_arcade_release({})
	_record_local_response("build_arcade_release", response)
	return response

func run_reveal_action() -> Dictionary:
	var response: Dictionary = _cmd_reveal_arcade_build({})
	_record_local_response("reveal_arcade_build", response)
	return response

func apply_settings_and_restart(bind_address: String, port: int, auth_token: String, autostart: bool) -> Dictionary:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	settings.set_setting(SETTING_BIND_ADDRESS, bind_address.strip_edges())
	settings.set_setting(SETTING_PORT, max(1, port))
	settings.set_setting(SETTING_AUTH_TOKEN, auth_token)
	settings.set_setting(SETTING_AUTOSTART, autostart)
	settings.save()

	_sync_server_from_settings(true)
	return get_server_status()

func start_server() -> Dictionary:
	if _server == null:
		return _error("server_unavailable", "Server is not initialized.")
	var err: int = _server.start()
	if err != OK:
		return _error("start_failed", "Failed to start server.", {
			"errorCode": err,
			"errorName": error_string(err),
		})
	_refresh_dock()
	return get_server_status()

func stop_server() -> Dictionary:
	if _server == null:
		return _error("server_unavailable", "Server is not initialized.")
	_server.stop()
	_refresh_dock()
	return get_server_status()

func ensure_arcade_web_export_preset() -> Dictionary:
	var config: Dictionary = _current_config()
	var preset_name: String = str(config.get("exportPresetName", ArcadeProjectConfig.DEFAULT_PRESET_NAME))
	var export_path: String = _relative_export_path(config)
	var presets: ConfigFile = ConfigFile.new()
	var presets_path: String = ProjectSettings.globalize_path("res://export_presets.cfg")
	var load_err: int = presets.load(presets_path)
	if load_err != OK and load_err != ERR_FILE_NOT_FOUND:
		return _error("export_presets_load_failed", "Failed to load export_presets.cfg.", {
			"errorCode": load_err,
			"errorName": error_string(load_err),
		})

	var section: String = _find_preset_section(presets, preset_name)
	if section.is_empty():
		section = "preset.%d" % _next_preset_index(presets)

	var options_section: String = "%s.options" % section
	presets.set_value(section, "name", preset_name)
	presets.set_value(section, "platform", "Web")
	presets.set_value(section, "runnable", true)
	presets.set_value(section, "dedicated_server", false)
	presets.set_value(section, "advanced_options", false)
	presets.set_value(section, "custom_features", "")
	presets.set_value(section, "export_filter", "all_resources")
	presets.set_value(section, "include_filter", "")
	presets.set_value(section, "exclude_filter", "")
	presets.set_value(section, "export_path", export_path)

	presets.set_value(options_section, "custom_template/debug", "")
	presets.set_value(options_section, "custom_template/release", "")
	presets.set_value(options_section, "variant/thread_support", false)
	presets.set_value(options_section, "html/export_icon", false)

	var save_err: int = presets.save(presets_path)
	if save_err != OK:
		return _error("export_presets_save_failed", "Failed to save export_presets.cfg.", {
			"errorCode": save_err,
			"errorName": error_string(save_err),
		})

	_append_log("Ensured arcade export preset %s." % preset_name)
	var validation: Dictionary = _validation_service.validate_arcade_web_export_preset(config, false)
	_refresh_dock()
	return _ok({
		"presetSummary": validation.get("presetSummary", {}),
		"validation": validation,
	})

func _register_settings() -> void:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	if not settings.has_setting(SETTING_BIND_ADDRESS):
		settings.set_setting(SETTING_BIND_ADDRESS, "127.0.0.1")
	if not settings.has_setting(SETTING_PORT):
		settings.set_setting(SETTING_PORT, 47891)
	if not settings.has_setting(SETTING_AUTOSTART):
		settings.set_setting(SETTING_AUTOSTART, true)
	if not settings.has_setting(SETTING_AUTH_TOKEN):
		settings.set_setting(SETTING_AUTH_TOKEN, "")
	settings.save()

func _sync_server_from_settings(force_restart: bool) -> void:
	if _server == null:
		return

	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	var new_bind_address: String = str(settings.get_setting(SETTING_BIND_ADDRESS)).strip_edges()
	if new_bind_address.is_empty():
		new_bind_address = "127.0.0.1"
	var new_port: int = int(settings.get_setting(SETTING_PORT))
	if new_port < 1:
		new_port = 47891
	var new_auth_token: String = str(settings.get_setting(SETTING_AUTH_TOKEN))
	var should_autostart: bool = bool(settings.get_setting(SETTING_AUTOSTART))

	var address_changed: bool = _server.bind_address != new_bind_address or _server.port != new_port
	if _server.is_running() and (force_restart or address_changed):
		_server.stop()

	_server.bind_address = new_bind_address
	_server.port = new_port
	_server.auth_token = new_auth_token

	if should_autostart and not _server.is_running():
		_server.start()

	_refresh_dock()

func _execute_agent_command(command: String, args: Dictionary) -> Dictionary:
	match command:
		"ping":
			return _cmd_ping(args)
		"list_commands":
			return _cmd_list_commands(args)
		"get_recent_logs":
			return _cmd_get_recent_logs(args)
		"editor_state":
			return _cmd_editor_state(args)
		"open_scene":
			return _cmd_open_scene(args)
		"save_scene":
			return _cmd_save_scene(args)
		"project_state":
			return _cmd_project_state(args)
		"get_arcade_project_config":
			return _cmd_get_arcade_project_config(args)
		"upsert_arcade_project_config":
			return _cmd_upsert_arcade_project_config(args)
		"generate_arcade_manifest_preview":
			return _cmd_generate_arcade_manifest_preview(args)
		"list_export_presets":
			return _cmd_list_export_presets(args)
		"ensure_arcade_web_export_preset":
			return _cmd_ensure_arcade_web_export_preset(args)
		"validate_arcade_web_export_preset":
			return _cmd_validate_arcade_web_export_preset(args)
		"validate_arcade_project":
			return _cmd_validate_arcade_project(args)
		"build_arcade_release":
			return _cmd_build_arcade_release(args)
		"reveal_arcade_build":
			return _cmd_reveal_arcade_build(args)
		_:
			return _error("unknown_command", "Unknown command: %s" % command, {
				"knownCommands": get_known_commands(),
			})

func _cmd_ping(_args: Dictionary) -> Dictionary:
	return _ok({
		"message": "pong",
		"plugin": "killatamata_arcade_bridge",
		"projectPath": ProjectSettings.globalize_path("res://"),
		"status": get_server_status(),
	})

func _cmd_list_commands(_args: Dictionary) -> Dictionary:
	return _ok({"commands": get_known_commands()})

func _cmd_get_recent_logs(args: Dictionary) -> Dictionary:
	return _ok({"logs": get_recent_logs_payload(int(args.get("limit", 20)))})

func _cmd_editor_state(_args: Dictionary) -> Dictionary:
	var root: Node = get_editor_interface().get_edited_scene_root()
	return _ok({
		"scenePath": root.scene_file_path if root != null else "",
		"sceneRootName": root.name if root != null else "",
		"isPlaying": get_editor_interface().is_playing_scene(),
	})

func _cmd_open_scene(args: Dictionary) -> Dictionary:
	var scene_path: String = _normalize_scene_path(str(args.get("path", "")))
	if scene_path.is_empty():
		return _error("missing_path", "open_scene requires args.path.")
	if not FileAccess.file_exists(scene_path):
		return _error("scene_not_found", "Scene path does not exist.", {"path": scene_path})

	var result: Variant = get_editor_interface().open_scene_from_path(scene_path)
	if typeof(result) == TYPE_INT and int(result) != OK:
		return _error("open_scene_failed", "Failed to open scene.", {
			"path": scene_path,
			"errorCode": int(result),
			"errorName": error_string(int(result)),
		})
	return _ok({"scenePath": scene_path})

func _cmd_save_scene(args: Dictionary) -> Dictionary:
	var root: Node = get_editor_interface().get_edited_scene_root()
	if root == null:
		return _error("no_scene", "No edited scene is currently open.")

	var explicit_path: String = _normalize_scene_path(str(args.get("path", "")))
	if not explicit_path.is_empty():
		var packed: PackedScene = PackedScene.new()
		var pack_err: int = packed.pack(root)
		if pack_err != OK:
			return _error("pack_failed", "Failed to pack scene.", {
				"errorCode": pack_err,
				"errorName": error_string(pack_err),
			})
		var save_err: int = ResourceSaver.save(packed, explicit_path)
		if save_err != OK:
			return _error("save_failed", "Failed to save scene.", {
				"path": explicit_path,
				"errorCode": save_err,
				"errorName": error_string(save_err),
			})
		return _ok({"scenePath": explicit_path})

	var result: Variant = get_editor_interface().save_scene()
	if typeof(result) == TYPE_INT and int(result) != OK:
		return _error("save_failed", "Failed to save scene.", {
			"errorCode": int(result),
			"errorName": error_string(int(result)),
		})
	return _ok({"scenePath": root.scene_file_path})

func _cmd_project_state(_args: Dictionary) -> Dictionary:
	return _ok(_build_project_state())

func _cmd_get_arcade_project_config(_args: Dictionary) -> Dictionary:
	return _ok({
		"config": _config_store.load_config(),
		"configPath": _config_store.get_config_path(),
		"configExists": _config_store.config_exists(),
	})

func _cmd_upsert_arcade_project_config(args: Dictionary) -> Dictionary:
	if typeof(args.get("patch", null)) != TYPE_DICTIONARY:
		return _error("missing_patch", "upsert_arcade_project_config requires args.patch.")
	var normalized: Dictionary = _config_store.upsert_config(args.get("patch", {}))
	_append_log("Updated %s." % _config_store.get_config_path())
	_refresh_dock()
	return _ok({
		"config": normalized,
		"configPath": _config_store.get_config_path(),
	})

func _cmd_generate_arcade_manifest_preview(_args: Dictionary) -> Dictionary:
	return _ok({"manifest": _export_service.generate_manifest_preview()})

func _cmd_list_export_presets(_args: Dictionary) -> Dictionary:
	return _ok({"presets": _validation_service.list_export_presets()})

func _cmd_ensure_arcade_web_export_preset(_args: Dictionary) -> Dictionary:
	return ensure_arcade_web_export_preset()

func _cmd_validate_arcade_web_export_preset(_args: Dictionary) -> Dictionary:
	return _ok(_validation_service.validate_arcade_web_export_preset(_current_config(), true))

func _cmd_validate_arcade_project(_args: Dictionary) -> Dictionary:
	return _ok(_validation_service.validate_arcade_project(true))

func _cmd_build_arcade_release(_args: Dictionary) -> Dictionary:
	var result: Dictionary = _export_service.build_arcade_release()
	if not bool(result.get("success", false)):
		return _error(
			str(result.get("errorCode", "build_failed")),
			str(result.get("errorMessage", "Arcade release build failed.")),
			result.get("details", {})
		)
	return _ok(result)

func _cmd_reveal_arcade_build(_args: Dictionary) -> Dictionary:
	var result: Dictionary = _export_service.reveal_arcade_build()
	if not bool(result.get("success", false)):
		return _error(
			str(result.get("errorCode", "reveal_failed")),
			str(result.get("errorMessage", "Failed to reveal arcade build directory.")),
			result.get("details", {})
		)
	return _ok(result)

func _build_project_state() -> Dictionary:
	var validation: Dictionary = _validation_service.validate_arcade_project(false)
	var config: Dictionary = _current_config()
	return {
		"projectPath": ProjectSettings.globalize_path("res://"),
		"projectName": str(ProjectSettings.get_setting("application/config/name", "")),
		"godotVersion": _config_store.get_engine_version_string(),
		"csharpDetected": bool(validation.get("csharpDetected", false)),
		"csharpMatches": validation.get("csharpMatches", []),
		"configPath": _config_store.get_config_path(),
		"configExists": _config_store.config_exists(),
		"arcadeConfig": config,
		"exportPresetSummary": validation.get("exportPresetSummary", {}),
		"validationSummary": {
			"ok": bool(validation.get("ok", false)),
			"blockingIssueCount": validation.get("blockingIssues", []).size(),
			"warningCount": validation.get("warnings", []).size(),
		},
	}

func _project_summary() -> Dictionary:
	var validation: Dictionary = _validation_service.validate_arcade_project(false)
	var config: Dictionary = _current_config()
	return {
		"projectName": str(ProjectSettings.get_setting("application/config/name", "")),
		"gameSlug": str(config.get("gameSlug", "")),
		"title": str(config.get("title", "")),
		"version": str(config.get("version", "")),
		"exportPresetName": str(config.get("exportPresetName", "")),
		"ready": bool(validation.get("ok", false)),
		"blockingIssueCount": validation.get("blockingIssues", []).size(),
		"warningCount": validation.get("warnings", []).size(),
	}

func _current_config() -> Dictionary:
	var loaded: Variant = _config_store.load_config()
	if typeof(loaded) == TYPE_DICTIONARY:
		return loaded
	return _config_store.default_config()

func _relative_export_path(config: Dictionary) -> String:
	var staging_dir: String = _config_store.resolve_staging_dir(config)
	if staging_dir.begins_with("res://"):
		staging_dir = staging_dir.substr("res://".length())
	while staging_dir.begins_with("/"):
		staging_dir = staging_dir.substr(1)
	return "%s/%s" % [staging_dir, ArcadeProjectConfig.DEFAULT_ENTRY_PATH]

func _find_preset_section(config: ConfigFile, preset_name: String) -> String:
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			if str(config.get_value(section, "name", "")) == preset_name:
				return section
	return ""

func _next_preset_index(config: ConfigFile) -> int:
	var next_index: int = 0
	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			next_index = max(next_index, int(section.get_slice(".", 1)) + 1)
	return next_index

func _normalize_scene_path(path: String) -> String:
	var normalized: String = path.strip_edges()
	if normalized.is_empty():
		return ""
	if normalized.begins_with("res://"):
		return normalized
	while normalized.begins_with("/"):
		normalized = normalized.substr(1)
	return "res://%s" % normalized

func _record_local_response(command: String, response: Dictionary) -> void:
	_last_command = command
	_last_response = response
	_refresh_dock()

func _on_server_log(message: String) -> void:
	_append_log(message)

func _on_command_processed(command: String, response: Dictionary) -> void:
	_last_command = command
	_last_response = response
	_last_connection_time = Time.get_datetime_string_from_system()
	_append_log("Processed command %s." % command)
	if _dock != null and _dock.has_method("set_last_command"):
		_dock.call("set_last_command", command, response)
	_refresh_dock()

func _on_server_status_changed(_is_running: bool, _bind_address: String, _port: int) -> void:
	_refresh_dock()

func _append_log(message: String) -> void:
	var entry: String = "[%s] %s" % [Time.get_datetime_string_from_system(), message]
	_logs.append(entry)
	while _logs.size() > 200:
		_logs.remove_at(0)
	_last_log = entry
	_refresh_dock()

func _refresh_dock() -> void:
	if _dock != null and _dock.has_method("refresh_from_plugin"):
		_dock.call_deferred("refresh_from_plugin")

func _ok(result: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"result": result,
	}

func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
			"details": details,
		},
	}

func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
