@tool
extends EditorPlugin

const AgentCommandServer = preload("res://addons/gotamata_agent_bridge/agent_command_server.gd")
const AgentServerDock = preload("res://addons/gotamata_agent_bridge/agent_server_dock.gd")
const AssetPipelineRepository = preload("res://addons/gotamata_agent_bridge/asset_pipeline_repository.gd")
const AssetPipelineScreen = preload("res://addons/gotamata_agent_bridge/asset_pipeline_screen.gd")

const BRIDGE_CONTRACT_PATH := "res://addons/gotamata_agent_bridge/bridge_contract.json"
const SETTING_BIND_ADDRESS: String = "gotamata/agent_bridge/bind_address"
const SETTING_PORT: String = "gotamata/agent_bridge/port"
const SETTING_AUTOSTART: String = "gotamata/agent_bridge/autostart"
const SETTING_AUTH_TOKEN: String = "gotamata/agent_bridge/auth_token"

var _server: AgentCommandServer
var _pipeline_repository: AssetPipelineRepository
var _dock: Control
var _main_screen: Control
var _last_log: String = ""
var _last_command: String = ""
var _last_response: Dictionary = {}

func _enter_tree() -> void:
	_register_settings()

	_pipeline_repository = AssetPipelineRepository.new()
	_pipeline_repository.initialize()

	_server = AgentCommandServer.new()
	_server.command_handler = Callable(self, "_execute_agent_command")
	_server.message_logged.connect(_on_server_log)
	_server.command_processed.connect(_on_command_processed)
	_server.status_changed.connect(_on_server_status_changed)

	_main_screen = AssetPipelineScreen.new()
	if _main_screen.has_method("attach_plugin"):
		_main_screen.call("attach_plugin", self)
	var main_screen_host: Control = _resolve_main_screen_host()
	if main_screen_host != null:
		main_screen_host.add_child(_main_screen)
	_make_visible(false)

	_dock = AgentServerDock.new()
	if _dock.has_method("attach_plugin"):
		_dock.call("attach_plugin", self)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	set_process(true)
	_sync_server_from_settings(false)
	_refresh_pipeline_screen()

func _exit_tree() -> void:
	set_process(false)

	if _server != null:
		_server.stop()

	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

	if _main_screen != null:
		_main_screen.queue_free()
		_main_screen = null

func _process(_delta: float) -> void:
	if _server != null:
		_server.process()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if _main_screen != null:
		_main_screen.visible = visible
	if visible:
		_refresh_pipeline_screen()

func _get_plugin_name() -> String:
	return "GoTamata"

func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_base_control().get_theme_icon("Node", "EditorIcons")

func get_known_commands() -> PackedStringArray:
	return _load_bridge_contract_commands()

func get_server_status() -> Dictionary:
	if _server == null:
		return {
			"running": false,
			"bind_address": "127.0.0.1",
			"port": 47891,
			"last_log": _last_log,
			"last_command": _last_command,
			"last_response": _last_response,
		}

	return {
		"running": _server.is_running(),
		"bind_address": _server.bind_address,
		"port": _server.port,
		"auth_token_set": not _server.auth_token.is_empty(),
		"last_log": _last_log,
		"last_command": _last_command,
		"last_response": _last_response,
	}

func get_settings_snapshot() -> Dictionary:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	return {
		"bind_address": str(settings.get_setting(SETTING_BIND_ADDRESS)),
		"port": int(settings.get_setting(SETTING_PORT)),
		"autostart": bool(settings.get_setting(SETTING_AUTOSTART)),
		"auth_token": str(settings.get_setting(SETTING_AUTH_TOKEN)),
	}

func get_pipeline_overview() -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	return _ok({"overview": _pipeline_repository.get_overview()})

func get_workflow_templates() -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	return _ok({"templates": _pipeline_repository.list_templates()})

func get_workflow_template(template_id: String) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var template_data: Dictionary = _pipeline_repository.get_template(template_id)
	if template_data.is_empty():
		return _error("template_not_found", "Workflow template does not exist.", {"template_id": template_id})
	return _ok({"template": template_data})

func upsert_workflow_template(template_data: Dictionary) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.upsert_template(template_data)
	_refresh_pipeline_screen()
	return response

func delete_workflow_template(template_id: String) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.delete_template(template_id)
	_refresh_pipeline_screen()
	return response

func get_workflow_runs() -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	return _ok({"runs": _pipeline_repository.list_runs()})

func get_workflow_run(run_id: String) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var run_data: Dictionary = _pipeline_repository.get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})
	return _ok({"run": run_data})

func create_workflow_run(template_id: String, asset_slug: String, display_name: String = "") -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.create_run(template_id, asset_slug, display_name)
	_refresh_pipeline_screen()
	return response

func delete_workflow_run(run_id: String) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.delete_run(run_id)
	_refresh_pipeline_screen()
	return response

func apply_workflow_decision(run_id: String, attempt_id: String, decision: String, note: String = "") -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.apply_decision(run_id, attempt_id, decision, note)
	_refresh_pipeline_screen()
	return response

func set_workflow_import_recipe(run_id: String, import_recipe: Dictionary) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.set_import_recipe(run_id, import_recipe)
	_refresh_pipeline_screen()
	return response

func set_workflow_attempt_job(
	run_id: String,
	attempt_id: String,
	provider: String,
	task_type: String,
	request_payload: Dictionary,
	job_id: String = "",
	idempotency_key: String = "",
	note: String = ""
) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.set_attempt_job(
		run_id,
		attempt_id,
		provider,
		task_type,
		request_payload,
		job_id,
		idempotency_key,
		note
	)
	_refresh_pipeline_screen()
	return response

func set_workflow_attempt_job_status(
	run_id: String,
	attempt_id: String,
	status: String,
	job_id: String = "",
	response_payload: Dictionary = {},
	output_urls: Array = [],
	downloaded_paths: Array = [],
	error_message: String = ""
) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.set_attempt_job_status(
		run_id,
		attempt_id,
		status,
		job_id,
		response_payload,
		output_urls,
		downloaded_paths,
		error_message
	)
	_refresh_pipeline_screen()
	return response

func register_workflow_artifact(
	run_id: String,
	attempt_id: String,
	artifact_type: String,
	display_name: String,
	storage_uri: String,
	preview_uri: String,
	metadata: Dictionary = {},
	selected: bool = false,
	publish_candidate: bool = false,
	artifact_id: String = ""
) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.register_artifact(
		run_id,
		attempt_id,
		artifact_type,
		display_name,
		storage_uri,
		preview_uri,
		metadata,
		selected,
		publish_candidate,
		artifact_id
	)
	_refresh_pipeline_screen()
	return response

func delete_workflow_artifact(run_id: String, artifact_id: String) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.delete_artifact(run_id, artifact_id)
	_refresh_pipeline_screen()
	return response

func publish_workflow_revision(run_id: String, version_label: String = "", notes: String = "") -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.publish_revision(run_id, version_label, notes)
	_refresh_pipeline_screen()
	return response

func set_workflow_artifact_selected(run_id: String, artifact_id: String, selected: bool) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.set_artifact_selected(run_id, artifact_id, selected)
	_refresh_pipeline_screen()
	return response

func set_workflow_artifact_publish_candidate(run_id: String, artifact_id: String, publish_candidate: bool) -> Dictionary:
	if _pipeline_repository == null:
		return _error("pipeline_unavailable", "Pipeline repository is not initialized.")
	var response: Dictionary = _pipeline_repository.set_artifact_publish_candidate(run_id, artifact_id, publish_candidate)
	_refresh_pipeline_screen()
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
			"error_code": err,
			"error_name": error_string(err),
		})
	_refresh_dock()
	return get_server_status()

func stop_server() -> Dictionary:
	if _server == null:
		return _error("server_unavailable", "Server is not initialized.")
	_server.stop()
	_refresh_dock()
	return get_server_status()

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
			return _ok({
				"message": "pong",
				"plugin": "gotamata_asset_pipeline",
				"status": get_server_status(),
			})
		"list_commands":
			return _ok({"commands": get_known_commands()})
		"editor_state":
			return _cmd_editor_state()
		"open_scene":
			return _cmd_open_scene(args)
		"play":
			return _cmd_play()
		"stop":
			return _cmd_stop()
		"save_scene":
			return _cmd_save_scene(args)
		"select_node":
			return _cmd_select_node(args)
		"add_node":
			return _cmd_add_node(args)
		"set_property":
			return _cmd_set_property(args)
		"set_main_screen":
			return _cmd_set_main_screen(args)
		"call":
			return _cmd_call(args)
		"pipeline_overview":
			return get_pipeline_overview()
		"list_workflow_templates":
			return get_workflow_templates()
		"get_workflow_template":
			return _cmd_get_workflow_template(args)
		"upsert_workflow_template":
			return _cmd_upsert_workflow_template(args)
		"delete_workflow_template":
			return _cmd_delete_workflow_template(args)
		"list_workflow_runs":
			return get_workflow_runs()
		"get_workflow_run":
			return _cmd_get_workflow_run(args)
		"create_workflow_run":
			return _cmd_create_workflow_run(args)
		"delete_workflow_run":
			return _cmd_delete_workflow_run(args)
		"apply_workflow_decision":
			return _cmd_apply_workflow_decision(args)
		"set_workflow_import_recipe":
			return _cmd_set_workflow_import_recipe(args)
		"set_workflow_attempt_job":
			return _cmd_set_workflow_attempt_job(args)
		"set_workflow_attempt_job_status":
			return _cmd_set_workflow_attempt_job_status(args)
		"register_workflow_artifact":
			return _cmd_register_workflow_artifact(args)
		"delete_workflow_artifact":
			return _cmd_delete_workflow_artifact(args)
		"publish_workflow_revision":
			return _cmd_publish_workflow_revision(args)
		"set_workflow_artifact_selected":
			return _cmd_set_workflow_artifact_selected(args)
		"set_workflow_artifact_publish_candidate":
			return _cmd_set_workflow_artifact_publish_candidate(args)
		_:
			return _error("unknown_command", "Unknown command: %s" % command, {
				"known_commands": get_known_commands(),
			})

func _cmd_editor_state() -> Dictionary:
	var root: Node = get_editor_interface().get_edited_scene_root()
	return _ok({
		"scene_path": root.scene_file_path if root != null else "",
		"scene_root_name": root.name if root != null else "",
		"is_playing": get_editor_interface().is_playing_scene(),
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
			"error_code": int(result),
			"error_name": error_string(int(result)),
		})

	return _ok({"scene_path": scene_path})

func _cmd_play() -> Dictionary:
	get_editor_interface().play_main_scene()
	return _ok({"is_playing": get_editor_interface().is_playing_scene()})

func _cmd_stop() -> Dictionary:
	get_editor_interface().stop_playing_scene()
	return _ok({"is_playing": get_editor_interface().is_playing_scene()})

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
				"error_code": pack_err,
				"error_name": error_string(pack_err),
			})
		var save_err: int = ResourceSaver.save(packed, explicit_path)
		if save_err != OK:
			return _error("save_failed", "Failed to save scene.", {
				"path": explicit_path,
				"error_code": save_err,
				"error_name": error_string(save_err),
			})
		return _ok({"scene_path": explicit_path})

	var result: Variant = get_editor_interface().save_scene()
	if typeof(result) == TYPE_INT and int(result) != OK:
		return _error("save_failed", "Failed to save scene.", {
			"error_code": int(result),
			"error_name": error_string(int(result)),
		})

	return _ok({"scene_path": root.scene_file_path})

func _cmd_select_node(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("path", "")).strip_edges()
	if node_path.is_empty():
		return _error("missing_path", "select_node requires args.path.")

	var node: Node = _resolve_node(node_path)
	if node == null:
		return _error("node_not_found", "Node path could not be resolved.", {"path": node_path})

	var selection: EditorSelection = get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(node)
	return _ok({"node_path": str(node.get_path())})

func _cmd_add_node(args: Dictionary) -> Dictionary:
	var root: Node = get_editor_interface().get_edited_scene_root()
	if root == null:
		return _error("no_scene", "No edited scene is currently open.")

	var parent_path: String = str(args.get("parent", ".")).strip_edges()
	var parent: Node = _resolve_node(parent_path)
	if parent == null:
		return _error("parent_not_found", "Parent path could not be resolved.", {"parent": parent_path})

	var type_name: String = str(args.get("type", "Node")).strip_edges()
	if type_name.is_empty():
		type_name = "Node"
	if not ClassDB.can_instantiate(type_name):
		return _error("invalid_type", "ClassDB cannot instantiate this type.", {"type": type_name})

	var instance: Variant = ClassDB.instantiate(type_name)
	if instance == null or not (instance is Node):
		return _error("invalid_node_instance", "Instantiated object is not a Node.", {"type": type_name})
	var node: Node = instance as Node

	var desired_name: String = str(args.get("name", type_name)).strip_edges()
	node.name = _unique_child_name(parent, desired_name)
	parent.add_child(node)
	node.owner = root

	var properties_value: Variant = args.get("properties", {})
	if typeof(properties_value) == TYPE_DICTIONARY:
		var properties: Dictionary = properties_value
		for key in properties.keys():
			node.set(str(key), properties[key])

	var selection: EditorSelection = get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(node)

	return _ok({
		"node_path": str(node.get_path()),
		"node_name": node.name,
		"node_type": type_name,
	})

func _cmd_set_property(args: Dictionary) -> Dictionary:
	var node_path: String = str(args.get("path", "")).strip_edges()
	if node_path.is_empty():
		return _error("missing_path", "set_property requires args.path.")
	if not args.has("value"):
		return _error("missing_value", "set_property requires args.value.")

	var property_name: String = str(args.get("property", "")).strip_edges()
	if property_name.is_empty():
		return _error("missing_property", "set_property requires args.property.")

	var node: Node = _resolve_node(node_path)
	if node == null:
		return _error("node_not_found", "Node path could not be resolved.", {"path": node_path})

	node.set(property_name, args.get("value"))
	return _ok({
		"node_path": str(node.get_path()),
		"property": property_name,
		"value": args.get("value"),
	})

func _cmd_set_main_screen(args: Dictionary) -> Dictionary:
	var screen: String = str(args.get("screen", "2D")).strip_edges()
	if screen.is_empty():
		return _error("missing_screen", "set_main_screen requires args.screen.")
	get_editor_interface().set_main_screen_editor(screen)
	return _ok({"screen": screen})

func _cmd_call(args: Dictionary) -> Dictionary:
	var target_name: String = str(args.get("target", "editor_interface")).strip_edges()
	var method_name: String = str(args.get("method", "")).strip_edges()
	if method_name.is_empty():
		return _error("missing_method", "call requires args.method.")
	if method_name.begins_with("_"):
		return _error("disallowed_method", "Methods starting with '_' are blocked.")

	var target: Object = _resolve_call_target(target_name)
	if target == null:
		return _error("invalid_target", "Target is not available.", {
			"target": target_name,
			"allowed": PackedStringArray(["editor_interface", "edited_scene_root", "selection", "plugin"]),
		})
	if not target.has_method(method_name):
		return _error("unknown_method", "Target does not expose method.", {
			"target": target_name,
			"method": method_name,
		})

	var call_args_variant: Variant = args.get("arguments", [])
	var call_args: Array = []
	if typeof(call_args_variant) == TYPE_ARRAY:
		call_args = call_args_variant
	else:
		call_args = [call_args_variant]

	var result: Variant = target.callv(method_name, call_args)
	return _ok({
		"target": target_name,
		"method": method_name,
		"result": result,
	})

func _cmd_get_workflow_run(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	if run_id.is_empty():
		return _error("missing_run_id", "get_workflow_run requires args.run_id.")
	return get_workflow_run(run_id)

func _cmd_get_workflow_template(args: Dictionary) -> Dictionary:
	var template_id: String = str(args.get("template_id", "")).strip_edges()
	if template_id.is_empty():
		return _error("missing_template_id", "get_workflow_template requires args.template_id.")
	return get_workflow_template(template_id)

func _cmd_upsert_workflow_template(args: Dictionary) -> Dictionary:
	var template_value: Variant = args.get("template", {})
	if typeof(template_value) != TYPE_DICTIONARY:
		return _error("missing_template", "upsert_workflow_template requires args.template as an object.")
	return upsert_workflow_template(template_value)

func _cmd_delete_workflow_template(args: Dictionary) -> Dictionary:
	var template_id: String = str(args.get("template_id", "")).strip_edges()
	if template_id.is_empty():
		return _error("missing_template_id", "delete_workflow_template requires args.template_id.")
	return delete_workflow_template(template_id)

func _cmd_create_workflow_run(args: Dictionary) -> Dictionary:
	var template_id: String = str(args.get("template_id", "")).strip_edges()
	var asset_slug: String = str(args.get("asset_slug", "")).strip_edges()
	if template_id.is_empty():
		return _error("missing_template_id", "create_workflow_run requires args.template_id.")
	if asset_slug.is_empty():
		return _error("missing_asset_slug", "create_workflow_run requires args.asset_slug.")
	return create_workflow_run(template_id, asset_slug, str(args.get("display_name", "")))

func _cmd_delete_workflow_run(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	if run_id.is_empty():
		return _error("missing_run_id", "delete_workflow_run requires args.run_id.")
	return delete_workflow_run(run_id)

func _cmd_apply_workflow_decision(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	var attempt_id: String = str(args.get("attempt_id", "")).strip_edges()
	var decision: String = str(args.get("decision", "")).strip_edges()
	if run_id.is_empty():
		return _error("missing_run_id", "apply_workflow_decision requires args.run_id.")
	if attempt_id.is_empty():
		return _error("missing_attempt_id", "apply_workflow_decision requires args.attempt_id.")
	if decision.is_empty():
		return _error("missing_decision", "apply_workflow_decision requires args.decision.")
	return apply_workflow_decision(run_id, attempt_id, decision, str(args.get("note", "")))

func _cmd_set_workflow_import_recipe(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	var import_recipe_value: Variant = args.get("import_recipe", {})
	if run_id.is_empty():
		return _error("missing_run_id", "set_workflow_import_recipe requires args.run_id.")
	if typeof(import_recipe_value) != TYPE_DICTIONARY:
		return _error("missing_import_recipe", "set_workflow_import_recipe requires args.import_recipe as an object.")
	return set_workflow_import_recipe(run_id, import_recipe_value)

func _cmd_set_workflow_attempt_job(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	var attempt_id: String = str(args.get("attempt_id", "")).strip_edges()
	var provider: String = str(args.get("provider", "")).strip_edges()
	var task_type: String = str(args.get("task_type", "")).strip_edges()
	var request_payload_value: Variant = args.get("request_payload", {})
	if run_id.is_empty():
		return _error("missing_run_id", "set_workflow_attempt_job requires args.run_id.")
	if attempt_id.is_empty():
		return _error("missing_attempt_id", "set_workflow_attempt_job requires args.attempt_id.")
	if provider.is_empty():
		return _error("missing_provider", "set_workflow_attempt_job requires args.provider.")
	if task_type.is_empty():
		return _error("missing_task_type", "set_workflow_attempt_job requires args.task_type.")
	if typeof(request_payload_value) != TYPE_DICTIONARY:
		return _error("missing_request_payload", "set_workflow_attempt_job requires args.request_payload as an object.")
	return set_workflow_attempt_job(
		run_id,
		attempt_id,
		provider,
		task_type,
		request_payload_value,
		str(args.get("job_id", "")),
		str(args.get("idempotency_key", "")),
		str(args.get("note", "")),
	)

func _cmd_set_workflow_attempt_job_status(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	var attempt_id: String = str(args.get("attempt_id", "")).strip_edges()
	var status: String = str(args.get("status", "")).strip_edges()
	var response_payload_value: Variant = args.get("response_payload", {})
	var output_urls_value: Variant = args.get("output_urls", [])
	var downloaded_paths_value: Variant = args.get("downloaded_paths", [])
	if run_id.is_empty():
		return _error("missing_run_id", "set_workflow_attempt_job_status requires args.run_id.")
	if attempt_id.is_empty():
		return _error("missing_attempt_id", "set_workflow_attempt_job_status requires args.attempt_id.")
	if status.is_empty():
		return _error("missing_status", "set_workflow_attempt_job_status requires args.status.")
	if typeof(response_payload_value) != TYPE_DICTIONARY:
		return _error("invalid_response_payload", "set_workflow_attempt_job_status requires args.response_payload as an object.")
	if typeof(output_urls_value) != TYPE_ARRAY:
		return _error("invalid_output_urls", "set_workflow_attempt_job_status requires args.output_urls as an array.")
	if typeof(downloaded_paths_value) != TYPE_ARRAY:
		return _error("invalid_downloaded_paths", "set_workflow_attempt_job_status requires args.downloaded_paths as an array.")
	return set_workflow_attempt_job_status(
		run_id,
		attempt_id,
		status,
		str(args.get("job_id", "")),
		response_payload_value,
		output_urls_value,
		downloaded_paths_value,
		str(args.get("error_message", "")),
	)

func _cmd_register_workflow_artifact(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	var artifact_type: String = str(args.get("artifact_type", "")).strip_edges()
	var storage_uri: String = str(args.get("storage_uri", "")).strip_edges()
	var metadata_value: Variant = args.get("metadata", {})
	if run_id.is_empty():
		return _error("missing_run_id", "register_workflow_artifact requires args.run_id.")
	if artifact_type.is_empty():
		return _error("missing_artifact_type", "register_workflow_artifact requires args.artifact_type.")
	if storage_uri.is_empty():
		return _error("missing_storage_uri", "register_workflow_artifact requires args.storage_uri.")
	if typeof(metadata_value) != TYPE_DICTIONARY:
		return _error("invalid_metadata", "register_workflow_artifact requires args.metadata as an object.")
	return register_workflow_artifact(
		run_id,
		str(args.get("attempt_id", "")),
		artifact_type,
		str(args.get("display_name", "")),
		storage_uri,
		str(args.get("preview_uri", "")),
		metadata_value,
		bool(args.get("selected", false)),
		bool(args.get("publish_candidate", false)),
		str(args.get("artifact_id", "")),
	)

func _cmd_delete_workflow_artifact(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	var artifact_id: String = str(args.get("artifact_id", "")).strip_edges()
	if run_id.is_empty():
		return _error("missing_run_id", "delete_workflow_artifact requires args.run_id.")
	if artifact_id.is_empty():
		return _error("missing_artifact_id", "delete_workflow_artifact requires args.artifact_id.")
	return delete_workflow_artifact(run_id, artifact_id)

func _cmd_publish_workflow_revision(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	if run_id.is_empty():
		return _error("missing_run_id", "publish_workflow_revision requires args.run_id.")
	return publish_workflow_revision(
		run_id,
		str(args.get("version_label", "")),
		str(args.get("notes", "")),
	)

func _cmd_set_workflow_artifact_selected(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	var artifact_id: String = str(args.get("artifact_id", "")).strip_edges()
	if run_id.is_empty():
		return _error("missing_run_id", "set_workflow_artifact_selected requires args.run_id.")
	if artifact_id.is_empty():
		return _error("missing_artifact_id", "set_workflow_artifact_selected requires args.artifact_id.")
	return set_workflow_artifact_selected(
		run_id,
		artifact_id,
		bool(args.get("selected", true)),
	)

func _cmd_set_workflow_artifact_publish_candidate(args: Dictionary) -> Dictionary:
	var run_id: String = str(args.get("run_id", "")).strip_edges()
	var artifact_id: String = str(args.get("artifact_id", "")).strip_edges()
	if run_id.is_empty():
		return _error("missing_run_id", "set_workflow_artifact_publish_candidate requires args.run_id.")
	if artifact_id.is_empty():
		return _error("missing_artifact_id", "set_workflow_artifact_publish_candidate requires args.artifact_id.")
	return set_workflow_artifact_publish_candidate(
		run_id,
		artifact_id,
		bool(args.get("publish_candidate", true)),
	)

func _resolve_call_target(target_name: String) -> Object:
	match target_name:
		"editor_interface":
			return get_editor_interface()
		"edited_scene_root":
			return get_editor_interface().get_edited_scene_root()
		"selection":
			return get_editor_interface().get_selection()
		"plugin":
			return self
		_:
			return null

func _load_bridge_contract_commands() -> PackedStringArray:
	if not FileAccess.file_exists(BRIDGE_CONTRACT_PATH):
		return PackedStringArray()

	var contract_file: FileAccess = FileAccess.open(BRIDGE_CONTRACT_PATH, FileAccess.READ)
	if contract_file == null:
		return PackedStringArray()

	var parsed: Variant = JSON.parse_string(contract_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return PackedStringArray()

	var commands_value: Variant = parsed.get("commands", [])
	if typeof(commands_value) != TYPE_ARRAY:
		return PackedStringArray()

	var commands: PackedStringArray = PackedStringArray()
	for command_value in commands_value:
		if typeof(command_value) != TYPE_DICTIONARY:
			continue
		var command_data: Dictionary = command_value
		var command_name: String = str(command_data.get("name", "")).strip_edges()
		if not command_name.is_empty():
			commands.append(command_name)
	return commands

func _resolve_main_screen_host() -> Control:
	var editor_interface: EditorInterface = get_editor_interface()
	if editor_interface != null and editor_interface.has_method("get_editor_main_screen"):
		var host_variant: Variant = editor_interface.call("get_editor_main_screen")
		if host_variant is Control:
			return host_variant as Control
	return editor_interface.get_base_control()

func _resolve_node(path: String) -> Node:
	var root: Node = get_editor_interface().get_edited_scene_root()
	if root == null:
		return null

	var cleaned: String = path.strip_edges()
	if cleaned.is_empty() or cleaned == "." or cleaned == "/":
		return root

	var direct: Node = root.get_node_or_null(NodePath(cleaned))
	if direct != null:
		return direct

	if cleaned.begins_with("/"):
		var relative: String = cleaned.trim_prefix("/")
		if relative == root.name:
			return root
		if relative.begins_with(root.name + "/"):
			relative = relative.trim_prefix(root.name + "/")
		var resolved: Node = root.get_node_or_null(NodePath(relative))
		if resolved != null:
			return resolved

	return null

func _normalize_scene_path(raw_path: String) -> String:
	var path: String = raw_path.strip_edges()
	if path.is_empty():
		return ""
	if path.begins_with("res://"):
		return path
	return "res://" + path.trim_prefix("/")

func _unique_child_name(parent: Node, preferred_name: String) -> String:
	var base_name: String = preferred_name
	if base_name.is_empty():
		base_name = "Node"

	var candidate: String = base_name
	var counter: int = 1
	while parent.has_node(NodePath(candidate)):
		candidate = "%s%d" % [base_name, counter]
		counter += 1
	return candidate

func _ok(extra: Dictionary = {}) -> Dictionary:
	var response: Dictionary = {"ok": true}
	for key in extra.keys():
		response[str(key)] = extra[key]
	return response

func _error(code: String, message: String, extra: Dictionary = {}) -> Dictionary:
	var response: Dictionary = {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
		},
	}
	for key in extra.keys():
		response[str(key)] = extra[key]
	return response

func _on_server_log(text: String) -> void:
	_last_log = text
	if _dock != null and _dock.has_method("append_log"):
		_dock.call("append_log", text)
	_refresh_dock()

func _on_command_processed(command: String, response: Dictionary) -> void:
	_last_command = command
	_last_response = response
	if _dock != null and _dock.has_method("set_last_command"):
		_dock.call("set_last_command", command, response)
	if command.find("workflow") != -1 or command.begins_with("pipeline_"):
		_refresh_pipeline_screen()
	_refresh_dock()

func _on_server_status_changed(_is_running: bool, _bind_address: String, _port: int) -> void:
	_refresh_dock()

func _refresh_dock() -> void:
	if _dock != null and _dock.has_method("refresh_from_plugin"):
		_dock.call("refresh_from_plugin")

func _refresh_pipeline_screen() -> void:
	if _main_screen != null and _main_screen.has_method("refresh_from_plugin"):
		_main_screen.call("refresh_from_plugin")
