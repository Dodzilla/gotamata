# KillaTamata Arcade Bridge (Godot 4.6)

This addon exposes a narrow localhost bridge for KillaTamata Arcade publishing workflows.
It is intentionally limited to project inspection, arcade config management, web export preset management, validation, and build artifact generation.
The build path stages the configured cover image into the exported bundle so the ZIP can be submitted as a self-contained arcade artifact.

## Bridge Transport

- Host: `127.0.0.1`
- Port: `47891`
- Framing: one JSON object per line (`\n` terminated)

Request shape:

```json
{"id":"req-1","token":"optional","command":"ping","args":{}}
```

Response shape:

```json
{"ok":true,"id":"req-1","command":"ping","result":{"message":"pong"}}
```

<!-- BEGIN GENERATED BRIDGE COMMANDS -->
## Commands

### Core
- `ping` (`args`: none)
- `list_commands` (`args`: none)
- `get_recent_logs` (`args`: limit optional)

### Editor
- `editor_state` (`args`: none)
- `open_scene` (`args`: path)
- `save_scene` (`args`: path optional)

### Project
- `project_state` (`args`: none)
- `get_arcade_project_config` (`args`: none)
- `upsert_arcade_project_config` (`args`: patch)
- `generate_arcade_manifest_preview` (`args`: none)

### Export
- `list_export_presets` (`args`: none)
- `ensure_arcade_web_export_preset` (`args`: none)

### Validation
- `validate_arcade_web_export_preset` (`args`: none)
- `validate_arcade_project` (`args`: none)

### Build
- `build_arcade_release` (`args`: none)
- `reveal_arcade_build` (`args`: none)
<!-- END GENERATED BRIDGE COMMANDS -->

## Safety

- The server listens on localhost only by default.
- Auth token support is optional but available.
- There is no generic method-call escape hatch.
- The addon does not perform remote KillaTamata HTTP submission.
