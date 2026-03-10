# gotamata

Repository bootstrap for:

- a Godot 4.6 asset pipeline plugin for workflow templates, runs, artifacts, and published revisions
- a localhost command bridge so agents can inspect and drive the same editor/plugin state
- an agent skill that knows how to communicate with that bridge

## Layout

- `godot-plugin/`
  - Godot 4.6 project root
  - plugin at `godot-plugin/addons/gotamata_agent_bridge`
  - workflow templates at `godot-plugin/workflows/templates`
  - persisted workflow runs at `godot-plugin/workflows/runs`
  - published revision manifests at `godot-plugin/assets/generated`
  - local scratch workspace at `godot-plugin/_ai_work` (gitignored)
- `agent-skill/godot-editor-agent-bridge/`
  - Codex skill for the localhost JSON/TCP bridge
  - includes `scripts/send_command.py` and protocol reference docs

## Godot Plugin Quick Start

1. Open `godot-plugin/` in Godot 4.6.
2. Confirm plugin is enabled: `Project > Project Settings > Plugins`.
3. Open the `GoTamata` main editor tab.
4. Create a workflow run from either seeded template:
   - `Image Asset`
   - `3D Model Asset`
5. Advance attempts with explicit decisions, select artifacts, and publish a revision manifest into `res://assets/generated/...`.
6. Use the `GoTamata Control` dock when you want localhost agent access:
   - verify bind address / port (defaults: `127.0.0.1:47891`)
   - set optional auth token
   - start/restart the server
7. Send a test command:

```bash
python3 agent-skill/godot-editor-agent-bridge/scripts/send_command.py ping
```

## Asset Pipeline Capabilities

- Reusable workflow templates with typed nodes and edges.
- Persisted workflow runs with step attempts, external job metadata/status, import recipes, artifacts, and logs.
- Template CRUD from both the Godot UI and the localhost bridge.
- Artifact registration, selection, publish-candidate tracking, and deletion from both surfaces.
- Canonical revision manifests written to `assets/generated/<asset_slug>/<version>/manifest/asset_revision.json`.
- A gitignored `res://_ai_work` scratch area for intermediate artifacts.
- Agent bridge commands for template CRUD, run management, job tracking, import recipe updates, artifact management, and publish.
- Agent skill guidance for using the bridge as the system of record while executing external generation with other skills such as KillaTamata.

## Agent Skill Quick Start

- Skill definition: `agent-skill/godot-editor-agent-bridge/SKILL.md`
- Command protocol reference: `agent-skill/godot-editor-agent-bridge/references/protocol.md`
- Skill metadata: `agent-skill/godot-editor-agent-bridge/agents/openai.yaml`

## Iteration Loop

- Update the plugin implementation in `godot-plugin/addons/gotamata_agent_bridge/`.
- When the bridge contract changes, edit `godot-plugin/addons/gotamata_agent_bridge/bridge_contract.json`.
- Run `make sync-bridge` to regenerate the addon command summary and the skill protocol reference.
- Run `make test` locally to sync then verify drift-free output.
- CI runs `make check-bridge` on every push and pull request so generated bridge docs cannot silently drift from the plugin contract.
