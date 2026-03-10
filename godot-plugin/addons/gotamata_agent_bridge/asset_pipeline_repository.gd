@tool
extends RefCounted
class_name AssetPipelineRepository

const TEMPLATE_DIR := "res://workflows/templates"
const RUN_DIR := "res://workflows/runs"
const GENERATED_DIR := "res://assets/generated"
const SCRATCH_DIR := "res://_ai_work"

const ACTIVE_STATES := {
	"idle": true,
	"queued": true,
	"running": true,
	"needs_review": true,
}

const TERMINAL_STATES := {
	"approved": true,
	"rejected": true,
	"failed": true,
	"skipped": true,
}

const REPEATABLE_DECISIONS := {
	"branch_new_attempt": true,
	"more_variants": true,
	"regenerate_from_same_reference": true,
}

const DECISION_TO_STATE := {
	"queue": "queued",
	"run": "running",
	"needs_review": "needs_review",
	"approve": "approved",
	"approve_one": "approved",
	"approve_many": "approved",
	"promote_to_reference": "approved",
	"publish": "approved",
	"complete": "approved",
	"skip": "skipped",
	"reject": "rejected",
	"request_changes": "rejected",
	"send_back_to_prompt": "rejected",
	"send_back_to_previous_stage": "rejected",
	"archive_candidate": "rejected",
	"back_to_concept": "rejected",
	"more_variants": "approved",
	"regenerate_from_same_reference": "approved",
	"branch_new_attempt": "approved",
}

const JOB_STATUS_TO_STATE := {
	"queued": "queued",
	"running": "running",
	"needs_review": "needs_review",
	"completed": "approved",
	"succeeded": "approved",
	"approved": "approved",
	"failed": "failed",
	"rejected": "rejected",
	"skipped": "skipped",
}

var _id_counter: int = 1

func initialize() -> Dictionary:
	_ensure_directory(TEMPLATE_DIR)
	_ensure_directory(RUN_DIR)
	_ensure_directory(GENERATED_DIR)
	_ensure_directory(SCRATCH_DIR)
	_seed_default_templates()
	return get_overview()

func get_overview() -> Dictionary:
	var templates: Array = list_templates()
	var runs: Array = list_runs()
	var revision_count: int = 0
	for run_summary in runs:
		revision_count += int(run_summary.get("revision_count", 0))
	return {
		"template_count": templates.size(),
		"run_count": runs.size(),
		"revision_count": revision_count,
		"template_dir": TEMPLATE_DIR,
		"run_dir": RUN_DIR,
		"generated_dir": GENERATED_DIR,
		"scratch_dir": SCRATCH_DIR,
	}

func list_templates() -> Array:
	var templates: Array = []
	for file_name in _list_json_files(TEMPLATE_DIR):
		var template_data: Dictionary = _read_json_file("%s/%s" % [TEMPLATE_DIR, file_name])
		if template_data.is_empty():
			continue
		templates.append(_build_template_summary(template_data))
	return templates

func get_template(template_id: String) -> Dictionary:
	if template_id.strip_edges().is_empty():
		return {}
	var direct_path: String = _template_path(template_id)
	if FileAccess.file_exists(direct_path):
		return _read_json_file(direct_path)
	for file_name in _list_json_files(TEMPLATE_DIR):
		var template_data: Dictionary = _read_json_file("%s/%s" % [TEMPLATE_DIR, file_name])
		if str(template_data.get("template_id", "")) == template_id:
			return template_data
	return {}

func upsert_template(template_data: Dictionary) -> Dictionary:
	var normalized_template: Dictionary = _normalize_template(template_data)
	if normalized_template.is_empty():
		return _error("invalid_template", "Template payload must be a JSON object.")

	var validation_error: Dictionary = _validate_template(normalized_template)
	if not validation_error.is_empty():
		return validation_error

	var template_id: String = str(normalized_template.get("template_id", ""))
	var write_error: int = _write_json_file(_template_path(template_id), normalized_template)
	if write_error != OK:
		return _error("template_write_failed", "Failed to write workflow template.", {
			"template_id": template_id,
			"error_code": write_error,
			"error_name": error_string(write_error),
		})

	return _success({
		"template": normalized_template,
		"template_summary": _build_template_summary(normalized_template),
	})

func delete_template(template_id: String) -> Dictionary:
	var cleaned_template_id: String = template_id.strip_edges()
	if cleaned_template_id.is_empty():
		return _error("missing_template_id", "Template id is required.")

	var template_path: String = _template_path(cleaned_template_id)
	if not FileAccess.file_exists(template_path):
		return _error("template_not_found", "Workflow template does not exist.", {
			"template_id": cleaned_template_id,
		})

	if _template_referenced_by_any_run(cleaned_template_id):
		return _error("template_in_use", "Cannot delete a template that is referenced by an existing workflow run.", {
			"template_id": cleaned_template_id,
		})

	var remove_error: int = _remove_file(template_path)
	if remove_error != OK:
		return _error("template_delete_failed", "Failed to delete workflow template.", {
			"template_id": cleaned_template_id,
			"error_code": remove_error,
			"error_name": error_string(remove_error),
		})

	return _success({"template_id": cleaned_template_id})

func list_runs() -> Array:
	var runs: Array = []
	for file_name in _list_json_files(RUN_DIR):
		var run_data: Dictionary = _read_json_file("%s/%s" % [RUN_DIR, file_name])
		if run_data.is_empty():
			continue
		runs.append(_build_run_summary(run_data))
	return runs

func get_run(run_id: String) -> Dictionary:
	var cleaned_run_id: String = run_id.strip_edges()
	if cleaned_run_id.is_empty():
		return {}
	var run_path: String = _run_path(cleaned_run_id)
	if not FileAccess.file_exists(run_path):
		return {}
	return _read_json_file(run_path)

func create_run(template_id: String, asset_slug: String, display_name: String = "") -> Dictionary:
	var template_data: Dictionary = get_template(template_id)
	if template_data.is_empty():
		return _error("missing_template", "Unknown workflow template.", {"template_id": template_id})

	var slug: String = _slugify(asset_slug)
	if slug.is_empty():
		return _error("invalid_asset_slug", "Asset slug must contain at least one letter or number.")

	var now: int = _now()
	var run_id: String = _make_id(slug)
	var resolved_display_name: String = display_name.strip_edges()
	if resolved_display_name.is_empty():
		resolved_display_name = slug.replace("-", " ").capitalize()

	var run_data: Dictionary = {
		"schema_version": 1,
		"run_id": run_id,
		"template_id": str(template_data.get("template_id", template_id)),
		"template_name": str(template_data.get("name", "Untitled Template")),
		"template_version": int(template_data.get("version", 1)),
		"asset_slug": slug,
		"display_name": resolved_display_name,
		"created_at": now,
		"updated_at": now,
		"active_node_ids": [],
		"attempts": {},
		"artifacts": {},
		"selected_artifact_ids": [],
		"current_review_requests": [],
		"revisions": [],
		"logs": [],
		"validation_report": [],
		"import_recipe": _default_import_recipe(slug),
	}

	var entry_nodes: Array = _find_entry_nodes(template_data)
	if entry_nodes.is_empty():
		return _error("template_has_no_entry", "Template does not define an entry node.", {
			"template_id": template_id,
		})

	for node_data in entry_nodes:
		var attempt_data: Dictionary = _new_attempt(run_id, node_data, [], "", "")
		_add_attempt_to_run(run_data, attempt_data)

	_append_log(run_data, "Created workflow run from %s." % str(run_data.get("template_name", "template")))
	_recompute_active_nodes(run_data)
	_update_validation(run_data)
	_save_run(run_data)
	return _success({"run": run_data})

func delete_run(run_id: String) -> Dictionary:
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})

	var scratch_paths: Array = _collect_run_scratch_paths(run_data)
	var remove_error: int = _remove_file(_run_path(run_id))
	if remove_error != OK:
		return _error("run_delete_failed", "Failed to delete workflow run.", {
			"run_id": run_id,
			"error_code": remove_error,
			"error_name": error_string(remove_error),
		})

	for scratch_path in scratch_paths:
		if FileAccess.file_exists(str(scratch_path)):
			_remove_file(str(scratch_path))

	return _success({"run_id": run_id})

func apply_decision(run_id: String, attempt_id: String, decision: String, note: String = "") -> Dictionary:
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})

	var attempt_data: Dictionary = _get_attempt(run_data, attempt_id)
	if attempt_data.is_empty():
		return _error("attempt_not_found", "Step attempt does not exist.", {
			"run_id": run_id,
			"attempt_id": attempt_id,
		})

	var cleaned_decision: String = decision.strip_edges()
	if cleaned_decision.is_empty():
		return _error("missing_decision", "A workflow decision is required.")

	var available_decisions: Array = _as_string_array(attempt_data.get("available_decisions", []))
	if not available_decisions.is_empty() and not available_decisions.has(cleaned_decision):
		return _error("invalid_decision", "Decision is not allowed for this step.", {
			"attempt_id": attempt_id,
			"decision": cleaned_decision,
			"available_decisions": available_decisions,
		})

	var applied_decisions: Array = _as_string_array(attempt_data.get("applied_decisions", []))
	if applied_decisions.has(cleaned_decision) and not REPEATABLE_DECISIONS.has(cleaned_decision):
		return _error("duplicate_decision", "This decision was already applied to the selected attempt.", {
			"attempt_id": attempt_id,
			"decision": cleaned_decision,
		})
	applied_decisions.append(cleaned_decision)
	attempt_data["applied_decisions"] = applied_decisions
	attempt_data["last_decision"] = cleaned_decision
	attempt_data["state"] = _decision_state(cleaned_decision)
	attempt_data["updated_at"] = _now()
	attempt_data["job_metadata"] = _update_job_metadata_status(
		_as_dictionary(attempt_data.get("job_metadata", {})),
		str(attempt_data.get("state", "idle")),
	)

	var review_notes: Array = _as_array(attempt_data.get("review_notes", []))
	if not note.strip_edges().is_empty():
		review_notes.append({
			"decision": cleaned_decision,
			"note": note.strip_edges(),
			"created_at": _now(),
		})
	attempt_data["review_notes"] = review_notes
	_set_attempt(run_data, attempt_id, attempt_data)
	_update_review_request_state(run_data, attempt_id, str(attempt_data.get("state", "idle")))

	var template_data: Dictionary = get_template(str(run_data.get("template_id", "")))
	var node_data: Dictionary = _get_template_node(template_data, str(attempt_data.get("step_id", "")))

	if _decision_creates_outputs(cleaned_decision):
		_ensure_attempt_outputs(run_data, attempt_id, node_data, cleaned_decision)
		attempt_data = _get_attempt(run_data, attempt_id)

	if cleaned_decision in ["approve_one", "approve_many", "promote_to_reference"]:
		_mark_attempt_outputs_selected(run_data, attempt_id, true)
		_mark_attempt_outputs_publish_candidate(run_data, attempt_id, true)
	elif cleaned_decision == "archive_candidate":
		_mark_attempt_outputs_publish_candidate(run_data, attempt_id, false)

	if cleaned_decision == "branch_new_attempt":
		_spawn_sibling_attempt(run_data, attempt_data, node_data)

	_activate_downstream_attempts(run_data, template_data, attempt_data, cleaned_decision)
	_append_log(run_data, "%s -> %s" % [str(attempt_data.get("step_label", "Step")), cleaned_decision])
	run_data["updated_at"] = _now()
	_recompute_active_nodes(run_data)
	_update_validation(run_data)
	_save_run(run_data)
	return _success({"run": run_data})

func set_import_recipe(run_id: String, import_recipe: Dictionary) -> Dictionary:
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})

	run_data["import_recipe"] = _normalize_import_recipe(import_recipe, str(run_data.get("asset_slug", "asset")))
	run_data["updated_at"] = _now()
	_append_log(run_data, "Updated import recipe.")
	_update_validation(run_data)
	_save_run(run_data)
	return _success({"run": run_data})

func set_attempt_job(
	run_id: String,
	attempt_id: String,
	provider: String,
	task_type: String,
	request_payload: Dictionary,
	job_id: String = "",
	idempotency_key: String = "",
	note: String = ""
) -> Dictionary:
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})

	var attempt_data: Dictionary = _get_attempt(run_data, attempt_id)
	if attempt_data.is_empty():
		return _error("attempt_not_found", "Step attempt does not exist.", {
			"run_id": run_id,
			"attempt_id": attempt_id,
		})

	var job_metadata: Dictionary = _as_dictionary(attempt_data.get("job_metadata", {}))
	job_metadata["provider"] = provider.strip_edges()
	job_metadata["task_type"] = task_type.strip_edges()
	job_metadata["request_payload"] = request_payload
	job_metadata["job_id"] = job_id.strip_edges()
	job_metadata["idempotency_key"] = idempotency_key.strip_edges()
	job_metadata["last_synced_at"] = _now()
	job_metadata["status"] = "queued"
	attempt_data["job_metadata"] = job_metadata
	attempt_data["state"] = "queued"
	attempt_data["updated_at"] = _now()

	var review_notes: Array = _as_array(attempt_data.get("review_notes", []))
	if not note.strip_edges().is_empty():
		review_notes.append({
			"decision": "job_request",
			"note": note.strip_edges(),
			"created_at": _now(),
		})
	attempt_data["review_notes"] = review_notes

	_set_attempt(run_data, attempt_id, attempt_data)
	_update_review_request_state(run_data, attempt_id, "queued")
	run_data["updated_at"] = _now()
	_append_log(run_data, "Updated job request for %s." % str(attempt_data.get("step_label", "step")))
	_recompute_active_nodes(run_data)
	_update_validation(run_data)
	_save_run(run_data)
	return _success({"run": run_data, "attempt": attempt_data})

func set_attempt_job_status(
	run_id: String,
	attempt_id: String,
	status: String,
	job_id: String = "",
	response_payload: Dictionary = {},
	output_urls: Array = [],
	downloaded_paths: Array = [],
	error_message: String = ""
) -> Dictionary:
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})

	var attempt_data: Dictionary = _get_attempt(run_data, attempt_id)
	if attempt_data.is_empty():
		return _error("attempt_not_found", "Step attempt does not exist.", {
			"run_id": run_id,
			"attempt_id": attempt_id,
		})

	var cleaned_status: String = status.strip_edges().to_lower()
	if cleaned_status.is_empty():
		return _error("missing_status", "Job status is required.")

	var job_metadata: Dictionary = _as_dictionary(attempt_data.get("job_metadata", {}))
	if not job_id.strip_edges().is_empty():
		job_metadata["job_id"] = job_id.strip_edges()
	job_metadata["status"] = cleaned_status
	job_metadata["response_payload"] = response_payload
	job_metadata["output_urls"] = _stringify_array(output_urls)
	job_metadata["downloaded_paths"] = _stringify_array(downloaded_paths)
	job_metadata["error_message"] = error_message.strip_edges()
	job_metadata["last_synced_at"] = _now()
	attempt_data["job_metadata"] = job_metadata
	attempt_data["updated_at"] = _now()
	if JOB_STATUS_TO_STATE.has(cleaned_status):
		attempt_data["state"] = str(JOB_STATUS_TO_STATE.get(cleaned_status, "running"))

	_set_attempt(run_data, attempt_id, attempt_data)
	_update_review_request_state(run_data, attempt_id, str(attempt_data.get("state", "idle")))
	run_data["updated_at"] = _now()
	_append_log(run_data, "Updated job status for %s to %s." % [
		str(attempt_data.get("step_label", "step")),
		cleaned_status,
	])
	_recompute_active_nodes(run_data)
	_update_validation(run_data)
	_save_run(run_data)
	return _success({"run": run_data, "attempt": attempt_data})

func register_artifact(
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
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})

	var cleaned_attempt_id: String = attempt_id.strip_edges()
	if not cleaned_attempt_id.is_empty() and _get_attempt(run_data, cleaned_attempt_id).is_empty():
		return _error("attempt_not_found", "Step attempt does not exist.", {
			"run_id": run_id,
			"attempt_id": cleaned_attempt_id,
		})

	var cleaned_artifact_type: String = artifact_type.strip_edges()
	if cleaned_artifact_type.is_empty():
		return _error("missing_artifact_type", "Artifact type is required.")

	var artifact_data: Dictionary = _register_artifact_on_run(
		run_data,
		cleaned_attempt_id,
		cleaned_artifact_type,
		display_name,
		storage_uri,
		preview_uri,
		metadata,
		selected,
		publish_candidate,
		artifact_id
	)

	run_data["updated_at"] = _now()
	_append_log(run_data, "Registered artifact %s." % str(artifact_data.get("artifact_id", "")))
	_update_validation(run_data)
	_save_run(run_data)
	return _success({"run": run_data, "artifact": artifact_data})

func delete_artifact(run_id: String, artifact_id: String) -> Dictionary:
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})

	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	if not artifacts.has(artifact_id):
		return _error("artifact_not_found", "Artifact does not exist.", {
			"run_id": run_id,
			"artifact_id": artifact_id,
		})

	var artifact_data: Dictionary = _as_dictionary(artifacts.get(artifact_id, {}))
	artifacts.erase(artifact_id)
	run_data["artifacts"] = artifacts
	_remove_artifact_from_attempts(run_data, artifact_id)
	_remove_artifact_references(run_data, artifact_id)

	var storage_uri: String = str(artifact_data.get("storage_uri", ""))
	if storage_uri.begins_with("%s/" % SCRATCH_DIR) and FileAccess.file_exists(storage_uri):
		_remove_file(storage_uri)

	run_data["updated_at"] = _now()
	_append_log(run_data, "Deleted artifact %s." % artifact_id)
	_update_validation(run_data)
	_save_run(run_data)
	return _success({"run": run_data, "artifact_id": artifact_id})

func set_artifact_selected(run_id: String, artifact_id: String, selected: bool) -> Dictionary:
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})

	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	if not artifacts.has(artifact_id):
		return _error("artifact_not_found", "Artifact does not exist.", {
			"run_id": run_id,
			"artifact_id": artifact_id,
		})

	_mark_artifact_selected_on_run(run_data, artifact_id, selected)
	run_data["updated_at"] = _now()
	_append_log(run_data, "%s artifact %s." % ["Selected" if selected else "Unselected", artifact_id])
	_update_validation(run_data)
	_save_run(run_data)
	return _success({"run": run_data, "artifact": _as_dictionary(run_data.get("artifacts", {})).get(artifact_id, {})})

func set_artifact_publish_candidate(run_id: String, artifact_id: String, publish_candidate: bool) -> Dictionary:
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})

	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	if not artifacts.has(artifact_id):
		return _error("artifact_not_found", "Artifact does not exist.", {
			"run_id": run_id,
			"artifact_id": artifact_id,
		})

	_mark_artifact_publish_candidate_on_run(run_data, artifact_id, publish_candidate)
	run_data["updated_at"] = _now()
	_append_log(run_data, "%s publish candidate %s." % [
		"Enabled" if publish_candidate else "Disabled",
		artifact_id,
	])
	_update_validation(run_data)
	_save_run(run_data)
	return _success({"run": run_data, "artifact": _as_dictionary(run_data.get("artifacts", {})).get(artifact_id, {})})

func publish_revision(run_id: String, version_label: String = "", notes: String = "") -> Dictionary:
	var run_data: Dictionary = get_run(run_id)
	if run_data.is_empty():
		return _error("run_not_found", "Workflow run does not exist.", {"run_id": run_id})
	return _publish_loaded_run(run_data, version_label, notes)

func _publish_loaded_run(run_data: Dictionary, version_label: String, notes: String) -> Dictionary:
	_update_validation(run_data)
	if not _validation_passes(_as_array(run_data.get("validation_report", []))):
		return _error("validation_failed", "Publish is blocked until required validation checks pass.", {
			"run": run_data,
			"validation_report": _as_array(run_data.get("validation_report", [])),
		})

	var selected_ids: Array = _as_string_array(run_data.get("selected_artifact_ids", []))
	if selected_ids.is_empty():
		selected_ids = _publish_candidate_artifact_ids(run_data)
	if selected_ids.is_empty():
		return _error("missing_publish_artifacts", "Publish requires at least one selected or publish-candidate artifact.", {
			"run": run_data,
		})

	var revisions: Array = _as_array(run_data.get("revisions", []))
	var next_revision_index: int = revisions.size() + 1
	var resolved_version: String = version_label.strip_edges()
	if resolved_version.is_empty():
		resolved_version = "v%d.0.0" % next_revision_index

	var superseded_revision: String = ""
	for index in revisions.size():
		var revision_data: Dictionary = _as_dictionary(revisions[index])
		if str(revision_data.get("release_state", "")) == "published":
			superseded_revision = str(revision_data.get("revision", ""))
			revision_data["release_state"] = "superseded"
			revisions[index] = revision_data

	var manifest_path: String = "%s/%s/%s/manifest/asset_revision.json" % [
		GENERATED_DIR,
		str(run_data.get("asset_slug", "asset")),
		resolved_version,
	]
	var import_recipe: Dictionary = _as_dictionary(run_data.get("import_recipe", {}))
	var revision_manifest: Dictionary = {
		"asset_id": str(run_data.get("asset_slug", "")),
		"revision": resolved_version,
		"release_state": "published",
		"canonical_artifact_ids": selected_ids,
		"import_recipe_id": str(import_recipe.get("recipe_id", "local_default")),
		"published_at": _now(),
		"supersedes_revision": superseded_revision,
		"notes": notes.strip_edges(),
		"run_id": str(run_data.get("run_id", "")),
		"template_id": str(run_data.get("template_id", "")),
		"manifest_path": manifest_path,
	}

	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	var manifest_payload: Dictionary = revision_manifest.duplicate(true)
	manifest_payload["display_name"] = str(run_data.get("display_name", ""))
	manifest_payload["artifacts"] = []
	manifest_payload["validation_report"] = _as_array(run_data.get("validation_report", []))
	manifest_payload["import_recipe"] = import_recipe
	for artifact_id in selected_ids:
		if artifacts.has(artifact_id):
			manifest_payload["artifacts"].append(_as_dictionary(artifacts.get(artifact_id, {})))

	var write_error: int = _write_json_file(manifest_path, manifest_payload)
	if write_error != OK:
		return _error("publish_write_failed", "Failed to write asset revision manifest.", {
			"manifest_path": manifest_path,
			"error_code": write_error,
			"error_name": error_string(write_error),
		})

	revisions.append(revision_manifest)
	run_data["revisions"] = revisions
	run_data["updated_at"] = _now()
	_append_log(run_data, "Published %s to %s." % [resolved_version, manifest_path])
	_update_validation(run_data)
	_save_run(run_data)
	return _success({
		"run": run_data,
		"revision": revision_manifest,
	})

func _build_template_summary(template_data: Dictionary) -> Dictionary:
	return {
		"template_id": str(template_data.get("template_id", "")),
		"name": str(template_data.get("name", "Untitled Template")),
		"asset_type": str(template_data.get("asset_type", "generic")),
		"version": int(template_data.get("version", 1)),
		"node_count": _as_array(template_data.get("nodes", [])).size(),
		"publish_node_ids": _as_string_array(template_data.get("publish_node_ids", [])),
		"required_artifact_types": _as_string_array(template_data.get("required_artifact_types", [])),
	}

func _build_run_summary(run_data: Dictionary) -> Dictionary:
	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	var attempts: Dictionary = _as_dictionary(run_data.get("attempts", {}))
	var revisions: Array = _as_array(run_data.get("revisions", []))
	var latest_revision: String = ""
	if not revisions.is_empty():
		latest_revision = str(_as_dictionary(revisions[revisions.size() - 1]).get("revision", ""))
	return {
		"run_id": str(run_data.get("run_id", "")),
		"template_id": str(run_data.get("template_id", "")),
		"template_name": str(run_data.get("template_name", "")),
		"asset_slug": str(run_data.get("asset_slug", "")),
		"display_name": str(run_data.get("display_name", "")),
		"updated_at": int(run_data.get("updated_at", 0)),
		"active_node_ids": _as_string_array(run_data.get("active_node_ids", [])),
		"review_request_count": _as_array(run_data.get("current_review_requests", [])).size(),
		"attempt_count": attempts.size(),
		"artifact_count": artifacts.size(),
		"revision_count": revisions.size(),
		"latest_revision": latest_revision,
	}

func _normalize_template(template_data: Dictionary) -> Dictionary:
	var normalized: Dictionary = template_data.duplicate(true)
	if not normalized.has("version"):
		normalized["version"] = 1
	if not normalized.has("asset_type"):
		normalized["asset_type"] = "generic"
	if not normalized.has("required_artifact_types"):
		normalized["required_artifact_types"] = []
	if not normalized.has("publish_node_ids"):
		normalized["publish_node_ids"] = []
	if not normalized.has("nodes"):
		normalized["nodes"] = []
	if not normalized.has("edges"):
		normalized["edges"] = []
	return normalized

func _validate_template(template_data: Dictionary) -> Dictionary:
	var template_id: String = _slugify(str(template_data.get("template_id", "")))
	if template_id.is_empty():
		return _error("invalid_template_id", "Template must include a valid template_id.")
	template_data["template_id"] = template_id

	var template_name: String = str(template_data.get("name", "")).strip_edges()
	if template_name.is_empty():
		return _error("missing_template_name", "Template must include a name.")
	template_data["name"] = template_name

	var nodes: Array = _as_array(template_data.get("nodes", []))
	if nodes.is_empty():
		return _error("missing_template_nodes", "Template must include at least one node.")

	var node_ids: Array = []
	var has_entry_node: bool = false
	for index in nodes.size():
		var node_dict: Dictionary = _as_dictionary(nodes[index])
		var node_id: String = _slugify(str(node_dict.get("id", "")))
		if node_id.is_empty():
			return _error("invalid_node_id", "Every node must include a valid id.", {"node_index": index})
		if node_ids.has(node_id):
			return _error("duplicate_node_id", "Template node ids must be unique.", {"node_id": node_id})
		node_ids.append(node_id)
		node_dict["id"] = node_id
		node_dict["label"] = str(node_dict.get("label", node_id)).strip_edges()
		node_dict["kind"] = str(node_dict.get("kind", "job")).strip_edges()
		node_dict["description"] = str(node_dict.get("description", ""))
		node_dict["consumes"] = _stringify_array(_as_array(node_dict.get("consumes", [])))
		node_dict["produces"] = _stringify_array(_as_array(node_dict.get("produces", [])))
		node_dict["decisions"] = _stringify_array(_as_array(node_dict.get("decisions", _default_decisions(str(node_dict.get("kind", "job"))))))
		nodes[index] = node_dict
		if bool(node_dict.get("entry", false)):
			has_entry_node = true
	template_data["nodes"] = nodes

	var edges: Array = _as_array(template_data.get("edges", []))
	for index in edges.size():
		var edge_dict: Dictionary = _as_dictionary(edges[index])
		var from_node: String = _slugify(str(edge_dict.get("from", "")))
		var to_node: String = _slugify(str(edge_dict.get("to", "")))
		if from_node.is_empty() or to_node.is_empty():
			return _error("invalid_edge", "Every edge must include non-empty from/to node ids.", {
				"edge_index": index,
			})
		if not node_ids.has(from_node) or not node_ids.has(to_node):
			return _error("unknown_edge_node", "Edges must point to known node ids.", {
				"edge_index": index,
				"from": from_node,
				"to": to_node,
			})
		edge_dict["from"] = from_node
		edge_dict["to"] = to_node
		edge_dict["decision"] = str(edge_dict.get("decision", "")).strip_edges()
		edges[index] = edge_dict
	template_data["edges"] = edges

	if not has_entry_node:
		var inbound_node_ids: Array = []
		for edge_data in edges:
			var edge_dict: Dictionary = _as_dictionary(edge_data)
			var target_id: String = str(edge_dict.get("to", ""))
			if not target_id.is_empty() and not inbound_node_ids.has(target_id):
				inbound_node_ids.append(target_id)
		for index in nodes.size():
			var node_dict: Dictionary = _as_dictionary(nodes[index])
			if not inbound_node_ids.has(str(node_dict.get("id", ""))):
				node_dict["entry"] = true
				nodes[index] = node_dict
				has_entry_node = true
				break

	if not has_entry_node:
		return _error("missing_entry_node", "Template must expose at least one entry node.")

	return {}

func _template_referenced_by_any_run(template_id: String) -> bool:
	for file_name in _list_json_files(RUN_DIR):
		var run_data: Dictionary = _read_json_file("%s/%s" % [RUN_DIR, file_name])
		if str(run_data.get("template_id", "")) == template_id:
			return true
	return false

func _find_entry_nodes(template_data: Dictionary) -> Array:
	var nodes: Array = _as_array(template_data.get("nodes", []))
	var edges: Array = _as_array(template_data.get("edges", []))
	var inbound_node_ids: Array = []
	for edge_data in edges:
		var edge_dict: Dictionary = _as_dictionary(edge_data)
		var target_id: String = str(edge_dict.get("to", ""))
		if not target_id.is_empty() and not inbound_node_ids.has(target_id):
			inbound_node_ids.append(target_id)

	var entry_nodes: Array = []
	for node_data in nodes:
		var node_dict: Dictionary = _as_dictionary(node_data)
		var node_id: String = str(node_dict.get("id", ""))
		if bool(node_dict.get("entry", false)) or not inbound_node_ids.has(node_id):
			entry_nodes.append(node_dict)
	return entry_nodes

func _new_attempt(
	run_id: String,
	node_data: Dictionary,
	input_artifact_ids: Array,
	parent_attempt_id: String,
	source_attempt_id: String
) -> Dictionary:
	var now: int = _now()
	var step_type: String = str(node_data.get("kind", "job"))
	return {
		"attempt_id": _make_id("%s-%s" % [run_id, str(node_data.get("id", "step"))]),
		"step_id": str(node_data.get("id", "")),
		"step_label": str(node_data.get("label", "Step")),
		"step_type": step_type,
		"description": str(node_data.get("description", "")),
		"state": "idle",
		"inputs": input_artifact_ids.duplicate(),
		"output_artifact_ids": [],
		"consumes": _as_string_array(node_data.get("consumes", [])),
		"produces": _as_string_array(node_data.get("produces", [])),
		"available_decisions": _as_string_array(node_data.get("decisions", _default_decisions(step_type))),
		"created_at": now,
		"updated_at": now,
		"review_notes": [],
		"applied_decisions": [],
		"parent_attempt_id": parent_attempt_id,
		"source_attempt_id": source_attempt_id,
		"job_metadata": _default_job_metadata(),
	}

func _default_decisions(step_type: String) -> Array:
	match step_type:
		"input":
			return ["approve", "request_changes"]
		"job":
			return ["queue", "run", "needs_review", "request_changes"]
		"review":
			return ["approve", "request_changes", "branch_new_attempt"]
		"transform", "validation", "import":
			return ["queue", "run", "approve", "skip", "request_changes"]
		"publish":
			return ["publish"]
		_:
			return ["approve", "request_changes"]

func _default_job_metadata() -> Dictionary:
	return {
		"provider": "",
		"task_type": "",
		"status": "",
		"job_id": "",
		"idempotency_key": "",
		"request_payload": {},
		"response_payload": {},
		"output_urls": [],
		"downloaded_paths": [],
		"error_message": "",
		"last_synced_at": 0,
	}

func _default_import_recipe(asset_slug: String) -> Dictionary:
	return {
		"recipe_id": "%s-default" % asset_slug,
		"destination_path": "res://assets/generated/%s" % asset_slug,
		"source_path": "",
		"scale": 1.0,
		"pivot_mode": "",
		"collision_mode": "",
		"material_bindings": [],
		"notes": "",
	}

func _normalize_import_recipe(import_recipe: Dictionary, asset_slug: String) -> Dictionary:
	var normalized: Dictionary = _default_import_recipe(asset_slug)
	for key in import_recipe.keys():
		normalized[str(key)] = import_recipe[key]
	return normalized

func _activate_downstream_attempts(run_data: Dictionary, template_data: Dictionary, attempt_data: Dictionary, decision: String) -> void:
	var source_step_id: String = str(attempt_data.get("step_id", ""))
	var edges: Array = _as_array(template_data.get("edges", []))
	var transition_inputs: Array = _transition_input_artifacts(attempt_data)
	for edge_data in edges:
		var edge_dict: Dictionary = _as_dictionary(edge_data)
		if str(edge_dict.get("from", "")) != source_step_id:
			continue
		if str(edge_dict.get("decision", "")) != decision:
			continue
		var target_node: Dictionary = _get_template_node(template_data, str(edge_dict.get("to", "")))
		if target_node.is_empty():
			continue
		var new_attempt: Dictionary = _new_attempt(
			str(run_data.get("run_id", "")),
			target_node,
			transition_inputs,
			str(attempt_data.get("attempt_id", "")),
			str(attempt_data.get("attempt_id", ""))
		)
		_add_attempt_to_run(run_data, new_attempt)
		_append_log(run_data, "Activated %s." % str(new_attempt.get("step_label", "step")))

func _spawn_sibling_attempt(run_data: Dictionary, attempt_data: Dictionary, node_data: Dictionary) -> void:
	if node_data.is_empty():
		return
	var sibling_attempt: Dictionary = _new_attempt(
		str(run_data.get("run_id", "")),
		node_data,
		_as_array(attempt_data.get("inputs", [])),
		str(attempt_data.get("attempt_id", "")),
		str(attempt_data.get("source_attempt_id", ""))
	)
	_add_attempt_to_run(run_data, sibling_attempt)
	_append_log(run_data, "Branched new attempt for %s." % str(attempt_data.get("step_label", "step")))

func _decision_state(decision: String) -> String:
	if DECISION_TO_STATE.has(decision):
		return str(DECISION_TO_STATE.get(decision, "approved"))
	return "approved"

func _decision_creates_outputs(decision: String) -> bool:
	return decision in [
		"needs_review",
		"approve",
		"approve_one",
		"approve_many",
		"promote_to_reference",
		"complete",
		"publish",
	]

func _ensure_attempt_outputs(run_data: Dictionary, attempt_id: String, node_data: Dictionary, decision: String) -> void:
	var attempt_data: Dictionary = _get_attempt(run_data, attempt_id)
	if attempt_data.is_empty():
		return
	var existing_outputs: Array = _as_array(attempt_data.get("output_artifact_ids", []))
	if not existing_outputs.is_empty():
		return

	var produces: Array = _as_string_array(node_data.get("produces", []))
	if produces.is_empty():
		return

	for artifact_type in produces:
		var artifact_id: String = _make_id(_slugify(artifact_type))
		var artifact_path: String = "%s/%s/%s/%s.json" % [
			SCRATCH_DIR,
			_slugify(artifact_type),
			str(run_data.get("run_id", "")),
			artifact_id,
		]
		_register_artifact_on_run(
			run_data,
			attempt_id,
			artifact_type,
			"%s %s" % [str(node_data.get("label", artifact_type)), artifact_type],
			artifact_path,
			artifact_path,
			{
				"decision": decision,
				"run_id": str(run_data.get("run_id", "")),
				"step_id": str(node_data.get("id", "")),
				"step_label": str(node_data.get("label", "")),
			},
			false,
			false,
			artifact_id
		)

func _attach_artifact_to_attempt(run_data: Dictionary, attempt_id: String, artifact_id: String) -> void:
	var attempt_data: Dictionary = _get_attempt(run_data, attempt_id)
	if attempt_data.is_empty():
		return
	var output_ids: Array = _as_string_array(attempt_data.get("output_artifact_ids", []))
	if not output_ids.has(artifact_id):
		output_ids.append(artifact_id)
	attempt_data["output_artifact_ids"] = output_ids
	_set_attempt(run_data, attempt_id, attempt_data)

func _register_artifact_on_run(
	run_data: Dictionary,
	attempt_id: String,
	artifact_type: String,
	display_name: String,
	storage_uri: String,
	preview_uri: String,
	metadata: Dictionary,
	selected: bool,
	publish_candidate: bool,
	artifact_id: String
) -> Dictionary:
	var resolved_artifact_id: String = artifact_id.strip_edges()
	if resolved_artifact_id.is_empty():
		resolved_artifact_id = _make_id(_slugify(artifact_type))

	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	var existing_artifact: Dictionary = _as_dictionary(artifacts.get(resolved_artifact_id, {}))
	var parent_artifact_ids: Array = _as_array(existing_artifact.get("parent_artifact_ids", []))
	if parent_artifact_ids.is_empty() and not attempt_id.is_empty():
		var attempt_data: Dictionary = _get_attempt(run_data, attempt_id)
		parent_artifact_ids = _as_array(attempt_data.get("inputs", []))

	var artifact_data: Dictionary = {
		"artifact_id": resolved_artifact_id,
		"artifact_type": artifact_type,
		"display_name": display_name.strip_edges() if not display_name.strip_edges().is_empty() else artifact_type,
		"source_attempt_id": attempt_id if not attempt_id.is_empty() else str(existing_artifact.get("source_attempt_id", "")),
		"storage_uri": storage_uri.strip_edges(),
		"preview_uri": preview_uri.strip_edges() if not preview_uri.strip_edges().is_empty() else storage_uri.strip_edges(),
		"metadata": metadata,
		"parent_artifact_ids": parent_artifact_ids,
		"is_selected": selected,
		"is_publish_candidate": publish_candidate,
	}

	artifacts[resolved_artifact_id] = artifact_data
	run_data["artifacts"] = artifacts
	if not attempt_id.is_empty():
		_attach_artifact_to_attempt(run_data, attempt_id, resolved_artifact_id)

	if selected:
		_mark_artifact_selected_on_run(run_data, resolved_artifact_id, true)
	else:
		_mark_artifact_selected_on_run(run_data, resolved_artifact_id, false)
	if publish_candidate:
		_mark_artifact_publish_candidate_on_run(run_data, resolved_artifact_id, true)
	else:
		_mark_artifact_publish_candidate_on_run(run_data, resolved_artifact_id, false)

	var artifact_storage_uri: String = str(artifact_data.get("storage_uri", ""))
	if artifact_storage_uri.begins_with("%s/" % SCRATCH_DIR) and artifact_storage_uri.get_extension() == "json":
		_write_json_file(str(artifact_data["storage_uri"]), artifact_data)

	return artifact_data

func _remove_artifact_from_attempts(run_data: Dictionary, artifact_id: String) -> void:
	var attempts: Dictionary = _as_dictionary(run_data.get("attempts", {}))
	for attempt_key in attempts.keys():
		var attempt_data: Dictionary = _as_dictionary(attempts.get(attempt_key, {}))
		var output_ids: Array = _as_string_array(attempt_data.get("output_artifact_ids", []))
		if output_ids.has(artifact_id):
			output_ids.erase(artifact_id)
			attempt_data["output_artifact_ids"] = output_ids
			attempts[attempt_key] = attempt_data
	run_data["attempts"] = attempts

func _remove_artifact_references(run_data: Dictionary, artifact_id: String) -> void:
	var selected_ids: Array = _as_string_array(run_data.get("selected_artifact_ids", []))
	selected_ids.erase(artifact_id)
	run_data["selected_artifact_ids"] = selected_ids

	var attempts: Dictionary = _as_dictionary(run_data.get("attempts", {}))
	for attempt_key in attempts.keys():
		var attempt_data: Dictionary = _as_dictionary(attempts.get(attempt_key, {}))
		var input_ids: Array = _as_string_array(attempt_data.get("inputs", []))
		if input_ids.has(artifact_id):
			input_ids.erase(artifact_id)
			attempt_data["inputs"] = input_ids
			attempts[attempt_key] = attempt_data
	run_data["attempts"] = attempts

	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	for artifact_key in artifacts.keys():
		var artifact_data: Dictionary = _as_dictionary(artifacts.get(artifact_key, {}))
		var parent_ids: Array = _as_string_array(artifact_data.get("parent_artifact_ids", []))
		if parent_ids.has(artifact_id):
			parent_ids.erase(artifact_id)
			artifact_data["parent_artifact_ids"] = parent_ids
			artifacts[artifact_key] = artifact_data
	run_data["artifacts"] = artifacts

func _mark_attempt_outputs_selected(run_data: Dictionary, attempt_id: String, selected: bool) -> void:
	var attempt_data: Dictionary = _get_attempt(run_data, attempt_id)
	if attempt_data.is_empty():
		return
	for artifact_id in _as_array(attempt_data.get("output_artifact_ids", [])):
		_mark_artifact_selected_on_run(run_data, str(artifact_id), selected)

func _mark_attempt_outputs_publish_candidate(run_data: Dictionary, attempt_id: String, publish_candidate: bool) -> void:
	var attempt_data: Dictionary = _get_attempt(run_data, attempt_id)
	if attempt_data.is_empty():
		return
	for artifact_id in _as_array(attempt_data.get("output_artifact_ids", [])):
		_mark_artifact_publish_candidate_on_run(run_data, str(artifact_id), publish_candidate)

func _mark_artifact_selected_on_run(run_data: Dictionary, artifact_id: String, selected: bool) -> void:
	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	if not artifacts.has(artifact_id):
		return
	var artifact_data: Dictionary = _as_dictionary(artifacts.get(artifact_id, {}))
	artifact_data["is_selected"] = selected
	artifacts[artifact_id] = artifact_data
	run_data["artifacts"] = artifacts

	var selected_ids: Array = _as_string_array(run_data.get("selected_artifact_ids", []))
	if selected:
		if not selected_ids.has(artifact_id):
			selected_ids.append(artifact_id)
	else:
		selected_ids.erase(artifact_id)
	run_data["selected_artifact_ids"] = selected_ids

func _mark_artifact_publish_candidate_on_run(run_data: Dictionary, artifact_id: String, publish_candidate: bool) -> void:
	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	if not artifacts.has(artifact_id):
		return
	var artifact_data: Dictionary = _as_dictionary(artifacts.get(artifact_id, {}))
	artifact_data["is_publish_candidate"] = publish_candidate
	artifacts[artifact_id] = artifact_data
	run_data["artifacts"] = artifacts

func _update_review_request_state(run_data: Dictionary, attempt_id: String, state: String) -> void:
	var requests: Array = _as_string_array(run_data.get("current_review_requests", []))
	if state == "needs_review":
		if not requests.has(attempt_id):
			requests.append(attempt_id)
	else:
		requests.erase(attempt_id)
	run_data["current_review_requests"] = requests

func _recompute_active_nodes(run_data: Dictionary) -> void:
	var attempts: Dictionary = _as_dictionary(run_data.get("attempts", {}))
	var active_nodes: Array = []
	for attempt_data in attempts.values():
		var attempt_dict: Dictionary = _as_dictionary(attempt_data)
		var state: String = str(attempt_dict.get("state", "idle"))
		if not ACTIVE_STATES.has(state):
			continue
		var node_id: String = str(attempt_dict.get("step_id", ""))
		if not node_id.is_empty() and not active_nodes.has(node_id):
			active_nodes.append(node_id)
	run_data["active_node_ids"] = active_nodes

func _update_validation(run_data: Dictionary) -> void:
	var template_data: Dictionary = get_template(str(run_data.get("template_id", "")))
	var attempts: Dictionary = _as_dictionary(run_data.get("attempts", {}))
	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	var report: Array = []
	var publish_node_ids: Array = _as_string_array(template_data.get("publish_node_ids", []))
	var import_recipe: Dictionary = _as_dictionary(run_data.get("import_recipe", {}))

	report.append(_validation_item(
		"asset_slug",
		true,
		not str(run_data.get("asset_slug", "")).is_empty(),
		"Asset slug is set."
	))
	report.append(_validation_item(
		"template_exists",
		true,
		not template_data.is_empty(),
		"Workflow template is available."
	))
	report.append(_validation_item(
		"attempts_present",
		true,
		attempts.size() > 0,
		"Run contains step attempts."
	))
	report.append(_validation_item(
		"artifacts_present",
		true,
		artifacts.size() > 0,
		"At least one artifact exists."
	))
	report.append(_validation_item(
		"selection_ready",
		true,
		not _as_string_array(run_data.get("selected_artifact_ids", [])).is_empty() or not _publish_candidate_artifact_ids(run_data).is_empty(),
		"Run has selected or publish-candidate artifacts."
	))
	report.append(_validation_item(
		"publish_step_reached",
		true,
		_publish_step_reached(attempts, publish_node_ids),
		"Publish node has been activated."
	))
	report.append(_validation_item(
		"reviews_resolved",
		true,
		_as_array(run_data.get("current_review_requests", [])).is_empty(),
		"No review requests are currently pending."
	))
	report.append(_validation_item(
		"import_recipe_ready",
		true,
		not str(import_recipe.get("destination_path", "")).strip_edges().is_empty(),
		"Import recipe includes a destination path."
	))

	run_data["validation_report"] = report

func _publish_step_reached(attempts: Dictionary, publish_node_ids: Array) -> bool:
	if publish_node_ids.is_empty():
		return true
	for attempt_data in attempts.values():
		var attempt_dict: Dictionary = _as_dictionary(attempt_data)
		if publish_node_ids.has(str(attempt_dict.get("step_id", ""))):
			return true
	return false

func _publish_candidate_artifact_ids(run_data: Dictionary) -> Array:
	var artifact_ids: Array = []
	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	for artifact_id in artifacts.keys():
		var artifact_data: Dictionary = _as_dictionary(artifacts.get(artifact_id, {}))
		if bool(artifact_data.get("is_publish_candidate", false)):
			artifact_ids.append(str(artifact_id))
	return artifact_ids

func _validation_item(id: String, required: bool, ok: bool, detail: String) -> Dictionary:
	return {
		"id": id,
		"required": required,
		"ok": ok,
		"detail": detail,
	}

func _validation_passes(report: Array) -> bool:
	for item_data in report:
		var item_dict: Dictionary = _as_dictionary(item_data)
		if bool(item_dict.get("required", false)) and not bool(item_dict.get("ok", false)):
			return false
	return true

func _get_template_node(template_data: Dictionary, node_id: String) -> Dictionary:
	for node_data in _as_array(template_data.get("nodes", [])):
		var node_dict: Dictionary = _as_dictionary(node_data)
		if str(node_dict.get("id", "")) == node_id:
			return node_dict
	return {}

func _transition_input_artifacts(attempt_data: Dictionary) -> Array:
	var output_ids: Array = _as_array(attempt_data.get("output_artifact_ids", []))
	if not output_ids.is_empty():
		return output_ids
	return _as_array(attempt_data.get("inputs", []))

func _get_attempt(run_data: Dictionary, attempt_id: String) -> Dictionary:
	var attempts: Dictionary = _as_dictionary(run_data.get("attempts", {}))
	if attempts.has(attempt_id):
		return _as_dictionary(attempts.get(attempt_id, {}))
	return {}

func _set_attempt(run_data: Dictionary, attempt_id: String, attempt_data: Dictionary) -> void:
	var attempts: Dictionary = _as_dictionary(run_data.get("attempts", {}))
	attempts[attempt_id] = attempt_data
	run_data["attempts"] = attempts

func _add_attempt_to_run(run_data: Dictionary, attempt_data: Dictionary) -> void:
	_set_attempt(run_data, str(attempt_data.get("attempt_id", "")), attempt_data)

func _update_job_metadata_status(job_metadata: Dictionary, status: String) -> Dictionary:
	var updated: Dictionary = _default_job_metadata()
	for key in job_metadata.keys():
		updated[str(key)] = job_metadata[key]
	updated["status"] = status
	updated["last_synced_at"] = _now()
	return updated

func _seed_default_templates() -> void:
	if not _list_json_files(TEMPLATE_DIR).is_empty():
		return
	_write_json_file(_template_path("image_asset_v1"), _default_image_template())
	_write_json_file(_template_path("model_asset_v1"), _default_model_template())

func _collect_run_scratch_paths(run_data: Dictionary) -> Array:
	var paths: Array = []
	var artifacts: Dictionary = _as_dictionary(run_data.get("artifacts", {}))
	for artifact_data in artifacts.values():
		var artifact_dict: Dictionary = _as_dictionary(artifact_data)
		for path_key in ["storage_uri", "preview_uri"]:
			var path_value: String = str(artifact_dict.get(path_key, ""))
			if path_value.begins_with("%s/" % SCRATCH_DIR) and not paths.has(path_value):
				paths.append(path_value)
	return paths

func _default_image_template() -> Dictionary:
	return {
		"template_id": "image_asset_v1",
		"name": "Image Asset",
		"asset_type": "image",
		"version": 1,
		"required_artifact_types": [
			"ConceptDoc",
			"PromptSpec",
			"ConceptImage",
			"AssetRevisionManifest",
		],
		"publish_node_ids": ["publish_revision"],
		"nodes": [
			{
				"id": "brief",
				"label": "Brief",
				"kind": "input",
				"entry": true,
				"description": "Capture the asset brief, constraints, and style direction.",
				"produces": ["ConceptDoc"],
				"decisions": ["approve", "request_changes"],
			},
			{
				"id": "prompt",
				"label": "Prompt",
				"kind": "input",
				"description": "Refine the generation prompt and negative prompt.",
				"consumes": ["ConceptDoc"],
				"produces": ["PromptSpec"],
				"decisions": ["approve", "request_changes"],
			},
			{
				"id": "generate_images",
				"label": "Generate Images",
				"kind": "job",
				"description": "Run a text-to-image job and stage the resulting concepts.",
				"consumes": ["PromptSpec"],
				"produces": ["ConceptImage"],
				"decisions": ["queue", "run", "needs_review", "request_changes"],
			},
			{
				"id": "review_images",
				"label": "Review Images",
				"kind": "review",
				"description": "Shortlist and select the preferred concept image.",
				"consumes": ["ConceptImage"],
				"produces": ["SelectedReferenceImage"],
				"decisions": ["approve_one", "more_variants", "request_changes", "promote_to_reference"],
			},
			{
				"id": "polish",
				"label": "Polish",
				"kind": "transform",
				"description": "Optional polish pass before publish.",
				"consumes": ["SelectedReferenceImage"],
				"produces": ["PolishedImage"],
				"decisions": ["queue", "run", "approve", "skip"],
			},
			{
				"id": "publish_revision",
				"label": "Publish Revision",
				"kind": "publish",
				"description": "Freeze the selected artifacts into a canonical revision manifest.",
				"consumes": ["PolishedImage", "SelectedReferenceImage"],
				"produces": ["AssetRevisionManifest"],
				"decisions": ["publish"],
			},
		],
		"edges": [
			{"from": "brief", "decision": "approve", "to": "prompt"},
			{"from": "prompt", "decision": "approve", "to": "generate_images"},
			{"from": "generate_images", "decision": "needs_review", "to": "review_images"},
			{"from": "generate_images", "decision": "request_changes", "to": "prompt"},
			{"from": "review_images", "decision": "approve_one", "to": "polish"},
			{"from": "review_images", "decision": "promote_to_reference", "to": "polish"},
			{"from": "review_images", "decision": "more_variants", "to": "generate_images"},
			{"from": "review_images", "decision": "request_changes", "to": "prompt"},
			{"from": "polish", "decision": "approve", "to": "publish_revision"},
			{"from": "polish", "decision": "skip", "to": "publish_revision"},
		],
	}

func _default_model_template() -> Dictionary:
	return {
		"template_id": "model_asset_v1",
		"name": "3D Model Asset",
		"asset_type": "3d_model",
		"version": 1,
		"required_artifact_types": [
			"ConceptDoc",
			"PromptSpec",
			"ConceptImage",
			"SelectedReferenceImage",
			"MeshDraft",
			"ImportedScene",
			"AssetRevisionManifest",
		],
		"publish_node_ids": ["publish_revision"],
		"nodes": [
			{
				"id": "concept_text",
				"label": "Concept Text",
				"kind": "input",
				"entry": true,
				"description": "Define the model brief, constraints, and references.",
				"produces": ["ConceptDoc"],
				"decisions": ["approve", "request_changes"],
			},
			{
				"id": "image_prompt",
				"label": "Image Prompt",
				"kind": "input",
				"description": "Translate the concept into a text-to-image prompt.",
				"consumes": ["ConceptDoc"],
				"produces": ["PromptSpec"],
				"decisions": ["approve", "request_changes"],
			},
			{
				"id": "text_to_image",
				"label": "Text To Image",
				"kind": "job",
				"description": "Generate concept image candidates.",
				"consumes": ["PromptSpec"],
				"produces": ["ConceptImage"],
				"decisions": ["queue", "run", "needs_review", "request_changes"],
			},
			{
				"id": "concept_review",
				"label": "Concept Review",
				"kind": "review",
				"description": "Approve a concept image or loop back for more variants.",
				"consumes": ["ConceptImage"],
				"produces": ["SelectedReferenceImage"],
				"decisions": ["approve_one", "more_variants", "request_changes", "promote_to_reference"],
			},
			{
				"id": "image_to_3d",
				"label": "Image To 3D",
				"kind": "job",
				"description": "Create mesh candidates from the selected concept image.",
				"consumes": ["SelectedReferenceImage"],
				"produces": ["MeshDraft"],
				"decisions": ["queue", "run", "needs_review", "request_changes"],
			},
			{
				"id": "mesh_review",
				"label": "Mesh Review",
				"kind": "review",
				"description": "Review topology, proportions, and readiness for import.",
				"consumes": ["MeshDraft"],
				"produces": ["ApprovedMesh"],
				"decisions": ["approve", "regenerate_from_same_reference", "back_to_concept", "request_changes"],
			},
			{
				"id": "import_and_validate",
				"label": "Import And Validate",
				"kind": "import",
				"description": "Prepare the asset for Godot import and validate it.",
				"consumes": ["ApprovedMesh"],
				"produces": ["ImportedScene", "ValidationReport"],
				"decisions": ["queue", "run", "approve", "request_changes"],
			},
			{
				"id": "publish_revision",
				"label": "Publish Revision",
				"kind": "publish",
				"description": "Write the canonical revision manifest into assets/generated.",
				"consumes": ["ImportedScene", "ValidationReport"],
				"produces": ["AssetRevisionManifest"],
				"decisions": ["publish"],
			},
		],
		"edges": [
			{"from": "concept_text", "decision": "approve", "to": "image_prompt"},
			{"from": "image_prompt", "decision": "approve", "to": "text_to_image"},
			{"from": "text_to_image", "decision": "needs_review", "to": "concept_review"},
			{"from": "text_to_image", "decision": "request_changes", "to": "image_prompt"},
			{"from": "concept_review", "decision": "approve_one", "to": "image_to_3d"},
			{"from": "concept_review", "decision": "promote_to_reference", "to": "image_to_3d"},
			{"from": "concept_review", "decision": "more_variants", "to": "text_to_image"},
			{"from": "concept_review", "decision": "request_changes", "to": "image_prompt"},
			{"from": "image_to_3d", "decision": "needs_review", "to": "mesh_review"},
			{"from": "image_to_3d", "decision": "request_changes", "to": "concept_review"},
			{"from": "mesh_review", "decision": "approve", "to": "import_and_validate"},
			{"from": "mesh_review", "decision": "regenerate_from_same_reference", "to": "image_to_3d"},
			{"from": "mesh_review", "decision": "back_to_concept", "to": "concept_review"},
			{"from": "mesh_review", "decision": "request_changes", "to": "image_to_3d"},
			{"from": "import_and_validate", "decision": "approve", "to": "publish_revision"},
			{"from": "import_and_validate", "decision": "request_changes", "to": "mesh_review"},
		],
	}

func _template_path(template_id: String) -> String:
	return "%s/%s.json" % [TEMPLATE_DIR, _slugify(template_id)]

func _run_path(run_id: String) -> String:
	return "%s/%s.json" % [RUN_DIR, run_id]

func _save_run(run_data: Dictionary) -> int:
	return _write_json_file(_run_path(str(run_data.get("run_id", ""))), run_data)

func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

func _write_json_file(path: String, payload: Dictionary) -> int:
	_ensure_directory(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ERR_CANT_CREATE
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return OK

func _remove_file(path: String) -> int:
	var directory: DirAccess = DirAccess.open(path.get_base_dir())
	if directory == null:
		return ERR_CANT_OPEN
	return directory.remove(path.get_file())

func _ensure_directory(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute_path)

func _list_json_files(path: String) -> Array:
	var files: Array = []
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return files
	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		if not directory.current_is_dir() and entry_name.get_extension() == "json":
			files.append(entry_name)
		entry_name = directory.get_next()
	directory.list_dir_end()
	return files

func _append_log(run_data: Dictionary, message: String) -> void:
	var logs: Array = _as_array(run_data.get("logs", []))
	logs.append("[%d] %s" % [_now(), message])
	run_data["logs"] = logs

func _make_id(prefix: String) -> String:
	var cleaned_prefix: String = _slugify(prefix)
	if cleaned_prefix.is_empty():
		cleaned_prefix = "id"
	var generated_id: String = "%s-%d-%d" % [cleaned_prefix, _now(), _id_counter]
	_id_counter += 1
	return generated_id

func _now() -> int:
	return int(Time.get_unix_time_from_system())

func _slugify(raw_value: String) -> String:
	var lowered: String = raw_value.strip_edges().to_lower()
	var output: String = ""
	var previous_was_dash: bool = false
	for index in lowered.length():
		var character: String = lowered.substr(index, 1)
		var is_alpha_numeric: bool = "abcdefghijklmnopqrstuvwxyz0123456789".contains(character)
		if is_alpha_numeric:
			output += character
			previous_was_dash = false
		elif not previous_was_dash and not output.is_empty():
			output += "-"
			previous_was_dash = true
	if output.ends_with("-"):
		output = output.left(output.length() - 1)
	return output

func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []

func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}

func _as_string_array(value: Variant) -> Array:
	return _stringify_array(_as_array(value))

func _stringify_array(values: Array) -> Array:
	var output: Array = []
	for item in values:
		output.append(str(item))
	return output

func _success(extra: Dictionary = {}) -> Dictionary:
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
