# GoTamata Asset Pipeline (Godot 4.6)

This plugin now has two surfaces:

- a `GoTamata` main editor tab for asset workflow templates, runs, artifacts, validation, and revision publishing
- a localhost TCP bridge so local AI agents can drive both editor actions and pipeline state through newline-delimited JSON commands

## Main Screen

The main screen is built around the pipeline plan:

- template selection and run creation on the left
- template JSON authoring with save/delete actions
- run summary, attempts, and artifacts in the center
- step decisions, external job tracking, import recipe editing, artifact register/delete, validation, and publish controls on the right
- logs, validation output, and raw run JSON at the bottom

Seeded workflow templates live in `res://workflows/templates`:

- `image_asset_v1`
- `model_asset_v1`

Runs persist to `res://workflows/runs`.
Published revision manifests persist to `res://assets/generated/<asset_slug>/<version>/manifest/asset_revision.json`.
Scratch artifacts are written under `res://_ai_work/`.

## Agent Bridge Transport

- Host: `127.0.0.1` by default
- Port: `47891` by default
- Framing: one JSON object per line (`\n` terminated)

Request shape:

```json
{"id":"req-1","token":"optional","command":"ping","args":{}}
```

Response shape:

```json
{"ok":true,"id":"req-1","command":"ping","message":"pong"}
```

<!-- BEGIN GENERATED BRIDGE COMMANDS -->
## Commands

### Core
- `ping` (`args`: none)
- `list_commands` (`args`: none)

### Editor
- `editor_state` (`args`: none)
- `open_scene` (`args`: path)
- `play` (`args`: none)
- `stop` (`args`: none)
- `save_scene` (`args`: path optional)
- `select_node` (`args`: path)
- `add_node` (`args`: parent optional, type optional, name optional, properties optional)
- `set_property` (`args`: path, property, value)
- `set_main_screen` (`args`: screen)
- `call` (`args`: target, method, arguments optional)

### Pipeline
- `pipeline_overview` (`args`: none)
- `list_workflow_templates` (`args`: none)
- `get_workflow_template` (`args`: template_id)
- `upsert_workflow_template` (`args`: template)
- `delete_workflow_template` (`args`: template_id)
- `list_workflow_runs` (`args`: none)
- `get_workflow_run` (`args`: run_id)
- `create_workflow_run` (`args`: template_id, asset_slug, display_name optional)
- `delete_workflow_run` (`args`: run_id)
- `apply_workflow_decision` (`args`: run_id, attempt_id, decision, note optional)
- `set_workflow_import_recipe` (`args`: run_id, import_recipe)
- `set_workflow_attempt_job` (`args`: run_id, attempt_id, provider, task_type, request_payload, job_id optional, idempotency_key optional, note optional)
- `set_workflow_attempt_job_status` (`args`: run_id, attempt_id, status, job_id optional, response_payload optional, output_urls optional, downloaded_paths optional, error_message optional)
- `register_workflow_artifact` (`args`: run_id, attempt_id optional, artifact_type, display_name optional, storage_uri, preview_uri optional, metadata optional, selected optional, publish_candidate optional, artifact_id optional)
- `delete_workflow_artifact` (`args`: run_id, artifact_id)
- `publish_workflow_revision` (`args`: run_id, version_label optional, notes optional)
- `set_workflow_artifact_selected` (`args`: run_id, artifact_id, selected optional)
- `set_workflow_artifact_publish_candidate` (`args`: run_id, artifact_id, publish_candidate optional)

`call` targets are currently: `editor_interface`, `edited_scene_root`, `selection`, `plugin`.
<!-- END GENERATED BRIDGE COMMANDS -->

## Safety

- The server listens only on localhost by default.
- Add an auth token in the dock to require `token` in requests.
- Methods beginning with `_` are blocked in `call`.
- External provider execution is expected to happen outside the bridge; write request/status/output state back with the workflow job commands.
