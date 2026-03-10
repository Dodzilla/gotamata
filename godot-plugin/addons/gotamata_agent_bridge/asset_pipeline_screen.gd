@tool
extends Control

var _plugin: EditorPlugin

var _templates: Array = []
var _run_summaries: Array = []
var _selected_template: Dictionary = {}
var _selected_run: Dictionary = {}
var _selected_template_id: String = ""
var _selected_run_id: String = ""
var _selected_attempt_id: String = ""
var _selected_artifact_id: String = ""

var _template_ids: Array = []
var _run_ids: Array = []
var _attempt_ids: Array = []
var _artifact_ids: Array = []

var _overview_label: Label
var _status_label: Label
var _template_list: ItemList
var _run_list: ItemList
var _revision_list: ItemList
var _asset_slug_input: LineEdit
var _display_name_input: LineEdit
var _run_summary_view: TextEdit
var _attempt_list: ItemList
var _artifact_list: ItemList
var _attempt_details_view: TextEdit
var _artifact_details_view: TextEdit
var _decision_buttons: FlowContainer
var _artifact_select_button: Button
var _artifact_publish_button: Button
var _artifact_delete_button: Button
var _publish_version_input: LineEdit
var _publish_notes_input: TextEdit
var _publish_button: Button
var _delete_run_button: Button
var _log_view: TextEdit
var _validation_view: TextEdit
var _json_view: TextEdit
var _template_json_view: TextEdit

var _job_provider_input: LineEdit
var _job_task_input: LineEdit
var _job_id_input: LineEdit
var _job_idempotency_input: LineEdit
var _job_status_input: LineEdit
var _job_error_input: LineEdit
var _job_request_view: TextEdit
var _job_response_view: TextEdit
var _job_output_urls_view: TextEdit
var _job_downloaded_paths_view: TextEdit

var _artifact_type_input: LineEdit
var _artifact_name_input: LineEdit
var _artifact_storage_input: LineEdit
var _artifact_preview_input: LineEdit
var _artifact_metadata_view: TextEdit
var _artifact_selected_check: CheckBox
var _artifact_publish_check: CheckBox

var _import_recipe_view: TextEdit

func _ready() -> void:
	name = "GoTamata Pipeline"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ensure_ui()

func attach_plugin(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_ensure_ui()
	refresh_from_plugin()

func refresh_from_plugin() -> void:
	_ensure_ui()
	if _plugin == null:
		return

	var overview_response: Dictionary = _plugin.call("get_pipeline_overview")
	var templates_response: Dictionary = _plugin.call("get_workflow_templates")
	var runs_response: Dictionary = _plugin.call("get_workflow_runs")

	if not bool(overview_response.get("ok", false)):
		_status_label.text = "Pipeline repository unavailable."
		return

	_templates = _as_array(templates_response.get("templates", []))
	_run_summaries = _as_array(runs_response.get("runs", []))

	var overview: Dictionary = _as_dictionary(overview_response.get("overview", {}))
	_overview_label.text = "Templates: %d   Runs: %d   Revisions: %d   Scratch: %s" % [
		int(overview.get("template_count", 0)),
		int(overview.get("run_count", 0)),
		int(overview.get("revision_count", 0)),
		str(overview.get("scratch_dir", "res://_ai_work")),
	]

	_refresh_template_list()
	_refresh_run_list()
	_load_selected_template()
	_load_selected_run()
	_refresh_revision_list()
	_refresh_attempt_list()
	_refresh_artifact_list()
	_refresh_detail_panels()
	_refresh_output_tabs()

func _ensure_ui() -> void:
	if _overview_label != null:
		return

	var root: VBoxContainer = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)

	var header: VBoxContainer = VBoxContainer.new()
	root.add_child(header)

	var title: Label = Label.new()
	title.text = "GoTamata Asset Pipeline"
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Templates, runs, jobs, imports, artifacts, and publish are available in both the UI and the bridge."
	header.add_child(subtitle)

	_overview_label = Label.new()
	_overview_label.text = "Templates: 0   Runs: 0   Revisions: 0"
	header.add_child(_overview_label)

	_status_label = Label.new()
	_status_label.text = "Select a template to create a workflow run."
	header.add_child(_status_label)

	var split_root: VSplitContainer = VSplitContainer.new()
	split_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split_root)

	var top_split: HSplitContainer = HSplitContainer.new()
	top_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_root.add_child(top_split)

	top_split.add_child(_build_left_panel())
	top_split.add_child(_build_center_panel())
	top_split.add_child(_build_right_panel())

	split_root.add_child(_build_bottom_tabs())

func _build_left_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(content)

	var template_label: Label = Label.new()
	template_label.text = "Workflow Templates"
	content.add_child(template_label)

	var template_button_row: HBoxContainer = HBoxContainer.new()
	content.add_child(template_button_row)

	var new_template_button: Button = Button.new()
	new_template_button.text = "New"
	new_template_button.pressed.connect(_on_new_template_pressed)
	template_button_row.add_child(new_template_button)

	var save_template_button: Button = Button.new()
	save_template_button.text = "Save"
	save_template_button.pressed.connect(_on_save_template_pressed)
	template_button_row.add_child(save_template_button)

	var delete_template_button: Button = Button.new()
	delete_template_button.text = "Delete"
	delete_template_button.pressed.connect(_on_delete_template_pressed)
	template_button_row.add_child(delete_template_button)

	_template_list = ItemList.new()
	_template_list.custom_minimum_size = Vector2(0, 140)
	_template_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_template_list.item_selected.connect(_on_template_selected)
	content.add_child(_template_list)

	_asset_slug_input = LineEdit.new()
	_asset_slug_input.placeholder_text = "asset-slug"
	content.add_child(_asset_slug_input)

	_display_name_input = LineEdit.new()
	_display_name_input.placeholder_text = "Display name (optional)"
	content.add_child(_display_name_input)

	var create_run_row: HBoxContainer = HBoxContainer.new()
	content.add_child(create_run_row)

	var create_run_button: Button = Button.new()
	create_run_button.text = "Create Run"
	create_run_button.pressed.connect(_on_create_run_pressed)
	create_run_row.add_child(create_run_button)

	var refresh_button: Button = Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh_from_plugin)
	create_run_row.add_child(refresh_button)

	var runs_label: Label = Label.new()
	runs_label.text = "Workflow Runs"
	content.add_child(runs_label)

	_run_list = ItemList.new()
	_run_list.custom_minimum_size = Vector2(0, 180)
	_run_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_run_list.item_selected.connect(_on_run_selected)
	content.add_child(_run_list)

	_delete_run_button = Button.new()
	_delete_run_button.text = "Delete Selected Run"
	_delete_run_button.disabled = true
	_delete_run_button.pressed.connect(_on_delete_run_pressed)
	content.add_child(_delete_run_button)

	var revisions_label: Label = Label.new()
	revisions_label.text = "Published Revisions"
	content.add_child(revisions_label)

	_revision_list = ItemList.new()
	_revision_list.custom_minimum_size = Vector2(0, 120)
	content.add_child(_revision_list)

	return panel

func _build_center_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(content)

	var summary_label: Label = Label.new()
	summary_label.text = "Run Summary"
	content.add_child(summary_label)

	_run_summary_view = TextEdit.new()
	_run_summary_view.custom_minimum_size = Vector2(0, 120)
	_run_summary_view.editable = false
	_run_summary_view.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.add_child(_run_summary_view)

	var attempt_label: Label = Label.new()
	attempt_label.text = "Step Attempts"
	content.add_child(attempt_label)

	_attempt_list = ItemList.new()
	_attempt_list.custom_minimum_size = Vector2(0, 180)
	_attempt_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_attempt_list.item_selected.connect(_on_attempt_selected)
	content.add_child(_attempt_list)

	var artifact_label: Label = Label.new()
	artifact_label.text = "Artifacts"
	content.add_child(artifact_label)

	_artifact_list = ItemList.new()
	_artifact_list.custom_minimum_size = Vector2(0, 180)
	_artifact_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_artifact_list.item_selected.connect(_on_artifact_selected)
	content.add_child(_artifact_list)

	return panel

func _build_right_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var inspector_label: Label = Label.new()
	inspector_label.text = "Inspector"
	content.add_child(inspector_label)

	_attempt_details_view = TextEdit.new()
	_attempt_details_view.custom_minimum_size = Vector2(0, 180)
	_attempt_details_view.editable = false
	_attempt_details_view.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.add_child(_attempt_details_view)

	var action_label: Label = Label.new()
	action_label.text = "Step Actions"
	content.add_child(action_label)

	_decision_buttons = FlowContainer.new()
	_decision_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_decision_buttons)

	content.add_child(_section_label("External Job"))
	_job_provider_input = _line_input(content, "Provider (for example killatamata)")
	_job_task_input = _line_input(content, "Task type (for example image.generate)")
	_job_id_input = _line_input(content, "Job id")
	_job_idempotency_input = _line_input(content, "Idempotency key")
	_job_request_view = _json_edit(content, 110)
	_job_status_input = _line_input(content, "Status")
	_job_error_input = _line_input(content, "Error message")
	_job_response_view = _json_edit(content, 90)
	_job_output_urls_view = _json_edit(content, 70)
	_job_downloaded_paths_view = _json_edit(content, 70)

	var job_button_row: HBoxContainer = HBoxContainer.new()
	content.add_child(job_button_row)

	var save_job_button: Button = Button.new()
	save_job_button.text = "Save Job Request"
	save_job_button.pressed.connect(_on_save_job_request_pressed)
	job_button_row.add_child(save_job_button)

	var save_job_status_button: Button = Button.new()
	save_job_status_button.text = "Save Job Status"
	save_job_status_button.pressed.connect(_on_save_job_status_pressed)
	job_button_row.add_child(save_job_status_button)

	content.add_child(_section_label("Import Recipe"))
	_import_recipe_view = _json_edit(content, 120)

	var save_import_recipe_button: Button = Button.new()
	save_import_recipe_button.text = "Save Import Recipe"
	save_import_recipe_button.pressed.connect(_on_save_import_recipe_pressed)
	content.add_child(save_import_recipe_button)

	content.add_child(_section_label("Artifact Details"))
	_artifact_details_view = TextEdit.new()
	_artifact_details_view.custom_minimum_size = Vector2(0, 120)
	_artifact_details_view.editable = false
	_artifact_details_view.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content.add_child(_artifact_details_view)

	var artifact_button_row: HBoxContainer = HBoxContainer.new()
	content.add_child(artifact_button_row)

	_artifact_select_button = Button.new()
	_artifact_select_button.text = "Toggle Selected"
	_artifact_select_button.disabled = true
	_artifact_select_button.pressed.connect(_on_toggle_selected_pressed)
	artifact_button_row.add_child(_artifact_select_button)

	_artifact_publish_button = Button.new()
	_artifact_publish_button.text = "Toggle Publish Candidate"
	_artifact_publish_button.disabled = true
	_artifact_publish_button.pressed.connect(_on_toggle_publish_candidate_pressed)
	artifact_button_row.add_child(_artifact_publish_button)

	_artifact_delete_button = Button.new()
	_artifact_delete_button.text = "Delete Artifact"
	_artifact_delete_button.disabled = true
	_artifact_delete_button.pressed.connect(_on_delete_artifact_pressed)
	artifact_button_row.add_child(_artifact_delete_button)

	content.add_child(_section_label("Register / Update Artifact"))
	_artifact_type_input = _line_input(content, "Artifact type")
	_artifact_name_input = _line_input(content, "Display name")
	_artifact_storage_input = _line_input(content, "Storage URI")
	_artifact_preview_input = _line_input(content, "Preview URI")
	_artifact_metadata_view = _json_edit(content, 90)

	var artifact_check_row: HBoxContainer = HBoxContainer.new()
	content.add_child(artifact_check_row)

	_artifact_selected_check = CheckBox.new()
	_artifact_selected_check.text = "Selected"
	artifact_check_row.add_child(_artifact_selected_check)

	_artifact_publish_check = CheckBox.new()
	_artifact_publish_check.text = "Publish Candidate"
	artifact_check_row.add_child(_artifact_publish_check)

	var register_artifact_button: Button = Button.new()
	register_artifact_button.text = "Register Artifact"
	register_artifact_button.pressed.connect(_on_register_artifact_pressed)
	content.add_child(register_artifact_button)

	content.add_child(_section_label("Publish Revision"))
	_publish_version_input = _line_input(content, "Version label (optional)")
	_publish_notes_input = TextEdit.new()
	_publish_notes_input.custom_minimum_size = Vector2(0, 90)
	content.add_child(_publish_notes_input)

	_publish_button = Button.new()
	_publish_button.text = "Publish Selected Run"
	_publish_button.disabled = true
	_publish_button.pressed.connect(_on_publish_pressed)
	content.add_child(_publish_button)

	return panel

func _build_bottom_tabs() -> Control:
	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var logs_tab: VBoxContainer = VBoxContainer.new()
	logs_tab.name = "Logs"
	tabs.add_child(logs_tab)
	_log_view = _read_only_edit(logs_tab)

	var validation_tab: VBoxContainer = VBoxContainer.new()
	validation_tab.name = "Validation"
	tabs.add_child(validation_tab)
	_validation_view = _read_only_edit(validation_tab)

	var raw_tab: VBoxContainer = VBoxContainer.new()
	raw_tab.name = "Run JSON"
	tabs.add_child(raw_tab)
	_json_view = _read_only_edit(raw_tab)

	var template_tab: VBoxContainer = VBoxContainer.new()
	template_tab.name = "Template JSON"
	tabs.add_child(template_tab)

	_template_json_view = TextEdit.new()
	_template_json_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_template_json_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_template_json_view.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	template_tab.add_child(_template_json_view)

	return tabs

func _section_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label

func _line_input(parent: Control, placeholder: String) -> LineEdit:
	var input: LineEdit = LineEdit.new()
	input.placeholder_text = placeholder
	parent.add_child(input)
	return input

func _json_edit(parent: Control, min_height: float) -> TextEdit:
	var edit: TextEdit = TextEdit.new()
	edit.custom_minimum_size = Vector2(0, min_height)
	edit.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(edit)
	return edit

func _read_only_edit(parent: Control) -> TextEdit:
	var edit: TextEdit = TextEdit.new()
	edit.editable = false
	edit.line_wrapping_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	return edit

func _refresh_template_list() -> void:
	_template_list.clear()
	_template_ids.clear()
	var has_selected_template: bool = false
	for template_summary in _templates:
		var template_data: Dictionary = _as_dictionary(template_summary)
		var template_id: String = str(template_data.get("template_id", ""))
		_template_ids.append(template_id)
		_template_list.add_item("%s [%s]" % [
			str(template_data.get("name", "Template")),
			str(template_data.get("asset_type", "generic")),
		])
		if template_id == _selected_template_id:
			_template_list.select(_template_ids.size() - 1)
			has_selected_template = true

	if _template_ids.is_empty():
		_selected_template_id = ""
	elif not has_selected_template:
		_selected_template_id = str(_template_ids[0])
		_template_list.select(0)

func _refresh_run_list() -> void:
	_run_list.clear()
	_run_ids.clear()
	var has_selected_run: bool = false
	for run_summary in _run_summaries:
		var run_data: Dictionary = _as_dictionary(run_summary)
		var run_id: String = str(run_data.get("run_id", ""))
		_run_ids.append(run_id)
		var label: String = "%s (%s) [%d attempts, %d artifacts]" % [
			str(run_data.get("display_name", run_data.get("asset_slug", run_id))),
			str(run_data.get("template_name", run_data.get("template_id", ""))),
			int(run_data.get("attempt_count", 0)),
			int(run_data.get("artifact_count", 0)),
		]
		if not str(run_data.get("latest_revision", "")).is_empty():
			label += " " + str(run_data.get("latest_revision", ""))
		_run_list.add_item(label)
		if run_id == _selected_run_id:
			_run_list.select(_run_ids.size() - 1)
			has_selected_run = true

	if _run_ids.is_empty():
		_selected_run_id = ""
		_selected_attempt_id = ""
		_selected_artifact_id = ""
	elif not has_selected_run:
		_selected_run_id = str(_run_ids[0])
		_run_list.select(0)

	_delete_run_button.disabled = _selected_run_id.is_empty()

func _load_selected_template() -> void:
	_selected_template = {}
	if _plugin == null or _selected_template_id.is_empty():
		_template_json_view.text = JSON.stringify(_new_template_stub(), "\t")
		return

	var response: Dictionary = _plugin.call("get_workflow_template", _selected_template_id)
	if not bool(response.get("ok", false)):
		_selected_template = _new_template_stub()
		_template_json_view.text = JSON.stringify(_selected_template, "\t")
		return

	_selected_template = _as_dictionary(response.get("template", {}))
	_template_json_view.text = JSON.stringify(_selected_template, "\t")

func _load_selected_run() -> void:
	_selected_run = {}
	if _plugin == null or _selected_run_id.is_empty():
		return
	var response: Dictionary = _plugin.call("get_workflow_run", _selected_run_id)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_selected_run = _as_dictionary(response.get("run", {}))
	_publish_button.disabled = _selected_run.is_empty()

func _refresh_revision_list() -> void:
	_revision_list.clear()
	for revision_data in _as_array(_selected_run.get("revisions", [])):
		var revision_dict: Dictionary = _as_dictionary(revision_data)
		_revision_list.add_item("%s [%s]" % [
			str(revision_dict.get("revision", "")),
			str(revision_dict.get("release_state", "draft_release")),
		])

func _refresh_attempt_list() -> void:
	_attempt_list.clear()
	_attempt_ids.clear()
	var attempts: Dictionary = _as_dictionary(_selected_run.get("attempts", {}))
	var attempt_keys: Array = attempts.keys()
	attempt_keys.sort()
	var has_selected_attempt: bool = false
	for attempt_id in attempt_keys:
		var attempt_data: Dictionary = _as_dictionary(attempts.get(attempt_id, {}))
		var label: String = "%s [%s]" % [
			str(attempt_data.get("step_label", attempt_id)),
			str(attempt_data.get("state", "idle")),
		]
		_attempt_ids.append(str(attempt_id))
		_attempt_list.add_item(label)
		if str(attempt_id) == _selected_attempt_id:
			_attempt_list.select(_attempt_ids.size() - 1)
			has_selected_attempt = true

	if _attempt_ids.is_empty():
		_selected_attempt_id = ""
	elif not has_selected_attempt:
		_selected_attempt_id = str(_attempt_ids[0])
		_attempt_list.select(0)

func _refresh_artifact_list() -> void:
	_artifact_list.clear()
	_artifact_ids.clear()
	var artifacts: Dictionary = _as_dictionary(_selected_run.get("artifacts", {}))
	var artifact_keys: Array = artifacts.keys()
	artifact_keys.sort()
	var has_selected_artifact: bool = false
	for artifact_id in artifact_keys:
		var artifact_data: Dictionary = _as_dictionary(artifacts.get(artifact_id, {}))
		var prefixes: Array = []
		if bool(artifact_data.get("is_selected", false)):
			prefixes.append("selected")
		if bool(artifact_data.get("is_publish_candidate", false)):
			prefixes.append("publish")
		var prefix_text: String = ""
		if not prefixes.is_empty():
			prefix_text = "[" + _join_values(prefixes, ", ") + "] "
		_artifact_ids.append(str(artifact_id))
		_artifact_list.add_item("%s%s" % [
			prefix_text,
			str(artifact_data.get("display_name", artifact_id)),
		])
		if str(artifact_id) == _selected_artifact_id:
			_artifact_list.select(_artifact_ids.size() - 1)
			has_selected_artifact = true

	if _artifact_ids.is_empty():
		_selected_artifact_id = ""
	elif not has_selected_artifact:
		_selected_artifact_id = str(_artifact_ids[0])
		_artifact_list.select(0)

func _refresh_detail_panels() -> void:
	_run_summary_view.text = _format_run_summary(_selected_run)
	_attempt_details_view.text = _format_attempt(_selected_attempt())
	_artifact_details_view.text = _format_artifact(_selected_artifact())
	_rebuild_decision_buttons()
	_load_job_controls()
	_load_import_recipe_controls()
	_load_artifact_controls()
	_update_action_button_state()

func _refresh_output_tabs() -> void:
	_log_view.text = _join_values(_as_array(_selected_run.get("logs", [])), "\n")
	_validation_view.text = _format_validation_report(_as_array(_selected_run.get("validation_report", [])))
	_json_view.text = JSON.stringify(_selected_run, "\t") if not _selected_run.is_empty() else ""

func _selected_attempt() -> Dictionary:
	var attempts: Dictionary = _as_dictionary(_selected_run.get("attempts", {}))
	if attempts.has(_selected_attempt_id):
		return _as_dictionary(attempts.get(_selected_attempt_id, {}))
	return {}

func _selected_artifact() -> Dictionary:
	var artifacts: Dictionary = _as_dictionary(_selected_run.get("artifacts", {}))
	if artifacts.has(_selected_artifact_id):
		return _as_dictionary(artifacts.get(_selected_artifact_id, {}))
	return {}

func _rebuild_decision_buttons() -> void:
	for child in _decision_buttons.get_children():
		child.queue_free()

	var attempt_data: Dictionary = _selected_attempt()
	if attempt_data.is_empty():
		return
	if str(attempt_data.get("step_type", "")) == "publish":
		var publish_hint: Label = Label.new()
		publish_hint.text = "Use the publish form below to create a canonical revision."
		_decision_buttons.add_child(publish_hint)
		return

	for decision_name in _as_array(attempt_data.get("available_decisions", [])):
		var button: Button = Button.new()
		button.text = _humanize_decision(str(decision_name))
		button.pressed.connect(_on_decision_pressed.bind(str(decision_name)))
		_decision_buttons.add_child(button)

func _load_job_controls() -> void:
	var attempt_data: Dictionary = _selected_attempt()
	var job_metadata: Dictionary = _as_dictionary(attempt_data.get("job_metadata", {}))
	_job_provider_input.text = str(job_metadata.get("provider", ""))
	_job_task_input.text = str(job_metadata.get("task_type", ""))
	_job_id_input.text = str(job_metadata.get("job_id", ""))
	_job_idempotency_input.text = str(job_metadata.get("idempotency_key", ""))
	_job_status_input.text = str(job_metadata.get("status", ""))
	_job_error_input.text = str(job_metadata.get("error_message", ""))
	_job_request_view.text = JSON.stringify(_as_dictionary(job_metadata.get("request_payload", {})), "\t")
	_job_response_view.text = JSON.stringify(_as_dictionary(job_metadata.get("response_payload", {})), "\t")
	_job_output_urls_view.text = JSON.stringify(_as_array(job_metadata.get("output_urls", [])), "\t")
	_job_downloaded_paths_view.text = JSON.stringify(_as_array(job_metadata.get("downloaded_paths", [])), "\t")

func _load_import_recipe_controls() -> void:
	var import_recipe: Dictionary = _as_dictionary(_selected_run.get("import_recipe", {}))
	_import_recipe_view.text = JSON.stringify(import_recipe, "\t") if not import_recipe.is_empty() else JSON.stringify({}, "\t")

func _load_artifact_controls() -> void:
	var artifact_data: Dictionary = _selected_artifact()
	_artifact_type_input.text = str(artifact_data.get("artifact_type", ""))
	_artifact_name_input.text = str(artifact_data.get("display_name", ""))
	_artifact_storage_input.text = str(artifact_data.get("storage_uri", ""))
	_artifact_preview_input.text = str(artifact_data.get("preview_uri", ""))
	_artifact_metadata_view.text = JSON.stringify(_as_dictionary(artifact_data.get("metadata", {})), "\t")
	_artifact_selected_check.button_pressed = bool(artifact_data.get("is_selected", false))
	_artifact_publish_check.button_pressed = bool(artifact_data.get("is_publish_candidate", false))

func _update_action_button_state() -> void:
	var has_artifact: bool = not _selected_artifact().is_empty()
	_artifact_select_button.disabled = not has_artifact
	_artifact_publish_button.disabled = not has_artifact
	_artifact_delete_button.disabled = not has_artifact
	_publish_button.disabled = _selected_run.is_empty()
	_delete_run_button.disabled = _selected_run_id.is_empty()

func _format_run_summary(run_data: Dictionary) -> String:
	if run_data.is_empty():
		return "Select or create a workflow run."

	return "\n".join([
		"Run: %s" % str(run_data.get("display_name", run_data.get("run_id", ""))),
		"Slug: %s" % str(run_data.get("asset_slug", "")),
		"Template: %s" % str(run_data.get("template_name", run_data.get("template_id", ""))),
		"Active nodes: %s" % _join_values(_as_array(run_data.get("active_node_ids", [])), ", "),
		"Attempts: %d" % _as_dictionary(run_data.get("attempts", {})).size(),
		"Artifacts: %d" % _as_dictionary(run_data.get("artifacts", {})).size(),
		"Selected artifacts: %s" % _join_values(_as_array(run_data.get("selected_artifact_ids", [])), ", "),
		"Review requests: %d" % _as_array(run_data.get("current_review_requests", [])).size(),
	])

func _format_attempt(attempt_data: Dictionary) -> String:
	if attempt_data.is_empty():
		return "Select a step attempt."

	var notes: Array = []
	for note_data in _as_array(attempt_data.get("review_notes", [])):
		var note_dict: Dictionary = _as_dictionary(note_data)
		notes.append("%s: %s" % [
			str(note_dict.get("decision", "")),
			str(note_dict.get("note", "")),
		])

	return "\n".join([
		"Step: %s" % str(attempt_data.get("step_label", "")),
		"Type: %s" % str(attempt_data.get("step_type", "")),
		"State: %s" % str(attempt_data.get("state", "idle")),
		"Consumes: %s" % _join_values(_as_array(attempt_data.get("consumes", [])), ", "),
		"Produces: %s" % _join_values(_as_array(attempt_data.get("produces", [])), ", "),
		"Inputs: %s" % _join_values(_as_array(attempt_data.get("inputs", [])), ", "),
		"Outputs: %s" % _join_values(_as_array(attempt_data.get("output_artifact_ids", [])), ", "),
		"Last decision: %s" % str(attempt_data.get("last_decision", "(none)")),
		"Description: %s" % str(attempt_data.get("description", "")),
		"Notes: %s" % _join_values(notes, "; "),
	])

func _format_artifact(artifact_data: Dictionary) -> String:
	if artifact_data.is_empty():
		return "Select an artifact."

	return "\n".join([
		"Artifact: %s" % str(artifact_data.get("display_name", artifact_data.get("artifact_id", ""))),
		"Type: %s" % str(artifact_data.get("artifact_type", "")),
		"Selected: %s" % str(artifact_data.get("is_selected", false)),
		"Publish candidate: %s" % str(artifact_data.get("is_publish_candidate", false)),
		"Source attempt: %s" % str(artifact_data.get("source_attempt_id", "")),
		"Storage: %s" % str(artifact_data.get("storage_uri", "")),
		"Preview: %s" % str(artifact_data.get("preview_uri", "")),
	])

func _format_validation_report(report: Array) -> String:
	if report.is_empty():
		return "No validation data available."
	var lines: Array = []
	for item_data in report:
		var item_dict: Dictionary = _as_dictionary(item_data)
		lines.append("%s %s - %s" % [
			"PASS" if bool(item_dict.get("ok", false)) else "FAIL",
			str(item_dict.get("id", "")),
			str(item_dict.get("detail", "")),
		])
	return "\n".join(lines)

func _humanize_decision(decision: String) -> String:
	return decision.replace("_", " ").capitalize()

func _on_template_selected(index: int) -> void:
	if index < 0 or index >= _template_ids.size():
		return
	_selected_template_id = str(_template_ids[index])
	_load_selected_template()
	_status_label.text = "Selected template %s." % _selected_template_id

func _on_run_selected(index: int) -> void:
	if index < 0 or index >= _run_ids.size():
		return
	_selected_run_id = str(_run_ids[index])
	_selected_attempt_id = ""
	_selected_artifact_id = ""
	_load_selected_run()
	_refresh_revision_list()
	_refresh_attempt_list()
	_refresh_artifact_list()
	_refresh_detail_panels()
	_refresh_output_tabs()
	_status_label.text = "Loaded run %s." % _selected_run_id

func _on_attempt_selected(index: int) -> void:
	if index < 0 or index >= _attempt_ids.size():
		return
	_selected_attempt_id = str(_attempt_ids[index])
	_refresh_detail_panels()

func _on_artifact_selected(index: int) -> void:
	if index < 0 or index >= _artifact_ids.size():
		return
	_selected_artifact_id = str(_artifact_ids[index])
	_refresh_detail_panels()

func _on_new_template_pressed() -> void:
	var stub: Dictionary = _new_template_stub()
	_selected_template = stub
	_selected_template_id = str(stub.get("template_id", ""))
	_template_json_view.text = JSON.stringify(stub, "\t")
	_status_label.text = "Loaded new template stub."

func _on_save_template_pressed() -> void:
	if _plugin == null:
		return
	var template_result: Dictionary = _parse_json_object_result(_template_json_view.text, "Template JSON")
	if not bool(template_result.get("ok", false)):
		return
	var template_payload: Dictionary = _as_dictionary(template_result.get("value", {}))
	var response: Dictionary = _plugin.call("upsert_workflow_template", template_payload)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	var template_summary: Dictionary = _as_dictionary(response.get("template_summary", {}))
	_selected_template_id = str(template_summary.get("template_id", _selected_template_id))
	_status_label.text = "Saved template %s." % _selected_template_id
	refresh_from_plugin()

func _on_delete_template_pressed() -> void:
	if _plugin == null or _selected_template_id.is_empty():
		return
	var response: Dictionary = _plugin.call("delete_workflow_template", _selected_template_id)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_selected_template_id = ""
	_status_label.text = "Deleted template."
	refresh_from_plugin()

func _on_create_run_pressed() -> void:
	if _plugin == null:
		return
	if _selected_template_id.is_empty():
		_status_label.text = "Select a template first."
		return
	var response: Dictionary = _plugin.call(
		"create_workflow_run",
		_selected_template_id,
		_asset_slug_input.text,
		_display_name_input.text
	)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	var run_data: Dictionary = _as_dictionary(response.get("run", {}))
	_selected_run_id = str(run_data.get("run_id", ""))
	_selected_attempt_id = ""
	_selected_artifact_id = ""
	_asset_slug_input.text = ""
	_display_name_input.text = ""
	_status_label.text = "Created run %s." % _selected_run_id
	refresh_from_plugin()

func _on_delete_run_pressed() -> void:
	if _plugin == null or _selected_run_id.is_empty():
		return
	var response: Dictionary = _plugin.call("delete_workflow_run", _selected_run_id)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_selected_run_id = ""
	_selected_attempt_id = ""
	_selected_artifact_id = ""
	_status_label.text = "Deleted run."
	refresh_from_plugin()

func _on_decision_pressed(decision: String) -> void:
	if _plugin == null or _selected_run_id.is_empty() or _selected_attempt_id.is_empty():
		return
	var response: Dictionary = _plugin.call(
		"apply_workflow_decision",
		_selected_run_id,
		_selected_attempt_id,
		decision,
		""
	)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_status_label.text = "Applied %s to %s." % [decision, _selected_attempt_id]
	refresh_from_plugin()

func _on_save_job_request_pressed() -> void:
	if _plugin == null or _selected_run_id.is_empty() or _selected_attempt_id.is_empty():
		return
	var request_result: Dictionary = _parse_json_object_result(_job_request_view.text, "Job request")
	if not bool(request_result.get("ok", false)):
		return
	var request_payload: Dictionary = _as_dictionary(request_result.get("value", {}))
	var response: Dictionary = _plugin.call(
		"set_workflow_attempt_job",
		_selected_run_id,
		_selected_attempt_id,
		_job_provider_input.text,
		_job_task_input.text,
		request_payload,
		_job_id_input.text,
		_job_idempotency_input.text,
		""
	)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_status_label.text = "Saved job request."
	refresh_from_plugin()

func _on_save_job_status_pressed() -> void:
	if _plugin == null or _selected_run_id.is_empty() or _selected_attempt_id.is_empty():
		return
	var response_result: Dictionary = _parse_json_object_result(_job_response_view.text, "Job response")
	if not bool(response_result.get("ok", false)):
		return
	var response_payload: Dictionary = _as_dictionary(response_result.get("value", {}))
	var output_urls_result: Dictionary = _parse_json_array_result(_job_output_urls_view.text, "Job output urls")
	if not bool(output_urls_result.get("ok", false)):
		return
	var output_urls: Array = _as_array(output_urls_result.get("value", []))
	var downloaded_paths_result: Dictionary = _parse_json_array_result(_job_downloaded_paths_view.text, "Downloaded paths")
	if not bool(downloaded_paths_result.get("ok", false)):
		return
	var downloaded_paths: Array = _as_array(downloaded_paths_result.get("value", []))
	var response: Dictionary = _plugin.call(
		"set_workflow_attempt_job_status",
		_selected_run_id,
		_selected_attempt_id,
		_job_status_input.text,
		_job_id_input.text,
		response_payload,
		output_urls,
		downloaded_paths,
		_job_error_input.text
	)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_status_label.text = "Saved job status."
	refresh_from_plugin()

func _on_save_import_recipe_pressed() -> void:
	if _plugin == null or _selected_run_id.is_empty():
		return
	var import_recipe_result: Dictionary = _parse_json_object_result(_import_recipe_view.text, "Import recipe")
	if not bool(import_recipe_result.get("ok", false)):
		return
	var import_recipe: Dictionary = _as_dictionary(import_recipe_result.get("value", {}))
	var response: Dictionary = _plugin.call("set_workflow_import_recipe", _selected_run_id, import_recipe)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_status_label.text = "Saved import recipe."
	refresh_from_plugin()

func _on_toggle_selected_pressed() -> void:
	var artifact_data: Dictionary = _selected_artifact()
	if artifact_data.is_empty() or _plugin == null:
		return
	var response: Dictionary = _plugin.call(
		"set_workflow_artifact_selected",
		_selected_run_id,
		_selected_artifact_id,
		not bool(artifact_data.get("is_selected", false))
	)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_status_label.text = "Updated artifact selection."
	refresh_from_plugin()

func _on_toggle_publish_candidate_pressed() -> void:
	var artifact_data: Dictionary = _selected_artifact()
	if artifact_data.is_empty() or _plugin == null:
		return
	var response: Dictionary = _plugin.call(
		"set_workflow_artifact_publish_candidate",
		_selected_run_id,
		_selected_artifact_id,
		not bool(artifact_data.get("is_publish_candidate", false))
	)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_status_label.text = "Updated publish candidate state."
	refresh_from_plugin()

func _on_delete_artifact_pressed() -> void:
	if _plugin == null or _selected_run_id.is_empty() or _selected_artifact_id.is_empty():
		return
	var response: Dictionary = _plugin.call("delete_workflow_artifact", _selected_run_id, _selected_artifact_id)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_selected_artifact_id = ""
	_status_label.text = "Deleted artifact."
	refresh_from_plugin()

func _on_register_artifact_pressed() -> void:
	if _plugin == null or _selected_run_id.is_empty():
		return
	var metadata_result: Dictionary = _parse_json_object_result(_artifact_metadata_view.text, "Artifact metadata")
	if not bool(metadata_result.get("ok", false)):
		return
	var metadata: Dictionary = _as_dictionary(metadata_result.get("value", {}))
	var response: Dictionary = _plugin.call(
		"register_workflow_artifact",
		_selected_run_id,
		_selected_attempt_id,
		_artifact_type_input.text,
		_artifact_name_input.text,
		_artifact_storage_input.text,
		_artifact_preview_input.text,
		metadata,
		_artifact_selected_check.button_pressed,
		_artifact_publish_check.button_pressed,
		_selected_artifact_id
	)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	var artifact_data: Dictionary = _as_dictionary(response.get("artifact", {}))
	_selected_artifact_id = str(artifact_data.get("artifact_id", _selected_artifact_id))
	_status_label.text = "Registered artifact %s." % _selected_artifact_id
	refresh_from_plugin()

func _on_publish_pressed() -> void:
	if _plugin == null or _selected_run_id.is_empty():
		return
	var response: Dictionary = _plugin.call(
		"publish_workflow_revision",
		_selected_run_id,
		_publish_version_input.text,
		_publish_notes_input.text
	)
	if not bool(response.get("ok", false)):
		_status_label.text = _error_message(response)
		return
	_publish_version_input.text = ""
	_publish_notes_input.text = ""
	_status_label.text = "Published revision for %s." % _selected_run_id
	refresh_from_plugin()

func _parse_json_object_result(text: String, label: String) -> Dictionary:
	var cleaned: String = text.strip_edges()
	if cleaned.is_empty():
		return {"ok": true, "value": {}}
	var parsed: Variant = JSON.parse_string(cleaned)
	if typeof(parsed) != TYPE_DICTIONARY:
		_status_label.text = "%s must be a JSON object." % label
		return {"ok": false, "value": {}}
	return {"ok": true, "value": parsed}

func _parse_json_array_result(text: String, label: String) -> Dictionary:
	var cleaned: String = text.strip_edges()
	if cleaned.is_empty():
		return {"ok": true, "value": []}
	var parsed: Variant = JSON.parse_string(cleaned)
	if typeof(parsed) != TYPE_ARRAY:
		_status_label.text = "%s must be a JSON array." % label
		return {"ok": false, "value": []}
	return {"ok": true, "value": parsed}

func _new_template_stub() -> Dictionary:
	return {
		"template_id": "new_template",
		"name": "New Template",
		"asset_type": "generic",
		"version": 1,
		"required_artifact_types": ["ConceptDoc", "AssetRevisionManifest"],
		"publish_node_ids": ["publish_revision"],
		"nodes": [
			{
				"id": "brief",
				"label": "Brief",
				"kind": "input",
				"entry": true,
				"description": "Capture the initial asset brief.",
				"produces": ["ConceptDoc"],
				"decisions": ["approve"],
			},
			{
				"id": "publish_revision",
				"label": "Publish Revision",
				"kind": "publish",
				"description": "Publish the approved artifact manifest.",
				"consumes": ["ConceptDoc"],
				"produces": ["AssetRevisionManifest"],
				"decisions": ["publish"],
			},
		],
		"edges": [
			{"from": "brief", "decision": "approve", "to": "publish_revision"},
		],
	}

func _error_message(response: Dictionary) -> String:
	var error_dict: Dictionary = _as_dictionary(response.get("error", {}))
	return "%s: %s" % [
		str(error_dict.get("code", "error")),
		str(error_dict.get("message", "Operation failed.")),
	]

func _join_values(values: Array, separator: String) -> String:
	var rendered: Array = []
	for value in values:
		rendered.append(str(value))
	return separator.join(rendered)

func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []

func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}
