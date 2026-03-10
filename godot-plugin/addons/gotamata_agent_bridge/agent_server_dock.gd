@tool
extends VBoxContainer

var _plugin: EditorPlugin

var _status_label: Label
var _bind_input: LineEdit
var _port_input: SpinBox
var _token_input: LineEdit
var _autostart_check: CheckBox
var _last_command_label: Label
var _last_response_view: TextEdit
var _log_view: TextEdit
var _last_log_rendered: String = ""

func _ready() -> void:
	name = "GoTamata Control"
	_ensure_ui()

func attach_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_ensure_ui()
	_refresh_settings_inputs()
	refresh_from_plugin()

func refresh_from_plugin() -> void:
	if _plugin == null:
		return
	if not _plugin.has_method("get_server_status"):
		return

	var status: Dictionary = _plugin.call("get_server_status")
	var running: bool = bool(status.get("running", false))
	var bind_address: String = str(status.get("bind_address", "127.0.0.1"))
	var port: int = int(status.get("port", 47891))

	_status_label.text = "Status: %s (%s:%d)" % ["Running" if running else "Stopped", bind_address, port]
	if status.has("last_log"):
		var last_log: String = str(status.get("last_log", ""))
		if not last_log.is_empty() and last_log != _last_log_rendered:
			append_log(last_log)

func append_log(message: String) -> void:
	_ensure_ui()
	if message.is_empty():
		return
	var current: String = _log_view.text
	if not current.is_empty():
		current += "\n"
	_log_view.text = current + message
	_last_log_rendered = message
	_log_view.scroll_vertical = _log_view.get_line_count()

func set_last_command(command: String, response: Dictionary) -> void:
	_ensure_ui()
	_last_command_label.text = "Last command: %s" % command
	_last_response_view.text = JSON.stringify(response)

func _ensure_ui() -> void:
	if _status_label != null:
		return

	custom_minimum_size = Vector2(320, 420)

	var title: Label = Label.new()
	title.text = "GoTamata Control Plane"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var hint: Label = Label.new()
	hint.text = "Use the GoTamata main tab for workflow runs and asset publishing."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_status_label = Label.new()
	_status_label.text = "Status: Stopped"
	add_child(_status_label)

	var bind_row: HBoxContainer = HBoxContainer.new()
	var bind_label: Label = Label.new()
	bind_label.text = "Bind"
	bind_row.add_child(bind_label)
	_bind_input = LineEdit.new()
	_bind_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bind_input.placeholder_text = "127.0.0.1"
	bind_row.add_child(_bind_input)
	add_child(bind_row)

	var port_row: HBoxContainer = HBoxContainer.new()
	var port_label: Label = Label.new()
	port_label.text = "Port"
	port_row.add_child(port_label)
	_port_input = SpinBox.new()
	_port_input.min_value = 1
	_port_input.max_value = 65535
	_port_input.step = 1
	_port_input.rounded = true
	_port_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(_port_input)
	add_child(port_row)

	var token_row: HBoxContainer = HBoxContainer.new()
	var token_label: Label = Label.new()
	token_label.text = "Token"
	token_row.add_child(token_label)
	_token_input = LineEdit.new()
	_token_input.secret = true
	_token_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_token_input.placeholder_text = "Optional shared secret"
	token_row.add_child(_token_input)
	add_child(token_row)

	_autostart_check = CheckBox.new()
	_autostart_check.text = "Autostart server when plugin loads"
	add_child(_autostart_check)

	var button_row: HBoxContainer = HBoxContainer.new()
	var apply_button: Button = Button.new()
	apply_button.text = "Apply + Restart"
	apply_button.pressed.connect(_on_apply_pressed)
	button_row.add_child(apply_button)

	var start_button: Button = Button.new()
	start_button.text = "Start"
	start_button.pressed.connect(_on_start_pressed)
	button_row.add_child(start_button)

	var stop_button: Button = Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(_on_stop_pressed)
	button_row.add_child(stop_button)
	add_child(button_row)

	_last_command_label = Label.new()
	_last_command_label.text = "Last command: (none)"
	add_child(_last_command_label)

	_last_response_view = TextEdit.new()
	_last_response_view.custom_minimum_size = Vector2(0, 80)
	_last_response_view.editable = false
	_last_response_view.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(_last_response_view)

	var log_label: Label = Label.new()
	log_label.text = "Server log"
	add_child(log_label)

	_log_view = TextEdit.new()
	_log_view.custom_minimum_size = Vector2(0, 160)
	_log_view.editable = false
	_log_view.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(_log_view)

func _refresh_settings_inputs() -> void:
	if _plugin == null:
		return
	if not _plugin.has_method("get_settings_snapshot"):
		return
	var settings: Dictionary = _plugin.call("get_settings_snapshot")
	_bind_input.text = str(settings.get("bind_address", "127.0.0.1"))
	_port_input.value = float(int(settings.get("port", 47891)))
	_token_input.text = str(settings.get("auth_token", ""))
	_autostart_check.button_pressed = bool(settings.get("autostart", true))

func _on_apply_pressed() -> void:
	if _plugin == null:
		return
	if not _plugin.has_method("apply_settings_and_restart"):
		return

	_plugin.call(
		"apply_settings_and_restart",
		_bind_input.text,
		int(_port_input.value),
		_token_input.text,
		_autostart_check.button_pressed
	)
	refresh_from_plugin()

func _on_start_pressed() -> void:
	if _plugin == null or not _plugin.has_method("start_server"):
		return
	_plugin.call("start_server")
	refresh_from_plugin()

func _on_stop_pressed() -> void:
	if _plugin == null or not _plugin.has_method("stop_server"):
		return
	_plugin.call("stop_server")
	refresh_from_plugin()
