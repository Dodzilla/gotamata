---
name: killatamata-arcade-publisher
description: Prepare a local Godot 4.6 project for KillaTamata Arcade, validate submission readiness, build an arcade release bundle, and submit that bundle through the KillaTamata creator API.
---

# KillaTamata Arcade Publisher

## Overview

Use this skill when a creator wants help getting a Godot project ready for KillaTamata Arcade submission.
The skill drives a running local Godot editor through the `killatamata_arcade_bridge` plugin, then uses the local submission client for creator API calls.

Start with inspection first, ask only for missing creator-authored metadata, and keep all project mutations narrow and explicit.

## Quick Start

1. Confirm the Godot plugin is enabled and the bridge server is running.
2. Inspect the project before making changes.
3. Fill only the missing arcade metadata.
4. Ensure the arcade web export preset.
5. Validate before building.
6. Build the release ZIP only after validation passes.
7. Submit only when the user explicitly asks to submit.

Use the helper script for repeatable bridge calls:

```bash
python3 scripts/send_bridge_command.py ping
python3 scripts/send_bridge_command.py project_state
python3 scripts/send_bridge_command.py get_arcade_project_config
python3 scripts/send_bridge_command.py validate_arcade_project
python3 scripts/send_bridge_command.py build_arcade_release
```

Use the submission client only after a valid ZIP exists:

```bash
python3 scripts/submission_client.py auth-state --base-url https://creator.example.com
python3 scripts/submission_client.py list-games --base-url https://creator.example.com
python3 scripts/submission_client.py publish-new \
  --base-url https://creator.example.com \
  --bundle /abs/path/game.zip \
  --cover-image /abs/path/cover.png
```

The ZIP's embedded `arcade.release.json` is the release metadata source of truth.
If you pass `--manifest-file`, it must exactly match the embedded manifest.
If you omit `--metadata-file` on `publish-new`, the client derives the new game record fields from the embedded manifest.

## Bridge Contract Snapshot

<!-- BEGIN GENERATED BRIDGE SNAPSHOT -->
- Transport: `127.0.0.1:47891` over newline-delimited JSON.
- Core commands: `ping`, `list_commands`, `get_recent_logs`.
- Editor commands: `editor_state`, `open_scene`, `save_scene`.
- Project commands: `project_state`, `get_arcade_project_config`, `upsert_arcade_project_config`, `generate_arcade_manifest_preview`.
- Export commands: `list_export_presets`, `ensure_arcade_web_export_preset`.
- Validation commands: `validate_arcade_web_export_preset`, `validate_arcade_project`.
- Build commands: `build_arcade_release`, `reveal_arcade_build`.
- Full argument and result details are generated in `references/bridge_protocol.md`.
<!-- END GENERATED BRIDGE SNAPSHOT -->

## Workflow Modes

### Configure

1. Call `project_state`.
2. Call `get_arcade_project_config`.
3. Ask only for missing creator-facing metadata.
4. Write the merged config with `upsert_arcade_project_config`.
5. Call `ensure_arcade_web_export_preset`.

### Validate

1. Call `validate_arcade_project`.
2. Present blocking issues, warnings, inferred values, and readiness.
3. Do not mutate the project unless the user asked for fixes.

### Build

1. Call `validate_arcade_project`.
2. If validation passes, call `build_arcade_release`.
3. Report the staging directory, ZIP path, manifest path, staged cover image path, and output inventory.

### Submit

1. Ensure a valid built ZIP already exists.
2. Resolve auth state with `submission_client.py auth-state`.
3. Determine whether this is a new game or an existing game update.
4. Create or resolve the game record.
5. Read release metadata from `arcade.release.json` inside the ZIP and only use an explicit manifest file as a strict match check.
6. Upload the bundle and optional replacement cover image.
7. Submit the release and report the resulting IDs and state.

## Command Rules

- Prefer `project_state`, `get_arcade_project_config`, and `validate_arcade_project` before asking questions.
- Prefer `upsert_arcade_project_config` over direct file edits.
- Prefer `ensure_arcade_web_export_preset` over hand-editing `export_presets.cfg`.
- Never submit if `validate_arcade_project` reports blocking issues.
- Treat C# detection and threaded web exports as V1 blockers.
- Treat `arcade.release.json` inside the ZIP as authoritative for release metadata. Rebuild the bundle to change version, descriptions, controls, display, tags, pricing, or cover path.
- Treat missing or unreadable cover images as blocking because the plugin is expected to stage the manifest cover asset into the exported bundle.

## Submission Rules

- Submission auth is intentionally abstracted behind the Python client.
- Prefer environment-driven auth when available.
- If no reusable auth is available, require explicit user-provided temporary headers instead of baking assumptions into the workflow.
- Prefer the built ZIP as the manifest source. An explicit `--manifest-file` is only for verification and must match the embedded manifest exactly.
- When publishing an existing game, default resolution to the embedded `gameSlug` unless the user explicitly selects another game ID or slug.
- Preserve idempotency when retrying uploads or submit calls.

## References

- Submission requirements: `references/arcade_submission.md`
- Bridge protocol: `references/bridge_protocol.md`
- Bridge helper: `scripts/send_bridge_command.py`
- Submission client: `scripts/submission_client.py`
