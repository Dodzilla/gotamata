---
name: godot-editor-agent-bridge
description: Control the local GoTamata Godot asset pipeline and editor bridge over localhost JSON/TCP. Use when an AI agent needs to manage workflow templates, runs, jobs, import recipes, artifacts, and published revisions, or inspect/editor-control a running Godot 4.6 editor.
---

# Godot Editor Agent Bridge

## Overview

Use this skill to drive a running local Godot editor and the GoTamata asset pipeline through the plugin server at `godot-plugin/addons/gotamata_agent_bridge`.
Use command-per-line JSON messages over TCP and treat every response as authoritative state.

## Quick Start

1. Confirm the Godot plugin is enabled and the server is running.
2. Send `ping` to verify connectivity.
3. Send `list_commands` and `pipeline_overview` to discover current pipeline context.
4. If you need editor context too, send `editor_state`.
5. Execute targeted commands.
6. Re-read `editor_state` after changes that could alter scene focus.

Use the helper script for repeatable calls:

```bash
python3 scripts/send_command.py ping
python3 scripts/send_command.py pipeline_overview
python3 scripts/send_command.py list_workflow_templates
python3 scripts/send_command.py editor_state
python3 scripts/send_command.py open_scene --args '{"path":"res://scenes/main.tscn"}'
```

## Bridge Contract Snapshot

<!-- BEGIN GENERATED BRIDGE SNAPSHOT -->
- Transport: `127.0.0.1:47891` over newline-delimited JSON.
- Core commands: `ping`, `list_commands`.
- Editor commands: `editor_state`, `open_scene`, `play`, `stop`, `save_scene`, `select_node`, `add_node`, `set_property`, `set_main_screen`, `call`.
- Pipeline commands: `pipeline_overview`, `list_workflow_templates`, `get_workflow_template`, `upsert_workflow_template`, `delete_workflow_template`, `list_workflow_runs`, `get_workflow_run`, `create_workflow_run`, `delete_workflow_run`, `apply_workflow_decision`, `set_workflow_import_recipe`, `set_workflow_attempt_job`, `set_workflow_attempt_job_status`, `register_workflow_artifact`, `delete_workflow_artifact`, `publish_workflow_revision`, `set_workflow_artifact_selected`, `set_workflow_artifact_publish_candidate`.
- Full argument and result details are generated in `references/protocol.md`.
<!-- END GENERATED BRIDGE SNAPSHOT -->

## Command Workflow

1. Prefer the pipeline commands for pipeline state: `pipeline_overview`, `list_workflow_templates`, `get_workflow_template`, `upsert_workflow_template`, `delete_workflow_template`, `list_workflow_runs`, `get_workflow_run`, `create_workflow_run`, `delete_workflow_run`, `apply_workflow_decision`, `set_workflow_import_recipe`, `set_workflow_attempt_job`, `set_workflow_attempt_job_status`, `register_workflow_artifact`, `delete_workflow_artifact`, `set_workflow_artifact_selected`, `set_workflow_artifact_publish_candidate`, `publish_workflow_revision`.
2. Prefer editor-specific commands for editor state: `open_scene`, `add_node`, `set_property`, `set_main_screen`.
3. Use `call` only when a specific command does not cover the operation.
4. Keep `call.method` non-private. Methods beginning with `_` are rejected.
5. Send one focused command at a time and inspect response `ok` before the next command.
6. For scene edits, call `save_scene` explicitly unless the user asked not to persist changes.

## Asset Pipeline Workflow

Use this sequence when the user wants an AI agent to manage assets through the pipeline:

1. Discover pipeline state and available templates.

```bash
python3 scripts/send_command.py pipeline_overview
python3 scripts/send_command.py list_workflow_templates
```

2. If needed, author or update a workflow template before creating a run.

```bash
python3 scripts/send_command.py get_workflow_template --args '{"template_id":"model_asset_v1"}'
python3 scripts/send_command.py upsert_workflow_template --args '{"template":{"template_id":"custom_model_v1","name":"Custom Model","asset_type":"3d_model","version":1,"required_artifact_types":["ConceptDoc","AssetRevisionManifest"],"publish_node_ids":["publish_revision"],"nodes":[{"id":"brief","label":"Brief","kind":"input","entry":true,"description":"Capture the brief.","produces":["ConceptDoc"],"decisions":["approve"]},{"id":"publish_revision","label":"Publish Revision","kind":"publish","description":"Publish the manifest.","consumes":["ConceptDoc"],"produces":["AssetRevisionManifest"],"decisions":["publish"]}],"edges":[{"from":"brief","decision":"approve","to":"publish_revision"}]}}'
```

3. Create a workflow run.

```bash
python3 scripts/send_command.py create_workflow_run --args '{"template_id":"model_asset_v1","asset_slug":"forest-gate","display_name":"Forest Gate"}'
```

4. Read the run document and capture `attempt_id` and `artifact_id` values from the response.

```bash
python3 scripts/send_command.py get_workflow_run --args '{"run_id":"forest-gate-..."}'
```

5. For job-backed steps, store the outbound provider request in the run before you execute it externally.

```bash
python3 scripts/send_command.py set_workflow_attempt_job --args '{"run_id":"forest-gate-...","attempt_id":"...","provider":"killatamata","task_type":"image_to_3d","request_payload":{"input":{"prompt":"Weathered stone gate"}},"job_id":"","idempotency_key":"forest-gate-image-to-3d-v1"}'
```

6. Execute the external provider call outside the bridge when required, then sync status and outputs back into the run.
   The bridge tracks pipeline state; it does not submit provider jobs for you.
   Use the relevant external skill for execution, for example the installed `$killatamata` skill, and then write the result back with:

```bash
python3 scripts/send_command.py set_workflow_attempt_job_status --args '{"run_id":"forest-gate-...","attempt_id":"...","status":"needs_review","job_id":"job_123","response_payload":{"status":"completed"},"output_urls":["https://..."],"downloaded_paths":["res://_ai_work/mesh/forest-gate.glb"],"error_message":""}'
python3 scripts/send_command.py register_workflow_artifact --args '{"run_id":"forest-gate-...","attempt_id":"...","artifact_type":"MeshDraft","display_name":"Forest Gate Draft","storage_uri":"res://_ai_work/mesh/forest-gate.glb","preview_uri":"res://_ai_work/mesh/forest-gate.png","metadata":{"provider":"killatamata","job_id":"job_123"},"selected":false,"publish_candidate":false}'
```

7. Update the import recipe when the asset needs explicit Godot import settings.

```bash
python3 scripts/send_command.py set_workflow_import_recipe --args '{"run_id":"forest-gate-...","import_recipe":{"recipe_id":"forest-gate-default","destination_path":"res://assets/generated/forest-gate","source_path":"res://_ai_work/mesh/forest-gate.glb","scale":1.0,"pivot_mode":"origin","collision_mode":"trimesh","material_bindings":[],"notes":"Initial import recipe"}}'
```

8. Move the selected attempt through the workflow by applying explicit decisions.

```bash
python3 scripts/send_command.py apply_workflow_decision --args '{"run_id":"forest-gate-...","attempt_id":"...","decision":"approve"}'
python3 scripts/send_command.py apply_workflow_decision --args '{"run_id":"forest-gate-...","attempt_id":"...","decision":"needs_review"}'
python3 scripts/send_command.py apply_workflow_decision --args '{"run_id":"forest-gate-...","attempt_id":"...","decision":"approve_one"}'
```

9. Select, update, or delete artifacts as the workflow evolves.

```bash
python3 scripts/send_command.py set_workflow_artifact_selected --args '{"run_id":"forest-gate-...","artifact_id":"...","selected":true}'
python3 scripts/send_command.py set_workflow_artifact_publish_candidate --args '{"run_id":"forest-gate-...","artifact_id":"...","publish_candidate":true}'
python3 scripts/send_command.py delete_workflow_artifact --args '{"run_id":"forest-gate-...","artifact_id":"..."}'
```

10. Publish the canonical revision manifest.

```bash
python3 scripts/send_command.py publish_workflow_revision --args '{"run_id":"forest-gate-...","version_label":"v1.0.0","notes":"Initial approved revision"}'
```

11. Use cleanup commands when the pipeline state is no longer needed.

```bash
python3 scripts/send_command.py delete_workflow_run --args '{"run_id":"forest-gate-..."}'
python3 scripts/send_command.py delete_workflow_template --args '{"template_id":"custom_model_v1"}'
```

## Pipeline Rules

- Treat `get_workflow_run` as the source of truth for active attempts, artifacts, revisions, logs, and validation state.
- Treat `get_workflow_template` as the source of truth for template JSON before editing or deleting a template.
- When a command requires `attempt_id` or `artifact_id`, fetch the latest run first instead of guessing.
- Use only the decision names listed on a step attempt in `available_decisions`.
- Use `set_workflow_attempt_job` before provider execution and `set_workflow_attempt_job_status` after polling or completion so the run remains auditably in sync with the external job.
- Use `register_workflow_artifact` for real outputs even if the run already contains placeholder artifacts from a workflow decision.
- Use `set_workflow_import_recipe` before publish when imported assets need stable destination or import settings.
- Select artifacts explicitly before publish unless the run already marks them as publish candidates.
- Stop and report the validation payload if `publish_workflow_revision` returns `validation_failed`.
- The bridge mirrors the current GoTamata UI surface for template CRUD, run management, external job tracking, import recipes, artifact management, and publish.
- External provider execution still happens outside the bridge. Run the provider with the relevant skill/tool, then sync the result back into the pipeline.

## Operational Rules

- Treat server and editor as local-only control plane; never expose host/port publicly.
- If auth token is configured in the plugin, include `--token` in every call.
- If a command fails, stop and report exact error payload before retrying.
- Use absolute `res://` paths when possible to avoid ambiguity.
- Avoid broad `call` invocations that mutate unknown state.

## References

- Protocol and command details: `references/protocol.md`
- CLI helper for transport: `scripts/send_command.py`
