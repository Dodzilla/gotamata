@tool
extends VBoxContainer

var _plugin: EditorPlugin

var _status_label: Label
var _summary_label: Label
var _last_command_label: Label
var _response_view: TextEdit
var _log_view: TextEdit

func _ready() -> void:
	name = "KillaTamata Arcade"
	_ensure_ui()

func attach_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_ensure_ui()
	refresh_from_plugin()

func refresh_from_plugin() -> void:
	if _plugin == null or not _plugin.has_method("get_dock_snapshot"):
		return

	var snapshot: Dictionary = _plugin.call("get_dock_snapshot")
	var server: Dictionary = snapshot.get("server", {})
	var project: Dictionary = snapshot.get("project", {})
	var logs: Array = snapshot.get("logs", [])

	_status_label.text = "Bridge: %s\nHost: %s:%d\nToken: %s\nLast connection: %s" % [
		"Running" if bool(server.get("running", false)) else "Stopped",
		str(server.get("bind_address", "127.0.0.1")),
		int(server.get("port", 47891)),
		"enabled" if bool(server.get("auth_token_set", false)) else "disabled",
		str(server.get("last_connection_time", "never")),
	]

	_summary_label.text = "Project: %s\nSlug: %s\nTitle: %s\nVersion: %s\nPreset: %s\nValidation: %s (%d blockers, %d warnings)" % [
		str(project.get("projectName", "")),
		str(project.get("gameSlug", "")),
		str(project.get("title", "")),
		str(project.get("version", "")),
		str(project.get("exportPresetName", "")),
		"ready" if bool(project.get("ready", false)) else "not ready",
		int(project.get("blockingIssueCount", 0)),
		int(project.get("warningCount", 0)),
	]

	_log_view.text = "\n".join(logs)
	_log_view.scroll_vertical = _log_view.get_line_count()

	if snapshot.has("lastCommand"):
		_last_command_label.text = "Last command: %s" % str(snapshot.get("lastCommand", "(none)"))
	if snapshot.has("lastResponse"):
		_response_view.text = JSON.stringify(snapshot.get("lastResponse", {}), "  ")

func set_last_command(command: String, response: Dictionary) -> void:
	_ensure_ui()
	_last_command_label.text = "Last command: %s" % command
	_response_view.text = JSON.stringify(response, "  ")

func _ensure_ui() -> void:
	if _status_label != null:
		return

	custom_minimum_size = Vector2(360, 560)

	var title: Label = Label.new()
	title.text = "KillaTamata Arcade Bridge"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var hint: Label = Label.new()
	hint.text = "Use this dock for server status, quick validation, and local release builds."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary_label)

	var server_buttons: HBoxContainer = HBoxContainer.new()
	server_buttons.add_child(_make_button("Start", "_on_start_pressed"))
	server_buttons.add_child(_make_button("Stop", "_on_stop_pressed"))
	add_child(server_buttons)

	var action_buttons: HBoxContainer = HBoxContainer.new()
	action_buttons.add_child(_make_button("Validate", "_on_validate_pressed"))
	action_buttons.add_child(_make_button("Ensure Preset", "_on_ensure_preset_pressed"))
	action_buttons.add_child(_make_button("Manifest", "_on_manifest_pressed"))
	add_child(action_buttons)

	var build_buttons: HBoxContainer = HBoxContainer.new()
	build_buttons.add_child(_make_button("Build Release", "_on_build_pressed"))
	build_buttons.add_child(_make_button("Reveal Build", "_on_reveal_pressed"))
	add_child(build_buttons)

	_last_command_label = Label.new()
	_last_command_label.text = "Last command: (none)"
	add_child(_last_command_label)

	_response_view = TextEdit.new()
	_response_view.custom_minimum_size = Vector2(0, 120)
	_response_view.editable = false
	_response_view.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(_response_view)

	var log_label: Label = Label.new()
	log_label.text = "Recent logs"
	add_child(log_label)

	_log_view = TextEdit.new()
	_log_view.custom_minimum_size = Vector2(0, 220)
	_log_view.editable = false
	_log_view.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(_log_view)

func _make_button(label: String, method_name: String) -> Button:
	var button: Button = Button.new()
	button.text = label
	button.pressed.connect(Callable(self, method_name))
	return button

func _run_plugin_action(method_name: String) -> void:
	if _plugin == null or not _plugin.has_method(method_name):
		return
	var response: Dictionary = _plugin.call(method_name)
	set_last_command(method_name, response)
	refresh_from_plugin()

func _on_start_pressed() -> void:
	_run_plugin_action("start_server")

func _on_stop_pressed() -> void:
	_run_plugin_action("stop_server")

func _on_validate_pressed() -> void:
	_run_plugin_action("run_validate_action")

func _on_ensure_preset_pressed() -> void:
	_run_plugin_action("run_ensure_preset_action")

func _on_manifest_pressed() -> void:
	_run_plugin_action("run_manifest_preview_action")

func _on_build_pressed() -> void:
	_run_plugin_action("run_build_action")

func _on_reveal_pressed() -> void:
	_run_plugin_action("run_reveal_action")
